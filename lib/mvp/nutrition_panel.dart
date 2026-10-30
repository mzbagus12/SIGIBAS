import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'nutrition.dart';
import 'ui_form_field.dart';
import 'kms.dart';

/// Pass effective approved revisions from repo.growthHistory(childId).
/// All recall and screening inputs are transient synthetic demo inputs.
class NutritionGrowthPanel extends StatefulWidget {
  final Map<String, dynamic> child;
  final List<Map<String, dynamic>> history;
  final String today;
  const NutritionGrowthPanel({
    super.key,
    required this.child,
    required this.history,
    required this.today,
  });
  @override
  State<NutritionGrowthPanel> createState() => _NutritionGrowthPanelState();
}

class _NutritionGrowthPanelState extends State<NutritionGrowthPanel> {
  final energy = TextEditingController(), protein = TextEditingController();
  final micronutrients = {
    'Zat besi (Fe), mg': TextEditingController(),
    'Vitamin A, RE': TextEditingController(),
    'Vitamin D, µg': TextEditingController(),
  };
  String allergy = 'unknown', danger = 'unknown';
  bool concern = false;
  String? calculation;
  @override
  void didUpdateWidget(covariant NutritionGrowthPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.child['id'] != widget.child['id'] ||
        oldWidget.child['birth'] != widget.child['birth'] ||
        oldWidget.child['name'] != widget.child['name']) {
      energy.clear();
      protein.clear();
      for (final field in micronutrients.values) {
        field.clear();
      }
      calculation = null;
      allergy = danger = 'unknown';
      concern = false;
    }
  }

  @override
  void dispose() {
    energy.dispose();
    protein.dispose();
    for (final field in micronutrients.values) {
      field.dispose();
    }
    super.dispose();
  }

  double? z(Map? revision, String index) {
    final score = (revision?['results'] as Map?)?[index] as Map?;
    if (score == null || score['status'] != 'valid') return null;
    final value = (score['rawZ'] as num?)?.toDouble();
    return value != null && value.isFinite ? value : null;
  }

  Widget screening(String label, String value, ValueChanged<String> change) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: DropdownButtonFormField<String>(
          key: ValueKey('$label-$value-${widget.child['id']}'),
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: const [
            DropdownMenuItem(value: 'unknown', child: Text('Belum dinilai')),
            DropdownMenuItem(value: 'yes', child: Text('Ya')),
            DropdownMenuItem(value: 'no', child: Text('Tidak')),
          ],
          onChanged: (v) {
            if (v != null) setState(() => change(v));
          },
        ),
      );
  @override
  Widget build(BuildContext context) {
    int? months;
    try {
      months = CivilDate.parse(widget.child['birth'])
          .completedMonthsAt(CivilDate.parse(widget.today));
    } catch (_) {
      /* Show missing age below. */
    }
    final akg = months == null ? null : AkgReference.forMonths(months);
    final approved =
        widget.history.where((r) => r['status'] == 'approved').toList()..sort(
          (a, b) =>
              '${a['input']?['date']}'.compareTo('${b['input']?['date']}'),
        );
    final latest = approved.isEmpty ? null : approved.last;
    final input = latest?['input'] as Map?;
    var recent = false;
    try {
      final age = CivilDate.parse(widget.today)
          .daysSince(CivilDate.parse(input?['date']));
      recent = age >= 0 && age <= 31;
    } catch (_) {
      /* Missing or malformed date cannot support PMT screening. */
    }
    final rawMuac = (input?['muac'] as num?)?.toDouble();
    final advice = PmtAdvice.assess(
      months: months ?? -1,
      wfaZ: recent ? z(latest, 'weightAge') : null,
      wfhZ: recent ? z(latest, 'weightHeight') : null,
      muac: recent ? rawMuac : null,
      oedema: input?['oedema'] == 'yes',
      redFlags: danger == 'yes',
      allergies: allergy == 'yes',
      growthConcern: concern && recent,
    );
    final cleared =
        allergy == 'no' && danger == 'no' && input?['oedema'] == 'no';
    final anthropometryReady = z(latest, 'weightHeight') != null;
    final range = cleared && recent && anthropometryReady ? advice.range : null;
    final stale = latest != null && !recent;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Gizi dan pertumbuhan — ${widget.child['name'] ?? 'Anak'}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text(
              'Simulasi data sintetis. AKG kelompok umur dan skrining ini bukan resep individual.',
            ),
            const SizedBox(height: 12),
            Text(
              'Acuan AKG harian',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              'Tanggal acuan: ${widget.today} • umur: ${months ?? 'belum valid'} bulan lengkap',
            ),
            if (akg == null)
              const Text('Acuan modul tersedia untuk umur 0–83 bulan.'),
            if (akg != null) ...[
              Text(
                'Kelompok ${akg.group}: ${akg.energy} kkal • protein ${akg.protein} g • lemak ${akg.fat} g • karbohidrat ${akg.carbohydrate} g • serat ${akg.fiber} g • air total ${akg.water} mL per hari.',
              ),
              Text(
                'Zat besi (Fe) ${akg.ironMg.toString().replaceAll(RegExp(r'\.0$'), '')} mg • vitamin A ${akg.vitaminARe} RE • vitamin D ${akg.vitaminDMcg} µg per hari.',
              ),
              ExpansionTile(
                title: const Text('Keterangan acuan'),
                children: [
                  const Text(
                    'RE = retinol equivalent (ekuivalen retinol). Ini acuan asupan, bukan dosis suplemen/kapsul vitamin atau obat.',
                  ),
                  const Text(
                    'Air total mencakup makanan/minuman, termasuk ASI; bukan anjuran memberi air putih tambahan kepada bayi. Nilai tabel tidak dikalikan berat badan aktual.',
                  ),
                ],
              ),
              FormFieldBlock(
                label: 'Asupan energi 24 jam sintetis (kkal)',
                child: TextField(
                  controller: energy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(),
                ),
              ),
              FormFieldBlock(
                label: 'Asupan protein 24 jam sintetis (g)',
                child: TextField(
                  controller: protein,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(),
                ),
              ),
              ExpansionTile(
                title: const Text('Asupan mikronutrien (opsional)'),
                children: [
                  for (final field in micronutrients.entries)
                    TextField(
                      controller: field.value,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Asupan 24 jam sintetis: ${field.key}',
                      ),
                    ),
                  const Text(
                    'Kosong berarti belum diketahui; tidak dianggap nol. Gunakan satuan yang sama dengan tabel AKG.',
                  ),
                ],
              ),
              FilledButton.tonal(
                onPressed: () {
                  final e = double.tryParse(energy.text.replaceAll(',', '.')),
                      p = double.tryParse(protein.text.replaceAll(',', '.'));
                  final microText = micronutrients.values
                      .map((v) => v.text.trim())
                      .toList();
                  final microValues = microText
                      .map((s) => double.tryParse(s.replaceAll(',', '.')))
                      .toList();
                  final invalidMicro = List.generate(
                    3,
                    (i) =>
                        microText[i].isNotEmpty &&
                        (microValues[i] == null ||
                            !microValues[i]!.isFinite ||
                            microValues[i]! < 0),
                  ).any((v) => v);
                  setState(() {
                    calculation =
                        e == null ||
                            p == null ||
                            !e.isFinite ||
                            !p.isFinite ||
                            e < 0 ||
                            p < 0 ||
                            invalidMicro
                        ? 'Isi energi dan protein dengan angka valid; isian mikronutrien opsional juga harus valid (nol diperbolehkan).'
                        : 'Energi ${akg.percentEnergy(e).toStringAsFixed(1)}% AKG; protein ${akg.percentProtein(p).toStringAsFixed(1)}% AKG. Perbandingan aritmetis satu hari, bukan diagnosis kecukupan individu.';
                    if (e != null &&
                        p != null &&
                        e.isFinite &&
                        p.isFinite &&
                        e >= 0 &&
                        p >= 0 &&
                        !invalidMicro) {
                      final percentages = [
                        akg.percentIron,
                        akg.percentVitaminA,
                        akg.percentVitaminD,
                      ];
                      final labels = ['Fe', 'Vitamin A', 'Vitamin D'];
                      for (var i = 0; i < 3; i++) {
                        if (microText[i].isNotEmpty) {
                          calculation =
                              '$calculation ${labels[i]} ${percentages[i](microValues[i]!).toStringAsFixed(1)}% AKG.';
                        }
                      }
                    }
                  });
                },
                child: const Text('Hitung persentase AKG'),
              ),
              if (calculation != null)
                Text(calculation!, key: const ValueKey('akg-result')),
            ],
            const Text(AkgReference.source),
            const Divider(height: 28),
            Text(
              'Skrining PMT lokal',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              latest == null
                  ? 'Belum ada hasil disetujui.'
                  : 'Pengukuran disetujui terbaru: ${input?['date']}',
            ),
            if (stale)
              const Text(
                'Perbarui pengukuran: modul membatasi skrining pada data ≤31 hari sebelum tanggal acuan.',
              ),
            screening('Riwayat alergi makanan', allergy, (v) => allergy = v),
            screening(
              'Tanda bahaya / penyakit penyerta',
              danger,
              (v) => danger = v,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Tenaga kesehatan menilai pertumbuhan tidak adekuat',
              ),
              value: concern,
              onChanged: (v) => setState(() => concern = v ?? false),
            ),
            Text(advice.message),
            if ((!cleared || !anthropometryReady) &&
                advice.kind == PmtKind.candidate)
              const Text(
                'Lengkapi hasil BB/PB atau BB/TB yang valid, penilaian alergi, tanda bahaya, dan oedema sebelum menampilkan rentang PMT.',
              ),
            if (range != null)
              Text(
                'Acuan PMT tambahan per hari: ${range.energyMin}–${range.energyMax} kkal; protein ${range.proteinMin}–${range.proteinMax} g. Tidak ditambahkan otomatis ke AKG sebagai target terapi.',
              ),
            ExpansionTile(
              title: const Text('Panduan PMT'),
              children: [
                const Text(
                  'Menu: pangan lokal beragam, utamakan protein hewani; tekstur sesuai umur dan lanjutkan ASI. PMT tidak mengganti makanan utama. Susun porsi bersama tenaga gizi; alergi memerlukan tata laksana khusus.',
                ),
                const Text(
                  'Pemantauan dan durasi ditentukan tenaga kesehatan. Bila tidak membaik dalam 14 hari, evaluasi/rujuk sesuai juknis. Tidak ada penyesuaian kalori terapi otomatis.',
                ),
              ],
            ),
            const Text(PmtAdvice.source),
            const Divider(height: 28),
            KmsGrowthPanel(child: widget.child, history: widget.history),
          ],
        ),
      ),
    );
  }
}
