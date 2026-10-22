import unittest
from .event_store import EventStore
from .models import CanonicalEvent

class TestSyncEngineBackend(unittest.TestCase):
    def setUp(self):
        self.store = EventStore()

    def test_append_assigns_sequential_seq_and_sha256_hash(self):
        events = [
            CanonicalEvent(
                event_id="0192a5b6-7c8d-7e0f-a1b2-c3d4e5f60001",
                patient_id="PAT-401",
                type="LoopOpened",
                author_id="NURSE-01",
                device_id="DEV-A",
                client_created_at="2026-10-21T08:00:00Z",
                payload={"title": "Check vitals"},
            ),
            CanonicalEvent(
                event_id="0192a5b6-7c8d-7e0f-a1b2-c3d4e5f60002",
                patient_id="PAT-401",
                type="MessagePosted",
                author_id="NURSE-01",
                device_id="DEV-A",
                client_created_at="2026-10-21T08:05:00Z",
                payload={"content": "Vitals normal"},
            ),
        ]

        acks = self.store.append_events(events)

        self.assertEqual(len(acks), 2)
        self.assertEqual(acks[0].server_seq, 1)
        self.assertEqual(acks[1].server_seq, 2)
        self.assertTrue(len(acks[0].hash) == 64)
        self.assertTrue(len(acks[1].hash) == 64)
        self.assertNotEqual(acks[0].hash, acks[1].hash)

    def test_idempotent_retry_does_not_duplicate(self):
        event = CanonicalEvent(
            event_id="0192a5b6-7c8d-7e0f-a1b2-c3d4e5f60001",
            patient_id="PAT-401",
            type="LoopOpened",
            author_id="NURSE-01",
            device_id="DEV-A",
            client_created_at="2026-10-21T08:00:00Z",
            payload={"title": "Check vitals"},
        )

        ack1 = self.store.append_events([event])[0]
        # Retry with identical event_id
        ack2 = self.store.append_events([event])[0]

        self.assertEqual(ack1.server_seq, ack2.server_seq)
        self.assertEqual(ack1.hash, ack2.hash)

        # Ensure total stored is still 1
        stored, latest_seq = self.store.get_events_since(since_seq=0)
        self.assertEqual(len(stored), 1)
        self.assertEqual(latest_seq, 1)

    def test_sync_pull_filters_by_since_seq(self):
        events = [
            CanonicalEvent(
                event_id=f"0192a5b6-7c8d-7e0f-a1b2-c3d4e5f6000{i}",
                patient_id="PAT-401",
                type="LoopOpened",
                author_id="NURSE-01",
                device_id="DEV-A",
                client_created_at="2026-10-21T08:00:00Z",
                payload={"title": f"Loop {i}"},
            )
            for i in range(1, 4)
        ]
        self.store.append_events(events)

        # Pull since seq 2 -> should return only seq 3
        pulled, latest_seq = self.store.get_events_since(since_seq=2)
        self.assertEqual(len(pulled), 1)
        self.assertEqual(pulled[0].server_seq, 3)
        self.assertEqual(latest_seq, 3)

if __name__ == "__main__":
    unittest.main()
