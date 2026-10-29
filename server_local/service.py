"""Local synthetic-only persistence. Not authentication or production health software."""
import hashlib
import json
import math
import re
import sqlite3


class DemoError(ValueError):
    pass


class DemoService:
    def __init__(self, path):
        self.db = sqlite3.connect(str(path), check_same_thread=False)
        self.db.executescript('''
            CREATE TABLE IF NOT EXISTS revisions (
              revision_id TEXT PRIMARY KEY, child_id TEXT NOT NULL,
              weight REAL NOT NULL, height REAL NOT NULL, previous_id TEXT UNIQUE,
              status TEXT NOT NULL, note TEXT NOT NULL DEFAULT '');
            CREATE TABLE IF NOT EXISTS commands (
              operation_id TEXT PRIMARY KEY, digest TEXT NOT NULL, result TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS audit (
              seq INTEGER PRIMARY KEY AUTOINCREMENT, revision_id TEXT NOT NULL,
              operation TEXT NOT NULL, status TEXT NOT NULL);
        ''')

    def close(self):
        self.db.close()

    @staticmethod
    def _id(value):
        if not isinstance(value, str) or not re.fullmatch(r'demo-[a-z0-9-]{1,60}', value):
            raise DemoError('ID harus memakai awalan demo dan huruf kecil/angka.')
        return value

    def _execute(self, operation, command, work):
        if not isinstance(operation, str) or not re.fullmatch(r'[a-z0-9-]{1,80}', operation):
            raise DemoError('ID operasi tidak valid.')
        digest = hashlib.sha256(json.dumps(command, sort_keys=True, allow_nan=False).encode()).hexdigest()
        with self.db:
            prior = self.db.execute('SELECT digest, result FROM commands WHERE operation_id=?', (operation,)).fetchone()
            if prior:
                if prior[0] != digest:
                    raise DemoError('ID operasi telah digunakan dengan data lain.')
                return json.loads(prior[1])
            result = work()
            self.db.execute('INSERT INTO commands VALUES (?, ?, ?)', (operation, digest, json.dumps(result)))
            return result

    def submit(self, operation, payload):
        required = {'synthetic', 'child_id', 'revision_id', 'weight', 'height'}
        if not isinstance(payload, dict) or set(payload) not in (required, required | {'previous_id'}) or payload['synthetic'] is not True:
            raise DemoError('Hanya data sintetis dengan field yang ditentukan diterima.')
        child = self._id(payload['child_id'])
        revision = self._id(payload['revision_id'])
        previous = self._id(payload['previous_id']) if 'previous_id' in payload else None
        for key in ('weight', 'height'):
            value = payload[key]
            if isinstance(value, bool) or not isinstance(value, (float, int)) or not math.isfinite(value) or value <= 0:
                raise DemoError('Berat dan tinggi harus berupa angka positif.')
        def write():
            if previous:
                parent = self.db.execute('SELECT child_id,status FROM revisions WHERE revision_id=?', (previous,)).fetchone()
                successor = self.db.execute('SELECT 1 FROM revisions WHERE previous_id=?', (previous,)).fetchone()
                if parent is None or parent[0] != child or parent[1] not in ('approved', 'rejected') or successor:
                    raise DemoError('Revisi sebelumnya tidak dapat dikoreksi.')
            try:
                self.db.execute('INSERT INTO revisions (revision_id,child_id,weight,height,status,previous_id) VALUES (?,?,?,?,?,?)',
                                (revision, child, payload['weight'], payload['height'], 'pending', previous))
            except sqlite3.IntegrityError as e:
                raise DemoError('Revisi sudah ada; operasi ditolak.') from e
            self.db.execute('INSERT INTO audit(revision_id,operation,status) VALUES (?,?,?)', (revision, operation, 'pending'))
            return {'revision_id': revision, 'status': 'pending'}
        return self._execute(operation, {'action': 'submit', 'payload': payload}, write)

    def review(self, operation, revision, status, note):
        self._id(revision)
        if status not in ('approved', 'rejected') or not isinstance(note, str) or len(note) > 500:
            raise DemoError('Keputusan atau catatan tidak valid.')
        note = note.strip()
        if status == 'rejected' and not note:
            raise DemoError('Catatan penolakan wajib.')
        def write():
            row = self.db.execute('SELECT status FROM revisions WHERE revision_id=?', (revision,)).fetchone()
            if row is None or row[0] != 'pending':
                raise DemoError('Revisi tidak tersedia atau tidak menunggu review.')
            self.db.execute('UPDATE revisions SET status=?, note=? WHERE revision_id=?', (status, note, revision))
            self.db.execute('INSERT INTO audit(revision_id,operation,status) VALUES (?,?,?)', (revision, operation, status))
            return {'revision_id': revision, 'status': status}
        return self._execute(operation, {'action': 'review', 'revision': revision, 'status': status, 'note': note}, write)

    def list_revisions(self):
        return [dict(zip(('revision_id','child_id','weight','height','status','note'), r))
                for r in self.db.execute('SELECT revision_id,child_id,weight,height,status,note FROM revisions ORDER BY revision_id')]

    def aggregate(self):
        rows = self.db.execute('SELECT revision_id,previous_id,status FROM revisions').fetchall()
        nodes = {revision: (previous, status) for revision, previous, status in rows}
        parents = {previous for _, previous, _ in rows if previous is not None}
        count = 0
        for revision in nodes.keys() - parents:
            current = revision
            while current is not None:
                previous, status = nodes[current]
                if status == 'approved':
                    count += 1
                    break
                current = previous
        return {'approved_count': count}
