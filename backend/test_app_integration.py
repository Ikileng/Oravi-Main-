"""Live HTTP integration test using only explicit isolated test fixtures."""

import json
import os
import socket
import sqlite3
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


class TestBackendHttpIntegration(unittest.TestCase):
    def test_shared_issues_and_replies_across_clinicians_after_local_midnight(self):
        from datetime import datetime, timezone
        from zoneinfo import ZoneInfo

        local_midnight = datetime.now(ZoneInfo('Africa/Nairobi')).replace(
            hour=0, minute=30, second=0, microsecond=0
        )
        today = local_midnight.date().isoformat()
        timestamp = local_midnight.astimezone(timezone.utc).isoformat()
        tokens = {}
        for staff, pin in [('CHARGE-TEST', '1234'), ('NURSE-TEST', '5678'),
                           ('DOC-TEST', '2468'), ('NURSE-INCOMING', '8765')]:
            code, login = self._request('POST', '/api/v1/auth/verify-pin',
                                       payload={'staff_id': staff, 'pin': pin})
            self.assertEqual(code, 200)
            tokens[staff] = login['token']
        code, _ = self._request('PUT', '/api/v1/staff/me/ward-context',
                                payload={'ward_id': 'WARD-TEST'}, token=tokens['CHARGE-TEST'])
        self.assertEqual(code, 200)
        code, body = self._request('POST', '/api/v1/allocations/publish',
            token=tokens['CHARGE-TEST'], payload={
                'allocation_id': 'SHARED-NIGHT', 'ward_id': 'WARD-TEST',
                'shift_type': 'night', 'date': today, 'published_by': 'CHARGE-TEST',
                'published_at': timestamp, 'support_roster': {},
                'bed_assignments': [{'bed_number': '1', 'patient_id': 'SHARED-PATIENT',
                    'patient_initials': 'T.S.', 'admitting_doctor': 'DOC-TEST',
                    'assigned_nurse_id': 'NURSE-TEST', 'status': 'accepted'}]})
        self.assertEqual(code, 200, body)
        event_ids = set()
        for author, other in [('NURSE-TEST', 'DOC-TEST'), ('DOC-TEST', 'NURSE-TEST')]:
            issue_id = 'ISSUE-' + author
            for event_id, event_type, writer, payload in [
                (issue_id, 'LoopOpened', author, {'title': 'Review observations',
                    'urgency': 'urgent', 'initial_owner_id': author}),
                ('REPLY-' + author, 'MessagePosted', other, {'content': 'Please repeat observations'})]:
                event = {'event_id': event_id, 'patient_id': 'SHARED-PATIENT',
                         'loop_id': issue_id, 'type': event_type, 'author_id': writer,
                         'device_id': 'PHONE-' + writer, 'client_created_at': timestamp,
                         'payload': payload}
                code, body = self._request('POST', '/api/v1/sync/push', token=tokens[writer],
                    payload={'device_id': 'PHONE-' + writer, 'events': [event]})
                self.assertEqual(code, 200, body)
                self.assertEqual(body['acknowledged_count'], 1, body)
                event_ids.add(event_id)
        for staff in ['NURSE-TEST', 'DOC-TEST', 'CHARGE-TEST']:
            code, body = self._request('GET', '/api/v1/sync/pull?ward_id=WARD-TEST&since_seq=0',
                                       token=tokens[staff])
            self.assertEqual(code, 200, body)
            self.assertEqual({e['event_id'] for e in body['events']}, event_ids)
            code, thread = self._request('GET', '/api/v1/patients/SHARED-PATIENT/medical-issues/ISSUE-NURSE-TEST',
                                         token=tokens[staff])
            self.assertEqual(code, 200, thread)
            self.assertEqual(len(thread['events']), 2)
        code, _ = self._request('GET', '/api/v1/patients/SHARED-PATIENT/medical-issues/ISSUE-NURSE-TEST',
                                token=tokens['NURSE-INCOMING'])
        self.assertEqual(code, 404)

    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory(prefix="oravi-api-test-")
        self.database_path = str(Path(self.temp_dir.name) / "integration.db")
        database_path = self.database_path
        env = os.environ.copy()
        env["ORAVI_DATABASE_PATH"] = database_path
        env["ORAVI_TIMEZONE"] = "Africa/Nairobi"
        repo_root = str(Path(__file__).resolve().parents[1])
        env["PYTHONPATH"] = os.pathsep.join(
            [repo_root, env.get("PYTHONPATH", "")]
        )
        sys.path.insert(0, repo_root)
        from backend.models import HospitalWardModel
        from backend.staff_store import StaffStore
        from backend.ward_store import WardStore

        staff_store = StaffStore(db_path=database_path)
        staff_store.create_first_admin("ADM-TEST", "Test Admin", "123456")
        staff_store.create_staff(
            "CHARGE-TEST", "Charge Test", "charge_nurse", "", "1234"
        )
        staff_store.create_staff(
            "NURSE-TEST", "Nurse Test", "ward_nurse", "", "5678"
        )
        staff_store.create_staff(
            "NURSE-INCOMING", "Incoming Nurse", "ward_nurse", "", "8765"
        )
        staff_store.create_staff(
            "DOC-TEST", "Doctor Test", "doctor_on_call", "", "2468"
        )
        staff_store.close()
        ward_store = WardStore(db_path=database_path)
        ward_store.create_ward(
            HospitalWardModel(
                ward_id="WARD-TEST",
                name="Test Ward",
                bed_count=2,
                bed_numbers=["1", "2"],
                department="Test",
                description="Isolated API test ward",
            )
        )

        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            self.port = sock.getsockname()[1]
        self.base_url = f"http://127.0.0.1:{self.port}"
        self.server = subprocess.Popen(
            [
                sys.executable,
                "-m",
                "uvicorn",
                "backend.main:app",
                "--host",
                "127.0.0.1",
                "--port",
                str(self.port),
                "--log-level",
                "error",
            ],
            cwd=repo_root,
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        try:
            self._wait_for_server()
        except Exception:
            if self.server.poll() is None:
                self.server.terminate()
                self.server.wait(timeout=10)
            self.temp_dir.cleanup()
            raise

    def tearDown(self):
        if self.server.poll() is None:
            self.server.terminate()
            self.server.wait(timeout=10)
        # Collect fixture SQLite connections before deleting their files on Windows.
        import gc
        gc.collect()
        self.temp_dir.cleanup()

    def _wait_for_server(self):
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            if self.server.poll() is not None:
                self.fail("The backend server exited before becoming ready.")
            try:
                with urlopen(f"{self.base_url}/health", timeout=1) as response:
                    if response.status == 200:
                        return
            except (OSError, URLError):
                time.sleep(0.1)
        self.fail("The backend server did not become ready in time.")

    def _request(
        self, method, path, *, payload=None, token=None, incoming_token=None
    ):
        headers = {}
        data = None
        if payload is not None:
            headers["Content-Type"] = "application/json"
            data = json.dumps(payload).encode("utf-8")
        if token is not None:
            headers["Authorization"] = f"Bearer {token}"
        if incoming_token is not None:
            headers["X-Incoming-Authorization"] = f"Bearer {incoming_token}"
        request = Request(
            f"{self.base_url}{path}",
            data=data,
            headers=headers,
            method=method,
        )
        try:
            with urlopen(request, timeout=5) as response:
                return response.status, json.loads(response.read())
        except HTTPError as error:
            try:
                return error.code, json.loads(error.read())
            finally:
                error.close()

    def test_charge_publishes_board_nurse_reads_assigned_ward_and_syncs(self):
        status_code, login = self._request(
            "POST",
            "/api/v1/auth/verify-pin",
            payload={"staff_id": "CHARGE-TEST", "pin": "1234"},
        )
        self.assertEqual(status_code, 200)

        self.assertTrue(login["success"])
        charge_token = login["token"]

        status_code, wards = self._request(
            "GET", "/api/v1/wards", token=charge_token
        )
        self.assertEqual(status_code, 200)
        self.assertEqual([ward["ward_id"] for ward in wards], ["WARD-TEST"])
        status_code, _ = self._request(
            "PUT",
            "/api/v1/staff/me/ward-context",
            payload={"ward_id": "WARD-TEST"},
            token=charge_token,
        )
        self.assertEqual(status_code, 200)

        today = time.strftime("%Y-%m-%d")
        status_code, published = self._request(
            "POST",
            "/api/v1/allocations/publish",
            payload={
                "allocation_id": "ALLOC-TEST",
                "ward_id": "WARD-TEST",
                "shift_type": "day",
                "date": today,
                "published_by": "CHARGE-TEST",
                "published_at": "2026-11-03T10:00:00Z",
                "support_roster": {},
                "bed_assignments": [
                    {
                        "bed_number": "1",
                        "patient_id": "PATIENT-TEST-1",
                        "patient_initials": "T.S.",
                        "admitting_doctor": "DOC-TEST",
                        "assigned_nurse_id": "NURSE-TEST",
                        "status": "accepted",
                    },
                    {
                        "bed_number": "2",
                        "patient_id": "PATIENT-TEST-2",
                        "patient_initials": "U.V.",
                        "admitting_doctor": "DOC-TEST",
                        "assigned_nurse_id": "NURSE-INCOMING",
                        "status": "pending",
                    }
                ],
            },
            token=charge_token,
        )
        self.assertEqual(status_code, 200)
        self.assertEqual(published["allocation_id"], "ALLOC-TEST")

        status_code, nurse_login = self._request(
            "POST",
            "/api/v1/auth/verify-pin",
            payload={"staff_id": "NURSE-TEST", "pin": "5678"},
        )
        self.assertEqual(status_code, 200)
        nurse_token = nurse_login["token"]
        status_code, assignment = self._request(
            "GET",
            f"/api/v1/staff/me/active-assignment?date={today}&shift_type=day",
            token=nurse_token,
        )
        self.assertEqual(status_code, 200)
        self.assertEqual(assignment["active_assignment"]["ward_id"], "WARD-TEST")

        status_code, board = self._request(
            "GET",
            f"/api/v1/wards/WARD-TEST/board?date={today}&shift_type=day",
            token=nurse_token,
        )
        self.assertEqual(status_code, 200)
        self.assertEqual(
            board["bed_assignments"][0]["patient_id"],
            "PATIENT-TEST-1",
        )
        status_code, patient_staff = self._request(
            "GET",
            f"/api/v1/patients/PATIENT-TEST-1/staff?date={today}",
            token=nurse_token,
        )
        self.assertEqual(status_code, 200)
        self.assertEqual(
            {staff["staff_id"] for staff in patient_staff["staff"]},
            {"CHARGE-TEST", "NURSE-TEST", "DOC-TEST"},
        )
        status_code, _ = self._request(
            "GET",
            f"/api/v1/patients/PATIENT-TEST-2/staff?date={today}",
            token=nurse_token,
        )
        self.assertEqual(status_code, 403)

        admission = {
            "event_id": "integration-admission",
            "patient_id": "PATIENT-TEST-1",
            "type": "PatientAdmitted",
            "author_id": "NURSE-TEST",
            "device_id": "PHONE-INTEGRATION",
            "client_created_at": f"{today}T10:00:00Z",
            "payload": {"ward_id": "WARD-TEST"},
        }
        status_code, pushed = self._request(
            "POST",
            "/api/v1/sync/push",
            payload={"device_id": "PHONE-INTEGRATION", "events": [admission]},
            token=nurse_token,
        )
        self.assertEqual(status_code, 200)
        self.assertEqual(pushed["acknowledged_count"], 1)
        handoff_loop_id = "ISSUE-HANDOFF-1"
        handoff_issue = {
            "event_id": "integration-handoff-issue-opened",
            "patient_id": "PATIENT-TEST-1",
            "type": "LoopOpened",
            "author_id": "NURSE-TEST",
            "device_id": "PHONE-INTEGRATION",
            "client_created_at": f"{today}T10:00:30Z",
            "loop_id": handoff_loop_id,
            "payload": {
                "title": "Monitor oxygen saturation",
                "description": "Review the next observation.",
                "loop_type": "escalation",
                "urgency": "urgent",
                "initial_owner_id": "NURSE-TEST",
                "initial_owner_role": "ward_nurse",
            },
        }
        handoff_discussion = {
            "event_id": "integration-handoff-issue-discussion",
            "patient_id": "PATIENT-TEST-1",
            "type": "MessagePosted",
            "author_id": "NURSE-TEST",
            "device_id": "PHONE-INTEGRATION",
            "client_created_at": f"{today}T10:00:35Z",
            "loop_id": handoff_loop_id,
            "payload": {"content": "The last observation showed a decline."},
        }
        status_code, pushed = self._request(
            "POST",
            "/api/v1/sync/push",
            payload={
                "device_id": "PHONE-INTEGRATION",
                "events": [handoff_issue, handoff_discussion],
            },
            token=nurse_token,
        )
        self.assertEqual(status_code, 200)
        self.assertEqual(pushed["acknowledged_count"], 2)
        unauthorized_event = {
            **admission,
            "event_id": "integration-unauthorized-patient-event",
            "patient_id": "PATIENT-TEST-2",
        }
        status_code, rejected = self._request(
            "POST",
            "/api/v1/sync/push",
            payload={
                "device_id": "PHONE-INTEGRATION",
                "events": [unauthorized_event],
            },
            token=nurse_token,
        )
        self.assertEqual(status_code, 200)
        self.assertEqual(rejected["status"], "partial")
        self.assertEqual(
            rejected["rejected"][0]["event_id"],
            "integration-unauthorized-patient-event",
        )

        status_code, incoming_login = self._request(
            "POST",
            "/api/v1/auth/verify-pin",
            payload={"staff_id": "NURSE-INCOMING", "pin": "8765"},
        )
        self.assertEqual(status_code, 200)
        incoming_token = incoming_login["token"]
        handoff_start = {
            "event_id": "integration-handoff-started",
            "patient_id": "WARD-TEST",
            "type": "HandoffStarted",
            "author_id": "NURSE-TEST",
            "device_id": "PHONE-INTEGRATION",
            "client_created_at": f"{today}T10:00:45Z",
            "payload": {
                "handoff_session_id": "HANDOFF-INTEGRATION",
                "ward_id": "WARD-TEST",
                "outgoing_nurse_id": "NURSE-TEST",
                "incoming_nurse_id": "NURSE-INCOMING",
            },
        }
        status_code, _ = self._request(
            "POST",
            "/api/v1/sync/push",
            payload={"device_id": "PHONE-INTEGRATION", "events": [handoff_start]},
            token=nurse_token,
        )
        self.assertEqual(status_code, 200)
        status_code, _ = self._request(
            "POST",
            "/api/v1/allocations/ALLOC-TEST/handoff/accept",
            payload={
                "outgoing_nurse_id": "NURSE-TEST",
                "beds": ["1"],
                "handoff_session_id": "HANDOFF-INTEGRATION",
                "transferred_loop_ids_by_patient": {
                    "PATIENT-TEST-1": [handoff_loop_id]
                },
            },
            token=nurse_token,
        )
        self.assertEqual(status_code, 401)
        status_code, transfer = self._request(
            "POST",
            "/api/v1/allocations/ALLOC-TEST/handoff/accept",
            payload={
                "outgoing_nurse_id": "NURSE-TEST",
                "beds": ["1"],
                "handoff_session_id": "HANDOFF-INTEGRATION",
                "transferred_loop_ids_by_patient": {
                    "PATIENT-TEST-1": [handoff_loop_id]
                },
            },
            token=nurse_token,
            incoming_token=incoming_token,
        )
        self.assertEqual(status_code, 200)
        self.assertEqual(transfer["accepted_count"], 1)
        status_code, updated_board = self._request(
            "GET",
            f"/api/v1/wards/WARD-TEST/board?date={today}&shift_type=night",
            token=incoming_token,
        )
        self.assertEqual(status_code, 200)
        self.assertEqual(
            updated_board["bed_assignments"][0]["day_shift_nurse_id"],
            None,
        )
        self.assertEqual(
            updated_board["bed_assignments"][0]["night_shift_nurse_id"],
            "NURSE-INCOMING",
        )
        accepted_bed = {
            "event_id": "integration-handoff-bed-accepted",
            "patient_id": "PATIENT-TEST-1",
            "type": "HandoffBedAccepted",
            "author_id": "NURSE-TEST",
            "device_id": "PHONE-INTEGRATION",
            "client_created_at": f"{today}T10:01:00Z",
            "payload": {
                "handoff_session_id": "HANDOFF-INTEGRATION",
                "bed_number": "1",
                "nothing_pending_confirmed": False,
                "transferred_loop_ids": [handoff_loop_id],
            },
        }
        ownership_transfer = {
            "event_id": "integration-handoff-issue-owner-changed",
            "patient_id": "PATIENT-TEST-1",
            "type": "LoopOwnerChanged",
            "author_id": "NURSE-TEST",
            "device_id": "PHONE-INTEGRATION",
            "client_created_at": f"{today}T10:01:01Z",
            "loop_id": handoff_loop_id,
            "payload": {
                "new_owner_id": "NURSE-INCOMING",
                "new_owner_role": "ward_nurse",
                "transfer_reason": "Shift handoff transfer to NURSE-INCOMING",
                "handoff_session_id": "HANDOFF-INTEGRATION",
            },
        }
        handoff_complete = {
            "event_id": "integration-handoff-completed",
            "patient_id": "WARD-TEST",
            "type": "HandoffCompleted",
            "author_id": "NURSE-TEST",
            "device_id": "PHONE-INTEGRATION",
            "client_created_at": f"{today}T10:02:00Z",
            "payload": {
                "handoff_session_id": "HANDOFF-INTEGRATION",
                "total_beds_handed_over": 1,
                "total_loops_transferred": 1,
            },
        }
        status_code, pushed = self._request(
            "POST",
            "/api/v1/sync/push",
            payload={
                "device_id": "PHONE-INTEGRATION",
                "events": [accepted_bed, ownership_transfer, handoff_complete],
            },
            token=nurse_token,
        )
        self.assertEqual(status_code, 200)
        self.assertEqual(pushed["acknowledged_count"], 3)

        status_code, outgoing_pull = self._request(
            "GET",
            f"/api/v1/sync/pull?ward_id=WARD-TEST&since_seq=0&limit=100",
            token=nurse_token,
        )
        self.assertEqual(status_code, 200)
        outgoing_event_ids = {
            event["event_id"] for event in outgoing_pull["events"]
        }
        self.assertIn("integration-handoff-started", outgoing_event_ids)
        self.assertIn("integration-handoff-completed", outgoing_event_ids)
        self.assertNotIn("integration-admission", outgoing_event_ids)
        self.assertNotIn("integration-handoff-issue-opened", outgoing_event_ids)

        outgoing_followup = {
            **admission,
            "event_id": "integration-outgoing-after-acceptance",
            "type": "MessagePosted",
            "author_id": "NURSE-TEST",
            "client_created_at": f"{today}T10:01:02Z",
            "loop_id": handoff_loop_id,
            "payload": {"content": "This must be rejected after handoff."},
        }
        status_code, rejected = self._request(
            "POST",
            "/api/v1/sync/push",
            payload={"device_id": "PHONE-INTEGRATION", "events": [outgoing_followup]},
            token=nurse_token,
        )
        self.assertEqual(status_code, 200)
        self.assertEqual(rejected["status"], "partial")
        self.assertEqual(
            rejected["rejected"][0]["event_id"],
            "integration-outgoing-after-acceptance",
        )

        followup = {
            **admission,
            "event_id": "integration-followup",
            "type": "MessagePosted",
            "author_id": "NURSE-INCOMING",
            "client_created_at": f"{today}T10:01:00Z",
            "payload": {"content": "Integration test event"},
        }
        status_code, pushed = self._request(
            "POST",
            "/api/v1/sync/push",
            payload={"device_id": "PHONE-INTEGRATION", "events": [followup]},
            token=incoming_token,
        )
        self.assertEqual(status_code, 200)
        self.assertEqual(pushed["acknowledged_count"], 1)
        handoff_reply = {
            **admission,
            "event_id": "integration-handoff-issue-reply",
            "type": "MessagePosted",
            "author_id": "NURSE-INCOMING",
            "client_created_at": f"{today}T10:02:30Z",
            "loop_id": handoff_loop_id,
            "payload": {"content": "I reviewed the previous observations."},
        }
        status_code, pushed = self._request(
            "POST",
            "/api/v1/sync/push",
            payload={"device_id": "PHONE-INTEGRATION", "events": [handoff_reply]},
            token=incoming_token,
        )
        self.assertEqual(status_code, 200)
        self.assertEqual(pushed["acknowledged_count"], 1)

        status_code, pulled = self._request(
            "GET",
            f"/api/v1/sync/pull?ward_id=WARD-TEST&since_seq=0&limit=100",
            token=incoming_token,
        )
        self.assertEqual(status_code, 200)
        pulled_event_ids = {event["event_id"] for event in pulled["events"]}
        self.assertTrue(
            {
                "integration-admission",
                "integration-followup",
                "integration-handoff-started",
                "integration-handoff-bed-accepted",
                "integration-handoff-issue-opened",
                "integration-handoff-issue-discussion",
                "integration-handoff-issue-owner-changed",
                "integration-handoff-issue-reply",
                "integration-handoff-completed",
            }.issubset(pulled_event_ids)
        )

        loop_id = "ISSUE-INTEGRATION-CRITICAL"
        issue_events = [
            {
                "event_id": "integration-issue-opened",
                "patient_id": "PATIENT-TEST-1",
                "type": "LoopOpened",
                "author_id": "NURSE-INCOMING",
                "device_id": "PHONE-INTEGRATION",
                "client_created_at": f"{today}T10:02:00Z",
                "loop_id": loop_id,
                "payload": {
                    "title": "Oxygen saturation dropping",
                    "description": "Escalate for urgent review.",
                    "loop_type": "escalation",
                    "urgency": "critical",
                    "initial_owner_id": "NURSE-INCOMING",
                    "initial_owner_role": "ward_nurse",
                },
            },
            {
                "event_id": "integration-issue-closed",
                "patient_id": "PATIENT-TEST-1",
                "type": "LoopClosed",
                "author_id": "NURSE-INCOMING",
                "device_id": "PHONE-INTEGRATION",
                "client_created_at": f"{today}T10:03:00Z",
                "loop_id": loop_id,
                "payload": {
                    "closure_reason": "Oxygen saturation stabilized after intervention.",
                    "resolution_type": "resolved",
                },
            },
        ]
        status_code, _ = self._request(
            "POST",
            "/api/v1/sync/push",
            payload={"device_id": "PHONE-INTEGRATION", "events": issue_events},
            token=incoming_token,
        )
        self.assertEqual(status_code, 200)

        unauthorized_confirmation = {
            "event_id": "integration-issue-confirmed-by-nurse",
            "patient_id": "PATIENT-TEST-1",
            "type": "LoopClosureConfirmed",
            "author_id": "NURSE-INCOMING",
            "device_id": "PHONE-INTEGRATION",
            "client_created_at": f"{today}T10:04:00Z",
            "loop_id": loop_id,
            "payload": {"confirmed_by_role": "ward_nurse"},
        }
        status_code, _ = self._request(
            "POST",
            "/api/v1/sync/push",
            payload={
                "device_id": "PHONE-INTEGRATION",
                "events": [unauthorized_confirmation],
            },
            token=incoming_token,
        )
        self.assertEqual(status_code, 409)

        status_code, doctor_login = self._request(
            "POST",
            "/api/v1/auth/verify-pin",
            payload={"staff_id": "DOC-TEST", "pin": "2468"},
        )
        self.assertEqual(status_code, 200)
        confirmation = {
            **unauthorized_confirmation,
            "event_id": "integration-issue-confirmed-by-doctor",
            "author_id": "DOC-TEST",
            "payload": {"confirmed_by_role": "doctor_on_call"},
        }
        status_code, _ = self._request(
            "POST",
            "/api/v1/sync/push",
            payload={"device_id": "PHONE-INTEGRATION", "events": [confirmation]},
            token=doctor_login["token"],
        )
        self.assertEqual(status_code, 200)

        routine_loop_id = "ISSUE-INTEGRATION-ROUTINE"
        routine_events = [
            {
                "event_id": "integration-routine-opened",
                "patient_id": "PATIENT-TEST-1",
                "type": "LoopOpened",
                "author_id": "NURSE-INCOMING",
                "device_id": "PHONE-INTEGRATION",
                "client_created_at": f"{today}T10:05:00Z",
                "loop_id": routine_loop_id,
                "payload": {
                    "title": "Repeat blood pressure",
                    "description": "Recheck after observation.",
                    "loop_type": "task_or_pending_result",
                    "urgency": "routine",
                    "initial_owner_id": "NURSE-INCOMING",
                    "initial_owner_role": "ward_nurse",
                },
            },
            {
                "event_id": "integration-routine-message",
                "patient_id": "PATIENT-TEST-1",
                "type": "MessagePosted",
                "author_id": "NURSE-INCOMING",
                "device_id": "PHONE-INTEGRATION",
                "client_created_at": f"{today}T10:06:00Z",
                "loop_id": routine_loop_id,
                "payload": {
                    "content": "Doctor, please review this repeat reading.",
                    "mentioned_staff_ids": ["DOC-TEST"],
                },
            },
        ]
        status_code, _ = self._request(
            "POST",
            "/api/v1/sync/push",
            payload={"device_id": "PHONE-INTEGRATION", "events": routine_events},
            token=incoming_token,
        )
        self.assertEqual(status_code, 200)
        connection = sqlite3.connect(self.database_path)
        try:
            new_issue_recipients = {
                row[0]
                for row in connection.execute(
                    """SELECT staff_id FROM medical_issue_notification_outbox
                       WHERE event_id = 'integration-issue-opened'"""
                )
            }
            message_recipients = {
                row[0]
                for row in connection.execute(
                    """SELECT staff_id FROM medical_issue_notification_outbox
                       WHERE event_id = 'integration-routine-message'"""
                )
            }
            handoff_reply_recipients = {
                row[0]
                for row in connection.execute(
                    """SELECT staff_id FROM medical_issue_notification_outbox
                       WHERE event_id = 'integration-handoff-issue-reply'"""
                )
            }
        finally:
            connection.close()
        self.assertEqual(
            new_issue_recipients,
            {"CHARGE-TEST", "DOC-TEST"},
        )
        # Push notifications exclude the author; shared thread access does not.
        self.assertEqual(message_recipients, {"DOC-TEST"})
        self.assertEqual(
            handoff_reply_recipients,
            set(),
        )

    def test_final_board_removal_carries_open_issue_with_thread_only_access(self):
        today = time.strftime("%Y-%m-%d")
        status_code, charge_login = self._request(
            "POST",
            "/api/v1/auth/verify-pin",
            payload={"staff_id": "CHARGE-TEST", "pin": "1234"},
        )
        self.assertEqual(status_code, 200)
        charge_token = charge_login["token"]
        status_code, _ = self._request(
            "PUT",
            "/api/v1/staff/me/ward-context",
            payload={"ward_id": "WARD-TEST"},
            token=charge_token,
        )
        self.assertEqual(status_code, 200)

        status_code, nurse_login = self._request(
            "POST",
            "/api/v1/auth/verify-pin",
            payload={"staff_id": "NURSE-TEST", "pin": "5678"},
        )
        self.assertEqual(status_code, 200)
        nurse_token = nurse_login["token"]
        status_code, owner_login = self._request(
            "POST",
            "/api/v1/auth/verify-pin",
            payload={"staff_id": "NURSE-INCOMING", "pin": "8765"},
        )
        self.assertEqual(status_code, 200)
        owner_token = owner_login["token"]

        status_code, _ = self._request(
            "POST",
            "/api/v1/allocations/publish",
            payload={
                "allocation_id": "ALLOC-CARRY-FORWARD",
                "ward_id": "WARD-TEST",
                "shift_type": "day",
                "date": today,
                "published_by": "CHARGE-TEST",
                "published_at": f"{today}T10:00:00Z",
                "support_roster": {},
                "bed_assignments": [
                    {
                        "bed_number": "1",
                        "patient_id": "PATIENT-CARRY",
                        "patient_initials": "C.F.",
                        "admitting_doctor": "DOC-TEST",
                        "assigned_nurse_id": "NURSE-TEST",
                        "status": "accepted",
                    }
                ],
            },
            token=charge_token,
        )
        self.assertEqual(status_code, 200)

        issue_id = "ISSUE-CARRY-FORWARD"
        issue_events = [
            {
                "event_id": "integration-carry-admission",
                "patient_id": "PATIENT-CARRY",
                "type": "PatientAdmitted",
                "author_id": "NURSE-TEST",
                "device_id": "PHONE-INTEGRATION",
                "client_created_at": f"{today}T10:01:00Z",
                "payload": {"ward_id": "WARD-TEST"},
            },
            {
                "event_id": "integration-carry-opened",
                "patient_id": "PATIENT-CARRY",
                "type": "LoopOpened",
                "author_id": "NURSE-TEST",
                "device_id": "PHONE-INTEGRATION",
                "client_created_at": f"{today}T10:02:00Z",
                "loop_id": issue_id,
                "payload": {
                    "title": "Monitor oxygen saturation",
                    "description": "Review the next observation.",
                    "loop_type": "escalation",
                    "urgency": "urgent",
                    "initial_owner_id": "NURSE-TEST",
                    "initial_owner_role": "ward_nurse",
                },
            },
            {
                "event_id": "integration-carry-discussion",
                "patient_id": "PATIENT-CARRY",
                "type": "MessagePosted",
                "author_id": "NURSE-TEST",
                "device_id": "PHONE-INTEGRATION",
                "client_created_at": f"{today}T10:03:00Z",
                "loop_id": issue_id,
                "payload": {"content": "Please review the latest observation."},
            },
        ]
        status_code, _ = self._request(
            "POST",
            "/api/v1/sync/push",
            payload={"device_id": "PHONE-INTEGRATION", "events": issue_events},
            token=nurse_token,
        )
        self.assertEqual(status_code, 200)

        removal = {
            "allocation_id": "ALLOC-CARRY-MISSING-OWNER",
            "ward_id": "WARD-TEST",
            "shift_type": "day",
            "date": today,
            "published_by": "CHARGE-TEST",
            "published_at": f"{today}T10:04:00Z",
            "support_roster": {},
            "bed_assignments": [],
            "carry_forward_issues": [],
        }
        status_code, _ = self._request(
            "POST",
            "/api/v1/allocations/publish",
            payload=removal,
            token=charge_token,
        )
        self.assertEqual(status_code, 409)
        status_code, board = self._request(
            "GET",
            f"/api/v1/wards/WARD-TEST/board?date={today}&shift_type=day",
            token=charge_token,
        )
        self.assertEqual(status_code, 200)
        self.assertEqual(board["bed_assignments"][0]["patient_id"], "PATIENT-CARRY")

        removal["allocation_id"] = "ALLOC-CARRY-VALID"
        removal["carry_forward_issues"] = [
            {
                "patient_id": "PATIENT-CARRY",
                "loop_id": issue_id,
                "owner_id": "NURSE-INCOMING",
                "reason": "",
            }
        ]
        status_code, published = self._request(
            "POST",
            "/api/v1/allocations/publish",
            payload=removal,
            token=charge_token,
        )
        self.assertEqual(status_code, 200)
        self.assertEqual(len(published["carry_forward_events"]), 1)

        status_code, _ = self._request(
            "GET",
            f"/api/v1/patients/PATIENT-CARRY/staff?date={today}",
            token=owner_token,
        )
        self.assertEqual(status_code, 403)
        status_code, carried = self._request(
            "GET", "/api/v1/medical-issues/carried", token=owner_token
        )
        self.assertEqual(status_code, 200)
        self.assertEqual([item["loop_id"] for item in carried["issues"]], [issue_id])
        self.assertEqual(
            {event["event_id"] for event in carried["issues"][0]["events"]},
            {
                "integration-carry-opened",
                "integration-carry-discussion",
                published["carry_forward_events"][0]["event_id"],
            },
        )
        status_code, issue_thread = self._request(
            "GET",
            f"/api/v1/patients/PATIENT-CARRY/medical-issues/{issue_id}",
            token=owner_token,
        )
        self.assertEqual(status_code, 200)
        self.assertEqual(issue_thread["patient_id"], "PATIENT-CARRY")
        self.assertEqual(issue_thread["loop_id"], issue_id)
        self.assertNotIn(
            "integration-carry-admission",
            {event["event_id"] for event in issue_thread["events"]},
        )
        status_code, _ = self._request(
            "GET",
            f"/api/v1/patients/PATIENT-CARRY/medical-issues/{issue_id}",
            token=nurse_token,
        )
        self.assertEqual(status_code, 404)

        status_code, pulled = self._request(
            "GET",
            f"/api/v1/sync/pull?ward_id=WARD-TEST&since_seq=0&limit=100",
            token=owner_token,
        )
        self.assertEqual(status_code, 200)
        pulled_ids = {event["event_id"] for event in pulled["events"]}
        self.assertIn("integration-carry-opened", pulled_ids)
        self.assertIn("integration-carry-discussion", pulled_ids)
        self.assertNotIn("integration-carry-admission", pulled_ids)

        owner_reply = {
            **issue_events[2],
            "event_id": "integration-carry-owner-reply",
            "author_id": "NURSE-INCOMING",
            "client_created_at": f"{today}T10:05:00Z",
            "payload": {"content": "I will review this issue."},
        }
        status_code, _ = self._request(
            "POST",
            "/api/v1/sync/push",
            payload={"device_id": "PHONE-INTEGRATION", "events": [owner_reply]},
            token=owner_token,
        )
        self.assertEqual(status_code, 200)

        unrelated_issue = {
            **owner_reply,
            "event_id": "integration-carry-unrelated",
            "patient_id": "PATIENT-TEST-2",
            "loop_id": "ISSUE-UNRELATED",
        }
        status_code, rejected = self._request(
            "POST",
            "/api/v1/sync/push",
            payload={
                "device_id": "PHONE-INTEGRATION",
                "events": [unrelated_issue],
            },
            token=owner_token,
        )
        self.assertEqual(status_code, 200)
        self.assertEqual(rejected["status"], "partial")
        self.assertEqual(
            rejected["rejected"][0]["event_id"],
            "integration-carry-unrelated",
        )


if __name__ == "__main__":
    unittest.main()
