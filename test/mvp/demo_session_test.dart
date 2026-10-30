import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sigibas_rasp/engine/engine.dart';
import 'package:sigibas_rasp/mvp/repository.dart';
import 'package:sigibas_rasp/mvp/demo_session.dart';
import 'package:sigibas_rasp/mvp/local_accounts.dart';

void main() {
  testWidgets('login demo memisahkan peran dan logout mengakhiri sesi', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final engine = GrowthEngine.fromJson(
      File('assets/engine/tables.json').readAsStringSync(),
      File('assets/engine/manifest.json').readAsStringSync(),
    );
    final repo = (await tester.runAsync(
      () async => MvpRepository.open(
        await databaseFactoryMemory.openDatabase('login-test'),
        engine,
        today: '2026-10-14',
      ),
    ))!;
    await tester.runAsync(
      () => LocalAccounts(repo.db).configure({
        'kader': '123456',
        'gizi': '234567',
        'pemerintah': '345678',
      }),
    );
    await tester.pumpWidget(MaterialApp(home: DemoSession(repo: repo)));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Masuk ke SI-GIBAS'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('login-user')), 'kader');
    await tester.enterText(find.byKey(const Key('login-pin')), '9999');
    await tester.runAsync(() async {
      await tester.tap(find.text('Masuk'));
      final dynamic session = tester.state(find.byType(DemoSession));
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (session.busy == true && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(session.busy, false);
    });
    await tester.pumpAndSettle();
    expect(find.text('ID atau PIN tidak sesuai.'), findsOneWidget);
    expect(find.text('Daftar anak'), findsNothing);
    await tester.enterText(find.byKey(const Key('login-pin')), '123456');
    await tester.runAsync(() async {
      await tester.tap(find.text('Masuk'));
      final dynamic session = tester.state(find.byType(DemoSession));
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (session.busy == true && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(session.busy, false);
    });
    await tester.pumpAndSettle();
    expect(find.text('Tambah anak'), findsOneWidget);
    expect(find.text('Badan Gizi'), findsNothing);
    await tester.tap(find.byTooltip('Keluar'));
    await tester.pumpAndSettle();
    expect(find.text('Masuk ke SI-GIBAS'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('login-user')), 'pemerintah');
    await tester.enterText(find.byKey(const Key('login-pin')), '345678');
    await tester.runAsync(() async {
      await tester.tap(find.text('Masuk'));
      final dynamic session = tester.state(find.byType(DemoSession));
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (session.busy == true && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(session.busy, false);
    });
    await tester.pumpAndSettle();
    expect(find.text('Ringkasan data disetujui'), findsOneWidget);
    expect(find.text('Daftar anak'), findsNothing);
    await tester.tap(find.byTooltip('Keluar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('login-user')), 'gizi');
    await tester.enterText(find.byKey(const Key('login-pin')), '234567');
    await tester.runAsync(() async {
      await tester.tap(find.text('Masuk'));
      final dynamic session = tester.state(find.byType(DemoSession));
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (session.busy == true && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(session.busy, false);
    });
    await tester.pumpAndSettle();
    expect(find.text('Pemeriksaan data'), findsOneWidget);
    expect(find.text('Daftar anak'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Masuk ke SI-GIBAS'), findsOneWidget);
    await tester.runAsync(() => repo.close());
  });
}
