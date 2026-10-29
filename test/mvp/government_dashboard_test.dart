import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigibas_rasp/mvp/government_dashboard.dart';

Map<String, dynamic> fixture() {
  Map<String, dynamic> revision(
    String id,
    String child,
    String measurement,
    String category, {
    String? previous,
    String status = 'approved',
    String date = '2026-09-01',
  }) => {
    'id': id,
    'child': child,
    'measurement': measurement,
    'previous': previous,
    'status': status,
    'input': {'date': date, 'private': 'must-not-leak'},
    'results': {
      'heightAge': {'status': 'valid', 'category': category},
      'weightAge': {'status': 'valid', 'category': 'normal'},
      'weightHeight': {'status': 'unavailable', 'category': null},
    },
  };
  return {
    'children': {
      'private-child-a': {
        'name': 'Secret Child',
        'nik': '0000000000000001',
        'village': 'Kelurahan A',
      },
      'private-child-b': {'name': 'Secret Two', 'village': 'Kelurahan B'},
    },
    'revisions': {
      'r1': revision('r1', 'private-child-a', 'm1', 'pendek'),
      'r2': revision('r2', 'private-child-a', 'm1', 'normal', previous: 'r1'),
      'r3': revision(
        'r3',
        'private-child-a',
        'm1',
        'sangat pendek',
        previous: 'r2',
        status: 'pending',
      ),
      'r4': revision(
        'r4',
        'private-child-b',
        'm2',
        'sangat pendek',
        date: '2026-10-01',
      ),
      'r5': revision(
        'r5',
        'private-child-b',
        'm3',
        'pendek',
        status: 'rejected',
      ),
      'r6': revision(
        'r6',
        'private-child-b',
        'm4',
        'pendek',
        date: '2026-10-02',
      ),
    },
  };
}

void main() {
  test(
    'effective corrections, invalid scores and count unit stay consistent',
    () {
      final data = buildGovernmentDashboard(fixture());
      final aggregate = combineDashboardCells(data['cells']);
      expect(aggregate['heightAge']['denominator'], 3);
      expect(aggregate['heightAge']['categories'], {
        'normal': 1,
        'pendek': 1,
        'sangat pendek': 1,
      });
      expect(dashboardStunting(aggregate), 2);
      expect(aggregate['weightHeight']['denominator'], 0);
      final changed = fixture();
      changed['revisions']['r3']['status'] = 'approved';
      final after = combineDashboardCells(
        buildGovernmentDashboard(changed)['cells'],
      );
      expect(after['heightAge']['denominator'], 3);
      expect(dashboardStunting(after), 3);
    },
  );
  test('privacy adapter whitelists aggregate output and synthesizes area coordinates', () {
    final data = buildGovernmentDashboard(fixture());
    final encoded = jsonEncode(data);
    for (final secret in [
      'private-child',
      'Secret Child',
      'Secret Two',
      '0000000000000001',
      'must-not-leak',
      'measurement',
      'results',
      'birth',
    ]) {
      expect(encoded, isNot(contains(secret)));
    }
    expect(data['areas'], [
      {'village': 'Kelurahan A', 'x': 1.0, 'y': 1.0},
      {'village': 'Kelurahan B', 'x': 3.3, 'y': 1.0},
    ]);
  });
  test('empty state and malformed cycle cannot fabricate observations', () {
    expect(
      combineDashboardCells(
        buildGovernmentDashboard({})['cells'],
      )['heightAge']['denominator'],
      0,
    );
    final state = fixture();
    state['revisions']['r1']['previous'] = 'r3';
    state['revisions']['r1']['status'] = 'pending';
    state['revisions']['r2']['status'] = 'pending';
    expect(
      combineDashboardCells(
        buildGovernmentDashboard(state)['cells'],
      )['heightAge']['denominator'],
      2,
    );
  });
  testWidgets(
    'mobile dashboard renders charts, applies filters and exposes no identity',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GovernmentDashboard(
                data: buildGovernmentDashboard(fixture()),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Secret Child'), findsNothing);
      expect(
        find.text('Tren stunting menurut bulan pengukuran'),
        findsOneWidget,
      );
      expect(find.text('Distribusi PB/U atau TB/U • n = 3'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026-09').last);
      await tester.pumpAndSettle();
      expect(find.text('Distribusi PB/U atau TB/U • n = 1'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Prioritas intervensi wilayah'),
        450,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byType(DataTable), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('zero dashboard stays usable on narrow screen', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GovernmentDashboard(data: buildGovernmentDashboard({})),
          ),
        ),
      ),
    );
    expect(
      find.text('Belum ada observasi disetujui untuk dashboard.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
