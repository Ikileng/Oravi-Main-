import os
import tempfile
import unittest
from datetime import date
from unittest.mock import patch
from fastapi.testclient import TestClient
import backend.main as api
from backend.communications import CommunicationsStore
from backend.event_store import EventStore
from backend.call_store import CallStore
from backend.staff_store import StaffStore
from backend.ward_store import WardStore
from backend.models import HospitalWardModel, ShiftAllocationModel, CanonicalEvent


class InboxTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        path = os.path.join(self.temp.name,'test.db')
        self.staff = StaffStore(path)
        self.wards = WardStore(path)
        self.events = EventStore(path)
        self.calls = CallStore(path)
        self.comms = CommunicationsStore(path)
        with patch.object(StaffStore,'hash_pin',return_value='test'):
            for who, role in [('N','ward_nurse'),('D','doctor_on_call'),('C','charge_nurse'),('H','housekeeper')]:
                self.staff.create_staff(who,who,role,'','1234')
                self.staff.create_session(who,who)
        self.staff.set_ward_preference('C','A')
        self.day = date.today().isoformat()
        self.wards.create_ward(HospitalWardModel('A','Ward A',1,['1'],'',''))
        self.wards.publish_shift_allocation(ShiftAllocationModel('A','A','day',self.day,'C','now',[
            {'bed_number':'1','patient_id':'P','patient_initials':'XX','assigned_nurse_id':'N','admitting_doctor':'D'}],{}))
        self.patches = [patch.object(api,key,value) for key,value in [
            ('staff_store',self.staff),('ward_store',self.wards),('store',self.events),
            ('call_store',self.calls),('communications_store',self.comms)]]
        for p in self.patches: p.start()
        self.client = TestClient(api.app)

    def tearDown(self):
        self.client.close()
        for p in self.patches: p.stop()
        self.staff.close()
        self.calls.conn.close()
        self.events._conn.close()
        self.temp.cleanup()

    def req(self,method,path='',who='N',payload=None):
        return self.client.request(method,'/api/v1/inbox'+path,headers={'Authorization':'Bearer '+who},json=payload)

    def message(self,ident):
        with self.comms.connection() as conn:
            conn.execute('INSERT INTO direct_messages(sender_id,recipient_id,body,sent_at,client_id) VALUES (?,?,?,?,?)',
                         ('H','N','Hello',self.day,ident))

    def issue(self):
        opened = CanonicalEvent('opened','P','LoopOpened','D','dev',self.day+'T09:00:00Z',loop_id='L',
                                payload={'title':'Review','urgency':'routine','initial_owner_id':'N'})
        self.events.append_events([opened],notification_staff_ids_by_event={'opened':['N','H','D']})

    def test_read_receipts_persist_and_do_not_swallow_new_messages(self):
        self.message('one')
        inbox = self.req('GET').json()
        self.assertEqual(inbox['unread_count'],1)
        ident = inbox['items'][0]['id']
        self.req('POST','/read','D',{'ids':[ident]})
        self.assertEqual(self.req('GET').json()['unread_count'],1)
        self.message('two')
        self.req('POST','/read',payload={'ids':[ident]})
        self.assertEqual(self.req('GET').json()['unread_count'],1)
        # A new store/connection sees the saved read state; no session-local counters.
        with patch.object(api,'communications_store',CommunicationsStore(self.comms.db_path)):
            self.assertFalse(next(i for i in self.req('GET').json()['items'] if i['id']==ident)['unread'])
        self.assertEqual(self.req('GET',who='H').json()['unread_count'],0)

    def test_clinical_alerts_survive_push_failure_but_not_revoked_access(self):
        self.issue()
        self.assertEqual(self.req('GET').json()['unread_count'],1)
        self.assertEqual(self.req('GET',who='H').json()['items'],[])
        self.assertEqual(self.req('GET',who='D').json()['items'],[]) # own event
        with self.wards._get_connection() as conn, conn:
            conn.execute("UPDATE shift_bed_assignments SET assigned_nurse_id=NULL")
        self.assertEqual(self.req('GET').json()['items'],[])

    def test_calls_include_clinical_calls_and_only_unseen_missed_count(self):
        for ident,patient,loop in [('direct','',''),('clinical','P','L')]:
            self.calls.create(call_id=ident,room_name=ident,patient_id=patient,loop_id=loop,
                              caller_id='D',recipient_id='N',lifetime_seconds=-1)
        inbox = self.req('GET').json()
        self.assertEqual(inbox['unread_count'],2)
        self.req('POST','/read',payload={'ids':[i['id'] for i in inbox['items']]})
        self.assertEqual(self.req('GET').json()['unread_count'],0)
        self.calls.create(call_id='ring',room_name='ring',patient_id='',loop_id='',caller_id='D',recipient_id='N')
        self.assertEqual(self.req('GET').json()['unread_count'],0)

    def test_recipients_include_participants_and_mentions_but_not_sender(self):
        self.issue()
        comment = CanonicalEvent('reply','P','MessagePosted','N','dev',self.day+'T10:00:00Z',loop_id='L',
                                 payload={'content':'Update','mentioned_staff_ids':['C','H']})
        self.assertEqual(api._notification_recipients_for_events([comment])['reply'],['C','D'])

    def test_message_author_role_is_verified_by_server(self):
        self.issue()
        event = CanonicalEvent('reply','P','MessagePosted','N','dev',self.day+'T10:00:00Z',loop_id='L',
                               payload={'message_id':'M','content':'Update','author_role':'doctor_on_call'})
        result = self.client.post('/api/v1/sync/push',headers={'Authorization':'Bearer N'},
                                  json={'device_id':'dev','events':[event.to_dict()]})
        self.assertEqual(result.status_code,200,result.text)
        self.assertEqual(self.events.get_loop_events('P','L')[-1].payload['author_role'],'ward_nurse')
