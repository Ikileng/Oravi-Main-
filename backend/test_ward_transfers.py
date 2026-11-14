import os
import tempfile
import unittest
from datetime import date
from unittest.mock import patch

from fastapi.testclient import TestClient
import backend.main as api
from backend.staff_store import StaffStore
from backend.ward_store import WardStore
from backend.event_store import EventStore
from backend.models import HospitalWardModel, ShiftAllocationModel, CanonicalEvent


class WardTransferTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        path = os.path.join(self.temp.name,'test.sqlite')
        self.staff = StaffStore(path)
        # PIN hashing is covered by auth tests; these tests exercise authenticated sessions.
        with patch.object(StaffStore,'hash_pin',return_value='test-only-hash'):
            for who, role in [('C','charge_nurse'),('B','charge_nurse'),('N','ward_nurse'),('R','ward_nurse'),('H','housekeeper')]:
                self.staff.create_staff(who,who,role,'','1234')
                self.staff.create_session(who,who)
        self.staff.set_ward_preference('C','A')
        self.staff.set_ward_preference('B','J')
        self.wards=WardStore(path)
        self.events=EventStore(path)
        self.day=date.today().isoformat()
        for ward in ['A','J']:
            self.wards.create_ward(HospitalWardModel(ward,'Ward '+ward,3,['1','2','3'],'',''))
        self.initial=ShiftAllocationModel('source','A','day',self.day,'C','now',[
            {'bed_number':'1','patient_id':'P1','patient_initials':'XX','assigned_nurse_id':'N'},
            {'bed_number':'2','patient_id':'P2','patient_initials':'YY','assigned_nurse_id':'R'}],{})
        self.wards.publish_shift_allocation(self.initial)
        self.events.append_events([CanonicalEvent('issue','P1','LoopOpened','N','device','now',loop_id='L1',
            payload={'title':'Review results','description':'Pending results','initial_owner_id':'N'})])
        self.patches=[patch.object(api,k,v) for k,v in [('staff_store',self.staff),('ward_store',self.wards),('store',self.events)]]
        for p in self.patches: p.start()
        self.client=TestClient(api.app)

    def tearDown(self):
        self.client.close()
        for p in self.patches: p.stop()
        self.staff.close()
        self.events._conn.close()
        self.temp.cleanup()

    def req(self,method,path,who='C',payload=None):
        return self.client.request(method,'/api/v1'+path,headers={'Authorization':'Bearer '+who},json=payload)

    def initiate(self):
        result=self.req('POST','/ward-transfers',payload={'nurse_id':'N','source_ward':'A','target_ward':'J','date':self.day,'shift_type':'day'})
        self.assertEqual(result.status_code,200,result.text)
        return result.json()['id']

    def test_doctor_removal_and_replacement_update_both_shifts_without_touching_nurses(self):
        with patch.object(StaffStore,'hash_pin',return_value='test-only-hash'):
            for doctor in ['D','E']:
                self.staff.create_staff(doctor,doctor,'doctor_on_call','','1234')
                self.staff.create_session(doctor,doctor)
        night = ShiftAllocationModel('night','A','night',self.day,'C','now',[
            {'bed_number':'1','patient_id':'P1','patient_initials':'XX','admitting_doctor':'D'}],{})
        self.wards.publish_shift_allocation(night)
        with self.wards._get_connection() as conn, conn:
            conn.execute("UPDATE shift_bed_assignments SET admitting_doctor='D' WHERE patient_id='P1'")
        payload = {'date':self.day,'patient_id':'P1','expected_doctor_id':'D','doctor_id':''}
        result = self.req('PUT','/wards/A/beds/1/doctor',payload=payload)
        self.assertEqual(result.status_code,200,result.text)
        for shift in ['day','night']:
            self.assertIsNone(self.wards.get_staff_active_assignment('D',self.day,shift))
        board = self.wards.get_ward_board('A',self.day,'day')['bed_assignments'][0]
        self.assertEqual(board['patient_id'],'P1')
        self.assertEqual(board['day_shift_nurse_id'],'N')
        self.assertEqual(board['admitting_doctor'],'')
        payload.update(expected_doctor_id='',doctor_id='E')
        self.assertEqual(self.req('PUT','/wards/A/beds/1/doctor',payload=payload).status_code,200)
        for shift in ['day','night']:
            self.assertEqual(self.wards.get_staff_active_assignment('E',self.day,shift)['ward_id'],'A')
        self.assertEqual(self.req('PUT','/wards/A/beds/1/doctor',payload=payload).status_code,409)

    def test_doctor_changes_require_charge_ward_and_current_patient(self):
        payload = {'date':self.day,'patient_id':'P1','expected_doctor_id':'','doctor_id':''}
        for actor in ['N','H','B']:
            self.assertEqual(self.req('PUT','/wards/A/beds/1/doctor',actor,payload).status_code,403)
        payload['doctor_id']='N'
        self.assertEqual(self.req('PUT','/wards/A/beds/1/doctor',payload=payload).status_code,400)
        payload.update(doctor_id='',patient_id='old-patient')
        self.assertEqual(self.req('PUT','/wards/A/beds/1/doctor',payload=payload).status_code,409)

    def submit(self,tid):
        result=self.req('POST',f'/ward-transfers/{tid}/handoff','N',{'replacement_id':'R','notes':'Please follow up results'})
        self.assertEqual(result.status_code,200,result.text)
        return self.req('GET',f'/ward-transfers/{tid}/handoff','R').json()['revision']

    def test_handoff_acceptance_atomically_transfers_responsibility_and_ward(self):
        self.staff.register_fcm_installation('N','device','token','android')
        with patch.object(api.fcm_service,'send_transfer_alert',return_value=True) as push:
            tid=self.initiate()
            push.assert_called_once_with('token')
        self.assertEqual(self.wards.get_staff_active_assignment('N',self.day,'day')['ward_id'],'A')
        self.assertEqual(self.req('POST',f'/ward-transfers/{tid}/accept','R',{'revision':'x'}).status_code,403)
        revision=self.submit(tid)
        self.assertEqual(self.req('POST',f'/ward-transfers/{tid}/accept','N',{'revision':revision}).status_code,403)
        with patch.object(api.fcm_service,'send_transfer_alert',return_value=True):
            result=self.req('POST',f'/ward-transfers/{tid}/accept','R',{'revision':revision})
        self.assertEqual(result.status_code,200,result.text)
        self.assertEqual(self.wards.get_staff_active_assignment('N',self.day,'day')['ward_id'],'J')
        board=self.wards.get_ward_board('A',self.day,'day')
        self.assertEqual(board['bed_assignments'][0]['day_shift_nurse_id'],'R')
        self.assertEqual(board['bed_assignments'][0]['patient_id'],'P1')
        self.assertEqual(self.req('GET',f'/wards/J/board?date={self.day}&shift_type=day','N').status_code,200)
        self.assertEqual(self.req('GET',f'/wards/A/board?date={self.day}&shift_type=day','N').status_code,403)
        history=self.events.get_patient_events('P1')
        self.assertEqual(history[-1].payload['new_owner_id'],'R')
        self.assertEqual(self.req('POST',f'/ward-transfers/{tid}/accept','R',{'revision':revision}).status_code,200)
        self.assertEqual(len(self.events.get_patient_events('P1')),len(history))

    def test_pending_handoff_cannot_be_bypassed_and_decline_keeps_assignments(self):
        tid=self.initiate()
        result=self.req('PUT','/wards/A/beds/1/nurse',payload={'date':self.day,'shift_type':'day','expected_nurse_id':'N','nurse_id':None})
        self.assertEqual(result.status_code,409,result.text)
        changed=ShiftAllocationModel('replacement','A','day',self.day,'C','now',[],{})
        with self.assertRaisesRegex(ValueError,'pending transfer'):
            self.wards.publish_shift_allocation(changed)
        self.submit(tid)
        self.assertEqual(self.req('POST',f'/ward-transfers/{tid}/decline','R').status_code,200)
        self.assertEqual(self.wards.get_staff_active_assignment('N',self.day,'day')['ward_id'],'A')
        self.assertEqual(self.req('POST',f'/ward-transfers/{tid}/cancel').status_code,200)
        self.assertEqual(self.req('POST',f'/ward-transfers/{tid}/accept','R',{'revision':'x'}).status_code,403)

    def test_changed_medical_issue_requires_resubmission(self):
        tid=self.initiate(); revision=self.submit(tid)
        self.events.append_events([CanonicalEvent('update','P1','LoopUpdated','N','device','later',loop_id='L1',payload={'note':'New information'})])
        result=self.req('POST',f'/ward-transfers/{tid}/accept','R',{'revision':revision})
        self.assertEqual(result.status_code,409,result.text)
        self.assertEqual(self.wards.get_staff_active_assignment('N',self.day,'day')['ward_id'],'A')
        revision=self.submit(tid)
        self.assertEqual(self.req('POST',f'/ward-transfers/{tid}/accept','R',{'revision':revision}).status_code,200)

    def test_double_shift_confirmation_and_correction_and_cross_ward_block(self):
        payload={'date':self.day,'shift_type':'night','nurse_id':'N','expected_nurse_id':None}
        result=self.req('PUT','/wards/A/beds/1/nurse',payload=payload)
        self.assertEqual(result.status_code,409,result.text)
        result=self.req('PUT','/wards/A/beds/1/nurse',payload={**payload,'confirm_both_shifts':True})
        self.assertEqual(result.status_code,200,result.text)
        result=self.req('PUT','/wards/A/beds/1/nurse',payload={'date':self.day,'shift_type':'day','nurse_id':None,'expected_nurse_id':'N'})
        self.assertEqual(result.status_code,200,result.text)
        result=self.req('PUT','/wards/A/beds/1/nurse',payload={'date':self.day,'shift_type':'day','nurse_id':'N','expected_nurse_id':None,'move_from_other_shift':True})
        self.assertEqual(result.status_code,200,result.text)
        row=self.wards.get_ward_board('A',self.day,'day')['bed_assignments'][0]
        self.assertEqual(row['day_shift_nurse_id'],'N'); self.assertIsNone(row['night_shift_nurse_id'])
        result=self.req('PUT','/wards/J/beds/1/nurse','B',{'date':self.day,'shift_type':'day','nurse_id':'N'})
        self.assertEqual(result.status_code,409,result.text)
        self.assertIn('Ward A',result.text)

    def test_privacy_and_stale_edits(self):
        tid=self.initiate()
        self.assertEqual(self.req('GET',f'/ward-transfers/{tid}/handoff','C').status_code,403)
        self.assertEqual(self.req('GET','/ward-transfers','H').status_code,403)
        self.assertEqual(self.req('GET','/ward-transfers','R').json(),[])
        self.assertEqual(self.req('POST',f'/ward-transfers/{tid}/handoff','N',{'replacement_id':'H'}).status_code,400)
        result=self.req('PUT','/wards/A/beds/2/nurse',payload={'date':self.day,'shift_type':'day','nurse_id':'N','expected_nurse_id':'OTHER'})
        self.assertEqual(result.status_code,409,result.text)

    def test_publish_cannot_bypass_double_shift_confirmation(self):
        opposite=ShiftAllocationModel('night','A','night',self.day,'C','now',self.initial.bed_assignments,{})
        with self.assertRaisesRegex(ValueError,'Explicit confirmation'):
            self.wards.publish_shift_allocation(opposite)
        opposite.confirmed_double_shift_nurse_ids=['N','R']
        self.assertTrue(self.wards.publish_shift_allocation(opposite))

    def test_acceptance_failure_rolls_back_events_and_patient_changes(self):
        tid=self.initiate(); revision=self.submit(tid)
        before=len(self.events.get_patient_events('P1'))
        # A conflicting placement discovered at commit must roll back the whole handoff.
        with self.wards._get_connection() as conn, conn:
            conn.execute('INSERT INTO nurse_shift_placements VALUES (?,?,?,?)',('R',self.day,'day','J'))
        result=self.req('POST',f'/ward-transfers/{tid}/accept','R',{'revision':revision})
        self.assertEqual(result.status_code,409,result.text)
        self.assertEqual(len(self.events.get_patient_events('P1')),before)
        self.assertEqual(self.wards.get_ward_board('A',self.day,'day')['bed_assignments'][0]['day_shift_nurse_id'],'N')
        self.assertEqual(self.wards.get_staff_active_assignment('N',self.day,'day')['ward_id'],'A')


if __name__=='__main__': unittest.main()
