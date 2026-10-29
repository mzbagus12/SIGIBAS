import 'package:flutter/material.dart';

/// Ringkasan agregat terkini; tidak menerima identitas atau riwayat individu.
class GovernmentSummary extends StatefulWidget {
  final Map<String, dynamic> aggregate;
  const GovernmentSummary({super.key, required this.aggregate});

  @override
  State<GovernmentSummary> createState() => _GovernmentSummaryState();
}

class _GovernmentSummaryState extends State<GovernmentSummary> {
  String selected = 'weightAge';
  bool ascending = true;
  int? sortColumn;
  static const names = {
    'weightAge': 'BB/U',
    'heightAge': 'PB/U atau TB/U',
    'weightHeight': 'BB/PB atau BB/TB',
  };
  static const descriptions = {
    'weightAge': 'Berat badan menurut umur',
    'heightAge': 'Panjang/tinggi badan menurut umur',
    'weightHeight': 'Berat badan menurut panjang/tinggi',
  };

  @override
  Widget build(BuildContext context) {
    final entries = widget.aggregate.entries.toList();
    if (sortColumn != null) {
      entries.sort((a, b) {
        final comparison = sortColumn == 0
            ? (names[a.key] ?? a.key).compareTo(names[b.key] ?? b.key)
            : (a.value['denominator'] as int).compareTo(
                b.value['denominator'] as int,
              );
        final tie = comparison == 0 ? a.key.compareTo(b.key) : comparison;
        return ascending ? tie : -tie;
      });
    }
    final selectedData = widget.aggregate[selected] as Map?;
    final categories = selectedData?['categories'] as Map? ?? const {};
    final denominator = selectedData?['denominator'] ?? 0;
    void sort(int column) => setState(() {
      ascending = sortColumn == column ? !ascending : true;
      sortColumn = column;
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Unit: observasi pengukuran disetujui efektif, bukan anak unik. Pilih indikator untuk melihat rincian. Geser tabel ke samping jika perlu.',
            style: TextStyle(color: Color(0xFF577169), fontSize: 13),
          ),
        ),
        Card(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                sortColumnIndex: sortColumn,
                sortAscending: ascending,
                columnSpacing: 24,
                headingRowColor: WidgetStatePropertyAll(Color(0xFFE8F3ED)),
                columns: [
                  DataColumn(
                    label: const Text('Indikator'),
                    onSort: (column, _) => sort(column),
                  ),
                  DataColumn(
                    label: const Text('Jumlah data'),
                    numeric: true,
                    onSort: (column, _) => sort(column),
                  ),
                  const DataColumn(label: Text('Rincian')),
                ],
                rows: [
                  for (final entry in entries)
                    DataRow(
                      key: ValueKey('row-${entry.key}'),
                      selected: selected == entry.key,
                      cells: [
                        DataCell(Text(names[entry.key] ?? entry.key)),
                        DataCell(Text('${entry.value['denominator']}')),
                        DataCell(
                          TextButton(
                            key: ValueKey('indicator-${entry.key}'),
                            onPressed: () =>
                                setState(() => selected = entry.key),
                            child: Text(
                              selected == entry.key ? 'Dipilih' : 'Lihat',
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          descriptions[selected] ?? selected,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Color(0xFF153E37),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Jumlah data yang dihitung: $denominator',
          style: const TextStyle(color: Color(0xFF577169)),
        ),
        if (categories.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text('Belum ada hasil yang dapat dihitung.'),
          )
        else
          Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: const WidgetStatePropertyAll(
                  Color(0xFFE8F3ED),
                ),
                columns: const [
                  DataColumn(label: Text('Kategori')),
                  DataColumn(label: Text('Jumlah'), numeric: true),
                ],
                rows: [
                  for (final entry in categories.entries)
                    DataRow(
                      cells: [
                        DataCell(Text('${entry.key}')),
                        DataCell(Text('${entry.value}')),
                      ],
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
