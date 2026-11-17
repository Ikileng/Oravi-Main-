"""Personal inbox views and durable per-user read receipts."""
import json
from datetime import date, datetime, timezone

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field
from .staff_roles import CLINICAL_ROLES


class ReadItems(BaseModel):
    ids: list[str] = Field(max_length=500)


def build_inbox_router(api):
    router = APIRouter(prefix='/api/v1/inbox')

    def clinical_access(profile, patient, loop):
        return profile.role in CLINICAL_ROLES and (
            api._staff_can_access_patient(profile, patient, date.today().isoformat())
            or api._staff_can_access_carried_issue(profile.staff_id, patient, loop))

    def items_for(profile):
        api.call_store.expire_stale()
        with api.communications_store.connection() as conn:
            read = {r['item_id'] for r in conn.execute(
                'SELECT item_id FROM inbox_reads WHERE staff_id=?', (profile.staff_id,))}
            messages = conn.execute('SELECT * FROM direct_messages WHERE recipient_id=? ORDER BY id DESC',
                                    (profile.staff_id,)).fetchall()
        people = {p.staff_id:p.name for p in api.staff_store.list_staff()}
        items = []
        for row in messages:
            items.append({'id':f"message:{row['id']}", 'kind':'message',
                'title':people.get(row['sender_id'], 'Unavailable account'), 'body':row['body'],
                'staff_id':row['sender_id'], 'created_at':row['sent_at']})
        if profile.role in CLINICAL_ROLES:
            with api.store._lock:
                alerts = api.store._conn.execute('''SELECT n.*,e.author_id,e.type,e.payload_json
                    FROM medical_issue_notification_outbox n JOIN server_events e ON e.event_id=n.event_id
                    WHERE n.staff_id=? AND e.author_id<>? ORDER BY n.notification_id DESC''',
                    (profile.staff_id,profile.staff_id)).fetchall()
            access = {}
            for row in alerts:
                key = (row['patient_id'], row['loop_id'])
                if key not in access:
                    access[key] = clinical_access(profile, *key)
                if not access[key]:
                    continue
                payload = json.loads(row['payload_json'])
                items.append({'id':f"issue:{row['notification_id']}", 'kind':'issue',
                    'title':people.get(row['author_id'], 'Clinician') + ' · Medical issue update',
                    'body':str(payload.get('content') or payload.get('title') or 'Open the issue to review this update.'),
                    'patient_id':row['patient_id'], 'loop_id':row['loop_id'], 'event_id':row['event_id'], 'created_at':row['created_at']})
        with api.call_store._lock:
            calls = api.call_store.conn.execute('SELECT * FROM call_sessions WHERE recipient_id=? ORDER BY created_at DESC',
                                               (profile.staff_id,)).fetchall()
        for row in calls:
            if row['patient_id'] and not clinical_access(profile,row['patient_id'],row['loop_id']):
                continue
            items.append({'id':f"call:{row['call_id']}:{row['status']}", 'kind':'call',
                'title':people.get(row['caller_id'], 'Unavailable account'), 'body':row['status'],
                'call_id':row['call_id'], 'staff_id':row['caller_id'], 'status':row['status'],
                'created_at':datetime.fromtimestamp(row['created_at'],timezone.utc).isoformat()})
        for item in items:
            item['unread'] = item['id'] not in read and (item['kind'] != 'call' or item['status'] == 'missed')
        items.sort(key=lambda i:i['created_at'],reverse=True)
        return items

    @router.get('')
    def inbox(profile=Depends(api.require_communicating_staff)):
        items = items_for(profile)
        return {'items':items, 'unread_count':sum(i['unread'] for i in items)}

    @router.get('/activities')
    def activities(
        q: str = Query(default='', max_length=160),
        kind: str = Query(default='', pattern='^(|message|call|brief)$'),
        limit: int = Query(default=100, ge=1, le=200),
        profile=Depends(api.require_communicating_staff),
    ):
        """Search recent staff messages, calls, and visible ritual activity."""
        with api.communications_store.connection() as conn:
            read = {r['item_id'] for r in conn.execute(
                'SELECT item_id FROM inbox_reads WHERE staff_id=?', (profile.staff_id,))}
            messages = conn.execute(
                'SELECT * FROM direct_messages WHERE sender_id=? OR recipient_id=? '
                'ORDER BY id DESC LIMIT 500',
                (profile.staff_id, profile.staff_id),
            ).fetchall()
        people = {p.staff_id: p.name for p in api.staff_store.list_staff()}
        result = []
        needle = q.strip().casefold()

        for row in messages:
            incoming = row['recipient_id'] == profile.staff_id
            other_id = row['sender_id'] if incoming else row['recipient_id']
            item_id = f"message:{row['id']}"
            result.append({
                'id': item_id,
                'kind': 'message',
                'title': people.get(other_id, 'Unavailable account'),
                'body': row['body'],
                'staff_id': other_id,
                'direction': 'received' if incoming else 'sent',
                'unread': incoming and item_id not in read,
                'created_at': row['sent_at'],
            })

        with api.call_store._lock:
            calls = api.call_store.conn.execute(
                'SELECT * FROM call_sessions WHERE caller_id=? OR recipient_id=? '
                'ORDER BY created_at DESC LIMIT 500',
                (profile.staff_id, profile.staff_id),
            ).fetchall()
        for row in calls:
            patient_id = row['patient_id']
            loop_id = row['loop_id']
            if patient_id and not clinical_access(profile, patient_id, loop_id):
                continue
            incoming = row['recipient_id'] == profile.staff_id
            other_id = row['caller_id'] if incoming else row['recipient_id']
            item_id = f"call:{row['call_id']}:{row['status']}"
            result.append({
                'id': item_id,
                'kind': 'call',
                'title': people.get(other_id, 'Unavailable account'),
                'body': row['status'],
                'call_id': row['call_id'],
                'staff_id': other_id,
                'direction': 'received' if incoming else 'placed',
                'status': row['status'],
                'unread': incoming and row['status'] == 'missed' and item_id not in read,
                'patient_id': patient_id,
                'loop_id': loop_id,
                'created_at': datetime.fromtimestamp(
                    row['created_at'], timezone.utc
                ).isoformat(),
            })

        if profile.role in CLINICAL_ROLES:
            with api.ritual_store.connection() as conn:
                rituals = conn.execute(
                    'SELECT * FROM clinical_rituals ORDER BY updated_at DESC LIMIT 500'
                ).fetchall()
            for row in rituals:
                ritual = api.ritual_store._row(row)
                participant = api.ritual_store.participant(
                    ritual['ritual_id'], profile.staff_id
                )
                is_creator = ritual['creator_id'] == profile.staff_id
                patient_id = ritual.get('patient_id')
                in_care_team = bool(patient_id) and profile.staff_id in (
                    api._authorized_patient_staff_ids(
                        patient_id, date.today().isoformat()
                    )
                )
                if not (is_creator or participant or in_care_team):
                    continue
                creator = people.get(ritual['creator_id'], 'Clinician')
                result.append({
                    'id': f"brief:{ritual['ritual_id']}",
                    'kind': 'brief',
                    'title': ritual['title'],
                    'body': f"{ritual['ritual_type']} · {ritual['status']} · {creator}",
                    'ritual_id': ritual['ritual_id'],
                    'ritual_type': ritual['ritual_type'],
                    'status': ritual['status'],
                    'creator_id': ritual['creator_id'],
                    'patient_id': patient_id,
                    'scheduled_for': ritual.get('scheduled_for'),
                    'created_at': ritual['updated_at'],
                })

        result = [
            item for item in result
            if (not kind or item['kind'] == kind)
            and (
                not needle
                or needle in ' '.join(str(value) for value in item.values()).casefold()
            )
        ]
        result.sort(key=lambda item: item['created_at'], reverse=True)
        return {'items': result[:limit], 'query': q, 'count': len(result)}

    @router.post('/read')
    def mark_read(payload: ReadItems, profile=Depends(api.require_communicating_staff)):
        allowed = {i['id'] for i in items_for(profile)}
        with api.communications_store.connection() as conn:
            conn.executemany('INSERT OR IGNORE INTO inbox_reads(staff_id,item_id) VALUES (?,?)',
                             [(profile.staff_id,item) for item in payload.ids if item in allowed])
        return {'success':True}

    return router
