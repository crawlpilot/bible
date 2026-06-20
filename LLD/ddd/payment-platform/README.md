# Payment Platform — DDD Implementation

**System:** Paytm / Google Pay style mobile payment application  
**Scale target:** 100M users, 10M transactions/day (~115 TPS average, 2,000 TPS peak)  
**Payments supported:** UPI, Credit/Debit Card, Utility Bills (BBPS), Wallet  
**Regulatory context:** India (RBI, NPCI, PCI-DSS)

---

## System Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                     Mobile App / Web App                         │
└──────────────────┬───────────────────────────────────────────────┘
                   │ HTTPS
┌──────────────────▼───────────────────────────────────────────────┐
│              API Gateway + Auth (JWT/OAuth2)                      │
└──────┬────────────┬────────────────┬─────────────────────────────┘
       │            │                │
┌──────▼──────┐ ┌───▼───────┐ ┌─────▼──────────┐ ┌──────────────┐
│  Payment    │ │  Wallet   │ │  Bill Payment  │ │  Identity &  │
│  Service   │ │  Service  │ │  Service       │ │  KYC Service │
│  (BC)      │ │  (BC)     │ │  (BC)          │ │  (BC)        │
└──────┬──────┘ └───┬───────┘ └─────┬──────────┘ └──────────────┘
       │            │                │
       └────────────┴────────────────┘
                    │ Domain Events
              ┌─────▼──────┐
              │ Event Bus  │ (Kafka)
              └─────┬──────┘
       ┌─────────────┼──────────────┐
┌──────▼──────┐ ┌────▼──────┐ ┌────▼────────────┐
│Notification │ │  Fraud    │ │  Ledger /       │
│  Service   │ │  Service  │ │  Audit Service  │
│  (BC)      │ │  (BC)     │ │  (BC)           │
└─────────────┘ └───────────┘ └─────────────────┘
                                        │
                              External Systems
               ┌──────────────┬─────────┴───────────┐
        ┌──────▼──────┐ ┌─────▼──────┐ ┌────────────▼──────┐
        │  NPCI/UPI   │ │  Bank/Card │ │  BBPS (Bharat     │
        │  Network    │ │  Networks  │ │  Bill Pay System) │
        └─────────────┘ └────────────┘ └───────────────────┘
```

---

## Bounded Context Summary

| Bounded Context | Subdomain Type | Owns | Key Invariant |
|---|---|---|---|
| **Payment** | Core Domain | Payment lifecycle | A payment is final once COMPLETED; cannot be modified |
| **Wallet** | Core Domain | User balance | Balance can never go below 0; KYC limits enforced |
| **Bill Payment** | Supporting | Bill orders | Fetch before pay; pay only once per bill reference |
| **Identity & KYC** | Supporting | User identity | KYC level gates transaction limits |
| **Notification** | Generic | Alerts, receipts | Best-effort; eventual; no payment logic |
| **Fraud Detection** | Supporting | Risk scores | Pre-payment gate; does not own payment state |
| **Ledger & Audit** | Generic | Transaction records | Append-only; immutable |

---

## Technology Choices & Rationale

| Concern | Choice | Why |
|---|---|---|
| **Language** | Java 17 | Records (value objects), sealed classes, strong typing for financial math |
| **Framework** | Spring Boot 3.x | Mature ecosystem; not in domain layer |
| **Database** | PostgreSQL per BC | ACID guarantees; row-level locking for aggregate consistency |
| **Event Bus** | Apache Kafka | Ordered, durable, replayable; mandatory for payment audit trail |
| **Cache** | Redis | Session tokens, idempotency keys, rate limiting |
| **ID Generation** | UUID v7 (time-ordered) | Globally unique + index-friendly (sequential) |
| **Money** | `BigDecimal` + Currency code | Never `double`/`float` for money — floating point rounding causes real financial loss |
| **Crypto** | AWS KMS | Card data encryption; never store raw card numbers |

### Why PostgreSQL and Not DynamoDB for Payment Domain?
Payment aggregates require **multi-field consistency** (status, amount, timestamps, settlement ID must be consistent in a single transaction). DynamoDB transactions are limited to 100 items and cost 2× WCUs. PostgreSQL row-level locking on a single payment row is simpler and cheaper at this scale. DynamoDB wins for the Wallet context where key-based access patterns dominate.

---

## File Navigation

| File | What you learn |
|------|---------------|
| [01-strategic-design.md](01-strategic-design.md) | Where the boundaries are and *why* |
| [02-ubiquitous-language.md](02-ubiquitous-language.md) | Exact domain vocabulary per BC |
| [03-payment-domain.md](03-payment-domain.md) | Full Java aggregate: Payment, UPI, Card — all value objects, entities, events |
| [04-wallet-domain.md](04-wallet-domain.md) | Full Java aggregate: Wallet, balance management, KYC limits |
| [05-bill-payment-domain.md](05-bill-payment-domain.md) | Bill Payment aggregate: BBPS integration, idempotency |
| [06-application-layer.md](06-application-layer.md) | CQRS: commands, queries, application services |
| [07-saga-patterns.md](07-saga-patterns.md) | UPI saga (choreography), wallet top-up saga (orchestration) |
| [08-infrastructure-layer.md](08-infrastructure-layer.md) | JPA repositories, ACLs for NPCI/BBPS/Bank, Kafka publisher |
| [09-production-patterns.md](09-production-patterns.md) | Idempotency, outbox, optimistic locking, observability |
