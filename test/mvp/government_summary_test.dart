import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigibas_rasp/mvp/government_summary.dart';

void main() {
  testWidgets('tabel agregat dapat memilih indikator dan mengurutkan jumlah', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = <String, dynamic>{
      'weightAge': {
        'denominator': 2,
        'categories': {'normal': 2},
      },
      'heightAge': {
        'denominator': 1,
        'categories': {'pendek': 1},
      },
      'weightHeight': {'denominator': 0, 'categories': <String, int>{}},
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GovernmentSummary(aggregate: data),
          ),
        ),
      ),
    );
    expect(find.byType(DataTable), findsNWidgets(2));
    expect(find.text('normal'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('indicator-heightAge')));
    await tester.pumpAndSettle();
    expect(find.text('pendek'), findsOneWidget);
    expect(find.text('normal'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('indicator-weightHeight')));
    await tester.pumpAndSettle();
    expect(find.text('Belum ada hasil yang dapat dihitung.'), findsOneWidget);
    await tester.tap(find.text('Jumlah data'));
    await tester.pumpAndSettle();
    final table = tester.widget<DataTable>(find.byType(DataTable).first);
    expect(table.sortColumnIndex, 1);
    expect(table.rows.first.key, const ValueKey('row-weightHeight'));
  });
}
