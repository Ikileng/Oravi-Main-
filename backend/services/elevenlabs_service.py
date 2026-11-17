import os
from typing import Any, Optional

from elevenlabs import ElevenLabs


class ElevenLabsTranscriptionService:
    def __init__(self, client: Optional[ElevenLabs] = None):
        self.api_key = os.getenv("ELEVENLABS_API_KEY", "").strip()
        self.model_id = os.getenv("ELEVENLABS_SCRIBE_MODEL", "scribe_v3")
        self.client = client

    def transcribe_url(self, source_url: str) -> dict[str, Any]:
        if not self.api_key and self.client is None:
            raise RuntimeError("ElevenLabs transcription is not configured.")
        if not source_url.startswith(("https://", "http://")):
            raise RuntimeError("The recording location is not an HTTP(S) URL.")

        client = self.client or ElevenLabs(api_key=self.api_key)
        result = client.speech_to_text.convert(
            model_id=self.model_id,
            source_url=source_url,
            timestamps_granularity="word",
            diarize=True,
        )
        return {
            "text": str(getattr(result, "text", "") or "").strip(),
            "language_code": getattr(result, "language_code", None),
            "language_probability": getattr(result, "language_probability", None),
            "audio_duration_secs": getattr(result, "audio_duration_secs", None),
            "transcription_id": getattr(result, "transcription_id", None),
        }
