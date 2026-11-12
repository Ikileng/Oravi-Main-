import tempfile
import unittest
from datetime import date, timedelta
from unittest.mock import patch

from fastapi.testclient import TestClient
import backend.main as api
from backend.models import HospitalWardModel, ShiftAllocationModel
from backend.ward_store import WardStore
from backend.staff_store import StaffStore


class WardConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.wards = WardStore(self.directory.name + '/wards.db')
        for letter in 'ABCDEFGHIJ':
            self.wards.create_ward(HospitalWardModel(letter, 'Ward ' + letter, 0,
                ['01', '02'] if letter == 'A' else [], 'General', 'Existing'))
        self.staff = StaffStore(':memory:')
        self.staff.create_first_admin('ADMIN', 'Admin', '123456')
        self.staff.create_session('ADMIN', 'admin')
        self.staff.create_staff('N', 'Nurse', 'ward_nurse', '', '1234')
        self.staff.create_session('N', 'nurse')
        self.patches = [patch.object(api, 'ward_store', self.wards),
                        patch.object(api, 'staff_store', self.staff)]
        for item in self.patches:
            item.start()
        self.client = TestClient(api.app)
        self.headers = {'Authorization': 'Bearer admin'}

    def tearDown(self):
        self.client.close()
        for item in self.patches:
            item.stop()
        self.staff.close()
        self.directory.cleanup()

    def payload(self, beds, expected):
        return dict(name='Ward A', department='General', description='Existing',
                    bed_numbers=beds, expected_bed_numbers=expected)

    def test_edit_preserves_all_existing_wards_and_ids(self):
        before = self.client.get('/api/v1/admin/wards', headers=self.headers).json()
        response = self.client.put('/api/v1/admin/wards/A', headers=self.headers,
            json=self.payload(['01', '02', '03'], ['01', '02']))
        self.assertEqual(response.status_code, 200, response.text)
        after = self.client.get('/api/v1/admin/wards', headers=self.headers).json()
        self.assertEqual(before[1:], after[1:])
        self.assertEqual(after[0]['ward_id'], 'A')
        self.assertEqual(after[0]['bed_count'], 3)
        empty = self.client.put('/api/v1/admin/wards/B', headers=self.headers,
            json=dict(name='Ward B', bed_numbers=['B1'], expected_bed_numbers=[]))
        self.assertEqual(empty.status_code, 200)

    def test_validation_stale_edits_and_creation(self):
        for beds in (['01', '01'], ['A', 'a'], [' ']):
            self.assertEqual(self.client.put('/api/v1/admin/wards/A', headers=self.headers,
                json=self.payload(beds, ['01', '02'])).status_code, 400)
        self.assertEqual(self.client.put('/api/v1/admin/wards/A', headers=self.headers,
            json=self.payload(['01'], [])).status_code, 409)
        response = self.client.post('/api/v1/admin/wards', headers=self.headers,
            json=dict(name='Ward K', bed_numbers=[]))
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(self.wards.get_all_wards()), 11)

    def test_stale_board_cannot_publish_a_removed_bed(self):
        ward = HospitalWardModel('A', 'Ward A', 1, ['01'], 'General', 'Existing')
        self.wards.update_ward_configuration(ward, ['01', '02'])
        allocation = ShiftAllocationModel('allocation', 'A', 'day', date.today().isoformat(),
            'charge', '2026-11-12T00:00:00Z', [{'bed_number': '02'}], {})
        with self.assertRaisesRegex(ValueError, 'Reload the board'):
            self.wards.publish_shift_allocation(allocation)

    def test_current_and_overnight_references_block_removal_but_history_is_retained(self):
        for day, shift in ((date.today(), 'day'), (date.today() - timedelta(days=1), 'night')):
            with self.wards._get_connection() as connection:
                connection.execute('DELETE FROM shift_bed_assignments')
                connection.execute('''INSERT INTO shift_bed_assignments
                    (allocation_id,ward_id,bed_number,shift_type,date) VALUES ('old','A','02',?,?)''',
                    (shift, day.isoformat()))
                connection.commit()
            response = self.client.put('/api/v1/admin/wards/A', headers=self.headers,
                json=self.payload(['01'], ['01', '02']))
            self.assertEqual(response.status_code, 409)
        with self.wards._get_connection() as connection:
            connection.execute('UPDATE shift_bed_assignments SET date=?',
                ((date.today() - timedelta(days=5)).isoformat(),))
            connection.commit()
        self.assertEqual(self.client.put('/api/v1/admin/wards/A', headers=self.headers,
            json=self.payload(['01'], ['01', '02'])).status_code, 200)
        with self.wards._get_connection() as connection:
            self.assertEqual(connection.execute('SELECT count(*) FROM shift_bed_assignments').fetchone()[0], 1)

    def test_only_admin_can_access_configuration_and_catalog_contains_no_clinical_fields(self):
        for headers in ({}, {'Authorization': 'Bearer nurse'}):
            for method, path, payload in (('GET', '', None), ('POST', '', dict(name='X', bed_numbers=[])),
                    ('PUT', '/A', self.payload([], ['01', '02']))):
                self.assertIn(self.client.request(method, '/api/v1/admin/wards' + path,
                    headers=headers, json=payload).status_code, (401, 403))
        catalog = self.client.get('/api/v1/admin/wards', headers=self.headers).json()
        self.assertEqual(set(catalog[0]), {'ward_id', 'name', 'bed_count', 'bed_numbers', 'department', 'description'})
