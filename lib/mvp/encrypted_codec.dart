import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:sembast/sembast.dart';

/// AES-256-GCM authenticated storage. Key is supplied by platform secure storage.
class EncryptedJsonCodec extends Codec<Object?, String> {
  final SecretKeyData key;
  final DartAesGcm cipher = DartAesGcm.with256bits();
  EncryptedJsonCodec(List<int> bytes)
    : key = SecretKeyData(List<int>.from(bytes)) {
    if (bytes.length != 32) throw ArgumentError('Storage key must be 32 bytes');
  }
  @override
  Converter<Object?, String> get encoder => _Encrypt(this);
  @override
  Converter<String, Object?> get decoder => _Decrypt(this);
}

class _Encrypt extends Converter<Object?, String> {
  final EncryptedJsonCodec codec;
  _Encrypt(this.codec);
  @override
  String convert(Object? input) {
    final box = codec.cipher.encryptSync(
      utf8.encode(jsonEncode(input)),
      secretKeyData: codec.key,
      aad: utf8.encode('sigibas-storage-v2'),
    );
    return base64Encode(box.concatenation());
  }
}

class _Decrypt extends Converter<String, Object?> {
  final EncryptedJsonCodec codec;
  _Decrypt(this.codec);
  @override
  Object? convert(String input) {
    final box = SecretBox.fromConcatenation(
      base64Decode(input),
      nonceLength: 12,
      macLength: 16,
    );
    return jsonDecode(
      utf8.decode(
        codec.cipher.decryptSync(
          box,
          secretKeyData: codec.key,
          aad: utf8.encode('sigibas-storage-v2'),
        ),
      ),
    );
  }
}

SembastCodec encryptedSembastCodec(List<int> key) => SembastCodec(
  signature: 'sigibas-aes256gcm-v2',
  codec: EncryptedJsonCodec(key),
);
