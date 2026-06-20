# Context Map Patterns

## Overview
A Context Map documents the relationships between Bounded Contexts. It is not just a diagram — it is an explicit record of:
- Which direction information flows
- Who has power over the contract (upstream vs downstream)
- How much the downstream adapts to the upstream
- Where translation layers are needed
- Where integration should be avoided entirely

Eric Evans defined the original Context Map patterns; the community has standardised 9 canonical relationships. Every real-world integration between two Bounded Contexts (or between your system and a legacy/external system) falls into one of these categories.

**Why this matters for principal engineers**: the Context Map makes invisible team and system dependencies explicit. Without it, teams integrate implicitly and incorrectly. With it, you can reason about the change blast radius of any modification.

---

## The 9 Context Mapping Patterns

### 1. Partnership
**Relationship**: Two Bounded Contexts co-evolve together. Both teams commit to keeping their interfaces in sync.

```
Context A  ◄──────────────────►  Context B
         (both teams coordinate)
```

**When to use**: Two teams with truly shared goals, equal power, and high communication bandwidth. Rare in practice.

**Risks**:
- High coordination overhead: every change requires both teams to agree and deploy together
- Breaks down when teams grow, are reorganised, or develop conflicting priorities
- Can drift into an undocumented shared kernel

**AWS/cloud implementation**: Blue/green deployments of both services must be coordinated. Feature flags to synchronise releases. Shared API contract tested via consumer-driven contract tests (Pact).

---

### 2. Shared Kernel
**Relationship**: Two Bounded Contexts share a small, explicitly defined subset of the domain model. The shared code is jointly owned and cannot be changed unilaterally.

```
Context A                    Context B
┌──────────┐                ┌──────────┐
│          │                │          │
│  ┌────┐  │                │  ┌────┐  │
│  │ SK │  │◄──── joint ───►│  │ SK │  │
│  └────┘  │    ownership   │  └────┘  │
│          │                │          │
└──────────┘                └──────────┘
```

**When to use**: Two contexts that genuinely share core domain concepts (e.g., a `Money` value object or `CustomerId` type shared between Orders and Payments).

**Risks**:
- The shared kernel becomes a hidden coupling point
- Changes require coordination and versioning — it becomes a mini-platform
- Teams resist changing shared code because of fear of breaking the other

**Implementation**: shared library published to internal package registry (npm, PyPI private index, Maven). Semantic versioning required. Both teams must approve changes.

**Anti-pattern**: sharing application services, repositories, or infrastructure code as a "shared kernel." Only share pure domain model types with no infrastructure dependencies.

---

### 3. Customer-Supplier
**Relationship**: An upstream context (Supplier) produces data/API; a downstream context (Customer) consumes it. The upstream team has power — they define the contract. The downstream adapts to it.

```
Upstream (Supplier)              Downstream (Customer)
┌──────────────────┐             ┌──────────────────┐
│                  │             │                  │
│  Payments        │ ──────────► │  Reporting       │
│                  │   events    │                  │
└──────────────────┘             └──────────────────┘
      (defines)                       (adapts)
```

**When to use**: Clear producer-consumer relationship where the upstream team is willing to take downstream needs into account when planning changes.

**Key rule**: the upstream team should involve downstream consumers in planning API/schema changes. Consumer-Driven Contract Testing (Pact) formalises this.

**AWS implementation**:
- Upstream publishes events to SNS/Kafka/EventBridge
- Downstream subscribes; upstream maintains backward compatibility in the event schema
- Schema Registry (Glue/Confluent) enforces the schema contract

---

### 4. Conformist
**Relationship**: The downstream context accepts the upstream's model as-is, with no translation. The downstream conforms to the upstream's language and structure.

```
Upstream (Legacy ERP)            Downstream (New Service)
┌──────────────────┐             ┌──────────────────┐
│                  │             │                  │
│  SAP             │ ──────────► │  Invoicing       │
│                  │   accepts   │  (uses SAP's     │
└──────────────────┘             │   vocabulary)    │
                                 └──────────────────┘
```

**When to use**: When the upstream is large/powerful (SaaS platform, legacy ERP) and will not change its model for you. Conforming is cheaper than building an ACL.

**Risk**: the downstream's model becomes polluted by the upstream's concerns. This is a deliberate trade-off when translation cost exceeds pollution cost.

**AWS implementation**: DMS or Glue pulls from legacy system; consuming service uses the upstream's field names and data structures directly.

---

### 5. Anti-Corruption Layer (ACL) ⭐ Most Important
**Relationship**: The downstream context builds a translation layer that converts the upstream's model into the downstream's own model. The downstream is protected from the upstream's concepts.

```
Upstream (Legacy / External)     ACL          Downstream (New System)
┌──────────────────┐         ┌────────┐      ┌──────────────────┐
│                  │         │        │      │                  │
│  Legacy CRM      │ ──────► │Adapter │ ──►  │  Sales Context   │
│  (AccountId,     │         │        │      │  (CustomerId,    │
│   ContractRef)   │         └────────┘      │   DealId)        │
│                  │         translates      │                  │
└──────────────────┘                         └──────────────────┘
```

**When to use**:
- Integrating with a legacy system that has a model you don't want to pollute your domain with
- Integrating with a third-party API (Salesforce, SAP, external partner)
- When the upstream's language is very different from your Bounded Context's language
- As a strangler fig facade pattern: the ACL sits in front of the monolith during migration

**Python implementation**:
```python
# The legacy CRM uses "AccountId" and "ContractRef"
# Our Sales domain uses "CustomerId" and "DealId"

class CRMClient:
    """Raw client for legacy CRM — speaks CRM language"""
    def get_account(self, account_id: str) -> dict:
        return self._http.get(f"/accounts/{account_id}")

class CRMAntiCorruptionLayer:
    """Translates legacy CRM model into our Sales domain model"""
    
    def __init__(self, crm_client: CRMClient):
        self._crm = crm_client
    
    def get_customer(self, customer_id: CustomerId) -> Customer:
        raw = self._crm.get_account(str(customer_id.value))
        return Customer(
            id=CustomerId(raw["accountId"]),
            name=CustomerName(raw["displayName"]),
            tier=self._map_tier(raw["contractLevel"])
        )
    
    def _map_tier(self, contract_level: str) -> CustomerTier:
        mapping = {"GOLD": CustomerTier.ENTERPRISE, "SILVER": CustomerTier.GROWTH}
        return mapping.get(contract_level, CustomerTier.STANDARD)
```

**AWS API Gateway as ACL**: API Gateway request/response mapping templates can translate an external API's schema to your domain's schema at the infrastructure level — no code required for simple transformations.

**Critical rule**: the ACL is part of the *downstream* context, not a standalone service. It is infrastructure for the downstream context.

---

### 6. Open Host Service (OHS)
**Relationship**: The upstream context offers a well-defined, stable, versioned service protocol that any downstream can consume without coordination. The upstream publishes and maintains the contract.

```
Upstream (Open Host Service)
┌──────────────────────────────────────┐
│                                      │
│  Payments Service                    │
│  Published API: /v2/payments/{id}    │
│  Published Events: PaymentCompleted  │
│                                      │
└──────────────────────────────────────┘
    │            │            │
    ▼            ▼            ▼
Reporting    Accounting   Notifications
(consumer)   (consumer)   (consumer)
```

**When to use**: When your Bounded Context is consumed by many other contexts. Rather than tailoring integration for each consumer, you publish a stable, versioned open protocol.

**AWS implementation**: API Gateway REST API with versioning (`/v1/`, `/v2/`); OpenAPI spec published to internal developer portal; event schema versioned in Glue Schema Registry.

---

### 7. Published Language
**Relationship**: A well-documented shared information exchange language is established between contexts. All communication uses this language.

**Relationship to OHS**: Often combined with OHS. OHS defines the *service protocol*; Published Language defines the *schema and vocabulary*.

**Modern implementations**:
- **CloudEvents spec** as the envelope for all domain events
- **Avro/Protobuf schema** registered in schema registry (Confluent / AWS Glue)
- **OpenAPI spec** as the Published Language for REST APIs
- **AsyncAPI spec** as the Published Language for event-driven APIs

```json
// CloudEvents as Published Language
{
  "specversion": "1.0",
  "type": "com.acme.payments.payment.completed",
  "source": "/payments-service",
  "id": "A234-1234-1234",
  "time": "2024-01-15T17:31:00Z",
  "datacontenttype": "application/json",
  "data": {
    "paymentId": "pay_123",
    "amount": {"value": 5000, "currency": "USD"},
    "orderId": "ord_456"
  }
}
```

Schema evolution rules: add optional fields (backward compatible); never rename or remove fields; bump major version for breaking changes.

---

### 8. Separate Ways
**Relationship**: Two Bounded Contexts have no integration at all. Each solves its problem independently, even if that means duplicating data or effort.

**When to use**:
- Integration cost exceeds benefit
- The two contexts genuinely serve different purposes with no shared data need
- Accepting data duplication is preferable to coupling

**Example**: a Customer Support context and a Warehouse Management context may both have a "product name" — but coupling them to share a single source of truth creates a dependency that doesn't justify its maintenance cost.

**AWS implementation**: no shared queues, no shared databases, no API calls between contexts. If both contexts need "product name," each maintains its own copy, updated via separate events from the Product Catalogue context.

---

### 9. Big Ball of Mud (Anti-Pattern)
**What it is**: No explicit Bounded Context boundaries. All teams access all models. Language is inconsistent. Everything depends on everything.

**How to recognise it**:
- Shared database accessed by 10+ services
- One model called `Order` that means different things in different parts of the code
- "We can't change this table because we don't know who uses it"
- Every deployment requires coordinating multiple teams
- Impossible to understand what a given data field means without reading 3 services' code

**How to escape it**: [Strangler Fig migration pattern](../../CloudArchitecture/patterns/strangler-fig.md) + [Context Map](03-context-map-patterns.md) to identify seams + [Anti-Corruption Layer](03-context-map-patterns.md) to isolate new contexts from the mud.

---

## Pattern Selection Decision Guide

```
Integrating with a third-party / legacy system with a bad model?
→ Anti-Corruption Layer (protect your model)

Your context is consumed by many others?
→ Open Host Service + Published Language (stable contract)

Two teams with shared goals and high bandwidth?
→ Partnership (temporary) or Shared Kernel (small, stable subset only)

One team clearly produces, another clearly consumes?
→ Customer-Supplier (consumer-driven contracts)

The upstream is powerful and won't change for you?
→ Conformist (if model pollution acceptable)
   OR Anti-Corruption Layer (if model purity required)

No valuable integration possible?
→ Separate Ways
```

---

## Context Map Trade-offs

| Pattern | Upstream flexibility | Downstream autonomy | Coupling | Coordination cost |
|---|---|---|---|---|
| Partnership | Low — must coordinate | Low | Very high | Very high |
| Shared Kernel | Low — joint ownership | Low | High | High |
| Customer-Supplier | Medium | Medium | Medium | Medium |
| Conformist | None — accepts as-is | None | Low (no translation) | Low |
| ACL | None needed | High (full translation) | Low | Low (ACL absorbs change) |
| Open Host Service | Medium (versioned) | High | Low | Low |
| Separate Ways | Full | Full | None | None |

**Default recommendation**: ACL for external/legacy integrations. Customer-Supplier with consumer-driven contracts for internal service integrations. OHS + Published Language when your context is a platform consumed by many.

---

## Best Practices

1. **Draw the Context Map explicitly** — it is a team and architectural decision; don't leave it implicit
2. **Default to ACL** for integrations with systems you don't control; protect your model from external vocabulary
3. **Consumer-driven contract tests** (Pact) for Customer-Supplier relationships — the downstream specifies what it needs; the upstream proves it still satisfies those needs in CI
4. **Version the Published Language** — never break consumers without a deprecation period
5. **Prefer Separate Ways** over a too-thin integration — a shared queue with one field is still a coupling point that requires coordination
6. **Update the Context Map when team structures change** — Conway's Law: team boundaries and context boundaries drift toward alignment

---

## FAANG Interview Points

**"How do you integrate a new microservice with an existing legacy monolith without polluting the new service's model?"**: Anti-Corruption Layer. The ACL is a translation adapter owned by the new service. It converts the legacy system's data model and vocabulary into the new service's domain model. The new service's code never imports or references legacy model types. When the legacy system changes, only the ACL changes — the domain model is protected.

**"How do you expose your service's data to many other teams without creating tight coupling?"**: Open Host Service with a Published Language. Define a versioned, documented API (OpenAPI for REST, AsyncAPI for events, Avro/Protobuf schema registry for Kafka). Version the API (`/v1/`, `/v2/`). Any consumer can integrate independently. When you need to make a breaking change, publish v2 alongside v1, give consumers a deprecation window (typically 3–6 months), then retire v1.

**"What does a Context Map tell you that a service dependency diagram doesn't?"**: A dependency diagram shows what calls what. A Context Map shows the *team relationship* (who has power to change the contract), the *model translation approach* (ACL, conformist, no translation), and the *integration pattern* (event-based, API, shared kernel). It tells you the change blast radius: if the upstream changes, who is affected and how severely?
