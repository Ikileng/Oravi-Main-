# ORAVI — Enterprise Clinical Operating System

> **Zero Preventable Medical Communication Errors**  
> An enterprise-grade clinical operating system engineered to bridge communication gaps during shift handoffs, transitions of care, and interdisciplinary coordination across hospital departments.

---

## 🏗️ Architecture & Environments

This repository maintains a single unified codebase supporting three strictly isolated environments:

| Environment | Purpose | Target / Data Isolation |
| :--- | :--- | :--- |
| **Development (`dev`)** | Daily feature development, rapid iteration, local emulators, and unit/integration testing. | Runtime starts without demo records; synthetic fixtures are isolated to automated tests. |
| **Staging (`staging`)** | Pre-production testing, QA validation, hospital stakeholder UAT, and SMART on FHIR sandboxes. | Production-replica architecture with synthetic hospital data. |
| **Production (`prod`)** | Live hospital deployment, operational workflows, and active clinical handoffs. | Live Protected Health Information (PHI), hardened security rules, and immutable audit logging. |

---

## 🌿 Git Branching Strategy

* `main` — Production-ready releases.
* `staging` — Pre-release validation & UAT builds.
* `develop` — Active development branch; feature branches (`feature/*`) merge here via Pull Request.

---

## 📚 Documentation

The technical architecture specification and Product Requirement Document (PRD) will define the exact build roadmap and feature boundaries.

## Mobile security status

- The app and backend do not seed runtime staff, ward, patient, or board data, and sign-in does not fall back to demo PINs. Automated tests use isolated synthetic fixtures.
- Provision the first administrator with `python -m backend.bootstrap_admin`, then configure wards with `python -m backend.configure_wards`. The Dev Admin provisions staff identities, roles, and PINs; Charge Nurses publish the shift board that determines ward and patient access.
- A staff dashboard with no active board assignment shows a no-ward message; a configured ward without board patients shows a separate no-patients message.
- Release builds require `ORAVI_API_BASE_URL` to point to an HTTPS service and fail closed if it is unavailable. The backend implementation is included, but a hosted production service, hospital identity provisioning, and deployment security review remain outstanding.
- The on-device event database uses SQLite3MultipleCiphers encryption. Its random key is held in Android Keystore or Apple Keychain. Existing plaintext databases are converted before startup, with a temporary recovery copy removed after conversion.
- Sync sends events only with a server-issued bearer token, retries missing acknowledgements, and recovers uploads interrupted by an app restart.

These protections harden the mobile client. They do not replace backend authorization, hospital identity provisioning, security review, or clinical validation.
