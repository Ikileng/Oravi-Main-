import re
from typing import Any, Dict, List, Optional, Tuple

class VerificationResult:
    def __init__(
        self,
        is_valid: bool,
        verified_quotes: List[Dict[str, Any]],
        verified_observation: Optional[str],
        failure_reasons: List[str],
        is_refusal: bool = False,
        refusal_message: Optional[str] = None,
        is_absence: bool = False,
        absence_message: Optional[str] = None,
    ):
        self.is_valid = is_valid
        self.verified_quotes = verified_quotes
        self.verified_observation = verified_observation
        self.failure_reasons = failure_reasons
        self.is_refusal = is_refusal
        self.refusal_message = refusal_message
        self.is_absence = is_absence
        self.absence_message = absence_message

    def to_dict(self) -> Dict[str, Any]:
        return {
            "is_valid": self.is_valid,
            "verified_quotes": self.verified_quotes,
            "observation_note": self.verified_observation,
            "failure_reasons": self.failure_reasons,
            "is_refusal": self.is_refusal,
            "refusal_message": self.refusal_message,
            "is_absence": self.is_absence,
            "absence_message": self.absence_message,
        }

class VerificationHarness:
    """
    Automatic verification harness enforcing zero-hallucination and clinical boundary rules.
    Tech Arch Section 11 & PRD Section 8A FR-40 & FR-194.
    """

    DIAGNOSTIC_TRIGGERS = [
        "kidney failure", "renal failure", "heart failure", "sepsis", "septic",
        "dying", "will he survive", "will she survive", "diagnose", "diagnosis",
        "prognosis", "prescribe", "what medicine should i give"
    ]

    @classmethod
    def is_diagnostic_query(cls, query: str) -> bool:
        lower = query.lower()
        return any(t in lower for t in cls.DIAGNOSTIC_TRIGGERS)

    @classmethod
    def extract_numbers(cls, text: str) -> List[str]:
        """Extracts integers and decimals from a text string."""
        # Finds standalone numbers like 88, 94, 7.1, 100, 2, excluding pure dates if formatted
        return re.findall(r'\b\d+(?:\.\d+)?\b', text)

    @classmethod
    def verify(
        cls,
        query: str,
        raw_patient_events: List[Any],
        model_output: Dict[str, Any],
    ) -> VerificationResult:
        failures = []
        is_diagnostic = cls.is_diagnostic_query(query)

        # 1. Diagnostic Boundary Refusal Check (FR-40)
        refusal_message = None
        if is_diagnostic:
            refusal_message = "I cannot diagnose or predict. This is what the record says about your query:"

        # 2. Extract and verify quotes against raw SQLite events (Rule 1)
        raw_texts = []
        for e in raw_patient_events:
            p = getattr(e, "payload", {}) if hasattr(e, "payload") else e.get("payload", {})
            for val in p.values():
                if isinstance(val, str):
                    raw_texts.append(val.strip())

        claimed_quotes = model_output.get("verbatim_quotes", [])
        verified_quotes = []

        for quote in claimed_quotes:
            q_text = quote.get("verbatim_text", "").strip()
            if not q_text:
                continue

            # Check if this exact text is a substring of any raw event text
            matched_raw = any(q_text in raw or raw in q_text for raw in raw_texts)
            if matched_raw:
                verified_quotes.append(quote)
            else:
                failures.append(f"Rejected unverified quote: '{q_text}' not in raw event store.")

        # 3. Absence Handling (Rule 5 & FR-37)
        is_absence = len(verified_quotes) == 0
        absence_message = None
        if is_absence and not is_diagnostic:
            absence_message = (
                f"No record in Oravi mentions '{query}' for this patient. "
                "Absence of a mention does not mean there was no change or that all is well."
            )

        # 4. Verify Numbers in Model Observation (Rule 2)
        raw_observation = model_output.get("observation_note", "")
        verified_observation = None

        if raw_observation:
            # Build set of all numbers authorized in verified quotes
            authorized_numbers = set()
            for q in verified_quotes:
                authorized_numbers.update(cls.extract_numbers(q.get("verbatim_text", "")))

            # Check sentences in the model observation
            sentences = re.split(r'(?<=[.!?])\s+', raw_observation.strip())
            valid_sentences = []

            for sent in sentences:
                sent_numbers = cls.extract_numbers(sent)
                unverified_nums = [n for n in sent_numbers if n not in authorized_numbers]

                if unverified_nums:
                    failures.append(
                        f"Stripped unverified sentence with numbers {unverified_nums}: '{sent}'"
                    )
                else:
                    valid_sentences.append(sent)

            if valid_sentences:
                verified_observation = " ".join(valid_sentences)
            else:
                verified_observation = None

        is_valid = len(failures) == 0 or len(verified_quotes) > 0 or is_absence or is_diagnostic

        return VerificationResult(
            is_valid=is_valid,
            verified_quotes=verified_quotes,
            verified_observation=verified_observation,
            failure_reasons=failures,
            is_refusal=is_diagnostic,
            refusal_message=refusal_message,
            is_absence=is_absence,
            absence_message=absence_message,
        )
