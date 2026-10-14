import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sigibas_rasp/engine/engine.dart';
import 'package:sigibas_rasp/mvp/repository.dart';
import 'package:sigibas_rasp/mvp/ui.dart';

void main() {
  testWidgets(
    'forms validation, real three outputs, review note, read-only aggregate',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final engine = GrowthEngine.fromJson(
        File('assets/engine/tables.json').readAsStringSync(),
        File('assets/engine/manifest.json').readAsStringSync(),
      );
      final repo = (await tester.runAsync(
        () async => MvpRepository.open(
          await databaseFactoryMemory.openDatabase('ui'),
          engine,
          today: '2026-10-14',
        ),
      ))!;
      await tester.pumpWidget(MaterialApp(home: MvpWorkspace(repo: repo)));
      await tester.tap(find.text('Daftar anak'));
      await tester.pumpAndSettle();
      expect(find.textContaining('FormatException'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('name')), 'Anak Demo');
      await tester.enterText(find.byKey(const Key('birth')), '2024-01-01');
      await tester.tap(find.text('Daftar anak'));
      await tester.pumpAndSettle();
      final c = repo.state['children'].keys.first as String;
      await tester.runAsync(() async {
        final id = await repo.save('d', c, {
          'date': '2026-10-01',
          'weight': 12.0,
          'cm': 88.0,
          'position': 'standing',
          'oedema': 'no',
        });
        await repo.submit('s', id);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: MvpWorkspace(key: UniqueKey(), repo: repo),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('BadanGizi'));
      await tester.pumpAndSettle();
      expect(find.textContaining('weightAge |'), findsOneWidget);
      expect(find.textContaining('heightAge |'), findsOneWidget);
      expect(find.textContaining('weightHeight |'), findsOneWidget);
      await tester.ensureVisible(find.text('Tolak'));
      await tester.tap(find.text('Tolak'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Catatan penolakan wajib'), findsOneWidget);
      await tester.tap(find.text('Pemerintah'));
      await tester.pumpAndSettle();
      expect(find.text('Agregat approved — baca saja'), findsOneWidget);
      expect(find.text('Daftar anak'), findsNothing);
      expect(find.text('Anak Demo'), findsNothing);
      await repo.close();
    },
  );
}
