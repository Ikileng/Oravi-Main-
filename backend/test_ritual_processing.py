import asyncio
import base64
import hashlib
import logging
import os
import tempfile
import threading
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch

import httpx
from fastapi import FastAPI
from livekit import api as livekit

from backend.rituals import ClinicalRitualStore, RitualCreateRequest, build_router
from backend.services.ritual_processing import RitualProcessor


class RitualProcessingTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        store = ClinicalRitualStore(os.path.join(self.directory.name, 'test.db'))
        self.ritual = store.create(RitualCreateRequest(
            ritual_type='huddle', title='Synthetic workflow test', patient_id='TEST'), 'N')
        self.api = SimpleNamespace(
            ritual_store=store, require_staff=lambda: None,
            livekit_egress_service=Mock(), transcription_service=Mock(),
            llm_service=Mock(), staff_store=Mock(), fcm_service=Mock(),
            logger=logging.getLogger('ritual-test'))
        self.api.staff_store.get_fcm_fids_for_staff.return_value = []
        self.api.transcription_service.transcribe_file.return_value = {'text': 'Review equipment.'}
        self.api.llm_service.summarize_ritual.return_value = {'sections': {'actions': ['Review equipment.']}}
        self.processor = RitualProcessor(self.api)
        self.api.ritual_processor = self.processor
        self.env = patch.dict(os.environ, TRANSCRIPTION_PROVIDER='whisper_local',
            LIVEKIT_API_KEY='test', LIVEKIT_API_SECRET='test-secret-with-at-least-32-characters')
        self.env.start()
        self.addCleanup(self.env.stop)

    def test_queue_survives_restart_and_duplicate_delivery(self):
        rid = self.ritual['ritual_id']
        self.processor.enqueue(rid, '/recording.ogg')
        self.processor.enqueue(rid, '/recording.ogg')
        restarted = RitualProcessor(self.api)
        job = restarted.claim()
        self.assertIsNotNone(job)
        self.assertIsNone(restarted.claim())
        restarted.process(job)
        self.processor.enqueue(rid, '/recording.ogg')
        self.assertIsNone(self.processor.claim())
        saved = self.api.ritual_store.get(rid)
        self.assertEqual(saved['status'], 'draft_ready')
        self.assertIsNone(saved['approved_by'])
        self.api.transcription_service.transcribe_file.assert_called_once()

    def test_interrupted_job_is_reclaimed_after_lease_expiry(self):
        rid = self.ritual['ritual_id']
        self.processor.enqueue(rid, '/recording.ogg')
        first = self.processor.claim()
        with self.api.ritual_store.connection() as conn:
            conn.execute('UPDATE ritual_processing_jobs SET lease_until=0')
        second = self.processor.claim()
        self.assertNotEqual(first['owner'], second['owner'])

    def test_transcription_failure_is_visible(self):
        self.api.transcription_service.transcribe_file.side_effect = ValueError('decoder error')
        rid = self.ritual['ritual_id']
        self.processor.enqueue(rid, '/recording.ogg')
        self.processor.process(self.processor.claim())
        self.assertEqual(self.api.ritual_store.get(rid)['recording_status'], 'failed')
        self.api.llm_service.summarize_ritual.assert_not_called()

    def test_summary_failure_preserves_transcript(self):
        self.api.llm_service.summarize_ritual.side_effect = RuntimeError('model unavailable')
        rid = self.ritual['ritual_id']
        self.processor.enqueue(rid, '/recording.ogg')
        self.processor.process(self.processor.claim())
        saved = self.api.ritual_store.get(rid)
        self.assertEqual(saved['transcript'], 'Review equipment.')
        self.assertEqual(saved['recording_status'], 'transcribed')
        self.assertIsNone(saved['summary'])

    def test_saved_transcript_is_reused_and_processing_remains_visible(self):
        rid = self.ritual['ritual_id']
        self.api.ritual_store.save_transcript(rid, 'Previously transcribed.')
        self.processor.enqueue(rid, '/recording.ogg')
        def summarize(**kwargs):
            self.assertEqual(kwargs['transcript'], 'Previously transcribed.')
            self.assertEqual(self.api.ritual_store.get(rid)['recording_status'], 'processing')
            return {'sections': {'actions': ['Review equipment.']}}
        self.api.llm_service.summarize_ritual.side_effect = summarize
        self.processor.process(self.processor.claim())
        self.api.transcription_service.transcribe_file.assert_not_called()
        self.assertEqual(self.api.ritual_store.get(rid)['status'], 'draft_ready')

    def test_signed_webhook_acknowledges_while_model_is_blocked(self):
        async def scenario():
            import json
            rid = self.ritual['ritual_id']
            with self.api.ritual_store.connection() as conn:
                conn.execute('UPDATE clinical_rituals SET egress_id=? WHERE ritual_id=?', ('EG-test', rid))
            started, release = threading.Event(), threading.Event()
            def transcribe(_):
                started.set()
                release.wait(10)
                return {'text': 'Review equipment.'}
            self.api.transcription_service.transcribe_file.side_effect = transcribe
            app = FastAPI()
            app.include_router(build_router(self.api))
            @app.get('/probe')
            async def probe():
                return {'ok': True}
            body = json.dumps({'event': 'egress_ended', 'egressInfo': {
                'egressId': 'EG-test', 'roomName': self.ritual['room_name'],
                'status': 'EGRESS_COMPLETE', 'fileResults': [{'location': '/recording.ogg'}]}}).encode()
            token = livekit.AccessToken(os.environ['LIVEKIT_API_KEY'], os.environ['LIVEKIT_API_SECRET']).with_sha256(
                base64.b64encode(hashlib.sha256(body).digest()).decode()).to_jwt()
            worker = asyncio.create_task(self.processor.run())
            try:
                async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url='http://test') as client:
                    rejected = await client.post('/api/v1/rituals/webhooks/livekit', content=body + b' ',
                        headers={'Content-Type': 'application/webhook+json', 'Authorization': token})
                    self.assertEqual(rejected.status_code, 401)
                    self.assertIsNone(self.processor.claim())
                    response = await asyncio.wait_for(client.post('/api/v1/rituals/webhooks/livekit', content=body,
                        headers={'Content-Type': 'application/webhook+json', 'Authorization': token}), 2)
                    self.assertEqual(response.status_code, 200)
                    self.assertEqual(response.json()['status'], 'queued')
                    self.assertTrue(await asyncio.to_thread(started.wait, 5))
                    response = await asyncio.wait_for(client.get('/probe'), 1)
                    self.assertEqual(response.status_code, 200)
                    self.assertIsNone(self.api.ritual_store.get(rid)['summary'])
            finally:
                release.set()
                worker.cancel()
                try:
                    await worker
                except asyncio.CancelledError:
                    pass
        asyncio.run(scenario())
