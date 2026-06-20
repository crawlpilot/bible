# DDD Philosophy & Eric Evans' Blue Book

## Overview
Domain-Driven Design was introduced by Eric Evans in *Domain-Driven Design: Tackling Complexity in the Heart of Software* (2003) — commonly called the "blue book." It is the foundational text for all DDD practice. Despite being published before microservices, Kubernetes, or cloud-native were vocabulary, its ideas have become *more* relevant, not less, as software systems have grown more distributed and complex.

The central problem DDD addresses: **software development projects fail not because developers can't write code, but because they build the wrong model.** The software models what developers assume the business does — filtered through requirements documents, misunderstood specifications, and meetings where domain experts and engineers talk past each other.

---

## The Central Thesis

> "The heart of software is its ability to solve domain-related problems for its users. All other features, vital as they may be, support this basic purpose." — Eric Evans

The software model must be **isomorphic to the domain model** — the concepts in the code should mirror the concepts the domain expert uses. When a billing specialist says "we apply a late fee on overdue invoices," that concept should exist explicitly in the code, not be buried in a `calculateTotal()` method inside a `InvoiceService` alongside unrelated calculations.

This is what DDD calls the **domain model**: not an ER diagram or a class diagram, but a living, evolving abstraction of the business concepts and their relationships.

---

## Three Modes of DDD Practice

### 1. Collaborative Discovery
Before any code is written: domain experts and engineers work together to build shared understanding. The output is a **Ubiquitous Language** — a vocabulary that both sides use, unambiguously, in conversation, documentation, and code.

Tools: Event Storming, Domain Storytelling, example mapping, user story workshops.

### 2. Strategic Design
Identifying the large-scale structure: where are the domain boundaries? Which subdomains are competitive differentiators? How do different parts of the system relate? Strategic design operates at the team and organisational level.

Tools: Bounded Contexts, Context Maps, Core/Supporting/Generic subdomain classification.

### 3. Tactical Design
The implementation patterns: how do you code the domain model itself? How do you represent business invariants in code without leaking them into controllers or databases?

Tools: Entities, Value Objects, Aggregates, Domain Services, Repositories, Domain Events.

---

## Eric Evans "Blue Book" — Key Takeaways by Section

### Part I: Putting the Domain Model to Work
- The domain model must be expressed in code — not just in documentation or whiteboards
- **Knowledge Crunching**: the model improves through intensive collaboration between developers and domain experts over time, not in a single requirements workshop. The first model is always wrong; the refined model emerges through iteration
- The model and the code must stay in sync — a model that lives only in documents is not a model, it's a lie
- **FAANG application**: "Breakthrough" moments happen when a better model suddenly makes the complex simple — be open to refactoring the model, not just the code

### Part II: The Building Blocks of a Model-Driven Design
- Entities, Value Objects, Aggregates, Services, Repositories, Factories (covered in depth in [04-tactical-design.md](04-tactical-design.md))
- The most important insight: **Aggregates define the transactional boundary**, not the database schema
- Business invariants must be enforced by the Aggregate, not by the service layer

### Part III: Refactoring Toward Deeper Insight
- The domain model must be refactored as understanding deepens — this is normal, not a failure
- **Supple Design**: code that reads like the domain, not like CRUD operations
- Intention-Revealing Interfaces: method names express what the business operation does (`invoice.applyLateFee()`), not how it does it (`invoice.setAmount(invoice.getAmount() * 1.05)`)
- Side-Effect-Free Functions: prefer Value Objects and pure transformations over state mutation

### Part IV: Strategic Design
- **Bounded Contexts**: the most important idea in the book. Every model has a bounded context within which it is valid
- **Context Maps**: the explicit documentation of how Bounded Contexts relate
- The Distillation chapter: how to identify and protect your Core Domain — the competitive advantage — from the entropy of supporting concerns
- Large-Scale Structure: patterns for giving the overall system coherence (Responsibility Layers, Evolving Order)

---

## Vaughn Vernon "Red Book" — Implementing DDD (Key Additions)

Vaughn Vernon's *Implementing Domain-Driven Design* (2013) takes Evans' concepts and shows how to implement them in actual code. Key additions:

| Contribution | Description |
|---|---|
| **Aggregate design rules** | Explicit rules for aggregate size: reference other aggregates by ID, not by object reference; one transaction per aggregate |
| **Domain Events as first-class citizens** | Evans mentions domain events briefly; Vernon elevates them to a primary tactical pattern |
| **Application Services** | Thin orchestration layer between the delivery mechanism (HTTP) and the domain; does not contain business logic |
| **CQRS + Event Sourcing integration** | How these patterns complement DDD's Aggregates |
| **Bounded Context implementation** | Concrete code structure for Bounded Context isolation (separate packages, separate databases) |

---

## Knowledge Crunching

Knowledge Crunching is Evans' term for the iterative process by which the domain model is refined:

```
1. Developer interviews domain expert
2. Developer builds a model based on what they heard
3. Domain expert reviews the model — "that's not quite right, a customer becomes a member after their third purchase, not first"
4. Model is refined
5. Repeat — the model gets richer and more accurate with each cycle
```

The model should be able to **run scenarios** — walk a domain expert through a concrete business situation using only the concepts in the model. If the expert can follow the walkthrough, the model is good. If they keep saying "but that's not how it works," the model is wrong.

**Implication for software**: a domain model that was correct 12 months ago may be wrong today as the business has evolved. The model must be maintained, not frozen.

---

## DDD Advantages

| Advantage | Description | When it pays off |
|---|---|---|
| **Explicit domain model** | Business rules live in the domain layer, not scattered across services | When rules are complex and change frequently |
| **Ubiquitous Language** | Engineers and domain experts speak the same language | Reduces "lost in translation" bugs; reduces requirements rework |
| **Evolvability** | Well-bounded models can be changed without system-wide impact | Long product lifetime; frequent domain evolution |
| **Team alignment** | Bounded Contexts give teams explicit ownership with clear contracts | Multi-team orgs; reduces stepping on each other |
| **Reduced integration bugs** | Context Map patterns make integration contracts explicit | Prevents model pollution from upstream systems |
| **Testability** | Domain logic separated from infrastructure can be tested independently | High test coverage at low cost when done correctly |
| **Onboarding** | Ubiquitous Language makes the codebase self-documenting for domain experts | Large codebases; high team turnover |

---

## DDD Disadvantages

| Disadvantage | Description | Mitigation |
|---|---|---|
| **Learning curve** | Full tactical DDD takes 6–12 months to internalise | Start with strategic design only; add tactical incrementally |
| **Upfront modelling cost** | Event Storming and domain workshops take time | Invest only in Core Domain; use shortcuts in Supporting/Generic |
| **Overhead for simple domains** | For CRUD apps, DDD is accidental complexity | Apply the complexity scale heuristic (see README.md) |
| **Domain expert availability** | Ubiquitous Language requires access to domain experts | Non-negotiable: without domain access, strategic DDD fails |
| **Model evolution disruption** | Model refactors propagate to multiple layers | Hexagonal architecture mitigates this by isolating the domain layer |
| **Anemic model risk** | Teams apply DDD vocabulary without the discipline, creating anemic models | Code review and pair programming on Aggregate design |

---

## Best Practices

1. **Start with Strategic Design** — Bounded Contexts and Ubiquitous Language before any Aggregates or Value Objects
2. **Invest DDD depth proportionally to domain value** — Core Domain gets full tactical DDD; Generic subdomains get bought/outsourced
3. **Use Event Storming early** — before the first line of code; model the domain in the open with all stakeholders
4. **Keep the model in the code** — if a domain concept is not in the code, it's not in the model; documentation-only models decay
5. **Refactor the model relentlessly** — a model that doesn't change doesn't reflect a business that changes
6. **Protect the domain layer** — no ORM imports, no HTTP clients, no AWS SDK in the domain package
7. **Make implicit concepts explicit** — when a domain expert uses a concept informally, give it a name and a class

---

## FAANG Interview Points

**"Why would you use Domain-Driven Design?"**: DDD solves two problems that get worse with scale. First, misaligned models — the software encodes what engineers think the business does, not what it actually does. Second, organisational coupling — without explicit Bounded Contexts, teams build on shared models that create invisible dependencies. DDD gives you the tools to identify boundaries, build shared language, and make integration contracts explicit. The payoff grows with system complexity and team size.

**"Walk me through how you'd model a payment processing domain"**: Start with Event Storming: map the domain events on a timeline (PaymentInitiated, PaymentAuthorised, PaymentSettled, PaymentFailed, RefundRequested, RefundIssued). Identify Bounded Contexts: Payments (authorisation + settlement), Fraud (risk scoring), Accounting (ledger entries), Notifications (customer-facing events). Each context owns its model of a "payment" — they look different in each. In the Payments context, use Aggregate design: `Payment` is the aggregate root; `PaymentAttempt` is a child entity; `Money` is a Value Object. The aggregate enforces the invariant: you cannot authorise a payment that is already settled.

**"What's the most common DDD mistake you've seen?"**: The Anemic Domain Model. Teams add DDD vocabulary — they have `PaymentEntity`, `PaymentRepository`, `PaymentFactory` — but `PaymentEntity` has only getters and setters. All the business logic is in `PaymentService` which has a `doPayment()` method. This is not DDD; it is procedural programming wearing DDD clothes. The fix: move the business rules into the entity and aggregate. If you can describe a business operation as a message sent to an object (`payment.authorise()`), that method belongs on the object.
