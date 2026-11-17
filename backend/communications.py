"""Staff-only conversations and ward duty contacts; no patient payloads."""
import sqlite3
import uuid
from contextlib import contextmanager
from datetime import date, datetime, timezone

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field
from .staff_roles import RESPONSIBILITIES, PROVISIONABLE_ROLES


class DutyRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    staff_id: str = ''


class MessageRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    body: str = Field(min_length=1, max_length=4000)
    client_id: str = Field(min_length=1, max_length=80)


class DirectCallRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    recipient_id: str


class CommunicationsStore:
    def __init__(self, db_path):
        self.db_path = db_path
        with self.connection() as conn:
            conn.executescript('''
                CREATE TABLE IF NOT EXISTS ward_responsibilities (
                    ward_id TEXT NOT NULL, duty_date TEXT NOT NULL,
                    shift_type TEXT NOT NULL, responsibility TEXT NOT NULL,
                    staff_id TEXT NOT NULL, assigned_by TEXT NOT NULL,
                    PRIMARY KEY(ward_id,duty_date,shift_type,responsibility));
                CREATE TABLE IF NOT EXISTS direct_messages (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    sender_id TEXT NOT NULL, recipient_id TEXT NOT NULL,
                    body TEXT NOT NULL, sent_at TEXT NOT NULL, client_id TEXT NOT NULL,
                    UNIQUE(sender_id,client_id));
                CREATE INDEX IF NOT EXISTS direct_message_recipient ON direct_messages(recipient_id,id);
                CREATE TABLE IF NOT EXISTS inbox_reads (
                    staff_id TEXT NOT NULL, item_id TEXT NOT NULL,
                    PRIMARY KEY(staff_id,item_id));
            ''')

    @contextmanager
    def connection(self):
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        try:
            with conn:
                yield conn
        finally:
            conn.close()


def build_router(api):
    router = APIRouter(prefix='/api/v1')

    def member(staff_id):
        people = api.staff_store.list_staff()
        return next((p for p in people if p.staff_id == staff_id and p.is_active
                     and p.role in PROVISIONABLE_ROLES), None)

    def contact(person):
        return {'staff_id': person.staff_id, 'name': person.name, 'role': person.role}

    def notify_message(recipient_id):
        if member(recipient_id) is None:
            return
        for fid in api.staff_store.get_fcm_fids_for_staff(recipient_id):
            try:
                api.fcm_service.send_staff_message(fid)
            except Exception:
                api.logger.warning('Staff message saved, but its push notification could not be delivered.')

    def authorize_ward(profile, ward_id, duty_date, shift_type):
        try:
            date.fromisoformat(duty_date)
        except ValueError:
            raise HTTPException(400, 'Invalid date.')
        if shift_type not in {'day', 'night'}:
            raise HTTPException(400, 'Invalid shift.')
        if not any(w.ward_id == ward_id for w in api.ward_store.get_all_wards()):
            raise HTTPException(404, 'Ward not found.')
        if not api._staff_can_access_ward(profile, ward_id, duty_date):
            raise HTTPException(403, 'You do not have access to this ward.')

    @router.get('/wards/{ward_id}/responsibilities')
    def duties(ward_id: str, duty_date: str, shift_type: str,
               profile=Depends(api.require_staff)):
        authorize_ward(profile, ward_id, duty_date, shift_type)
        with api.communications_store.connection() as conn:
            rows = conn.execute('SELECT responsibility,staff_id FROM ward_responsibilities '
                'WHERE ward_id=? AND duty_date=? AND shift_type=?',
                (ward_id, duty_date, shift_type)).fetchall()
        assigned = {r['responsibility']: member(r['staff_id']) for r in rows}
        return [{'key': key, 'label': label, 'staff': contact(assigned[key])
                 if assigned.get(key) else None} for key, (label, _) in RESPONSIBILITIES.items()]

    @router.get('/wards/{ward_id}/responsibility-candidates')
    def candidates(ward_id: str, responsibility: str, q: str = '',
                   profile=Depends(api.require_charge_nurse)):
        if api.staff_store.get_ward_preference(profile.staff_id) != ward_id:
            raise HTTPException(403, 'Confirm this ward first.')
        if responsibility not in RESPONSIBILITIES:
            raise HTTPException(400, 'Unknown responsibility.')
        allowed = RESPONSIBILITIES[responsibility][1]
        return [contact(p) for p in api.staff_store.list_staff()
                if p.is_active and p.role in allowed and
                q.casefold() in (p.name + ' ' + p.staff_id).casefold()]

    @router.put('/wards/{ward_id}/responsibilities/{responsibility}')
    def assign(ward_id: str, responsibility: str, duty_date: str, shift_type: str,
               payload: DutyRequest, profile=Depends(api.require_charge_nurse)):
        authorize_ward(profile, ward_id, duty_date, shift_type)
        if responsibility not in RESPONSIBILITIES:
            raise HTTPException(400, 'Unknown responsibility.')
        person = member(payload.staff_id) if payload.staff_id else None
        if payload.staff_id and (person is None or person.role not in RESPONSIBILITIES[responsibility][1]):
            raise HTTPException(400, 'Choose an active account eligible for this responsibility.')
        with api.communications_store.connection() as conn:
            if person:
                conn.execute('INSERT INTO ward_responsibilities VALUES (?,?,?,?,?,?) '
                    'ON CONFLICT(ward_id,duty_date,shift_type,responsibility) DO UPDATE SET '
                    'staff_id=excluded.staff_id,assigned_by=excluded.assigned_by',
                    (ward_id,duty_date,shift_type,responsibility,person.staff_id,profile.staff_id))
            else:
                conn.execute('DELETE FROM ward_responsibilities WHERE ward_id=? AND duty_date=? '
                    'AND shift_type=? AND responsibility=?', (ward_id,duty_date,shift_type,responsibility))
        return {'success': True}

    @router.get('/direct/threads')
    def threads(profile=Depends(api.require_communicating_staff)):
        with api.communications_store.connection() as conn:
            rows = conn.execute('SELECT * FROM direct_messages WHERE sender_id=? OR recipient_id=? '
                                'ORDER BY id DESC', (profile.staff_id,profile.staff_id)).fetchall()
        result, seen = [], set()
        for row in rows:
            other = row['recipient_id'] if row['sender_id'] == profile.staff_id else row['sender_id']
            if other in seen:
                continue
            seen.add(other)
            person = member(other)
            result.append({'contact': contact(person) if person else
                {'staff_id': other, 'name': 'Unavailable account', 'role': ''},
                'last_message': row['body'], 'sent_at': row['sent_at']})
        return result

    @router.get('/direct/threads/{other_id}')
    def messages(other_id: str, profile=Depends(api.require_communicating_staff)):
        with api.communications_store.connection() as conn:
            return [dict(r) for r in conn.execute('SELECT id,sender_id,recipient_id,body,sent_at '
                'FROM direct_messages WHERE (sender_id=? AND recipient_id=?) OR '
                '(sender_id=? AND recipient_id=?) ORDER BY id DESC LIMIT 200',
                (profile.staff_id,other_id,other_id,profile.staff_id)).fetchall()][::-1]

    @router.post('/direct/threads/{other_id}')
    def send(other_id: str, payload: MessageRequest, background_tasks: BackgroundTasks,
             profile=Depends(api.require_communicating_staff)):
        if other_id == profile.staff_id or member(other_id) is None:
            raise HTTPException(400, 'Recipient is unavailable.')
        if not payload.body.strip():
            raise HTTPException(400, 'Enter a message.')
        with api.communications_store.connection() as conn:
            existing = conn.execute('SELECT recipient_id,body FROM direct_messages WHERE sender_id=? AND client_id=?',
                                   (profile.staff_id,payload.client_id)).fetchone()
            if existing and (existing['recipient_id'] != other_id or existing['body'] != payload.body.strip()):
                raise HTTPException(409, 'Message identifier is already in use.')
            inserted = conn.execute('INSERT OR IGNORE INTO direct_messages '
                '(sender_id,recipient_id,body,sent_at,client_id) VALUES (?,?,?,?,?)',
                (profile.staff_id,other_id,payload.body.strip(),datetime.now(timezone.utc).isoformat(),payload.client_id)).rowcount
        if inserted:
            background_tasks.add_task(notify_message, other_id)
        return {'success': True}

    @router.get('/direct/calls')
    def calls(profile=Depends(api.require_communicating_staff)):
        api.call_store.expire_stale()
        with api.communications_store.connection() as conn:
            rows = conn.execute("SELECT call_id,caller_id,recipient_id,status,created_at FROM call_sessions "
                "WHERE patient_id='' AND loop_id='' AND (caller_id=? OR recipient_id=?) "
                'ORDER BY created_at DESC LIMIT 100', (profile.staff_id,profile.staff_id)).fetchall()
        result = []
        for row in rows:
            item = dict(row)
            other = member(row['recipient_id'] if row['caller_id'] == profile.staff_id else row['caller_id'])
            item['name'] = other.name if other else 'Unavailable account'
            result.append(item)
        return result

    @router.post('/direct/calls')
    def invite(payload: DirectCallRequest, profile=Depends(api.require_communicating_staff)):
        recipient = member(payload.recipient_id)
        if recipient is None or recipient.staff_id == profile.staff_id:
            raise HTTPException(400, 'Recipient is unavailable.')
        recipient_fids = api.staff_store.get_fcm_fids_for_staff(recipient.staff_id)
        if not recipient_fids:
            raise HTTPException(409, 'This clinician has no reachable Oravi device right now.')
        call_id, room = 'CALL-' + str(uuid.uuid4()), 'oravi-call-' + uuid.uuid4().hex
        token = api._livekit_token(profile.staff_id, profile.name, room)
        api.call_store.create(call_id=call_id,room_name=room,patient_id='',loop_id='',
                              caller_id=profile.staff_id,recipient_id=recipient.staff_id)
        delivered = 0
        for fid in recipient_fids:
            try:
                if api.fcm_service.send_call_invitation(fid,call_id=call_id): delivered += 1
            except Exception:
                api.logger.warning('Direct call push could not be delivered.')
        if delivered == 0:
            api.call_store.mark_cancelled(call_id, profile.staff_id)
            raise HTTPException(503, 'The clinician could not be notified. They may be offline.')
        return {'call_id':call_id,'patient_id':'','loop_id':'','caller_id':profile.staff_id,
                'caller_name':profile.name,'recipient_id':recipient.staff_id,'recipient_name':recipient.name,
                'recipient_role':recipient.role,'room_name':room,'livekit_url':api.os.getenv('LIVEKIT_URL'),
                'token':token,'status':'ringing'}

    return router
