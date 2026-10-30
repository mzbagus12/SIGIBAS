import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sigibas_rasp/engine/engine.dart';
import 'package:sigibas_rasp/mvp/care_panel.dart';
import 'package:sigibas_rasp/mvp/repository.dart';
import 'package:sigibas_rasp/mvp/ui.dart';

void main() {
  testWidgets('hanya Kader dapat memulihkan profil arsip', (tester) async {
    final engine = GrowthEngine.fromJson(
      File('assets/engine/tables.json').readAsStringSync(),
      File('assets/engine/manifest.json').readAsStringSync(),
    );
    final repo = (await tester.runAsync(() async {
      final repo = await MvpRepository.open(
        await databaseFactoryMemory.openDatabase('restore-ui'),
        engine,
        today: '2026-10-29',
      );
      final id = await repo.register(
        'child',
        'Anak Dummy',
        '2024-01-01',
        'male',
      );
      await repo.archiveChild('archive', id);
      return repo;
    }))!;
    final id = repo.state['children'].keys.single as String;
    await tester.runAsync(() async {
      await repo.restoreChild('seed-restore', id);
      await repo.save('seed-revision', id, {
        'date': '2026-10-01',
        'weight': 12,
        'cm': 88,
        'position': 'standing',
        'oedema': 'no',
      });
      await repo.archiveChild('seed-archive', id);
    });
    tester.view.physicalSize = const Size(1400, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MvpWorkspace(
          repo: repo,
          role: 'Kader',
          initialPage: 'history',
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Anak Dummy'), findsWidgets);
    Widget screen(String role) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CarePanel(
            key: ValueKey(role),
            repo: repo,
            role: role,
            onChanged: () {},
          ),
        ),
      ),
    );
    await tester.pumpWidget(screen('BadanGizi'));
    expect(find.text('Profil diarsipkan'), findsNothing);
    await tester.pumpWidget(screen('Kader'));
    await tester.tap(find.text('Profil diarsipkan'));
    await tester.pumpAndSettle();
    expect(find.text('Anak Dummy'), findsOneWidget);
    await tester.tap(find.text('Pulihkan'));
    await tester.pumpAndSettle();
    expect(repo.state['children'][id]['archived'], false);
    expect(find.text('Profil diarsipkan'), findsNothing);
    await tester.runAsync(() => repo.close());
  });
}
