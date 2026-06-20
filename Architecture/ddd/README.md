# Domain-Driven Design (DDD)

Domain-Driven Design is a software development philosophy that places the **domain model at the centre of the system** — not the database, not the framework, not the API. It provides tools to tackle the core challenge of complex software: ensuring that the software accurately reflects the business domain it serves, and that domain experts and engineers share a common, unambiguous language and mental model.

DDD is a principal engineer interview topic because it directly answers two of the hardest system design questions: "How do you define microservice boundaries?" and "How do you manage complexity as an organisation and codebase scale?"

---

## File Index

| File | Topic | Reach for this when… |
|---|---|---|
| [01-philosophy-and-ddd-bible.md](01-philosophy-and-ddd-bible.md) | Eric Evans book, DDD philosophy, Knowledge Crunching | You need to explain *why* DDD exists and what it's trying to solve |
| [02-strategic-design.md](02-strategic-design.md) | Bounded Contexts, Subdomains, Ubiquitous Language | Designing microservice boundaries; team ownership; legacy decomposition |
| [03-context-map-patterns.md](03-context-map-patterns.md) | All 9 Context Mapping patterns (ACL, OHS, Conformist…) | Integrating with legacy systems; defining team dependency direction |
| [04-tactical-design.md](04-tactical-design.md) | Aggregates, Entities, Value Objects, Repositories, Factories | Designing the internals of a service; preventing anemic domain model |
| [05-hexagonal-and-clean-architecture.md](05-hexagonal-and-clean-architecture.md) | Hexagonal / Ports & Adapters, Clean Architecture, Onion | Structuring a service for testability and infrastructure independence |
| [06-event-storming-and-discovery.md](06-event-storming-and-discovery.md) | Event Storming, Domain Storytelling, stakeholder alignment | Discovering domain boundaries; aligning product and engineering |
| [07-ddd-microservices-and-teams.md](07-ddd-microservices-and-teams.md) | DDD + Microservices + Team Topologies + Conway's Law | Answering "how many microservices?" and "who owns the data?" |
| [08-trade-offs-and-anti-patterns.md](08-trade-offs-and-anti-patterns.md) | Anemic Domain Model, God Aggregate, when NOT to use DDD | Demonstrating DDD depth: trade-offs, not just pattern recall |

---

## Quick Decision Guide: How Much DDD Do You Need?

```
Is the domain complex? (Many business rules, edge cases, expert knowledge required?)
│
├── NO → Don't use DDD. Simple CRUD / data pipeline / infra tooling → YAGNI.
│
└── YES
    │
    Is the team small (<10 engineers) or pre-product-market fit?
    │
    ├── YES → Strategic design only:
    │         • Define Bounded Contexts (who owns what)
    │         • Build a Ubiquitous Language glossary
    │         • Draw a rough Context Map
    │         Skip tactical patterns for now.
    │
    └── NO (multiple teams, established domain knowledge)
        │
        Is this the Core Domain (your competitive advantage)?
        │
        ├── NO (Supporting / Generic subdomain) → Strategic only, or buy/outsource
        │
        └── YES → Full DDD:
                  • Strategic: Bounded Contexts + Context Map + Subdomains
                  • Tactical: Aggregates + Value Objects + Domain Events + Repositories
                  • Architectural: Hexagonal Architecture
                  • Organisational: Team Topologies alignment + Event Storming
```

---

## DDD Complexity Scale

| Domain complexity | Team maturity | Recommended DDD depth |
|---|---|---|
| Simple CRUD (blog, todo) | Any | None — standard layered architecture |
| Medium (e-commerce MVP) | Growing | Strategic only (Bounded Contexts + Ubiquitous Language) |
| High (fintech, healthcare, insurance) | Experienced | Full tactical design in Core Domain |
| Platform scale (FAANG) | Senior+ | Full DDD + Hexagonal + Team Topologies alignment |

---

## Patterns by Concern

### Strategic (Organisation and Boundaries)
- [Bounded Contexts](02-strategic-design.md) — the primary architectural unit in DDD
- [Subdomains](02-strategic-design.md) — Core / Supporting / Generic classification
- [Context Map Patterns](03-context-map-patterns.md) — how contexts relate and integrate

### Tactical (Domain Model Internals)
- [Aggregates & Aggregate Roots](04-tactical-design.md) — transactional consistency boundary
- [Entities & Value Objects](04-tactical-design.md) — identity and immutability
- [Domain Services, Repositories, Factories](04-tactical-design.md) — the supporting cast

### Architectural (Code Structure)
- [Hexagonal Architecture](05-hexagonal-and-clean-architecture.md) — Ports & Adapters
- [Clean Architecture](05-hexagonal-and-clean-architecture.md) — concentric rings, Dependency Rule
- [Onion Architecture](05-hexagonal-and-clean-architecture.md) — variant of Clean Architecture

### Organisational (People and Process)
- [Event Storming](06-event-storming-and-discovery.md) — collaborative domain discovery
- [Team Topologies alignment](07-ddd-microservices-and-teams.md) — stream-aligned teams per Bounded Context
- [Conway's Law + Inverse Conway Manoeuvre](07-ddd-microservices-and-teams.md)

---

## Cross-Cutting Reference Matrix

| Concern | Primary file | Supporting files |
|---|---|---|
| Microservice boundary definition | [02-strategic-design.md](02-strategic-design.md) | [07-ddd-microservices-and-teams.md](07-ddd-microservices-and-teams.md) |
| Legacy system integration | [03-context-map-patterns.md](03-context-map-patterns.md) | [strangler-fig.md](../../CloudArchitecture/patterns/strangler-fig.md) |
| Team structure and ownership | [07-ddd-microservices-and-teams.md](07-ddd-microservices-and-teams.md) | [06-event-storming-and-discovery.md](06-event-storming-and-discovery.md) |
| Service testability | [05-hexagonal-and-clean-architecture.md](05-hexagonal-and-clean-architecture.md) | [04-tactical-design.md](04-tactical-design.md) |
| Stakeholder alignment | [06-event-storming-and-discovery.md](06-event-storming-and-discovery.md) | [02-strategic-design.md](02-strategic-design.md) |
| When not to use DDD | [08-trade-offs-and-anti-patterns.md](08-trade-offs-and-anti-patterns.md) | [01-philosophy-and-ddd-bible.md](01-philosophy-and-ddd-bible.md) |
| Async domain events | [04-tactical-design.md](04-tactical-design.md) | [LLD: Domain Events](../../LLD/design-patterns/modern/31-domain-events.md) |
| Distributed workflows | [04-tactical-design.md](04-tactical-design.md) | [LLD: Saga](../../LLD/design-patterns/modern/26-saga.md) |

---

## Related Sections

- [Architecture/decisions/](../decisions/) — ADRs that apply DDD principles to real decisions
- [LLD/design-patterns/modern/](../../LLD/design-patterns/modern/) — CQRS, Saga, Outbox, Domain Events (tactical DDD patterns)
- [CloudArchitecture/patterns/strangler-fig.md](../../CloudArchitecture/patterns/strangler-fig.md) — incremental monolith decomposition using Bounded Context seams
- [CloudArchitecture/patterns/event-driven-architecture.md](../../CloudArchitecture/patterns/event-driven-architecture.md) — EDA as DDD's async integration mechanism
- [Books/summaries/](../../Books/summaries/) — Evans (blue book) and Vernon (red book) are the primary references
