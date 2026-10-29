import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigibas_rasp/mvp/nutrition_panel.dart';
import 'package:sigibas_rasp/mvp/kms.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Decode the real asset outside each widget test's fake async clock.
  setUpAll(() async {
    await GrowthCurves.load();
  });
  testWidgets('empty approved history, recall calculation and narrow layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NutritionGrowthPanel(
              child: const {
                'id': 'demo',
                'name': 'Anak Sintetis',
                'birth': '2025-10-29',
                'sex': 'female',
              },
              history: const [],
              today: '2026-10-29',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Belum ada hasil disetujui.'), findsOneWidget);
    expect(
      find.text('Belum ada pengukuran disetujui yang layak diplot.'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField).at(0), '675');
    await tester.enterText(find.byType(TextField).at(1), '10');
    await tester.tap(find.text('Hitung persentase AKG'));
    await tester.pump();
    expect(
      find.textContaining('Energi 50.0% AKG; protein 50.0% AKG.'),
      findsOneWidget,
    );
      expect(find.textContaining('Zat besi (Fe) 7 mg • vitamin A 400 RE • vitamin D 15 µg'), findsOneWidget);
      expect(find.textContaining('Fe 0.0% AKG'), findsNothing);
      await tester.ensureVisible(find.text('Asupan mikronutrien (opsional)'));
      await tester.tap(find.text('Asupan mikronutrien (opsional)'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(2), '3,5');
      await tester.enterText(find.byType(TextField).at(3), '200');
      await tester.enterText(find.byType(TextField).at(4), '7.5');
      await Scrollable.ensureVisible(tester.element(find.text('Hitung persentase AKG')), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hitung persentase AKG'));
      await tester.pump();
      expect(find.textContaining('Fe 50.0% AKG. Vitamin A 50.0% AKG. Vitamin D 50.0% AKG.'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(2), '-1');
      await Scrollable.ensureVisible(tester.element(find.text('Hitung persentase AKG')), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hitung persentase AKG'));
      await tester.pump();
      expect(find.textContaining('isian mikronutrien opsional juga harus valid'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('stale results and oedema do not show a PMT numeric target', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NutritionGrowthPanel(
              child: const {
                'id': 'demo',
                'name': 'Anak Sintetis',
                'birth': '2025-01-01',
                'sex': 'male',
              },
              today: '2026-10-29',
              history: const [
                {
                  'status': 'approved',
                  'input': {
                    'date': '2026-01-01',
                    'weight': 8.0,
                    'oedema': 'yes',
                  },
                  'results': {
                    'weightAge': {'status': 'valid', 'rawZ': -2.5},
                  },
                },
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Perbarui pengukuran:'), findsOneWidget);
    expect(
      find.textContaining('Perlu pemeriksaan tenaga kesehatan segera'),
      findsOneWidget,
    );
    expect(find.textContaining('Acuan PMT tambahan per hari:'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
