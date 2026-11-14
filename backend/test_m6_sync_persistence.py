"""
Milestone 6: Server Persistence & Cryptographic Hash Chain Audit Tests (Tech Arch Section 4.1, 7, 10).
"""
import os
import tempfile
import unittest
import sqlite3
from .event_store import EventStore, GENESIS_HASH
from .models import CanonicalEvent

class TestM6SyncPersistence(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.db_path = os.path.join(self.temp_dir.name, "test_oravi_server.db")
        self.store = EventStore(db_path=self.db_path)

    def tearDown(self):
        self.store.close()
        self.temp_dir.cleanup()

    def test_disk_persistence_and_hash_chain_across_restarts(self):
        # 1. Append 2 events
        ev1 = CanonicalEvent(
            event_id="0192a5b6-0001-7000-8000-000000000001",
            patient_id="PAT-4B-01",
            type="PatientAdmitted",
            author_id="NURSE-MWANGI",
            device_id="DEV-A",
            client_created_at="2026-10-29T00:00:00Z",
            payload={"bed_number": "Bed 1", "admission_number": "ADM-01"},
        )
        ev2 = CanonicalEvent(
            event_id="0192a5b6-0001-7000-8000-000000000002",
            patient_id="PAT-4B-01",
            type="LoopOpened",
            author_id="NURSE-MWANGI",
            device_id="DEV-A",
            client_created_at="2026-10-29T00:05:00Z",
            payload={"title": "Check IV cannula"},
        )

        acks = self.store.append_events([ev1, ev2])
        self.assertEqual(len(acks), 2)
        self.assertEqual(acks[0].server_seq, 1)
        self.assertEqual(acks[1].server_seq, 2)
        self.assertEqual(self.store._latest_seq, 2)
        last_hash_before_close = self.store._last_hash

        # Verify hash chain in memory
        self.assertTrue(self.store.verify_hash_chain())

        # 2. Simulate server restart: close and reopen database file
        self.store.close()
        reopened_store = EventStore(db_path=self.db_path)

        # Check that latest sequence and hash chain picked up from disk
        self.assertEqual(reopened_store._latest_seq, 2)
        self.assertEqual(reopened_store._last_hash, last_hash_before_close)
        self.assertTrue(reopened_store.verify_hash_chain())

        # 3. Append 3rd event to restarted server
        ev3 = CanonicalEvent(
            event_id="0192a5b6-0001-7000-8000-000000000003",
            patient_id="PAT-4B-01",
            type="MessagePosted",
            author_id="NURSE-MWANGI",
            device_id="DEV-A",
            client_created_at="2026-10-29T00:10:00Z",
            payload={"content": "Cannula intact"},
        )
        acks3 = reopened_store.append_events([ev3])
        self.assertEqual(len(acks3), 1)
        self.assertEqual(acks3[0].server_seq, 3)
        self.assertEqual(reopened_store._latest_seq, 3)
        self.assertTrue(reopened_store.verify_hash_chain())

        # 4. Pull sync verification
        events, latest = reopened_store.get_events_since(since_seq=1, limit=10)
        self.assertEqual(len(events), 2)
        self.assertEqual(events[0].server_seq, 2)
        self.assertEqual(events[1].server_seq, 3)
        self.assertEqual(latest, 3)

        reopened_store.close()

    def test_idempotent_deduplication_across_restarts(self):
        ev1 = CanonicalEvent(
            event_id="evt-fixed-id-1",
            patient_id="PAT-4B-02",
            type="LoopOpened",
            author_id="NURSE-01",
            device_id="DEV-A",
            client_created_at="2026-10-29T00:00:00Z",
            payload={"title": "Foley Catheter"},
        )
        ack1 = self.store.append_events([ev1])[0]

        # Close and reopen
        self.store.close()
        reopened_store = EventStore(db_path=self.db_path)

        # Resend exact same event
        ack2 = reopened_store.append_events([ev1])[0]

        self.assertEqual(ack1.server_seq, ack2.server_seq)
        self.assertEqual(ack1.hash, ack2.hash)
        self.assertEqual(reopened_store._latest_seq, 1)

        reopened_store.close()

    def test_tamper_detection_triggers_validation_error(self):
        ev = CanonicalEvent(
            event_id="evt-audit-1",
            patient_id="PAT-4B-03",
            type="MessagePosted",
            author_id="DOC-OTIENO",
            device_id="DEV-A",
            client_created_at="2026-10-29T00:00:00Z",
            payload={"content": "Prescribed Ceftriaxone 2g"},
        )
        self.store.append_events([ev])
        self.assertTrue(self.store.verify_hash_chain())

        # Simulate malicious tampering in SQLite: edit payload directly without recalculating hash
        conn = sqlite3.connect(self.db_path)
        with conn:
            conn.execute("UPDATE server_events SET payload_json = '{\"content\": \"Prescribed Paracetamol 1g\"}' WHERE server_seq = 1;")
        conn.close()

        # Close and reopen store
        self.store.close()
        tampered_store = EventStore(db_path=self.db_path)

        with self.assertRaises(ValueError) as ctx:
            tampered_store.verify_hash_chain()
        self.assertIn("Hash signature mismatch", str(ctx.exception))

        tampered_store.close()
