import 'package:flutter_test/flutter_test.dart';
import 'package:sigibas_rasp/mvp/visit_notification.dart';

void main() {
  test('jadwal pukul 09 WIB mempunyai instant UTC benar dan ID stabil', () {
    expect(
      visitReminderTime('2026-11-01').toUtc(),
      DateTime.utc(2026, 11, 1, 2),
    );
    expect(visitNotificationId('child:a'), visitNotificationId('child:a'));
    expect(
      visitNotificationId('child:a'),
      isNot(visitNotificationId('child:b')),
    );
    expect(() => visitReminderTime('2026-02-30'), throwsFormatException);
  });
}
