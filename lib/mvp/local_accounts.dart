import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:sembast/sembast.dart';

class LocalAccounts {
  final Database db;
  LocalAccounts(this.db);
  static const roles = {
    'kader': 'Kader',
    'gizi': 'BadanGizi',
    'pemerintah': 'Pemerintah',
  };
  static final record = stringMapStoreFactory
      .store('local_auth')
      .record('accounts');
  static final algorithm = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 100000,
    bits: 256,
  );
  Future<bool> configured() async => await record.get(db) != null;
  Future<String> hash(String pin, List<int> salt) async => base64Encode(
    await (await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    )).extractBytes(),
  );
  Future<void> configure(Map<String, String> pins) async {
    if (pins.length != 3 ||
        roles.keys.any(
          (id) => !RegExp(r'^[0-9]{6,12}$').hasMatch(pins[id] ?? ''),
        ) ||
        pins.values.toSet().length != 3) {
      throw const FormatException(
        'Gunakan PIN berbeda untuk setiap peran, 6–12 angka.',
      );
    }
    final accounts = <String, dynamic>{};
    for (final id in roles.keys) {
      final salt = List.generate(16, (_) => Random.secure().nextInt(256));
      accounts[id] = {
        'salt': base64Encode(salt),
        'hash': await hash(pins[id]!, salt),
      };
    }
    await db.transaction((txn) async {
      if (await record.get(txn) != null) {
        throw StateError('Akun sudah disiapkan');
      }
      await record.put(txn, {'accounts': accounts, 'failures': 0, 'until': 0});
    });
  }

  Future<String?> login(String id, String pin, {DateTime? now}) async {
    final at = (now ?? DateTime.now()).millisecondsSinceEpoch;
    return db.transaction((txn) async {
      final saved = await record.get(txn);
      final data = saved == null ? null : Map<String, dynamic>.from(saved);
      if (data == null) throw StateError('Siapkan akun terlebih dahulu');
      if ((data['until'] as int) > at) {
        throw StateError('Terlalu banyak percobaan. Tunggu satu menit.');
      }
      final account = (data['accounts'] as Map)[id];
      final salt = account == null
          ? List<int>.filled(16, 0)
          : base64Decode(account['salt']);
      final derived = await hash(pin, salt);
      final expected = account?['hash'] as String? ?? '';
      var difference = derived.length ^ expected.length;
      for (var i = 0; i < derived.length; i++) {
        difference |=
            derived.codeUnitAt(i) ^
            (i < expected.length ? expected.codeUnitAt(i) : 0);
      }
      if (account == null || difference != 0) {
        final failures = (data['failures'] as int) + 1;
        data['failures'] = failures >= 5 ? 0 : failures;
        data['until'] = failures >= 5 ? at + 60000 : 0;
        await record.put(txn, data);
        return null;
      }
      data['failures'] = 0;
      data['until'] = 0;
      await record.put(txn, data);
      return roles[id];
    });
  }
}
