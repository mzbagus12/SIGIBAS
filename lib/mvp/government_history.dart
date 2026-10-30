import 'package:flutter/material.dart';

import 'government_summary.dart';

/// Hanya menampilkan snapshot agregat per persetujuan, tanpa identitas anak.
class GovernmentHistory extends StatefulWidget {
  final List<Map<String, dynamic>> history;
  const GovernmentHistory({super.key, required this.history});

  @override
  State<GovernmentHistory> createState() => _GovernmentHistoryState();
}

class _GovernmentHistoryState extends State<GovernmentHistory> {
  int? selected;
  bool newestFirst = true;

  String displayTime(dynamic value) {
    final date = value is String ? DateTime.tryParse(value) : null;
    if (date == null) return 'Waktu tidak tersedia';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final indexes = List<int>.generate(widget.history.length, (index) => index);
    if (newestFirst) {
      indexes.setAll(0, indexes.reversed.toList());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ringkasan setelah setiap persetujuan. Waktu mengikuti perangkat.',
          style: TextStyle(color: Color(0xFF577169), fontSize: 13),
        ),
        const SizedBox(height: 8),
        if (indexes.isEmpty)
          const Text('Belum ada riwayat persetujuan.')
        else ...[
          TextButton.icon(
            onPressed: () => setState(() => newestFirst = !newestFirst),
            icon: const Icon(Icons.swap_vert_rounded),
            label: Text(newestFirst ? 'Terbaru dahulu' : 'Terlama dahulu'),
          ),
          const Text(
            'Geser untuk kolom lainnya.',
            style: TextStyle(color: Color(0xFF577169), fontSize: 13),
          ),
          Card(
            margin: const EdgeInsets.only(top: 16, bottom: 24),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: const WidgetStatePropertyAll(
                  Color(0xFFE8F3ED),
                ),
                columnSpacing: 22,
                columns: const [
                  DataColumn(label: Text('Waktu perangkat')),
                  DataColumn(label: Text('BB/U'), numeric: true),
                  DataColumn(label: Text('PB/U atau TB/U'), numeric: true),
                  DataColumn(label: Text('BB/PB atau BB/TB'), numeric: true),
                  DataColumn(label: Text('Rincian')),
                ],
                rows: [
                  for (final index in indexes)
                    DataRow(
                      selected: selected == index,
                      cells: [
                        DataCell(
                          Text(displayTime(widget.history[index]['atDevice'])),
                        ),
                        for (final key in [
                          'weightAge',
                          'heightAge',
                          'weightHeight',
                        ])
                          DataCell(
                            Text(
                              '${widget.history[index]['aggregate'][key]['denominator']}',
                            ),
                          ),
                        DataCell(
                          TextButton(
                            key: ValueKey('history-$index'),
                            onPressed: () => setState(() => selected = index),
                            child: Text(
                              selected == index ? 'Dipilih' : 'Lihat',
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          if (selected != null && selected! < widget.history.length) ...[
            const SizedBox(height: 14),
            Text(
              'Rincian saat ${displayTime(widget.history[selected!]['atDevice'])}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            GovernmentSummary(
              aggregate: Map<String, dynamic>.from(
                widget.history[selected!]['aggregate'] as Map,
              ),
            ),
          ],
        ],
      ],
    );
  }
}
