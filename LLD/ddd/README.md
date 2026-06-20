# Domain-Driven Design (DDD) — Reference & Standards

This folder is the canonical reference for **Domain-Driven Design** applied to complex, production-grade systems. Every file here follows the approach described in Eric Evans' *Domain-Driven Design* (the Blue Book) and Vaughn Vernon's *Implementing Domain-Driven Design* (the Red Book), adapted to modern distributed systems.

---

## What DDD Is (and Is Not)

DDD is a **software design philosophy** that places the business domain at the center of every architectural decision. It is not a framework, library, or deployment pattern — it is a way of thinking and collaborating.

**DDD is valuable when:**
- The domain is complex (payment processing, healthcare, logistics, financial trading)
- Business rules change frequently and must be encoded without losing intent
- Multiple teams work on the same system and need clear ownership boundaries
- The model needs to survive more than one technology stack generation

**DDD is overkill when:**
- The problem is CRUD (create, read, update, delete) with thin business rules
- The team is small and the domain is well-understood and stable
- Speed of delivery outweighs long-term model integrity

---

## The Two Levels of DDD

### Strategic Design — "Where do we draw the lines?"

Strategic design establishes **bounded contexts**: the boundaries within which a particular domain model is consistent and valid. This is the most impactful part of DDD and the hardest to get right.

```
Subdomain Types:
  Core Domain     → where competitive advantage lives; invest the most here
  Supporting      → needed to support core, but not differentiating; can be bought/outsourced
  Generic         → commodity; buy or use open-source (auth, email, logging)

Bounded Context → the explicit boundary within which a model applies unambiguously
  One team owns one bounded context (Conway's Law alignment)
  One codebase per bounded context (physical boundary)
  One database schema per bounded context (data boundary)
```

**Context Map** — shows how bounded contexts relate to each other:
| Relationship | Meaning |
|---|---|
| Shared Kernel | Two contexts share a small, stable part of the model |
| Customer-Supplier | Downstream context depends on upstream; upstream prioritizes downstream's needs |
| Conformist | Downstream conforms to upstream's model with no influence |
| Anti-Corruption Layer (ACL) | Downstream protects itself from upstream's model via translation layer |
| Open Host Service | Upstream publishes a well-defined protocol for others to consume |
| Published Language | Shared, well-documented exchange format (JSON schema, Protobuf) |
| Separate Ways | Contexts are fully independent; no integration |

### Tactical Design — "How do we model inside a boundary?"

Tactical design provides **building blocks** for implementing a single bounded context:

| Building Block | Definition | Rule |
|---|---|---|
| **Value Object** | Describes a thing; identity by value; immutable | No ID; `equals()` based on all fields |
| **Entity** | Has a unique identity that persists over time | Has ID; `equals()` based on ID only |
| **Aggregate** | Cluster of entities/VOs treated as a single unit of consistency | One root entity; all access via root |
| **Aggregate Root** | The gateway to the aggregate; enforces all invariants | External objects hold only its reference |
| **Domain Event** | A record of something that happened in the domain | Immutable; past tense; carries enough data |
| **Repository** | Collection abstraction over persistence | Interface in domain; impl in infrastructure |
| **Domain Service** | Stateless operation that spans multiple aggregates | No state; named after domain verb |
| **Application Service** | Use case orchestrator; not business logic | Thin; delegates to domain objects |
| **Factory** | Creates complex aggregates | Enforces creation invariants |

---

## The Four Layers of DDD Architecture

```
┌────────────────────────────────────────────────────────────────┐
│  API Layer (Interfaces)                                        │
│  REST controllers, GraphQL resolvers, gRPC handlers            │
│  → Translates HTTP/gRPC to commands/queries                    │
├────────────────────────────────────────────────────────────────┤
│  Application Layer                                             │
│  Command handlers, Query handlers, Application services        │
│  → Orchestrates domain objects; owns transactions              │
├────────────────────────────────────────────────────────────────┤
│  Domain Layer                       ← The Heart               │
│  Aggregates, Entities, Value Objects, Domain Events            │
│  Domain Services, Repositories (interfaces only)              │
│  → Pure business logic; zero infrastructure dependencies       │
├────────────────────────────────────────────────────────────────┤
│  Infrastructure Layer                                          │
│  Repository implementations (JPA, DynamoDB, Redis)            │
│  Event publishers (Kafka, SNS), External API clients (ACLs)   │
│  → All I/O; implements domain interfaces                       │
└────────────────────────────────────────────────────────────────┘

Dependency Rule: each layer depends only on layers below it.
The Domain Layer has ZERO dependencies on any other layer.
```

---

## Key Design Decisions in This Repo

### Aggregate Size — Small Aggregates

**Rule:** Aggregates should be as small as possible — ideally 1-3 entities. Large aggregates cause:
- Contention (every change locks the whole aggregate)
- Performance issues (loading 500 line-items to change the order header)
- Merge conflicts

**Reference between aggregates by ID only** (never by object reference):
```java
// Wrong — creates tight coupling between aggregates
public class Order {
    private Customer customer;    // ← never hold a reference to another aggregate
}

// Right — reference by identity
public class Order {
    private CustomerId customerId; // ← hold the ID; load separately when needed
}
```

### Domain Events — the Integration Glue

Domain events decouple bounded contexts without creating direct dependencies:
```
Payment Aggregate emits PaymentCompleted (domain event)
  → published to event bus
  → Notification Context reacts: sends SMS
  → Ledger Context reacts: records transaction
  → Fraud Context reacts: updates user risk profile
```

Payment doesn't know Notification, Ledger, or Fraud exist. They subscribe to the event.

### Repository Pattern — Persistence Ignorance

Domain objects must not know how they are stored:
```java
// Domain layer — interface only
public interface PaymentRepository {
    void save(Payment payment);
    Optional<Payment> findById(PaymentId id);
    Optional<Payment> findByReferenceId(PaymentReferenceId referenceId);
}

// Infrastructure layer — JPA implementation
public class JpaPaymentRepository implements PaymentRepository {
    // JPA annotations, entity managers — all here, none in domain
}
```

---

## Example Application in This Folder

**[Payment Platform (Paytm/Google Pay style)](payment-platform/README.md)** — a production-grade payment system covering:
- UPI (Unified Payments Interface)
- Card payments (credit/debit)
- Utility bill payments (BBPS)
- Wallet money management

Files in order:
1. [Strategic Design](payment-platform/01-strategic-design.md) — bounded contexts, context map, subdomain analysis
2. [Ubiquitous Language](payment-platform/02-ubiquitous-language.md) — domain glossary per bounded context
3. [Payment Domain](payment-platform/03-payment-domain.md) — Payment BC: full Java aggregate code
4. [Wallet Domain](payment-platform/04-wallet-domain.md) — Wallet BC: full Java aggregate code
5. [Bill Payment Domain](payment-platform/05-bill-payment-domain.md) — Bill Payment BC: full code
6. [Application Layer](payment-platform/06-application-layer.md) — CQRS, command/query handlers
7. [Saga Patterns](payment-platform/07-saga-patterns.md) — distributed transactions across contexts
8. [Infrastructure Layer](payment-platform/08-infrastructure-layer.md) — repositories, ACLs, event bus
9. [Production Patterns](payment-platform/09-production-patterns.md) — idempotency, outbox, monitoring

---

## FAANG Interview Application

When asked "Design Paytm / Google Pay / a payment system" at principal engineer level, DDD gives you a structured answer:

1. **Identify bounded contexts** (5 min) — show strategic thinking
2. **Pick the core domain aggregate** (5 min) — Payment aggregate, invariants
3. **Show data model driven by domain** (5 min) — not DB-first, domain-first
4. **Describe event-driven integration** (5 min) — domain events between BCs
5. **Discuss consistency trade-offs** (5 min) — eventual consistency across BCs, why it's acceptable

This is the difference between a senior engineer answer ("we'll have a payments table") and a principal engineer answer ("we'll draw a boundary here because the payment lifecycle has different consistency requirements than the notification lifecycle").
