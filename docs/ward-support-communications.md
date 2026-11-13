# Ward support communications

Account permissions and ward responsibilities are separate.

- Admin provisions the fixed clinical roles plus PCA, Housekeeper, Catering, and Fire Marshal. Custom roles are rejected.
- Charge Nurse assigns the eight responsibilities for the selected ward, date, and day/night shift. In-charge nurse remains a separate responsibility, not an editing permission.
- In-charge nurse, team leader, duty leader, and discharge nurse are assigned to nursing accounts. The other duties use their matching support accounts; a Fire Marshal duty can also be held by an existing clinician.
- Other assigned ward clinicians view responsibilities and use Call or Message. Support accounts cannot open the clinical ward board, patient records, medical issues, or clinical sync endpoints.
- Support accounts open the shared Messages & calls dashboard. Direct conversations are visible only to their participants. Direct calls carry no patient or medical-issue identifiers.

## Try it on Android

1. Restart the backend to load the new endpoints and create the additive communications tables. Existing wards and bed allocations are retained.
2. Relaunch the updated app. As Admin, provision a support account with a fixed role.
3. As Charge Nurse, confirm a ward and shift, open the ward board, and assign a provisioned person under Ward Responsibilities.
4. As an assigned ward clinician, tap that person and choose Message or Call. There should be no responsibility-edit action.
5. Sign in on a second device as the support account. Only Messages & calls should appear. Reply to the conversation and test answering or declining a call.

Messages and calls refresh while their screens are open. Message retries use a stable identifier to avoid duplicate delivery. The thread currently shows its latest 200 messages; call history follows the existing call-store retention of 24 hours after a call finishes.

Calls require the backend's `LIVEKIT_URL`, `LIVEKIT_API_KEY`, and `LIVEKIT_API_SECRET`. Push delivery requires backend Firebase credentials and notification permission on the receiving device. Message notifications contain a generic alert, never the message body. Open Messages & calls to read the conversation.

Automated tests cover provisioning, nonclinical access denial, responsibility assignment, participant isolation, retry deduplication, and the Android-sized screens. Two-device audio and actual push delivery require device testing.
