import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigibas_rasp/mvp/report.dart';

void main() {
  final data = <String, dynamic>{
    'heightAge': {
      'denominator': 2,
      'categories': {'normal': 1, 'stunted': 1},
    },
  };
  test('Excel berisi agregat yang dapat dibaca ulang tanpa data individu', () {
    final bytes = buildAggregateExcel(data);
    final book = Excel.decodeBytes(bytes);
    final rows = book.tables['Agregat']!.rows;
    expect(rows.length, 3);
    expect(rows[1][2]!.value.toString(), '1');
    expect(rows[1][3]!.value.toString(), '2');
  });
  test('PDF menghasilkan dokumen valid dan menerima keadaan kosong', () async {
    final bytes = await buildAggregatePdf(data);
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    expect(await buildAggregatePdf({}), isNotEmpty);
  });
  test(
    'zero denominators are explicit and malformed aggregates fail closed',
    () {
      final zero = {
        'heightAge': {'denominator': 0, 'categories': <String, int>{}},
      };
      expect(aggregateRows(zero).single, [
        'PB/U atau TB/U',
        'Belum ada hasil valid',
        '0',
        '0',
        '0.0',
      ]);
      for (final invalid in [
        {
          'denominator': 2,
          'categories': {'normal': 1},
        },
        {
          'denominator': -1,
          'categories': {'normal': -1},
        },
        {
          'denominator': 1,
          'categories': {'normal': '1'},
        },
      ]) {
        expect(
          () => aggregateRows({'heightAge': invalid}),
          throwsFormatException,
        );
      }
    },
  );
  test('spreadsheet percentages stay numeric and category text cannot become formula', () {
    final book = Excel.decodeBytes(
      buildAggregateExcel({
        'heightAge': {
          'denominator': 3,
          'categories': {'=1+1': 1, 'normal': 2},
        },
      }),
    );
    final rows = book['Agregat'].rows;
    expect(rows[1][1]!.value, isA<TextCellValue>());
    expect(rows[1][1]!.value.toString(), '=1+1');
    expect(rows[1][2]!.value, isA<IntCellValue>());
    expect(rows[1][4]!.value, isA<DoubleCellValue>());
    expect(rows[1][4]!.value.toString(), '33.3');
    expect(book.tables.keys, contains('Keterangan'));
  });
  test(
    'write synthetic export fixtures for independent parser and visual QA',
    () async {
      final fixture = <String, dynamic>{
        'weightAge': {
          'denominator': 7,
          'categories': {
            'berat badan normal': 4,
            'berat badan kurang': 2,
            'berat badan sangat kurang': 1,
          },
        },
        'heightAge': {
          'denominator': 7,
          'categories': {'normal': 4, 'pendek': 2, 'sangat pendek': 1},
        },
        'weightHeight': {
          'denominator': 6,
          'categories': {
            'gizi baik': 3,
            'gizi kurang': 1,
            'gizi buruk': 1,
            'risiko gizi lebih': 1,
          },
        },
      };
      final directory = Directory('docs/dashboard/export-qa')
        ..createSync(recursive: true);
      File('${directory.path}/synthetic-aggregate.pdf')
          .writeAsBytesSync(await buildAggregatePdf(fixture));
      File('${directory.path}/synthetic-aggregate.xlsx')
          .writeAsBytesSync(buildAggregateExcel(fixture));
      File('${directory.path}/synthetic-empty.pdf')
          .writeAsBytesSync(await buildAggregatePdf({}));
      expect(aggregateRows(fixture).length, 10);
    },
  );
}
