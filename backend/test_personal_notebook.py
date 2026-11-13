import os
import tempfile
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient
import backend.main as api
from backend.notebook import NotebookStore
from backend.staff_store import StaffStore


class PersonalNotebookTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.temp.name, 'notebook.sqlite')
        self.staff = StaffStore(self.path)
        self.staff.create_first_admin('A', 'Admin', '123456')
        self.staff.create_session('A', 'A')
        for who, role in [('N', 'ward_nurse'), ('C', 'charge_nurse'),
                          ('D', 'doctor_on_call'), ('H', 'housekeeper')]:
            self.staff.create_staff(who, who, role, '', '1234')
            self.staff.create_session(who, who)
        self.notebook = NotebookStore(self.path)
        self.patches = [patch.object(api, 'staff_store', self.staff),
                        patch.object(api, 'notebook_store', self.notebook)]
        for item in self.patches:
            item.start()
        self.client = TestClient(api.app)

    def tearDown(self):
        self.client.close()
        for item in self.patches:
            item.stop()
        self.staff.close()
        self.temp.cleanup()

    def request(self, method, path='', who='N', **kwargs):
        return self.client.request(method, '/api/v1/notebook' + path,
                                   headers={'Authorization': 'Bearer ' + who}, **kwargs)

    def test_private_persistent_history_and_idempotent_save(self):
        payload = {'body': 'Ward rounds', 'kind': 'task',
                   'reminder_at': '2030-01-01T09:00:00+03:00'}
        for _ in range(2):
            result = self.request('PUT', '/one', json=payload)
            self.assertEqual(result.status_code, 200, result.text)
        self.assertEqual(len(self.request('GET').json()), 1)
        created = result.json()['created_at']
        self.assertEqual(result.json()['reminder_at'], '2030-01-01T06:00:00+00:00')
        for who in ['C', 'D']:
            self.assertEqual(self.request('GET', who=who).json(), [])
            self.request('DELETE', '/one', who=who)
        self.assertEqual(len(self.request('GET').json()), 1)
        self.request('PUT', '/one', json={**payload, 'completed': True})
        with patch.object(api, 'notebook_store', NotebookStore(self.path)):
            saved = self.request('GET').json()[0]
        self.assertEqual(saved['created_at'], created)
        self.assertEqual(saved['completed'], 1)
        self.assertIsNotNone(saved['completed_at'])
        self.assertIsNone(saved['reminder_at'])
        self.request('PUT', '/one', json={**payload, 'reminder_at': None})
        self.assertIsNone(self.request('GET').json()[0]['completed_at'])
        self.request('DELETE', '/one')
        self.assertEqual(self.request('GET').json(), [])

    def test_authorization_and_no_patient_or_owner_payloads(self):
        for who in ['A', 'H', 'invalid']:
            for method, suffix in [('GET', ''), ('PUT', '/one'), ('DELETE', '/one')]:
                result = self.request(method, suffix, who=who,
                                      **({'json': {'body': 'private'}} if method == 'PUT' else {}))
                self.assertIn(result.status_code, [401, 403])
        for field in ['owner_id', 'patient_id', 'ward_id']:
            self.assertEqual(self.request('PUT', '/one', json={'body': 'note', field: 'C'}).status_code, 422)
        self.assertEqual(self.request('PUT', '/one', json={'body': '   '}).status_code, 400)
        self.assertEqual(self.request('PUT', '/one', json={
            'body': 'note', 'reminder_at': '2030-01-01T09:00:00'}).status_code, 422)
        self.assertEqual(self.request('PUT', '/one', json={
            'body': 'note', 'kind': 'note', 'completed': True}).status_code, 400)

    def test_notes_and_snoozes_are_account_scoped(self):
        for who in ['N', 'C', 'D']:
            self.assertEqual(self.request('PUT', '/same-id', who=who,
                json={'body': who + ' note', 'kind': 'note'}).status_code, 200)
        self.request('PUT', '/same-id', json={'body': 'N note', 'kind': 'note',
                                            'reminder_at': '2030-01-01T09:15:00Z'})
        for who in ['N', 'C', 'D']:
            row = self.request('GET', who=who).json()[0]
            self.assertEqual(row['body'], who + ' note')
            self.assertEqual(row['reminder_at'] is not None, who == 'N')


if __name__ == '__main__':
    unittest.main()
