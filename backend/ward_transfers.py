"""Explicit shift corrections and ward transfers gated by a receiving nurse's handoff."""
import hashlib
import json
import uuid
from datetime import date as CalendarDate, datetime, timezone
from typing import Literal

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from pydantic import BaseModel, ConfigDict
from .models import CanonicalEvent
from .services.medical_issue_validation import open_medical_issue_ids


def init_transfer_tables(conn):
    conn.executescript('''
      CREATE TABLE IF NOT EXISTS nurse_shift_placements (
        staff_id TEXT NOT NULL, date TEXT NOT NULL, shift_type TEXT NOT NULL,
        ward_id TEXT NOT NULL, PRIMARY KEY(staff_id,date,shift_type));
      CREATE TABLE IF NOT EXISTS ward_transfers (
        id TEXT PRIMARY KEY, nurse_id TEXT NOT NULL, source_ward TEXT NOT NULL,
        target_ward TEXT NOT NULL, date TEXT NOT NULL, shift_type TEXT NOT NULL,
        initiated_by TEXT NOT NULL, replacement_id TEXT, status TEXT NOT NULL,
        handoff_json TEXT, created_at TEXT NOT NULL, completed_at TEXT);
      CREATE UNIQUE INDEX IF NOT EXISTS one_pending_ward_transfer
        ON ward_transfers(nurse_id,date,shift_type)
        WHERE status IN ('pending','handoff');
      CREATE TABLE IF NOT EXISTS nurse_shift_confirmations (
        nurse_id TEXT NOT NULL, date TEXT NOT NULL, confirmed_by TEXT NOT NULL,
        confirmed_at TEXT NOT NULL, PRIMARY KEY(nurse_id,date));
    ''')


def assignments(conn, nurse_id, day):
    return [dict(r) for r in conn.execute('''SELECT DISTINCT x.ward_id,w.name AS ward_name,x.shift_type
        FROM (SELECT ward_id,shift_type FROM shift_bed_assignments WHERE assigned_nurse_id=? AND date=?
        UNION SELECT ward_id,shift_type FROM nurse_shift_placements WHERE staff_id=? AND date=?) x
        JOIN hospital_wards w ON w.ward_id=x.ward_id''', (nurse_id,day,nurse_id,day))]


def check_assignment(conn, nurse_id, day, shift, ward, confirmed=False, actor=''):
    if not nurse_id:
        return
    existing = assignments(conn, nurse_id, day)
    conflict = next((r for r in existing if r['shift_type'] == shift and r['ward_id'] != ward), None)
    if conflict:
        raise ValueError(f"{nurse_id} is already in {conflict['ward_name']} for {shift}. An explicit ward transfer is required.")
    opposite = any(r['shift_type'] != shift for r in existing)
    already_both = {r['shift_type'] for r in existing} == {'day','night'}
    if opposite and not already_both and not confirmed:
        raise ValueError(f'{nurse_id} already has the opposite shift. Explicit confirmation is required for both shifts.')
    if opposite and confirmed:
        conn.execute('INSERT OR REPLACE INTO nurse_shift_confirmations VALUES (?,?,?,?)',
                     (nurse_id,day,actor,datetime.now(timezone.utc).isoformat()))


def protect_pending_board(conn, allocation):
    pending = conn.execute("SELECT nurse_id FROM ward_transfers WHERE source_ward=? AND date=? AND shift_type=? AND status IN ('pending','handoff')",
                           (allocation.ward_id,allocation.date,allocation.shift_type)).fetchall()
    for row in pending:
        nurse = row['nurse_id']
        old = {(r['bed_number'],r['patient_id'],r['assigned_nurse_id']) for r in conn.execute(
            'SELECT bed_number,patient_id,assigned_nurse_id FROM shift_bed_assignments WHERE ward_id=? AND date=? AND shift_type=? AND assigned_nurse_id=?',
            (allocation.ward_id,allocation.date,allocation.shift_type,nurse))}
        new = {(r.get('bed_number'),r.get('patient_id'),r.get('assigned_nurse_id')) for r in allocation.bed_assignments if r.get('assigned_nurse_id') == nurse}
        if old != new:
            raise ValueError('This nurse has a pending transfer. Complete or cancel the handoff before changing their allocations.')


class StrictRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')


class CellChange(StrictRequest):
    date: str
    shift_type: Literal['day','night']
    nurse_id: str | None = None
    expected_nurse_id: str | None = None
    confirm_both_shifts: bool = False
    move_from_other_shift: bool = False


class TransferRequest(StrictRequest):
    nurse_id: str
    source_ward: str
    target_ward: str
    date: str
    shift_type: Literal['day','night']


class DoctorChange(StrictRequest):
    date: str
    patient_id: str | None = None
    expected_doctor_id: str = ''
    doctor_id: str = ''


class HandoffRequest(StrictRequest):
    replacement_id: str
    notes: str = ''


class AcceptRequest(StrictRequest):
    revision: str
    confirm_both_shifts: bool = False


def build_transfer_router(api):
    router = APIRouter(prefix='/api/v1')

    def validate_date(day):
        try:
            CalendarDate.fromisoformat(day)
        except ValueError:
            raise HTTPException(400, 'Invalid shift date.')

    def nurse(staff_id):
        people = api.staff_store.get_active_staff_by_ids([staff_id])
        if not people or people[0].role not in {'ward_nurse','charge_nurse'}:
            raise HTTPException(400, 'Choose an active nurse.')
        return people[0]

    def notify(staff_id):
        for token in api.staff_store.get_fcm_fids_for_staff(staff_id):
            try:
                api.fcm_service.send_transfer_alert(token)
            except Exception:
                api.logger.warning('Ward transfer saved; push delivery failed. The in-app notice remains available.')

    def get_transfer(conn, transfer_id):
        row = conn.execute('SELECT * FROM ward_transfers WHERE id=?', (transfer_id,)).fetchone()
        if row is None:
            raise HTTPException(404, 'Transfer not found.')
        return dict(row)

    def can_view(t, profile):
        return profile.staff_id in {t['nurse_id'],t['replacement_id']} or (
            profile.role == 'charge_nurse' and api.staff_store.get_ward_preference(profile.staff_id) in {t['source_ward'],t['target_ward']})

    def snapshot(conn, t):
        beds = [dict(r) for r in conn.execute('''SELECT bed_number,patient_id,patient_initials
            FROM shift_bed_assignments WHERE ward_id=? AND date=? AND shift_type=?
            AND assigned_nurse_id=? ORDER BY bed_number''',
            (t['source_ward'],t['date'],t['shift_type'],t['nurse_id']))]
        for bed in beds:
            history = api.store.get_patient_events(bed['patient_id']) if bed['patient_id'] else []
            ids = open_medical_issue_ids(history)
            bed['issues'] = [e.to_dict() for e in history if e.loop_id in ids]
            bed['loop_ids'] = sorted(ids)
        return beds

    def revision(beds):
        return hashlib.sha256(json.dumps(beds,sort_keys=True,default=str).encode()).hexdigest()

    @router.get('/nurses/{nurse_id}/assignments')
    def nurse_assignments(nurse_id: str, date: str, profile=Depends(api.require_charge_nurse)):
        validate_date(date)
        with api.ward_store._get_connection() as conn:
            return assignments(conn,nurse_id,date)

    @router.put('/wards/{ward_id}/beds/{bed_number}/nurse')
    def change_nurse(ward_id: str, bed_number: str, payload: CellChange, profile=Depends(api.require_charge_nurse)):
        validate_date(payload.date)
        if api.staff_store.get_ward_preference(profile.staff_id) != ward_id:
            raise HTTPException(403, 'Confirm this ward first.')
        if payload.nurse_id:
            nurse(payload.nurse_id)
        try:
            with api.store._lock, api.ward_store._get_connection() as conn, conn:
                conn.execute('BEGIN IMMEDIATE')
                ward = conn.execute('SELECT bed_numbers FROM hospital_wards WHERE ward_id=?',(ward_id,)).fetchone()
                if not ward or bed_number not in json.loads(ward['bed_numbers']):
                    raise ValueError('This bed no longer exists. Reload the board.')
                rows = conn.execute('SELECT * FROM shift_bed_assignments WHERE ward_id=? AND date=? AND bed_number=?',
                                    (ward_id,payload.date,bed_number)).fetchall()
                current = next((r for r in rows if r['shift_type'] == payload.shift_type),None)
                other = next((r for r in rows if r['shift_type'] != payload.shift_type),None)
                actual = current['assigned_nurse_id'] or None if current else None
                if actual != (payload.expected_nurse_id or None):
                    raise ValueError('This assignment changed. Reload and try again.')
                for person in {actual,payload.nurse_id,other['assigned_nurse_id'] if payload.move_from_other_shift and other else None} - {None,''}:
                    if conn.execute("SELECT 1 FROM ward_transfers WHERE nurse_id=? AND date=? AND status IN ('pending','handoff')",(person,payload.date)).fetchone():
                        raise ValueError('This nurse has a pending transfer. Complete or cancel it before editing assignments.')
                if payload.move_from_other_shift:
                    if not other or other['assigned_nurse_id'] != payload.nurse_id or actual:
                        raise ValueError('Move requires this nurse in the other column and an empty destination. Reload the board.')
                    conn.execute('UPDATE shift_bed_assignments SET assigned_nurse_id=NULL,status=\'pending\' WHERE id=?',(other['id'],))
                check_assignment(conn,payload.nurse_id,payload.date,payload.shift_type,ward_id,payload.confirm_both_shifts,profile.staff_id)
                if current:
                    conn.execute("UPDATE shift_bed_assignments SET assigned_nurse_id=?,status='pending' WHERE id=?",(payload.nurse_id,current['id']))
                elif payload.nurse_id:
                    allocation = conn.execute('SELECT allocation_id FROM shift_allocations WHERE ward_id=? AND date=? AND shift_type=?',
                                              (ward_id,payload.date,payload.shift_type)).fetchone()
                    aid = allocation['allocation_id'] if allocation else str(uuid.uuid4())
                    if not allocation:
                        conn.execute('INSERT INTO shift_allocations VALUES (?,?,?,?,?,?,?)',(aid,ward_id,payload.shift_type,payload.date,profile.staff_id,datetime.now(timezone.utc).isoformat(),'{}'))
                    conn.execute('''INSERT INTO shift_bed_assignments
                        (allocation_id,ward_id,bed_number,patient_id,patient_initials,admitting_doctor,assigned_nurse_id,shift_type,date,status)
                        VALUES (?,?,?,?,?,?,?,?,?,'pending')''', (aid,ward_id,bed_number,other['patient_id'] if other else None,
                        other['patient_initials'] if other else '',other['admitting_doctor'] if other else '',payload.nurse_id,payload.shift_type,payload.date))
        except ValueError as error:
            raise HTTPException(409,str(error))
        return {'success': True}

    @router.put('/wards/{ward_id}/beds/{bed_number}/doctor')
    def change_doctor(ward_id: str, bed_number: str, payload: DoctorChange, profile=Depends(api.require_charge_nurse)):
        validate_date(payload.date)
        if api.staff_store.get_ward_preference(profile.staff_id) != ward_id:
            raise HTTPException(403, 'Confirm this ward first.')
        if payload.doctor_id:
            people = api.staff_store.get_active_staff_by_ids([payload.doctor_id])
            if not people or people[0].role != 'doctor_on_call':
                raise HTTPException(400, 'Choose an active doctor.')
        with api.store._lock, api.ward_store._get_connection() as conn, conn:
            conn.execute('BEGIN IMMEDIATE')
            rows = conn.execute('SELECT * FROM shift_bed_assignments WHERE ward_id=? AND date=? AND bed_number=?',
                                (ward_id,payload.date,bed_number)).fetchall()
            # A doctor is displayed once per patient, across both shift columns.
            matching = [r for r in rows if (r['patient_id'] or None) == (payload.patient_id or None)]
            normal = lambda value: '' if value in (None, '', '-') else value
            if not matching or any(normal(r['admitting_doctor']) != normal(payload.expected_doctor_id) for r in matching):
                raise HTTPException(409, 'This assignment changed. Reload the board and try again.')
            for row in matching:
                conn.execute('UPDATE shift_bed_assignments SET admitting_doctor=? WHERE id=?',
                             (payload.doctor_id,row['id']))
        return {'success': True}

    @router.get('/ward-transfers')
    def transfers(profile=Depends(api.require_staff)):
        names = {p.staff_id:p.name for p in api.staff_store.list_staff()}
        wards = {w.ward_id:w.name for w in api.ward_store.get_all_wards()}
        with api.ward_store._get_connection() as conn:
            rows = [dict(r) for r in conn.execute('SELECT * FROM ward_transfers ORDER BY created_at DESC')]
        return [{**{k:v for k,v in t.items() if k != 'handoff_json'},
                 'nurse_name':names.get(t['nurse_id'],t['nurse_id']),
                 'source_name':wards.get(t['source_ward'],t['source_ward']),
                 'target_name':wards.get(t['target_ward'],t['target_ward'])} for t in rows if can_view(t,profile)]

    @router.post('/ward-transfers')
    def initiate(payload: TransferRequest, background: BackgroundTasks, profile=Depends(api.require_charge_nurse)):
        validate_date(payload.date)
        nurse(payload.nurse_id)
        if payload.source_ward == payload.target_ward:
            raise HTTPException(400,'Choose a different destination ward.')
        if api.staff_store.get_ward_preference(profile.staff_id) not in {payload.source_ward,payload.target_ward}:
            raise HTTPException(403,'Confirm the source or destination ward first.')
        if payload.target_ward not in {w.ward_id for w in api.ward_store.get_all_wards()}:
            raise HTTPException(404,'Destination ward not found.')
        with api.store._lock, api.ward_store._get_connection() as conn, conn:
            conn.execute('BEGIN IMMEDIATE')
            if not any(r['ward_id']==payload.source_ward and r['shift_type']==payload.shift_type for r in assignments(conn,payload.nurse_id,payload.date)):
                raise HTTPException(409,'The nurse is no longer assigned to that source ward and shift.')
            if conn.execute("SELECT 1 FROM ward_transfers WHERE nurse_id=? AND date=? AND shift_type=? AND status IN ('pending','handoff')",
                            (payload.nurse_id,payload.date,payload.shift_type)).fetchone():
                raise HTTPException(409,'This nurse already has a pending transfer.')
            tid = str(uuid.uuid4())
            conn.execute('INSERT INTO ward_transfers VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
                (tid,payload.nurse_id,payload.source_ward,payload.target_ward,payload.date,payload.shift_type,profile.staff_id,None,'pending',None,datetime.now(timezone.utc).isoformat(),None))
        background.add_task(notify,payload.nurse_id)
        return {'id':tid}

    @router.get('/ward-transfers/{transfer_id}/handoff')
    def handoff(transfer_id: str, profile=Depends(api.require_staff)):
        with api.store._lock, api.ward_store._get_connection() as conn:
            t = get_transfer(conn,transfer_id)
            if profile.staff_id not in {t['nurse_id'],t['replacement_id']}:
                raise HTTPException(403,'Only the handing-over and receiving nurses may review this handoff.')
            beds = snapshot(conn,t) if t['status'] != 'completed' else json.loads(t['handoff_json'] or '{}').get('beds',[])
            saved = json.loads(t['handoff_json'] or '{}')
            return {'beds':beds,'revision':revision(beds),'notes':saved.get('notes',''),
                    'submitted_revision':saved.get('revision')}

    @router.get('/ward-transfers/{transfer_id}/replacements')
    def replacements(transfer_id: str, profile=Depends(api.require_staff)):
        with api.ward_store._get_connection() as conn:
            t = get_transfer(conn,transfer_id)
            if profile.staff_id != t['nurse_id']:
                raise HTTPException(403,'Only the transferring nurse can choose the handoff recipient.')
            return [{'staff_id':p.staff_id,'name':p.name} for p in api.staff_store.list_staff()
                    if p.is_active and p.role in {'ward_nurse','charge_nurse'} and p.staff_id != t['nurse_id']
                    and any(r['ward_id']==t['source_ward'] and r['shift_type']==t['shift_type'] for r in assignments(conn,p.staff_id,t['date']))]

    @router.post('/ward-transfers/{transfer_id}/handoff')
    def submit_handoff(transfer_id: str, payload: HandoffRequest, background: BackgroundTasks, profile=Depends(api.require_staff)):
        nurse(payload.replacement_id)
        if len(payload.notes)>4000:
            raise HTTPException(400,'Handoff notes must be at most 4000 characters.')
        with api.store._lock, api.ward_store._get_connection() as conn, conn:
            conn.execute('BEGIN IMMEDIATE')
            t = get_transfer(conn,transfer_id)
            if profile.staff_id != t['nurse_id'] or t['status'] not in {'pending','handoff'}:
                raise HTTPException(403,'Only the transferring nurse can submit a pending handoff.')
            if payload.replacement_id == t['nurse_id'] or not any(r['ward_id']==t['source_ward'] and r['shift_type']==t['shift_type'] for r in assignments(conn,payload.replacement_id,t['date'])):
                raise HTTPException(409,'The replacement must be assigned to the source ward for this shift.')
            if conn.execute("SELECT 1 FROM ward_transfers WHERE nurse_id=? AND date=? AND shift_type=? AND status IN ('pending','handoff')",(payload.replacement_id,t['date'],t['shift_type'])).fetchone():
                raise HTTPException(409,'The replacement is also awaiting transfer. Choose another nurse.')
            beds = snapshot(conn,t)
            conn.execute("UPDATE ward_transfers SET replacement_id=?,status='handoff',handoff_json=? WHERE id=?",
                (payload.replacement_id,json.dumps({'beds':beds,'revision':revision(beds),'notes':payload.notes}),transfer_id))
        background.add_task(notify,payload.replacement_id)
        return {'success':True}

    @router.post('/ward-transfers/{transfer_id}/cancel')
    def cancel(transfer_id: str, profile=Depends(api.require_charge_nurse)):
        with api.store._lock, api.ward_store._get_connection() as conn, conn:
            conn.execute('BEGIN IMMEDIATE')
            t=get_transfer(conn,transfer_id)
            if not can_view(t,profile) or t['status'] not in {'pending','handoff'}:
                raise HTTPException(409,'Only a charge nurse in an involved ward can cancel a pending transfer.')
            conn.execute("UPDATE ward_transfers SET status='cancelled' WHERE id=?",(transfer_id,))
        return {'success':True}

    @router.post('/ward-transfers/{transfer_id}/decline')
    def decline(transfer_id: str, background: BackgroundTasks, profile=Depends(api.require_staff)):
        with api.store._lock, api.ward_store._get_connection() as conn, conn:
            conn.execute('BEGIN IMMEDIATE')
            t=get_transfer(conn,transfer_id)
            if profile.staff_id != t['replacement_id'] or t['status'] != 'handoff':
                raise HTTPException(403,'Only the designated recipient can decline this handoff.')
            conn.execute("UPDATE ward_transfers SET status='pending',replacement_id=NULL,handoff_json=NULL WHERE id=?",(transfer_id,))
        background.add_task(notify,t['nurse_id'])
        return {'success':True}

    @router.post('/ward-transfers/{transfer_id}/accept')
    def accept(transfer_id: str, payload: AcceptRequest, background: BackgroundTasks, profile=Depends(api.require_staff)):
        try:
            with api.store._lock, api.ward_store._get_connection() as read:
                t=get_transfer(read,transfer_id)
                if profile.staff_id != t['replacement_id']:
                    raise HTTPException(403,'Only the designated receiving nurse can accept responsibility.')
                if t['status']=='completed':
                    return {'success':True}
                if t['status']!='handoff':
                    raise HTTPException(409,'The outgoing nurse must submit the handoff first.')
                nurse(t['nurse_id']); nurse(t['replacement_id'])
                beds=snapshot(read,t)
                saved=json.loads(t['handoff_json'] or '{}')
                if payload.revision != revision(beds) or saved.get('revision') != payload.revision:
                    raise ValueError('Patients or Medical Issues changed. The outgoing nurse must review and submit the handoff again.')
                now=datetime.now(timezone.utc).isoformat()
                events=[]
                for bed in beds:
                    if not bed['patient_id']:
                        continue
                    events.append(CanonicalEvent(str(uuid.uuid4()),bed['patient_id'],'BedAccepted',profile.staff_id,
                        'TRANSFER-'+transfer_id,now,payload={'handoff_session_id':transfer_id,'incoming_nurse_id':profile.staff_id,
                        'outgoing_nurse_id':t['nurse_id'],'bed_number':bed['bed_number'],'transferred_loop_ids':bed['loop_ids'],'ward_transfer':True}))
                    for loop_id in bed['loop_ids']:
                        events.append(CanonicalEvent(str(uuid.uuid4()),bed['patient_id'],'LoopOwnerChanged',profile.staff_id,
                            'TRANSFER-'+transfer_id,now,loop_id=loop_id,payload={'new_owner_id':profile.staff_id,
                            'new_owner_role':profile.role,'transfer_reason':'Accepted ward-transfer handoff','handoff_session_id':transfer_id}))
                def complete(conn):
                    # append_events owns the transaction; acquire a write lock even for a zero-patient handoff.
                    conn.execute('UPDATE ward_transfers SET status=status WHERE id=?',(transfer_id,))
                    current=get_transfer(conn,transfer_id)
                    if current['status']!='handoff' or current['handoff_json']!=t['handoff_json']:
                        raise ValueError('The transfer changed. Reload it.')
                    live = snapshot(conn,t)
                    if [(b['bed_number'],b['patient_id']) for b in live] != [(b['bed_number'],b['patient_id']) for b in beds]:
                        raise ValueError('The patient assignments changed. Submit the handoff again.')
                    if conn.execute("SELECT 1 FROM ward_transfers WHERE nurse_id=? AND date=? AND shift_type=? AND status IN ('pending','handoff')",(profile.staff_id,t['date'],t['shift_type'])).fetchone():
                        raise ValueError('The replacement now has a pending transfer.')
                    check_assignment(conn,profile.staff_id,t['date'],t['shift_type'],t['source_ward'],payload.confirm_both_shifts,profile.staff_id)
                    for bed in beds:
                        if bed['patient_id']:
                            origin=conn.execute('SELECT allocation_id FROM shift_bed_assignments WHERE ward_id=? AND date=? AND shift_type=? AND patient_id=?',
                                (t['source_ward'],t['date'],t['shift_type'],bed['patient_id'])).fetchone()
                            conn.execute('INSERT INTO handoff_bed_acceptances VALUES (?,?,?,?,?,?,?,?)',
                                (transfer_id,origin['allocation_id'],bed['patient_id'],bed['bed_number'],t['nurse_id'],profile.staff_id,json.dumps(bed['loop_ids']),now))
                    conn.execute("UPDATE shift_bed_assignments SET assigned_nurse_id=?,status='accepted' WHERE assigned_nurse_id=? AND ward_id=? AND date=? AND shift_type=?",
                        (profile.staff_id,t['nurse_id'],t['source_ward'],t['date'],t['shift_type']))
                    conn.execute('DELETE FROM nurse_shift_placements WHERE staff_id=? AND date=? AND shift_type=?',(t['nurse_id'],t['date'],t['shift_type']))
                    check_assignment(conn,t['nurse_id'],t['date'],t['shift_type'],t['target_ward'],True,t['initiated_by'])
                    conn.execute('INSERT OR REPLACE INTO nurse_shift_placements VALUES (?,?,?,?)',(t['nurse_id'],t['date'],t['shift_type'],t['target_ward']))
                    conn.execute("UPDATE ward_transfers SET status='completed',completed_at=? WHERE id=?",(now,transfer_id))
                api.store.append_events(events,transaction_action=complete)
        except ValueError as error:
            raise HTTPException(409,str(error))
        background.add_task(notify,t['nurse_id'])
        return {'success':True}

    return router
