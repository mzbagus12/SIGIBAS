import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sigibas_rasp/engine/engine.dart';
import 'package:sigibas_rasp/mvp/repository.dart';
import 'package:sigibas_rasp/mvp/ui.dart';

void main() {
  testWidgets(
    'halaman tugas push/pop mempertahankan isian dan tidak menumpuk formulir',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = (await tester.runAsync(
        () async => MvpRepository.open(
          await databaseFactoryMemory.openDatabase('navigation'),
          GrowthEngine.fromJson(
            File('assets/engine/tables.json').readAsStringSync(),
            File('assets/engine/manifest.json').readAsStringSync(),
          ),
        ),
      ))!;
      await tester.pumpWidget(
        MaterialApp(
          home: MvpWorkspace(repo: repo, role: 'Kader', onLogout: () {}),
        ),
      );
      expect(find.byKey(const Key('open-register')), findsOneWidget);
      expect(find.byKey(const Key('name')), findsNothing);
      await tester.tap(find.byKey(const Key('open-register')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('name')),
        'Isian belum disimpan',
      );
      expect(find.byKey(const Key('weight')), findsNothing);
      await tester.ensureVisible(find.text('Lanjut ke pengukuran'));
      await tester.tap(find.text('Lanjut ke pengukuran'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Kembali'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('name')), findsOneWidget);
      await tester.tap(find.byTooltip('Kembali'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-register')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('name')))
            .controller!
            .text,
        'Isian belum disimpan',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => repo.close());
    },
  );
  testWidgets(
    'halaman tiap peran tidak overflow pada ponsel, lanskap dan teks besar',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = (await tester.runAsync(
        () async => MvpRepository.open(
          await databaseFactoryMemory.openDatabase('responsive-navigation'),
          GrowthEngine.fromJson(
            File('assets/engine/tables.json').readAsStringSync(),
            File('assets/engine/manifest.json').readAsStringSync(),
          ),
        ),
      ))!;
      await tester.runAsync(repo.initializeDummyProfiles);
      for (final size in [
        const Size(375, 812),
        const Size(812, 375),
        const Size(1024, 768),
      ]) {
        tester.view.physicalSize = size;
        for (final role in ['Kader', 'BadanGizi', 'Pemerintah']) {
          for (final page in [
            'home',
            'profiles',
            if (role == 'Kader') ...['register', 'measurement'],
            if (role != 'Pemerintah') 'history',
            if (role == 'Pemerintah') ...[
              'summary',
              'aggregate-history',
              'dashboard',
            ],
          ]) {
            if (role == 'Pemerintah' && page == 'profiles') continue;
            await tester.pumpWidget(
              MaterialApp(
                key: UniqueKey(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(2),
                    disableAnimations: true,
                  ),
                  child: child!,
                ),
                home: MvpWorkspace(
                  repo: repo,
                  role: role,
                  initialPage: page,
                  onLogout: () {},
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '$role $page $size text scale 2',
            );
          }
        }
      }
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(repo.close);
    },
  );
}
