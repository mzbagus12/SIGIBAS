import 'package:sembast_web/sembast_web.dart';

import 'dart:js_interop';

import 'encrypted_codec.dart';
import 'storage_key.dart';
import 'storage_migration.dart';

@JS('navigator.locks.request')
external JSPromise<JSAny?> _requestStorageLock(
  JSString name,
  JSFunction action,
);

Future<Database> openMvpDatabase() async {
  Database? opened;
  // Serialize key creation AND migration across same-origin tabs. Never fall
  // back to a racy unlocked initialization if this browser lacks Web Locks.
  await _requestStorageLock(
    'sigibas-encrypted-storage-v2'.toJS,
    ((JSAny? _) {
      return (() async {
        opened = await _openLocked();
        return null as JSAny?;
      })().toJS;
    }).toJS,
  ).toDart;
  return opened!;
}

Future<Database> _openLocked() async {
  const target = 'sigibas-v2-encrypted';
  final key = await loadDatabaseKey(
    encryptedExists: await databaseFactoryWeb.databaseExists(target),
  );
  return openMigratedDatabase(
    legacyFactory: databaseFactoryWeb,
    legacyPath: 'sigibas-mvp-v1',
    targetFactory: databaseFactoryWeb,
    targetPath: target,
    codec: encryptedSembastCodec(key),
  );
}
