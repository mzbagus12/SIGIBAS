import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:convert';

import 'package:sembast/sembast.dart';

import '../engine/engine.dart';
import '../engine/sha256.dart';

typedef DemoSyncTransport = Future<Map<String, dynamic>> Function(
  String role,
  String path,
  Map<String, dynamic> body,
);

class DemoSyncResult {
  final int sent;
  final int remaining;
  final String? error;
  const DemoSyncResult(this.sent, this.remaining, [this.error]);
}

/// Local synthetic demo only. Role selection is not authorization.
class MvpRepository {
  final Database db;
  final GrowthEngine engine;
  final String today;
  bool failNextCommit = false;
  bool _syncing = false;
  bool _exchanging = false;
  Map<String, dynamic> _state;
  static final _record = stringMapStoreFactory.store('mvp').record('state');
  MvpRepository._(this.db, this.engine, this.today, this._state);
  static Map<String, dynamic> _copy(Map value) =>
      jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
  Map<String, dynamic> get state => _copy(_state);
  static String _demoId(String id) =>
      'demo-${sha256(utf8.encode(id)).substring(0, 56)}';
  static String _demoOp(String id) =>
      'op-${sha256(utf8.encode(id)).substring(0, 56)}';
  int get pendingDemoSyncCount =>
      ((_state['demoSyncQueue'] as List?) ?? const [])
          .where((entry) => entry['sent'] != true)
          .length;

  static void _enqueue(Map<String, dynamic> state, Map<String, dynamic> entry) {
    final queue = state.putIfAbsent('demoSyncQueue', () => <dynamic>[]) as List;
    queue.add(entry);
  }

  /// Explicit user-triggered, outbound-only synthetic demo; not real synchronization.
  Future<DemoSyncResult> syncDemo(DemoSyncTransport transport) async {
    if (_syncing || _exchanging) {
      return DemoSyncResult(
        0,
        pendingDemoSyncCount,
        'Pengiriman sedang berlangsung.',
      );
    }
    _syncing = true;
    var sent = 0;
    try {
      while (true) {
        final queue = (_state['demoSyncQueue'] as List?) ?? const [];
        final pending = queue.where((item) => item['sent'] != true);
        if (pending.isEmpty) return DemoSyncResult(sent, 0);
        final entry = _copy(pending.first as Map);
        try {
          final reply = await transport(
            entry['role'] as String,
            entry['path'] as String,
            _copy(entry['body'] as Map),
          ).timeout(const Duration(seconds: 8));
          if (reply['revision_id'] != entry['expectedRevision'] ||
              reply['status'] != entry['expectedStatus']) {
            return DemoSyncResult(
              sent,
              pendingDemoSyncCount,
              'Respons server tidak sesuai; data tetap antre.',
            );
          }
          late Map<String, dynamic> committed;
          await db.transaction((txn) async {
            final state = _copy(await _record.get(txn) ?? _state);
            final target = (state['demoSyncQueue'] as List).firstWhere(
              (item) => item['operation'] == entry['operation'],
            );
            target['sent'] = true;
            await _record.put(txn, state);
            committed = state;
          });
          _state = committed;
          sent++;
        } catch (_) {
          return DemoSyncResult(
            sent,
            pendingDemoSyncCount,
            'Server demo tidak tersedia atau menolak data; coba lagi.',
          );
        }
      }
    } finally {
      _syncing = false;
    }
  }

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
  static String _canonical(dynamic value) {
    dynamic sort(dynamic v) {
      if (v is Map) {
        final keys = v.keys.cast<String>().toList()..sort();
        return {for (final k in keys) k: sort(v[k])};
      }
      if (v is List) return v.map(sort).toList();
      return v;
    }

    return jsonEncode(sort(value));
  }

  List<Map<String, dynamic>> get syncConflicts =>
      ((_state['syncConflicts'] as List?) ?? []).map((e) => _copy(e)).toList();

  Future<void> resolveSyncConflict(
    String key, {
    required bool useRemote,
  }) async {
    if (_exchanging) throw StateError('Tunggu sinkronisasi selesai');
    final next = _copy(_state);
    final conflicts = next['syncConflicts'] as List? ?? [];
    final item = conflicts.firstWhere((e) => e['key'] == key);
    const names = {
      'child': 'children',
      'revision': 'revisions',
      'visit': 'visits',
    };
    final remote = item['remote'];
    final values = next[names[remote['kind']]] as Map;
    if (useRemote) {
      values[remote['id']] = _copy(remote['value']);
    } else if (remote['kind'] == 'revision') {
      if (![
        'draft',
        'approved',
        'rejected',
      ].contains(remote['value']['status'])) {
        throw StateError(
          'Tunggu review server selesai sebelum membuat koreksi.',
        );
      }
      final id =
          'revision:sync-correction-${DateTime.now().microsecondsSinceEpoch}';
      final correction = _copy(item['local']);
      correction.addAll({
        'id': id,
        'previous': remote['id'],
        'measurement': remote['value']['measurement'],
        'status': 'draft',
        'note': '',
      });
      values[remote['id']] = _copy(remote['value']);
      values[id] = correction;
    }
    (next.putIfAbsent('syncBases', () => <String, dynamic>{}) as Map)[key] = {
      'version': remote['version'],
      'value': _copy(remote['value']),
    };
    (next['audit'] as List).add({
      'type': 'sync_conflict_resolved',
      'key': key,
      'choice': useRemote ? 'server' : 'local',
      'localBackup': item['local'],
      'atDevice': DateTime.now().toIso8601String(),
    });
    conflicts.removeWhere((e) => e['key'] == key);
    await _record.put(db, next);
    _state = next;
  }

  Future<int> exchangeState(
    String role,
    Future<Map<String, dynamic>> Function(List<Map<String, dynamic>>)
    transport, {
    Future<Map<String, dynamic>> Function(String cursor)? fetchPage,
  }) async {
    if (_exchanging || _syncing) {
      throw StateError('Sinkronisasi sedang berjalan');
    }
    if (!['kader', 'gizi', 'pemerintah'].contains(role)) {
      throw StateError('Peran tidak diizinkan');
    }
    if (syncConflicts.isNotEmpty) {
      throw StateError('Selesaikan konflik terlebih dahulu');
    }
    _exchanging = true;
    var received = 0;
    const collections = {
      'child': 'children',
      'revision': 'revisions',
      'visit': 'visits',
    };
    try {
      var again = true;
      while (again) {
        final next = _copy(_state);
        final bases =
            next.putIfAbsent('syncBases', () => <String, dynamic>{}) as Map;
        final changes = <Map<String, dynamic>>[];
        for (final kind in collections.keys) {
          if ((kind == 'child' && role != 'kader') ||
              (kind == 'visit' && role != 'gizi') ||
              role == 'pemerintah') {
            continue;
          }
          for (final entry in (next[collections[kind]] as Map? ?? {}).entries) {
            final base = bases['$kind|${entry.key}'];
            if (_canonical(entry.value) == _canonical(base?['value'])) continue;
            var value = _copy(entry.value);
            if (kind == 'revision') {
              final previous = value['previous'];
              if (base == null && previous != null) {
                final parentBase = bases['revision|$previous'];
                // A reviewed ancestor backfills as pending first. Descendants
                // wait until a gizi session confirms that ancestor, rather than
                // submitting a chain whose parent is still pending remotely.
                if (parentBase == null ||
                    parentBase['value']['status'] == 'pending') {
                  continue;
                }
              }

              if (role == 'gizi' &&
                  (!['approved', 'rejected'].contains(value['status']) ||
                      base == null)) {
                continue;
              }
              if (role == 'kader' &&
                  ['approved', 'rejected'].contains(value['status'])) {
                if (base != null) continue;
                // Backfill as pending only: original local review remains intact,
                // and a gizi session must confirm it separately on the server.
                value['status'] = 'pending';
                value['note'] = '';
              }
            }
            final change = <String, dynamic>{
              'kind': kind,
              'id': entry.key,
              'version': base?['version'] ?? 0,
              'value': value,
            };
            change['operation'] = _demoOp(_canonical([role, change]));
            changes.add(change);
          }
        }
        again = changes.length > 25;
        final batch = changes.take(25).toList();
        Map<String, dynamic> reply;
        try {
          reply = await transport(batch).timeout(const Duration(seconds: 15));
        } catch (_) {
          // A failed ACK may follow a successful commit. Pulling detects the
          // resulting version; identical records are safe to reconcile/retry.
          reply = await transport([]).timeout(const Duration(seconds: 15));
          final remote = reply['records'];
          if (remote is! List ||
              !batch.every(
                (c) => remote.any(
                  (r) =>
                      r['kind'] == c['kind'] &&
                      r['id'] == c['id'] &&
                      _canonical(r['value']) == _canonical(c['value']),
                ),
              )) {
            // Process remote values below to persist explicit conflict choices.
            reply = {...reply, 'ack': [], 'failedBatch': true};
          } else {
            reply = {
              ...reply,
              'ack': batch.map((c) => c['operation']).toList(),
            };
          }
        }
        if (reply['records'] is! List || reply['ack'] is! List) {
          throw const FormatException('Respons sinkronisasi tidak valid');
        }
        final records = List<dynamic>.from(reply['records']);
        String? cursor = reply['nextCursor'];
        final cursors = <String>{};
        while (cursor != null) {
          if (fetchPage == null || !cursors.add(cursor)) {
            throw const FormatException('Halaman sinkronisasi tidak valid');
          }
          final page = await fetchPage(cursor)
              .timeout(const Duration(seconds: 15));
          if (page['records'] is! List) {
            throw const FormatException('Halaman sinkronisasi tidak valid');
          }
          records.addAll(page['records']);
          cursor = page['nextCursor'];
        }
        final seen = <String>{};
        for (final record in records) {
          if (record is! Map ||
              !seen.add('${record['kind']}|${record['id']}')) {
            throw const FormatException('Record server duplikat/tidak valid');
          }
        }
        for (final change in batch) {
          if ((reply['ack'] as List).contains(change['operation']) &&
              !records.any(
                (r) =>
                    r['kind'] == change['kind'] &&
                    r['id'] == change['id'] &&
                    r['version'] is int &&
                    r['version'] >= change['version'] + 1,
              )) {
            throw const FormatException('ACK tanpa versi record yang sesuai');
          }
        }
        if (role == 'pemerintah') {
          if (records.isNotEmpty || reply['aggregate'] is! Map) {
            throw const FormatException('Respons agregat tidak valid');
          }
          next['serverAggregate'] = _copy(reply['aggregate']);
          if (reply['dashboard'] is Map) {
            next['serverDashboard'] = _copy(reply['dashboard']);
          }
          next['serverAggregateAt'] = DateTime.now().toIso8601String();
        }
        final conflicts = <dynamic>[];
        for (final record in records) {
          final kind = record['kind'], id = record['id'];
          if (!collections.containsKey(kind) ||
              id is! String ||
              record['value'] is! Map ||
              record['version'] is! int ||
              record['version'] < 1) {
            throw const FormatException('Record server tidak valid');
          }
          final key = '$kind|$id';
          final values = next.putIfAbsent(
            collections[kind]!,
            () => <String, dynamic>{},
          ) as Map;
          final local = values[id], base = bases[key];
          final matching = batch.where(
            (c) => c['kind'] == kind && c['id'] == id,
          );
          final sent =
              matching.isNotEmpty &&
              (reply['ack'] as List).contains(matching.first['operation']) &&
              _canonical(record['value']) ==
                  _canonical(matching.first['value']);
          final backfill =
              sent &&
              kind == 'revision' &&
              ['approved', 'rejected'].contains(local?['status']) &&
              record['value']['status'] == 'pending';
          if (!sent &&
              local != null &&
              _canonical(local) != _canonical(base?['value']) &&
              _canonical(local) != _canonical(record['value'])) {
            // Unchanged server baseline is not a conflict: local work waits.
            if (_canonical(record['value']) == _canonical(base?['value'])) {
              continue;
            }
            conflicts.add({'key': key, 'local': local, 'remote': record});
            continue;
          }
          if (!backfill) {
            if (kind == 'revision' &&
                record['value']['status'] == 'approved' &&
                local?['status'] != 'approved') {
              (next['audit'] as List).add({
                'type': 'approve',
                'revision': id,
                'atDevice': DateTime.now().toIso8601String(),
                'operation': 'sync-$key-${record['version']}',
              });
            }
            values[id] = _copy(record['value']);
          }
          bases[key] = {
            'version': record['version'],
            'value': _copy(record['value']),
          };
        }
        next['syncConflicts'] = conflicts;
        await db.transaction((txn) async {
          await _record.put(txn, next);
        });
        _state = next;
        received += records.length;
        if (conflicts.isNotEmpty) {
          throw StateError(
            'Konflik tersimpan; pilih penyelesaian di panel sinkronisasi',
          );
        }
        if (reply['failedBatch'] == true) {
          throw StateError('Pengiriman belum diakui; data tetap lokal');
        }
        if (batch.any(
          (c) => (reply['ack'] as List).contains(c['operation']) == false,
        )) {
          throw const FormatException('ACK sinkronisasi tidak sesuai');
        }
      }
      return received;
    } finally {
      _exchanging = false;
    }
  }

  Future<String> _commit(
    String op,
    String type,
    String Function(Map<String, dynamic>) mutate,
  ) async {
    if (_exchanging) throw StateError('Tunggu sinkronisasi selesai');
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
  Future<void> initializeDummyProfiles() async {
    if ((_state['children'] as Map).isNotEmpty ||
        (_state['commands'] as Map).containsKey('initial-dummy-profiles')) {
      return;
    }
    await _commit('initial-dummy-profiles', 'dummy_initialized', (s) {
      if ((s['children'] as Map).isEmpty) {
        for (final entry in {
          'demo-local-1': 'Anak Contoh A',
          'demo-local-2': 'Anak Contoh B',
        }.entries) {
          s['children'][entry.key] = {
            'id': entry.key,
            'name': entry.value,
            'birth': '2024-01-01',
            'sex': entry.key == 'demo-local-1' ? 'male' : 'female',
            'nik': null,
          };
        }
      }
      return 'local-dummy';
    });
  }

  bool _latestLeaf(Map s, String id) =>
      !s['revisions'].values.any((r) => r['previous'] == id);

  Future<String> updateProfile(
    String op,
    String child,
    Map<String, dynamic> values,
  ) => _commit(op, 'profile_updated', (s) {
    final c = s['children'][child];
    if (c == null || c['archived'] == true) {
      throw StateError('Profil tidak aktif');
    }
    const allowed = {
      'name',
      'nik',
      'guardian',
      'village',
      'exclusiveBreastfeeding',
      'immunization',
    };
    if (values.keys.any((k) => !allowed.contains(k)) ||
        values.values.any((v) => v is! String || v.length > 200) ||
        (values.containsKey('name') &&
            (values['name'] as String).trim().isEmpty)) {
      throw const FormatException('Profil tidak valid');
    }
    for (final key in ['exclusiveBreastfeeding', 'immunization']) {
      if (values.containsKey(key) &&
          !['yes', 'no', 'unknown'].contains(values[key])) {
        throw const FormatException('Pilihan profil tidak valid');
      }
    }
    if (values.containsKey('nik')) {
      final nik = (values['nik'] as String).trim();
      if (nik.isNotEmpty && !RegExp(r'^000000[0-9]{10}$').hasMatch(nik)) {
        throw const FormatException(
          'NIK dummy harus 16 angka dan diawali 000000',
        );
      }
    }
    c.addAll(values.map((k, v) => MapEntry(k, (v as String).trim())));
    return child;
  });

  Future<String> updatePhoto(String op, String child, Uint8List? bytes) async {
    String? encoded;
    if (bytes != null) {
      if (bytes.isEmpty || bytes.length > 262144) {
        throw const FormatException('Foto maksimal 256 KB');
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final codec = await ui.instantiateImageCodecWithSize(
        buffer,
        getTargetSize: (width, height) {
          if (width > 2048 || height > 2048) {
            throw const FormatException('Ukuran foto maksimal 2048 piksel');
          }
          return ui.TargetImageSize(width: width > 256 ? 256 : width);
        },
      );
      try {
        final frame = await codec.getNextFrame();
        try {
          final png = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (png == null || png.lengthInBytes > 262144) {
            throw const FormatException('Foto terlalu besar');
          }
          encoded = base64Encode(
            png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
          );
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    }
    return _commit(op, 'photo_updated', (s) {
      final profile = s['children'][child];
      if (profile == null || profile['archived'] == true) {
        throw StateError('Profil tidak aktif');
      }
      profile['photo'] = encoded;
      return child;
    });
  }

  Future<String> archiveChild(String op, String child) =>
      _commit(op, 'child_archived', (s) {
        final c = s['children'][child];
        if (c == null) throw StateError('Anak tidak ada');
        c['archived'] = true;
        return child;
      });

  Future<String> restoreChild(String op, String child) =>
      _commit(op, 'child_restored', (s) {
        final c = s['children'][child];
        if (c == null || c['archived'] != true) {
          throw StateError('Profil tidak dalam arsip');
        }
        c['archived'] = false;
        return child;
      });

  Future<String> scheduleVisit(
    String op,
    String child,
    String date,
    String note,
  ) => _commit(op, 'visit_scheduled', (s) {
    if (s['children'][child] == null ||
        s['children'][child]['archived'] == true) {
      throw StateError('Profil tidak aktif');
    }
    if (CivilDate.parse(date).compareTo(CivilDate.parse(today)) < 0 ||
        note.length > 500) {
      throw const FormatException('Jadwal tidak valid atau sudah lewat');
    }
    final visits = s.putIfAbsent('visits', () => <String, dynamic>{}) as Map;
    visits[child] = {'date': date, 'note': note.trim()};
    return child;
  });

  List<Map<String, dynamic>> growthHistory(String child) {
    final rows = _effectiveApproved(_state).values
        .where((r) => r['child'] == child)
        .map((r) => _copy(r as Map))
        .toList();
    rows.sort(
      (a, b) => (a['input']['date'] as String).compareTo(
        b['input']['date'] as String,
      ),
    );
    return rows;
  }

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
    if (c['archived'] == true) throw StateError('Profil sudah diarsipkan');
    for (final key in ['muac', 'head']) {
      final value = input[key];
      if (value != null && (value is! num || !value.isFinite || value <= 0)) {
        throw const FormatException(
          'Lingkar lengan/kepala harus angka positif',
        );
      }
    }
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
    final queue = (s['demoSyncQueue'] as List?) ?? const [];
    String? parent = r['previous'] as String?;
    while (parent != null &&
        !queue.any(
          (item) =>
              item['path'] == '/revisions' &&
              item['expectedRevision'] == _demoId(parent!),
        )) {
      parent = s['revisions'][parent]?['previous'] as String?;
    }
    final payload = <String, dynamic>{
      'synthetic': true,
      'child_id': _demoId(r['child'] as String),
      'revision_id': _demoId(id),
      'weight': i['weight'],
      'height': i['cm'],
      if (parent != null) 'previous_id': _demoId(parent),
    };
    _enqueue(s, {
      'operation': _demoOp(op),
      'role': 'kader',
      'path': '/revisions',
      'body': {'operation_id': _demoOp(op), 'payload': payload},
      'expectedRevision': _demoId(id),
      'expectedStatus': 'pending',
      'sent': false,
    });
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
        final queue = (s['demoSyncQueue'] as List?) ?? const [];
        // Legacy revisions may predate the demo queue; never send a review for
        // a revision the demo server was never asked to receive.
        if (queue.any(
          (item) =>
              item['path'] == '/revisions' &&
              item['expectedRevision'] == _demoId(id),
        )) {
          _enqueue(s, {
            'operation': _demoOp(op),
            'role': 'gizi',
            'path': '/review',
            'body': {
              'operation_id': _demoOp(op),
              'revision_id': _demoId(id),
              'status': approve ? 'approved' : 'rejected',
              'note': approve ? '' : 'Catatan demo sintetis',
            },
            'expectedRevision': _demoId(id),
            'expectedStatus': approve ? 'approved' : 'rejected',
            'sent': false,
          });
        }
        return id;
      });
  Map<String, dynamic> _aggregateRevisions(Iterable<dynamic> revisions) {
    final out = <String, dynamic>{
      for (final index in Index.values)
        index.name: {'denominator': 0, 'categories': <String, int>{}},
    };
    for (final r in revisions) {
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

  Map<String, dynamic> aggregate() =>
      _aggregateRevisions(_effectiveApproved(_state).values);

  Map<String, dynamic> governmentAggregate() => _state['serverAggregate'] is Map
      ? _copy(_state['serverAggregate'])
      : aggregate();

  /// Replays committed approvals in audit order, returning aggregates only.
  /// atDevice is an untrusted local-device timestamp, not server time.
  List<Map<String, dynamic>> aggregateHistory() {
    final revisions = _state['revisions'] as Map;
    final effective = <String, dynamic>{};
    final history = <Map<String, dynamic>>[];
    for (final event in _state['audit'] as List) {
      if (event['type'] != 'approve') continue;
      final revision = revisions[event['revision']];
      if (revision == null) continue;
      effective[revision['measurement'] as String] = revision;
      history.add({
        'atDevice': event['atDevice'],
        'aggregate': _aggregateRevisions(effective.values),
      });
    }
    return history;
  }
}
