import os
from typing import Any, Optional


class WhisperTranscriptionService:
    """Local Whisper transcription for residency-preserving development."""

    def __init__(self) -> None:
        self.model_name = os.getenv("WHISPER_MODEL", "large-v3").strip()
        self.device = os.getenv("WHISPER_DEVICE", "auto").strip()
        self.compute_type = os.getenv("WHISPER_COMPUTE_TYPE", "int8").strip()
        self._model: Optional[Any] = None

    def _get_model(self) -> Any:
        if self._model is None:
            try:
                from faster_whisper import WhisperModel
            except ImportError as error:
                raise RuntimeError(
                    "Local Whisper is not installed. Install faster-whisper in the backend environment."
                ) from error
            self._model = WhisperModel(
                self.model_name,
                device=self.device,
                compute_type=self.compute_type,
            )
        return self._model

    def transcribe_file(self, source_path: str) -> dict[str, Any]:
        if not os.path.isfile(source_path):
            raise RuntimeError("The local recording file is not available.")
        model = self._get_model()
        segments, info = model.transcribe(
            source_path,
            beam_size=5,
            vad_filter=True,
            word_timestamps=True,
            condition_on_previous_text=True,
        )
        materialized_segments = []
        text_parts = []
        for segment in segments:
            text = str(segment.text or "").strip()
            if not text:
                continue
            text_parts.append(text)
            materialized_segments.append(
                {
                    "start": float(segment.start),
                    "end": float(segment.end),
                    "text": text,
                }
            )
        return {
            "text": " ".join(text_parts).strip(),
            "language_code": getattr(info, "language", None),
            "language_probability": getattr(info, "language_probability", None),
            "segments": materialized_segments,
            "provider": "whisper_local",
            "model": self.model_name,
        }
