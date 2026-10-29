import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigibas_rasp/mvp/demo_sync_io.dart';
import 'package:sigibas_rasp/engine/sha256.dart';

void main() {
  test(
    'transport lokal mengirim JSON dan role tanpa mengikuti redirect',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final endpoint = Uri.parse('http://127.0.0.1:${server.port}');
      final handled = server.first.then((request) async {
        expect(request.uri.path, '/revisions');
        expect(request.headers.value('X-Demo-Role'), 'kader');
        expect(jsonDecode(await utf8.decoder.bind(request).join()), {
          'operation_id': 'op-test',
        });
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'revision_id': 'demo-1', 'status': 'pending'}),
        );
        await request.response.close();
      });
      expect(
        await sendLocalDemoRequest('kader', '/revisions', {
          'operation_id': 'op-test',
        }, endpoint: endpoint),
        {'revision_id': 'demo-1', 'status': 'pending'},
      );
      await handled;
    },
  );
  test('endpoint publik dan peran/rute lain ditolak sebelum koneksi', () async {
    await expectLater(
      sendLocalDemoRequest(
        'kader',
        '/revisions',
        {},
        endpoint: Uri.parse('http://example.com'),
      ),
      throwsStateError,
    );
    await expectLater(
      sendLocalDemoRequest('pemerintah', '/revisions', {}),
      throwsStateError,
    );
    await expectLater(
      sendLocalDemoRequest('gizi', '/aggregate', {}),
      throwsStateError,
    );
  });
  test('respons redirect tidak diterima sebagai ACK', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final handled = server.first.then((request) async {
      await request.drain<void>();
      request.response.statusCode = 302;
      request.response.headers.set('location', 'http://example.com');
      await request.response.close();
    });
    await expectLater(
      sendLocalDemoRequest(
        'gizi',
        '/review',
        {},
        endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
      ),
      throwsStateError,
    );
    await handled;
  });
  test(
    'TLS accepts exact certificate pin and rejects mismatch before POST',
    () async {
      final openssl = Platform.isWindows
          ? r'C:\Program Files\Git\usr\bin\openssl.exe'
          : '/usr/bin/openssl';
      if (!File(openssl).existsSync()) {
        markTestSkipped('OpenSSL unavailable');
        return;
      }
      final dir = await Directory.systemTemp.createTemp('sigibas-tls-test-');
      addTearDown(() => dir.delete(recursive: true));
      final cert = '${dir.path}/cert.pem', key = '${dir.path}/key.pem';
      final generated = await Process.run(openssl, [
        'req',
        '-x509',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-keyout',
        key,
        '-out',
        cert,
        '-days',
        '2',
        '-subj',
        '/CN=127.0.0.1',
        '-addext',
        'subjectAltName=IP:127.0.0.1',
      ]);
      expect(generated.exitCode, 0);
      final pem = File(cert).readAsStringSync();
      final der = base64Decode(
        pem
            .split('-----')[2]
            .replaceAll(RegExp(r'\s'), ' ')
            .trim()
            .replaceAll(' ', ''),
      );
      final pin = sha256(der);
      final context = SecurityContext()
        ..useCertificateChain(cert)
        ..usePrivateKey(key);
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      addTearDown(() => server.close(force: true));
      var accepted = 0;
      server.listen((request) async {
        accepted++;
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"ack":[]}');
        await request.response.close();
      }, onError: (Object _) {});
      final endpoint = Uri.parse('https://127.0.0.1:${server.port}');
      await expectLater(
        sendLocalDemoRequest(
          'kader',
          '/sync',
          {},
          endpoint: endpoint,
          expectedFingerprint: '0' * 64,
        ),
        throwsA(isA<HandshakeException>()),
      );
      expect(accepted, 0);
      expect(
        await sendLocalDemoRequest(
          'kader',
          '/sync',
          {},
          endpoint: endpoint,
          expectedFingerprint: pin,
        ),
        {'ack': []},
      );
      expect(accepted, 1);
    },
  );
}
