import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast_sqflite/sembast_sqflite.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import 'encrypted_codec.dart';
import 'storage_key.dart';
import 'storage_migration.dart';

Future<Database> openMvpDatabase() async {
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  final targetFactory =
      (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)
      ? getDatabaseFactorySqflite(sqflite.databaseFactory)
      : databaseFactoryIo;
  final base = '${dir.path}${Platform.pathSeparator}';
  final target = '${base}sigibas-v2-encrypted.sqlite';
  final key = await loadDatabaseKey(
    encryptedExists: await targetFactory.databaseExists(target),
  );
  return openMigratedDatabase(
    legacyFactory: databaseFactoryIo,
    legacyPath: '${base}sigibas-mvp-v1.db',
    targetFactory: targetFactory,
    targetPath: target,
    codec: encryptedSembastCodec(key),
  );
}
