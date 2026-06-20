# Role: Operations / SRE / Reliability Engineer

## Core Identity

Operations (or SRE at FAANG scale) owns **system reliability in production**. They ensure the software engineers build actually works at scale, under load, and through failures. SRE is Google's formalization of this role — a software engineer who applies engineering discipline to operations problems.

At FAANG scale, this means owning SLOs, incident response, capacity planning, and the reliability roadmap for systems serving hundreds of millions of users globally.

---

## Primary Accountabilities

### 1. Service Level Objectives (SLOs)
- Define SLOs jointly with engineering (availability, latency, error rate, throughput)
- Own the error budget: track burn rate, alert on depletion, pause feature work when budget is exhausted
- Review SLO breaches and trigger reliability work orders
- Example SLO stack:
  - SLI: P99 latency measured at load balancer
  - SLO: P99 < 200ms for 99.9% of requests over 30 days
  - Error budget: 43.2 minutes downtime per month

### 2. Incident Management
- Be the first responder or incident commander for Sev1/Sev2 incidents
- Own the incident lifecycle: detect → mitigate → resolve → post-mortem
- Maintain on-call rotation, runbooks, and escalation paths
- Drive mean time to detect (MTTD) and mean time to recover (MTTR) down over time

### 3. Capacity Planning
- Forecast traffic growth and provision infrastructure proactively
- Load test systems before peak events (Black Friday, product launches, sporting events)
- Own auto-scaling configurations and headroom policies
- Manage cloud costs through rightsizing, reserved instances, spot usage

### 4. Production Hardening
- Drive production readiness reviews (PRRs) before new services launch
- Require runbooks, alerts, dashboards, and rollback procedures as launch gates
- Enforce chaos engineering practices — deliberately inject failures to find weaknesses
- Review architectures for single points of failure before they ship

### 5. Toil Reduction
- SRE philosophy: toil (manual, repetitive, automatable work) should be < 50% of time
- Automate runbooks: turn manual escalation steps into automated remediation
- Own observability infrastructure: metrics pipeline, tracing, logging, alerting

### 6. Post-Mortem & Continuous Improvement
- Facilitate blameless post-mortems after every Sev1/Sev2
- Track action items from post-mortems with owners and deadlines
- Publish reliability trends to engineering leadership
- Prevent repeat incidents by identifying systemic fixes, not just local patches

---

## SRE vs Traditional Ops vs DevOps

| Dimension | Traditional Ops | SRE (Google Model) | DevOps |
|-----------|----------------|-------------------|--------|
| Primary tool | Manual processes, tickets | Software, automation | Culture + tooling |
| Relationship with dev | Adversarial (wall of confusion) | Embedded partnership | Merged (no wall) |
| On-call model | Ops team only | Shared dev + SRE | Developers own it |
| Toil tolerance | High (accepted) | < 50% hard limit | Minimize, automate |
| Error budget | Not used | Core governance mechanism | Varies |
| Hiring bar | IT background | Software engineer | Engineer |

---

## Operations Artifacts

| Artifact | Purpose |
|----------|---------|
| Runbook | Step-by-step response to specific alerts |
| Post-Mortem | Root cause, timeline, action items |
| Capacity Plan | Traffic forecast + infrastructure headroom |
| SLO Dashboard | Real-time error budget tracking |
| On-Call Rotation | Who responds, escalation chain, rotation schedule |
| PRR Checklist | Production readiness gates before service launch |
| Chaos Engineering Report | Blast radius analysis of injected failures |

---

## Key Metrics Operations Owns

| Metric | Target (typical FAANG) |
|--------|----------------------|
| Availability | 99.9% – 99.999% depending on service tier |
| P99 Latency | Service-specific; often 50–200ms at API layer |
| MTTD | < 5 minutes for Sev1 |
| MTTR | < 30 minutes for Sev1 |
| Error Budget Burn Rate | < 1x (budget not depleting faster than replenishing) |
| On-Call Hours (toil) | < 50% of SRE's time |
| Change Failure Rate | < 5% (DORA metric) |
| Deployment Frequency | > 1/day (DORA elite) |

---

## Operations ↔ Principal Engineer Interface

Principal engineers interact with Operations on:

### Design Reviews for Reliability
- Before finalizing an HLD, principal engineers must answer Ops questions:
  - "What happens when this dependency is down?"
  - "What's the graceful degradation story?"
  - "Where are the circuit breakers and bulkheads?"
  - "What does failure look like to the user?"

### SLO Negotiation
- Principal engineers help define technically achievable SLOs
- Operations holds the line on non-negotiable SLO bars
- Tension: product wants 99.99%; principal engineers calculate the cost and propose 99.9% with graceful degradation

### Incident Root Cause
- During major incidents, Ops leads the war room; principal engineers diagnose complex system interactions
- Post-mortem: principal engineers own the architectural remediation; Ops owns the process improvement

### Production Readiness
- Ops gates launches on PRR completion
- Principal engineers are often required to sign off on architecture sections of the PRR
- Common PRR checklist items principal engineers own:
  - Dependency failure modes documented
  - Rate limiting in place
  - Circuit breakers configured
  - Distributed tracing instrumented
  - Capacity estimate reviewed by Ops

---

## Failure Mode Taxonomy (Operations Lens)

| Failure Type | Cause | Detection | Mitigation |
|-------------|-------|-----------|------------|
| Cascading failure | Dependency down, no circuit breaker | Error rate spike, latency surge | Circuit breaker, bulkhead, timeout |
| Resource exhaustion | Memory leak, thread pool full | OOM alert, thread pool saturation | Heap dump, restart with canary |
| Data corruption | Bad deploy, migration bug | Data validation alerts, user complaints | Rollback, point-in-time restore |
| Traffic spike | Marketing event, bot attack | QPS anomaly detection | Auto-scaling, rate limiting, CDN |
| Configuration drift | Manual change, bad deploy | Config diff alerts | IaC enforcement, change auditing |
| Thundering herd | Cold start after outage | Latency spike on recovery | Jitter, cache warm-up, request shedding |

---

## On-Call Design Principles (Principal Engineer Must Know)

1. **Pager equity**: Alert only the person who can act — not everyone in the org
2. **Actionable alerts**: Every alert needs a runbook link; alerts without runbooks are noise
3. **Toil tracking**: Measure on-call burden per person per week; prevent burnout
4. **Escalation paths**: Primary → Secondary → EM → VP — each with defined SLA
5. **Alert fatigue**: Reduce false positives aggressively; alert on symptoms (user-facing), not causes (CPU %)
6. **Post-mortem cadence**: Every Sev1 gets a post-mortem; Sev2s get one if they repeat

---

## FAANG Operations Patterns

### Google SRE
- SREs are software engineers who embed with product teams
- 50% cap on toil; above cap, SREs can refuse on-call duty — forces automation
- Error budget is a contract between product and SRE: violate it → freeze feature work
- Chaos engineering via DiRT (Disaster Recovery Testing) — annual large-scale drills

### Amazon
- "You build it, you run it" — development teams own production
- No separate SRE function at many Amazon teams; DevOps model
- Extensive use of CloudWatch, X-Ray, AWS-native observability
- Operational Excellence is a Well-Architected pillar with formal review process

### Netflix
- Chaos Monkey, Chaos Kong — Netflix invented chaos engineering
- Simian Army: suite of tools that randomly kill instances, regions, services
- No downtime tolerance — Netflix is always-on globally
- SRE called "Edge Engineering" and "Reliability Engineering" — small teams, high automation

### Meta
- "Production Engineering" (PE) is Meta's SRE equivalent
- PE engineers are full-stack: own everything from hardware to application layer
- FBOSS — Meta wrote its own network OS; PEs own networking layer too

---

## Common Operations Anti-Patterns

| Anti-Pattern | Impact | Remedy |
|-------------|--------|--------|
| Alert on causes, not symptoms | Alert fatigue, missed user-facing issues | Alert on error rate / latency (SLIs), not CPU / memory |
| No runbooks | Long MTTR, tribal knowledge | Require runbooks as PRR gate |
| On-call hero culture | Burnout, single point of failure | Enforce rotation, document everything |
| Post-mortem blame | No learning, defensive culture | Blameless post-mortems; ask "what let this happen?" |
| Manual deployments | Human error, slow recovery | Automate; every deploy is scripted |
| Ignoring error budget | Death by 1000 cuts | Error budget as hard gate on feature work |

---

## Interview Angles for Principal Engineers

**"How do you design for operational excellence from day one?"**
- Embed SLO definition in the initial design doc (not as an afterthought)
- Require PRR as a launch gate before any new service goes to prod
- Instrument distributed tracing, structured logging, and metrics in the service template
- Design failure modes explicitly: circuit breakers, timeouts, bulkheads in the HLD

**"Tell me about a major incident you led or contributed to resolving."**
- Follow: detect (MTTD) → mitigate (stop the bleeding) → resolve (root cause) → prevent (systemic fix)
- Quantify: "$X million revenue impact, resolved in Y minutes"
- Show architectural insight: "Root cause was missing circuit breaker on dependency Z — fixed it and added to PRR checklist for all future services"

**"How do you balance reliability investment vs feature velocity?"**
- Error budget is the mechanism — when budget is healthy, ship features; when depleted, invest in reliability
- Make the cost of unreliability concrete: "$50K per 9 of availability, last quarter we left 2 nines on the table"
- Principal engineers champion a reliability roadmap that earns velocity back
