# Trade-off: Monolith vs Microservices

**Category**: HLD · Architecture Decision · Technical Strategy  
**FAANG interview trigger**: "Would you design this as a monolith or microservices?" / "When would you choose to NOT use microservices?" / "How do you decide when to split a service?"

---

## Context

Microservices are not the default right answer. They are an architectural style with genuine benefits at scale — and genuine costs at any scale. The principal engineer answer starts with "it depends" backed by a concrete framework for when each applies. Defaulting to microservices without analysis is a red flag at the PE level.

---

## Definitions

**Monolith**: a single deployable unit containing all application functionality. Can be internally modular (well-factored monolith) or a "big ball of mud" (tangled monolith). The deployment boundary is the module boundary.

**Microservices**: an architecture where each service is independently deployable, independently scalable, and owns its own data store. Services communicate over a network (HTTP/gRPC/messaging).

**Distributed Monolith**: the worst of both worlds — multiple services that are still tightly coupled (e.g., shared database, synchronous dependency chains that require coordinated deployment). Achieves microservices' operational complexity without the benefits.

---

## Monolith Benefits

**1. Operational simplicity**
One service to deploy, monitor, debug, and scale. No inter-service network calls to trace. No distributed transaction management. Stack traces show the full call chain. IDE refactoring works across the whole system.

**2. No distributed systems problems**
A function call within a monolith is always consistent, always fast (no network), and always available (if the process is up). Microservices introduce partial failure, network latency, and consistency challenges that don't exist in a monolith.

**3. Easier to refactor**
Changing an interface across a monolith is an editor operation. Changing an interface between microservices requires versioning, backward compatibility, and coordination across teams.

**4. Development velocity for small teams**
A 5-engineer team deploying one service moves faster than the same team managing 10 services with deployment pipelines, separate monitoring, and cross-service coordination overhead.

**5. Transactional consistency**
A single database transaction spans the entire operation. No Saga patterns, no distributed transactions, no compensating transactions.

**Real examples**: Stack Overflow runs on a monolith serving millions of requests/day with a team of ~100 engineers. Shopify's core platform was a monolith until they had thousands of engineers. Basecamp is a monolith by design choice.

---

## Microservices Benefits

**1. Independent deployability**
Each service deploys on its own schedule. A change to the recommendation engine doesn't require a checkout service deployment. This is the primary driver for most FAANG microservices adoption.

**2. Independent scalability**
Scale the read-heavy product catalog independently from the write-heavy order service. Allocate GPUs to the ML inference service without provisioning GPUs for everything.

**3. Technology heterogeneity**
The recommendation service uses Python + PyTorch. The payment service uses Java + strict type safety. The search service uses Elasticsearch-specific clients. Each service uses the best tool for its job.

**4. Team autonomy**
Conway's Law: systems mirror the communication structure of the organizations that build them. Microservices enable team boundaries to be service boundaries — teams can move at different speeds without stepping on each other.

**5. Fault isolation**
A bug in the recommendation service crashes that service, not the entire platform. With good circuit breakers and fallbacks, the rest of the system degrades gracefully.

**Real examples**: Netflix (~1000 services), Amazon (~500+ services for Amazon.com), Uber (2000+ services). All cite team autonomy and independent scalability as primary motivations.

---

## When Each Applies

### Default to a Monolith When:

1. **Team is small (<15 engineers)**: microservices overhead (service mesh, distributed tracing, separate deployments) consumes 20-30% of engineering time that a small team can't afford.

2. **Product-market fit is not established**: you'll be refactoring frequently. Refactoring within a monolith is fast. Refactoring across services is coordination-heavy.

3. **Domain boundaries are unclear**: if you don't know where the seams are yet, microservices that cut along the wrong seams become a distributed monolith. Wait until boundaries emerge from the codebase's natural fracture lines.

4. **You don't have the operational maturity**: microservices require sophisticated CI/CD (per-service pipelines), distributed tracing (Jaeger, Zipkin), service mesh (Istio/Linkerd), and container orchestration (Kubernetes). If your team hasn't operated these at scale, the operational overhead can be crippling.

5. **Consistency is critical across the entire operation**: financial ledgers, transactional systems where multi-entity ACID is required. Microservices make this much harder (Saga patterns, eventual consistency).

### Default to Microservices When:

1. **Team is large and growing (>50 engineers)**: monolith deployment coordination becomes a bottleneck. 50 engineers sharing one deploy pipeline creates queues, broken builds blocking everyone, and "deploy freeze" periods.

2. **Independent scalability requirements**: one component needs 100× the compute of another, or needs different hardware (GPU, high-memory), or needs to scale to a different tier.

3. **Polyglot technology requirements**: different components genuinely benefit from different stacks and the benefits outweigh integration overhead.

4. **Different reliability/SLO requirements**: the payment service needs 99.99% uptime; the notification service needs 99.9%. Coupling them in a monolith drags the high-reliability service down.

5. **Regulatory or security isolation**: payment card data (PCI-DSS), healthcare data (HIPAA) often requires physical isolation — a separate deployment zone that a monolith can't provide.

---

## The Migration Path

The right answer for most companies is: **start as a modular monolith, extract services when the pain is real.**

**Modular monolith**: well-defined internal modules with explicit interfaces, no circular dependencies, ready to be extracted as services when needed. The internal module structure is the seam along which you'll eventually cut.

**When to extract a service (the pain signals):**
- A specific team's feature velocity is blocked by another team's deploy schedule
- A specific component needs to scale independently (10× more than the rest)
- A component has failed and cascaded to the entire system
- A component has fundamentally different technology requirements
- Regulatory requirements force physical isolation

**The Strangler Fig pattern**: extract services incrementally rather than rewriting from scratch. Route traffic through a proxy; move functionality behind the proxy piece by piece. The monolith shrinks while the new services grow.

---

## Comparison Table

| Dimension | Monolith | Microservices |
|-----------|---------|---------------|
| **Deploy complexity** | Low (one artifact) | High (per-service pipelines) |
| **Operational overhead** | Low | High (service mesh, tracing, discovery) |
| **Inter-team coordination** | High (shared codebase) | Low (API contracts) |
| **Debugging** | Easy (local call stack) | Hard (distributed traces) |
| **Consistency** | Easy (single DB transaction) | Hard (Saga, eventual consistency) |
| **Scalability** | Scale the whole thing | Scale individual services |
| **Technology diversity** | Limited | Full freedom |
| **Fault isolation** | None (one failure = full outage) | Circuit breakers provide isolation |
| **Development speed (small team)** | Faster | Slower |
| **Development speed (large team)** | Slower (coordination) | Faster (autonomy) |

---

## Anti-Pattern: Distributed Monolith

A distributed monolith has microservices' operational costs without their benefits. You have a distributed monolith when:
- Services share a database (coupling through data layer)
- Services require coordinated deployment (can't deploy one without the others)
- Services have synchronous chains 5+ levels deep (A→B→C→D→E), making any failure cascade
- "Microservices" were extracted based on technical layers (data layer, business logic layer, API layer) rather than business domains

**How to avoid it**: follow Domain-Driven Design's bounded context principle — each service owns its domain data and exposes it only through APIs. No shared databases.

---

## FAANG Interview Callouts

**Demonstrate this thinking:**
- "Given this is a new product with a 10-engineer team, I'd start with a well-structured monolith. The risk of early microservices is a distributed monolith — all the complexity with none of the benefits. I'd define clear module boundaries now that become service boundaries later."
- "For Twitter's timeline at 300M users with a dedicated timelines team, microservices are the right call — the timelines team needs to deploy independently, use a custom storage model, and scale differently from the tweet ingestion path."
- "The distinction I'd make is between 'independently deployable' and 'independently scalable' — those are different reasons to split a service and lead to different architectural decisions."

**Red flags:**
- "I'd use microservices because they scale better" — microservices scale independently; a monolith can also scale (vertically or as a horizontally-replicated cluster)
- Proposing microservices for a new product without calling out the operational overhead
- Not mentioning the distributed monolith anti-pattern
- "A monolith can't handle this scale" — Stack Overflow, Shopify, and Basecamp disprove this at significant scale

**The PM-friendly framing**: "Microservices are about organizational scalability (team autonomy) as much as technical scalability. If you're not at the scale where team coordination is the bottleneck, you're paying microservices costs without getting the primary benefit."
