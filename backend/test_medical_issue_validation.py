import unittest

from .models import CanonicalEvent
from .services.medical_issue_validation import validate_medical_issue_event


def _event(event_id, event_type, author_id, payload, sequence):
    return CanonicalEvent(
        event_id=event_id,
        patient_id="PATIENT-1",
        type=event_type,
        author_id=author_id,
        device_id="DEVICE-1",
        client_created_at=f"2026-10-21T08:0{sequence}:00Z",
        loop_id="ISSUE-1",
        payload=payload,
    )


class TestMedicalIssueValidation(unittest.TestCase):
    def setUp(self):
        self.authorized = {"NURSE-1", "DOCTOR-1", "CHARGE-1"}
        self.doctors = {"DOCTOR-1"}
        self.opened = _event(
            "opened",
            "LoopOpened",
            "NURSE-1",
            {
                "title": "Oxygen saturation dropping",
                "urgency": "critical",
                "initial_owner_id": "NURSE-1",
            },
            1,
        )

    def test_critical_closure_requires_board_doctor_confirmation(self):
        validate_medical_issue_event(
            [], self.opened, self.authorized, self.doctors
        )
        closed = _event(
            "closed",
            "LoopClosed",
            "CHARGE-1",
            {
                "closure_reason": "Oxygen stabilized after intervention.",
                "resolution_type": "resolved",
            },
            2,
        )
        history = [self.opened]
        validate_medical_issue_event(
            history, closed, self.authorized, self.doctors
        )
        history.append(closed)
        nurse_confirmation = _event(
            "nurse-confirmation",
            "LoopClosureConfirmed",
            "NURSE-1",
            {},
            3,
        )
        with self.assertRaisesRegex(ValueError, "board-assigned doctor"):
            validate_medical_issue_event(
                history, nurse_confirmation, self.authorized, self.doctors
            )
        doctor_confirmation = _event(
            "doctor-confirmation",
            "LoopClosureConfirmed",
            "DOCTOR-1",
            {},
            3,
        )
        validate_medical_issue_event(
            history, doctor_confirmation, self.authorized, self.doctors
        )

    def test_message_mentions_must_be_patient_authorized(self):
        history = [self.opened]
        message = _event(
            "message",
            "MessagePosted",
            "NURSE-1",
            {
                "content": "Please review the oxygen trend.",
                "mentioned_staff_ids": ["UNASSIGNED-1"],
            },
            2,
        )
        with self.assertRaisesRegex(ValueError, "mentioned clinician"):
            validate_medical_issue_event(
                history, message, self.authorized, self.doctors
            )

    def test_closure_requires_reason_and_valid_outcome(self):
        missing_reason = _event(
            "closed",
            "LoopClosed",
            "NURSE-1",
            {"resolution_type": "resolved"},
            2,
        )
        with self.assertRaisesRegex(ValueError, "closure reason"):
            validate_medical_issue_event(
                [self.opened], missing_reason, self.authorized, self.doctors
            )

        invalid_outcome = _event(
            "closed",
            "LoopClosed",
            "NURSE-1",
            {
                "closure_reason": "Issue closed.",
                "resolution_type": "unknown",
            },
            2,
        )
        with self.assertRaisesRegex(ValueError, "closure outcome"):
            validate_medical_issue_event(
                [self.opened], invalid_outcome, self.authorized, self.doctors
            )


if __name__ == "__main__":
    unittest.main()
