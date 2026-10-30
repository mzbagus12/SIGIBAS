import 'package:flutter/material.dart';

import 'repository.dart';
import 'ui_form_field.dart';
import 'government_summary.dart';
import 'government_history.dart';
import 'care_panel.dart';
import 'report.dart';
import 'report_save.dart';
import 'government_dashboard.dart';

import 'package:printing/printing.dart';

class MvpWorkspace extends StatefulWidget {
  final MvpRepository repo;
  final String role;
  final VoidCallback onLogout;
  final String initialPage;
  const MvpWorkspace({
    super.key,
    required this.repo,
    required this.role,
    required this.onLogout,
    this.initialPage = 'home',
  });
  @override
  State<MvpWorkspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<MvpWorkspace> {
  final _navigator = GlobalKey<NavigatorState>();
  final _changes = ValueNotifier<int>(0);
  void updateView(VoidCallback change) {
    setState(change);
    _changes.value++;
  }

  void openPage(String page) => _navigator.currentState!.pushNamed(page);
  static const titles = {
    'home': 'SI-GIBAS',
    'profiles': 'Profil dan kontrol',
    'register': 'Tambah anak',
    'measurement': 'Pengukuran',
    'history': 'Riwayat pengukuran',
    'detail': 'Rincian pengukuran',
    'summary': 'Ringkasan data',
    'aggregate-history': 'Riwayat agregat',
    'dashboard': 'Dashboard wilayah',
  };
  @override
  Widget build(BuildContext context) => NavigatorPopHandler<void>(
    onPopWithResult: (_) => _navigator.currentState!.pop(),
    child: Navigator(
      key: _navigator,
      initialRoute: widget.initialPage,
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (context) => ListenableBuilder(
          listenable: _changes,
          builder: (context, _) => settings.name == 'home'
              ? homePage(context)
              : buildPage(context, settings.name!),
        ),
      ),
    ),
  );
  Widget homePage(BuildContext context) {
    final menus = role == 'Pemerintah'
        ? [
            (
              'summary',
              'Ringkasan data disetujui',
              Icons.insights_outlined,
              'Tabel hasil dan ekspor laporan',
            ),
            (
              'aggregate-history',
              'Riwayat agregat',
              Icons.history,
              'Perubahan setelah persetujuan',
            ),
            (
              'dashboard',
              'Dashboard wilayah',
              Icons.bar_chart,
              'Grafik, filter dan prioritas wilayah',
            ),
          ]
        : [
            (
              'profiles',
              'Profil dan kontrol',
              Icons.people_outline,
              'Profil, pertumbuhan dan jadwal',
            ),
            if (role == 'Kader') ...[
              (
                'register',
                'Tambah anak',
                Icons.person_add_outlined,
                'Daftarkan profil anak',
              ),
              (
                'measurement',
                'Pengukuran',
                Icons.monitor_weight_outlined,
                'Catat hasil penimbangan',
              ),
            ],
            (
              'history',
              role == 'Kader' ? 'Riwayat pengukuran' : 'Pemeriksaan data',
              Icons.fact_check_outlined,
              'Buka rincian dan tindak lanjuti',
            ),
          ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('SI-GIBAS'),
        actions: [
          IconButton(
            onPressed: widget.onLogout,
            tooltip: 'Keluar',
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        role == 'BadanGizi' ? 'Badan Gizi' : role,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Pilih kegiatan untuk memulai. Data tersimpan pada perangkat ini.',
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Ruang kerja',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                for (final menu in menus)
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      key: Key('open-${menu.$1}'),
                      contentPadding: const EdgeInsets.all(16),
                      leading: Icon(menu.$3),
                      title: Text(menu.$2),
                      subtitle: Text(menu.$4),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => openPage(menu.$1),
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Data latihan • Hasil bukan diagnosis atau terapi.',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String sex = 'male', position = 'standing', oedema = 'no';
  String get role => widget.role;
  String? child, previous;
  String? selectedRevision;
  bool historyNewestFirst = true;
  String message = '';
  final fields = {
    for (final k in [
      'name',
      'birth',
      'date',
      'weight',
      'cm',
      'muac',
      'head',
      'note',
    ])
      k: TextEditingController(),
  };
  int sequence = 0;
  String op() => '${DateTime.now().microsecondsSinceEpoch}-${sequence++}';
  String indicator(String key) => switch (key) {
    'weightAge' => 'Berat badan menurut umur (BB/U)',
    'heightAge' => 'Panjang/tinggi badan menurut umur (PB/U atau TB/U)',
    'weightHeight' => 'Berat badan menurut panjang/tinggi (BB/PB atau BB/TB)',
    _ => key,
  };
  String statusLabel(String status) => switch (status) {
    'draft' => 'Draf',
    'pending' => 'Menunggu pemeriksaan',
    'approved' => 'Disetujui',
    'rejected' => 'Ditolak',
    _ => status,
  };
  String optionLabel(String value) => switch (value) {
    'male' => 'Laki-laki',
    'female' => 'Perempuan',
    'standing' => 'Berdiri',
    'recumbent' => 'Berbaring',
    'no' => 'Tidak',
    'yes' => 'Ya',
    'unknown' => 'Tidak diketahui',
    _ => value,
  };
  Widget detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(label, style: const TextStyle(color: Color(0xFF577169))),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 5,
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
  Widget sectionTitle(String title, String subtitle, IconData icon) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 20),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFDCF1E9),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: const Color(0xFF096B5D), size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF153E37),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: Color(0xFF577169),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  @override
  void dispose() {
    _changes.dispose();
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> act(Future<dynamic> Function() work, {String? success}) async {
    try {
      final result = await work();
      if (mounted) {
        updateView(
          () => message = result is ReportSaved
              ? result.message
              : success ?? 'Tersimpan pada perangkat ini',
        );
      }
    } catch (e) {
      if (mounted) {
        updateView(
          () => message = switch (e) {
            StateError() => e.message.toString(),
            FormatException() =>
              'Masukan tidak valid. Periksa tanggal dan angka yang dimasukkan.',
            _ => 'Terjadi kesalahan: $e',
          },
        );
      }
    }
  }

  Widget field(String key, String label) => FormFieldBlock(
    label: label,
    child: TextField(
      key: Key(key),
      controller: fields[key],
      keyboardType: ['weight', 'cm', 'muac', 'head'].contains(key)
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        hintText: ['birth', 'date'].contains(key) ? 'YYYY-MM-DD' : null,
        border: const OutlineInputBorder(),
      ),
    ),
  );
  Widget select(
    String label,
    String value,
    List<String> items,
    ValueChanged<String> update,
  ) => FormFieldBlock(
    label: label,
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(),
      items: items
          .map((v) => DropdownMenuItem(value: v, child: Text(optionLabel(v))))
          .toList(),
      onChanged: (v) => updateView(() => update(v!)),
    ),
  );
  Widget buildPage(BuildContext context, String page) {
    final state = widget.repo.state;
    final children = Map.fromEntries(
      (state['children'] as Map).entries.where(
        (e) => e.value['archived'] != true,
      ),
    );
    if (child != null && !children.containsKey(child)) child = null;
    final revisions = state['revisions'] as Map;
    child ??= children.keys.firstOrNull as String?;
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[page] ?? 'SI-GIBAS'),
        leading: page == widget.initialPage
            ? null
            : IconButton(
                icon: const BackButtonIcon(),
                tooltip: 'Kembali',
                onPressed: () => Navigator.pop(context),
              ),
        actions: [
          IconButton(
            onPressed: widget.onLogout,
            tooltip: 'Keluar',
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
              children: [
                if (message.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(message, key: const Key('message')),
                  ),
                if (role == 'Pemerintah') ...[
                  if (page == 'summary') ...[
                    sectionTitle(
                      'Ringkasan data disetujui',
                      'Pantau data yang sudah melalui pemeriksaan.',
                      Icons.insights_rounded,
                    ),
                    const Text(
                      'Hanya pengukuran valid yang disetujui dihitung.',
                    ),
                    GovernmentSummary(aggregate: widget.repo.aggregate()),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Ekspor PDF'),
                          onPressed: () => act(() async {
                            await Printing.sharePdf(
                              bytes: await buildAggregatePdf(
                                widget.repo.aggregate(),
                              ),
                              filename:
                                  'sigibas-agregat-${DateTime.now().microsecondsSinceEpoch}.pdf',
                            );
                          }, success: 'Dialog ekspor PDF dibuka.'),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.table_view_outlined),
                          label: const Text('Ekspor Excel'),
                          onPressed: () => act(() async {
                            final path = await saveExcelReport(
                              buildAggregateExcel(widget.repo.aggregate()),
                            );
                            return ReportSaved('Excel: $path');
                          }),
                        ),
                      ],
                    ),
                  ],
                  if (page == 'aggregate-history') ...[
                    sectionTitle(
                      'Riwayat agregat',
                      'Pantau perubahan setelah setiap persetujuan.',
                      Icons.history_rounded,
                    ),
                    GovernmentHistory(history: widget.repo.aggregateHistory()),
                  ],
                  if (page == 'dashboard')
                    GovernmentDashboard(
                      data: buildGovernmentDashboard(widget.repo.state),
                    ),
                ] else ...[
                  if (page == 'profiles')
                    CarePanel(
                      repo: widget.repo,
                      role: role,
                      onChanged: () => updateView(() {}),
                    ),
                  if (role == 'Kader') ...[
                    if (page == 'register') ...[
                      sectionTitle(
                        'Registrasi anak sintetis',
                        'Isi data anak.',
                        Icons.person_add_alt_1_rounded,
                      ),
                      field('name', 'Nama sintetis'),
                      field('birth', 'Tanggal lahir YYYY-MM-DD'),
                      select('Jenis kelamin', sex, [
                        'male',
                        'female',
                      ], (v) => sex = v),
                      FilledButton(
                        onPressed: () => act(() async {
                          final id = await widget.repo.register(
                            op(),
                            fields['name']!.text,
                            fields['birth']!.text,
                            sex,
                          );
                          child = id;
                        }),
                        child: const Text('Daftar anak'),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => openPage('measurement'),
                        child: const Text('Lanjut ke pengukuran'),
                      ),
                    ],
                    if (page == 'measurement' && children.isEmpty)
                      const Text('Tambahkan profil anak terlebih dahulu.'),
                    if (page == 'measurement' && children.isNotEmpty) ...[
                      FormFieldBlock(
                        label: 'Anak',
                        child: DropdownButtonFormField<String>(
                          key: ValueKey(child),
                          isExpanded: true,
                          initialValue: child,
                          decoration: const InputDecoration(),
                          items: children.entries
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e.key as String,
                                  child: Text('${e.value['name']}'),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => updateView(() {
                            child = v;
                            previous = null;
                          }),
                        ),
                      ),
                      Text(
                        previous == null ? 'Pengukuran baru' : 'Mode koreksi; pengukuran sebelumnya tetap tersimpan',
                      ),
                      field('date', 'Tanggal ukur YYYY-MM-DD'),
                      field('weight', 'Berat kg'),
                      field('cm', 'Panjang/tinggi cm'),
                      field('muac', 'Lingkar lengan atas (LiLA) cm — opsional'),
                      field('head', 'Lingkar kepala (LK) cm — opsional'),
                      select('Posisi', position, [
                        'standing',
                        'recumbent',
                      ], (v) => position = v),
                      select('Oedema', oedema, [
                        'no',
                        'yes',
                        'unknown',
                      ], (v) => oedema = v),
                      FilledButton(
                        onPressed: () => act(() async {
                          double? numeric(String k) {
                            final t = fields[k]!.text.trim();
                            if (t.isEmpty) return null;
                            final n = double.parse(t);
                            if (!n.isFinite) {
                              throw const FormatException('Angka harus finite');
                            }
                            return n;
                          }

                          await widget.repo.save(op(), child!, {
                            'date': fields['date']!.text,
                            'weight': numeric('weight'),
                            'cm': numeric('cm'),
                            'muac': numeric('muac'),
                            'head': numeric('head'),
                            'position': position,
                            'oedema': oedema,
                          }, previous: previous);
                          previous = null;
                        }),
                        child: const Text('Simpan draft'),
                      ),
                    ],
                  ],
                  if (role == 'BadanGizi' && page == 'detail') ...[
                    sectionTitle(
                      'Pemeriksaan data',
                      'Tinjau hasil dan berikan keputusan.',
                      Icons.fact_check_outlined,
                    ),
                    const Text('Catatan wajib untuk penolakan.'),
                    field('note', 'Catatan review / wajib jika tolak'),
                  ],
                  if (page == 'history') ...[
                    sectionTitle(
                      'Riwayat pengukuran',
                      'Pilih hasil untuk ditindaklanjuti.',
                      Icons.history_rounded,
                    ),
                    if (revisions.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Belum ada riwayat pengukuran.'),
                      )
                    else ...[
                      const Text('Pilih pengukuran untuk melihat rincian.'),
                      TextButton.icon(
                        onPressed: () => updateView(
                          () => historyNewestFirst = !historyNewestFirst,
                        ),
                        icon: const Icon(Icons.swap_vert_rounded),
                        label: Text(
                          historyNewestFirst
                              ? 'Terbaru dahulu'
                              : 'Terlama dahulu',
                        ),
                      ),
                      Card(
                        margin: const EdgeInsets.symmetric(vertical: 16),
                        clipBehavior: Clip.antiAlias,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            key: const Key('revision-table'),
                            headingRowColor: const WidgetStatePropertyAll(
                              Color(0xFFE8F3ED),
                            ),
                            columnSpacing: 24,
                            columns: const [
                              DataColumn(label: Text('Anak')),
                              DataColumn(label: Text('Tanggal ukur')),
                              DataColumn(label: Text('Status')),
                              DataColumn(label: Text('Rincian')),
                            ],
                            rows: [
                              for (final r
                                  in historyNewestFirst
                                      ? revisions.values.toList().reversed
                                      : revisions.values)
                                DataRow(
                                  key: ValueKey('revision-row-${r['id']}'),
                                  selected: selectedRevision == r['id'],
                                  cells: [
                                    DataCell(
                                      Text(
                                        '${state['children'][r['child']]['name']}',
                                      ),
                                    ),
                                    DataCell(
                                      Text('${r['input']['date'] ?? '-'}'),
                                    ),
                                    DataCell(Text(statusLabel(r['status']))),
                                    DataCell(
                                      TextButton(
                                        key: ValueKey(
                                          'revision-select-${r['id']}',
                                        ),
                                        onPressed: () {
                                          updateView(
                                            () => selectedRevision = r['id'],
                                          );
                                          openPage('detail');
                                        },
                                        child: Text(
                                          selectedRevision == r['id']
                                              ? 'Dipilih'
                                              : 'Lihat',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                  if (page == 'detail')
                    for (final r in revisions.values.where(
                      (r) => r['id'] == selectedRevision,
                    ))
                      Card(
                        margin: const EdgeInsets.symmetric(vertical: 16),
                        clipBehavior: Clip.antiAlias,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${state['children'][r['child']]['name']} — ${statusLabel(r['status'])}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              detailRow(
                                'Tanggal ukur',
                                '${r['input']['date'] ?? '-'}',
                              ),
                              detailRow(
                                'Berat badan',
                                r['input']['weight'] == null
                                    ? '-'
                                    : "${r['input']['weight']} kg",
                              ),
                              detailRow(
                                'Panjang / tinggi',
                                r['input']['cm'] == null
                                    ? '-'
                                    : "${r['input']['cm']} cm",
                              ),
                              detailRow(
                                'Posisi pengukuran',
                                optionLabel(
                                  '${r['input']['position'] ?? 'unknown'}',
                                ),
                              ),
                              detailRow(
                                'Oedema',
                                optionLabel(
                                  '${r['input']['oedema'] ?? 'unknown'}',
                                ),
                              ),
                              if ((r['note'] as String).isNotEmpty)
                                Text('Catatan: ${r['note']}'),
                              Text(
                                (state['audit'] as List).any(
                                      (event) =>
                                          event['type'] == 'superseded' &&
                                          event['revision'] == r['id'],
                                    )
                                    ? 'Digantikan oleh revisi yang disetujui'
                                    : revisions.values.any(
                                        (v) => v['previous'] == r['id'],
                                      )
                                    ? 'Riwayat revisi; koreksi belum menggantikan hasil yang disetujui'
                                    : 'Revisi terkini',
                              ),
                              const Divider(height: 28),
                              const Text(
                                'Hasil pengukuran',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              for (final score
                                  in (r['results'] as Map).entries) ...[
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(
                                    indicator(score.key),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF153E37),
                                    ),
                                  ),
                                ),
                                detailRow(
                                  'Kategori',
                                  '${score.value['category'] ?? 'Belum tersedia'}',
                                ),
                                detailRow(
                                  'Z-score',
                                  '${score.value['roundedZ'] ?? '-'}',
                                ),
                                if (score.value['officialFlag'] == true ||
                                    score.value['rawReviewFlag'] == true)
                                  detailRow('Tindak lanjut', 'Perlu ditinjau'),
                                if (score.value['category'] == null)
                                  detailRow(
                                    'Keterangan',
                                    '${score.value['reason']}',
                                  ),
                              ],
                              const SizedBox(height: 12),
                              if (role == 'Kader' &&
                                  !revisions.values.any(
                                    (v) => v['previous'] == r['id'],
                                  ))
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    if (r['status'] == 'draft')
                                      FilledButton(
                                        onPressed: () => act(
                                          () =>
                                              widget.repo.submit(op(), r['id']),
                                        ),
                                        child: const Text('Ajukan'),
                                      ),
                                    if ([
                                      'draft',
                                      'rejected',
                                      'approved',
                                    ].contains(r['status']))
                                      OutlinedButton(
                                        onPressed: () {
                                          updateView(() {
                                            previous = r['id'];
                                            child = r['child'];
                                            for (final k in [
                                              'date',
                                              'weight',
                                              'cm',
                                              'muac',
                                              'head',
                                            ]) {
                                              fields[k]!.text =
                                                  '${r['input'][k] ?? ''}';
                                            }
                                            position =
                                                r['input']['position'] ??
                                                'standing';
                                            oedema =
                                                r['input']['oedema'] ??
                                                'unknown';
                                            message = 'Form koreksi siap; simpan menghasilkan revisi baru';
                                          });
                                          openPage('measurement');
                                        },
                                        child: const Text('Koreksi'),
                                      ),
                                  ],
                                ),
                              if (role == 'BadanGizi' &&
                                  r['status'] == 'pending' &&
                                  !revisions.values.any(
                                    (v) => v['previous'] == r['id'],
                                  ))
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    FilledButton(
                                      onPressed: () => act(
                                        () => widget.repo.review(
                                          op(),
                                          r['id'],
                                          true,
                                          fields['note']!.text,
                                        ),
                                      ),
                                      child: const Text('Setujui'),
                                    ),
                                    OutlinedButton(
                                      onPressed: () => act(
                                        () => widget.repo.review(
                                          op(),
                                          r['id'],
                                          false,
                                          fields['note']!.text,
                                        ),
                                      ),
                                      child: const Text('Tolak'),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
