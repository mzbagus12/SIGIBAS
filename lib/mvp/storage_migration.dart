import 'dart:convert';

import 'package:sembast/utils/sembast_import_export.dart';

import '../engine/sha256.dart';

const _migrationStore = 'sigibas_migration_v2';
String _fingerprint(Map data) {
  dynamic sort(dynamic v) {
    if (v is Map) {
      final keys = v.keys.map((k) => k.toString()).toList()..sort();
      return {for (final k in keys) k: sort(v[k])};
    }
    if (v is List) return v.map(sort).toList();
    return v;
  }

  final stores =
      ((data['stores'] as List?) ?? [])
          .where((s) => s['name'] != _migrationStore)
          .map((s) {
            final keys = s['keys'] as List, values = s['values'] as List;
            final pairs = [
              for (var i = 0; i < keys.length; i++) [keys[i], values[i]],
            ];
            pairs.sort((a, b) => jsonEncode(a[0]).compareTo(jsonEncode(b[0])));
            return {'name': s['name'], 'records': pairs};
          })
          .toList()
        ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
  return sha256(
    utf8.encode(
      jsonEncode(sort({'version': data['version'], 'stores': stores})),
    ),
  );
}

/// Copy all stores transactionally, reopen and verify before removing plaintext.
/// Divergent targets and decryption errors fail without a reset.
Future<Database> openMigratedDatabase({
  required DatabaseFactory legacyFactory,
  required String legacyPath,
  required DatabaseFactory targetFactory,
  required String targetPath,
  required SembastCodec codec,
}) async {
  if (!await legacyFactory.databaseExists(legacyPath)) {
    return targetFactory.openDatabase(
      targetPath,
      mode: DatabaseMode.create,
      codec: codec,
    );
  }
  final legacy = await legacyFactory.openDatabase(
    legacyPath,
    mode: DatabaseMode.existing,
  );
  Map<String, Object?> source;
  try {
    source = await exportDatabase(legacy);
  } finally {
    await legacy.close();
  }
  final sourceHash = _fingerprint(source);
  final existing = await targetFactory.databaseExists(targetPath);
  var target = await targetFactory.openDatabase(
    targetPath,
    mode: DatabaseMode.create,
    codec: codec,
    version: existing ? null : source['version'] as int?,
  );
  final marker = stringMapStoreFactory
      .store(_migrationStore)
      .record('verified');
  Future<void> deleteUnchangedSource() async {
    final latest = await legacyFactory.openDatabase(
      legacyPath,
      mode: DatabaseMode.existing,
    );
    late String latestHash;
    try {
      latestHash = _fingerprint(await exportDatabase(latest));
    } finally {
      await latest.close();
    }
    if (latestHash != sourceHash) {
      throw StateError(
        'Sumber berubah selama migrasi. Sumber dan tujuan dipertahankan. Tutup tab aplikasi lama sebelum mencoba lagi.',
      );
    }
    await legacyFactory.deleteDatabase(legacyPath);
  }

  try {
    final previous = await marker.get(target);
    if (previous?['sourceHash'] == sourceHash) {
      await deleteUnchangedSource();
      return target;
    }
    final current = await exportDatabase(target);
    final currentStores = (current['stores'] as List?) ?? [];
    if (currentStores.isNotEmpty && _fingerprint(current) != sourceHash) {
      throw StateError(
        'Migrasi dihentikan: sumber dan tujuan berbeda. Kedua data dipertahankan.',
      );
    }
    if (currentStores.isEmpty) {
      await target.transaction((txn) async {
        for (final item in (source['stores'] as List?) ?? []) {
          final keys = item['keys'] as List, values = item['values'] as List;
          final store = StoreRef<Object, Object?>(item['name'] as String);
          for (var i = 0; i < keys.length; i++) {
            await store.record(keys[i] as Object).put(txn, values[i]);
          }
        }
      });
    }
    await target.close();
    target = await targetFactory.openDatabase(
      targetPath,
      mode: DatabaseMode.existing,
      codec: codec,
    );
    if (_fingerprint(await exportDatabase(target)) != sourceHash) {
      throw StateError('Verifikasi migrasi gagal. Sumber dipertahankan.');
    }
    await marker.put(target, {'sourceHash': sourceHash, 'verified': true});
    await deleteUnchangedSource();
    return target;
  } catch (_) {
    await target.close();
    rethrow;
  }
}
