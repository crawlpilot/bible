# Implementing Domain-Driven Design
**Author**: Vaughn Vernon  
**Edition**: Addison-Wesley, 2013 (the "Red Book")  
**Category**: Software Architecture · Domain Modeling · Distributed Systems · Microservices

> "The goal of DDD is not to design classes and methods. It is to build a shared model of the business that developers and domain experts can use together to solve business problems."

---

## Why This Book Matters for FAANG PE Interviews

At principal/staff level, FAANG design interviews test whether you can decompose a complex problem into **the right service boundaries** — not just draw boxes. Vernon's book is the definitive practical guide to doing that, building on Evans' "Blue Book" with actual production patterns.

**Direct interview mapping**:
- Bounded contexts → "How would you decompose Uber into microservices?"
- Aggregate design → "How do you prevent double-spend in a payment system?"
- Domain events → "How do you keep three microservices consistent without 2PC?"
- Anti-Corruption Layers → "How do you migrate from a monolith without a big-bang rewrite?"
- Context maps → "How do teams coordinate at Amazon's scale?"

This is the difference between a senior answer ("I'd split this into microservices") and a principal answer ("here's the bounded context boundary, here's why the Order aggregate owns only these invariants, and here's how the downstream inventory context stays consistent via domain events").

---

## TL;DR — 3 Ideas to Internalize

1. **Bounded Context is the unit of ownership**: every service, team, and database schema boundary should align with a bounded context. Conway's Law is a DDD theorem, not a coincidence.
2. **Aggregates are the unit of consistency, not the unit of data**: design aggregates around the invariants they must protect, not the joins they enable. Small aggregates are almost always right.
3. **Domain events are the decoupling mechanism**: when two bounded contexts need to stay in sync, publish an event — never share a table, never make a synchronous call into another team's domain.

---

## Section A — Strategic Design: Drawing the Right Lines

Strategic design is Vernon's most important contribution. Getting bounded context boundaries wrong at the start is the root cause of most microservice failures.

### The Subdomain Taxonomy

Before writing a single class, answer: *what kind of problem is this part of the domain?*

| Subdomain Type | Definition | Investment Level | Examples |
|---|---|---|---|
| **Core Domain** | Where the company's competitive advantage lives; unique to the business | Maximum — hire the best engineers, apply full DDD | Google's ranking algorithm, Amazon's fulfillment routing, Stripe's fraud model |
| **Supporting Subdomain** | Necessary infrastructure that supports the core but is not differentiating | Medium — bespoke if core logic is complex, otherwise outsource | Merchant onboarding at Stripe, seller analytics at Amazon |
| **Generic Subdomain** | Commodity capability every company needs | Minimal — buy, open-source, or SaaS | Auth (Okta), email (SendGrid), logging (Datadog), payments (Stripe) |

**FAANG application**: In an Uber design, the **routing/matching algorithm** is the core domain (the entire company depends on it being optimal). **Driver payments** are a supporting subdomain. **Email notifications** and **authentication** are generic subdomains. Allocating principal engineering time to generic subdomains is an organizational anti-pattern.

### Bounded Context

A **bounded context** is an explicit boundary within which a particular domain model applies consistently and without ambiguity. Every term in the ubiquitous language has one — and only one — meaning within a bounded context.

```
Single concept, multiple meanings (without bounded contexts):
  "Account" in Banking Core    → has balance, transactions, interest rate
  "Account" in Customer Profile → has name, address, preferences, communication history
  "Account" in IAM             → has credentials, roles, permissions, last login

→ Three different models of "Account". One shared Account class will serve none of them well.
  The solution is three bounded contexts, each with its own Account model.
```

**Physical boundaries** (a bounded context should have all of):
- Its own codebase (repository)
- Its own database schema (no cross-context joins)
- Its own deployment unit (service or module boundary)
- One team owns it end-to-end (Conway's Law alignment)

### Context Map — How Bounded Contexts Relate

The context map is the architecture diagram of your strategic design. Every team-to-team integration has a pattern:

| Relationship Pattern | Who Has Power | When to Use | Real-World Example |
|---|---|---|---|
| **Partnership** | Both teams co-evolve | Two BCs must succeed or fail together; teams are close | Checkout and Inventory at Amazon during launch |
| **Shared Kernel** | Both teams must agree on changes | Two BCs share a small, critical, stable model | Order ID format shared between Order and Fulfillment |
| **Customer-Supplier** | Upstream (supplier) serves downstream (customer) | Clear dependency; upstream respects downstream needs | Platform team (supplier) → product team (customer) |
| **Conformist** | Upstream dictates; downstream conforms | Upstream is external/large; downstream can't negotiate | Payment processor API, Stripe, or AWS SDK |
| **Anti-Corruption Layer (ACL)** | Downstream protects itself | Upstream model is complex/legacy; downstream wants isolation | Wrapping a legacy ERP or third-party API |
| **Open Host Service (OHS)** | Upstream controls the protocol | Upstream serves many consumers; needs a stable interface | REST API, gRPC service contract |
| **Published Language** | Both teams agree on the schema | Shared event schema between contexts | Protobuf/Avro schema for Kafka events |
| **Separate Ways** | Independent | Integration cost exceeds benefit | Two independent business units with no data sharing |

**FAANG interview frame**: "At Google's scale, the relationship between the Search Index context and the Ads context is a Customer-Supplier pattern where Ads is the customer — they need the search result context but can't modify it. They'd build an Anti-Corruption Layer to translate the search ranking signals into their own ad ranking model."

### Big Ball of Mud

Vernon is explicit: the most common context map in real companies is the **Big Ball of Mud** — no boundaries, everything depends on everything else, multiple conflicting models for the same concept. Recognizing and naming this pattern is itself valuable in interviews: "This monolith has no bounded contexts — it's a Big Ball of Mud, and this is *why* adding the feature required touching 47 files."

---

## Section B — Ubiquitous Language

The ubiquitous language is not documentation. It is the shared vocabulary that developers and domain experts use in code, conversations, tests, and stories.

**The rules**:
1. Every term must have an unambiguous definition agreed on by both developers and domain experts
2. If the same term means different things to different people, a context boundary is missing
3. The code must reflect the language — class names, method names, variable names should match domain terms exactly
4. When the business says "authorize a payment", the code should say `payment.authorize()`, not `paymentService.updateStatus(AUTHORIZED)`

**Linguistic test for bounded context boundaries**: if a word means something different in two parts of the system, those two parts belong in different bounded contexts.

```
"Order" in e-commerce:
  Shopping Context:   Order = cart with intent to purchase; mutable; can be abandoned
  Fulfillment Context: Order = committed work item; triggers warehouse pick-pack-ship
  Accounting Context:  Order = revenue recognition event; triggers invoice, journal entries

→ Three bounded contexts. One "Order" class shared across all three is a time bomb.
```

---

## Section C — Tactical Design: Building Blocks

Tactical patterns are tools for implementing a single bounded context. Apply them only to the core domain — not to supporting or generic subdomains.

### Value Objects

A value object **describes** something. It has no identity — two value objects with the same attributes are identical.

**Rules**:
- Immutable: creation is the only mutation; produce a new VO to represent change
- Equality by value: `equals()` based on all attributes, not identity
- Self-validating: a VO that can be constructed is guaranteed to be valid
- Side-effect-free: methods return new values, they don't mutate state

```java
// Bad: primitive obsession — no domain semantics, no validation
public class Payment {
    private String currency;  // is "USD" valid? "US Dollar"? "usd"?
    private BigDecimal amount; // is -1 valid? is 0.000001 valid?
}

// Good: value objects carry domain rules
public final class Money {
    private final Currency currency;
    private final BigDecimal amount;

    public Money(Currency currency, BigDecimal amount) {
        if (amount.compareTo(BigDecimal.ZERO) < 0)
            throw new InvalidMoneyAmountException("Amount cannot be negative");
        this.currency = Objects.requireNonNull(currency);
        this.amount = amount.setScale(2, RoundingMode.HALF_UP);
    }

    public Money add(Money other) {
        if (!this.currency.equals(other.currency))
            throw new CurrencyMismatchException();
        return new Money(this.currency, this.amount.add(other.amount));
    }
}
```

**FAANG calibration**: At Stripe level, a `Money` value object prevents entire classes of bugs: currency mismatches, negative amounts, precision errors. The validation is in one place, enforced at construction, not scattered across services.

### Entities

An entity **is** something. It has a unique identity that persists over time. Two entities with the same attributes but different IDs are different objects.

**Rules**:
- Equality by identity: `equals()` based on ID only
- Identity must be assigned early and never change
- Prefer application-generated IDs (UUID) over database-generated IDs (auto-increment)
- An entity that loses its identity becomes a different entity

```java
// Application-generated UUID identity — no DB round-trip needed
public class Payment {
    private final PaymentId id;  // strongly-typed ID, not raw UUID or Long
    private PaymentStatus status;
    private Money amount;
    private CustomerId customerId;

    // Factory method enforces creation invariants
    public static Payment initiate(CustomerId customerId, Money amount) {
        return new Payment(PaymentId.generate(), customerId, amount, PaymentStatus.INITIATED);
    }

    // Behavior-rich: state transitions carry domain semantics
    public void authorize(AuthorizationCode code) {
        if (this.status != PaymentStatus.INITIATED)
            throw new InvalidPaymentStateTransitionException(this.status, PaymentStatus.AUTHORIZED);
        this.status = PaymentStatus.AUTHORIZED;
        // register domain event
    }
}
```

**Strongly-typed IDs**: Use `PaymentId`, `CustomerId`, `OrderId` (wrappers around UUID), never raw `UUID` or `Long`. This prevents a category of bugs where an OrderId is accidentally passed where a PaymentId is expected — caught at compile time.

### Aggregates — The Most Critical Tactical Pattern

An aggregate is a **cluster of domain objects** treated as a single unit of consistency. The aggregate root is the single entry point that enforces all invariants for the cluster.

**The four rules of aggregates** (Vernon's most cited contribution):

**Rule 1: Reference other aggregates by identity only**
```java
// Wrong — holds a reference to another aggregate
public class Order {
    private Customer customer;  // ← tight coupling; forces loading Customer to load Order
}

// Right — holds the ID; loads Customer only when needed
public class Order {
    private CustomerId customerId;  // ← loosely coupled; cross-context boundary is explicit
}
```

**Rule 2: Only the root can be accessed from outside**
```java
// Wrong — bypasses aggregate root's invariant enforcement
orderLineItemRepository.save(newLineItem); // ← directly mutating a child entity

// Right — all mutations go through the root
order.addLineItem(product, quantity);  // ← root enforces "max 50 line items" invariant
```

**Rule 3: Aggregates enforce transactional consistency boundaries**
- One aggregate = one database transaction
- Consistency across aggregates = eventual consistency via domain events
- If you find yourself updating two aggregates in one transaction, either the aggregate boundary is wrong, or you need a saga

**Rule 4: Design small aggregates**

| Large Aggregate | Small Aggregate |
|---|---|
| `Order` contains all `LineItem` objects in memory | `Order` has a count; `LineItem` references `OrderId` |
| Locks the entire order for any change | Fine-grained locking; concurrent updates to different line items |
| Loading 500 line items to update the shipping address | Loading only the header |
| Merge conflicts when two users edit simultaneously | Independent edits |

```
Example: Forum application
  Bad aggregate: Thread contains all Posts
    → Loading a thread with 10,000 posts to add a new post
    → Adding a post and moderating a post contend on the same lock

  Good aggregate: Thread (root: threadId, title, status, postCount — that's it)
                  Post (root: postId, threadId, content, authorId, postedAt)
    → Post references Thread by ID
    → Adding a post and moderating are independent operations
    → Thread.postCount is incremented via domain event, not direct mutation
```

### Domain Events

A domain event records something that **happened** in the domain. It is immutable, past-tense, and carries enough data for consumers to act without making additional calls.

```java
// Naming: past-tense, captures the exact business moment
public final class PaymentAuthorized {
    private final PaymentId paymentId;
    private final CustomerId customerId;
    private final Money amount;
    private final AuthorizationCode authorizationCode;
    private final Instant occurredOn;

    // No setters — domain events are immutable
}
```

**Why events over direct calls**:

| Direct Call (Synchronous) | Domain Event (Asynchronous) |
|---|---|
| Payment service calls Notification service | Payment publishes `PaymentCompleted`; Notification subscribes |
| Payment can't complete if Notification is down | Payment completes regardless of Notification state |
| Payment knows about Notification (coupling) | Payment knows nothing about Notification (decoupled) |
| Adding a new downstream requires changing Payment | New subscriber added with zero changes to Payment |
| Retry logic lives in Payment | Each consumer owns its own retry/error handling |

**Outbox Pattern** (production-grade event publishing):
```
Problem: how do you atomically commit a database write AND publish an event?
  Option A: Write DB → Publish event   → DB commit fails: inconsistency (event published, data not saved)
  Option B: Publish event → Write DB   → publish fails: inconsistency (data saved, event not published)
  Option C: Outbox pattern:
    1. Write domain state + event record to outbox table in the same DB transaction
    2. Relay process reads outbox, publishes to event bus, marks as published
    → Exactly-once write to DB; at-least-once publish to event bus; idempotent consumers handle duplicates
```

### Repositories

A repository is a **collection abstraction** over persistence. From the domain's perspective, a repository looks like an in-memory collection.

```java
// Domain layer — only the interface; zero infrastructure dependency
public interface OrderRepository {
    void save(Order order);
    Optional<Order> findById(OrderId id);
    List<Order> findByCustomerIdAndStatus(CustomerId id, OrderStatus status);
    void remove(Order order);
}

// Infrastructure layer — the actual persistence implementation
@Repository
public class JpaOrderRepository implements OrderRepository {
    // JPA, Hibernate, SQL — all contained here; none leaks into domain
}
```

**Repository vs DAO**:
- **DAO (Data Access Object)**: maps to a database table; exposes CRUD; infrastructure concern
- **Repository**: maps to an aggregate; exposes collection semantics; domain concept
- A repository can internally use multiple DAOs to reconstitute a complex aggregate

**One repository per aggregate root** — not one per entity, not one per table.

### Domain Services

A domain service encapsulates a **business operation that doesn't naturally belong to a single entity or value object**.

```java
// When the operation spans multiple aggregates:
// "Can this customer make this payment given their current account balance and risk profile?"
public class PaymentEligibilityService {
    public PaymentEligibility check(Customer customer, Account account, Money amount) {
        // logic that touches both Customer aggregate and Account aggregate
        // but belongs to neither
    }
}
```

**Domain Service vs Application Service**:

| | Domain Service | Application Service |
|---|---|---|
| **Contains** | Business logic | Orchestration logic |
| **Knows about** | Domain objects only | Repositories, domain services, event publishers |
| **Is stateless** | Yes | Yes |
| **Has infrastructure deps** | Never | Yes (repositories, message bus) |
| **Example** | `FundsTransferService.transfer()` | `TransferCommandHandler.handle()` |

### Application Services (Use Case Handlers)

The application service is the **use case boundary**. It is the first thing called after the API layer. It is thin — it orchestrates domain objects but contains no business logic itself.

```java
// Thin orchestration: no business rules, only workflow
public class InitiatePaymentCommandHandler {
    private final CustomerRepository customerRepository;
    private final PaymentRepository paymentRepository;
    private final DomainEventPublisher eventPublisher;

    @Transactional
    public PaymentId handle(InitiatePaymentCommand command) {
        Customer customer = customerRepository.findById(command.customerId())
            .orElseThrow(() -> new CustomerNotFoundException(command.customerId()));

        Payment payment = Payment.initiate(customer.id(), command.amount());

        paymentRepository.save(payment);
        eventPublisher.publishAll(payment.domainEvents());

        return payment.id();
    }
}
```

**The test tells you if your layer is right**: if a unit test of your application service requires mocking domain logic, the domain logic has leaked up. If a unit test of your domain object requires mocking a database, the infrastructure has leaked down.

### Factories

A factory creates **complex aggregates** whose construction requires multiple steps or enforces non-trivial invariants.

```java
// When creation requires complex invariant enforcement
public class OrderFactory {
    public Order createExpressOrder(CustomerId customerId, List<OrderItem> items, Address address) {
        if (items.isEmpty())
            throw new OrderCreationException("Cannot create order with no items");
        if (!address.isEligibleForExpress())
            throw new OrderCreationException("Address not eligible for express shipping");

        Order order = new Order(OrderId.generate(), customerId, OrderType.EXPRESS);
        items.forEach(item -> order.addLineItem(item.productId(), item.quantity(), item.price()));
        order.setShippingAddress(address);
        order.applyExpressShippingCost();
        return order;
    }
}
```

---

## Section D — Architecture: Ports and Adapters (Hexagonal Architecture)

Vernon advocates **Hexagonal Architecture** (Ports and Adapters) as the default architecture for a DDD bounded context. It is the blueprint that keeps the domain layer clean.

```
                    ┌───────────────────────────────┐
                    │         Primary Adapters       │
   REST Request ───▶│  REST Controller               │
    gRPC Request ──▶│  gRPC Handler                  │
   Message Broker ─▶│  Event Consumer                │
                    └────────────┬──────────────────┘
                                 │ Commands / Queries
                    ┌────────────▼──────────────────┐
                    │      Application Layer         │
                    │  Command Handlers              │
                    │  Query Handlers                │
                    └────────────┬──────────────────┘
                                 │
                    ┌────────────▼──────────────────┐
                    │        Domain Layer            │◀── The Hexagon
                    │  Aggregates, Entities, VOs     │
                    │  Domain Services, Events       │
                    │  Repository Interfaces         │
                    └────────────┬──────────────────┘
                                 │ Implements Ports
                    ┌────────────▼──────────────────┐
                    │      Secondary Adapters        │
                    │  JPA Repository                │
                    │  Kafka Publisher               │
                    │  HTTP Client (ACL)             │
                    └───────────────────────────────┘
```

**Ports**: interfaces defined in the domain layer (`OrderRepository`, `PaymentGateway`, `EventPublisher`)
**Adapters**: implementations of those interfaces in the infrastructure layer

**The Dependency Rule**: dependencies point inward only. The domain layer has zero imports from infrastructure. This is testable, replaceable, and technology-agnostic.

---

## Section E — Integrating Bounded Contexts

### Anti-Corruption Layer (ACL)

When your bounded context must integrate with an external system (legacy monolith, third-party API, another team's context with a different model), build an ACL to translate between models.

```java
// External Stripe API has its own model
// Your domain uses your own PaymentResult model
// The ACL translates between them

public class StripePaymentGatewayAdapter implements PaymentGateway {
    private final StripeClient stripeClient;

    @Override
    public PaymentResult charge(PaymentIntent intent) {
        // Translate from your domain model to Stripe's model
        StripeChargeRequest stripeRequest = toStripeRequest(intent);
        StripeChargeResponse response = stripeClient.charges().create(stripeRequest);
        // Translate Stripe's response back to your domain model
        return toPaymentResult(response);
    }
}
```

**Why ACL matters at scale**: Stripe changes its API. Your bounded context's model should not change because Stripe did. The ACL absorbs the change. This is Conway's Law in practice — the external team's decisions don't propagate into your architecture.

### Event-Driven Integration Between Bounded Contexts

The recommended integration pattern between bounded contexts at FAANG scale:

```
Payment BC (Publisher)                         Notification BC (Subscriber)
─────────────────────                          ────────────────────────────
Payment.authorize() succeeds
→ emits PaymentAuthorized event
→ Outbox Pattern saves to DB
→ Relay publishes to Kafka topic               ← consumes PaymentAuthorized
  "payment-events"                             → translates to NotificationBC model
                                               → sends SMS/push/email
                                               → idempotent (deduplicates by eventId)
```

**FAANG interview frame**: "Cross-context consistency at Amazon's scale uses eventual consistency via domain events — the Order context publishes an OrderPlaced event, and the Inventory, Fulfillment, and Accounting contexts independently consume it. There's no distributed transaction. If the Accounting context is down, orders still get placed; Accounting catches up when it recovers. This is the only architecture that scales to Amazon's throughput."

### CQRS — Command Query Responsibility Segregation

Vernon dedicates significant coverage to CQRS as a pattern that complements DDD naturally.

```
Command Side (Write)                         Query Side (Read)
────────────────────                         ─────────────────
 InitiatePaymentCommand                       PaymentSummaryQuery
       ↓                                             ↓
 Command Handler                              Query Handler
       ↓                                             ↓
 Payment Aggregate                            Denormalized Read Model
   (enforces invariants)                        (optimized for UI)
       ↓                                             ↑
 PaymentRepository (write)              PaymentReadModelRepository
       ↓                                             ↑
 Relational DB (normalized)             PaymentAuthorized event
                                            → updates read model
```

**When CQRS is justified**:
- Read and write models have fundamentally different shapes (normalized write, denormalized read)
- Read load is orders of magnitude larger than write load (separate scaling)
- The domain is complex enough to benefit from separating concern of "what happened" from "what to show"

**When CQRS is over-engineering**:
- Simple CRUD applications
- Single-team context with no read/write scaling difference
- Adding complexity before you've hit the scaling problem

---

## Section F — Event Sourcing

Vernon covers Event Sourcing as an advanced pattern that pairs naturally with DDD's domain events.

**Core idea**: instead of storing the current state of an aggregate, store the sequence of domain events that led to that state. The current state is derived by replaying events.

```
Traditional persistence:
  Database: { paymentId: "123", status: "COMPLETED", amount: 100.00 }
  → You know the state. You don't know how you got there.

Event-sourced persistence:
  Event store: [
    PaymentInitiated  { paymentId: "123", amount: 100.00, t: 09:00:00 }
    PaymentAuthorized { paymentId: "123", authCode: "XYZ",  t: 09:00:01 }
    PaymentCaptured   { paymentId: "123", capturedAt: ...,   t: 09:00:05 }
    PaymentCompleted  { paymentId: "123", completedAt: ...,  t: 09:00:05 }
  ]
  → You know every state AND the complete history.
```

**Trade-offs**:

| Benefit | Cost |
|---|---|
| Complete audit log — required in finance, healthcare | Query complexity: can't SELECT * WHERE status = 'ACTIVE' |
| Time-travel: replay to any point in history | Event schema evolution is hard; old events must still replay |
| Natural fit with domain events (they are the events) | Performance: replaying 10,000 events for each aggregate load |
| Easy to add new projections retroactively | Snapshot strategy needed for long-lived aggregates |
| Enables powerful debugging | Steep learning curve; unfamiliar to most engineers |

**When to use Event Sourcing**:
- Financial systems with audit requirements (banking, payments)
- Systems where history matters more than current state
- When you need the ability to replay and reprocess historical data
- Temporal queries: "what did the account look like on March 15th?"

**When NOT to use**:
- Most CRUD applications
- When your team is not already comfortable with DDD
- When query patterns require arbitrary reads over current state

---

## Section G — Distilled Key Principles (Interview Quick-Reference)

### The 10 Rules Vernon Would Give a Design Interview

1. **Start with the domain**, not the database. Draw the aggregate first; let the schema follow.
2. **Name things after what they mean**, not what they do technically. `OrderPlaced`, not `OrderStatusUpdate`.
3. **Make aggregates small**. If you're loading more than 3-5 objects to enforce an invariant, split the aggregate.
4. **Domain events are the preferred cross-context communication** — over direct synchronous calls in all but the most exceptional cases.
5. **Application services are thin**. If a method in your application service is more than 20 lines, business logic has leaked up.
6. **Never let infrastructure dependencies into the domain layer.** No JPA annotations on domain classes, no `@Autowired`, no `import jakarta.persistence.*`.
7. **One repository per aggregate root**, not one per entity or table.
8. **Use strongly-typed IDs** (`OrderId`, `CustomerId`) — not `Long` or raw `UUID`.
9. **The context map is your architectural documentation** — draw it and maintain it.
10. **Apply tactical patterns only to the core domain**. Supporting and generic subdomains don't justify the overhead.

### The Three Warning Signs of a Bad DDD Implementation

| Anti-Pattern | What It Looks Like | The Real Problem |
|---|---|---|
| **Anemic Domain Model** | All domain classes are pure data (getters/setters only); all logic in services | Domain objects have no behavior; DDD overhead with none of the benefit |
| **Repository per Table** | `UserRepository`, `UserAddressRepository`, `UserPreferencesRepository` | Thinking in database tables, not aggregates; should be one `UserRepository` |
| **Service for Everything** | `PaymentService.authorizePayment()`, `PaymentService.capturePayment()` | Logic that belongs in `Payment.authorize()` and `Payment.capture()` is in a service |

---

## Section H — FAANG Interview Cheat Sheet

### Decomposing a System into Bounded Contexts (30-Second Framework)

1. **Ask about the business subdomains**: "What does the business actually do? What are the distinct capabilities?"
2. **Find the linguistic boundaries**: "Does 'Order' mean the same thing in fulfillment and in billing? No? Separate contexts."
3. **Apply Conway's Law**: "How many teams own this? Each team should own exactly one bounded context."
4. **Draw the context map**: "These two contexts have a Customer-Supplier relationship — the fulfillment context is the customer; the inventory context is the supplier."

### Aggregate Design Under Questioning

If the interviewer asks "how do you keep these consistent?" — don't reach for 2PC (two-phase commit). The answer is:
1. **Within one aggregate**: transactional consistency via optimistic locking
2. **Across aggregates in one context**: Saga (choreography or orchestration) via domain events
3. **Across bounded contexts**: eventual consistency via published domain events + idempotent consumers

### Numbers to Know

| Concept | Concrete Number |
|---|---|
| Typical aggregate load time | < 5ms (should fit in a single DB read) |
| Aggregate size (rule of thumb) | < 10 entities/VOs; < 1KB in serialized form |
| Event replay (snapshot threshold) | Snapshot every 50-100 events to avoid full replay |
| Eventual consistency lag (Kafka) | P99 < 100ms for same-datacenter event propagation |

---

## Chapter-by-Chapter Reference

| Chapter | Core Contribution | FAANG Application |
|---|---|---|
| 1 — Getting Started with DDD | Why DDD; when it pays off; the cost of a Big Ball of Mud | Frame "why" before proposing DDD in an interview |
| 2 — Domains, Subdomains, Bounded Contexts | Subdomain taxonomy; bounded context definition; physical boundaries | The first 10 minutes of any microservices decomposition question |
| 3 — Context Maps | All 8 integration patterns; how teams relate to each other | Answer: "How do teams coordinate at Amazon's scale?" |
| 4 — Architecture | Hexagonal architecture; Ports & Adapters; layering rules | Justify your layering choices under follow-up questioning |
| 5 — Entities | Identity; equality semantics; lifecycle | Entity vs Value Object decision |
| 6 — Value Objects | Immutability; primitive obsession anti-pattern; domain types | Money, Address, Email — show self-validating VOs |
| 7 — Services | Domain service vs application service; when to use | Explain why a `TransferService` exists vs `Account.debit()` |
| 8 — Domain Events | Event structure; publishing; eventual consistency | The answer to "how do you keep two services consistent?" |
| 9 — Modules | Packaging; cohesion rules | How to structure a bounded context's codebase |
| 10 — Aggregates | The four rules; aggregate size; consistency boundaries | The most tested chapter — know it cold |
| 11 — Factories | Creation invariants; when a constructor isn't enough | Complex object creation patterns |
| 12 — Repositories | Collection semantics; interface location; implementation location | Repository vs DAO; one repo per aggregate root |
| 13 — Integrating Bounded Contexts | ACL; event-driven integration; RPC vs messaging | Migration from monolith; third-party API integration |
| 14 — Application | CQRS deep dive; read model design | When to apply CQRS; query performance at scale |
| Appendix — Event Sourcing | Full event-sourcing pattern; snapshots; projections | Finance/audit system design questions |

---

## Connecting to the Rest of the Interview Preparation

| Topic | Where to Look |
|---|---|
| DDD applied to a Payment Platform (full code) | [LLD/ddd/payment-platform/](../../LLD/ddd/payment-platform/README.md) |
| Strategic design reference | [LLD/ddd/README.md](../../LLD/ddd/README.md) |
| Saga orchestration across bounded contexts | [LLD/ddd/payment-platform/07-saga-patterns.md](../../LLD/ddd/payment-platform/07-saga-patterns.md) |
| Outbox pattern, idempotency, production patterns | [LLD/ddd/payment-platform/09-production-patterns.md](../../LLD/ddd/payment-platform/09-production-patterns.md) |
| Distributed consistency (CAP/PACELC) | [Books/summaries/designing-data-intensive-applications-kleppmann.md](designing-data-intensive-applications-kleppmann.md) |
| Microservices patterns | Architecture/microservices/ |
