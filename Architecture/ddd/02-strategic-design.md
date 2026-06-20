# Strategic Design: Bounded Contexts, Subdomains & Ubiquitous Language

## Overview
Strategic Design is the highest-value part of DDD for principal engineers — it operates at the team and organisational level, long before any code is written. It answers: "What should this service own? What should it not own? What is the business trying to differentiate on? How should teams be structured?"

Strategic Design has three interlocking tools: **Ubiquitous Language** (shared vocabulary), **Subdomains** (business capability classification), and **Bounded Contexts** (explicit model boundaries).

---

## Ubiquitous Language

A Ubiquitous Language is a shared vocabulary between domain experts and engineers, used consistently in conversation, documentation, user stories, and code. Not a translation layer — the same words everywhere.

### The Problem It Solves
```
Domain expert says: "A customer becomes eligible for a loyalty tier upgrade
                     after 3 qualifying purchases in a rolling 90-day window."

Developer hears:   "Something happens after purchases. I'll use a User table
                    and add a loyaltyStatus field."

Code says:         user.loyaltyStatus = calculateLoyalty(user.purchaseHistory)

Domain expert looks at code: "What is calculateLoyalty? What is loyaltyStatus?
                               What's a qualifying purchase? What's 'rolling'?"
```

The model fails because the vocabulary diverged. Ubiquitous Language would have produced:
```python
customer.attemptLoyaltyTierUpgrade(evaluationWindow=days(90))
# Method name is literally the domain concept
# evaluationWindow is named as the domain expert named it
# "qualifying purchase" is a concept with its own type
```

### Building a Ubiquitous Language
1. Domain expert + developer work together on concrete scenarios (not abstract requirements)
2. Every new concept gets a name agreed upon by both sides
3. When disagreement occurs, it surfaces a misunderstanding that must be resolved
4. The language is captured in a **domain glossary** — living document, updated as the model evolves
5. If a developer uses a term the domain expert doesn't recognise, it's a red flag

### Language Divergence as a Boundary Signal
When the same word means different things in two contexts, you have found a Bounded Context boundary:

| Term | Meaning in Sales | Meaning in Fulfilment | Meaning in Billing |
|---|---|---|---|
| "Order" | Opportunity being negotiated | Physical shipment to fulfil | Invoice to generate |
| "Customer" | Account with a sales rep | Shipping address | Legal entity to invoice |
| "Product" | SKU with pricing tiers | Physical item to pick/pack | Line item on invoice |
| "Cancel" | Close lost opportunity | Return shipment | Credit note |

These are not the same concepts. Forcing them into one model creates a **Big Ball of Mud**.

---

## Subdomains: Classifying the Business

A Domain is the problem space — the business and everything it does. Subdomains are the logical parts of the domain. The critical classification:

### Core Domain
The competitive advantage. The thing your company does that no one else does as well. This is why customers choose you over competitors.

- Invest maximum engineering effort here
- Best engineers work here
- Build, never buy — off-the-shelf solutions can't model your differentiating logic
- Apply full tactical DDD — Aggregates, Value Objects, Domain Events, Hexagonal Architecture

**Examples**: Netflix recommendation engine; Uber's dynamic pricing algorithm; Stripe's payment fraud detection; Amazon's fulfilment routing

### Supporting Subdomain
Necessary to support the Core Domain but not differentiating. Customers don't choose you because of this.

- Build lean or outsource; don't gold-plate
- Simpler architecture acceptable (light tactical DDD or none)
- Lower seniority engineers can own these
- Could buy if a good-enough solution exists

**Examples**: user notifications system; audit logging; reporting dashboards; document storage

### Generic Subdomain
A solved problem. Identical to what every other company needs.

- **Buy or use open source** — never build
- No engineering differentiation to be had here
- Accepting a 90%-fit off-the-shelf solution is correct

**Examples**: authentication/authorisation (Auth0, Okta), email delivery (SendGrid), payment processing (Stripe), observability (Datadog)

### E-Commerce Platform Subdomain Classification

| Capability | Subdomain type | Approach |
|---|---|---|
| Personalised recommendations | Core | Build, full DDD, best engineers |
| Dynamic pricing / promotions engine | Core | Build, full DDD |
| Order fulfilment routing | Core | Build, full DDD |
| Inventory management | Supporting | Build lean or use ERP module |
| Customer notifications | Supporting | Build thin wrapper around SendGrid |
| User authentication | Generic | Buy (Okta / Cognito) |
| Payment processing | Generic | Buy (Stripe / Adyen) |
| PDF invoice generation | Generic | Buy (open source library) |
| Observability | Generic | Buy (Datadog / CloudWatch) |

---

## Bounded Context

A Bounded Context is **the explicit boundary within which a particular domain model is defined and applicable**. Inside the boundary, every term has a single, unambiguous meaning. The same term may mean something different in another Bounded Context — that is correct and expected.

### The Most Common Misunderstanding
Bounded Contexts are not modules, packages, or microservices. They are a **modelling boundary**. They *often* map to microservices, but the mapping can be 1:many or many:1.

```
Bounded Context: Payments
  ├── Could be one microservice (payments-service)
  ├── Could be three microservices (authorisation-service, settlement-service, fraud-service)
  └── Always: one team, one codebase, one database, one deployment decision per context
```

### Same Concept, Different Models

```
                    ┌─────────────────────────────────┐
                    │       SALES CONTEXT              │
                    │                                  │
                    │  Customer {                      │
                    │    id, name, salesRepId,         │
                    │    accountTier, ltvEstimate       │
                    │  }                               │
                    └─────────────────────────────────┘

                    ┌─────────────────────────────────┐
                    │     FULFILMENT CONTEXT           │
                    │                                  │
                    │  Customer {                      │
                    │    id, shippingAddress,          │
                    │    deliveryPreferences,          │
                    │    contactPhone                  │
                    │  }                               │
                    └─────────────────────────────────┘

                    ┌─────────────────────────────────┐
                    │      BILLING CONTEXT             │
                    │                                  │
                    │  Customer {                      │
                    │    id, legalEntityName,          │
                    │    taxId, billingAddress,        │
                    │    paymentTerms                  │
                    │  }                               │
                    └─────────────────────────────────┘
```

These are three different models of "Customer." Forcing them into one Customer table/class is the root cause of God Objects and Big Ball of Mud systems.

### Bounded Context vs Microservice

| Scenario | Relationship | Rationale |
|---|---|---|
| Default | 1 BC = 1 microservice | Simplest; team owns the context end-to-end |
| High throughput subdomain | 1 BC = 2+ microservices | Split authorisation and settlement for independent scaling |
| Early-stage startup | 1 BC = 1 monolith module | Not worth microservice overhead yet; boundary is still the code module |
| Legacy system | Multiple BCs in 1 monolith | Bounded Contexts can be logical, not physical — preparation for future extraction |

**Rule**: a microservice must never span two Bounded Contexts. If it does, it owns two conflicting models, two languages, and two sets of invariants — guaranteed coupling and confusion.

---

## Context Map

A Context Map is the explicit documentation of how Bounded Contexts relate and integrate. It is the strategic DDD equivalent of a network diagram — it shows team relationships and data flows.

The full patterns are documented in [03-context-map-patterns.md](03-context-map-patterns.md). At the strategic level, the key questions are:

```
For any two Bounded Contexts A and B:
1. Which is upstream (produces) and which is downstream (consumes)?
2. How coupled is the downstream to the upstream model?
3. Who has the power to change the contract?
4. What happens when the upstream changes?
```

---

## Discovering Bounded Context Boundaries

In a greenfield system: use Event Storming to discover where language diverges — that's a boundary.

In an existing system/legacy codebase:

1. **Look for linguistic seams**: where does the same word mean something different in different parts of the code?
2. **Look for database join aversion**: where do developers avoid joining tables because "those two things don't really belong together"?
3. **Look for team friction**: where does Team A keep breaking Team B's functionality? That's an implicit, violated context boundary.
4. **Look for deployment coupling**: which sets of services always deploy together because they share a model? That set might be one Bounded Context.
5. **Look for change frequency**: code that changes together for the same business reason tends to belong in the same context.

---

## Cognitive Load Reduction

Bounded Contexts are the primary DDD tool for reducing cognitive load on engineering teams:

- A team that owns a Bounded Context only needs to understand their context's model — not the entire system
- The Context Map tells them exactly where the boundaries are and what the integration contracts look like
- New engineers joining a team can learn one context's domain language without needing to understand six others
- When a domain expert needs to explain a feature, they explain it in one context's vocabulary — not in "global" terms that span everything

**Team Topologies connection**: a stream-aligned team's cognitive load is bounded by the Bounded Context they own. The Context Map makes cross-team dependencies explicit — which is the prerequisite for managing those dependencies intentionally (see [07-ddd-microservices-and-teams.md](07-ddd-microservices-and-teams.md)).

---

## Best Practices

1. **Draw the Context Map before designing APIs** — the map tells you who is upstream and downstream; the API follows from that
2. **Duplicate data, not models** — it is correct for the same piece of information to be represented differently in each context; resist the urge to share one model
3. **Protect the Core Domain** — don't let Supporting or Generic subdomain concerns pollute the Core Domain model
4. **Name contexts by capability, not by team** — "Payments" not "Team-Payments"; teams change, capabilities don't
5. **One team per Bounded Context maximum** — shared ownership of a context leads to shared-model creep
6. **Evolve context boundaries** — initial boundaries are always approximate; refine them as the model deepens

---

## FAANG Interview Points

**"How do you define microservice boundaries?"**: Bounded Contexts from DDD. A Bounded Context is the boundary within which a domain model is internally consistent and the language is unambiguous. One team owns one Bounded Context. The boundary is discovered through language divergence (where the same word means different things) and business capability seams. A microservice should never span two Bounded Contexts because that forces two conflicting models into one codebase.

**"Your team is building a large e-commerce platform. How would you decompose it into services?"**: Start with Event Storming to discover domain events across the timeline. Identify where language diverges — that signals a Bounded Context boundary. Classify subdomains: Recommendations and Pricing are Core (build, full DDD); Notifications and Reporting are Supporting (build lean); Auth and Payment Processing are Generic (buy). Each Core subdomain becomes a Bounded Context owned by a stream-aligned team. Context Map defines how they integrate (Customer-Supplier relationships, Anti-Corruption Layers for legacy integrations).

**"What is Ubiquitous Language and why does it matter?"**: It's the shared vocabulary between domain experts and engineers that is used consistently in conversation, requirements, documentation, and code. It matters because misaligned vocabulary is the root cause of requirements that don't match business intent. When the domain expert says "qualifying purchase" and the code has `purchase.isEligible()`, they're speaking the same language — and that means the code is less likely to be wrong.
