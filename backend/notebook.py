"""Private clinician notes, tasks and optional in-app reminders."""
from datetime import datetime, timezone
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field, AwareDatetime

from .communications import CommunicationsStore


class NotebookEntry(BaseModel):
    model_config = ConfigDict(extra='forbid')
    body: str = Field(min_length=1, max_length=4000)
    kind: Literal['note', 'task'] = 'task'
    completed: bool = False
    reminder_at: AwareDatetime | None = None


class NotebookStore(CommunicationsStore):
    def __init__(self, db_path):
        self.db_path = db_path
        with self.connection() as conn:
            conn.execute('''CREATE TABLE IF NOT EXISTS personal_notebook (
                owner_id TEXT NOT NULL, id TEXT NOT NULL, body TEXT NOT NULL,
                kind TEXT NOT NULL, completed INTEGER NOT NULL,
                reminder_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
                completed_at TEXT, PRIMARY KEY(owner_id,id))''')


def build_notebook_router(api):
    router = APIRouter(prefix='/api/v1/notebook')

    @router.get('')
    def entries(profile=Depends(api.require_staff)):
        with api.notebook_store.connection() as conn:
            rows = conn.execute('SELECT * FROM personal_notebook WHERE owner_id=? '
                                'ORDER BY created_at DESC,id', (profile.staff_id,)).fetchall()
        return [dict(row) for row in rows]

    @router.put('/{entry_id}')
    def save(entry_id: str, payload: NotebookEntry, profile=Depends(api.require_staff)):
        if not entry_id or len(entry_id) > 80:
            raise HTTPException(400, 'Invalid entry ID.')
        body = payload.body.strip()
        if not body:
            raise HTTPException(400, 'Write a note or task first.')
        if payload.kind == 'note' and payload.completed:
            raise HTTPException(400, 'Only tasks can be marked done.')
        now = datetime.now(timezone.utc).isoformat()
        reminder = (payload.reminder_at.astimezone(timezone.utc).isoformat()
                    if payload.reminder_at and not payload.completed else None)
        with api.notebook_store.connection() as conn:
            previous = conn.execute('SELECT * FROM personal_notebook WHERE owner_id=? AND id=?',
                                    (profile.staff_id, entry_id)).fetchone()
            completed_at = ((previous['completed_at'] if previous else None) or now
                            if payload.completed else None)
            conn.execute('''INSERT INTO personal_notebook VALUES (?,?,?,?,?,?,?,?,?)
                ON CONFLICT(owner_id,id) DO UPDATE SET body=excluded.body,kind=excluded.kind,
                completed=excluded.completed,reminder_at=excluded.reminder_at,
                updated_at=excluded.updated_at,completed_at=excluded.completed_at''',
                (profile.staff_id, entry_id, body, payload.kind, int(payload.completed),
                 reminder, now, now, completed_at))
            return dict(conn.execute('SELECT * FROM personal_notebook WHERE owner_id=? AND id=?',
                                     (profile.staff_id, entry_id)).fetchone())

    @router.delete('/{entry_id}')
    def delete(entry_id: str, profile=Depends(api.require_staff)):
        with api.notebook_store.connection() as conn:
            conn.execute('DELETE FROM personal_notebook WHERE owner_id=? AND id=?',
                         (profile.staff_id, entry_id))
        return {'success': True}

    return router
