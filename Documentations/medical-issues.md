# Medical Issues

Medical Issues are patient-linked, append-only clinical conversations. Internal
event identifiers retain the legacy `Loop` name for stored-event compatibility.

## Access and workflow

- The current ward board determines which patients are available.
- Patient issue data is available only to the assigned nurse(s), the board-listed
  doctor, and a Charge Nurse who has selected that ward.
- Opening an issue thread records a per-clinician read event. Acknowledgment is
  a separate per-clinician action.
- During a bed-by-bed SBAR handoff, every open issue transfers to the incoming
  nurse with its existing thread history. Critical issues still require
  individual verbal acceptance.
- Critical issues remain awaiting confirmation until the doctor assigned to the
  patient on the ward board confirms closure. If no doctor is assigned, a Charge
  Nurse sees a warning and confirmation is blocked.
- Closure requires a typed reason and an explicit `Resolved` or
  `Closed without resolution` outcome.
- An exact-title issue closed within the previous 24 hours prompts the clinician
  to reopen it or create a new linked issue.

## Push alert setup

The Messages & calls inbox includes received direct messages, authorised Medical
Issue updates, and incoming calls. Its badge counts unread messages/issue updates
and unseen missed calls, including zero. Read receipts are stored per account on
the backend and are independent of clinical acknowledgment and push delivery.
Reading a thread clears alerts only for events loaded on the device. Clinical
entries are filtered again against current access; support accounts never receive
patient issue entries. The foreground inbox refreshes every five seconds.

New messages preserve the author's role, verified by the backend, for role colours.
Older messages without a recorded role use the available patient staff roster;
unknown roles use a neutral colour instead of assuming the author is a nurse.

For local development, the backend loads `backend/.env` without overriding existing
environment variables. Set `GOOGLE_APPLICATION_CREDENTIALS` to the local path of
your Firebase Admin service-account JSON file and restart the backend. A Firebase
project ID alone is not sufficient to send alerts. Do not paste the private key
into source files or commit the credential file. The health flag reports credential
configuration presence, not a successful Firebase delivery test.

The client uses the shared `MedicalIssuePushService` for Firebase Messaging and
foreground local notifications. Firebase client configuration comes from the
generated `lib/firebase_options.dart` and the platform Firebase configuration.
Keep backend service-account credentials out of source control.

The backend needs Firebase Admin credentials through
`GOOGLE_APPLICATION_CREDENTIALS` (or workload identity) and
`FIREBASE_PROJECT_ID`. `FIREBASE_SERVICE_ACCOUNT_JSON` is also supported for
deployments that inject the service-account JSON from a secret manager. Keep
these values outside source control. The `/health` response reports whether
push configuration is present.

FCM delivery uses a durable event outbox with retry backoff and tracks delivery
per installation so a partial multi-device failure does not resend to devices
that already received the alert. Lock-screen
notifications use generic, non-identifying text; patient and issue identifiers
are only included in the notification data payload. The FCM project and platform
push credentials, including APNs configuration for Apple platforms, must be
configured before real-device delivery can be tested. The client registers its
Firebase Installation ID (FID) with the backend after sign-in and removes that
installation on sign-out. Older FCM-token registrations are discarded during
the backend migration and are refreshed when those devices sign in again.

Opening an alert requires a signed-in clinician and fetches only the requested
Medical Issue thread through the backend's authorization-checked endpoint. A
stale notification for an issue the clinician can no longer access will not
open the thread.
