import unittest
from .event_store import EventStore
from .models import CanonicalEvent

class TestSyncEngineBackend(unittest.TestCase):
    def setUp(self):
        self.store = EventStore(db_path=":memory:")

    def tearDown(self):
        self.store.close()

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

    def test_ward_pull_includes_followups_and_legacy_patient_id_prefix(self):
        events = [
            CanonicalEvent(
                event_id="ward-admission",
                patient_id="PAT-4B-91",
                type="PatientAdmitted",
                author_id="NUR-401",
                device_id="PHONE-A",
                client_created_at="2026-10-21T08:00:00Z",
                payload={"ward_id": "WARD-4B"},
            ),
            CanonicalEvent(
                event_id="ward-message",
                patient_id="PAT-4B-91",
                type="MessagePosted",
                author_id="NUR-401",
                device_id="PHONE-A",
                client_created_at="2026-10-21T08:05:00Z",
                payload={"content": "Handover note"},
            ),
            CanonicalEvent(
                event_id="other-ward-admission",
                patient_id="PAT-OTHER-01",
                type="PatientAdmitted",
                author_id="NUR-501",
                device_id="PHONE-B",
                client_created_at="2026-10-21T08:10:00Z",
                payload={"ward_id": "WARD-OTHER"},
            ),
        ]
        self.store.append_events(events)

        pulled, _ = self.store.get_events_since(ward_id="WARD-4B")
        self.assertEqual(
            [event.event_id for event in pulled],
            ["ward-admission", "ward-message"],
        )
        self.assertTrue(self.store.patient_belongs_to_ward("PAT-4B-91", "WARD-4B"))
        self.assertEqual(self.store.get_patient_ward("PAT-4B-91"), "WARD-4B")

    def test_notification_outbox_is_atomic_and_idempotent(self):
        event = CanonicalEvent(
            event_id="issue-notification-event",
            patient_id="PAT-401",
            type="LoopOpened",
            author_id="NURSE-01",
            device_id="DEV-A",
            client_created_at="2026-10-21T08:00:00Z",
            loop_id="ISSUE-401",
            payload={"title": "Check oxygen saturation"},
        )
        self.store.append_events(
            [event],
            notification_staff_ids_by_event={
                event.event_id: ["NURSE-01", "DOC-01", "CHARGE-01"]
            },
        )

        queued = self.store.get_due_medical_issue_notifications()
        self.assertEqual(
            {item["staff_id"] for item in queued},
            {"NURSE-01", "DOC-01", "CHARGE-01"},
        )

        self.store.append_events(
            [event],
            notification_staff_ids_by_event={event.event_id: ["NURSE-02"]},
        )
        self.assertEqual(len(self.store.get_due_medical_issue_notifications()), 3)

        self.store.mark_medical_issue_notification_delivered(
            int(queued[0]["notification_id"])
        )
        remaining = self.store.get_due_medical_issue_notifications()
        self.assertEqual(len(remaining), 2)

    def test_notification_retries_track_delivered_installations(self):
        event = CanonicalEvent(
            event_id="installation-retry-event",
            patient_id="PAT-402",
            type="LoopOpened",
            author_id="NURSE-01",
            device_id="DEV-A",
            client_created_at="2026-10-21T08:00:00Z",
            loop_id="ISSUE-402",
            payload={"title": "Review observation"},
        )
        self.store.append_events(
            [event],
            notification_staff_ids_by_event={event.event_id: ["NURSE-01"]},
        )
        notification_id = int(
            self.store.get_due_medical_issue_notifications()[0]["notification_id"]
        )

        self.store.mark_medical_issue_notification_fid_delivered(
            notification_id, "fid-first-device"
        )
        self.assertEqual(
            self.store.get_delivered_medical_issue_fids(notification_id),
            {"fid-first-device"},
        )
        self.store.mark_medical_issue_notification_fid_delivered(
            notification_id, "fid-second-device"
        )
        self.assertEqual(
            self.store.get_delivered_medical_issue_fids(notification_id),
            {"fid-first-device", "fid-second-device"},
        )

if __name__ == "__main__":
    unittest.main()
