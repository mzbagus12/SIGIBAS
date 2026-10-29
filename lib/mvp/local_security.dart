import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

List<String> evaluateLocalSecurity(
  Map<String, dynamic> result, {
  required bool debugMode,
}) => [
  for (final key in ['root', 'emulator', 'hook', 'signature'])
    if (result[key] == true) key,
  if (!debugMode && result['debugger'] == true) 'debugger',
];
const _storage = FlutterSecureStorage();
const _eventKey = 'sigibas.local-security.events.v1';
Future<List<Map<String, dynamic>>> pendingSecurityEvents() async {
  final encoded = await _storage.read(key: _eventKey);
  if (encoded == null) return [];
  return (jsonDecode(encoded) as List)
      .map((v) => Map<String, dynamic>.from(v as Map))
      .toList();
}

Future<void> ackSecurityEvents(List<String> ids) async {
  final events = await pendingSecurityEvents();
  await _storage.write(
    key: _eventKey,
    value: jsonEncode(
      events.where((v) => !ids.contains(v['eventId'])).toList(),
    ),
  );
}

Future<void> _recordSecurityEvent(List<String> findings) async {
  final events = await pendingSecurityEvents();
  if (events.isNotEmpty &&
      jsonEncode(events.last['findings']) == jsonEncode(findings)) {
    return;
  }
  final now = DateTime.now();
  events.add({
    'eventId': 'local-${now.microsecondsSinceEpoch}',
    'atDevice': now.toIso8601String(),
    'findings': findings,
  });
  await _storage.write(
    key: _eventKey,
    value: jsonEncode(
      events.length > 100 ? events.sublist(events.length - 100) : events,
    ),
  );
}

/// Offline Android heuristics. No third-party telemetry or remote SDK startup.
class LocalSecurityGate extends StatefulWidget {
  final Widget child;
  const LocalSecurityGate({super.key, required this.child});
  @override
  State<LocalSecurityGate> createState() => _LocalSecurityGateState();
}

class _LocalSecurityGateState extends State<LocalSecurityGate>
    with WidgetsBindingObserver {
  List<String>? findings;
  String? error;
  bool checking = false;
  Timer? timer;
  bool get android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    check();
    if (android) {
      timer = Timer.periodic(const Duration(seconds: 15), (_) => check());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) check();
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> check() async {
    if (checking) return;
    checking = true;
    try {
      final result = android
          ? await const MethodChannel('sigibas/security')
                .invokeMapMethod<String, dynamic>('check')
          : <String, dynamic>{};
      if (result == null) {
        throw StateError('Pemeriksaan tidak memberikan hasil');
      }
      final detected = evaluateLocalSecurity(result, debugMode: kDebugMode);
      if (detected.isNotEmpty) await _recordSecurityEvent(detected);
      if (mounted) {
        setState(() {
          findings = detected;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Pemeriksaan keamanan lokal gagal. Data tidak direset.',
        );
      }
    } finally {
      checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (error == null && findings?.isEmpty == true) return widget.child;
    const labels = {
      'root': 'Indikasi akses root',
      'emulator': 'Lingkungan emulator',
      'hook': 'Indikasi hooking',
      'signature': 'Identitas/tanda tangan aplikasi tidak sesuai',
      'debugger': 'Debugger terhubung',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Pemeriksaan perangkat')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (findings == null && error == null)
              const CircularProgressIndicator()
            else ...[
              Text(
                error ?? 'Akses aplikasi dihentikan oleh pemeriksaan lokal.',
              ),
              for (final code in findings ?? <String>[])
                Text(labels[code] ?? code),
              const Text(
                'Pemeriksaan ini memakai indikator lokal dan dapat memiliki keterbatasan. Gunakan APK asli pada perangkat fisik yang sesuai. Tidak ada pelaporan ke layanan eksternal.',
              ),
              FilledButton(
                onPressed: check,
                child: const Text('Periksa ulang'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
