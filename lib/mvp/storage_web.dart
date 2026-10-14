import 'package:sembast_web/sembast_web.dart';

Future<Database> openMvpDatabase() => databaseFactoryWeb.openDatabase(
  'sigibas-mvp-v1',
  mode: DatabaseMode.create,
);
