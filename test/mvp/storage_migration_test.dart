import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sigibas_rasp/mvp/encrypted_codec.dart';
import 'package:sigibas_rasp/mvp/storage_migration.dart';

void main(){
  test('verified migration copies all stores and removes old source only after verification',() async {
    final dir=await Directory('.dart_tool').createTemp('migrate-');
    final old='${dir.path}/legacy.db', target='${dir.path}/encrypted.db';
    var db=await databaseFactoryIo.openDatabase(old,version:3);
    await stringMapStoreFactory.store('mvp').record('state').put(db,{'name':'Dummy','revisions':{'a':1}});
    await intMapStoreFactory.store('other').record(1).put(db,{'value':'keep'});
    await db.close();
    final codec=encryptedSembastCodec(List.filled(32,8));
    db=await openMigratedDatabase(legacyFactory:databaseFactoryIo,legacyPath:old,targetFactory:databaseFactoryIo,targetPath:target,codec:codec);
    expect(db.version,3);
    expect((await stringMapStoreFactory.store('mvp').record('state').get(db))!['name'],'Dummy');
    expect((await intMapStoreFactory.store('other').record(1).get(db))!['value'],'keep');
    expect(await databaseFactoryIo.databaseExists(old),false);
    await db.close();
    expect(File(target).readAsStringSync(),isNot(contains('Dummy')));
  });
  test('different nonempty target is never overwritten and legacy survives',() async {
    final dir=await Directory('.dart_tool').createTemp('migrate-conflict-');
    final old='${dir.path}/legacy.db',target='${dir.path}/encrypted.db';
    var db=await databaseFactoryIo.openDatabase(old);
    await stringMapStoreFactory.store('mvp').record('state').put(db,{'name':'Original'});
    await db.close();
    final codec=encryptedSembastCodec(List.filled(32,8));
    db=await databaseFactoryIo.openDatabase(target,codec:codec);
    await stringMapStoreFactory.store('mvp').record('state').put(db,{'name':'Other'});await db.close();
    await expectLater(openMigratedDatabase(legacyFactory:databaseFactoryIo,legacyPath:old,targetFactory:databaseFactoryIo,targetPath:target,codec:codec),throwsStateError);
    expect(await databaseFactoryIo.databaseExists(old),true);
    db=await databaseFactoryIo.openDatabase(target,codec:codec);
    expect((await stringMapStoreFactory.store('mvp').record('state').get(db))!['name'],'Other');await db.close();
  });
}
