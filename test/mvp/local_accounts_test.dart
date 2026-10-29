import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sigibas_rasp/mvp/local_accounts.dart';

void main() {
  test('PIN salt/hash, akun tunggal, pembatasan persisten dan pemulihan setelah waktu tunggu', () async {
    final db = await databaseFactoryMemory.openDatabase('auth');
    final auth = LocalAccounts(db);
    await expectLater(auth.configure({'kader': '1111'}), throwsFormatException);
    await auth.configure({
      'kader': '123456',
      'gizi': '234567',
      'pemerintah': '345678',
    });
    final stored = (await LocalAccounts.record.get(db)).toString();
    expect(stored.contains('123456'), false);
    await expectLater(
      auth.configure({
        'kader': '123456',
        'gizi': '234567',
        'pemerintah': '345678',
      }),
      throwsStateError,
    );
    final now = DateTime(2026, 10, 29);
    for (var i = 0; i < 5; i++) {
      expect(await auth.login('kader', 'wrong', now: now), isNull);
    }
    await expectLater(
      LocalAccounts(db).login('kader', '123456', now: now),
      throwsStateError,
    );
    expect(
      await auth.login(
        'kader',
        '123456',
        now: now.add(const Duration(seconds: 61)),
      ),
      'Kader',
    );
    expect(
      await auth.login(
        'gizi',
        '234567',
        now: now.add(const Duration(seconds: 62)),
      ),
      'BadanGizi',
    );
    await db.close();
  });
}
