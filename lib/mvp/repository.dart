import 'dart:convert';

import 'package:sembast/sembast.dart';

import '../engine/engine.dart';

/// Local synthetic demo only. Role selection is not authorization.
class MvpRepository {
  final Database db;
  final GrowthEngine engine;
  final String today;
  bool failNextCommit = false;
  Map<String, dynamic> _state;
  static final _record = stringMapStoreFactory.store('mvp').record('state');
  MvpRepository._(this.db, this.engine, this.today, this._state);
  static Map<String, dynamic> _copy(Map value) =>
      jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
  Map<String, dynamic> get state => _copy(_state);
  static Future<MvpRepository> open(
    Database db,
    GrowthEngine engine, {
    String? today,
  }) async {
    final value = await _record.get(db);
    if (value != null && value['schema'] != 1) {
      await db.close();
      throw StateError('Unsupported schema; database preserved');
    }
    final now = DateTime.now();
    return MvpRepository._(
      db,
      engine,
      today ?? CivilDate(now.year, now.month, now.day).iso,
      value ??
          {
            'schema': 1,
            'children': <String, dynamic>{},
            'revisions': <String, dynamic>{},
            'audit': <dynamic>[],
            'commands': <String, dynamic>{},
          },
    );
  }

  Future<void> close() => db.close();
  Future<String> _commit(
    String op,
    String type,
    String Function(Map<String, dynamic>) mutate,
  ) async {
    if (op.trim().isEmpty) throw StateError('Operation ID required');
    late Map<String, dynamic> committed;
    final time = DateTime.now().toIso8601String();
    final result = await db.transaction((txn) async {
      final s = _copy(await _record.get(txn) ?? _state);
      if (s['commands'].containsKey(op)) {
        committed = s;
        return s['commands'][op] as String;
      }
      final id = mutate(s);
      s['audit'].add({
        'operation': op,
        'type': type,
        'revision': id,
        'atDevice': time,
      });
      s['commands'][op] = id;
      await _record.put(txn, s);
      if (failNextCommit) {
        failNextCommit = false;
        throw StateError('Injected failure after write before commit');
      }
      committed = s;
      return id;
    });
    _state = committed;
    return result;
  }

  void _date(String value, {String? birth}) {
    final date = CivilDate.parse(value);
    if (date.compareTo(CivilDate.parse(today)) > 0 ||
        (birth != null && date.compareTo(CivilDate.parse(birth)) < 0)) {
      throw const FormatException('Tanggal di masa depan/sebelum lahir');
    }
  }

  Future<String> register(String op, String name, String birth, String sex) =>
      _commit(op, 'register', (s) {
        _date(birth);
        if (name.trim().isEmpty || !['male', 'female'].contains(sex)) {
          throw const FormatException('Nama/jenis kelamin wajib');
        }
        final id = 'child:$op';
        s['children'][id] = {
          'id': id,
          'name': name.trim(),
          'birth': birth,
          'sex': sex,
          'nik': null,
        };
        return id;
      });
  bool _latestLeaf(Map s, String id) =>
      !s['revisions'].values.any((r) => r['previous'] == id);
  // Revision chains are linear: editability follows leaf, reporting follows
  // latest approved ancestor, regardless of later draft/pending/rejected nodes.
  Map<String, dynamic> _effectiveApproved(Map s) {
    final effective = <String, dynamic>{};
    for (final leaf in s['revisions'].values) {
      if (!_latestLeaf(s, leaf['id'])) continue;
      dynamic revision = leaf;
      while (revision != null && revision['status'] != 'approved') {
        revision = s['revisions'][revision['previous']];
      }
      if (revision != null) effective[revision['measurement']] = revision;
    }
    return effective;
  }

  Future<String> save(
    String op,
    String child,
    Map<String, dynamic> input, {
    String? previous,
  }) => _commit(op, 'save', (s) {
    final c = s['children'][child];
    if (c == null) throw StateError('Anak tidak ada');
    if (previous != null) {
      final old = s['revisions'][previous];
      if (old == null ||
          old['child'] != child ||
          !_latestLeaf(s, previous) ||
          !['rejected', 'approved', 'draft'].contains(old['status'])) {
        throw StateError('Revisi stale/tidak dapat dikoreksi');
      }
    }
    if (input['date'] != null && input['date'] != '') {
      _date(input['date'], birth: c['birth']);
    }
    final measurement = Measurement(
      birth: CivilDate.parse(c['birth']),
      sex: Sex.values.byName(c['sex']),
      measured: input['date'] == null || input['date'] == ''
          ? null
          : CivilDate.parse(input['date']),
      weightKg: (input['weight'] as num?)?.toDouble(),
      rawCm: (input['cm'] as num?)?.toDouble(),
      rawPosition: input['position'] == null
          ? null
          : Position.values.byName(input['position']),
      oedema: Oedema.values.byName(input['oedema'] ?? 'unknown'),
    );
    final result = engine.evaluate(measurement);
    final id = 'revision:$op';
    s['revisions'][id] = {
      'id': id,
      'child': child,
      'previous': previous,
      'measurement': previous == null
          ? id
          : s['revisions'][previous]['measurement'],
      'input': _copy(input),
      'status': 'draft',
      'note': '',
      'results': {
        for (final e in result.results.entries)
          e.key.name: {
            'status': e.value.status.name,
            'reason': e.value.reason,
            'rawZ': e.value.rawZ,
            'roundedZ': e.value.officialRoundedZ,
            'officialFlag': e.value.officialFlag,
            'rawReviewFlag': e.value.rawReviewFlag,
            'boundarySensitive': e.value.boundarySensitive,
            'category': e.value.categoryFinal,
            'standard': e.value.standard,
          },
      },
      'provenance': result.provenance,
      'ageDays': result.ageDays,
      'correctedCm': result.correctedCm,
    };
    if (previous != null) {
      s['audit'].add({
        'operation': op,
        'type': 'revision_created',
        'revision': previous,
        'by': id,
      });
    }
    return id;
  });
  Future<String> submit(String op, String id) => _commit(op, 'submit', (s) {
    final r = s['revisions'][id];
    if (r == null || !_latestLeaf(s, id) || r['status'] != 'draft') {
      throw StateError('Revisi stale/bukan draft');
    }
    final i = r['input'];
    if ([
          'date',
          'weight',
          'cm',
          'position',
          'oedema',
        ].any((k) => i[k] == null || i[k] == '') ||
        (i['weight'] as num) <= 0 ||
        (i['cm'] as num) <= 0) {
      throw StateError('Input wajib/positif belum lengkap');
    }
    r['status'] = 'pending';
    return id;
  });
  Future<String> review(String op, String id, bool approve, String note) =>
      _commit(op, approve ? 'approve' : 'reject', (s) {
        final r = s['revisions'][id];
        if (r == null || !_latestLeaf(s, id) || r['status'] != 'pending') {
          throw StateError('Revisi stale/bukan pending');
        }
        if (!approve && note.trim().isEmpty) {
          throw StateError('Catatan penolakan wajib');
        }
        if (approve) {
          final old = _effectiveApproved(s)[r['measurement']];
          if (old != null) {
            s['audit'].add({
              'operation': op,
              'type': 'superseded',
              'revision': old['id'],
              'by': id,
            });
          }
        }
        r['status'] = approve ? 'approved' : 'rejected';
        r['note'] = note.trim();
        return id;
      });
  Map<String, dynamic> aggregate() {
    final out = <String, dynamic>{
      for (final index in Index.values)
        index.name: {'denominator': 0, 'categories': <String, int>{}},
    };
    for (final r in _effectiveApproved(_state).values) {
      for (final index in Index.values) {
        final score = r['results'][index.name];
        if (score['status'] != 'valid' || score['category'] == null) continue;
        final bucket = out[index.name];
        bucket['denominator']++;
        final categories = bucket['categories'];
        categories[score['category']] =
            (categories[score['category']] ?? 0) + 1;
      }
    }
    return out;
  }
}
