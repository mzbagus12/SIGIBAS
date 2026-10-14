import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

Future<Database> openMvpDatabase() async {
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  return databaseFactoryIo.openDatabase(
    '${dir.path}${Platform.pathSeparator}sigibas-mvp-v1.db',
    mode: DatabaseMode.create,
  );
}
