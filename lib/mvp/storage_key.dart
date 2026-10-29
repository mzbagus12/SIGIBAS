import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _secureStorage = FlutterSecureStorage();
const _storageKey = 'sigibas.database.aes256.v2';
Future<List<int>> loadDatabaseKey({required bool encryptedExists}) async {
  var encoded = await _secureStorage.read(key: _storageKey);
  if (encoded == null) {
    if (encryptedExists) {
      throw StateError(
        'Kunci penyimpanan tidak tersedia. Database dipertahankan; jangan hapus data aplikasi.',
      );
    }
    final random = Random.secure();
    encoded = base64Encode(List.generate(32, (_) => random.nextInt(256)));
    await _secureStorage.write(key: _storageKey, value: encoded);
    if (await _secureStorage.read(key: _storageKey) != encoded) {
      throw StateError('Kunci gagal disimpan. Database tidak direset.');
    }
  }
  final key = base64Decode(encoded);
  if (key.length != 32) {
    throw const FormatException('Kunci penyimpanan tidak valid');
  }
  return key;
}
