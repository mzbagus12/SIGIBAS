import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sigibas_rasp/mvp/encrypted_codec.dart';

void main() {
  test('AES-GCM round trip, fresh nonce, tampering and wrong key fail', () {
    final codec=EncryptedJsonCodec(List.generate(32,(i)=>i));
    final value={'name':'Anak Dummy Rahasia','nested':[1,true,null]};
    final encrypted=codec.encode(value);
    expect(codec.decode(encrypted),value);
    expect(codec.encode(value),isNot(encrypted));
    expect(encrypted, isNot(contains('Anak Dummy')));
    expect(()=>EncryptedJsonCodec(List.filled(32,1)).decode(encrypted),throwsA(anything));
    final modified='${encrypted.substring(0,encrypted.length-3)}AAAA';
    expect(()=>codec.decode(modified),throwsA(anything));
  });
  test('encrypted sembast file survives reopen and does not contain plaintext', () async {
    final dir=await Directory('.dart_tool').createTemp('encrypted-');
    final path='${dir.path}/encrypted.db';
    final codec=encryptedSembastCodec(List.generate(32,(i)=>i));
    var db=await databaseFactoryIo.openDatabase(path,codec:codec);
    final record=stringMapStoreFactory.store('mvp').record('state');
    await record.put(db,{'name':'Anak Dummy Rahasia'});
    await db.close();
    expect(File(path).readAsStringSync(),isNot(contains('Anak Dummy Rahasia')));
    db=await databaseFactoryIo.openDatabase(path,codec:codec);
    expect((await record.get(db))!['name'],'Anak Dummy Rahasia');
    await db.close();
  });
}
