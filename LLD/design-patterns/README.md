# Design Patterns — Master Index

All 48 patterns organized into 6 categories. Every file contains: ASCII class diagram, practical real-world example (e-commerce / platform engineering / distributed systems), implementation pseudocode, SOLID analysis, when-to-use / when-NOT-to-use, trade-offs, and a FAANG interview callout.

---

## Creational Patterns — *How objects are created*

| # | Pattern | Real-World Example | FAANG Signal |
|---|---------|-------------------|--------------|
| [01](creational/01-singleton.md) | Singleton | DB connection pool, Config service | "Single shared instance — thread-safe lazy init with double-checked locking" |
| [02](creational/02-factory-method.md) | Factory Method | Payment gateway factory (Stripe/PayPal/Braintree) | "New gateway without changing client code — OCP via factory subclassing" |
| [03](creational/03-abstract-factory.md) | Abstract Factory | Cloud infra factory (AWS vs GCP resource families) | "Families of related objects — swap entire cloud provider via config" |
| [04](creational/04-builder.md) | Builder | Order builder with promo, gift wrap, delivery slot | "Complex object assembly — separate construction from representation" |
| [05](creational/05-prototype.md) | Prototype | Marketplace product listing template cloning | "Clone expensive-to-initialize objects — prototype registry for variants" |

---

## Structural Patterns — *How objects are composed*

| # | Pattern | Real-World Example | FAANG Signal |
|---|---------|-------------------|--------------|
| [06](structural/06-adapter.md) | Adapter | Legacy payment processor → unified PaymentGateway | "Make incompatible interfaces work together — wrap without modifying" |
| [07](structural/07-bridge.md) | Bridge | Notification type × channel (Email/Push/SMS) | "Two independent hierarchies — vary abstraction and implementation separately" |
| [08](structural/08-composite.md) | Composite | Cart item tree (item, bundle, combo offer) | "Treat single objects and composites uniformly — recursive tree operations" |
| [09](structural/09-decorator.md) | Decorator | Cart pricing pipeline (discount → tax → shipping) | "Add behaviour at runtime without subclassing — stackable wrappers" |
| [10](structural/10-facade.md) | Facade | Order placement (inventory + payment + notify + ship) | "Single entry point hiding subsystem complexity — simplify client code" |
| [11](structural/11-flyweight.md) | Flyweight | Product variant SKUs sharing immutable metadata | "Share intrinsic state — 100K SKUs, O(1) memory per unique metadata object" |
| [12](structural/12-proxy.md) | Proxy | Service registry proxy with cache + circuit breaker | "Control access — add caching, auth, lazy load, circuit breaking transparently" |

---

## Behavioral Patterns — *How objects communicate*

| # | Pattern | Real-World Example | FAANG Signal |
|---|---------|-------------------|--------------|
| [13](behavioral/13-chain-of-responsibility.md) | Chain of Responsibility | Promo eligibility pipeline (coupon → loyalty → flash sale) | "Decouple sender from receiver — each handler decides to handle or pass on" |
| [14](behavioral/14-command.md) | Command | Cart operations with undo/redo (add/remove/apply-promo) | "Encapsulate request as object — enables queuing, logging, undo" |
| [15](behavioral/15-iterator.md) | Iterator | Cursor-based paginated product catalog API | "Traverse without exposing internals — uniform interface over any collection" |
| [16](behavioral/16-mediator.md) | Mediator | Checkout form: promo ↔ total ↔ payment coordination | "Reduce coupling — components talk through mediator, not directly" |
| [17](behavioral/17-memento.md) | Memento | Cart state save/restore for guest→login merge | "Capture and restore state without violating encapsulation" |
| [18](behavioral/18-observer.md) | Observer | OrderPlaced → email + push + inventory + analytics | "One-to-many event fan-out — publisher unaware of subscriber count" |
| [19](behavioral/19-state.md) | State | Order state machine (Pending→Confirmed→Shipped→Returned) | "Replace conditionals with state objects — invalid transitions are impossible" |
| [20](behavioral/20-strategy.md) | Strategy | Promo discount engine (%, BOGO, fixed, bundle) | "Swap algorithm at runtime — promo type loaded from config, not if-else chain" |
| [21](behavioral/21-template-method.md) | Template Method | Payment processing: authorize→capture→notify→audit | "Define skeleton, override steps — common flow, provider-specific steps" |
| [22](behavioral/22-visitor.md) | Visitor | Cart visitor: tax + discount + shipping per item | "Add operations to objects without modifying them — double dispatch" |
| [23](behavioral/23-interpreter.md) | Interpreter | Promo rule DSL: "BUY 2 GET 1 ON category:electronics" | "Parse and evaluate a grammar — composable expression tree" |

---

## Modern / Enterprise Patterns — *Distributed and domain-driven*

| # | Pattern | Real-World Example | FAANG Signal |
|---|---------|-------------------|--------------|
| [24](modern/24-repository.md) | Repository | Product catalog: Redis → PostgreSQL → Elasticsearch | "Decouple domain from data source — swap storage without changing business logic" |
| [25](modern/25-cqrs.md) | CQRS | Order service: write model vs read projections | "Separate command and query models — optimize each independently" |
| [26](modern/26-saga.md) | Saga | Distributed order: reserve → charge → ship + compensation | "Distributed transaction without 2PC — choreography or orchestration" |
| [27](modern/27-event-sourcing.md) | Event Sourcing | Account ledger as append-only event log | "State = fold of events — full audit trail, any past state reconstructible" |
| [28](modern/28-outbox-pattern.md) | Outbox Pattern | Reliable Kafka publish from order service via DB outbox | "Exactly-once event publish — same DB transaction as business write" |
| [29](modern/29-circuit-breaker.md) | Circuit Breaker | Payment service: Closed→Open→Half-Open | "Fail fast — stop cascading failures, allow self-healing" |
| [30](modern/30-specification.md) | Specification | Product filter: category AND price AND rating AND stock | "Composable business rules — unit-testable, combinable predicates" |
| [31](modern/31-domain-events.md) | Domain Events | OrderPlaced → inventory, loyalty, email bounded contexts | "Decouple bounded contexts — domain logic raises events, not direct calls" |
| [32](modern/32-unit-of-work.md) | Unit of Work | Commit Order + Inventory + Payment in one transaction | "Track changes across repos — single atomic commit, rollback all on failure" |
| [38](modern/38-object-pool.md) | Object Pool | DB connection pool — 20 reused connections serve 10K req/s | "Pre-allocate expensive resources — borrow, use, return; HikariCP + PgBouncer in production" |
| [39](modern/39-scatter-gather.md) | Scatter-Gather | Product page: prices + inventory + ratings fetched in parallel | "Fan out to N services concurrently; aggregate within a deadline — serial 450ms → parallel 55ms" |
| [40](modern/40-idempotent-consumer.md) | Idempotent Consumer | OrderPlaced Kafka event safe under redelivery via Redis dedup | "At-least-once safe — dedup store keyed on message ID prevents double-charge / double-email" |
| [41](modern/41-dead-letter-queue.md) | Dead Letter Queue | Poison-pill orders quarantined after 3 retry failures | "Quarantine unprocessable messages — main queue unblocked; inspect, fix, replay from DLQ" |

---

## Infrastructure / Resource Management Patterns — *Concurrency, resource lifecycle, distributed coordination*

| # | Pattern | Real-World Example | FAANG Signal |
|---|---------|-------------------|--------------|
| [42](infrastructure/42-rate-limiter.md) | Rate Limiter | API gateway: 1,000 req/min per API key (Token Bucket + Redis) | "Token Bucket = standard; Sliding Window Counter = best balance; Redis Lua for atomicity" |
| [43](infrastructure/43-leader-election.md) | Leader Election | Distributed cron: exactly one pod runs DailyReportJob across 10 replicas | "Redis SET NX for advisory; etcd/ZK for split-brain safety; Kafka partition leader uses Raft" |
| [44](infrastructure/44-read-write-lock.md) | Read-Write Lock | Product catalog: 10K reads/s, 10 writes/s — concurrent readers, exclusive writer | "ReentrantReadWriteLock(fair=true) prevents starvation; StampedLock for 99%+ read workloads" |

---

## Functional Programming Patterns — *FP primitives adopted in JS, Python, Java, Kotlin*

| # | Pattern | Intent | Interview Frequency |
|---|---------|--------|---------------------|
| [33](functional/33-functor.md) | Functor | Map a function over a wrapped value (`Array.map`, `Optional.map`, `Stream.map`) | Common |
| [34](functional/34-monad.md) | Monad | Chain computations that return wrapped values without double-nesting (`flatMap`, `thenCompose`) | Common |
| [35](functional/35-maybe-option.md) | Maybe / Option | Null-safe container — explicit absence without null (`Optional<T>`, Kotlin `?`, `?.`) | Common |
| [36](functional/36-either.md) | Either | Typed error as a value — Railway-Oriented Programming (`Right(value)` / `Left(error)`) | Occasional |
| [37](functional/37-function-composition.md) | Function Composition | Build pipelines from pure functions (`andThen`, `pipe`, `compose`) | Common |
| [38](functional/38-currying-partial-application.md) | Currying & Partial Application | Fix arguments to produce specialised functions — FP-style DI | Occasional |
| [39](functional/39-immutable-data.md) | Immutable Data | Prevent mutation — Java records, Kotlin `data class`, Python frozen dataclass | Common |
| [40](functional/40-lazy-evaluation.md) | Lazy Evaluation | Defer computation — `Stream`, Kotlin `Sequence`, Python generators, JS `function*` | Common |
| [41](functional/41-memoization.md) | Memoization | Cache pure function results by input — `@lru_cache`, `by lazy`, `computeIfAbsent` | Common |

---

## Pattern Selection Guide

```
OBJECT CREATION PROBLEM?
  → One instance needed globally       → Singleton
  → Create objects by type/config      → Factory Method
  → Families of related objects        → Abstract Factory
  → Complex multi-step object assembly → Builder
  → Clone existing objects             → Prototype

OBJECT COMPOSITION PROBLEM?
  → Incompatible interface to wrap     → Adapter
  → Two independent dimensions        → Bridge
  → Tree structures, recursive ops    → Composite
  → Add behaviour dynamically         → Decorator
  → Simplify complex subsystem        → Facade
  → Many similar objects, low memory  → Flyweight
  → Control access / add cross-cuts   → Proxy

OBJECT COMMUNICATION PROBLEM?
  → Chain of handlers, one processes  → Chain of Responsibility
  → Encapsulate request, support undo → Command
  → Traverse collection uniformly     → Iterator
  → Reduce N×N coupling to N+N       → Mediator
  → Save/restore state                → Memento
  → 1-to-many event notification      → Observer
  → Behaviour changes with state      → State
  → Swap algorithm at runtime         → Strategy
  → Common skeleton, vary steps       → Template Method
  → New op on many types, no change   → Visitor
  → Parse and evaluate grammar        → Interpreter

DISTRIBUTED SYSTEM PROBLEM?
  → Decouple domain from storage      → Repository
  → Separate read/write models        → CQRS
  → Distributed transaction           → Saga
  → Full audit trail / time travel    → Event Sourcing
  → Reliable event publish            → Outbox Pattern
  → Prevent cascading failures        → Circuit Breaker
  → Composable business rules         → Specification
  → Cross-context domain integration  → Domain Events
  → Multi-repo atomic transaction     → Unit of Work
  → Reuse expensive resources         → Object Pool
  → Parallel fan-out + aggregate      → Scatter-Gather
  → Safe under broker redelivery      → Idempotent Consumer
  → Quarantine bad messages           → Dead Letter Queue

INFRASTRUCTURE / RESOURCE PROBLEM?
  → Bound inbound request rate        → Rate Limiter
  → One coordinator in a cluster      → Leader Election
  → Concurrent reads, rare writes     → Read-Write Lock

FUNCTIONAL PROGRAMMING PROBLEM?
  → Transform value inside container  → Functor (map)
  → Chain ops that return wrappers    → Monad (flatMap)
  → Represent absence without null    → Maybe / Option
  → Typed error without exceptions    → Either (Railway)
  → Build pipeline of pure functions  → Function Composition
  → Specialise a general function     → Currying / Partial Application
  → Prevent mutation / thread safety  → Immutable Data
  → Defer or stream large sequences   → Lazy Evaluation
  → Cache repeated pure-fn calls      → Memoization
```
