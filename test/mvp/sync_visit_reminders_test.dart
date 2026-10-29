import 'package:flutter_test/flutter_test.dart';
import 'package:sigibas_rasp/mvp/sync_visit_reminders.dart';

void main() {
  test(
    'jadwal berubah dijadwalkan sekali, arsip membatalkan, gagal dicoba lagi',
    () async {
      final calls = <String>[];
      final ledger = <String, String>{};
      var fail = false;
      Future<bool> schedule(String id, String date) async {
        calls.add('schedule:$id:$date');
        return !fail;
      }

      Future<bool> cancel(String id) async {
        calls.add('cancel:$id');
        return !fail;
      }

      var state = <String, dynamic>{
        'children': {
          'a': <String, dynamic>{'name': 'Dummy'},
        },
        'visits': {
          'a': {'date': '2026-11-01'},
        },
      };
      Future<bool> run() =>
          reconcileVisitReminders(state, ledger, schedule, cancel);
      expect(await run(), true);
      expect(await run(), true);
      expect(calls, ['schedule:a:2026-11-01']);
      state['visits']['a']['date'] = '2026-11-02';
      fail = true;
      expect(await run(), false);
      expect(ledger['a'], '2026-11-01');
      fail = false;
      expect(await run(), true);
      expect(ledger['a'], '2026-11-02');
      state['children']['a']['archived'] = true;
      expect(await run(), true);
      expect(calls.last, 'cancel:a');
      expect(await run(), true);
      expect(calls.where((c) => c == 'cancel:a').length, 1);
    },
  );
  test(
    'pengarsipan saat penjadwalan membatalkan pengingat yang baru dibuat',
    () async {
      final ledger = <String, String>{};
      final calls = <String>[];
      var state = <String, dynamic>{
        'children': {
          'a': <String, dynamic>{'archived': false},
        },
        'visits': {
          'a': {'date': '2026-11-01'},
        },
      };
      final initial = {
        'children': {
          'a': <String, dynamic>{'archived': false},
        },
        'visits': {
          'a': {'date': '2026-11-01'},
        },
      };
      final result = await reconcileVisitReminders(
        initial,
        ledger,
        (id, date) async {
          calls.add('schedule:$id');
          state['children']['a']['archived'] = true;
          return true;
        },
        (id) async {
          calls.add('cancel:$id');
          return true;
        },
        currentState: () => state,
      );
      expect(result, true);
      expect(calls, ['schedule:a', 'cancel:a']);
      expect(ledger['a'], '-');
    },
  );
}
