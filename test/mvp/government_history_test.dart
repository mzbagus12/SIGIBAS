import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigibas_rasp/mvp/government_history.dart';

Map<String, dynamic> snapshot(int count) => {
  'weightAge': {
    'denominator': count,
    'categories': {'normal': count},
  },
  'heightAge': {
    'denominator': count,
    'categories': {'normal': count},
  },
  'weightHeight': {
    'denominator': count,
    'categories': {'gizi baik': count},
  },
};

void main() {
  testWidgets('riwayat agregat dapat dipilih tanpa identitas anak', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final history = [
      {'atDevice': '2026-10-28T10:00:00', 'aggregate': snapshot(1)},
      {'atDevice': '2026-10-29T11:00:00', 'aggregate': snapshot(2)},
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GovernmentHistory(history: history),
          ),
        ),
      ),
    );
    expect(find.text('2026-10-29 11:00'), findsOneWidget);
    expect(find.text('2026-10-28 10:00'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('history-0')));
    await tester.pumpAndSettle();
    expect(find.text('Jumlah data yang dihitung: 1'), findsOneWidget);
    expect(find.text('normal'), findsOneWidget);
  });
  testWidgets('riwayat kosong menjelaskan belum ada persetujuan', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: GovernmentHistory(history: [])),
      ),
    );
    expect(find.text('Belum ada riwayat persetujuan.'), findsOneWidget);
  });
}
