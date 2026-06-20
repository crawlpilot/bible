# DDD Trade-offs, Anti-Patterns & When NOT to Use It

## Overview
DDD is not a universal solution. It is a set of tools for managing complexity in software that models complex domains. Applying DDD where the complexity doesn't exist creates accidental complexity — overhead that slows teams down without corresponding benefit.

Principal engineers must be able to answer both "when would you use DDD?" and "when would you NOT?" Candidates who only know the first question are pattern-collectors. Candidates who know both understand architecture as a discipline of trade-offs.

---

## The Honest Trade-off Table

| Dimension | DDD (Full) | Simple Layered Architecture |
|---|---|---|
| **Model accuracy** | High — domain experts co-build the model | Medium — developers interpret requirements |
| **Evolvability** | High — bounded changes; explicit contracts | Low — changes ripple through layers |
| **Team scalability** | High — Bounded Contexts enable parallel teams | Low — shared model = coordination overhead |
| **Upfront investment** | High — Event Storming, modelling workshops, hexagonal structure | Low — start coding immediately |
| **Learning curve** | 6–12 months to full tactical fluency | Days to weeks |
| **Overhead for simple domains** | Very high — unnecessary abstraction | None |
| **Domain expert requirement** | Non-negotiable — must have access | Optional |
| **Testability** | Excellent (with hexagonal architecture) | Moderate (mocking required) |
| **Code volume** | Higher — more classes, more interfaces | Lower |
| **Correctness for complex rules** | High — invariants enforced by Aggregate | Low — rules scattered, duplicated |

---

## The Anemic Domain Model Anti-Pattern

**Identified by**: Martin Fowler, 2003 — ironically the same year Evans published the blue book.

### What It Looks Like

```python
# ANEMIC DOMAIN MODEL — the anti-pattern

class Order:  # "Domain object" — but only data
    def __init__(self):
        self.order_id = None
        self.status = None
        self.lines = []
        self.total_amount = 0
    
    # Only getters/setters — no behaviour, no invariants
    def get_status(self): return self.status
    def set_status(self, status): self.status = status  # any status, any time — no validation
    def get_total(self): return self.total_amount
    def set_total(self, total): self.total_amount = total  # can be set to -1000

class OrderService:  # All business logic here
    def submit_order(self, order_id):
        order = self.repo.find(order_id)
        # Business rules duplicated in every service method:
        if order.status != "DRAFT":
            raise Exception("Invalid")
        if len(order.lines) == 0:
            raise Exception("Empty")
        order.set_status("SUBMITTED")
        order.set_total(self._calculate_total(order.lines))
        self.repo.save(order)
        self.notifier.send(order)
    
    def cancel_order(self, order_id):
        order = self.repo.find(order_id)
        if order.status != "DRAFT":  # Same rule — copied
            raise Exception("Invalid")
        order.set_status("CANCELLED")
        self.repo.save(order)
```

### Why It's a Problem

1. **Rules are scattered**: the "can only submit a DRAFT order" rule exists in `submit_order()` — but is it also in the API layer? In the batch processor? In the event consumer? Each copy diverges over time.
2. **No protection from invalid state**: `order.set_status("INVALID_STATUS_NOBODY_CHECKED")` compiles and runs.
3. **Testing requires full stack**: there's no logic in the domain objects to test; tests must exercise service methods with database access or mocks.
4. **No Ubiquitous Language**: `set_status`, `set_total`, `calculate_total` — none of these are domain language. What does `submit` mean to the domain expert?

### The Fix: Rich Domain Model

```python
# RICH DOMAIN MODEL — DDD style

class Order:  # Aggregate Root with behaviour
    def __init__(self, order_id: OrderId, customer_id: CustomerId):
        self._id = order_id
        self._customer_id = customer_id
        self._lines = []
        self._status = OrderStatus.DRAFT
        self._events = []
    
    def submit(self) -> None:
        """Domain method — enforces invariants; cannot be bypassed"""
        if self._status != OrderStatus.DRAFT:
            raise InvalidOrderStateError(f"Order {self._id} is not in DRAFT state")
        if not self._lines:
            raise InvalidOrderStateError("Cannot submit an order with no lines")
        
        self._status = OrderStatus.SUBMITTED
        self._events.append(OrderSubmitted(self._id, self._customer_id, self.total()))
    
    def cancel(self, reason: CancellationReason) -> None:
        if self._status not in (OrderStatus.DRAFT, OrderStatus.SUBMITTED):
            raise InvalidOrderStateError("Cannot cancel a confirmed or fulfilled order")
        self._status = OrderStatus.CANCELLED
        self._events.append(OrderCancelled(self._id, reason))
```

The state machine lives in the Aggregate. No external code can set an invalid status. The rules can be tested in isolation — no database, no HTTP, no mocks.

---

## Other DDD Anti-Patterns

### God Aggregate

An Aggregate that has grown to encompass everything related to its root entity. The `Order` Aggregate contains Order, Customer information, Inventory reservations, Payment state, Shipment tracking — everything that touches an order.

**Problems**:
- Every write operation hits the same aggregate → throughput bottleneck, high contention
- The aggregate crosses Bounded Context boundaries → exposes coupling
- Any change to any part touches the same table → can't deploy independently

**Fix**: decompose by Bounded Context and by consistency requirement. The Order Aggregate should own only the Order's lifecycle in the Orders context. Payment state lives in the Payments Aggregate. Inventory reservation lives in the Inventory Aggregate. They communicate via Domain Events.

---

### Leaky Abstraction (Dependency Rule Violation)

The domain layer imports infrastructure:

```python
# WRONG — domain layer importing ORM (dependency rule violation)
from sqlalchemy.orm import Session  # infrastructure in domain
from boto3 import client as aws_client  # infrastructure in domain

class Order:
    def save(self):  # WRONG — domain objects don't know about persistence
        session = Session()
        session.add(self)
```

**Fix**: see [05-hexagonal-and-clean-architecture.md](05-hexagonal-and-clean-architecture.md). The domain layer defines repository interfaces; the infrastructure layer implements them. The dependency points inward, not outward.

---

### Premature Bounded Context Splitting

Splitting the domain into Bounded Contexts before the model is understood — often driven by the enthusiasm of "we're going to do microservices from day one."

**What happens**:
- The boundaries are drawn on technical guesses, not domain knowledge
- A business feature requires changing 6 services and 4 teams
- The contexts share a model (because they were one concept split by technology)
- The team regrets the split and is "locked in" because rewriting microservices is expensive

**When it happens**: early in a product's life before domain knowledge is deep; or when driven by technology goals ("microservices architecture") rather than domain goals.

**Fix**: start as a modular monolith with clear internal module boundaries. Extract services only when:
- The module's team needs to deploy independently
- The module has genuinely different scaling needs
- The module boundary has been stable for 6+ months (the model is understood)

---

### Cargo-Cult DDD

Using DDD vocabulary — Entity, Repository, Aggregate, Value Object — without understanding the underlying principles.

**Signs**:
- Every class is an Entity (even ones with no identity)
- Repositories exist per Entity, not per Aggregate Root
- Aggregates are designed by database schema, not by consistency boundaries
- Ubiquitous Language glossary exists but nobody uses the terms — the code says something different

**Root cause**: DDD is learned from the patterns (tactical building blocks) rather than from the philosophy (collaborative discovery, explicit models, consistency boundaries).

**Fix**: start with strategic design. Understand *why* the patterns exist before applying them. Run Event Storming before designing Aggregates. Ask "what consistency invariant does this Aggregate enforce?" — if you can't answer, the Aggregate is wrong.

---

### Context Map Avoidance

Teams acknowledge that Bounded Contexts exist but never draw or maintain the Context Map. Cross-context dependencies are implicit, undocumented, and accidental.

**What happens over time**:
- A team changes their event schema without realising another team depends on it
- Two teams implement the same integration differently (one uses ACL, one uses conformist)
- When a legacy system changes, nobody knows which downstream systems will break
- The upstream/downstream relationship is assumed differently by the two teams involved

**Fix**: draw the Context Map. Review it quarterly. Every cross-context integration must be documented with its pattern (ACL, Customer-Supplier, OHS, etc.). Use consumer-driven contract tests (Pact) for Customer-Supplier relationships.

---

## DDD Complexity Scale: The Decision Framework

```
Step 1: Is the domain complex?
  ├── NO  → Standard layered architecture. Don't use DDD.
  └── YES ↓

Step 2: Is this a Core Domain (competitive advantage)?
  ├── NO  (Supporting) → Build lean; strategic design only
  ├── NO  (Generic)   → Buy/use open-source; no DDD
  └── YES (Core)      ↓

Step 3: Do you have access to domain experts?
  ├── NO  → Strategic design only (as much as possible without experts)
  └── YES ↓

Step 4: What is the team maturity level?
  ├── Junior/new team → Strategic design first (Bounded Contexts + Ubiquitous Language)
  │                     Add tactical patterns in 6+ months
  └── Experienced team → Full tactical DDD: Aggregates, Value Objects, Hexagonal Architecture
```

### When NOT to Use DDD

| Situation | Why DDD doesn't help | Better approach |
|---|---|---|
| **Simple CRUD application** | No business rules to model; domain is trivial | Simple REST API + ORM; no domain layer needed |
| **Data pipelines and ETL** | No domain behaviour; purely data transformation | Apache Beam, Spark, Glue; data-centric design |
| **Infrastructure tooling** | Domain is technical, not business | Standard engineering patterns; no DDD vocabulary |
| **Startup pre-PMF** | Domain is unknown and will change radically | Lean, fast iteration; DDD too heavyweight for pivoting |
| **No domain expert access** | Ubiquitous Language cannot be built | Work with whatever domain knowledge exists; skip Event Storming until experts available |
| **Short-lived scripts or tools** | No long-term evolution; investment doesn't pay off | Procedural scripts; no architecture overhead |
| **Small team (<5 engineers)** | Overhead of Bounded Contexts exceeds benefit | Modular monolith with clear module boundaries; extract later |

---

## Cognitive Load Cost of DDD

DDD introduces cognitive load before it reduces it:

**Phase 1 (0–6 months)**: High cost. Learning new vocabulary (Aggregate, Value Object, Port, Adapter). New project structure. Event Storming facilitation. Hexagonal architecture wiring. Developers slow down before they speed up.

**Phase 2 (6–18 months)**: Break-even. The model is understood. New features are added with confidence. The domain layer is testable. But the overhead of maintaining the structure is still felt.

**Phase 3 (18+ months)**: Net benefit. The domain can evolve without cascading changes. New engineers onboard by learning the domain, not by reading spaghetti code. Domain experts can validate the model because it speaks their language.

**Implication**: DDD is a long-term investment. If the product has a < 2 year lifetime, or the team will not stay together long enough to reach Phase 3, DDD may not pay off.

**Recommendation**: introduce incrementally:
1. Start with Ubiquitous Language (zero cost, immediate benefit)
2. Add Bounded Context boundaries (moderate cost, significant benefit)
3. Add tactical patterns in Core Domain only (high cost, high benefit for the right domain)
4. Add hexagonal architecture in services that need to evolve significantly

---

## Best Practices

1. **Match DDD depth to domain complexity** — not every service needs Aggregates; apply proportionally
2. **Start with strategic design, not tactical** — Bounded Contexts first; Aggregates only when the model is understood
3. **Reserve full tactical DDD for Core Domain only** — Supporting and Generic subdomains don't warrant it
4. **Introduce incrementally** — Ubiquitous Language → Context Map → tactical patterns; not all at once
5. **Measure the model's accuracy regularly** — run Event Storming sessions every 6 months for evolving domains
6. **Identify and kill anemic models actively** — review domain objects in code review; if they have only setters, push back
7. **Don't force DDD on resistant teams** — cultural adoption matters; forced DDD produces cargo-cult DDD
8. **Know the exit criteria** — have a clear answer to "what would make us reconsider this boundary?"

---

## FAANG Interview Points

**"When would you NOT apply DDD?"**: Four clear cases. First: simple CRUD — no complex business rules, so no domain model to enrich. A blog post API doesn't benefit from Aggregates. Second: data pipelines — the domain is data transformation, not business behaviour. Spark jobs don't have Aggregates. Third: startups pre-product-market fit — the domain is unknown and will pivot; DDD over-invests in modelling a model that will change. Fourth: teams without domain expert access — Ubiquitous Language requires domain experts; without them, you model what developers assume, not what the business does.

**"What's the biggest risk of applying DDD incorrectly?"**: The Anemic Domain Model. Teams add DDD vocabulary — Entity, Repository, Service — but put all business logic in Service classes. The domain objects are data bags with no behaviour. The result is worse than not using DDD: you have the overhead of the pattern (more classes, more interfaces) without the benefit (invariants enforced in the model, testable domain logic). Detection: if your domain class has `set_status()` with no validation, you have an anemic model.

**"How do you sell DDD to a team that's skeptical of the upfront investment?"**: Start with the one part that has zero upfront cost and immediate payoff: Ubiquitous Language. Spend one hour with the team and one domain expert building a glossary for the five most important domain concepts. When the developer uses the same word the domain expert uses, requirements bugs decrease immediately. Then, after a few sprints where the shared language is visibly reducing rework, propose drawing a Context Map. Add tactical patterns only when the team can see the specific problem they solve.
