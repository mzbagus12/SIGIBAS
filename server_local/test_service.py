import tempfile
import unittest
from pathlib import Path
from service import DemoService, DemoError


class DemoServiceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.s = DemoService(Path(self.tmp.name) / 'demo.sqlite')
        self.payload = {'synthetic': True, 'child_id': 'demo-child-1',
                        'revision_id': 'demo-revision-1', 'weight': 12.0,
                        'height': 88.0}

    def tearDown(self):
        self.s.close()
        self.tmp.cleanup()

    def test_submit_idempotency_and_conflict(self):
        first = self.s.submit('demo-op-1', self.payload)
        self.assertEqual(first['status'], 'pending')
        self.assertEqual(self.s.submit('demo-op-1', self.payload), first)
        with self.assertRaises(DemoError):
            self.s.submit('demo-op-1', {**self.payload, 'weight': 13.0})
        self.assertEqual(len(self.s.list_revisions()), 1)

    def test_reject_invalid_and_non_synthetic(self):
        for p in ({**self.payload, 'synthetic': False},
                  {**self.payload, 'weight': -1},
                  {**self.payload, 'name': 'private'}):
            with self.assertRaises(DemoError):
                self.s.submit('invalid', p)
        self.assertEqual(self.s.list_revisions(), [])

    def test_review_requires_note_and_aggregate_excludes_identity(self):
        self.s.submit('submit', self.payload)
        with self.assertRaises(DemoError):
            self.s.review('reject-empty', 'demo-revision-1', 'rejected', ' ')
        self.assertEqual(self.s.aggregate(), {'approved_count': 0})
        self.s.review('approve', 'demo-revision-1', 'approved', '')
        self.assertEqual(self.s.aggregate(), {'approved_count': 1})
        self.assertEqual(self.s.review('approve', 'demo-revision-1', 'approved', '')['status'], 'approved')
        with self.assertRaises(DemoError):
            self.s.review('other', 'demo-revision-1', 'rejected', 'bad')

    def test_correction_preserves_effective_approval_until_replacement(self):
        self.s.submit('submit', self.payload)
        self.s.review('approve', 'demo-revision-1', 'approved', '')
        correction = {**self.payload, 'revision_id': 'demo-revision-2',
                      'previous_id': 'demo-revision-1', 'weight': 11.0}
        self.s.submit('correction', correction)
        self.assertEqual(self.s.aggregate(), {'approved_count': 1})
        self.s.review('reject', 'demo-revision-2', 'rejected', 'Ukur ulang')
        self.assertEqual(self.s.aggregate(), {'approved_count': 1})
        replacement = {**correction, 'revision_id': 'demo-revision-3',
                       'previous_id': 'demo-revision-2'}
        self.s.submit('replacement', replacement)
        self.s.review('approve-new', 'demo-revision-3', 'approved', '')
        self.assertEqual(self.s.aggregate(), {'approved_count': 1})
        with self.assertRaises(DemoError):
            self.s.submit('stale', {**correction, 'revision_id':'demo-revision-4'})


if __name__ == '__main__':
    unittest.main()
