import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sigibas_rasp/engine/engine.dart';
import 'package:sigibas_rasp/mvp/repository.dart';
import 'package:sigibas_rasp/mvp/encrypted_codec.dart';
import 'package:sigibas_rasp/mvp/government_dashboard.dart';
import 'package:sigibas_rasp/mvp/report.dart';

void main() {
  test('profil performa lokal terenkripsi dengan 100 profil dummy', () async {
    // Host file storage measures shared Dart logic, not Android SQLite or frames.
    final directory = await Directory('.dart_tool').createTemp('offline-perf-');
    final path = '${directory.path}/encrypted.db';
    final codec = encryptedSembastCodec(List<int>.generate(32, (i) => i));
    final engine = GrowthEngine.fromJson(
      File('assets/engine/tables.json').readAsStringSync(),
      File('assets/engine/manifest.json').readAsStringSync(),
    );
    Future<MvpRepository> open() async => MvpRepository.open(
      await databaseFactoryIo.openDatabase(path, codec: codec),
      engine,
      today: '2026-10-30',
    );
    var repo = await open();
    final timings = <String, List<double>>{};
    Future<T> measure<T>(String name, Future<T> Function() action) async {
      final watch = Stopwatch()..start();
      final value = await action();
      timings.putIfAbsent(name, () => []).add(watch.elapsedMicroseconds / 1000);
      return value;
    }

    try {
      for (var i = 0; i < 100; i++) {
        final child = await measure(
          'register',
          () => repo.register(
            'perf-child-$i',
            'Anak Dummy $i',
            '2024-01-01',
            i.isEven ? 'male' : 'female',
          ),
        );
        final revision = await measure(
          'save',
          () => repo.save('perf-save-$i', child, {
            'date': '2026-10-01',
            'weight': 12.0,
            'cm': 88.0,
            'position': 'standing',
            'oedema': 'no',
          }),
        );
        await measure('submit', () => repo.submit('perf-submit-$i', revision));
        await measure(
          'approve',
          () => repo.review('perf-review-$i', revision, true, ''),
        );
      }
      for (var i = 0; i < 20; i++) {
        await measure('aggregate', () async => repo.aggregate());
        await measure('aggregateHistory', () async => repo.aggregateHistory());
        await measure(
          'dashboard',
          () async => buildGovernmentDashboard(repo.state),
        );
      }
      await measure('pdf', () => buildAggregatePdf(repo.aggregate()));
      await measure('excel', () async => buildAggregateExcel(repo.aggregate()));
      await repo.close();
      repo = await measure('reopen', open);
      expect((repo.state['children'] as Map).length, 100);
      expect((repo.state['revisions'] as Map).length, 100);
      expect(repo.aggregate()['weightAge']['denominator'], 100);
      expect(repo.aggregateHistory().length, 100);
      final metrics = <String, dynamic>{};
      for (final entry in timings.entries) {
        final values = entry.value..sort();
        metrics[entry.key] = {
          'samples': values.length,
          'p95Ms': values[(values.length * .95).ceil() - 1],
          'maxMs': values.last,
        };
      }
      // Acceptance limits for this host dataset, fixed before the first run.
      const limits = {
        'register': 1000,
        'save': 1000,
        'submit': 1000,
        'approve': 1000,
        'aggregate': 250,
        'aggregateHistory': 1000,
        'dashboard': 250,
        'pdf': 2000,
        'excel': 2000,
        'reopen': 2000,
      };
      final output = File('${directory.path}/results.json');
      output.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'at': DateTime.now().toIso8601String(),
          'platform': Platform.operatingSystem,
          'scope': 'Flutter test host, encrypted Sembast file; not Android SQLite or UI frame timing',
          'profiles': 100,
          'approvedMeasurements': 100,
          'metrics': metrics,
          'p95LimitsMs': limits,
        }),
      );
      // ignore: avoid_print
      print(
        'PERFORMANCE_EVIDENCE ${output.absolute.path} ${jsonEncode(metrics)}',
      );
      for (final entry in limits.entries) {
        expect(
          metrics[entry.key]['p95Ms'],
          lessThanOrEqualTo(entry.value),
          reason: entry.key,
        );
      }
    } finally {
      await repo.close();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
