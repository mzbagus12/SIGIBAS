import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';

class ReportSaved {
  final String message;
  const ReportSaved(this.message);
}

List<List<String>> aggregateRows(Map<String, dynamic> aggregate) {
  final rows = <List<String>>[];
  const names = {
    'weightAge': 'BB/U',
    'heightAge': 'PB/U atau TB/U',
    'weightHeight': 'BB/PB atau BB/TB',
  };
  for (final key in names.keys) {
    final value = aggregate[key] as Map?;
    if (value == null) continue;
    final denominator = value['denominator'];
    final categories = value['categories'];
    if (denominator is! int ||
        denominator < 0 ||
        categories is! Map ||
        categories.entries.any(
          (e) => e.key is! String || e.value is! int || e.value < 0,
        ) ||
        categories.values.fold<int>(0, (n, v) => n + v as int) != denominator) {
      throw const FormatException(
        'Agregat laporan tidak konsisten; sinkronkan ulang.',
      );
    }
    final entries = categories.entries.toList()
      ..sort((a, b) => '${a.key}'.compareTo('${b.key}'));
    if (entries.isEmpty) {
      rows.add([names[key]!, 'Belum ada hasil valid', '0', '0', '0.0']);
    }
    for (final entry in entries) {
      final count = entry.value as int;
      rows.add([
        names[key]!,
        '${entry.key}',
        '$count',
        '$denominator',
        denominator == 0
            ? '0.0'
            : (count * 100 / denominator).toStringAsFixed(1),
      ]);
    }
  }
  return rows;
}

const reportHeaders = ['Indikator', 'Kategori', 'Jumlah', 'Penyebut', 'Persen'];
Uint8List buildAggregateExcel(Map<String, dynamic> aggregate) {
  final book = Excel.createExcel();
  final sheet = book['Agregat'];
  book.delete('Sheet1');
  sheet.appendRow(reportHeaders.map((s) => TextCellValue(s)).toList());
  for (final row in aggregateRows(aggregate)) {
    sheet.appendRow([
      TextCellValue(row[0]),
      TextCellValue(row[1]),
      IntCellValue(int.parse(row[2])),
      IntCellValue(int.parse(row[3])),
      DoubleCellValue(double.parse(row[4])),
    ]);
  }
  for (var column = 0; column < reportHeaders.length; column++) {
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 0))
        .cellStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#DCEFE6'),
    );
  }
  sheet.setColumnWidth(0, 23);
  sheet.setColumnWidth(1, 32);
  for (var column = 2; column < 5; column++) {
    sheet.setColumnWidth(column, 15);
  }
  final notes = book['Keterangan'];
  for (final text in [
    'SI-GIBAS - Data sintetis, bukan laporan resmi SSGI/e-PPGBM.',
    'Unit: observasi pengukuran disetujui efektif; bukan jumlah anak unik.',
    'Koreksi disetujui menggantikan observasi lama. Hanya kategori berstatus valid dihitung.',
    'Penyebut dan persen dihitung per indikator; tanpa hasil valid ditulis 0.',
    'Persen dibulatkan satu desimal; total bisa berbeda dari 100 karena pembulatan.',
    'Kolom angka tetap numerik. Tidak ada nama, NIK, ID anak, tanggal lahir atau koordinat individu.',
  ]) {
    notes.appendRow([TextCellValue(text)]);
  }
  notes.setColumnWidth(0, 110);
  return Uint8List.fromList(book.encode()!);
}

Future<Uint8List> buildAggregatePdf(Map<String, dynamic> aggregate) async {
  final doc = pw.Document();
  final rows = aggregateRows(aggregate);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Data sintetis | Halaman ${context.pageNumber} / ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ),
      build: (_) => [
        pw.Header(level: 0, child: pw.Text('SI-GIBAS - Laporan agregat')),
        pw.Text(
          'Data sintetis - bukan laporan resmi SSGI/e-PPGBM. Unit: observasi pengukuran disetujui efektif, bukan jumlah anak unik. Koreksi menggantikan observasi lama. Hanya hasil valid dihitung. Persentase memakai penyebut setiap indikator dan dibulatkan satu desimal.',
        ),
        pw.SizedBox(height: 16),
        if (rows.isEmpty)
          pw.Text('Belum ada data agregat.')
        else
          pw.TableHelper.fromTextArray(
            headers: reportHeaders,
            data: rows,
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 10,
            ),
            cellStyle: const pw.TextStyle(fontSize: 10),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xffdcefe6),
            ),
            cellPadding: const pw.EdgeInsets.all(7),
            columnWidths: {
              0: const pw.FlexColumnWidth(1.6),
              1: const pw.FlexColumnWidth(2.3),
              2: const pw.FlexColumnWidth(1),
              3: const pw.FlexColumnWidth(1.2),
              4: const pw.FlexColumnWidth(1),
            },
          ),
      ],
    ),
  );
  return doc.save();
}
