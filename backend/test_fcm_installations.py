import os
import sqlite3
import tempfile
import unittest

from backend.staff_store import StaffStore


class TestFcmInstallations(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
