# Digital Bank KYC & Account Onboarding Platform
**System Reference: Paytm / PhonePe / Jupiter style**

## Overview

This design covers the end-to-end KYC and account onboarding platform for a modern Indian digital bank / payments super-app serving 300M+ users. The system handles:

- Multi-tier KYC (Minimum, Full, Video, Re-KYC)
- 5 distinct account types with divergent compliance requirements
- ECA (Event-Condition-Action) workflow engine for lead tracking
- UIDAI / Aadhaar eKYC, biometric and OTP-based verification
- KRA / CKYC registry integration
- Fraud, blacklist, and criminal-record screening via external bureaus
- PII encryption, tokenization, and audit trail for DPDPA 2023 compliance

---

## Design Files Index

| File | Contents |
|------|----------|
| [01-requirements-and-estimation.md](01-requirements-and-estimation.md) | Functional + non-functional requirements, scale estimates, compliance matrix |
| [02-system-architecture.md](02-system-architecture.md) | Component diagram, service decomposition, data models, API contracts, data flow |
| [03-eca-workflow-engine.md](03-eca-workflow-engine.md) | ECA pattern internals, event taxonomy, condition evaluator, action executor, lead FSM |
| [04-account-onboarding-flows.md](04-account-onboarding-flows.md) | Per-account-type onboarding state machines, document matrix, upgrade paths |
| [05-compliance-fraud-security.md](05-compliance-fraud-security.md) | UIDAI/Aadhaar, KRA/CKYC, fraud scoring, blacklist screening, encryption strategy |
| [06-disaster-recovery.md](06-disaster-recovery.md) | RTO/RPO targets (RBI BCDR), multi-DC topology, per-component replication & failover (Kafka MM2, PostgreSQL Patroni, ES CCR, RabbitMQ Federation, Redis Sentinel), K8s cross-DC with ArgoCD, DR runbook, chaos testing |

---

## Key Design Decisions (TL;DR)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Workflow engine | ECA over pure BPMN | Decoupled event-driven; supports rule hot-reload without redeployment |
| KYC orchestration | Saga (choreography-first) | Avoids single orchestrator SPOF; each step independently retryable |
| Account factory | Strategy + Factory Method | Account type logic isolated; new types added without touching core |
| PII storage | Encrypted at-rest (AES-256) + tokenized in transit | Satisfies DPDPA 2023 and RBI data localisation |
| Aadhaar data | Never persist raw Aadhaar XML | UIDAI circular: retain only token + demographic hash |
| Fraud screening | Synchronous pre-account-creation | Block account creation before any funds flow |
| KRA/CKYC | Async deduplication post-onboarding | CKYC fetch < 200ms SLA; fallback to fresh KYC if registry miss |
| Re-KYC scheduling | Periodic + event-triggered | RBI mandates re-KYC on risk events + 2-year cycle for high-risk |
| DR topology | Active-Passive (Mumbai primary, Hyderabad warm standby) | No dual-write conflicts on KYC records; single audit trail for PMLA compliance |
| Kafka cross-DC | MirrorMaker 2 + Outbox pattern | MM2 ensures near-real-time replication; outbox eliminates in-flight message loss at failover |

---

## Regulatory Landscape (India)

| Regulation | Body | Key Obligations |
|------------|------|-----------------|
| RBI KYC Master Directions 2016 (updated 2023) | RBI | CDD, EDD, CKYC upload within 3 days |
| PMLA 2002 + Rules | FINTRAC/FIU-IND | SAR filing, CTR (>₹10L cash), record retention 5 years |
| Aadhaar Act 2016 | UIDAI | Consent-based eKYC only; no biometric storage by RE |
| IT Act 2000 / DPDPA 2023 | MeiTY | Explicit consent, right to erasure, data principal rights |
| PCI-DSS v4.0 | PCI SSC | Card-holder data encryption, network segmentation |
| FATF Recommendations | RBI adoption | Risk-based approach, PEP/sanctions screening |

---

## FAANG Interview Callout

> Interviewers at Google/Meta/Amazon will probe: "How does your ECA engine handle concurrent events on the same user?" and "Walk me through exactly what data you store after an Aadhaar eKYC response — and what you delete." Prepare both answers cold.
