import json
import os
import urllib.request
import urllib.error
from typing import Any, Dict, List, Optional
from ..event_store import EventStore
from .clinical_tools import CLINICAL_TOOLS, execute_query_patient_timeline
from .verification_harness import VerificationHarness, VerificationResult

class LLMService:
    """
    Vendor-agnostic LLM client speaking standard OpenAI-compatible API protocol.
    Works seamlessly with:
    - Local Ollama (qwen2.5:7b)
    - Google Gemini (via OpenAI compatibility endpoint)
    - Microsoft Azure OpenAI
    - Cloud OpenAI
    """

    def __init__(self, store: EventStore):
        self.store = store
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
            "temperature": 0.1,
        }
        if tools:
            payload["tools"] = tools

        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(url, data=data, headers=headers, method="POST")

        try:
            with urllib.request.urlopen(req, timeout=4.0) as resp:
                if resp.status == 200:
                    body = resp.read().decode("utf-8")
                    return json.loads(body)
        except Exception:
            # Model server unreachable or timed out; fall back seamlessly
            return None

    def query(self, patient_id: str, query_text: str, time_window_hours: Optional[int] = None) -> Dict[str, Any]:
        """
        Executes a natural language query with verification harness and fallback.
        """
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
        system_prompt = (
            "You are Oravi, an offline clinical assistant for hospital inpatient wards. "
            "You quote records verbatim and cite the author and time. "
            "You NEVER diagnose, predict, or prescribe. "
            "If asked for a diagnosis or treatment, state that you cannot diagnose. "
            "Output JSON with keys: 'verbatim_quotes' (list), 'observation_note' (string or null)."
        )

        model_response = self._call_openai_compatible_api(
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": f"Patient: {patient_id}. Question: {query_text}. Available records: {json.dumps(quotes)}"}
            ]
        )

        raw_model_output = {}
        if model_response and "choices" in model_response and model_response["choices"]:
            content = model_response["choices"][0]["message"].get("content", "")
            try:
                raw_model_output = json.loads(content)
            except Exception:
                raw_model_output = {"verbatim_quotes": quotes, "observation_note": None}
        else:
            # Offline / model unavailable fallback: Use deterministic extraction directly
            raw_model_output = {
                "verbatim_quotes": quotes,
                "observation_note": None,
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
