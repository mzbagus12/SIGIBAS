"""Transactional versioned record exchange for synthetic localhost testing.

Not an HTTP endpoint or authentication boundary: caller must authenticate role.
Government receives no individual records. Clinical results require server validation.
"""
import hashlib
import json
import sqlite3
import math
import re
import datetime


class SyncConflict(ValueError):
    pass


class SyncStore:
    def __init__(self, path):
        self.db = sqlite3.connect(str(path), check_same_thread=False)
        self.db.executescript('''
          CREATE TABLE IF NOT EXISTS sync_records (
            kind TEXT, id TEXT, version INTEGER NOT NULL, value TEXT NOT NULL,
            PRIMARY KEY(kind,id));
          CREATE TABLE IF NOT EXISTS sync_commands (
            operation TEXT PRIMARY KEY, digest TEXT NOT NULL);
        ''')

    def close(self):
        self.db.close()

    def aggregate(self):
        rows = {i: json.loads(v) for i, v in self.db.execute(
            "SELECT id,value FROM sync_records WHERE kind='revision'")}
        effective = {}
        parents = {v.get('previous') for v in rows.values()}
        for ident, leaf in rows.items():
            if ident in parents:
                continue
            seen = set()
            while leaf and leaf.get('status') != 'approved':
                key = leaf.get('id')
                if key in seen:
                    raise ValueError('Siklus revisi')
                seen.add(key)
                leaf = rows.get(leaf.get('previous'))
            if leaf:
                effective[leaf['measurement']] = leaf
        result = {k: {'denominator': 0, 'categories': {}} for k in
                  ('weightAge', 'heightAge', 'weightHeight')}
        for revision in effective.values():
            for kind, score in revision.get('results', {}).items():
                if kind in result and score.get('status') == 'valid' and isinstance(score.get('category'), str):
                    bucket = result[kind]
                    bucket['denominator'] += 1
                    category = score['category']
                    bucket['categories'][category] = bucket['categories'].get(category, 0) + 1
        return result

    def _validate(self, kind, ident, value, old):
        def date(raw):
            if not isinstance(raw, str) or len(raw) != 10:
                raise ValueError('Tanggal tidak valid')
            return datetime.date.fromisoformat(raw)
        if kind == 'child':
            nik = value.get('nik')
            if nik not in (None, '') and (not isinstance(nik, str) or re.fullmatch(r'000000[0-9]{10}', nik) is None):
                raise ValueError('NIK dummy tidak valid')
            if value.get('id', ident) != ident or not isinstance(value.get('name'), str) or not value['name'].strip() or len(value['name']) > 200:
                raise ValueError('Profil tidak valid')
            if value.get('sex') not in ('male', 'female') or date(value.get('birth')) > datetime.date.today():
                raise ValueError('Kelahiran/jenis kelamin tidak valid')
            if old and (old.get('birth') != value.get('birth') or old.get('sex') != value.get('sex')):
                raise ValueError('Tanggal lahir/jenis kelamin tidak dapat berubah lewat sync')
        elif kind == 'visit':
            date(value.get('date'))
            if not isinstance(value.get('note'), str) or len(value['note']) > 500:
                raise ValueError('Catatan jadwal tidak valid')
            if not self.db.execute("SELECT 1 FROM sync_records WHERE kind='child' AND id=?", (ident,)).fetchone():
                raise ValueError('Anak jadwal tidak ada')
        else:
            if not isinstance(value.get('child'), str) or not isinstance(value.get('measurement'), str) or value.get('previous') is not None and not isinstance(value.get('previous'), str):
                raise ValueError('Identitas rantai tidak valid')
            if value.get('id') != ident or value.get('status') not in ('draft','pending','approved','rejected'):
                raise ValueError('Identitas/status revisi tidak valid')
            child = self.db.execute("SELECT value FROM sync_records WHERE kind='child' AND id=?", (value.get('child'),)).fetchone()
            if child is None:
                raise ValueError('Anak revisi tidak ada')
            inputs = value.get('input')
            if not isinstance(inputs, dict) or not isinstance(value.get('results'), dict) or not isinstance(value.get('note'), str) or len(value['note']) > 2000:
                raise ValueError('Isi revisi tidak valid')
            if inputs.get('date') is not None and (date(inputs['date']) < date(json.loads(child[0])['birth']) or date(inputs['date']) > datetime.date.today()):
                raise ValueError('Tanggal ukur tidak valid')
            for key in ('weight','cm','muac','head'):
                raw = inputs.get(key)
                if raw is not None and (type(raw) not in (int,float) or not math.isfinite(raw) or raw <= 0):
                    raise ValueError('Pengukuran harus positif dan finite')
            if inputs.get('position') not in (None,'standing','recumbent') or inputs.get('oedema') not in (None,'yes','no','unknown'):
                raise ValueError('Posisi/oedema tidak valid')
            if value['status'] != 'draft' and any(inputs.get(k) is None for k in ('date','weight','cm','position','oedema')):
                raise ValueError('Pengukuran belum lengkap')
            for index, score in value['results'].items():
                if index not in ('weightAge','heightAge','weightHeight') or not isinstance(score,dict) or score.get('status') not in ('valid','missingInput','invalidInput','referenceOutOfDomain','unavailableOedema','needsReview') or score.get('category') is not None and (not isinstance(score['category'],str) or len(score['category'])>150):
                    raise ValueError('Format hasil tidak valid')
                for key in ('rawZ','roundedZ'):
                    raw=score.get(key)
                    if raw is not None and (type(raw) not in (int,float) or not math.isfinite(raw)):
                        raise ValueError('Skor tidak valid')
            previous = value.get('previous')
            if old and (old.get('previous') != previous or old.get('measurement') != value.get('measurement') or old.get('child') != value.get('child')):
                raise ValueError('Rantai revisi tidak dapat diubah')
            if previous is None:
                if value.get('measurement') != ident:
                    raise ValueError('Akar pengukuran tidak valid')
            else:
                parent = self.db.execute("SELECT value FROM sync_records WHERE kind='revision' AND id=?", (previous,)).fetchone()
                if parent is None or previous == ident:
                    raise ValueError('Induk revisi tidak ada/siklus')
                parent = json.loads(parent[0])
                if parent['child'] != value['child'] or parent['measurement'] != value.get('measurement') or parent['status'] not in ('draft','approved','rejected'):
                    raise ValueError('Induk revisi tidak sesuai')
                for other_id, raw in self.db.execute("SELECT id,value FROM sync_records WHERE kind='revision' AND id<>?", (ident,)):
                    if json.loads(raw).get('previous') == previous:
                        raise ValueError('Rantai revisi bercabang')
            for other_id, raw in self.db.execute("SELECT id,value FROM sync_records WHERE kind='revision' AND id<>?", (ident,)):
                if old and json.loads(raw).get('previous') == ident:
                    raise ValueError('Revisi bukan leaf')

    def dashboard(self):
        rows = {i: json.loads(v) for i,v in self.db.execute("SELECT id,value FROM sync_records WHERE kind='revision'")}
        children = {i: json.loads(v) for i,v in self.db.execute("SELECT id,value FROM sync_records WHERE kind='child'")}
        parents = {v.get('previous') for v in rows.values()}
        effective = {}
        for ident, leaf in rows.items():
            if ident in parents: continue
            while leaf and leaf.get('status') != 'approved':
                leaf = rows.get(leaf.get('previous'))
            if leaf: effective[leaf['measurement']] = leaf
        cells = {}
        for value in effective.values():
            village = children.get(value['child'], {}).get('village', 'Belum diisi')
            key = (value['input']['date'][:7], village)
            cell = cells.setdefault(key, {k:{'denominator':0,'categories':{}} for k in ('weightAge','heightAge','weightHeight')})
            for kind, score in value.get('results', {}).items():
                if kind in cell and score.get('status') == 'valid' and isinstance(score.get('category'),str):
                    cell[kind]['denominator'] += 1
                    cats = cell[kind]['categories']; cats[score['category']] = cats.get(score['category'],0) + 1
        areas = sorted({v for m,v in cells})
        return {'unit':'observasi pengukuran disetujui efektif',
                'cells':[{'month':m,'village':v,'aggregate':a} for (m,v),a in sorted(cells.items())],
                'areas':[{'village':v,'x':1+(i%4)*2.3,'y':1+(i//4)*2.3} for i,v in enumerate(areas)]}

    def exchange(self, role, changes, cursor=None, limit=None):
        if role not in ('kader', 'gizi', 'pemerintah') or not isinstance(changes, list) or len(changes) > 100:
            raise ValueError('Permintaan sinkronisasi tidak valid')
        if role == 'pemerintah':
            if changes:
                raise ValueError('Pemerintah tidak dapat mengubah data individu')
            return {'records': [], 'ack': [], 'aggregate': self.aggregate(), 'clinicalValidation': False, 'dashboard': self.dashboard()}
        if limit is not None and (type(limit) is not int or not 1 <= limit <= 100 or (cursor is not None and not isinstance(cursor, str))):
            raise ValueError('Halaman tidak valid')
        ack = []
        with self.db:
            for change in changes:
                if not isinstance(change, dict) or set(change) != {'operation', 'kind', 'id', 'version', 'value'}:
                    raise ValueError('Field perubahan tidak valid')
                op, kind, ident, version, value = (change[k] for k in ('operation', 'kind', 'id', 'version', 'value'))
                if kind not in ('child', 'revision', 'visit') or not isinstance(value, dict):
                    raise ValueError('Jenis/isi record tidak valid')
                if any(not isinstance(v, str) or not v or len(v) > 150 for v in (op, ident)):
                    raise ValueError('ID tidak valid')
                if type(version) is not int or version < 0:
                    raise ValueError('Versi tidak valid')
                raw = json.dumps(value, sort_keys=True, allow_nan=False)
                if len(raw.encode()) > 32768:
                    raise ValueError('Record terlalu besar')
                digest = hashlib.sha256(json.dumps({'role': role, 'change': change}, sort_keys=True, allow_nan=False).encode()).hexdigest()
                prior = self.db.execute('SELECT digest FROM sync_commands WHERE operation=?', (op,)).fetchone()
                if prior:
                    if prior[0] != digest:
                        raise ValueError('ID operasi digunakan ulang dengan data berbeda')
                    ack.append(op)
                    continue
                row = self.db.execute('SELECT version,value FROM sync_records WHERE kind=? AND id=?', (kind, ident)).fetchone()
                if version != (row[0] if row else 0):
                    raise SyncConflict('Versi berubah; data lokal dipertahankan untuk rekonsiliasi')
                self._validate(kind, ident, value, json.loads(row[1]) if row else None)
                if kind == 'visit' and role != 'gizi':
                    raise ValueError('Hanya gizi dapat mengubah jadwal')
                if kind == 'child' and role != 'kader':
                    raise ValueError('Hanya kader dapat mengubah profil')
                if kind == 'revision':
                    old = json.loads(row[1]) if row else None
                    if role == 'gizi':
                        if old is None or old.get('status') != 'pending' or value.get('status') not in ('approved', 'rejected'):
                            raise ValueError('Review tidak valid')
                        if {k: v for k, v in old.items() if k not in ('status', 'note')} != {k: v for k, v in value.items() if k not in ('status', 'note')}:
                            raise ValueError('Review tidak boleh mengubah pengukuran')
                        if value['status'] == 'rejected' and not str(value.get('note', '')).strip():
                            raise ValueError('Alasan penolakan wajib')
                    elif old and old.get('status') == 'pending' and old != value:
                        raise ValueError('Revisi pending tidak dapat diubah sebelum review')
                    elif value.get('status') not in ('draft', 'pending') or (old and old.get('status') in ('approved', 'rejected')):
                        raise ValueError('Revisi yang telah ditinjau harus dikoreksi sebagai revisi baru')
                self.db.execute('INSERT OR REPLACE INTO sync_records VALUES (?,?,?,?)', (kind, ident, version + 1, raw))
                self.db.execute('INSERT INTO sync_commands VALUES (?,?)', (op, digest))
                ack.append(op)
            records = [{'kind': k, 'id': i, 'version': v, 'value': json.loads(raw)}
                       for k, i, v, raw in self.db.execute('SELECT kind,id,version,value FROM sync_records ORDER BY kind,id')]
        if limit is not None:
            if type(limit) is not int or not 1 <= limit <= 100 or (cursor is not None and not isinstance(cursor, str)):
                raise ValueError('Halaman tidak valid')
            records = [r for r in records if cursor is None or r['kind'] + '|' + r['id'] > cursor]
            more = len(records) > limit
            records = records[:limit]
            return {'records': records, 'ack': ack, 'nextCursor': records[-1]['kind'] + '|' + records[-1]['id'] if more else None}
        return {'records': records, 'ack': ack}
