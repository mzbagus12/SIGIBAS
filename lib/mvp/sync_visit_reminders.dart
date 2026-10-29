import 'dart:convert';

typedef ReminderSchedule = Future<bool> Function(String child, String date);
typedef ReminderCancel = Future<bool> Function(String child);

Future<bool> reconcileVisitReminders(
  Map<String, dynamic> state,
  Map<String, String> ledger,
  ReminderSchedule schedule,
  ReminderCancel cancel, {
  Map<String, dynamic> Function()? currentState,
}) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    final before = jsonEncode([state['children'], state['visits']]);
    final ok = await _reconcileOnce(state, ledger, schedule, cancel);
    if (!ok) return false;
    if (currentState == null) return true;
    final latest = currentState();
    if (before == jsonEncode([latest['children'], latest['visits']])) {
      return true;
    }
    state = latest;
  }
  return false;
}

Future<bool> _reconcileOnce(
  Map<String, dynamic> state,
  Map<String, String> ledger,
  ReminderSchedule schedule,
  ReminderCancel cancel,
) async {
  final children = state['children'] as Map? ?? {};
  final visits = state['visits'] as Map? ?? {};
  final ids = {...children.keys.cast<String>(), ...ledger.keys};
  var success = true;
  for (final id in ids) {
    final child = children[id];
    final date = visits[id]?['date'];
    final desired =
        child == null || child['archived'] == true || date is! String
        ? '-'
        : date;
    if (ledger[id] == desired ||
        (ledger[id] == null && desired == '-' && child?['archived'] != true)) {
      continue;
    }
    try {
      final ok = desired == '-'
          ? await cancel(id)
          : await schedule(id, desired);
      if (ok) {
        ledger[id] = desired;
      } else {
        success = false;
      }
    } catch (_) {
      success = false;
    }
  }
  return success;
}
