import 'dart:convert';

import 'package:flutter/material.dart';

import 'repository.dart';

class MvpWorkspace extends StatefulWidget {
  final MvpRepository repo;
  const MvpWorkspace({super.key, required this.repo});
  @override
  State<MvpWorkspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<MvpWorkspace> {
  String role = 'Kader', sex = 'male', position = 'standing', oedema = 'no';
  String? child, previous;
  String message = '';
  final fields = {
    for (final k in ['name', 'birth', 'date', 'weight', 'cm', 'note'])
      k: TextEditingController(),
  };
  int sequence = 0;
  String op() => '${DateTime.now().microsecondsSinceEpoch}-${sequence++}';
  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> act(Future<dynamic> Function() work) async {
    try {
      await work();
      if (mounted) {
        setState(() => message = 'Tersimpan lokal; bukan ACK server');
      }
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    }
  }

  Widget field(String key, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: TextField(
      key: Key(key),
      controller: fields[key],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );
  Widget select(
    String label,
    String value,
    List<String> items,
    ValueChanged<String> update,
  ) => DropdownButtonFormField<String>(
    key: ValueKey('$label-$value'),
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: items
        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
        .toList(),
    onChanged: (v) => setState(() => update(v!)),
  );
  @override
  Widget build(BuildContext context) {
    final state = widget.repo.state;
    final children = state['children'] as Map;
    final revisions = state['revisions'] as Map;
    child ??= children.keys.firstOrNull as String?;
    return Scaffold(
      appBar: AppBar(title: const Text('SI-GIBAS RASP')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'DATA SINTETIS / DEMO — Jangan masukkan data pribadi. Bukan diagnosis atau terapi. Server, sinkronisasi, PIN role, RASP dan pinning: simulasi, bukan keamanan produksi. Penyimpanan lokal tanpa enkripsi/backup; tanggal perangkat bukan waktu tepercaya.',
            ),
            Wrap(
              spacing: 8,
              children: ['Kader', 'BadanGizi', 'Pemerintah']
                  .map(
                    (r) => ChoiceChip(
                      label: Text(r),
                      selected: role == r,
                      onSelected: (_) => setState(() => role = r),
                    ),
                  )
                  .toList(),
            ),
            Text(message, key: const Key('message')),
            if (role == 'Pemerintah') ...[
              const Text(
                'Agregat approved — baca saja',
                style: TextStyle(fontSize: 22),
              ),
              const Text(
                'Hanya revisi terkini approved; denominator tiap indeks mengecualikan unavailable/flag. Pending dan rejected tidak dihitung.',
              ),
              for (final e in widget.repo.aggregate().entries)
                Text(
                  '${e.key}: denominator ${e.value['denominator']} | kategori ${jsonEncode(e.value['categories'])}',
                ),
            ] else ...[
              if (role == 'Kader') ...[
                const Text(
                  'Registrasi anak sintetis',
                  style: TextStyle(fontSize: 22),
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
                const Text('ID internal stabil; NIK null; tanpa foto.'),
                if (children.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    key: ValueKey(child),
                    initialValue: child,
                    decoration: const InputDecoration(labelText: 'Anak'),
                    items: children.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key as String,
                            child: Text('${e.value['name']} | ${e.key}'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() {
                      child = v;
                      previous = null;
                    }),
                  ),
                  Text(
                    previous == null
                        ? 'Pengukuran baru'
                        : 'Koreksi baru atas $previous; input lama tetap utuh',
                  ),
                  field('date', 'Tanggal ukur YYYY-MM-DD'),
                  field('weight', 'Berat kg'),
                  field('cm', 'Panjang/tinggi cm'),
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
                        'position': position,
                        'oedema': oedema,
                      }, previous: previous);
                      previous = null;
                    }),
                    child: const Text('Simpan draft'),
                  ),
                ],
              ],
              if (role == 'BadanGizi')
                field('note', 'Catatan review / wajib jika tolak'),
              const Text(
                'Riwayat immutable / review lokal',
                style: TextStyle(fontSize: 22),
              ),
              for (final r in revisions.values)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${r['id']} | ${r['status']} | ${children[r['child']]['name']}',
                        ),
                        Text(
                          'Input: ${jsonEncode(r['input'])} | catatan: ${r['note']}',
                        ),
                        Text(
                          (state['audit'] as List).any(
                                (event) =>
                                    event['type'] == 'superseded' &&
                                    event['revision'] == r['id'],
                              )
                              ? 'Superseded (audit append-only)'
                              : revisions.values.any(
                                  (v) => v['previous'] == r['id'],
                                )
                              ? 'Histori revisi; koreksi belum menggantikan approved'
                              : 'Revisi terkini',
                        ),
                        for (final score in (r['results'] as Map).entries)
                          Text(
                            '${score.key} | ${score.value['status']} | raw ${score.value['rawZ']} | rounded ${score.value['roundedZ']} | flag ${score.value['officialFlag']}/${score.value['rawReviewFlag']} | ${score.value['reason']} | kategori ${score.value['category'] ?? 'unavailable'}',
                          ),
                        Text('Provenance ${jsonEncode(r['provenance'])}'),
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
                                    () => widget.repo.submit(op(), r['id']),
                                  ),
                                  child: const Text('Ajukan'),
                                ),
                              if ([
                                'draft',
                                'rejected',
                                'approved',
                              ].contains(r['status']))
                                OutlinedButton(
                                  onPressed: () => setState(() {
                                    previous = r['id'];
                                    child = r['child'];
                                    for (final k in ['date', 'weight', 'cm']) {
                                      fields[k]!.text =
                                          '${r['input'][k] ?? ''}';
                                    }
                                    position =
                                        r['input']['position'] ?? 'standing';
                                    oedema = r['input']['oedema'] ?? 'unknown';
                                    message = 'Form koreksi siap; simpan menghasilkan revisi baru';
                                  }),
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
              Text('Audit append-only: ${jsonEncode(state['audit'])}'),
            ],
          ],
        ),
      ),
    );
  }
}
