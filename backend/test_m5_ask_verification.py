import os
import unittest
from backend.event_store import EventStore
from backend.models import CanonicalEvent
from backend.services.clinical_tools import execute_query_patient_timeline
from backend.services.verification_harness import VerificationHarness
from backend.services.llm_service import LLMService

class TestM5AskVerification(unittest.TestCase):
    def setUp(self):
        self.store = EventStore(db_path=":memory:")
        # Seed test events
        self.events = [
            CanonicalEvent(
                event_id="evt-1",
                patient_id="PAT-4B-01",
                author_id="NURSE-WANJIKU",
                device_id="DEV-A",
                type="MessagePosted",
                payload={"content": "Urine output 30ml in last 2 hours. Foley draining dark amber."},
                client_created_at="2026-10-23T06:00:00Z",
                server_received_at="2026-10-23T06:00:01Z",
                loop_id="loop-uo",
            ),
            CanonicalEvent(
                event_id="evt-2",
                patient_id="PAT-4B-01",
                author_id="DOC-OTIENO",
                device_id="DEV-A",
                type="MessagePosted",
                payload={"content": "SpO2 88% on room air at 07:15. Commenced oxygen 2L/min via nasal prongs."},
                client_created_at="2026-10-23T07:15:00Z",
                server_received_at="2026-10-23T07:15:01Z",
                loop_id="loop-resp",
            ),
            CanonicalEvent(
                event_id="evt-3",
                patient_id="PAT-4B-01",
                author_id="NURSE-WANJIKU",
                device_id="DEV-A",
                type="MessagePosted",
                payload={"content": "Sats improved to 94% on 2L oxygen at 08:00."},
                client_created_at="2026-10-23T08:00:00Z",
                server_received_at="2026-10-23T08:00:01Z",
                loop_id="loop-resp",
            ),
            CanonicalEvent(
                event_id="evt-4",
                patient_id="PAT-4B-01",
                author_id="CO-MUTUA",
                device_id="DEV-A",
                type="LoopOpened",
                payload={"title": "Cross-match 2 units PRBC", "description": "Urgent cross-match requested from lab for pre-op hb 7.1"},
                client_created_at="2026-10-23T08:30:00Z",
                server_received_at="2026-10-23T08:30:01Z",
                loop_id="loop-blood",
            ),
        ]
        self.store.append_events(self.events)

    def tearDown(self):
        self.store.close()

    def test_kiswahili_and_synonym_retrieval(self):
        # Querying 'mkojo' should retrieve urine output event
        res_mkojo = execute_query_patient_timeline(self.store, "PAT-4B-01", "mkojo")
        self.assertEqual(len(res_mkojo["quotes"]), 1)
        self.assertIn("30ml", res_mkojo["quotes"][0]["verbatim_text"])

        # Querying 'oxygen' should retrieve SpO2 / sats events
        res_o2 = execute_query_patient_timeline(self.store, "PAT-4B-01", "oxygen")
        self.assertEqual(len(res_o2["quotes"]), 2)

    def test_diagnostic_refusal_rule_4(self):
        # Querying diagnostic prompt "Does patient have kidney failure?"
        query = "Does patient have kidney failure?"
        res = VerificationHarness.verify(
            query=query,
            raw_patient_events=self.events,
            model_output={"verbatim_quotes": [], "observation_note": None}
        )
        self.assertTrue(res.is_refusal)
        self.assertIn("I cannot diagnose or predict", res.refusal_message)

    def test_absence_statement_rule_5(self):
        # Querying allergies when no record exists
        query = "penicillin allergy"
        res = VerificationHarness.verify(
            query=query,
            raw_patient_events=self.events,
            model_output={"verbatim_quotes": [], "observation_note": None}
        )
        self.assertTrue(res.is_absence)
        self.assertIn("No record in Oravi mentions 'penicillin allergy'", res.absence_message)
        self.assertIn("Absence of a mention does not mean there was no change", res.absence_message)

    def test_missing_record_blocks_model_reassurance(self):
        result = VerificationHarness.verify(
            query="urine",
            raw_patient_events=[],
            model_output={"verbatim_quotes": [], "observation_note": "Urine is normal. All clear."},
        )
        self.assertTrue(result.is_absence)
        self.assertIsNone(result.verified_observation)
        self.assertIn("main hospital EHR", result.absence_message)
        self.assertIn("Oravi has not searched", result.absence_message)

    def test_hallucination_number_stripping_rule_2(self):
        # Model claims numbers not present in raw quotes (e.g. 120/80 or 40ml)
        model_output = {
            "verbatim_quotes": [
                {
                    "verbatim_text": "Urine output 30ml in last 2 hours. Foley draining dark amber.",
                    "author_id": "NURSE-WANJIKU",
                    "timestamp": "2026-10-23T06:00:00Z"
                }
            ],
            "observation_note": "Urine was 30ml earlier. However BP is 120 and heart rate is 95."
        }
        res = VerificationHarness.verify(
            query="urine",
            raw_patient_events=self.events,
            model_output=model_output
        )
        # Sentence with 120 and 95 must be stripped because 120 and 95 are not in verified quotes
        self.assertIsNotNone(res.verified_observation)
        self.assertIn("Urine was 30ml earlier.", res.verified_observation)
        self.assertNotIn("120", res.verified_observation)
        self.assertNotIn("95", res.verified_observation)

    def test_unverified_quote_rejection_rule_1(self):
        # Model hallucinates a quote not in raw events
        fake_quote = {
            "verbatim_text": "Patient vomited 200ml clear fluid at 09:00",
            "author_id": "NURSE-WANJIKU",
            "timestamp": "2026-10-23T09:00:00Z"
        }
        model_output = {
            "verbatim_quotes": [fake_quote],
            "observation_note": "Vomiting observed."
        }
        res = VerificationHarness.verify(
            query="vomit",
            raw_patient_events=self.events,
            model_output=model_output
        )
        self.assertEqual(len(res.verified_quotes), 0)
        self.assertTrue(any("Rejected unverified quote" in fail for fail in res.failure_reasons))

    def test_conversational_greeting_hello(self):
        llm = LLMService(store=self.store)
        res = llm.query(patient_id="PAT-4B-01", query_text="Hello")
        self.assertEqual(res["observation_note"], "Hey, how may I help you?")
        self.assertTrue(res["verification_passed"])

    def test_llm_service_offline_fallback(self):
        # LLMService should execute deterministic fallback gracefully without throwing
        llm = LLMService(store=self.store)
        # Mocking an unreachable LLM port
        llm.base_url = "http://127.0.0.1:54321/v1"
        result = llm.query(patient_id="PAT-4B-01", query_text="urine")
        self.assertEqual(result["patient_id"], "PAT-4B-01")
        self.assertEqual(len(result["verbatim_quotes"]), 1)
        self.assertIn("30ml", result["verbatim_quotes"][0]["verbatim_text"])
        self.assertTrue(result["verification_passed"])

if __name__ == "__main__":
    unittest.main()
