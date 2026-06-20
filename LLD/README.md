# Low-Level Design (LLD)

Object-oriented design, design patterns, and component-level design. Calibrated to FAANG LLD interview rounds.

## Sub-directories

| Folder | Contents |
|--------|----------|
| `design-patterns/` | All 23 GoF patterns + modern patterns (Repository, CQRS, Saga, etc.) |
| `object-oriented/` | SOLID principles, DRY, YAGNI, clean code applied to interview problems |
| `system-components/` | LLD for common components: rate limiter, cache, message queue, elevator, parking lot |
| `code-examples/` | Runnable Java/Python/Go code for LLD problems |
| `ddd/` | Domain-Driven Design reference + full production example (Paytm/Google Pay payment platform) |

## DDD Reference — Payment Platform (Paytm / Google Pay)

The [`ddd/`](ddd/) folder is a complete, production-grade DDD implementation of a payment application. It covers:

- **Strategic Design**: Bounded contexts, context map, subdomain classification
- **Ubiquitous Language**: Per-bounded-context glossary
- **Domain Models (Java)**: Payment, Wallet, and Bill Payment aggregates with full code
- **Application Layer**: CQRS, command/query handlers, use case orchestration
- **Saga Patterns**: Choreography (UPI payment) and orchestration (wallet top-up, bill payment)
- **Infrastructure Layer**: JPA repositories, NPCI/BBPS Anti-Corruption Layers, Kafka outbox
- **Production Patterns**: Idempotency, optimistic locking, reconciliation, rate limiting, PCI-DSS

Payment types covered: **UPI**, **Card (Credit/Debit)**, **Utility Bills (BBPS)**, **Wallet**

## Grokking OOD Reference

The `Grokking the Object Oriented Design Interview.pdf` at repo root is the primary reference. Summaries go in `Books/grokking/`.

## Template

Use `/lld [problem name]` with Claude to generate a complete LLD with class diagram and pattern analysis.
