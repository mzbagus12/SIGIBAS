import json
import tempfile
import threading
import unittest
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from server import create_server


class ServerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.server = create_server(Path(self.tmp.name) / 'demo.sqlite', port=0)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = 'http://127.0.0.1:%d' % self.server.server_port

    def tearDown(self):
        self.server.shutdown()
        self.thread.join()
        self.server.server_close()
        self.tmp.cleanup()

    def call(self, path, role, payload=None):
        body = None if payload is None else json.dumps(payload).encode()
        req = Request(self.url + path, data=body, headers={'Content-Type': 'application/json', 'X-Demo-Role': role})
        try:
            with urlopen(req, timeout=3) as response:
                return response.status, json.load(response)
        except HTTPError as e:
            return e.code, json.load(e)

    def test_roles_submission_review_and_anonymous_aggregate(self):
        p = {'operation_id':'demo-op-1', 'payload':{'synthetic':True,'child_id':'demo-child-1',
              'revision_id':'demo-revision-1','weight':12,'height':88}}
        self.assertEqual(self.call('/revisions', 'pemerintah', p)[0], 403)

        self.assertEqual(self.call('/revisions', 'kader', p)[0], 200)
        self.assertEqual(self.call('/revisions', 'kader', p)[0], 200)
        self.assertEqual(self.call('/revisions', 'pemerintah')[0], 403)
        self.assertEqual(self.call('/review', 'kader', {'operation_id':'review-1',
             'revision_id':'demo-revision-1','status':'approved','note':''})[0], 403)
        self.assertEqual(self.call('/review', 'gizi', {'operation_id':'review-1',
             'revision_id':'demo-revision-1','status':'approved','note':''})[0], 200)
        self.assertEqual(self.call('/aggregate', 'pemerintah'), (200, {'approved_count':1}))
        self.assertEqual(self.call('/aggregate', 'unknown')[0], 403)

    def test_sync_sessions_transfer_review_and_ignore_spoofed_role(self):
        self.assertEqual(self.call('/sync', 'kader', {'synthetic':True, 'token':'fake', 'changes':[]})[0],403)
        _, login = self.call('/sync-login','pemerintah',{'user':'kader','pin':'1111'})
        kader = login['token']
        _, login = self.call('/sync-login','kader',{'user':'gizi','pin':'2222'})
        gizi = login['token']
        child = {'operation':'child-state','kind':'child','id':'c','version':0,
                 'value':{'name':'Synthetic','birth':'2024-01-01','sex':'male'}}
        self.assertEqual(self.call('/sync','kader',{'synthetic':True,'token':kader,'changes':[child]})[0],200)
        change = {'operation':'submit-state','kind':'revision','id':'revision:one','version':0,
                  'value':{'id':'revision:one','child':'c','measurement':'revision:one','previous':None,
                           'status':'pending','note':'','results':{},'input':{'date':'2026-10-01','weight':12,'cm':88,'position':'standing','oedema':'no'}}}
        status, reply = self.call('/sync','gizi',{'synthetic':True,'token':kader,'changes':[change]})
        self.assertEqual(status,200)
        self.assertEqual(reply['records'][0]['version'],1)
        status, fetched = self.call('/sync','kader',{'synthetic':True,'token':gizi,'changes':[]})
        self.assertEqual(status,200)
        self.assertEqual(fetched['records'],reply['records'])
        review = {**change,'operation':'review-state','version':1,'value':{**change['value'],'status':'approved'}}
        self.assertEqual(self.call('/sync','gizi',{'synthetic':True,'token':kader,'changes':[review]})[0],400)
        self.assertEqual(self.call('/sync','kader',{'synthetic':True,'token':gizi,'changes':[review]})[0],200)
        stale = {**change,'operation':'stale-state','value':{**change['value'],'note':'late'}}
        self.assertEqual(self.call('/sync','kader',{'synthetic':True,'token':kader,'changes':[stale]})[0],409)
        _, final = self.call('/sync','kader',{'synthetic':True,'token':kader,'changes':[]})
        self.assertEqual(final['records'][1]['value']['status'],'approved')

    def test_synthetic_correction_across_http_roles(self):
        payload = {'synthetic': True, 'child_id': 'demo-child-1',
                   'revision_id': 'demo-revision-1', 'weight': 12, 'height': 88}
        self.assertEqual(self.call('/revisions', 'kader', {'operation_id': 'send-1', 'payload': payload})[0], 200)
        reject = {'operation_id': 'reject-1', 'revision_id': 'demo-revision-1',
                  'status': 'rejected', 'note': 'Ukur ulang sintetis'}
        self.assertEqual(self.call('/review', 'gizi', {**reject, 'note': ' '})[0], 400)
        self.assertEqual(self.call('/review', 'gizi', reject)[0], 200)
        corrected = {**payload, 'revision_id': 'demo-revision-2',
                     'previous_id': 'demo-revision-1', 'weight': 12.1}
        self.assertEqual(self.call('/revisions', 'kader', {'operation_id': 'send-2', 'payload': corrected})[0], 200)
        self.assertEqual(self.call('/review', 'gizi', {'operation_id': 'approve-2',
                         'revision_id': 'demo-revision-2', 'status': 'approved', 'note': ''})[0], 200)
        self.assertEqual(self.call('/aggregate', 'pemerintah'), (200, {'approved_count': 1}))
        status, content = self.call('/revisions', 'gizi')
        self.assertEqual(status, 200)
        self.assertEqual([row['status'] for row in content['revisions']], ['rejected', 'approved'])

    def test_archived_profile_restore_transfers_between_sessions(self):
        _, first = self.call('/sync-login', 'kader', {'user': 'kader', 'pin': '1111'})
        _, second = self.call('/sync-login', 'kader', {'user': 'gizi', 'pin': '2222'})
        tokens = (first['token'], second['token'])
        value = {'id': 'child:dummy', 'name': 'Dummy', 'birth': '2024-01-01', 'sex': 'male'}
        def change(op, version, data):
            return {'operation': op, 'kind': 'child', 'id': 'child:dummy', 'version': version, 'value': data}
        def sync(token, changes):
            return self.call('/sync', 'kader', {'synthetic': True, 'token': token, 'changes': changes})
        self.assertEqual(sync(tokens[0], [change('create', 0, value)])[0], 200)
        self.assertEqual(sync(tokens[0], [change('archive', 1, {**value, 'archived': True})])[0], 200)
        self.assertTrue(sync(tokens[1], [])[1]['records'][0]['value']['archived'])
        self.assertEqual(sync(tokens[1], [change('denied', 2, {**value, 'archived': False})])[0], 400)
        self.assertEqual(sync(tokens[0], [change('restore', 2, {**value, 'archived': False})])[0], 200)
        restored = sync(tokens[1], [])[1]['records'][0]
        self.assertEqual(restored['version'], 3)
        self.assertFalse(restored['value']['archived'])

    def test_demo_role_header_is_not_authentication(self):
        # Menunjukkan batas keamanan: klien dapat mengaku sebagai peran apa pun.
        status, result = self.call('/aggregate', 'pemerintah')
        self.assertEqual((status, result), (200, {'approved_count': 0}))

    def test_cors_only_allows_local_test_origin(self):
        req = Request(self.url + '/revisions', method='OPTIONS', headers={
            'Origin': 'http://127.0.0.1:8767',
            'Access-Control-Request-Method': 'POST',
            'Access-Control-Request-Headers': 'content-type,x-demo-role',
        })
        with urlopen(req, timeout=3) as response:
            self.assertEqual(response.status, 204)
            self.assertEqual(response.headers['Access-Control-Allow-Origin'], 'http://127.0.0.1:8767')
        req.add_header('Origin', 'https://example.com')
        with self.assertRaises(HTTPError) as error:
            urlopen(req, timeout=3)
        self.assertEqual(error.exception.code, 403)

    def test_post_from_other_origin_does_not_mutate(self):
        payload = {'operation_id': 'bad-origin', 'payload': {'synthetic': True,
                   'child_id': 'demo-child-1', 'revision_id': 'demo-revision-1',
                   'weight': 12, 'height': 88}}
        request = Request(self.url + '/revisions', data=json.dumps(payload).encode(),
                          headers={'Origin': 'https://example.com', 'Content-Type': 'text/plain',
                                   'X-Demo-Role': 'kader'})
        with self.assertRaises(HTTPError) as error:
            urlopen(request, timeout=3)
        self.assertEqual(error.exception.code, 403)
        self.assertEqual(self.call('/revisions', 'gizi'), (200, {'revisions': []}))

if __name__ == '__main__':
    unittest.main()

class AuthTests(unittest.TestCase):
    setUp = ServerTests.setUp
    tearDown = ServerTests.tearDown
    call = ServerTests.call
    def test_password_rotation_revokes_tokens_and_government_is_aggregate_only(self):
        _, login = self.call('/sync-login','kader',{'user':'pemerintah','pin':'3333'})
        token = login['token']
        status, result = self.call('/sync','kader',{'synthetic':True,'token':token,'changes':[]})
        self.assertEqual(status,200)
        self.assertIn('aggregate',result)
        self.assertEqual(result['records'],[])
        self.assertEqual(self.call('/sync-password','kader',{'token':token,'oldPin':'3333','newPin':'new-local-pin'})[0],200)
        self.assertEqual(self.call('/sync','kader',{'synthetic':True,'token':token,'changes':[]})[0],403)
        self.assertEqual(self.call('/sync-login','kader',{'user':'pemerintah','pin':'3333'})[0],403)
        status, login = self.call('/sync-login','kader',{'user':'pemerintah','pin':'new-local-pin'})
        self.assertEqual(status,200)
        self.assertEqual(self.call('/sync-logout','kader',{'token':login['token']})[0],200)
        self.assertEqual(self.call('/sync','kader',{'synthetic':True,'token':login['token'],'changes':[]})[0],403)

    def test_security_events_require_session_and_minimal_enum_schema(self):
        event={'eventId':'synthetic-event-1','atDevice':'2026-10-29T12:00:00','findings':['root','emulator']}
        self.assertEqual(self.call('/security-events','kader',{'events':[event]})[0],403)
        _,login=self.call('/sync-login','kader',{'user':'kader','pin':'1111'})
        body={'token':login['token'],'events':[event]}
        self.assertEqual(self.call('/security-events','pemerintah',body),(200,{'ack':['synthetic-event-1']}))
        self.assertEqual(self.call('/security-events','pemerintah',body)[0],200)
        self.assertEqual(self.call('/security-events','kader',{'token':login['token'],'events':[{**event,'deviceId':'not-allowed'}]})[0],400)
        self.assertEqual(self.call('/security-events','kader',{'token':login['token'],'events':[{**event,'findings':['arbitrary']} ]})[0],400)
        self.assertEqual(self.server.sync_store.db.execute('SELECT COUNT(*) FROM security_events').fetchone()[0],1)
