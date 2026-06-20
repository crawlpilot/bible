# Hexagonal, Clean & Onion Architecture

## Overview
Three independent architects arrived at the same insight at different times:

- **Alistair Cockburn** (2005): Hexagonal Architecture (Ports & Adapters)
- **Jeffrey Palermo** (2008): Onion Architecture
- **Robert C. Martin** (2017): Clean Architecture

The insight is identical in all three: **business logic must not depend on infrastructure**. The domain model should be the most stable part of the system. Databases, frameworks, HTTP clients, and message brokers are all implementation details — plugins into the domain, not the other way around.

This principle is the architectural foundation for DDD tactical patterns: it is the structure that keeps the domain layer pure, testable, and independently evolvable.

---

## The Dependency Rule

The single principle that underlies all three architectures:

> **Source code dependencies can only point inward. Nothing in an inner layer can know anything about an outer layer.**

```
         Outermost (most volatile, most likely to change)
         ┌──────────────────────────────────────────┐
         │  Frameworks & Drivers                     │
         │  (HTTP server, ORM, message broker SDK,   │
         │   AWS SDK, test harness)                  │
         │  ┌────────────────────────────────────┐   │
         │  │  Interface Adapters                 │   │
         │  │  (REST controllers, repository     │   │
         │  │   implementations, event consumers) │   │
         │  │  ┌──────────────────────────────┐  │   │
         │  │  │  Use Cases / Application     │  │   │
         │  │  │  Services                    │  │   │
         │  │  │  ┌──────────────────────┐   │  │   │
         │  │  │  │  Entities /          │   │  │   │
         │  │  │  │  Domain Model        │   │  │   │
         │  │  │  │  (most stable)       │   │  │   │
         │  │  │  └──────────────────────┘   │  │   │
         │  │  └──────────────────────────────┘  │   │
         │  └────────────────────────────────────┘   │
         └──────────────────────────────────────────┘
         Innermost (most stable, domain knowledge)

Dependencies: → inward only
              Outer layers know about inner layers
              Inner layers know NOTHING about outer layers
```

**Consequence**: the domain model can be tested without starting a database, launching an HTTP server, or connecting to a message broker. All infrastructure is injectable and replaceable.

---

## Hexagonal Architecture (Ports & Adapters)

Alistair Cockburn's original formulation uses a hexagon not because six sides matter, but to signal that an application has **multiple equivalent entry points and exit points**, not a single front-back axis.

### The Hexagon

```
                         ┌─────────────────────┐
                         │   Driving Adapters   │
                         │  (call INTO the app) │
  REST Controller ──────►│                      │
  CLI Command    ──────►│      ┌──────────┐    │
  Test Harness   ──────►│      │          │    │
  Event Consumer ──────►│      │  DOMAIN  │    │
                         │      │          │    │◄──── PostgreSQL Adapter
                         │      │ (no infra│    │◄──── Kafka Producer Adapter
                         │      │ imports) │    │◄──── S3 Adapter
                         │      │          │    │◄──── SMTP Adapter
                         │      └──────────┘    │
                         │                      │
                         │   Driven Adapters    │
                         │  (called BY the app) │
                         └─────────────────────┘
```

### Ports: Interfaces Defined by the Domain

A **Driving Port** is an interface the domain *exposes* for external actors to call. A **Driven Port** is an interface the domain *requires* to be implemented by infrastructure.

```python
# domain/ports/primary.py  — Driving Port (what the app offers)
from abc import ABC, abstractmethod

class SubmitOrderUseCase(ABC):
    @abstractmethod
    def execute(self, command: SubmitOrderCommand) -> OrderId:
        ...

# domain/ports/secondary.py  — Driven Ports (what the domain requires)
class OrderRepository(ABC):
    @abstractmethod
    def save(self, order: Order) -> None: ...
    
    @abstractmethod
    def find_by_id(self, order_id: OrderId) -> Optional[Order]: ...

class PaymentGateway(ABC):
    @abstractmethod
    def authorise(self, amount: Money, card_token: str) -> AuthorisationResult: ...

class EventPublisher(ABC):
    @abstractmethod
    def publish(self, event: DomainEvent) -> None: ...
```

### Domain Use Case (Application Service)

```python
# domain/use_cases/submit_order.py
class SubmitOrderService(SubmitOrderUseCase):
    """Application Service — orchestrates domain objects and driven ports"""
    
    def __init__(
        self,
        order_repo: OrderRepository,     # driven port — injected
        payment_gw: PaymentGateway,      # driven port — injected
        event_pub: EventPublisher,       # driven port — injected
    ):
        self._orders = order_repo
        self._payments = payment_gw
        self._events = event_pub
    
    def execute(self, command: SubmitOrderCommand) -> OrderId:
        order = self._orders.find_by_id(command.order_id)
        if not order:
            raise OrderNotFoundError(command.order_id)
        
        order.submit()  # domain logic — invariant enforcement on the aggregate
        
        auth = self._payments.authorise(order.total(), command.card_token)
        if not auth.is_approved:
            order.fail_payment(auth.decline_reason)
        
        self._orders.save(order)
        
        for event in order.pull_events():
            self._events.publish(event)
        
        return order.id
```

### Adapters: Infrastructure Implementations

```python
# adapters/primary/rest_handler.py  — Driving Adapter
from fastapi import APIRouter, Depends

router = APIRouter()

@router.post("/orders/{order_id}/submit")
async def submit_order(order_id: str, body: SubmitOrderRequest,
                        use_case: SubmitOrderUseCase = Depends()):
    # Adapter: translates HTTP request into domain command
    command = SubmitOrderCommand(
        order_id=OrderId(UUID(order_id)),
        card_token=body.payment_token
    )
    result_id = use_case.execute(command)
    return {"order_id": str(result_id.value)}

# adapters/secondary/postgres_order_repo.py  — Driven Adapter
class PostgreSQLOrderRepository(OrderRepository):
    def __init__(self, session: Session):
        self._session = session
    
    def save(self, order: Order) -> None:
        # Translate domain model to ORM model — the domain never sees SQLAlchemy
        orm_order = self._to_orm(order)
        self._session.merge(orm_order)
    
    def find_by_id(self, order_id: OrderId) -> Optional[Order]:
        row = self._session.get(OrderORM, str(order_id.value))
        return self._to_domain(row) if row else None
```

### Python Project Structure

```
payments-service/
├── domain/
│   ├── model/
│   │   ├── order.py              # Order aggregate
│   │   ├── value_objects.py      # Money, OrderId, CustomerId
│   │   └── events.py             # Domain events
│   ├── ports/
│   │   ├── primary.py            # Use case interfaces (driving)
│   │   └── secondary.py         # Repository, gateway interfaces (driven)
│   └── use_cases/
│       ├── submit_order.py       # Application service
│       └── cancel_order.py
├── adapters/
│   ├── primary/
│   │   ├── rest_handler.py       # FastAPI router
│   │   ├── lambda_handler.py     # AWS Lambda driving adapter
│   │   └── sqs_consumer.py      # SQS event driving adapter
│   └── secondary/
│       ├── postgres_repo.py      # SQLAlchemy repository implementation
│       ├── stripe_gateway.py     # Stripe payment gateway adapter
│       └── sns_publisher.py      # SNS event publisher adapter
└── config/
    └── container.py              # Dependency injection wiring
```

**Key**: the `domain/` package has **zero imports** from `adapters/`, FastAPI, SQLAlchemy, boto3, or any external library. The domain layer is a pure Python module with no infrastructure dependencies.

---

## Clean Architecture (Robert C. Martin)

Clean Architecture uses four concentric rings. The Dependency Rule is identical to Hexagonal:

```
┌──────────────────────────────────────────────────────┐
│  Frameworks & Drivers (Web, DB, External services)   │
│  ┌────────────────────────────────────────────────┐  │
│  │  Interface Adapters (Controllers, Presenters,  │  │
│  │  Gateways, Repository implementations)         │  │
│  │  ┌──────────────────────────────────────────┐  │  │
│  │  │  Use Cases (Application Business Rules)  │  │  │
│  │  │  ┌────────────────────────────────────┐  │  │  │
│  │  │  │  Entities (Enterprise Business     │  │  │  │
│  │  │  │  Rules — Aggregates, Value Objects) │  │  │  │
│  │  │  └────────────────────────────────────┘  │  │  │
│  │  └──────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
```

**The Plugin Architecture**: The Entities ring doesn't know about Use Cases. Use Cases don't know about Controllers. The database is a plugin that can be swapped. The HTTP framework is a plugin. Tests can run against the domain without any infrastructure.

**Martin's key insight**: "The web is a delivery mechanism, not your application." The application is the domain and the use cases. FastAPI, Lambda handlers, SQS consumers — all are delivery mechanisms that call into the application.

---

## Onion Architecture (Jeffrey Palermo)

Onion Architecture expresses the same Dependency Rule with a slightly different layer vocabulary:

```
Domain Model (innermost — Entities, Value Objects, Aggregates)
  ↑
Domain Services (stateless, cross-aggregate logic)
  ↑
Application Services (use cases — orchestration layer)
  ↑
Infrastructure (Repository implementations, HTTP adapters, message brokers)
```

The practical difference from Clean Architecture is minor — Onion is more aligned with DDD's own layer naming. Use Onion terminology when the audience is DDD-fluent.

---

## Architecture Comparison

| Dimension | Hexagonal | Clean Architecture | Traditional N-tier |
|---|---|---|---|
| **Core idea** | Ports & Adapters | Concentric rings | Controller → Service → Repository |
| **Dependency direction** | Inward only | Inward only | Top-down (Controller knows DB) |
| **Domain purity** | Full — domain has no infra imports | Full | None — service imports ORM |
| **Testability** | Domain tests: no infra needed | Domain tests: no infra needed | Unit tests require mocking |
| **Swappability** | Any adapter can be replaced | Any outer ring can be replaced | Database and framework are baked in |
| **Complexity** | Medium — more files, more interfaces | Medium | Low — fewer abstractions |
| **When to use** | DDD Core Domain; long-lived services | Same as Hexagonal | Simple CRUD; short-lived scripts |

---

## AWS Deployment: The Adapter Advantage

The hexagonal architecture's killer property in cloud deployments: the **same domain logic runs on multiple AWS compute surfaces without change**.

```
Domain Logic (SubmitOrderService) — unchanged

├── Lambda Handler (adapter):  handler(event, ctx) → use_case.execute(...)
├── ECS FastAPI (adapter):     @router.post("/orders") → use_case.execute(...)
├── SQS Consumer (adapter):    for msg in messages: → use_case.execute(...)
└── Step Functions (adapter):  def lambda_handler → use_case.execute(...)
```

The compute surface is a plug-in choice. The domain logic is the stable core.

**Testing**: domain tests run with in-memory adapters (fake repository, fake payment gateway) in milliseconds. No `moto`, no Docker, no test database required for domain tests.

```python
def test_submit_order_raises_event():
    # All dependencies are in-memory fakes
    repo = InMemoryOrderRepository()
    gateway = FakePaymentGateway(should_approve=True)
    publisher = InMemoryEventPublisher()
    
    service = SubmitOrderService(repo, gateway, publisher)
    order_id = service.execute(SubmitOrderCommand(order_id=..., card_token=...))
    
    assert publisher.events[-1] == OrderSubmitted(order_id=order_id, ...)
```

---

## Best Practices

1. **Zero infrastructure imports in the domain layer** — if you see `import boto3` or `from sqlalchemy` in `domain/`, it is a violation
2. **Define ports (interfaces) in the domain layer** — the domain specifies what it needs; adapters implement it
3. **Application Services are thin** — orchestrate domain objects and ports; contain no business logic; have no `if/else` based on domain rules
4. **One Use Case per Application Service** — `SubmitOrderService`, `CancelOrderService`, not a monolithic `OrderService`
5. **Fake adapters for domain tests** — fast, no infrastructure setup; integration tests cover adapter correctness separately
6. **Dependency injection at the composition root** — wire adapters to ports at startup; the domain layer never instantiates its own dependencies
7. **Keep adapters thin** — adapters translate between protocol and domain; they do not contain business logic

---

## FAANG Interview Points

**"How do you structure a service so the domain logic is testable?"**: Hexagonal Architecture. The domain and application services are pure Python — no framework imports, no database imports. They depend only on port interfaces (abstract classes). In tests, I inject in-memory fakes for the repositories and gateways. Domain tests run in milliseconds with no infrastructure. Integration tests then cover the real adapters. The Dependency Rule ensures the domain can never accidentally call a real database.

**"If we switch from Postgres to DynamoDB, how much of the service do we need to rewrite?"**: With Hexagonal Architecture: only the `PostgreSQLOrderRepository` adapter is replaced with a `DynamoDBOrderRepository` adapter. The domain model, application services, and other adapters are untouched. Without it: the database is wired into every service layer, and the migration touches every file.

**"How does Hexagonal Architecture relate to DDD?"**: They are complementary. DDD defines *what* the domain model looks like (Aggregates, Value Objects, Domain Events). Hexagonal Architecture defines *where* it lives (the domain layer, isolated from infrastructure). Without hexagonal structure, DDD domain models gradually accumulate framework imports and infrastructure concerns. With it, the domain layer stays pure and the Dependency Rule enforces the separation automatically.
