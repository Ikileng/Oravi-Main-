import os
import tempfile
import unittest
from datetime import date
from unittest.mock import patch
from fastapi.testclient import TestClient
import backend.main as api
from backend.staff_store import StaffStore
from backend.ward_store import WardStore
from backend.call_store import CallStore
from backend.communications import CommunicationsStore
from backend.models import HospitalWardModel, ShiftAllocationModel


class SupportCommunicationsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        path = os.path.join(self.temp.name, 'test.sqlite')
        self.staff = StaffStore(path)
        self.wards = WardStore(path)
        self.calls = CallStore(path)
        self.comms = CommunicationsStore(path)
        self.staff.create_first_admin('ADMIN', 'Admin', '123456')
        self.staff.create_session('ADMIN', 'ADMIN')
        for staff_id, role in [('N','ward_nurse'),('C','charge_nurse'),('D','doctor_on_call'),
                                ('P','pca'),('H','housekeeper'),('K','catering'),('F','fire_marshall')]:
            self.staff.create_staff(staff_id, 'Staff ' + staff_id, role, '', '1234')
            self.staff.create_session(staff_id, staff_id)
        self.wards.create_ward(HospitalWardModel('A','Ward A',1,['1'],'',''))
        self.staff.set_ward_preference('C','A')
        self.day = date.today().isoformat()
        self.wards.publish_shift_allocation(ShiftAllocationModel('alloc','A','day',self.day,'C','now',
            [{'bed_number':'1','assigned_nurse_id':'N','patient_id':'PRIVATE','patient_initials':'XX'}],{}))
        self.patches = [patch.object(api, key, value) for key,value in [
            ('staff_store',self.staff),('ward_store',self.wards),('call_store',self.calls),
            ('communications_store',self.comms)]]
        for item in self.patches:
            item.start()
        self.client = TestClient(api.app)

    def tearDown(self):
        self.client.close()
        for item in self.patches:
            item.stop()
        self.staff.close()
        self.calls.conn.close()
        self.temp.cleanup()

    def request(self, method, path, who='N', **kwargs):
        return self.client.request(method,path,headers={'Authorization':'Bearer '+who},**kwargs)

    def duty(self, key='housekeeper'):
        return f'/api/v1/wards/A/responsibilities/{key}?duty_date={self.day}&shift_type=day'

    def test_support_is_denied_every_clinical_entry_point(self):
        paths = ['/api/v1/wards', '/api/v1/wards/A/board?date='+self.day+'&shift_type=day',
                 '/api/v1/patients/PRIVATE/staff?date='+self.day,
                 '/api/v1/patients/PRIVATE/medical-issues/secret',
                 '/api/v1/sync/pull?ward_id=A&after_seq=0',
                 '/api/v1/medical-issues/carried', '/api/v1/admin/staff',
                 f'/api/v1/wards/A/responsibilities?duty_date={self.day}&shift_type=day']
        for who in ['P','H','K','F']:
            for path in paths:
                with self.subTest(who=who,path=path):
                    self.assertEqual(self.request('GET',path,who).status_code,403)
            self.assertFalse(self.staff.is_active_clinical_staff(who))
            self.assertEqual(self.request('POST','/api/v1/calls/invite',who,
                json={'patient_id':'PRIVATE','loop_id':'secret','recipient_id':'N'}).status_code,403)

    def test_charge_alone_assigns_fixed_responsibilities(self):
        for who in ['N','D','P','H','K','F','ADMIN']:
            self.assertEqual(self.request('PUT',self.duty(),who,json={'staff_id':'H'}).status_code,403)
        self.assertEqual(self.request('PUT',self.duty(),'C',json={'staff_id':'H'}).status_code,200)
        self.assertEqual(self.request('PUT',self.duty('incharge_nurse'),'C',json={'staff_id':'H'}).status_code,400)
        self.assertEqual(self.request('PUT',self.duty('incharge_nurse'),'C',json={'staff_id':'N'}).status_code,200)
        self.assertEqual(self.request('PUT',self.duty('custom'),'C',json={'staff_id':'H'}).status_code,400)
        response = self.request('GET',f'/api/v1/wards/A/responsibilities?duty_date={self.day}&shift_type=day')
        self.assertEqual(response.status_code,200,response.text)
        self.assertEqual(len(response.json()),8)
        self.assertNotIn('PRIVATE',response.text)
        self.assertNotIn('patient',str(response.json()[0]['staff']))

    def test_support_cannot_be_assigned_as_patient_clinician(self):
        response=self.request('POST','/api/v1/allocations/publish','C',json={
            'allocation_id':'bad','ward_id':'A','shift_type':'day','date':self.day,
            'published_by':'C','published_at':'now','bed_assignments':[{'bed_number':'1','assigned_nurse_id':'H'}],
            'support_roster':{}})
        self.assertEqual(response.status_code,400,response.text)

    def test_messages_are_private_durable_and_retry_safe(self):
        path='/api/v1/direct/threads/H'
        payload={'body':'Please arrange supplies','client_id':'message-1'}
        self.staff.register_fcm_installation('H', 'device', 'test-registration-token', 'android')
        with patch.object(api.fcm_service, 'send_staff_message', return_value=True) as notify:
            for _ in range(2):
                self.assertEqual(self.request('POST',path,json=payload).status_code,200)
            notify.assert_called_once_with('test-registration-token')
        own=self.request('GET',path).json()
        self.assertEqual(len(own),1)
        self.assertEqual(self.request('GET','/api/v1/direct/threads/N','H').json(),own)
        self.assertEqual(self.request('GET',path,'K').json(),[])
        self.assertEqual(self.request('GET',path,'ADMIN').status_code,403)
        with self.comms.connection() as conn:
            self.assertEqual(conn.execute('SELECT count(*) FROM direct_messages').fetchone()[0],1)
        self.assertEqual(self.request('POST',path,json={**payload,'patient_id':'PRIVATE'}).status_code,422)

    def test_deactivated_accounts_cannot_send_or_receive_new_messages(self):
        self.staff.set_staff_active('H',False)
        self.assertEqual(self.request('GET','/api/v1/direct/threads','H').status_code,401)
        self.assertEqual(self.request('POST','/api/v1/direct/threads/H',json={'body':'Hi','client_id':'x'}).status_code,400)

    def test_direct_call_participants_and_no_patient_context(self):
        self.staff.register_fcm_installation('H', 'phone-H', 'test-call-token', 'android')
        with patch.object(api,'_livekit_token',return_value='test-token'), patch.dict(os.environ,{'LIVEKIT_URL':'wss://example.test'}), patch.object(api.fcm_service, 'send_call_invitation', return_value=True):
            response=self.request('POST','/api/v1/direct/calls',json={'recipient_id':'H'})
            self.assertEqual(response.status_code,200,response.text)
            call_id=response.json()['call_id']
            self.assertEqual(response.json()['patient_id'],'')
            self.assertEqual(self.request('GET',f'/api/v1/calls/{call_id}','K').status_code,404)
            self.assertEqual(self.request('POST',f'/api/v1/calls/{call_id}/accept','K').status_code,404)
            self.assertEqual(self.request('POST',f'/api/v1/calls/{call_id}/accept','H').status_code,200)
            self.assertEqual(len(self.request('GET','/api/v1/direct/calls','H').json()),1)
            self.assertEqual(self.request('POST',f'/api/v1/calls/{call_id}/end','H').status_code,200)
            self.assertEqual(self.request('POST','/api/v1/direct/calls',json={'recipient_id':'H','patient_id':'PRIVATE'}).status_code,422)

    def test_admin_provisions_only_predefined_roles(self):
        for role in ['pca','housekeeper','catering','fire_marshall']:
            response=self.request('POST','/api/v1/admin/staff','ADMIN',json={
                'staff_id':'new-'+role,'name':role,'role':role,'pin':'1234'})
            self.assertEqual(response.status_code,200,response.text)
        self.assertEqual(self.request('POST','/api/v1/admin/staff','ADMIN',json={
            'staff_id':'bad','name':'Bad','role':'custom','pin':'1234'}).status_code,400)
