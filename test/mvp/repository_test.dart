import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sigibas_rasp/engine/engine.dart';
import 'package:sigibas_rasp/mvp/repository.dart';

void main() {
  late Directory dir;
  late MvpRepository repo;
  late GrowthEngine engine;
  setUp(() async {
    dir = await Directory(Platform.environment['TMPDIR'] ?? '.dart_tool')
        .createTemp('sigibas-test-');
    engine = GrowthEngine.fromJson(
      File('assets/engine/tables.json').readAsStringSync(),
      File('assets/engine/manifest.json').readAsStringSync(),
    );
    repo = await MvpRepository.open(
      await databaseFactoryIo.openDatabase('${dir.path}/data.db'),
      engine,
      today: '2026-10-14',
    );
  });
  tearDown(() async {
    await repo.close();
    // Preserve runtime files; Hermes scratch retention handles idle pruning.
  });
  Future<String> child() =>
      repo.register('c1', 'Anak Sintetis', '2024-01-01', 'male');
  Map<String, dynamic> input([double weight = 12]) => {
    'date': '2026-10-01',
    'weight': weight,
    'cm': 88.0,
    'position': 'standing',
    'oedema': 'no',
  };
  test('register stable ID NIK null; validate civil dates', () async {
    final id = await child();
    expect(repo.state['children'][id]['nik'], isNull);
    await expectLater(
      repo.register('c2', 'X', '2027-01-01', 'male'),
      throwsA(isA<FormatException>()),
    );
    await repo.close();
    repo = await MvpRepository.open(
      await databaseFactoryIo.openDatabase('${dir.path}/data.db'),
      engine,
      today: '2026-10-14',
    );
    expect(repo.state['children'][id]['name'], 'Anak Sintetis');
  });
  test(
    'reject correction resubmit approve immutable history and idempotency',
    () async {
      final c = await child();
      final r = await repo.save('d1', c, input());
      await repo.submit('s1', r);
      await expectLater(repo.review('bad', r, false, ' '), throwsStateError);
      await repo.review('reject', r, false, 'Ukur ulang');
      final r2 = await repo.save('d2', c, input(12.1), previous: r);
      await expectLater(repo.submit('stale', r), throwsStateError);
      await repo.submit('s2', r2);
      await repo.review('approve', r2, true, '');
      final n = (repo.state['audit'] as List).length;
      await repo.review('approve', r2, true, '');
      expect((repo.state['audit'] as List).length, n);
      expect(repo.state['revisions'][r]['status'], 'rejected');
      expect(repo.state['revisions'][r]['input']['weight'], 12);
      expect(repo.aggregate()['weightAge']['denominator'], 1);
      expect(repo.state['revisions'][r2]['results'].length, 3);
      expect(
        repo.state['revisions'][r2]['provenance']['tableHash'],
        GrowthEngine.tableSHA256,
      );
    },
  );
  test(
    'failed revision preserves committed child and no half result/audit',
    () async {
      final c = await child();
      final before = repo.state;
      repo.failNextCommit = true;
      await expectLater(repo.save('broken', c, input()), throwsStateError);
      expect(repo.state, before);
      await repo.close();
      repo = await MvpRepository.open(
        await databaseFactoryIo.openDatabase('${dir.path}/data.db'),
        engine,
        today: '2026-10-14',
      );
      expect(repo.state, before);
      final id = await repo.save('retry', c, input());
      expect(repo.state['revisions'][id]['results'].length, 3);
    },
  );
  test('schema failure preserves existing database bytes', () async {
    final file = '${dir.path}/schema.db';
    final db = await databaseFactoryIo.openDatabase(file);
    await stringMapStoreFactory.store('mvp').record('state').put(db, {
      'schema': 999,
      'sentinel': 'preserve',
    });
    await db.close();
    final before = File(file).readAsBytesSync();
    await expectLater(
      MvpRepository.open(await databaseFactoryIo.openDatabase(file), engine),
      throwsStateError,
    );
    expect(File(file).readAsBytesSync(), before);
  });
  test('corrupt open fails without deleting original', () async {
    final file = File('${dir.path}/corrupt.db');
    await file.writeAsString('not-sembast\\n');
    final before = file.readAsBytesSync();
    await expectLater(
      databaseFactoryIo.openDatabase(file.path, mode: DatabaseMode.create),
      throwsA(anything),
    );
    expect(file.readAsBytesSync(), before);
  });
  test('rollback transaction no half audit and reopen', () async {
    final before = repo.state;
    repo.failNextCommit = true;
    await expectLater(child(), throwsStateError);
    expect(repo.state, before);
    await repo.close();
    repo = await MvpRepository.open(
      await databaseFactoryIo.openDatabase('${dir.path}/data.db'),
      engine,
      today: '2026-10-14',
    );
    expect(repo.state['children'], isEmpty);
    expect(repo.state['audit'], isEmpty);
  });
  test(
    'draft incomplete unavailable never normal; submit rejects missing/future',
    () async {
      final c = await child();
      final r = await repo.save('d', c, {'date': '2026-10-01'});
      expect(
        repo.state['revisions'][r]['results']['weightAge']['rawZ'],
        isNull,
      );
      await expectLater(repo.submit('s', r), throwsStateError);
      await expectLater(
        repo.save('future', c, {...input(), 'date': '2026-10-15'}),
        throwsA(isA<FormatException>()),
      );
      expect(repo.aggregate()['weightAge']['denominator'], 0);
    },
  );
  for (final stage in ['draft', 'pending', 'rejected']) {
    test('approved remains effective with $stage correction', () async {
      final c = await child();
      final a = await repo.save('a', c, input());
      await repo.submit('as', a);
      await repo.review('aa', a, true, '');
      final before = repo.aggregate();
      final b = await repo.save('b', c, input(7), previous: a);
      if (stage != 'draft') await repo.submit('bs', b);
      if (stage == 'rejected') await repo.review('br', b, false, 'Ukur ulang');
      expect(repo.aggregate(), before);
      expect(repo.aggregate()['weightAge']['denominator'], 1);
      expect(
        (repo.state['audit'] as List).where((e) => e['type'] == 'superseded'),
        isEmpty,
      );
      final latest = stage == 'rejected'
          ? await repo.save('c', c, input(7), previous: b)
          : b;
      if (stage != 'pending') await repo.submit('cs', latest);
      repo.failNextCommit = true;
      await expectLater(
        repo.review('failed-approval', latest, true, ''),
        throwsStateError,
      );
      expect(repo.aggregate(), before);
      expect(
        (repo.state['audit'] as List).where((e) => e['type'] == 'superseded'),
        isEmpty,
      );
      await repo.review('ca', latest, true, '');
      final category =
          repo.state['revisions'][latest]['results']['weightAge']['category'];
      expect(
        category,
        isNot(repo.state['revisions'][a]['results']['weightAge']['category']),
      );
      expect(repo.aggregate()['weightAge'], {
        'denominator': 1,
        'categories': {category: 1},
      });
      final superseded = (repo.state['audit'] as List)
          .where((e) => e['type'] == 'superseded')
          .toList();
      expect(superseded, hasLength(1));
      expect(superseded.single['revision'], a);
      expect(superseded.single['by'], latest);
      await expectLater(
        repo.save('stale', c, input(), previous: a),
        throwsStateError,
      );
    });
  }
  test(
    'superseded approved excluded; unavailable per-index excluded',
    () async {
      final c = await child();
      final a = await repo.save('a', c, input());
      await repo.submit('as', a);
      await repo.review('aa', a, true, '');
      final b = await repo.save('b', c, {
        ...input(),
        'oedema': 'yes',
      }, previous: a);
      await repo.submit('bs', b);
      await repo.review('ba', b, true, 'Diperiksa');
      expect(repo.aggregate()['weightAge']['denominator'], 0);
      expect(repo.aggregate()['heightAge']['denominator'], 1);
      expect(repo.state['revisions'][a]['status'], 'approved');
      expect(
        (repo.state['audit'] as List)
            .where((e) => e['type'] == 'superseded')
            .length,
        1,
      );
    },
  );
}
