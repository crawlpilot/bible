# Role: Senior Engineer (L5 / Senior SWE)

## Core Identity

The Senior Engineer owns a **significant component or service end-to-end** — including design, implementation, testing, deployment, and ongoing operations. They are the **execution backbone** of an engineering team: autonomous enough to operate without hand-holding, experienced enough to mentor others, and skilled enough to handle ambiguity in both technical and product requirements.

At FAANG, L5 Senior SWE is the target level for most engineers after 4-8 years. It's the level where engineers stop executing tasks and start owning outcomes.

---

## Primary Accountabilities

### 1. End-to-End Component Ownership
- Own one or more services/components from design to production
- Write the design doc for new features in owned domain
- Lead implementation: break into tasks, estimate accurately, flag risks
- Own the operational health of the service: dashboards, alerts, runbooks
- Be on-call for owned services; own incident response within scope

### 2. Technical Quality
- Write production-quality code: correct, tested, observable, secure
- Own test coverage for owned components (unit, integration, contract)
- Write performant code with awareness of time/space complexity
- Perform thorough code reviews for peers — not rubber-stamp approvals
- Proactively identify and address technical debt in owned domain

### 3. Mentorship of Junior/Mid Engineers
- Pair-program with L3/L4 engineers on complex problems
- Review code with teaching intent: explain why, not just what
- Give specific, actionable feedback in performance cycles
- Help junior engineers design solutions before they implement

### 4. Cross-Team Collaboration
- Integrate with APIs and services owned by other teams
- Negotiate API contracts with neighboring teams
- Communicate blockers and dependencies clearly and early
- Write clear tickets, RFCs, and integration guides for consumers

### 5. Estimation & Delivery
- Break large features into accurate estimates (days, not months)
- Surface risks before commitment deadlines, not after
- Self-manage against sprint goals without requiring daily check-ins
- Communicate progress proactively: "This is taking longer because X; here's my plan"

---

## Senior Engineer Level Expectations (FAANG)

### What L5 Is NOT
- Not just "writes good code" — L4s write good code too
- Not just "doesn't need help" — L4 can also be independent within well-defined scope
- Not "10x velocity" — raw output is not the differentiator

### What L5 IS
| Dimension | L4 (Mid-Level) | L5 (Senior) |
|-----------|---------------|-------------|
| Scope | Task / ticket | Component / service |
| Ambiguity | Given clear specs | Resolves ambiguity independently |
| Design | Implements others' designs | Produces designs for review |
| Testing | Writes unit tests | Owns full testing strategy |
| Mentorship | Receives mentorship | Actively mentors L3/L4 |
| Impact | Team | Team + adjacent teams |
| Estimation | Task-level (hours) | Feature-level (weeks) |
| On-call | Responds to pages | Improves on-call quality |
| Technical debt | Reports it | Addresses it |

---

## Senior Engineer Artifacts

| Artifact | Purpose |
|----------|---------|
| Design Document | Feature or component design with trade-offs |
| ADR | Decision records for choices made in owned domain |
| Runbook | Operational procedure for owned service |
| Post-Mortem Contribution | Root cause analysis for incidents in owned area |
| Performance Review Input | Feedback on junior/mid engineers |
| Estimation Sheet | Breakdown of feature tasks with dependencies |
| API Documentation | Contract for services others consume |

---

## Technical Excellence at Senior Level

### Code Quality Bar
```java
// NOT senior-level: works but fragile
public void process(List<Order> orders) {
    for (Order order : orders) {
        try {
            db.save(order);
        } catch (Exception e) {
            // ignore
        }
    }
}

// SENIOR-LEVEL: correct, observable, resilient
public void process(List<Order> orders) {
    for (Order order : orders) {
        try {
            db.save(order);
            metrics.increment("order.processed");
        } catch (DatabaseException e) {
            metrics.increment("order.failed");
            log.error("Failed to persist order={} reason={}", order.id(), e.getMessage(), e);
            // Re-throw or push to DLQ — never silently swallow
            deadLetterQueue.publish(order, e);
        }
    }
}
```

### Testing Strategy Ownership
```
For owned service:
├── Unit Tests: 80%+ coverage of business logic
├── Integration Tests: all DB, queue, external service interactions
├── Contract Tests: API contract with consumers verified (Pact)
├── Performance Tests: baseline benchmarks in CI (P99 < threshold)
└── Chaos Tests: dependency failure scenarios (testcontainers)
```

### Observability Standard
A senior engineer ships no code without:
- Structured logging (JSON, with correlation ID / trace ID)
- Metrics (requests, errors, latency — RED method)
- Distributed tracing spans for all I/O operations
- Alerts for error rate > 1% and P99 > SLO threshold

---

## Mentorship Approach

### Teaching Code Review
```
NOT helpful:
"This is wrong, change it to X"

SENIOR-LEVEL:
"This will cause a race condition when two threads call concurrently 
because Map is not thread-safe. Consider ConcurrentHashMap or 
synchronizing the block. See: [link to docs]. What do you think?"
```

### Scaffolding for Juniors
- Don't give solutions — give the right question: "What happens if the database is down at this point?"
- Review the design before implementation (not after) — saves 10x the rework
- Debrief after every incident: "What would you do differently?"

### Calibrating Feedback for Performance Reviews
A senior's feedback on a junior should be:
1. **Specific**: "Ravi resolved the payment timeout bug by identifying the missing circuit breaker"
2. **Evidence-based**: Link to PRs, design docs, incidents
3. **Level-appropriate**: Judge against L3/L4 bar, not senior bar
4. **Directional**: Where does this person need to grow?

---

## Senior Engineer ↔ Tech Lead Interface

- TL sets direction; Senior executes with high autonomy within it
- Senior can disagree with TL's design — does so in the design doc or review, with data
- Senior owns the implementation quality; TL does not need to review every PR
- Senior flags when a design decision made by TL creates implementation problems
- Senior can take on TL responsibilities for smaller projects ("acting TL")

## Senior Engineer ↔ Principal Engineer Interface

- Principal sets org-wide patterns; Senior implements them in specific services
- Senior gives Principal feedback on platform usability: "Your new logging library has a footgun — here's what I found"
- Principal is a resource for Senior on hard technical problems they can't resolve
- Senior is a candidate for growth into Staff/Principal: Principal actively sponsors this
- Senior engineers are the "early adopters" Principal relies on to validate new approaches before org-wide rollout

---

## Common Senior Engineer Failure Modes

| Failure Mode | Symptom | Impact |
|-------------|---------|--------|
| **Scope creep ownership** | Takes on too much; becomes bottleneck | Burnout; others starved of growth |
| **Code silo** | Only person who understands the service | Bus factor 1; dangerous for team |
| **Review bottleneck** | Reviews too slowly or too superficially | Team velocity blocked |
| **Over-engineering** | Builds for hypothetical future requirements | Complexity without value |
| **Under-communicating** | Works heads-down; PM/EM unaware of progress | Surprises at deadline |
| **Tech debt tolerance** | "We'll fix it later" attitude | Interest compounds; eventually a rewrite |
| **Refusing to mentor** | Sees mentorship as a distraction | Team doesn't grow; TL/Principal candidate pool shrinks |

---

## Growth Path: Senior → Staff/Principal

A senior engineer becomes a staff/principal candidate when they:

1. **Expand scope organically**: Starts owning cross-team designs without being asked
2. **Multiplies team output**: Others ship faster because of what the senior built or documented
3. **Operates under ambiguity**: Given "we need to reduce latency by 50%" — creates the plan, not just executes it
4. **Demonstrates technical judgment at scale**: Makes calls that hold up at 100x current load
5. **Influences without authority**: Changes the way the team or a neighboring team does something through writing or advocacy, not just code

**Promotion signals**:
- Owns a critical service end-to-end for 6+ months with high reliability
- Led at least one significant cross-team integration
- Mentored at least 2 L3/L4 engineers with visible outcomes
- Wrote and got approved at least one design doc without heavy revision from TL/Principal

---

## FAANG Senior Engineer Salary Context (for calibration, not interview topic)

| Company | Level | Approximate TC Range |
|---------|-------|---------------------|
| Google | L5 | $350K–$550K |
| Meta | E5 | $350K–$600K |
| Amazon | SDE3 | $250K–$400K |
| Apple | ICT4 | $280K–$450K |
| Netflix | Senior | $400K–$800K |

---

## Interview Angles for Principal Engineers

**"How do you identify when a senior engineer is ready for staff/principal?"**
- I look for scope expansion: are they owning more than their assigned component?
- Do they surface problems others don't see, or just solve problems given to them?
- Do they make the team better — do others ship faster because of them?
- I test with stretch assignments: give them an ambiguous, cross-team problem and observe

**"How do you mentor a senior engineer who has plateaued?"**
- First, diagnose: is it motivation, skill gap, or organizational constraint?
- Create visibility: if they're doing great work in a corner, no one sees it — fix that
- Give real stretch: not more of the same work, but qualitatively different scope
- Be direct about what the gap is and what closing it looks like — don't hint

**"What do you do when a senior engineer consistently underestimates?"**
- Don't punish — investigate: root cause is usually incomplete requirements, hidden dependencies, or overconfidence
- Build the estimation skill: teach breakdown techniques, historical calibration, risk buffering
- Create a feedback loop: compare estimates to actuals post-sprint; review together
- For chronic pattern: document, work with EM on performance conversation
