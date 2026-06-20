# Engineering Best Practices — FAANG Production Standards

Principal engineers are not just expected to write good code — they are expected to set the standard for how an entire engineering organisation writes and operates code. This directory covers the cross-cutting engineering disciplines that distinguish senior from principal engineer work.

---

## Files

| File | Contents | Reach for this when... |
|---|---|---|
| [01-code-review-standards.md](01-code-review-standards.md) | Review checklist (author + reviewer), comment quality, FAANG review culture (Google/Meta/Amazon), automated gates, handling disagreements, review metrics | Setting up review culture; coaching reviewers; defining what "LGTM" means |
| [02-java-best-practices.md](02-java-best-practices.md) | Immutability, Optional, concurrency (CompletableFuture, thread pools, lock-free DS), memory management, JVM tuning, API design, testing standards | Java system design; diagnosing Java production incidents; LLD in Java |
| [03-rest-api-best-practices.md](03-rest-api-best-practices.md) | Resource naming, HTTP semantics, status codes, pagination (cursor vs offset), versioning strategy, idempotency, security, rate limiting, contract testing | Designing new APIs; reviewing API proposals; API versioning decisions |
| [04-observability-monitoring.md](04-observability-monitoring.md) | Four Golden Signals, RED/USE methods, SLI/SLO/error budgets, distributed tracing, alerting design, multi-window burn rate, AWS observability stack | Designing monitoring for a new system; SLO definitions; alert design |
| [05-logging-best-practices.md](05-logging-best-practices.md) | Structured logging (JSON), log level standards, MDC correlation, PII/secret exclusions, sampling strategy, log aggregation, retention tiers, Logback config | Logging strategy; GDPR compliance; debugging production incidents |
| [06-configuration-management.md](06-configuration-management.md) | Secret vs config taxonomy, AWS Secrets Manager, HashiCorp Vault, feature flags (LaunchDarkly/Unleash), validation-at-startup, configuration drift, twelve-factor | Rolling out features safely; secrets management; environment-specific config |
| [07-engineering-standards.md](07-engineering-standards.md) | Test pyramid, security-by-default (OWASP), threat modelling (STRIDE), dependency management, ADRs, incident management, post-mortems, production readiness checklist | New service launch; incident post-mortem; building engineering culture |

---

## Quick Decision Guide

**"My team's PRs have 5 review cycles on average"**
→ [01-code-review-standards.md](01-code-review-standards.md): pre-review design alignment, PR size standards, comment classification

**"How do I optimise a Java service that is GC-pausing under load?"**
→ [02-java-best-practices.md](02-java-best-practices.md): JVM flags, GC tuning (G1GC vs ZGC), heap dump analysis

**"How do I handle breaking API changes with 50 consumers?"**
→ [03-rest-api-best-practices.md](03-rest-api-best-practices.md): versioning strategy, additive-only changes, sunset headers

**"We're getting paged 20 times a night; half the alerts are noise"**
→ [04-observability-monitoring.md](04-observability-monitoring.md): SLO burn rate alerting, alert quality standards, P1–P4 taxonomy

**"A PII field was logged in production and a GDPR request came in"**
→ [05-logging-best-practices.md](05-logging-best-practices.md): what not to log, log masking, retention policy

**"We need to roll out a risky feature to 100M users safely"**
→ [06-configuration-management.md](06-configuration-management.md): feature flag lifecycle, canary rollout, kill switches

**"A new service is going to production next sprint — what's the checklist?"**
→ [07-engineering-standards.md](07-engineering-standards.md): production readiness checklist (observability, reliability, security, ops)

---

## FAANG Company Practices Reference

| Company | Known for | File |
|---|---|---|
| **Google** | SRE, SLO/error budgets, blameless post-mortems, design docs | [04](04-observability-monitoring.md), [07](07-engineering-standards.md) |
| **Meta** | Differential culture (small commits), feature flags everywhere | [01](01-code-review-standards.md), [06](06-configuration-management.md) |
| **Amazon** | Dive Deep, Leadership Principles in PR review, Operational Excellence | [01](01-code-review-standards.md), [07](07-engineering-standards.md) |
| **Netflix** | Freedom & Responsibility, chaos engineering, surgical reviews | [01](01-code-review-standards.md), [04](04-observability-monitoring.md) |
| **Stripe** | API versioning discipline, idempotency keys, developer experience | [03](03-rest-api-best-practices.md), [06](06-configuration-management.md) |

---

## Cross-Links to Other Repository Sections

| Topic | Where |
|---|---|
| CI/CD pipeline design | [Development/ci-cd/](../ci-cd/) |
| Git workflow and PR process | [Development/workflows/](../workflows/) |
| Incident management (on-call) | [Development/processes/](../processes/) |
| Distributed systems resilience | [Architecture/distributed-systems/](../../Architecture/distributed-systems/) |
| Service mesh observability | [CloudArchitecture/patterns/service-mesh.md](../../CloudArchitecture/patterns/service-mesh.md) |
| Resilience patterns (circuit breaker, retry) | [CloudArchitecture/patterns/resilience-patterns.md](../../CloudArchitecture/patterns/resilience-patterns.md) |
| API design (HLD level) | [HLD/](../../HLD/) |
| DDD domain model testing | [Architecture/ddd/05-hexagonal-and-clean-architecture.md](../../Architecture/ddd/05-hexagonal-and-clean-architecture.md) |
| Java LLD patterns | [LLD/design-patterns/](../../LLD/design-patterns/) |

---

## Patterns by Concern

### Quality Assurance
Code review standards → test pyramid → contract testing → production readiness checklist

### Security
OWASP Top 10 → threat modelling (STRIDE) → secrets management → input validation → PII protection in logs

### Reliability
SLO/error budgets → burn rate alerting → distributed tracing → incident management → blameless post-mortems

### Developer Productivity
Feature flags → API versioning → structured logging → configuration validation → ADR documentation
