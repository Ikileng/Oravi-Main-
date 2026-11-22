"""Exercise the actual decoder API used by Whisper, without model weights."""
import io
import unittest
import wave

from faster_whisper.audio import decode_audio


class WhisperAudioTests(unittest.TestCase):
    def test_recording_can_be_decoded_for_whisper(self):
        recording = io.BytesIO()
        with wave.open(recording, 'wb') as audio:
            audio.setnchannels(1)
            audio.setsampwidth(2)
            audio.setframerate(16000)
            audio.writeframes(b'\0\0' * 1600)
        recording.seek(0)
        samples = decode_audio(recording, sampling_rate=16000)
        self.assertEqual(len(samples), 1600)
        self.assertEqual(str(samples.dtype), 'float32')
