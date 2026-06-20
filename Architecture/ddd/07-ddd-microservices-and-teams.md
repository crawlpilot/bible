# DDD + Microservices + Team Topologies

## Overview
Domain-Driven Design is the missing link between microservice architecture and team structure. Without DDD, microservice decomposition is driven by technical intuition — "let's make a service for each database table" or "the checkout flow should be its own service." With DDD, decomposition is driven by domain semantics: Bounded Contexts define ownership, Ubiquitous Language defines the API contracts, and Context Map patterns define the integration approach.

The result: microservice boundaries that align with both the domain model and the team structure — which, through Conway's Law, is the only way they will stay aligned as the system evolves.

---

## The Bounded Context → Microservice Mapping

### The Fundamental Rule
**A microservice must never span two Bounded Contexts.**

If a service owns models from two Bounded Contexts, it owns two conflicting vocabularies, two sets of invariants, and two team charters. Deployments require coordinating both contexts. Changes to one context inadvertently affect the other.

**One Bounded Context can be one or many microservices.** The Bounded Context is the semantic unit; microservice decomposition within a context is a deployment and scaling decision.

```
E-Commerce Platform (Bounded Contexts → Microservices)

┌─────────────────────────────────┐
│  Orders Bounded Context         │
│  ├── order-service              │  ← 1:1 default
└─────────────────────────────────┘

┌─────────────────────────────────┐
│  Payments Bounded Context       │
│  ├── payment-authorisation-svc  │  ← 1:many (split for throughput)
│  └── payment-settlement-svc     │
└─────────────────────────────────┘

┌─────────────────────────────────┐
│  Catalogue Bounded Context      │
│  ├── product-catalogue-svc      │  ← 1:many (split read/write)
│  └── catalogue-search-svc       │
└─────────────────────────────────┘

┌─────────────────────────────────┐
│  Fulfilment Bounded Context     │
│  ├── fulfil-svc                 │  ← 1:1
└─────────────────────────────────┘
```

### When to Split a Bounded Context into Multiple Services

| Trigger | Action |
|---|---|
| Deployment cadence diverges significantly | Split: the fast-changing part becomes its own service |
| Scaling requirements differ by order of magnitude | Split: the high-throughput part needs its own scaling policy |
| Team cognitive load exceeds what one team can hold | Split: consider whether this signals two sub-contexts |
| Two sub-domains within the context have diverging vocabularies | Split: you may have initially drawn the context boundary too broadly |

### When to Merge Services

| Trigger | Action |
|---|---|
| Two services always deploy together | Merge: they are probably one context masquerading as two |
| A business operation always spans both services in one transaction | Merge: if you can't avoid distributed transactions, the boundary is wrong |
| The services share a model (same class definitions in both) | Merge: Shared Kernel anti-pattern — merge and draw the boundary correctly |

---

## Conway's Law and the Inverse Conway Manoeuvre

### Conway's Law (Melvin Conway, 1968)
> "Any organisation that designs a system will produce a design whose structure is a copy of the organisation's communication structure."

This is not a warning — it is an **inevitable force**. If you have a team that spans three Bounded Contexts, those contexts will become tightly coupled because the team members talk to each other. If you have three teams that each own one context, those contexts will be loosely coupled because the teams communicate through explicit APIs.

### Conway's Law in Practice

```
If this is your team structure:    You will get this architecture:

Team A ──────── Team B             Service A tightly coupled to Service B
     (constant communication)       (shared DB, direct calls, no contracts)

Team A │ Team B │ Team C            Service A ←→ Service B ←→ Service C
     (structured APIs only)         (explicit contracts, independent deployment)
```

### The Inverse Conway Manoeuvre

If you want a specific architecture, **design the team structure first**. The architecture will follow.

1. Identify the desired Bounded Contexts (through Event Storming, strategic design)
2. Assign one stream-aligned team per Core Domain Bounded Context
3. The teams will naturally build interfaces that match the Context Map
4. The architecture that emerges will align with the Bounded Context boundaries

**This is why team structure is an architecture decision**, not just an HR decision. Reorganising teams changes the software architecture — inevitably.

---

## Team Topologies Alignment

Team Topologies (Skelton & Pais) provides the organisational design framework that maps cleanly onto DDD's Bounded Context structure.

### Stream-Aligned Team ↔ Core Domain Bounded Context

A stream-aligned team is a cross-functional team that owns a full slice of the product from user need to production deployment. They are the primary team type.

**DDD mapping**: one stream-aligned team owns one Core Domain Bounded Context.

```
Stream-aligned Team: "Payments"
  Owns: Payments Bounded Context (payment-authorisation-svc, payment-settlement-svc)
  Vocabulary: the Payments Ubiquitous Language (Payment, Authorisation, Settlement, Refund)
  Upstream of: Reporting, Accounting
  Downstream of: Orders (receives OrderSubmitted events)
  
Cognitive load: limited to the Payments context — team does not need to understand Catalogue or Fulfilment
```

### Platform Team ↔ Generic Subdomain

Platform teams provide internal capabilities that reduce cognitive load for stream-aligned teams. They treat stream-aligned teams as customers.

**DDD mapping**: the platform team owns Generic subdomain Bounded Contexts (observability, CI/CD platform, secrets management, message bus infrastructure).

```
Platform Team: "Developer Platform"
  Owns: CI/CD pipelines, Kubernetes cluster management, Observability stack
  These are Generic subdomains — buy where possible (Datadog, AWS services)
  Service to: all stream-aligned teams (reduces their infrastructure cognitive load)
```

### Complicated Subsystem Team ↔ Complex Supporting Subdomain

These teams own areas of specialised knowledge that are too complex for a generalist stream-aligned team but not directly competitive.

**DDD mapping**: owns a Supporting subdomain that requires deep specialist expertise.

```
Complicated Subsystem Team: "Search & Recommendations"
  Owns: ML-based recommendation engine, Elasticsearch search cluster
  This is a Supporting subdomain for the business but requires ML expertise
  Provides capability to: Catalogue context (consumed as a service)
```

### Enabling Team ↔ DDD Practice Facilitation

Enabling teams work with stream-aligned teams temporarily to build capability they don't have.

**DDD mapping**: facilitates Event Storming, runs modelling workshops, helps teams identify and correct Bounded Context boundary mistakes, introduces tactical DDD patterns.

---

## Data Ownership: One Context, One Database

**The rule**: each Bounded Context owns its data. No other context may access that data directly — not via shared database, not via direct table join, not via ORM relationship.

```
                        Payments Context             Orders Context
                        ┌─────────────────┐          ┌──────────────────┐
                        │  Payment DB      │          │  Orders DB        │
                        │  (PostgreSQL)    │          │  (Aurora)         │
                        │                 │          │                   │
                        │  payments table │          │  orders table     │
                        │  settlements    │          │  order_lines      │
                        └────────┬────────┘          └──────────┬────────┘
                                 │                              │
                                 └──────────── NO JOIN ─────────┘
                                              ↓
                                   Cross-context access via:
                                   - Async domain events (preferred)
                                   - Synchronous API call (when consistency required)
                                   - NEVER via shared DB
```

### Cross-Context Data Access Patterns

| Pattern | When | Trade-off |
|---|---|---|
| **Async Domain Events** | Read model built from upstream events; eventual consistency acceptable | Low coupling; eventual consistency; complex failure handling |
| **Synchronous API call** | Upstream data needed to complete a synchronous operation | Temporal coupling; upstream availability required; simpler |
| **Shared Read Model** | Reporting context aggregates from multiple upstream events | Very low coupling; read-only; eventual consistency |
| **Never: shared DB** | — | Tight coupling; migrations affect multiple teams; context boundary destroyed |

---

## Microservice Sizing Heuristic (Synthesis)

There is no correct number of microservices. The correct question is: **does each service align with a Bounded Context, and does each team own a cognitively manageable scope?**

| Signal | Action |
|---|---|
| Services always deploy together | Merge — they are one deployment unit, probably one context |
| Team can't understand what their service does without understanding five others | Context boundary too broad — split |
| A business feature requires coordinating three teams for one PR | Team boundaries don't match the domain — reorganise |
| Service has multiple conflicting vocabularies for the same concept | Context boundary drawn incorrectly — refactor |
| Throughput bottleneck in one part of a context | Split microservices within the context for independent scaling |

---

## Operational Benefits of DDD-Aligned Microservices

| Benefit | Mechanism | Example |
|---|---|---|
| **Independent scaling** | Each context scales independently | Payments scales to 10k TPS for Black Friday; Catalogue scales separately for search load |
| **Independent deployment** | Each context deployed on its own cadence | Payments deploys 4× per day; Reporting deploys weekly |
| **Fault isolation** | Failure in one context contained by ACL pattern | Reporting outage doesn't affect Order placement or Payment processing |
| **Technology heterogeneity** | Each context chooses appropriate storage and compute | Payments: PostgreSQL (ACID); Catalogue: Elasticsearch (search); Recommendations: DynamoDB + ML platform |
| **Team autonomy** | Teams make decisions without cross-team coordination | Payments team can refactor their data model without filing a change request with Catalogue team |
| **Blast radius control** | Cell-based architecture within a context | (see [cell-based-architecture.md](../../CloudArchitecture/patterns/cell-based-architecture.md)) |

---

## Anti-Patterns

### Nano-services
Services so small they cannot independently implement a business capability. Every feature requires coordinating multiple services, multiple teams, multiple deployments.

**Symptom**: a business requirement that should be a 2-hour implementation takes 2 weeks because it touches 8 "microservices" owned by 4 teams.

**Fix**: merge services into a Bounded Context aligned service. One team can own a larger, coherent service better than four teams can own four tiny ones.

### Shared Database
Multiple services access the same database directly. The database schema becomes a shared model — changing a column breaks multiple services simultaneously.

**Symptom**: database migrations require coordinating 6 teams, locking the table for 4 hours, and a 3-page runbook.

**Fix**: one database per Bounded Context. Cross-context data via events or API. 

### Distributed Monolith
Microservices that are independently deployed but tightly coupled at the data or model level. Releasing any service requires releasing all of them in a specific order.

**Root cause**: Bounded Context boundaries were not drawn before microservice decomposition. The monolith's coupling was distributed across the network rather than removed.

**Fix**: map Bounded Contexts correctly; introduce ACL for cross-context communication; decouple deployments by introducing async events.

---

## Best Practices

1. **Draw the Context Map before defining microservice boundaries** — the map tells you who owns what; boundaries follow
2. **One team per Bounded Context** — shared team ownership of a context leads to shared model and implicit coupling
3. **Each context owns its database** — shared databases destroy context boundaries over time
4. **Start with one service per context** — split only when scaling or cognitive load demands it
5. **Use async events for cross-context eventual consistency** — don't let cross-context operations require distributed transactions
6. **Communicate team boundaries to leadership** — Conway's Law means team reorganisations change the architecture; this must be a deliberate decision
7. **Monitor team cognitive load explicitly** — if a team consistently reports that "it's hard to understand what this service does," the context boundary may be wrong

---

## FAANG Interview Points

**"How many microservices should we have?"**: Start with one service per Bounded Context. Context boundaries come from Event Storming — where language diverges, a boundary exists. Within a context, split for independent scaling or distinct deployment cadence. The number isn't a target: 10 services with clear boundaries is better than 100 with overlapping responsibilities. The right number is "one per team-ownable, cognitively-manageable, independently-deployable domain boundary."

**"How do you manage data consistency across microservices?"**: Each Bounded Context owns its database. Cross-context consistency is eventual, via domain events. The Orders context publishes `OrderSubmitted`; the Inventory context subscribes and reserves stock; Payments subscribes to `InventoryReserved` and authorises payment. This is a Saga — see [LLD: Saga](../../LLD/design-patterns/modern/26-saga.md). For synchronous consistency requirements, use API calls with the Anti-Corruption Layer pattern. Never use cross-service DB joins or distributed transactions (2PC).

**"How does team structure affect software architecture?"**: Conway's Law: the architecture mirrors team communication structure — inevitably. If you want loosely coupled services, you need loosely coupled teams. We use the Inverse Conway Manoeuvre: decide the desired Bounded Context architecture first via Event Storming, then design the team structure to match. Each stream-aligned team owns one Bounded Context. Team APIs become service APIs. Team contracts become Context Map patterns. The architecture then emerges organically because the teams naturally produce it.
