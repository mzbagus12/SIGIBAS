import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sigibas_rasp/engine/engine.dart';
import 'package:sigibas_rasp/mvp/repository.dart';

void main() {
  late MvpRepository repo;
  late Map<String, dynamic> remote;
  late Set<String> operations;
  var failAck = false;
  final sizes = <int>[];
  Future<Map<String, dynamic>> transport(
    List<Map<String, dynamic>> changes,
  ) async {
    sizes.add(changes.length);
    for (final c in changes) {
      if (operations.contains(c['operation'])) continue;
      final key = "${c['kind']}|${c['id']}";
      if ((remote[key]?['version'] ?? 0) != c['version']) {
        throw StateError('Conflict');
      }
      remote[key] = {
        'kind': c['kind'],
        'id': c['id'],
        'version': c['version'] + 1,
        'value': c['value'],
      };
      operations.add(c['operation']);
    }
    if (failAck) {
      failAck = false;
      throw StateError('Lost ACK');
    }
    return {
      'records': remote.values.toList(),
      'ack': changes.map((c) => c['operation']).toList(),
    };
  }

  setUp(() async {
    remote = {};
    operations = {};
    sizes.clear();
    failAck = false;
    repo = await MvpRepository.open(
      await databaseFactoryMemory.openDatabase(
        'sync-${DateTime.now().microsecondsSinceEpoch}',
      ),
      GrowthEngine.fromJson(
        File('assets/engine/tables.json').readAsStringSync(),
        File('assets/engine/manifest.json').readAsStringSync(),
      ),
      today: '2026-10-29',
    );
  });
  tearDown(() => repo.close());
  test('more than 100 local changes are sent in durable batches', () async {
    for (var i = 0; i < 123; i++) {
      await repo.register('c$i', 'Synthetic $i', '2024-01-01', 'male');
    }
    await repo.exchangeState('kader', transport);
    expect(remote.length, 123);
    expect(sizes.every((s) => s <= 25), isTrue);
    expect((repo.state['syncBases'] as Map).length, 123);
  });
  test('lost ACK reconciles identical committed remote data without duplicate writes', () async {
    final id = await repo.register('one', 'Synthetic', '2024-01-01', 'male');
    failAck = true;
    await repo.exchangeState('kader', transport);
    expect(remote['child|$id']['version'], 1);
    await repo.exchangeState('kader', transport);
    expect(remote['child|$id']['version'], 1);
  });
  test('conflict persists both values and explicit local choice rebases next write', () async {
    final id = await repo.register('one', 'Synthetic', '2024-01-01', 'male');
    await repo.exchangeState('kader', transport);
    await repo.updateProfile('local', id, {'name': 'Local choice'});
    remote['child|$id'] = {
      ...remote['child|$id'],
      'version': 2,
      'value': {...remote['child|$id']['value'], 'name': 'Other device'},
    };
    await expectLater(repo.exchangeState('kader', transport), throwsStateError);
    expect(repo.state['children'][id]['name'], 'Local choice');
    expect(
      repo.syncConflicts.single['remote']['value']['name'],
      'Other device',
    );
    await repo.resolveSyncConflict('child|$id', useRemote: false);
    await repo.exchangeState('kader', transport);
    expect(remote['child|$id']['version'], 3);
    expect(remote['child|$id']['value']['name'], 'Local choice');
  });
  test(
    'reviewed legacy records stage pending then require gizi confirmation',
    () async {
      final c = await repo.register(
        'legacy',
        'Synthetic',
        '2024-01-01',
        'male',
      );
      final r = await repo.save('measure', c, {
        'date': '2026-10-01',
        'weight': 12,
        'cm': 88,
        'position': 'standing',
        'oedema': 'no',
      });
      await repo.submit('submit', r);
      await repo.review('review', r, true, '');
      await repo.exchangeState('kader', transport);
      expect(remote['revision|$r']['value']['status'], 'pending');
      expect(repo.state['revisions'][r]['status'], 'approved');
      await repo.exchangeState('gizi', transport);
      expect(remote['revision|$r']['value']['status'], 'approved');
    },
  );
  test(
    'government receives aggregate response without applying individuals',
    () async {
      await repo.exchangeState('pemerintah', (changes) async {
        expect(changes, isEmpty);
        return {
          'records': [],
          'ack': [],
          'aggregate': {
            'heightAge': {'denominator': 7, 'categories': {}},
          },
        };
      });
      expect(repo.governmentAggregate()['heightAge']['denominator'], 7);
      expect(repo.state['children'], isEmpty);
    },
  );
  test(
    'paginated pull collects all records before applying local transaction',
    () async {
      final rows = List.generate(
        65,
        (i) => {
          'kind': 'child',
          'id': 'remote-$i',
          'version': 1,
          'value': {
            'id': 'remote-$i',
            'name': 'Synthetic $i',
            'birth': '2024-01-01',
            'sex': 'male',
          },
        },
      );
      Map<String, dynamic> page(int offset) => {
        'records': rows.skip(offset).take(25).toList(),
        'ack': [],
        'nextCursor': offset + 25 < rows.length ? '${offset + 25}' : null,
      };
      await repo.exchangeState(
        'gizi',
        (changes) async => page(0),
        fetchPage: (cursor) async => page(int.parse(cursor)),
      );
      expect((repo.state['children'] as Map).length, 65);
    },
  );
  test(
    'malformed ACK does not mark unsent local record synchronized',
    () async {
      final id = await repo.register('one', 'Synthetic', '2024-01-01', 'male');
      await expectLater(
        repo.exchangeState(
          'kader',
          (changes) async => {
            'ack': changes.map((c) => c['operation']).toList(),
            'records': [],
          },
        ),
        throwsFormatException,
      );
      expect(repo.state['syncBases'], isNull);
      expect(repo.state['children'][id]['name'], 'Synthetic');
    },
  );
  test(
    'legacy rejected ancestor and approved correction migrate in review phases',
    () async {
      final c = await repo.register(
        'legacy-chain',
        'Synthetic',
        '2024-01-01',
        'male',
      );
      final first = await repo.save('first', c, {
        'date': '2026-10-01',
        'weight': 12,
        'cm': 88,
        'position': 'standing',
        'oedema': 'no',
      });
      await repo.submit('s-first', first);
      await repo.review('r-first', first, false, 'Synthetic remeasure');
      final second = await repo.save('second', c, {
        'date': '2026-10-01',
        'weight': 12.1,
        'cm': 88,
        'position': 'standing',
        'oedema': 'no',
      }, previous: first);
      await repo.submit('s-second', second);
      await repo.review('r-second', second, true, '');
      await repo.exchangeState('kader', transport);
      expect(remote.containsKey('revision|$second'), isFalse);
      expect(remote['revision|$first']['value']['status'], 'pending');
      await repo.exchangeState('gizi', transport);
      expect(remote['revision|$first']['value']['status'], 'rejected');
      await repo.exchangeState('kader', transport);
      expect(remote['revision|$second']['value']['status'], 'pending');
      await repo.exchangeState('gizi', transport);
      expect(remote['revision|$second']['value']['status'], 'approved');
      expect(repo.state['revisions'][first]['status'], 'rejected');
      expect(repo.state['revisions'][second]['status'], 'approved');
    },
  );
}
