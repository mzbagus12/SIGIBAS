import 'dart:convert';

import 'package:flutter/material.dart';

import 'repository.dart';
import 'photo_picker.dart';
import 'visit_notification.dart';
import 'nutrition_panel.dart';

class CarePanel extends StatefulWidget {
  final MvpRepository repo;
  final String role;
  final VoidCallback onChanged;
  const CarePanel({
    super.key,
    required this.repo,
    required this.role,
    required this.onChanged,
  });
  @override
  State<CarePanel> createState() => _CarePanelState();
}

class _CarePanelState extends State<CarePanel>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  String? selected;
  String message = '';
  final fields = {
    for (final k in ['name', 'nik', 'guardian', 'village', 'date', 'note'])
      k: TextEditingController(),
  };
  String breastfeeding = 'unknown', immunization = 'unknown';
  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  void select(String id, Map c) {
    selected = id;
    for (final key in ['name', 'nik', 'guardian', 'village']) {
      fields[key]!.text = '${c[key] ?? ''}';
    }
    breastfeeding = c['exclusiveBreastfeeding'] ?? 'unknown';
    immunization = c['immunization'] ?? 'unknown';
    final visit = (widget.repo.state['visits'] as Map?)?[id];
    fields['date']!.text = visit?['date'] ?? '';
    fields['note']!.text = visit?['note'] ?? '';
  }

  Future<void> run(Future<dynamic> Function() task) async {
    try {
      final result = await task();
      if (!mounted) return;
      setState(
        () => message = result is String && result.startsWith('Jadwal')
            ? result
            : 'Tersimpan',
      );
      widget.onChanged();
    } on FormatException catch (e) {
      if (mounted) setState(() => message = e.message);
    } on StateError catch (e) {
      if (mounted) setState(() => message = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => message = 'Tidak dapat menyimpan. Coba lagi.');
      }
    }
  }

  String op() => 'care-${DateTime.now().microsecondsSinceEpoch}';
  Widget field(String key, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextField(
      controller: fields[key],
      decoration: InputDecoration(labelText: label),
    ),
  );
  Widget choice(String label, String value, ValueChanged<String> change) =>
      DropdownButtonFormField<String>(
        key: ValueKey('$label-$selected-$value'),
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: const [
          DropdownMenuItem(value: 'yes', child: Text('Ya')),
          DropdownMenuItem(value: 'no', child: Text('Tidak')),
          DropdownMenuItem(value: 'unknown', child: Text('Belum diketahui')),
        ],
        onChanged: (v) {
          if (v != null) setState(() => change(v));
        },
      );
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = widget.repo.state;
    final children = (state['children'] as Map).entries
        .where((e) => e.value['archived'] != true)
        .toList();
    final archived = (state['children'] as Map).entries
        .where((e) => e.value['archived'] == true)
        .toList();
    if (selected != null && !children.any((e) => e.key == selected)) {
      selected = null;
    }
    final rows = selected == null
        ? <Map<String, dynamic>>[]
        : widget.repo.growthHistory(selected!);
    final visits = state['visits'] as Map? ?? {};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Profil, pertumbuhan dan kontrol',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (widget.role == 'Kader' && archived.isNotEmpty)
              ExpansionTile(
                title: const Text('Profil diarsipkan'),
                children: [
                  for (final child in archived)
                    ListTile(
                      title: Text('${child.value['name']}'),
                      trailing: TextButton(
                        onPressed: () => run(() async {
                          final id = child.key as String;
                          await widget.repo.restoreChild(op(), id);
                          final date = visits[id]?['date'] as String?;
                          if (date == null ||
                              date.compareTo(widget.repo.today) < 0) {
                            return 'Jadwal tidak berubah; profil dipulihkan.';
                          }
                          try {
                            return await scheduleVisitNotification(id, date);
                          } catch (_) {
                            return 'Jadwal tersimpan; pengingat gagal dijadwalkan setelah pemulihan.';
                          }
                        }),
                        child: const Text('Pulihkan'),
                      ),
                    ),
                ],
              ),
            for (final c in children)
              if (visits[c.key] != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_note),
                  title: Text('${c.value['name']} — ${visits[c.key]['date']}'),
                  subtitle: Text('${visits[c.key]['note']}'),
                  trailing: Text(
                    (visits[c.key]['date'] as String).compareTo(
                              widget.repo.today,
                            ) <
                            0
                        ? 'Terlewat'
                        : 'Terjadwal',
                  ),
                ),
            DropdownButtonFormField<String>(
              key: ValueKey('care-$selected'),
              initialValue: selected,
              decoration: const InputDecoration(
                labelText: 'Pilih profil untuk rincian',
              ),
              items: [
                for (final c in children)
                  DropdownMenuItem(
                    value: c.key as String,
                    child: Text('${c.value['name']}'),
                  ),
              ],
              onChanged: (id) {
                if (id != null) {
                  setState(() => select(id, (state['children'] as Map)[id]));
                }
              },
            ),
            if (selected != null) ...[
              if (state['children'][selected]['photo'] is String)
                Image.memory(
                  base64Decode(state['children'][selected]['photo']),
                  width: 128,
                  height: 128,
                  fit: BoxFit.contain,
                  semanticLabel: 'Foto profil dummy',
                  errorBuilder: (_, error, stack) =>
                      const Text('Foto tidak dapat ditampilkan'),
                ),
              if (widget.role == 'Kader')
                Wrap(
                  children: [
                    TextButton(
                      onPressed: () => run(() async {
                        final id = selected!;
                        final bytes = await pickProfilePhoto();
                        if (bytes != null) {
                          await widget.repo.updatePhoto(op(), id, bytes);
                        }
                      }),
                      child: const Text('Pilih foto dummy'),
                    ),
                    if (state['children'][selected]['photo'] != null)
                      TextButton(
                        onPressed: () => run(
                          () => widget.repo.updatePhoto(op(), selected!, null),
                        ),
                        child: const Text('Hapus foto'),
                      ),
                  ],
                ),
              if (widget.role == 'Kader')
                ExpansionTile(
                  title: const Text('Ubah profil'),
                  children: [
                    field('name', 'Nama sintetis'),
                    field('nik', 'NIK dummy 16 angka, awalan 000000'),
                    field('guardian', 'Nama wali sintetis'),
                    field('village', 'Kelurahan / wilayah sintetis'),
                    choice(
                      'ASI eksklusif',
                      breastfeeding,
                      (v) => breastfeeding = v,
                    ),
                    choice(
                      'Imunisasi lengkap',
                      immunization,
                      (v) => immunization = v,
                    ),
                    FilledButton(
                      onPressed: () => run(
                        () => widget.repo.updateProfile(op(), selected!, {
                          'name': fields['name']!.text,
                          'nik': fields['nik']!.text,
                          'guardian': fields['guardian']!.text,
                          'village': fields['village']!.text,
                          'exclusiveBreastfeeding': breastfeeding,
                          'immunization': immunization,
                        }),
                      ),
                      child: const Text('Simpan profil'),
                    ),
                    TextButton(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Arsipkan profil?'),
                            content: const Text(
                              'Profil keluar dari daftar aktif. Riwayat pengukuran tetap tersimpan.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Batal'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Arsipkan'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true && mounted) {
                          final childId = selected!;
                          await run(() async {
                            await widget.repo.archiveChild(op(), childId);
                            try {
                              await cancelVisitNotification(childId);
                              return 'Jadwal pengingat dibatalkan; profil diarsipkan.';
                            } catch (_) {
                              return 'Jadwal pengingat gagal dibatalkan; profil sudah diarsipkan.';
                            }
                          });
                        }
                      },
                      child: const Text('Arsipkan profil'),
                    ),
                  ],
                ),
              ExpansionTile(
                title: const Text('Jadwal kontrol'),
                children: [
                  field('date', 'Tanggal kontrol YYYY-MM-DD'),
                  field('note', 'Catatan kontrol'),
                  FilledButton(
                    onPressed: () => run(() async {
                      await widget.repo.scheduleVisit(
                        op(),
                        selected!,
                        fields['date']!.text,
                        fields['note']!.text,
                      );
                      try {
                        return await scheduleVisitNotification(
                          selected!,
                          fields['date']!.text,
                        );
                      } catch (_) {
                        return 'Jadwal disimpan; pengingat sistem gagal dijadwalkan.';
                      }
                    }),
                    child: const Text('Simpan jadwal'),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Riwayat pertumbuhan disetujui'),
              ),
              if (rows.isEmpty)
                const Text('Belum ada pengukuran disetujui.')
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Tanggal')),
                      DataColumn(label: Text('BB (kg)')),
                      DataColumn(label: Text('PB/TB (cm)')),
                      DataColumn(label: Text('LiLA (cm)')),
                      DataColumn(label: Text('LK (cm)')),
                    ],
                    rows: [
                      for (final r in rows)
                        DataRow(
                          cells: [
                            for (final k in [
                              'date',
                              'weight',
                              'cm',
                              'muac',
                              'head',
                            ])
                              DataCell(Text('${r['input'][k] ?? '—'}')),
                          ],
                        ),
                    ],
                  ),
                ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Jadwal terlihat saat aplikasi dibuka. Android dapat menjadwalkan pengingat dengan izin notifikasi.',
                ),
              ),
              NutritionGrowthPanel(
                key: ValueKey('nutrition-$selected'),
                child: Map<String, dynamic>.from(
                  (state['children'] as Map)[selected],
                ),
                history: rows,
                today: widget.repo.today,
              ),
            ],
            if (message.isNotEmpty) Text(message),
          ],
        ),
      ),
    );
  }
}
