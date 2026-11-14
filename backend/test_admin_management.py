import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

import backend.main as api
from backend.staff_store import StaffStore


class AdminManagementTests(unittest.TestCase):
    def setUp(self):
        self.store = StaffStore(':memory:')
        self.store.create_first_admin('ADMIN', 'Test Admin', '123456')
        self.store.create_session('ADMIN', 'admin-token')
        self.store.create_staff('N1', 'Test Nurse', 'ward_nurse', '', '1234')
        self.store.create_session('N1', 'nurse-token')
        self.override = patch.object(api, 'staff_store', self.store)
        self.override.start()
        self.client = TestClient(api.app)
        self.admin = {'Authorization': 'Bearer admin-token'}
        self.nurse = {'Authorization': 'Bearer nurse-token'}

    def tearDown(self):
        self.client.close()
        self.override.stop()
        self.store.close()

    def test_admin_cannot_read_clinical_data_or_allocations(self):
        for path in (
            '/api/v1/wards',
            '/api/v1/wards/private/board?date=2026-11-12&shift_type=day',
            '/api/v1/sync/pull?ward_id=private&after_seq=0',
            '/api/v1/calls/private',
        ):
            with self.subTest(path=path):
                self.assertEqual(self.client.get(path, headers=self.admin).status_code, 403)

    def test_only_admin_can_manage_staff(self):
        for headers in ({}, self.nurse):
            self.assertIn(self.client.get('/api/v1/admin/staff', headers=headers).status_code, (401, 403))
            self.assertIn(self.client.delete('/api/v1/admin/staff/N1', headers=headers).status_code, (401, 403))

    def test_directory_never_discloses_assignments_or_pins(self):
        self.store.conn.execute("UPDATE staff_users SET ward_id = 'private-ward' WHERE staff_id = 'N1'")
        self.store.conn.commit()
        response = self.client.get('/api/v1/admin/staff', headers=self.admin)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()[0]['ward_id'], '')
        self.assertNotIn('private-ward', response.text)
        self.assertNotIn('pin_hash', response.text)

    def test_create_all_three_roles_and_reject_duplicate(self):
        for role in ('ward_nurse', 'charge_nurse', 'doctor_on_call'):
            payload = dict(staff_id=role, name='Test User', role=role, pin='5678')
            result = self.client.post('/api/v1/admin/staff', headers=self.admin, json=payload)
            self.assertEqual(result.status_code, 200, result.text)
            self.assertEqual(result.json()['role'], role)
            self.assertEqual(self.client.post('/api/v1/admin/staff', headers=self.admin, json=payload).status_code, 409)

    def test_deactivate_revokes_session_and_reactivation_requires_login(self):
        self.store.register_fcm_installation('N1', 'device', 'test-target', 'android')
        result = self.client.patch('/api/v1/admin/staff/N1', headers=self.admin, json={'is_active': False})
        self.assertEqual(result.status_code, 200)
        self.assertFalse(result.json()['is_active'])
        self.assertIsNone(self.store.get_session('nurse-token'))
        self.assertFalse(self.store.verify_pin('N1', '1234')[0])
        self.assertEqual(self.store.get_fcm_fids_for_staff('N1'), [])
        self.assertEqual(self.client.patch('/api/v1/admin/staff/N1', headers=self.admin, json={'is_active': True}).status_code, 200)
        self.assertTrue(self.store.verify_pin('N1', '1234')[0])
        self.assertIsNone(self.store.get_session('nurse-token'))

    def test_delete_removes_identity_and_does_not_reuse_historical_id(self):
        self.store.conn.execute('CREATE TABLE clinical_history (author_id TEXT, note TEXT)')
        self.store.conn.execute("INSERT INTO clinical_history VALUES ('N1', 'retained')")
        self.store.conn.commit()
        self.assertEqual(self.client.delete('/api/v1/admin/staff/N1', headers=self.admin).status_code, 200)
        self.assertEqual(self.store.list_staff(), [])
        self.assertIsNone(self.store.get_session('nurse-token'))
        self.assertFalse(self.store.verify_pin('N1', '1234')[0])
        self.assertEqual(self.store.conn.execute('SELECT note FROM clinical_history').fetchone()[0], 'retained')
        with self.assertRaises(ValueError):
            self.store.create_staff('N1', 'Different User', 'ward_nurse', '', '1234')

    def test_cannot_delete_or_deactivate_bootstrap_admin(self):
        self.assertEqual(self.client.delete('/api/v1/admin/staff/ADMIN', headers=self.admin).status_code, 404)
        self.assertEqual(self.client.patch('/api/v1/admin/staff/ADMIN', headers=self.admin, json={'is_active': False}).status_code, 404)
        self.assertIsNotNone(self.store.get_session('admin-token'))


if __name__ == '__main__':
    unittest.main()
