"""Live HTTP integration test using only explicit isolated test fixtures."""

import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


class TestBackendHttpIntegration(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory(prefix="oravi-api-test-")
        database_path = str(Path(self.temp_dir.name) / "integration.db")
        env = os.environ.copy()
        env["ORAVI_DATABASE_PATH"] = database_path
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
            return error.code, json.loads(error.read())

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

        status_code, incoming_login = self._request(
            "POST",
            "/api/v1/auth/verify-pin",
            payload={"staff_id": "NURSE-INCOMING", "pin": "8765"},
        )
        self.assertEqual(status_code, 200)
        incoming_token = incoming_login["token"]
        status_code, _ = self._request(
            "POST",
            "/api/v1/allocations/ALLOC-TEST/handoff/accept",
            payload={"outgoing_nurse_id": "NURSE-TEST", "beds": ["1"]},
            token=nurse_token,
        )
        self.assertEqual(status_code, 401)
        status_code, transfer = self._request(
            "POST",
            "/api/v1/allocations/ALLOC-TEST/handoff/accept",
            payload={"outgoing_nurse_id": "NURSE-TEST", "beds": ["1"]},
            token=nurse_token,
            incoming_token=incoming_token,
        )
        self.assertEqual(status_code, 200)
        self.assertEqual(transfer["accepted_count"], 1)
        status_code, updated_board = self._request(
            "GET",
            f"/api/v1/wards/WARD-TEST/board?date={today}&shift_type=day",
            token=incoming_token,
        )
        self.assertEqual(status_code, 200)
        self.assertEqual(
            updated_board["bed_assignments"][0]["day_shift_nurse_id"],
            "NURSE-INCOMING",
        )
        self.assertEqual(updated_board["bed_assignments"][0]["status"], "accepted")

        followup = {
            **admission,
            "event_id": "integration-followup",
            "type": "MessagePosted",
            "author_id": "NURSE-INCOMING",
            "client_created_at": "2026-11-03T10:01:00Z",
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

        status_code, pulled = self._request(
            "GET",
            f"/api/v1/sync/pull?ward_id=WARD-TEST&since_seq=0&limit=100",
            token=incoming_token,
        )
        self.assertEqual(status_code, 200)
        self.assertEqual(
            [event["event_id"] for event in pulled["events"]],
            ["integration-admission", "integration-followup"],
        )


if __name__ == "__main__":
    unittest.main()
