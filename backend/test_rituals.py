import os
import tempfile
import unittest

from backend.rituals import ClinicalRitualStore, RitualCreateRequest


class TestClinicalRitualStore(unittest.TestCase):
    def test_draft_requires_approval_before_record_completion(self):
        with tempfile.TemporaryDirectory() as directory:
            store = ClinicalRitualStore(os.path.join(directory, "rituals.db"))
            ritual = store.create(
                RitualCreateRequest(
                    ritual_type="huddle",
                    title="Bed 12 post-op bleeding",
                    patient_id="PAT-12",
                ),
                "NUR-401",
            )
            store.save_transcript(ritual["ritual_id"], "Discussed urgent review.")
            draft = store.save_draft(
                ritual["ritual_id"],
                {
                    "sections": {
                        "situation": ["Urgent review requested."],
                        "decisions": [],
                    }
                },
            )
            self.assertEqual(draft["status"], "draft_ready")
            approved = store.approve(
                ritual["ritual_id"],
                draft["summary"],
                "DOC-401",
            )
            self.assertEqual(approved["status"], "approved")
            self.assertEqual(approved["approved_by"], "DOC-401")


if __name__ == "__main__":
    unittest.main()
