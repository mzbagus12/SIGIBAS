import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../engine/sha256.dart';

// Android debug can reach the computer's loopback via adb reverse tcp:8768 tcp:8768.
const _serverUrl = String.fromEnvironment(
  'SIGIBAS_SERVER_URL',
  defaultValue: 'http://127.0.0.1:8768',
);
const _certificatePin = String.fromEnvironment('SIGIBAS_TLS_SHA256');
bool get demoSyncSupported =>
    Platform.isAndroid &&
    (kDebugMode ||
        (_serverUrl.startsWith('https://127.0.0.1:') &&
            RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(_certificatePin)));

Future<Map<String, dynamic>> sendDemoRequest(
  String role,
  String path,
  Map<String, dynamic> body,
) {
  if (!demoSyncSupported) {
    return Future.error(
      StateError('Pengiriman lokal hanya untuk Android debug.'),
    );
  }
  return sendLocalDemoRequest(role, path, body);
}

Future<Map<String, dynamic>> sendLocalDemoRequest(
  String role,
  String path,
  Map<String, dynamic> body, {
  Uri? endpoint,
  String? expectedFingerprint,
}) async {
  final base = endpoint ?? Uri.parse(_serverUrl);
  final pin = (expectedFingerprint ?? _certificatePin).toLowerCase();
  if (!['http', 'https'].contains(base.scheme) ||
      (base.scheme == 'https' && !RegExp(r'^[a-f0-9]{64}$').hasMatch(pin)) ||
      (base.scheme == 'http' && !kDebugMode) ||
      base.host != '127.0.0.1' ||
      base.userInfo.isNotEmpty ||
      base.hasQuery ||
      base.hasFragment ||
      (base.path.isNotEmpty && base.path != '/') ||
      !((role == 'kader' && path == '/revisions') ||
          (role == 'gizi' && path == '/review') ||
          (['kader', 'gizi', 'pemerintah'].contains(role) &&
              [
                '/sync-login',
                '/sync',
                '/sync-logout',
                '/sync-password',
                '/security-events',
              ].contains(path)))) {
    throw StateError('Endpoint atau operasi demo lokal tidak diizinkan.');
  }
  final client = HttpClient(
    context: base.scheme == 'https'
        ? SecurityContext(withTrustedRoots: false)
        : null,
  )..connectionTimeout = const Duration(seconds: 5);
  if (base.scheme == 'https') {
    client.badCertificateCallback = (cert, host, port) =>
        host == '127.0.0.1' && sha256(cert.der) == pin;
  }
  client.findProxy = (_) => 'DIRECT';
  try {
    return await (() async {
      final request = await client.postUrl(base.resolve(path));
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.headers.set('X-Demo-Role', role);
      request.write(jsonEncode(body));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw StateError('Permintaan demo ditolak.');
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > (path == '/sync' ? 1048576 : 16384)) {
          throw const FormatException('Respons terlalu besar.');
        }
      }
      final value = jsonDecode(utf8.decode(bytes));
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Respons tidak valid.');
      }
      return value;
    })().timeout(const Duration(seconds: 7));
  } finally {
    client.close(force: true);
  }
}
