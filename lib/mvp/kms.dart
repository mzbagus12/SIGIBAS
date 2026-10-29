import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../engine/engine.dart';
import 'kms_trend.dart';

class GrowthCurves {
  final Map<String, Map<int, List<double>>> _weight;
  GrowthCurves._(this._weight);
  factory GrowthCurves.fromJson(String tables, String manifest) {
    // Reuse the engine's pinned manifest and SHA validation before reading LMS.
    GrowthEngine.fromJson(tables, manifest);
    final decoded = jsonDecode(tables) as Map;
    final values = {
      'male': <int, List<double>>{},
      'female': <int, List<double>>{},
    };
    for (final row in decoded['wei'] as List) {
      values[row[0] == 1 ? 'male' : 'female']![(row[1] as num).toInt()] = [
        for (final n in row.skip(2)) (n as num).toDouble(),
      ];
    }
    return GrowthCurves._(values);
  }
  static Future<GrowthCurves>? _cached;
  static GrowthCurves? _loaded;
  static Future<GrowthCurves> load() =>
      _loaded != null ? SynchronousFuture(_loaded!) : _cached ??= _load();
  static Future<GrowthCurves> _load() async => _loaded = GrowthCurves.fromJson(
    await rootBundle.loadString('assets/engine/tables.json'),
    await rootBundle.loadString('assets/engine/manifest.json'),
  );
  double? weightAt(String sex, int day, int z) {
    if (z < -3 || z > 3) return null;
    final lms = _weight[sex]?[day];
    if (lms == null) return null;
    final l = lms[0], m = lms[1], s = lms[2];
    return l == 0 ? m * math.exp(s * z) : m * math.pow(1 + l * s * z, 1 / l);
  }
}

class GrowthPoint {
  final int days;
  final String date;
  final double kg;
  const GrowthPoint(this.days, this.date, this.kg);
  static List<GrowthPoint> approved(
    Map child,
    List<Map<String, dynamic>> rows,
  ) {
    final points = <GrowthPoint>[];
    try {
      final birth = CivilDate.parse(child['birth'] as String);
      for (final row in rows) {
        if (row['status'] != 'approved') continue;
        try {
          final input = row['input'] as Map;
          final date = input['date'] as String;
          final days = CivilDate.parse(date).daysSince(birth);
          final kg = (input['weight'] as num).toDouble();
          if (days < 0 || days > 1826 || !kg.isFinite || kg <= 0) continue;
          // Values flagged by the existing engine are retained in review history,
          // not drawn as reliable growth points.
          final result = (row['results'] as Map?)?['weightAge'] as Map?;
          if (result != null && !['valid'].contains(result['status'])) continue;
          if (input['oedema'] == 'yes') continue;
          points.add(GrowthPoint(days, date, kg));
        } catch (_) {
          /* Malformed legacy rows are not plotted. */
        }
      }
    } catch (_) {
      return points;
    }
    points.sort((a, b) => a.days.compareTo(b.days));
    return points;
  }
}

class KmsGrowthPanel extends StatefulWidget {
  final Map<String, dynamic> child;
  final List<Map<String, dynamic>> history;
  const KmsGrowthPanel({super.key, required this.child, required this.history});
  @override
  State<KmsGrowthPanel> createState() => _KmsGrowthPanelState();
}

class _KmsGrowthPanelState extends State<KmsGrowthPanel> {
  late final Future<GrowthCurves> curves = GrowthCurves.load();
  @override
  Widget build(BuildContext context) {
    final points = GrowthPoint.approved(widget.child, widget.history);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Kurva pertumbuhan BB/U',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const Text(
          'Kurva WHO BB/U sesuai jenis kelamin. Perbandingan bulanan memakai KBM Buku KIA 2024.',
        ),
        if (!['male', 'female'].contains(widget.child['sex']))
          const Text('Jenis kelamin belum valid untuk kurva.'),
        if (['male', 'female'].contains(widget.child['sex']))
          FutureBuilder<GrowthCurves>(
            future: curves,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text(
                  'Acuan kurva tidak dapat diverifikasi. Grafik tidak ditampilkan.',
                );
              }
              if (!snapshot.hasData) return const LinearProgressIndicator();
              return Semantics(
                label: 'Grafik berat menurut umur. Data rinci tersedia pada tabel setelah grafik.',
                child: SizedBox(
                  height: 290,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: GrowthCurvePainter(
                      snapshot.data!,
                      widget.child['sex'],
                      points,
                    ),
                  ),
                ),
              );
            },
          ),
        const Text(
          'Sumbu X: umur (hari). Sumbu Y: berat (kg). Hitam: pengukuran disetujui; hijau: median; merah: ±3 SD; jingga: ±2 SD; abu-abu: ±1 SD.',
        ),
        if (points.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Belum ada pengukuran disetujui yang layak diplot.'),
          ),
        if (points.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Tanggal')),
                DataColumn(label: Text('Umur (hari)')),
                DataColumn(label: Text('BB (kg)')),
              ],
              rows: [
                for (final p in points)
                  DataRow(
                    cells: [
                      DataCell(Text(p.date)),
                      DataCell(Text('${p.days}')),
                      DataCell(Text(p.kg.toStringAsFixed(2))),
                    ],
                  ),
              ],
            ),
          ),
        if (points.isNotEmpty && widget.child['birth'] is String)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Tanggal')),
                DataColumn(label: Text('Kenaikan (g)')),
                DataColumn(label: Text('KBM (g)')),
                DataColumn(label: Text('Hasil bulanan')),
              ],
              rows: [
                for (final row in MonthlyGrowth.assess(
                  widget.child['birth'],
                  widget.child['sex'] ?? '',
                  [
                    for (final point in points)
                      {'date': point.date, 'kg': point.kg},
                  ],
                ))
                  DataRow(
                    cells: [
                      DataCell(Text(row.date)),
                      DataCell(Text(row.gainGrams?.toString() ?? '—')),
                      DataCell(Text(row.minimumGrams?.toString() ?? '—')),
                      DataCell(Text(row.status)),
                    ],
                  ),
              ],
            ),
          ),
        const Text(
          'Perbandingan KBM memakai dua penimbangan pada bulan berurutan. Data ganda atau bulan terlewat perlu pemeriksaan petugas. Hasil T perlu tindak lanjut tenaga kesehatan. Penilaian arah kurva tetap dilakukan petugas; KBM membantu bila arah kurva meragukan.',
        ),
        const Text(
          'Sumber: WHO Child Growth Standards, tabel LMS BB/U lokal terverifikasi. Versi engine 0.1.0; provenance dan lisensi: assets/engine/manifest.json dan NOTICE.md.',
        ),
      ],
    );
  }
}

class GrowthCurvePainter extends CustomPainter {
  final GrowthCurves curves;
  final String sex;
  final List<GrowthPoint> points;
  GrowthCurvePainter(this.curves, this.sex, this.points);
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 100) return;
    final area = Rect.fromLTRB(35, 15, size.width - 35, size.height - 30);
    final maxKg = math.max(
      35.0,
      points.fold<double>(0, (p, e) => math.max(p, e.kg)) + 2,
    );
    Offset at(int days, double kg) => Offset(
      area.left + days / 1826 * area.width,
      area.bottom - kg / maxKg * area.height,
    );
    void label(String text, Offset pos, [Color color = Colors.black87]) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(fontSize: 10, color: color),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, pos);
    }

    for (var kg = 0; kg <= maxKg; kg += 5) {
      final y = at(0, kg.toDouble()).dy;
      canvas.drawLine(
        Offset(area.left, y),
        Offset(area.right, y),
        Paint()..color = Colors.black12,
      );
      label('$kg', Offset(4, y - 5));
    }
    for (final days in [0, 365, 730, 1095, 1460, 1826]) {
      final x = at(days, 0).dx;
      canvas.drawLine(
        Offset(x, area.top),
        Offset(x, area.bottom),
        Paint()..color = Colors.black12,
      );
      label('$days', Offset(x - 10, area.bottom + 6));
    }
    for (var z = -3; z <= 3; z++) {
      final path = Path();
      var start = true;
      final color = z == 0
          ? Colors.green.shade700
          : z.abs() == 3
          ? Colors.red.shade700
          : z.abs() == 2
          ? Colors.orange.shade800
          : Colors.blueGrey;
      for (var day = 0; day <= 1826; day += 1) {
        final kg = curves.weightAt(sex, day, z);
        if (kg == null) continue;
        final point = at(day, kg);
        if (start) {
          path.moveTo(point.dx, point.dy);
          start = false;
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = z == 0 ? 2 : 1,
      );
      label(
        '${z > 0 ? '+' : ''}$z',
        Offset(area.right + 3, at(1826, curves.weightAt(sex, 1826, z)!).dy - 5),
        color,
      );
    }
    // Separate dots, avoiding a false continuity claim across missed visits.
    for (final point in points) {
      canvas.drawCircle(
        at(point.days, point.kg),
        4,
        Paint()..color = Colors.black,
      );
    }
  }

  @override
  bool shouldRepaint(covariant GrowthCurvePainter oldDelegate) => true;
}
