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
      await tester.pumpWidget(
        MaterialApp(
          home: MvpWorkspace(
            repo: repo,
            role: 'Kader',
            initialPage: 'register',
            onLogout: () {},
          ),
        ),
      );
      await tester.tap(find.text('Daftar anak'));
      await tester.pumpAndSettle();
      expect(find.textContaining('FormatException'), findsNothing);
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
          home: MvpWorkspace(
            key: UniqueKey(),
            repo: repo,
            role: 'BadanGizi',
            initialPage: 'history',
            onLogout: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('revision-table')), findsOneWidget);
      expect(find.text('Tanggal ukur'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('revision-select-revision:d')),
      );
      await tester.tap(find.byKey(const Key('revision-select-revision:d')));
      await tester.pumpAndSettle();
      expect(find.text('Catatan wajib untuk penolakan.'), findsOneWidget);
      expect(find.textContaining('Berat badan menurut umur'), findsOneWidget);
      expect(
        find.textContaining('Panjang/tinggi badan menurut umur'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Berat badan menurut panjang/tinggi'),
        findsOneWidget,
      );
      expect(find.text('Detail teknis'), findsNothing);
      expect(find.text('Riwayat audit teknis'), findsNothing);
      expect(find.text('Hasil pengukuran'), findsOneWidget);
      expect(find.text('Tanggal ukur'), findsOneWidget);
      expect(find.text('Berat badan'), findsOneWidget);
      expect(find.text('Panjang / tinggi'), findsOneWidget);
      await tester.ensureVisible(find.text('Tolak'));
      await tester.tap(find.text('Tolak'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Catatan penolakan wajib'), findsOneWidget);
      expect(find.textContaining('Bad state:'), findsNothing);
      await tester.enterText(find.byKey(const Key('note')), 'Ukur ulang');
      await tester.ensureVisible(find.text('Tolak'));
      await tester.tap(find.text('Tolak'));
      await tester.pumpAndSettle();
      expect(find.text('Anak Demo — Ditolak'), findsOneWidget);
      expect(find.textContaining('Catatan: Ukur ulang'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: MvpWorkspace(
            key: UniqueKey(),
            repo: repo,
            role: 'Kader',
            initialPage: 'history',
            onLogout: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('revision-select-revision:d')),
      );
      await tester.tap(find.byKey(const Key('revision-select-revision:d')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('revision-table')), findsNothing);
      await tester.ensureVisible(find.text('Koreksi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Koreksi'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Form koreksi siap'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('weight')))
            .controller!
            .text,
        '12.0',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MvpWorkspace(
            key: UniqueKey(),
            repo: repo,
            role: 'Pemerintah',
            initialPage: 'summary',
            onLogout: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ringkasan data disetujui'), findsOneWidget);
      expect(find.text('Daftar anak'), findsNothing);
      expect(find.text('Anak Demo'), findsNothing);
      await repo.close();
    },
  );
}
