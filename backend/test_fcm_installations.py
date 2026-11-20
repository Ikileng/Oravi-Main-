import os
import sqlite3
import tempfile
import unittest

from backend.staff_store import StaffStore


class TestFcmInstallations(unittest.TestCase):
    def test_explicit_unavailability_survives_reconnect_login_and_restart(self):
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, 'availability.db')
            store = StaffStore(path)
            store.create_staff('N', 'Nurse', 'ward_nurse', '', '1234')
            credential = store.issue_call_device_credential('N', 'device', 'android')
            self.assertTrue(store.refresh_contact_device(credential, 'first-token'))
            self.assertEqual(store.get_fcm_fids_for_staff('N'), ['first-token'])
            store.set_available('N', False)
            store.close()
            store = StaffStore(path)
            try:
                self.assertFalse(store.refresh_contact_device(credential, 'new-token'))
                self.assertTrue(store.verify_pin('N', '1234')[0])
                self.assertFalse(store.is_available('N'))
                self.assertEqual(store.get_fcm_fids_for_staff('N'), [])
                self.assertIsNone(store.refresh_contact_device('invalid', 'bad-token'))
                store.set_available('N', True)
                self.assertEqual(store.get_fcm_fids_for_staff('N'), ['new-token'])
                store.set_staff_active('N', False)
                self.assertIsNone(store.refresh_contact_device(credential, 'blocked-token'))
            finally:
                store.close()

    def test_legacy_registration_tokens_are_discarded(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            database_path = os.path.join(temp_dir, "staff.db")
            connection = sqlite3.connect(database_path)
            try:
                connection.execute(
                    """CREATE TABLE fcm_device_tokens (
                           staff_id TEXT NOT NULL,
                           device_id TEXT NOT NULL,
                           token TEXT NOT NULL UNIQUE,
                           platform TEXT NOT NULL,
                           updated_at TEXT NOT NULL,
                           PRIMARY KEY (staff_id, device_id)
                       )"""
                )
                connection.execute(
                    """INSERT INTO fcm_device_tokens
                       (staff_id, device_id, token, platform, updated_at)
                       VALUES (?, ?, ?, ?, ?)""",
                    (
                        "NURSE-OLD",
                        "DEVICE-OLD",
                        "legacy-fcm-registration-token",
                        "android",
                        "2026-01-01T00:00:00Z",
                    ),
                )
            finally:
                connection.close()

            store = StaffStore(db_path=database_path)
            try:
                columns = {
                    row["name"]
                    for row in store.conn.execute(
                        "PRAGMA table_info(fcm_device_tokens)"
                    ).fetchall()
                }
                self.assertIn("fid", columns)
                self.assertNotIn("token", columns)
                self.assertEqual(store.get_fcm_fids_for_staff("NURSE-OLD"), [])
            finally:
                store.close()

    def test_installation_registration_replaces_same_device_fid(self):
        store = StaffStore(db_path=":memory:")
        try:
            store.create_staff(
                staff_id="NURSE-NEW",
                name="Nurse New",
                role="ward_nurse",
                ward_id="",
                pin="1234",
            )

            self.assertTrue(
                store.register_fcm_installation(
                    "NURSE-NEW", "DEVICE-NEW", "fid-first-registration-0001", "android"
                )
            )
            self.assertTrue(
                store.register_fcm_installation(
                    "NURSE-NEW", "DEVICE-NEW", "fid-refreshed-registration-0002", "android"
                )
            )
            self.assertEqual(
                store.get_fcm_fids_for_staff("NURSE-NEW"),
                ["fid-refreshed-registration-0002"],
            )
        finally:
            store.close()

    def test_call_credential_is_device_scoped_and_resolvable(self):
        store = StaffStore(db_path=":memory:")
        try:
            store.create_staff(
                staff_id="NURSE-CALL",
                name="Nurse Call",
                role="ward_nurse",
                ward_id="",
                pin="1234",
            )
            credential = store.issue_call_device_credential(
                "NURSE-CALL", "DEVICE-CALL", "android"
            )

            profile = store.get_staff_for_call_credential(credential)
            self.assertIsNotNone(profile)
            self.assertEqual(profile.staff_id, "NURSE-CALL")
            self.assertIsNone(
                store.get_staff_for_call_credential("invalid-call-credential")
            )
        finally:
            store.close()


if __name__ == "__main__":
    unittest.main()
