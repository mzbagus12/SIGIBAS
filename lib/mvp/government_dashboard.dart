import 'dart:math' as math;

import 'package:flutter/material.dart';

const dashboardIndicators = {
  'weightAge': 'BB/U',
  'heightAge': 'PB/U atau TB/U',
  'weightHeight': 'BB/PB atau BB/TB',
};

Map<String, dynamic> _emptyAggregate() => {
  for (final key in dashboardIndicators.keys)
    key: {'denominator': 0, 'categories': <String, int>{}},
};

/// Privacy boundary: call inside repository/controller, never pass state to UI.
/// Counts effective approved measurement observations, not unique children.
/// Coordinates form a fictional local map and never locate an individual.
Map<String, dynamic> buildGovernmentDashboard(Map<String, dynamic> state) {
  final revisions = state['revisions'] as Map? ?? {};
  final children = state['children'] as Map? ?? {};
  final parents = revisions.values.map((r) => r['previous']).toSet();
  final effective = <String, Map>{};
  for (final leaf in revisions.values) {
    if (parents.contains(leaf['id'])) continue;
    dynamic revision = leaf;
    final visited = <String>{};
    while (revision is Map && revision['status'] != 'approved') {
      if (!visited.add('${revision['id']}')) {
        revision = null;
        break;
      }
      revision = revisions[revision['previous']];
    }
    if (revision is Map && revision['measurement'] is String) {
      effective[revision['measurement']] = revision;
    }
  }
  final cells = <String, Map<String, dynamic>>{};
  for (final revision in effective.values) {
    final date = DateTime.tryParse('${revision['input']?['date']}');
    if (date == null) continue;
    final month = '${date.year}-${date.month.toString().padLeft(2, '0')}';
    final rawVillage = children[revision['child']]?['village'];
    final village = rawVillage is String && rawVillage.trim().isNotEmpty
        ? rawVillage.trim()
        : 'Wilayah belum diisi';
    final cell = cells.putIfAbsent(
      '$month\u0000$village',
      () => {
        'month': month,
        'village': village,
        'aggregate': _emptyAggregate(),
      },
    );
    for (final key in dashboardIndicators.keys) {
      final score = revision['results']?[key];
      if (score is! Map ||
          score['status'] != 'valid' ||
          score['category'] is! String) {
        continue;
      }
      final bucket = cell['aggregate'][key];
      bucket['denominator']++;
      final categories = bucket['categories'] as Map;
      categories[score['category']] = (categories[score['category']] ?? 0) + 1;
    }
  }
  final villages =
      cells.values.map((c) => c['village'] as String).toSet().toList()..sort();
  return {
    'unit': 'observasi pengukuran disetujui efektif',
    'cells': cells.values.toList()
      ..sort(
        (a, b) => '${a['month']}${a['village']}'.compareTo(
          '${b['month']}${b['village']}',
        ),
      ),
    'areas': [
      for (var i = 0; i < villages.length; i++)
        {
          'village': villages[i],
          // Synthetic east/north coordinates in a fictional 10 km local extent.
          'x': 1.0 + (i % 4) * 2.3,
          'y': 1.0 + (i ~/ 4) * 2.3,
        },
    ],
  };
}

Map<String, dynamic> combineDashboardCells(Iterable<dynamic> cells) {
  final result = _emptyAggregate();
  for (final cell in cells) {
    for (final key in dashboardIndicators.keys) {
      final source = cell['aggregate'][key] as Map;
      final target = result[key];
      target['denominator'] += source['denominator'] as int;
      for (final entry in (source['categories'] as Map).entries) {
        target['categories'][entry.key] =
            (target['categories'][entry.key] ?? 0) + entry.value;
      }
    }
  }
  return result;
}

int dashboardStunting(Map aggregate) {
  final categories = aggregate['heightAge']['categories'] as Map;
  return (categories['pendek'] as int? ?? 0) +
      (categories['sangat pendek'] as int? ?? 0);
}

class GovernmentDashboard extends StatefulWidget {
  final Map<String, dynamic> data;
  const GovernmentDashboard({super.key, required this.data});
  @override
  State<GovernmentDashboard> createState() => _GovernmentDashboardState();
}

class _GovernmentDashboardState extends State<GovernmentDashboard> {
  String indicator = 'heightAge';
  String month = 'Semua';
  String village = 'Semua';
  bool rate = true;
  bool descending = true;
  static const colors = [
    Color(0xff167866),
    Color(0xffdf9b29),
    Color(0xffc95555),
    Color(0xff547fc1),
    Color(0xff9670b6),
    Color(0xff638b48),
  ];
  @override
  Widget build(BuildContext context) {
    final cells = widget.data['cells'] as List? ?? [];
    final months = cells.map((c) => c['month'] as String).toSet().toList()
      ..sort();
    final villages = cells.map((c) => c['village'] as String).toSet().toList()
      ..sort();
    if (!months.contains(month)) month = 'Semua';
    if (!villages.contains(village)) village = 'Semua';
    final filtered = cells.where(
      (c) =>
          (month == 'Semua' || c['month'] == month) &&
          (village == 'Semua' || c['village'] == village),
    );
    final aggregate = combineDashboardCells(filtered);
    final categories = aggregate[indicator]['categories'] as Map;
    final denominator = aggregate[indicator]['denominator'] as int;
    final byVillage = <String, Map>{
      for (final v in villages.where((v) => village == 'Semua' || village == v))
        v: combineDashboardCells(filtered.where((c) => c['village'] == v)),
    };
    double prevalence(Map a) {
      final n = a['heightAge']['denominator'] as int;
      return n == 0 ? 0 : 100 * dashboardStunting(a) / n;
    }

    final ranked = byVillage.entries.toList()
      ..sort((a, b) {
        final comparison = prevalence(a.value).compareTo(prevalence(b.value));
        return comparison == 0
            ? a.key.compareTo(b.key)
            : (descending ? -comparison : comparison);
      });
    Widget picker(
      String label,
      String value,
      List<String> values,
      ValueChanged<String> change,
    ) => SizedBox(
      width: 220,
      child: DropdownButtonFormField<String>(
        key: ValueKey('$label-$value'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: values
            .map(
              (v) => DropdownMenuItem(
                value: v,
                child: Text(v, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: (v) => setState(() => change(v!)),
      ),
    );
    Widget panel(String title, Widget child) => Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Dashboard wilayah',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text(
          'Data sintetis • Unit: observasi pengukuran disetujui efektif, bukan jumlah anak unik. Koreksi menggantikan observasi lama. Stunting = pendek + sangat pendek pada PB/TB menurut umur.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            picker('Bulan pengukuran', month, [
              'Semua',
              ...months,
            ], (v) => month = v),
            picker('Kelurahan', village, [
              'Semua',
              ...villages,
            ], (v) => village = v),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                initialValue: indicator,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Indikator pie/bar',
                ),
                items: dashboardIndicators.entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => indicator = v!),
              ),
            ),
          ],
        ),
        if (cells.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Belum ada observasi disetujui untuk dashboard.'),
          ),
        panel(
          'Tren stunting menurut bulan pengukuran',
          Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  rate ? 'Tampilkan persentase' : 'Tampilkan jumlah observasi',
                ),
                value: rate,
                onChanged: (v) => setState(() => rate = v),
              ),
              SizedBox(
                height: 180,
                width: double.infinity,
                child: CustomPaint(
                  painter: _TrendPainter(
                    [
                      for (final m in months)
                        (() {
                          final a = combineDashboardCells(
                            cells.where(
                              (c) =>
                                  c['month'] == m &&
                                  (village == 'Semua' ||
                                      c['village'] == village),
                            ),
                          );
                          return rate
                              ? prevalence(a)
                              : dashboardStunting(a).toDouble();
                        })(),
                    ],
                    months,
                    rate,
                  ),
                ),
              ),
              const Text(
                'Tren memakai semua bulan untuk kelurahan terpilih. Bulan tanpa penyebut ditandai 0; bukan bukti tidak ada stunting.',
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final m in months)
                    (() {
                      final a = combineDashboardCells(
                        cells.where(
                          (c) =>
                              c['month'] == m &&
                              (village == 'Semua' || c['village'] == village),
                        ),
                      );
                      final n = a['heightAge']['denominator'];
                      return ActionChip(
                        label: Text(
                          '$m: ${dashboardStunting(a)}/$n (${n == 0 ? 'belum dinilai' : '${prevalence(a).toStringAsFixed(1)}%'})',
                        ),
                        onPressed: () => setState(() => month = m),
                      );
                    })(),
                ],
              ),
            ],
          ),
        ),
        panel(
          'Distribusi ${dashboardIndicators[indicator]} • n = $denominator',
          Wrap(
            spacing: 24,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Semantics(
                label: 'Diagram pie distribusi kategori. Rincian angka tersedia di legenda.',
                child: SizedBox(
                  width: 150,
                  height: 150,
                  child: CustomPaint(
                    painter: _PiePainter(
                      categories.values
                          .map((v) => (v as num).toDouble())
                          .toList(),
                      colors,
                    ),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (denominator == 0) const Text('Tidak ada hasil valid.'),
                  for (var i = 0; i < categories.length; i++)
                    Text(
                      '● ${categories.keys.elementAt(i)}: ${categories.values.elementAt(i)} (${denominator == 0 ? '0.0' : (100 * (categories.values.elementAt(i) as int) / denominator).toStringAsFixed(1)}%)',
                      style: TextStyle(color: colors[i % colors.length]),
                    ),
                ],
              ),
            ],
          ),
        ),
        panel(
          'Bar observasi valid per kelurahan • ${dashboardIndicators[indicator]}',
          Column(
            children: [
              for (final e in byVillage.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${e.key}: ${e.value[indicator]['denominator']}'),
                      LinearProgressIndicator(
                        value: denominator == 0
                            ? 0
                            : (e.value[indicator]['denominator'] as int) /
                                  denominator,
                        minHeight: 12,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        panel(
          'Heatmap stunting • peta koordinat lokal sintetis',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Peta fiktif untuk demonstrasi; koordinat pusat wilayah sintetis (km timur/utara), bukan lokasi administratif atau anak. Warna menunjukkan persentase stunting, radius tetap. Ketuk titik untuk menyaring kelurahan.',
              ),
              SizedBox(
                height: 300,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final areas = (widget.data['areas'] as List? ?? [])
                        .where((a) => byVillage.containsKey(a['village']))
                        .toList();
                    final maxY = math.max(
                      8.0,
                      areas.fold<double>(
                            0,
                            (n, a) => math.max(n, (a['y'] as num).toDouble()),
                          ) +
                          1,
                    );
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(painter: _MapGrid()),
                        ),
                        const Positioned(
                          left: 8,
                          top: 4,
                          child: Text('↑ Utara (km)'),
                        ),
                        const Positioned(
                          right: 4,
                          bottom: 0,
                          child: Text('Timur (km) →'),
                        ),
                        for (final area in areas)
                          Positioned(
                            left:
                                ((area['x'] as num) /
                                        10 *
                                        (constraints.maxWidth - 72))
                                    .toDouble(),
                            bottom: ((area['y'] as num) / maxY * 235 + 25)
                                .toDouble(),
                            child: Tooltip(
                              message:
                                  byVillage[area['village']]!['heightAge']['denominator'] ==
                                      0
                                  ? '${area['village']}: belum ada hasil valid'
                                  : '${area['village']}: ${prevalence(byVillage[area['village']]!).toStringAsFixed(1)}%',
                              child: InkWell(
                                onTap: () =>
                                    setState(() => village = area['village']),
                                child: Container(
                                  width: 68,
                                  height: 48,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        byVillage[area['village']]!['heightAge']['denominator'] ==
                                                0
                                            ? Colors.grey
                                            : Color.lerp(
                                                const Color(0xffb6dec9),
                                                const Color(0xffb52b38),
                                                prevalence(
                                                      byVillage[area['village']]!,
                                                    ) /
                                                    100,
                                              )!,
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                  child: Text(
                                    '${villages.indexOf(area['village']) + 1}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              const Text(
                'Legenda intensitas: hijau 0% → merah 100%; tanpa hasil valid: belum dapat dinilai. Nomor titik merujuk daftar kelurahan di bawah.',
              ),
              for (final v in byVillage.keys)
                Text('${villages.indexOf(v) + 1}. $v'),
            ],
          ),
        ),
        panel(
          'Prioritas intervensi wilayah',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Urutan berdasarkan persentase stunting observasi, bukan diagnosis atau alokasi otomatis. Tinjau penyebut kecil dan cakupan sebelum keputusan PMT/audit.',
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  sortColumnIndex: 3,
                  sortAscending: !descending,
                  columns: [
                    const DataColumn(label: Text('Kelurahan')),
                    const DataColumn(label: Text('Stunting'), numeric: true),
                    const DataColumn(
                      label: Text('Valid PB/TB/U'),
                      numeric: true,
                    ),
                    DataColumn(
                      label: const Text('%'),
                      numeric: true,
                      onSort: (_, _) =>
                          setState(() => descending = !descending),
                    ),
                    const DataColumn(label: Text('Tindak lanjut')),
                  ],
                  rows: [
                    for (final e in ranked)
                      DataRow(
                        cells: [
                          DataCell(Text(e.key)),
                          DataCell(Text('${dashboardStunting(e.value)}')),
                          DataCell(
                            Text('${e.value['heightAge']['denominator']}'),
                          ),
                          DataCell(
                            Text(
                              e.value['heightAge']['denominator'] == 0
                                  ? '—'
                                  : prevalence(e.value).toStringAsFixed(1),
                            ),
                          ),
                          DataCell(
                            Text(
                              e.value['heightAge']['denominator'] == 0
                                  ? 'Lengkapi cakupan'
                                  : dashboardStunting(e.value) > 0
                                  ? 'Tinjau PMT dan audit wilayah'
                                  : 'Lanjutkan pemantauan',
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PiePainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  _PiePainter(this.values, this.colors);
  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (a, b) => a + b);
    if (total == 0) {
      canvas.drawCircle(
        size.center(Offset.zero),
        size.shortestSide / 2,
        Paint()..color = const Color(0xffe4e8e5),
      );
      return;
    }
    var angle = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * math.pi * 2;
      canvas.drawArc(
        Offset.zero & size,
        angle,
        sweep,
        true,
        Paint()..color = colors[i % colors.length],
      );
      angle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PiePainter oldDelegate) => true;
}

class _TrendPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  final bool rate;
  _TrendPainter(this.values, this.labels, this.rate);
  void label(Canvas c, String text, Offset at) {
    final p = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Colors.black87, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    p.paint(c, at);
  }

  @override
  void paint(Canvas c, Size s) {
    final max = rate ? 100.0 : math.max(1.0, values.fold<double>(0, math.max));
    final paint = Paint()
      ..color = const Color(0xff167866)
      ..strokeWidth = 3;
    c.drawLine(const Offset(32, 8), Offset(32, s.height - 28), paint);
    c.drawLine(
      Offset(32, s.height - 28),
      Offset(s.width, s.height - 28),
      paint,
    );
    label(c, '${max.round()}${rate ? '%' : ''}', Offset.zero);
    label(c, '0', Offset(10, s.height - 30));
    Offset? previous;
    for (var i = 0; i < values.length; i++) {
      final point = Offset(
        42 + (s.width - 90) * i / math.max(1, values.length - 1),
        s.height - 28 - values[i] / max * (s.height - 48),
      );
      if (previous != null) {
        c.drawLine(previous, point, paint);
      }
      c.drawCircle(point, 4, paint);
      if (i == 0 || i == values.length - 1 || values.length <= 4) {
        label(c, labels[i], Offset(point.dx - 14, s.height - 19));
      }
      previous = point;
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) => true;
}

class _MapGrid extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xfff0f5ef),
    );
    final p = Paint()
      ..color = const Color(0xffccdbd0)
      ..strokeWidth = 1;
    for (var i = 1; i < 10; i++) {
      canvas.drawLine(
        Offset(size.width * i / 10, 0),
        Offset(size.width * i / 10, size.height),
        p,
      );
      canvas.drawLine(
        Offset(0, size.height * i / 10),
        Offset(size.width, size.height * i / 10),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MapGrid oldDelegate) => false;
}
