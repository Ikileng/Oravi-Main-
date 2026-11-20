import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from backend.services.livekit_egress_service import LiveKitEgressService


class LiveKitEgressPathTests(unittest.TestCase):
    def test_local_recording_uses_reported_ogg_path(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            reported = root / "oravi" / "rituals" / "RITUAL-1" / "room.ogg"
            reported.parent.mkdir(parents=True)
            reported.write_bytes(b"audio")
            with patch.dict(
                "os.environ",
                {
                    "LIVEKIT_EGRESS_STORAGE": "local",
                    "LIVEKIT_LOCAL_RECORDING_DIR": str(root),
                    "LIVEKIT_INTERNAL_URL": "http://livekit:7880",
                    "ORAVI_PUBLIC_URL": "http://backend:8000",
                    "LIVEKIT_API_KEY": "devkey",
                    "LIVEKIT_API_SECRET": "secret",
                },
                clear=False,
            ):
                service = LiveKitEgressService()
                self.assertEqual(
                    service.recording_url(
                        ritual_id="RITUAL-1",
                        room_name="room",
                        location="/recordings/oravi/rituals/RITUAL-1/room.ogg",
                    ),
                    str(reported.resolve()),
                )


if __name__ == "__main__":
    unittest.main()
