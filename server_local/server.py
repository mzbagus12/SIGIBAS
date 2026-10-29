"""Demo server: localhost only, synthetic inputs, no real authentication."""
import argparse
import json
import secrets
import time
import hmac
import hashlib
import ssl
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from service import DemoError, DemoService
from sync_store import SyncStore, SyncConflict


class Handler(BaseHTTPRequestHandler):
    server_version = 'SI-GIBAS-Demo/0.1'
    demo_origin = 'http://127.0.0.1:8767'
    def log_message(self, format, *args):
        pass  # Avoid logging request data.

    def send_json(self, status, obj):
        raw = json.dumps(obj, allow_nan=False).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Cache-Control', 'no-store')
        if self.headers.get('Origin') == self.demo_origin:
            self.send_header('Access-Control-Allow-Origin', self.demo_origin)
            self.send_header('Vary', 'Origin')
        self.send_header('Content-Length', str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_OPTIONS(self):
        if (self.path not in ('/revisions', '/review', '/sync-login', '/sync', '/sync-logout', '/sync-password', '/security-events') or
                self.headers.get('Origin') != self.demo_origin or
                self.headers.get('Access-Control-Request-Method') != 'POST'):
            self.send_json(403, {'error': 'Origin demo tidak diizinkan.'})
            return
        self.send_response(204)
        self.send_header('Access-Control-Allow-Origin', self.demo_origin)
        self.send_header('Access-Control-Allow-Methods', 'POST')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, X-Demo-Role')
        self.send_header('Vary', 'Origin')
        self.send_header('Content-Length', '0')
        self.end_headers()

    def allowed(self, roles):
        # Demo roles are deliberately spoofable; never use for real data.
        if self.headers.get('X-Demo-Role') not in roles:
            self.send_json(403, {'error': 'Peran demo tidak diizinkan.'})
            return False
        return True

    def body(self):
        length = int(self.headers.get('Content-Length', '0'))
        if length <= 0 or length > (1048576 if self.path == '/sync' else 4096):
            raise DemoError('Ukuran data tidak valid.')
        value = json.loads(self.rfile.read(length).decode('utf-8'))
        if not isinstance(value, dict):
            raise DemoError('Data harus berupa objek.')
        return value

    def do_GET(self):
        if self.path == '/aggregate' and self.allowed({'pemerintah'}):
            self.send_json(200, self.server.service.aggregate())
        elif self.path == '/revisions' and self.allowed({'gizi'}):
            self.send_json(200, {'revisions': self.server.service.list_revisions()})
        elif self.path not in ('/aggregate', '/revisions'):
            self.send_json(404, {'error':'Rute tidak ditemukan.'})

    def do_POST(self):
        if self.path not in ('/revisions', '/review', '/sync-login', '/sync', '/sync-logout', '/sync-password', '/security-events'):
            self.send_json(404, {'error':'Rute tidak ditemukan.'})
            return
        try:
            body = self.body()
            origin = self.headers.get('Origin')
            if origin is not None and origin != self.demo_origin:
                self.send_json(403, {'error': 'Origin demo tidak diizinkan.'})
                return
            if self.path == '/sync-login':
                user, pin = body.get('user'), body.get('pin')
                if not isinstance(user, str) or not isinstance(pin, str):
                    raise DemoError('Akun tidak valid')
                failures, until = self.server.login_failures.get(user, (0, 0))
                if until > time.monotonic():
                    self.send_json(429, {'error': 'Tunggu sebelum mencoba lagi.'})
                    return
                row = self.server.sync_store.db.execute('SELECT salt,digest FROM sync_accounts WHERE user=?', (user,)).fetchone()
                if row is None or not hmac.compare_digest(row[1], hashlib.pbkdf2_hmac('sha256', pin.encode(), bytes.fromhex(row[0]), 120000).hex()):
                    failures += 1
                    self.server.login_failures[user] = (failures, time.monotonic() + 30 if failures >= 5 else 0)
                    self.send_json(403, {'error': 'Akun demo tidak sesuai.'})
                    return
                self.server.login_failures.pop(user, None)
                now = time.monotonic()
                self.server.sessions = {k:v for k,v in self.server.sessions.items() if v[1] > now}
                if len(self.server.sessions) >= 100:
                    self.send_json(429, {'error': 'Terlalu banyak sesi demo.'})
                    return
                token = secrets.token_urlsafe(32)
                self.server.sessions[token] = (user, now + 1800)
                self.send_json(200, {'token': token, 'role': user, 'expiresIn': 1800})
                return
            if self.path in ('/sync', '/sync-logout', '/sync-password', '/security-events'):
                token = body.get('token')
                session = self.server.sessions.get(token) if isinstance(token, str) else None
                if session is None or session[1] <= time.monotonic():
                    self.send_json(403, {'error': 'Sesi sinkronisasi berakhir.'})
                    return
                if self.path == '/security-events':
                    events = body.get('events')
                    allowed_codes = {'root','emulator','hook','debugger','signature','root_detected','emulator_detected','hook_detected','debugger_attached','signature_mismatch'}
                    if not isinstance(events,list) or len(events)>100:
                        raise DemoError('Daftar kejadian tidak valid')
                    ack=[]
                    with self.server.sync_store.db:
                        for event in events:
                            if not isinstance(event,dict) or set(event) != {'eventId','atDevice','findings'} or not isinstance(event['eventId'],str) or not 1<=len(event['eventId'])<=150 or not isinstance(event['atDevice'],str) or not 1<=len(event['atDevice'])<=40 or not isinstance(event['findings'],list) or not 1<=len(event['findings'])<=10 or any(not isinstance(v,str) or v not in allowed_codes for v in event['findings']):
                                raise DemoError('Kejadian tidak valid')
                            raw=json.dumps(event,sort_keys=True)
                            prior=self.server.sync_store.db.execute('SELECT value FROM security_events WHERE user=? AND id=?',(session[0],event['eventId'])).fetchone()
                            if prior and prior[0] != raw:
                                raise DemoError('ID kejadian digunakan ulang')
                            self.server.sync_store.db.execute('INSERT OR IGNORE INTO security_events VALUES (?,?,?)',(session[0],event['eventId'],raw))
                            ack.append(event['eventId'])
                    self.send_json(200, {'ack':ack})
                    return
                if self.path == '/sync-logout':
                    self.server.sessions.pop(token, None)
                    self.send_json(200, {'revoked': True})
                    return
                if self.path == '/sync-password':
                    old, new = body.get('oldPin'), body.get('newPin')
                    row = self.server.sync_store.db.execute('SELECT salt,digest FROM sync_accounts WHERE user=?', (session[0],)).fetchone()
                    if not isinstance(old, str) or not isinstance(new, str) or not 8 <= len(new) <= 128 or not hmac.compare_digest(row[1], hashlib.pbkdf2_hmac('sha256', old.encode(), bytes.fromhex(row[0]), 120000).hex()):
                        raise DemoError('PIN lama salah atau PIN baru kurang dari 8 karakter')
                    salt = secrets.token_bytes(16)
                    with self.server.sync_store.db:
                        self.server.sync_store.db.execute('UPDATE sync_accounts SET salt=?,digest=? WHERE user=?', (salt.hex(), hashlib.pbkdf2_hmac('sha256', new.encode(), salt, 120000).hex(), session[0]))
                    self.server.sessions = {k:v for k,v in self.server.sessions.items() if v[0] != session[0]}
                    self.send_json(200, {'revoked': True})
                    return
                if body.get('synthetic') is not True:
                    raise DemoError('Data sintetis wajib.')
                self.send_json(200, self.server.sync_store.exchange(session[0], body.get('changes'), body.get('cursor'), body.get('limit')))
                return
            if not self.allowed({'kader'} if self.path == '/revisions' else {'gizi'}):
                return
            if self.path == '/revisions':
                if set(body) != {'operation_id', 'payload'}:
                    raise DemoError('Field permintaan tidak valid.')
                result = self.server.service.submit(body['operation_id'], body['payload'])
            else:
                if set(body) != {'operation_id','revision_id','status','note'}:
                    raise DemoError('Field permintaan tidak valid.')
                result = self.server.service.review(body['operation_id'], body['revision_id'], body['status'], body['note'])
            self.send_json(200, result)
        except SyncConflict as e:
            self.send_json(409, {'error': str(e)})
        except (DemoError, ValueError, UnicodeError, json.JSONDecodeError) as e:
            self.send_json(400, {'error': str(e)})


def create_server(database, port=8768, tls_cert=None, tls_key=None):
    server = HTTPServer(('127.0.0.1', port), Handler)
    if (tls_cert is None) != (tls_key is None):
        server.server_close()
        raise ValueError('Sertifikat dan private key TLS harus diberikan bersama')
    if tls_cert is not None:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(str(tls_cert), str(tls_key))
        server.socket = context.wrap_socket(server.socket, server_side=True)
    server.service = DemoService(database)
    server.sync_store = SyncStore(str(database) + '.sync.sqlite')
    server.sessions = {}
    server.login_failures = {}
    with server.sync_store.db:
        server.sync_store.db.execute('CREATE TABLE IF NOT EXISTS security_events (user TEXT,id TEXT,value TEXT,PRIMARY KEY(user,id))')
        server.sync_store.db.execute('CREATE TABLE IF NOT EXISTS sync_accounts (user TEXT PRIMARY KEY,salt TEXT,digest TEXT)')
        for user, pin in (('kader','1111'),('gizi','2222'),('pemerintah','3333')):
            salt = secrets.token_bytes(16)
            server.sync_store.db.execute('INSERT OR IGNORE INTO sync_accounts VALUES (?,?,?)', (user,salt.hex(),hashlib.pbkdf2_hmac('sha256',pin.encode(),salt,120000).hex()))
    old_close = server.server_close
    def close():
        old_close()
        server.service.close()
        server.sync_store.close()
    server.server_close = close
    return server


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Demo lokal: data sintetis saja, bukan layanan produksi')
    parser.add_argument('--database', required=True, help='Path database sintetis lokal')
    parser.add_argument('--port', type=int, default=8768)
    parser.add_argument('--tls-cert', help='Sertifikat PEM lokal')
    parser.add_argument('--tls-key', help='Private key PEM lokal, jangan commit')
    args = parser.parse_args()
    server = create_server(Path(args.database), args.port, args.tls_cert, args.tls_key)
    print('DEMO DATA SINTETIS SAJA: %s://127.0.0.1:%d' % ('https' if args.tls_cert else 'http', server.server_port), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
