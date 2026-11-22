"""Persistent, serial ritual processing outside the API event loop."""
import asyncio
import sqlite3
import time
import uuid


class RitualProcessor:
    def __init__(self, api):
        self.api = api
        with api.ritual_store.connection() as conn:
            conn.execute('''CREATE TABLE IF NOT EXISTS ritual_processing_jobs (
                ritual_id TEXT PRIMARY KEY, location TEXT NOT NULL,
                state TEXT NOT NULL DEFAULT 'queued', owner TEXT,
                lease_until REAL NOT NULL DEFAULT 0, error TEXT)''')

    def enqueue(self, ritual_id, location):
        with self.api.ritual_store.connection() as conn:
            conn.execute('''INSERT OR IGNORE INTO ritual_processing_jobs
                (ritual_id, location) VALUES (?, ?)''', (ritual_id, location))
            conn.execute('''UPDATE clinical_rituals SET recording_location=?,
                recording_status='processing', status='ended'
                WHERE ritual_id=? AND status NOT IN ('draft_ready','approved')
                AND EXISTS (SELECT 1 FROM ritual_processing_jobs
                    WHERE ritual_id=? AND state IN ('queued','running'))''',
                (location, ritual_id, ritual_id))

    def claim(self):
        with self.api.ritual_store.connection() as conn:
            conn.execute('BEGIN IMMEDIATE')
            row = conn.execute('''SELECT * FROM ritual_processing_jobs
                WHERE state='queued' OR (state='running' AND lease_until < ?)
                ORDER BY rowid LIMIT 1''', (time.time(),)).fetchone()
            if row is None:
                return None
            job = dict(row)
            job['owner'] = uuid.uuid4().hex
            conn.execute('''UPDATE ritual_processing_jobs SET state='running',
                owner=?, lease_until=? WHERE ritual_id=?''',
                (job['owner'], time.time() + 90, job['ritual_id']))
            return job

    def renew(self, job):
        with self.api.ritual_store.connection() as conn:
            conn.execute('''UPDATE ritual_processing_jobs SET lease_until=?
                WHERE ritual_id=? AND owner=? AND state='running' ''',
                (time.time() + 90, job['ritual_id'], job['owner']))

    def finish(self, job, error=None):
        with self.api.ritual_store.connection() as conn:
            conn.execute('''UPDATE ritual_processing_jobs SET state=?, error=?,
                lease_until=0 WHERE ritual_id=? AND owner=?''',
                ('failed' if error else 'done', error, job['ritual_id'], job['owner']))

    def process(self, job):
        api = self.api
        ritual_id = job['ritual_id']
        ritual = api.ritual_store.get(ritual_id)
        if ritual is None or ritual['status'] in {'draft_ready', 'approved'}:
            self.finish(job)
            return
        try:
            transcript = ritual.get('transcript')
            if not transcript:
                source = api.livekit_egress_service.recording_url(
                    ritual_id=ritual_id, room_name=ritual['room_name'],
                    location=job['location'])
                import os
                if os.getenv('TRANSCRIPTION_PROVIDER', 'elevenlabs').strip().lower() == 'whisper_local':
                    result = api.transcription_service.transcribe_file(source)
                else:
                    result = api.transcription_service.transcribe_url(source)
                transcript = result['text'].strip()
                if not transcript:
                    raise RuntimeError('No speech was transcribed.')
                api.ritual_store.save_transcript(ritual_id, transcript)
            summary = api.llm_service.summarize_ritual(
                ritual_type=ritual['ritual_type'], title=ritual['title'], transcript=transcript)
            # Never replace a draft edited/approved while processing ran.
            current = api.ritual_store.get(ritual_id)
            if current['status'] not in {'draft_ready', 'approved'}:
                api.ritual_store.set_recording_status(ritual_id, 'transcribed')
                api.ritual_store.save_draft(ritual_id, summary)
            self.finish(job)
        except Exception as error:
            # Preserve the transcript so the existing draft retry can reuse it.
            current = api.ritual_store.get(ritual_id)
            if current and current['status'] not in {'draft_ready', 'approved'}:
                api.ritual_store.set_recording_status(
                    ritual_id, 'transcribed' if current.get('transcript') else 'failed')
            self.finish(job, type(error).__name__)
            api.logger.error('Ritual processing failed for %s (%s).', ritual_id, type(error).__name__)
            return
        try:
            for fid in api.staff_store.get_fcm_fids_for_staff(ritual['creator_id']):
                if not api.fcm_service.send_clinical_ritual_review_alert(
                    fid, ritual_id=ritual_id, title=ritual['title']):
                    api.staff_store.remove_fcm_fid(fid)
        except Exception as error:
            api.logger.error('Ritual review alert failed (%s).', type(error).__name__)

    async def run(self):
        while True:
            try:
                job = await asyncio.to_thread(self.claim)
            except sqlite3.OperationalError:
                self.api.logger.exception('Ritual queue temporarily unavailable; retrying.')
                await asyncio.sleep(2)
                continue
            if job is None:
                await asyncio.sleep(2)
                continue
            work = asyncio.create_task(asyncio.to_thread(self.process, job))
            try:
                while not work.done():
                    await asyncio.wait({work}, timeout=15)
                    if not work.done():
                        await asyncio.to_thread(self.renew, job)
                await work
            except asyncio.CancelledError:
                # A live thread cannot be cancelled. Keep its lease until it
                # exits; a killed process is recovered after lease expiry.
                while not work.done():
                    await asyncio.wait({work}, timeout=15)
                    if not work.done():
                        await asyncio.to_thread(self.renew, job)
                await work
                raise
