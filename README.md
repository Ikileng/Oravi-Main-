# ORAVI — Enterprise Clinical Operating System

> **Zero Preventable Medical Communication Errors**  
> An enterprise-grade clinical operating system engineered to bridge communication gaps during shift handoffs, transitions of care, and interdisciplinary coordination across hospital departments.

---

## 🏗️ Architecture & Environments

This repository maintains a single unified codebase supporting three strictly isolated environments:

| Environment | Purpose | Target / Data Isolation |
| :--- | :--- | :--- |
| **Development (`dev`)** | Daily feature development, rapid iteration, local emulators, and unit/integration testing. | Synthetic / Mock test data only. |
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
