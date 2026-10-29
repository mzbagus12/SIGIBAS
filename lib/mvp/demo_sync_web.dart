// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;

const _serverUrl = String.fromEnvironment(
  'SIGIBAS_SERVER_URL',
  defaultValue: 'http://127.0.0.1:8768',
);

bool get demoSyncSupported =>
    Uri.base.scheme == 'http' &&
    Uri.base.host == '127.0.0.1' &&
    Uri.base.port == 8767;

Future<Map<String, dynamic>> sendDemoRequest(
  String role,
  String path,
  Map<String, dynamic> body,
) async {
  final base = Uri.parse(_serverUrl);
  if (!['http', 'https'].contains(base.scheme) ||
      base.host != '127.0.0.1' ||
      base.userInfo.isNotEmpty ||
      base.hasQuery ||
      base.hasFragment ||
      (base.path.isNotEmpty && base.path != '/') ||
      !demoSyncSupported ||
      ![
        '/revisions',
        '/review',
        '/sync-login',
        '/sync',
        '/sync-logout',
        '/sync-password',
        '/security-events',
      ].contains(path) ||
      !['kader', 'gizi', 'pemerintah'].contains(role)) {
    throw StateError(
      'Pengiriman demo hanya tersedia pada localhost yang ditetapkan.',
    );
  }
  final response = await html.HttpRequest.request(
    base.resolve(path).toString(),
    method: 'POST',
    requestHeaders: {'Content-Type': 'application/json', 'X-Demo-Role': role},
    sendData: jsonEncode(body),
  );
  if (response.status != 200) throw StateError('Permintaan demo ditolak.');
  final data = jsonDecode(response.responseText ?? '');
  if (data is! Map<String, dynamic>) {
    throw const FormatException('Respons tidak valid.');
  }
  return data;
}
