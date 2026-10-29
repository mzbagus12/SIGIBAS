import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../engine/engine.dart';
import '../engine/sha256.dart';

tz.TZDateTime visitReminderTime(String date) {
  final civil = CivilDate.parse(date);
  tzdata.initializeTimeZones();
  final parts = civil.iso.split('-').map(int.parse).toList();
  return tz.TZDateTime(
    tz.getLocation('Asia/Jakarta'),
    parts[0],
    parts[1],
    parts[2],
    9,
  );
}

int visitNotificationId(String child) =>
    int.parse(sha256(utf8.encode(child)).substring(0, 7), radix: 16);
final _plugin = FlutterLocalNotificationsPlugin();
bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
Future<void> _initialize() => _plugin.initialize(
  settings: const InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  ),
);

Future<String> scheduleVisitNotification(
  String child,
  String date, {
  bool requestPermission = true,
}) async {
  if (!_android) {
    return 'Jadwal disimpan. Pengingat sistem tersedia di Android.';
  }
  final time = visitReminderTime(date);
  await _initialize();
  final android = _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()!;
  final allowed = requestPermission
      ? await android.requestNotificationsPermission()
      : await android.areNotificationsEnabled();
  if (allowed != true) {
    return 'Jadwal disimpan; izin notifikasi belum diberikan.';
  }
  await _plugin.cancel(id: visitNotificationId(child));
  if (!time.isAfter(DateTime.now())) {
    return 'Jadwal disimpan; waktu pengingat pukul 09.00 WIB sudah lewat.';
  }
  await _plugin.zonedSchedule(
    id: visitNotificationId(child),
    scheduledDate: time,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'kontrol',
        'Pengingat kontrol',
        channelDescription: 'Jadwal penimbangan ulang',
        importance: Importance.defaultImportance,
      ),
    ),
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    title: 'Jadwal kontrol SI-GIBAS',
    body: 'Periksa jadwal kontrol di aplikasi.',
  );
  return 'Jadwal disimpan. Pengingat Android dijadwalkan sekitar pukul 09.00 WIB.';
}

Future<void> cancelVisitNotification(String child) async {
  if (_android) {
    await _initialize();
    await _plugin.cancel(id: visitNotificationId(child));
  }
}
