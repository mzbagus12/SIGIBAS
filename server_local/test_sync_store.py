import tempfile
import unittest
from pathlib import Path
from sync_store import SyncStore, SyncConflict


class SyncTests(unittest.TestCase):
    def test_only_synthetic_nik_is_accepted(self):
        base = {'operation':'nik-op','kind':'child','id':'child:nik','version':0,
                'value':{'id':'child:nik','name':'Dummy','birth':'2024-01-01','sex':'male','nik':'1234567890123456'}}
        with self.assertRaises(ValueError):
            self.store.exchange('kader', [base])
        base['value']['nik'] = '0000001234567890'
        self.assertEqual(self.store.exchange('kader', [base])['records'][0]['value']['nik'], '0000001234567890')

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.store = SyncStore(Path(self.tmp.name) / 'sync.sqlite')

    def tearDown(self):
        self.store.close()
        self.tmp.cleanup()

    def test_two_clients_retry_conflict_and_restart(self):
        change = {'operation': 'op-1', 'kind': 'child', 'id': 'child:1',
                  'version': 0, 'value': {'name': 'Synthetic', 'birth': '2024-01-01', 'sex': 'male'}}
        first = self.store.exchange('kader', [change])
        self.assertEqual(first['records'][0]['version'], 1)
        self.assertEqual(self.store.exchange('kader', [change])['records'], first['records'])
        stale = {**change, 'operation': 'op-2', 'value': {**change['value'], 'name': 'Other'}}
        with self.assertRaises(SyncConflict):
            self.store.exchange('kader', [stale])
        self.assertEqual(self.store.exchange('gizi', [])['records'], first['records'])
        self.store.close()
        self.store = SyncStore(Path(self.tmp.name) / 'sync.sqlite')
        self.assertEqual(self.store.exchange('gizi', [])['records'], first['records'])

    def test_roles_and_operation_collision(self):
        change = {'operation': 'op-1', 'kind': 'child', 'id': 'child:1', 'version': 0,
                  'value': {'name': 'Synthetic', 'birth': '2024-01-01', 'sex': 'male'}}
        with self.assertRaises(ValueError):
            self.store.exchange('pemerintah', [change])
        with self.assertRaises(ValueError):
            self.store.exchange('gizi', [change])
        self.store.exchange('kader', [change])
        with self.assertRaises(ValueError):
            self.store.exchange('kader', [{**change, 'value': {**change['value'], 'name': 'changed'}}])
        self.assertEqual(self.store.exchange('pemerintah', [])['records'], [])

    def child(self, ident='c'):
        return {'operation':'child-'+ident,'kind':'child','id':ident,'version':0,
                'value':{'id':ident,'name':'Synthetic','birth':'2024-01-01','sex':'male'}}

    def revision(self, ident='r', previous=None):
        return {'operation':'save-'+ident,'kind':'revision','id':ident,'version':0,
                'value':{'id':ident,'child':'c','measurement':'r','previous':previous,
                         'status':'pending','note':'','input':{'date':'2026-10-01','weight':12,'cm':88,'position':'standing','oedema':'no'},
                         'results':{'heightAge':{'status':'valid','category':'pendek'}}}}

    def test_chain_validation_atomicity_and_government_privacy(self):
        child, first = self.child(), self.revision()
        self.store.exchange('kader',[child,first])
        approved = {**first,'operation':'review-r','version':1,'value':{**first['value'],'status':'approved'}}
        self.store.exchange('gizi',[approved])
        second = self.revision('r2','r')
        self.store.exchange('kader',[second])
        third = self.revision('r3','r')
        with self.assertRaises(ValueError): self.store.exchange('kader',[third])
        with self.assertRaises(ValueError):
            self.store.exchange('kader',[self.child('rollback'),{**third,'value':{**third['value'],'child':[]}}])
        ids = [r['id'] for r in self.store.exchange('gizi',[])['records']]
        self.assertNotIn('rollback',ids)
        government = self.store.exchange('pemerintah',[])
        self.assertEqual(government['aggregate']['heightAge']['denominator'],1)
        self.assertEqual(government['records'],[])
        self.assertNotIn('Synthetic',str(government))
        self.assertFalse(government['clinicalValidation'])

    def test_pagination_and_lost_ack_idempotency(self):
        changes = [self.child(str(i)) for i in range(55)]
        self.store.exchange('kader',changes)
        reply = self.store.exchange('kader',changes,limit=10)
        self.assertEqual(len(reply['ack']),55)
        rows = list(reply['records'])
        while reply['nextCursor']:
            reply = self.store.exchange('kader',[],cursor=reply['nextCursor'],limit=10)
            rows += reply['records']
        self.assertEqual(len(rows),55)
        self.assertTrue(all(r['version']==1 for r in rows))
        with self.assertRaises(ValueError): self.store.exchange('kader',[self.child('invalid-page')],limit=-1)
        self.assertEqual(len(self.store.exchange('kader',[])['records']),55)
