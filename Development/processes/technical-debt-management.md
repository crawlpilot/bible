# Technical Debt Management

**Category**: Engineering Strategy · Code Quality · Long-Term Reliability  
**Audience**: Principal / Staff Engineers responsible for codebase health and engineering strategy  
**Related**: [Change Management](change-management-process.md) · [Engineering Standards](../best-practices/07-engineering-standards.md)

> "Technical debt is not inherently bad. Deliberately incurred debt — a known shortcut taken to ship faster, with an explicit plan to pay it back — is a valid engineering tool. The problem is invisible debt: shortcuts that no one knows about, that accumulate interest silently until they cause an incident or make the next feature impossible to build."

---

## What Is Technical Debt?

**The original metaphor (Ward Cunningham, 1992)**: Shipping imperfect code is like taking out a loan. You get the benefit of faster shipping now, but you pay interest in the form of slower future development until the debt is paid back (refactored).

**Three categories of technical debt**:

| Category | Description | Management Approach |
|----------|-------------|-------------------|
| **Deliberate, visible** | Known shortcuts with documented trade-offs ("We're hardcoding this for now — ticket #1234") | Pay back in agreed timeframe |
| **Deliberate, invisible** | Shortcuts taken without documentation | Surface and document; then schedule |
| **Inadvertent** | Not a shortcut at the time — became debt as requirements evolved, code grew, team changed | Identify in code reviews and incident post-mortems |

---

## Why Technical Debt Matters to Principal Engineers

At senior levels, your job is not to personally write debt-free code — it is to manage the technical debt of entire systems and teams.

**Why it matters operationally**:
- High-debt codebases slow feature velocity (each change requires understanding brittle dependencies)
- High-debt codebases cause incidents (complex code has more failure modes, harder to debug)
- High-debt codebases increase on-call burden (harder to diagnose, more edge cases)

**Why it matters organizationally**:
- Accumulated debt creates "invisible ceilings" — the team cannot ship new features because the foundation is too brittle
- Debt creates knowledge concentration (only 1-2 people can work on the most complex areas)
- Debt increases hiring friction (experienced engineers evaluate codebase quality before joining)

**The PE's job**:
- Make debt visible (what debt exists, what it costs)
- Prioritize debt payback against feature investment
- Ensure teams are not accumulating debt faster than they're paying it back

---

## Measuring Technical Debt

You can't manage what you can't measure. Proxy metrics for technical debt:

### Leading Indicators (debt accumulating)

| Metric | What It Measures | Warning Signal |
|--------|----------------|---------------|
| **Code churn rate** | % of files modified in last 30 days | Low churn in critical areas = code becoming stale |
| **Cyclomatic complexity** | Number of independent paths through code | Average complexity > 10 per function |
| **Test coverage in critical paths** | % of critical code covered by tests | < 60% in critical paths |
| **Build time** | Time for full CI pipeline | > 15 minutes (slow builds reduce feedback loop) |
| **Dependency age** | Age of oldest dependency versions | Major version > 2 years old = unmanaged debt |
| **Duplication rate** | Code clone percentage (SonarQube) | > 10% duplication |

### Lagging Indicators (debt causing problems)

| Metric | What It Measures | Warning Signal |
|--------|----------------|---------------|
| **Incident frequency** | SEV-2+ incidents per month per service | Increasing trend = debt causing instability |
| **Feature velocity** | Story points delivered per sprint | Declining over quarters = debt slowing team |
| **Bug escape rate** | Bugs found in production vs. caught pre-production | > 20% escape rate = test coverage debt |
| **Deployment frequency** | How often can you deploy? | < 1/week = deployment pipeline debt |
| **Time to onboard** | How long before a new engineer is productive? | > 3 months = documentation + complexity debt |
| **Mean time to understand (MTTU)** | Time to understand and fix a bug in a new area | Subjective but trackable via on-call data |

---

## Technical Debt Classification Framework

Use a standard framework to classify and communicate debt items:

### Debt Taxonomy

```
Architectural Debt
  └── Wrong abstraction chosen; need to redesign boundaries
  └── Monolith that should be split; or microservices that should be merged
  └── Technology choice that no longer fits the use case
  └── Missing cross-cutting concern (auth, logging, rate limiting) spread ad-hoc across services

Design Debt
  └── Classes/modules with too many responsibilities (SRP violations)
  └── Deep inheritance hierarchies; prefer composition
  └── God objects / God services
  └── Missing abstractions (business logic in controllers, repeated DB access patterns)

Implementation Debt
  └── Known bugs or corner cases not handled
  └── Hardcoded values that should be configurable
  └── Missing error handling
  └── Inconsistent error codes / API responses

Test Debt
  └── No tests for critical path
  └── Tests that mock too much (don't catch real integration issues)
  └── Flaky tests (intermittent failures destroying CI confidence)
  └── Missing load tests; no performance baseline

Operational Debt
  └── Missing or stale runbooks
  └── Alert defined but no owner
  └── No deploy pipeline (manual deployments)
  └── No monitoring for a critical service

Dependency Debt
  └── EOL dependencies (language runtimes, frameworks, OS versions)
  └── Known-vulnerable dependencies
  └── Transitive dependency sprawl (thousands of unreviewed transitive deps)
  └── Vendor lock-in without justification

Documentation Debt
  └── No ADRs for key architecture decisions (why is it built this way?)
  └── Outdated onboarding documentation
  └── Undocumented APIs
  └── Tribal knowledge not codified
```

---

## Debt Inventory Process

### Step 1: Debt Discovery

Debt discovery channels:

```
1. Retrospectives: "What slowed us down this sprint?"
   → Each item where the answer is "X is hard to work with" or "Y is confusing" is a debt item

2. Incident post-mortems: Contributing factors section
   → "Missing monitoring," "no rollback path," "complex code hard to debug" = operational and implementation debt

3. Code review: Reviewers flag known debt while reviewing related code
   → Don't just approve; note when the surrounding code has debt that should be addressed

4. Tech debt days/hackathons: Dedicated time to find and document debt
   → Better than discovery during critical paths

5. Onboarding new engineers: Fresh eyes see debt that veterans have normalized
   → New hire's first 90-day friction points = your onboarding and documentation debt list

6. Static analysis: SonarQube, CodeClimate, language-specific linters
   → Automated detection of code smells, complexity, duplication
```

### Step 2: Debt Documentation Format

Every tracked debt item should have:

```markdown
## Debt Item: [Short Title]

**ID**: TD-2024-042
**Type**: [Architecture / Design / Implementation / Test / Operational / Dependency / Documentation]
**Severity**: [Critical / High / Medium / Low]
**Affected Component**: [service name, module, file path]
**Discovered**: 2024-03-15
**Discoverer**: @alice
**Related Incidents**: [INC-2024-0087] — poor code structure made debugging take 2h instead of 20min

### Description
[What is the debt? Be specific about what the problem is and where it lives.]

### Impact
**Current impact**: [How is this slowing us down or causing problems today?]
**Projected impact**: [How does this get worse if not addressed? When does it become critical?]
**Risk if not addressed**: [Outage risk, velocity loss, security risk, etc.]

### Proposed Resolution
[What is the specific fix? High-level is fine — this is for prioritization, not implementation.]

### Effort Estimate
[S / M / L / XL] — S: < 1 day, M: 1 week, L: 1 month, XL: quarter+

### Priority Score
[Calculated below]
```

### Step 3: Debt Prioritization

Prioritize debt using a simple scoring model:

**RICE score for technical debt**:

```
Impact (I): How much does this slow the team or risk incidents?
  1 = Minor inconvenience
  2 = Noticeable slowdown or moderate incident risk
  3 = Significant velocity loss or high incident risk
  4 = Blocking progress or near-certain incident risk

Confidence (C): How confident are we in the impact assessment?
  1 = Gut feeling
  2 = Some evidence
  3 = Strong evidence from incidents or metrics

Effort (E): How much work to fix?
  1 = > 1 month
  2 = 1 week to 1 month
  3 = < 1 week
  4 = < 1 day

Priority Score = I × C × E
```

**Priority tiers**:
- Score ≥ 30: Address in next sprint
- Score 15–29: Address in next quarter
- Score 1–14: Backlog; address when touching related code

---

## Debt Payback Strategy

### The "20% Rule"

Sustainable teams allocate **20% of engineering capacity** to technical debt and operational improvements. The exact percentage is less important than the principle: **debt reduction is a standing sprint commitment, not something that happens only when there's "time."**

If teams consistently don't have time to pay back debt, they are operating at unsustainable velocity and the debt load will eventually slow them down to below 80% of today's output.

### Debt Payback Patterns

**Pattern 1: Boy Scout Rule** (continuous, low-overhead)
> "Always leave the code better than you found it."

When touching code for a feature or bug fix, make small improvements to the surrounding code:
- Rename a confusing variable
- Extract a function that's too long
- Add a missing test for a path you noticed
- Update a stale comment

**No tracking required; no sprint planning required; zero overhead.** This keeps debt from compounding in actively-maintained code.

**Pattern 2: Dedicated Debt Sprint** (quarterly, high-impact)

Schedule one sprint per quarter focused exclusively on technical debt. Use the debt inventory to pick high-priority items. Communicate the investment to stakeholders:

> "This sprint we're investing in code quality. Feature delivery will be paused. Expected outcome: [specific improvements], which will increase our velocity by [estimate] in subsequent quarters."

**Pattern 3: Debt Coupled to Feature Work** (most common)

When planning a new feature that will touch an area with known debt, include debt cleanup in the same ticket:

> "Feature: Add OAuth2 login. This touches the auth module, which has significant test debt (coverage = 30%). Scope includes: OAuth2 implementation + increase auth module test coverage to 70%. Combined estimate: 2 weeks."

The cost of cleaning the area once is less than the accumulated cost of working around the debt on every future change.

**Pattern 4: Architecture Migration** (large, planned)

For large architectural debt (monolith decomposition, platform migration, ORM replacement):

1. Write an ADR documenting the current state and the target state
2. Define the migration strategy (strangler fig, big bang, feature flag)
3. Break the migration into phases with independent value (each phase is shippable)
4. Track as a multi-quarter engineering initiative with EM sponsorship
5. Measure progress with defined metrics (% of services migrated, % of traffic on new path)

**The strangler fig pattern** (preferred for large migrations):

```
New system built alongside old
Traffic gradually shifted (feature flags, API gateway routing)
Old system killed once traffic = 0

Benefits:
  - Incremental validation at each step
  - Rollback possible at any point
  - No "big bang" risk
  - Each phase is independently valuable and deployable

Timeline example (monolith → microservices):
  Q1: Extract auth service (high isolation, clear boundary)
  Q2: Extract user profile service
  Q3: Extract notification service
  Q4: Extract payment service
  Following year: Decompose remaining monolith core
```

---

## Communicating Debt to Stakeholders

Technical debt is invisible to non-engineers. Your job as a principal engineer is to make it visible and translate it into business impact.

### Framing Debt for Non-Technical Audiences

**Don't say**: "We have a lot of technical debt that's slowing us down."  
**Do say**: "Our current checkout service architecture adds 2 weeks of development time to every new payment feature. We've traced 3 of our last 5 payment incidents to the same architectural shortcut. Investing 6 weeks in a targeted refactor will reduce our payment incident rate by an estimated 60% and reduce feature development time by 50%. Here's the trade-off: we delay the coupon feature by 6 weeks in exchange for permanent velocity gains on our highest-revenue service."

**The business translation formula**:
```
Debt impact = (current velocity cost per sprint × sprints per year)
            + (incident cost per incident × estimated incidents caused by this debt per year)

Example:
  Velocity cost: 2 extra days per feature touching auth module
  Features touching auth per year: 20
  Total velocity cost: 40 engineer-days per year

  Incident cost: auth incidents average 90 minutes MTTR × 3 incidents per year
                 = 4.5 engineer-hours per year (plus SLO budget burned)

  Investment: 3 weeks refactor

  Payback period: 3 weeks investment / (40 days/year saved × 1/52 year/week) ≈ 4 weeks
                  → ROI positive in 4 weeks; net positive after that
```

### Debt Dashboard for Leadership

Track and present debt metrics monthly at engineering leadership reviews:

```
Technical Health Dashboard:
  Debt backlog: [N] items ([N] Critical, [N] High, [N] Medium)
  Debt items added this quarter: [N]
  Debt items resolved this quarter: [N]
  Net change: [+N/-N] items
  
  Velocity impact (estimated): [N] engineer-days per sprint lost to debt
  Incidents attributed to debt: [N] in last quarter
  
  Top 3 debt items by priority score:
  1. [Auth module test coverage] — blocks feature velocity (P: 40)
  2. [Payment service timeout configuration] — incident risk (P: 36)
  3. [Legacy notification queue] — operational overhead (P: 28)
  
  Investment planned next quarter: [N] sprints allocated to debt reduction
```

---

## Debt Anti-Patterns

| Anti-Pattern | Consequence | Correction |
|-------------|------------|------------|
| **"We'll clean it up later"** (without a ticket) | Later never comes | All acknowledged debt gets a ticket at creation time |
| **Debt-only sprints without agreement** | Stakeholders feel blindsided by "no features" sprint | Communicate quarterly allocation; get EM alignment in advance |
| **Perfection as a goal** | Engineers spend time on minor cleanup while critical debt accumulates | Prioritize by impact; 80% clean is good enough |
| **Big-bang refactors** | Long-lived branch; integration nightmare; morale risk if abandoned | Strangler fig; incremental migration; each phase independently deployable |
| **Ignoring test debt** | Fast feature velocity now → slow velocity later as confidence erodes | Test coverage is a non-negotiable part of the definition of done |
| **Treating all debt the same** | Low-value debt gets time that should go to high-impact debt | Explicit prioritization with RICE or equivalent scoring |
| **No owner for debt items** | Items sit in backlog indefinitely | Every debt item has a named owner and a due date or "deprioritized until X" |

---

## FAANG Interview Framing

### "How do you manage technical debt at scale?"

> "I manage technical debt as an inventory, not a vague concept. Every known debt item gets a ticket with a description of the impact — in terms of velocity cost and incident risk — and a priority score. I track three things monthly: how much debt we're adding (leading indicator of practices), how much we're paying back (investment), and what the lagging indicators say (is debt actually slowing us down or causing incidents?). For payback strategy, I use three modes simultaneously: the Boy Scout Rule for continuous small improvements, coupling debt cleanup to feature work when touching high-debt areas, and quarterly dedicated sprint for high-priority items. The hardest part is communicating debt to stakeholders in business terms. 'Our auth module has 30% test coverage' means nothing. 'Every payment feature takes 2 extra weeks because the auth module is brittle, and we've had 3 auth incidents this year from code nobody is confident touching' creates alignment. At the PE level, my job is to make the invisible visible and translate engineering health into business impact."

### "How do you decide when to refactor vs. when to continue shipping features?"

> "I use a payback period model. If the investment in refactoring pays back in velocity within 2 quarters, I argue for it strongly. If it takes longer, I look at the incident risk — is there an incident risk that justifies the investment even if velocity payback is slow? The other factor is trajectory: is this area of the codebase getting worse every quarter? If we're adding debt faster than we're paying it back in a critical area, I treat it as a time-sensitive issue. I also use the strangler fig pattern to avoid the 'stop everything and refactor' trap — I can almost always structure a large refactor as a series of incremental improvements that each deliver independent value, so we're never choosing between refactoring and shipping features as an either/or."
