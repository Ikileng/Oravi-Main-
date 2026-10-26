import os
import json
import urllib.request
from typing import Any, Dict, List, Optional
from backend.event_store import EventStore
from backend.services.clinical_tools import execute_query_patient_timeline
from backend.services.verification_harness import VerificationHarness, VerificationResult

class LLMService:
    """
    Local LLM service interfacing with Ollama (Qwen 2.5 7B default) or OpenAI-compatible endpoint.
    Strictly verifies all synthesized observations against raw event quotes (Tech Arch Section 11).
    """

    def __init__(self, store: EventStore):
        self.store = store
        # Load .env file automatically if present
        candidate_paths = [
            ".env",
            "backend/.env",
            "../.env",
            os.path.join(os.path.dirname(__file__), "..", ".env"),
            os.path.join(os.path.dirname(__file__), "..", "..", ".env"),
        ]
        for p in candidate_paths:
            if os.path.exists(p):
                try:
                    with open(p, "r", encoding="utf-8") as f_env:
                        for line in f_env:
                            line = line.strip()
                            if line and not line.startswith("#") and "=" in line:
                                k, v = line.split("=", 1)
                                k, v = k.strip(), v.strip().strip('"').strip("'")
                                if k not in os.environ:
                                    os.environ[k] = v
                except Exception:
                    pass
                break

        self.provider = os.getenv("LLM_PROVIDER", "ollama")
        self.base_url = os.getenv("LLM_BASE_URL", "http://localhost:11434/v1")
        self.api_key = os.getenv("LLM_API_KEY", "ollama")
        self.model_name = os.getenv("LLM_MODEL_NAME", "qwen2.5:7b")

    def _call_openai_compatible_api(self, messages: List[Dict[str, str]], tools: Optional[List[Dict[str, Any]]] = None) -> Optional[Dict[str, Any]]:
        url = f"{self.base_url.rstrip('/')}/chat/completions"
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {self.api_key}",
        }
        payload = {
            "model": self.model_name,
            "messages": messages,
            "temperature": 0.2,
            "max_tokens": 120,
        }
        if tools:
            payload["tools"] = tools

        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(url, data=data, headers=headers, method="POST")

        try:
            # 35s timeout gives local CPU inference breathing room on cold start
            with urllib.request.urlopen(req, timeout=35.0) as resp:
                if resp.status == 200:
                    body = resp.read().decode("utf-8")
                    return json.loads(body)
        except Exception as e:
            return None

    def query(self, patient_id: str, query_text: str, time_window_hours: Optional[int] = None) -> Dict[str, Any]:
        """
        Executes a natural language query with verification harness and fallback.
        """
        clean_lower = query_text.strip().lower()
        # 0. Conversational greetings
        if clean_lower in ["hello", "hi", "hey", "jambo", "habari", "good morning", "good afternoon", "good evening", "how are you", "sasa"]:
            return {
                "patient_id": patient_id,
                "query": query_text,
                "verbatim_quotes": [],
                "observation_note": "Hey, how may I help you?",
                "coverage_summary": "Conversational assistant ready.",
                "is_refusal": False,
                "refusal_message": None,
                "is_absence": False,
                "absence_message": None,
                "doctor_in_charge": "DOC-OTIENO",
                "verification_passed": True,
                "model_provider": self.provider,
                "model_name": self.model_name,
            }

        all_events, _ = self.store.get_events_since(since_seq=0, limit=1000)
        patient_events = [e for e in all_events if e.patient_id == patient_id]

        # 1. Deterministic tool retrieval (ensures ground truth is always available)
        deterministic_tool_result = execute_query_patient_timeline(
            store=self.store,
            patient_id=patient_id,
            topic=query_text,
            time_window_hours=time_window_hours,
        )

        quotes = deterministic_tool_result["quotes"]
        coverage = deterministic_tool_result["coverage_summary"]

        # 2. Check if local Qwen/Ollama model is running
        record_lines = [q.get("verbatim_text", "") for q in quotes if q.get("verbatim_text")]
        records_context = "\n".join(record_lines)

        system_prompt = (
            "You are Oravi, an offline bedside clinical assistant for hospital inpatient wards in Kenya/East Africa. "
            "Respond directly, naturally, and supportively to the clinician in 2-3 sentences based strictly on the verified patient records. "
            "When giving a briefing, state the admission reason, limb/dressing status, key alerts, and medical issues status clearly. "
            "Do not diagnose, predict, or prescribe. State only facts from the record."
        )

        model_response = self._call_openai_compatible_api(
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": f"Verified Patient Records:\n{records_context}\n\nClinician Question: {query_text}"}
            ]
        )

        observation_note = None
        if model_response and "choices" in model_response and model_response["choices"]:
            observation_note = model_response["choices"][0]["message"].get("content", "").strip()

        raw_model_output = {
            "verbatim_quotes": quotes,
            "observation_note": observation_note,
        }

        # 3. Pass through the Automatic Verification Harness (Tech Arch Section 11)
        verification: VerificationResult = VerificationHarness.verify(
            query=query_text,
            raw_patient_events=patient_events,
            model_output=raw_model_output,
        )

        return {
            "patient_id": patient_id,
            "query": query_text,
            "verbatim_quotes": verification.verified_quotes,
            "observation_note": verification.verified_observation,
            "coverage_summary": coverage,
            "is_refusal": verification.is_refusal,
            "refusal_message": verification.refusal_message,
            "is_absence": verification.is_absence,
            "absence_message": verification.absence_message,
            "doctor_in_charge": "DOC-OTIENO",
            "verification_passed": verification.is_valid,
            "model_provider": self.provider,
            "model_name": self.model_name,
        }
