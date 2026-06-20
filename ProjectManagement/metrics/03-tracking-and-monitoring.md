# Tracking, Monitoring & Accountability

## Why Most Tracking Fails

Tracking fails when it becomes a reporting exercise rather than a decision-making tool. Weekly status updates nobody reads, dashboards nobody looks at, OKR scores filled in on the last day of the quarter because someone asked — all of this is process theater.

**Effective tracking has one purpose**: surface information that changes behavior before the problem becomes expensive. If a metric is tracked but never changes what the team does, it is not serving its function.

---

## The Review Cadence Stack

Different metrics need different review frequencies. Reviewing everything at the same cadence either creates alert fatigue (too frequent) or misses fast-moving problems (too infrequent).

```
Real-time / continuous:
  Production alerts, SLO burn rate, error rate
  → Automated. Humans only engaged when threshold crossed.

Daily:
  Deployment health, CI/CD pipeline health, on-call queue
  → Engineer on rotation glances at dashboard. < 5 min.

Weekly:
  Delivery metrics (lead time, cycle time, deploy frequency)
  Sprint progress vs. plan
  OKR leading indicators (are we on track?)
  Tech debt delta (added vs. paid this week)
  → Team sync: 30 min, data-first, action-item per metric that's off track.

Monthly:
  DORA trend (month-over-month)
  OKR scoring checkpoint (current trajectory: 0.0–1.0)
  Incident retrospective: pattern analysis across incidents
  Team health indicators (eNPS trend, on-call burden, velocity stability)
  → Engineering leadership review: 60 min.

Quarterly:
  OKR final grades + retrospective
  Business metrics review (conversion, NPS, feature adoption tied to eng work)
  Tech debt prioritization
  V2MOM progress review
  Annual roadmap adjustment
  → Full engineering leadership + product leadership: 90–120 min.
```

---

## OKR Progress Tracking in Practice

### The Confidence Score

At each checkpoint (weekly or bi-weekly), each KR gets two scores:
1. **Current attainment**: where are we right now? (0.0–1.0)
2. **Confidence score**: given current progress, how confident are we in hitting 0.7 by end of quarter? (🔴 Low / 🟡 Medium / 🟢 High)

```
Week 6 OKR Review:

KR1: Reduce payment timeout errors 2.1% → 0.5%
  Current:     1.3% → attainment 0.5
  Confidence:  🟢 High — trending correctly, infra change shipped last week
  
KR2: Reduce checkout p99 from 3.2s → 1.0s
  Current:     2.8s → attainment 0.2
  Confidence:  🔴 Low — DB query optimization still blocked on DBA access
  Action:      Escalate DBA access by Thursday, or de-risk with caching approach

KR3: Checkout CSAT 3.1 → 4.2
  Current:     3.4 → attainment 0.27
  Confidence:  🟡 Medium — survey data noisy, need 2 more weeks to see signal
```

The confidence score drives conversation: anything 🔴 needs an explicit action item and owner in the meeting. Anything 🟢 is acknowledged and moved past. This keeps meetings focused on blockers, not reporting.

### Trajectory Projection

```
At week 6 of 13-week quarter:
  KR target: reduce latency from 3.2s → 1.0s (delta = 2.2s)
  Current:   2.8s (achieved 0.4s reduction = 18% of target)
  
  Linear projection at current pace:
    Week 13 estimate = 0.4s × (13/6) = 0.87s improvement
    Projected final:  3.2 - 0.87 = 2.33s   (attainment: 0.4 out of 1.0)
  
  Conclusion: on pace to miss target significantly.
  Required weekly velocity: (3.2 - 1.0) / 13 = 0.17s/week
  Actual weekly velocity:   0.4s / 6 = 0.07s/week
  Gap: need to 2.4× the current rate of improvement.
```

This is the calculation to run at the mid-quarter checkpoint. If the numbers show a clear miss, it's better to know in week 6 than week 12.

---

## Sprint / Delivery Tracking

### Burn-Down Chart

Tracks planned vs. actual remaining work over the sprint.

```
Sprint burn-down (10-day sprint, 50 points planned):

Day:  0   1   2   3   4   5   6   7   8   9   10
Plan: 50  45  40  35  30  25  20  15  10   5    0  (ideal line)
Act:  50  48  45  40  36  35  32  28  20  15   8  (actual)

Reading:
  Day 5: 5 points behind pace (35 vs 30 remaining)
  Day 8: 8 points behind (28 vs 20) — accelerating gap
  Day 10: 8 points not completed → 84% sprint completion
```

**What burn-down reveals**:
- Flat line mid-sprint: team is blocked or stories are not sliceable into daily increments
- Sudden drop: a large story was completed (fine) or a story was artificially closed (bad)
- Below ideal line: team is ahead — could pull in backlog items or scope is too light

### Burn-Up Chart (alternative)

Tracks work completed vs. total scope. Better for projects where scope changes mid-sprint (common).

```
Day:       0   3   6   10
Completed: 0  15  28   42
Scope:    50  50  55   55  (scope was added on day 5)

Burn-up shows scope increase clearly — burn-down would just show
slower progress without explaining why.
```

Use burn-up when scope is expected to change. Use burn-down when scope is stable and you want clear pace-to-completion signal.

---

## Accountability Structures

### The Decision Log

At principal engineer scope, many decisions are made collaboratively — in Slack, in meetings, in docs. Without a decision log, the same decisions get re-litigated, context is lost, and accountability is diffuse.

**Format** (lightweight, in project doc or Confluence):

```markdown
| Date       | Decision                                           | Owner  | Rationale                        | Revisit When                    |
|------------|----------------------------------------------------|--------|----------------------------------|---------------------------------|
| 2026-03-01 | Use PostgreSQL for the new service (not DynamoDB)  | Alice  | Team expertise, simpler ops      | If write throughput > 50K TPS   |
| 2026-03-08 | Defer mobile push to v2                            | Bob    | Scope reduction for Q1 deadline  | Q2 kickoff                      |
| 2026-03-15 | Phase canary rollout in 5%/25%/100% steps          | Alice  | High-risk change, new payment flow | After first full rollout cycle |
```

**Why it matters**: when a post-mortem traces an incident to "we decided to skip the circuit breaker to ship faster," the decision log shows who made that call, what the rationale was, and that the trade-off was intentional — not an oversight.

### RACI Matrix (for multi-team accountability)

For any initiative touching 3+ teams, establish RACI before work begins:

```
R = Responsible  (does the work)
A = Accountable  (owns the outcome, single person)
C = Consulted    (provides input before decision)
I = Informed     (notified after decision/completion)

Example: Real-Time Notifications Initiative

                    Platform  Auth  Notifications  Mobile  Data
─────────────────────────────────────────────────────────────────
API Design           C         C     R, A           I       I
WebSocket server     R         I     A              C       I
Client SDK           I         I     C              R, A    I
Message fanout       R, A      I     C              C       I
Push integration     I         I     R              A       C
Load testing         C         I     R, A           C       I
Go-live decision     I         I     A              C       I
```

**Key rule**: one A per row. Two accountable parties = no accountability.

If a row has two A's, clarify now — mid-project is too late.

### Weekly Written Update (for large initiatives)

For any initiative > 6 weeks with stakeholders outside your team, a weekly written update prevents status meetings and provides an audit trail.

**Format (BLUF — Bottom Line Up Front)**:

```
Week 8 Update — Payment Reliability Initiative
Status: 🟡 On track, one risk

HEADLINE: Retry logic shipped to staging; performance testing in progress.
          DB query optimization blocked — see Risk section.

COMPLETED THIS WEEK:
  - Shipped retry logic with exponential backoff to staging (KR1)
  - Checkout p99 in staging: 1.4s (down from 2.8s) — target 1.0s
  - 3/5 integration test suites passing; 2 flaky tests quarantined

NEXT WEEK:
  - Complete DB query optimization (if DBA access granted)
  - Run load test at 10× baseline traffic
  - Deploy retry logic to canary (5% traffic)

RISKS:
  🔴 DBA access for query optimization: requested 2026-03-01, not granted.
     Impact: KR2 (p99 latency) at risk. Mitigation: Redis caching as fallback.
     Owner: Alice. Escalation: If not resolved by Wednesday, escalate to VP Eng.

DECISIONS NEEDED:
  - Approve Redis caching as KR2 fallback approach? (Alice + PM needed)
```

**Key principle**: stakeholders should be able to read this in 90 seconds and know: status, progress, blockers, what needs their attention. No narrative prose, no padding.

---

## Metric Review Meeting Structure

### Anti-pattern: the status meeting

```
Bad format:
  "Alice, where are you on the migration?"
  "We're making progress. Should be done next week."
  "Great. Bob, where are you on..."
  
Output: nobody learned anything. No decisions made. Could have been an email.
```

### Good format: the exception-based review

```
Good format:
  Pre-work: team updates their KR scores and flags in a shared doc
  
  Meeting agenda:
    1. Review 🔴 items only (5 min per item max)
       - What's the blocker?
       - What's the action and owner?
       - What's the deadline to resolve before escalation?
    2. Decisions needed — items that require cross-team or leadership input
    3. 🟢 items acknowledged, no discussion
    
  Output: decision log updated, action items assigned with owner + deadline
```

This format works because people come prepared (no "let me check on that"), decisions are made in the room, and 🟢 items don't consume time.

---

## Escalation Framework

When a risk or blocker isn't resolved within the team:

```
Day 0:    Blocker identified. Owner assigned. Resolution deadline set.
Day 3:    If unresolved → mentioned in weekly update with 🔴 status.
Day 5:    If unresolved → escalate to tech lead / EM in 1:1.
Day 8:    If unresolved → escalate to director / VP in written update.
Day 10:   If unresolved → add to next steering committee / leadership sync.
```

**What to include in an escalation**:
1. What is blocked (specific KR or milestone)
2. Since when (days blocked)
3. What you've already tried
4. What you need from the escalation (a decision, a resource, an unblock from another team)
5. The cost of continued delay (timeline impact in weeks)

Never escalate vaguely ("we have a blocker"). Escalate specifically with context and a concrete ask.

---

## FAANG Interview Callouts

**Q: You're leading a 20-week initiative with 6 teams. At week 10, you're behind on 3 of 5 milestones. How do you handle it?**

First, diagnose before acting:
- Are all 3 milestones behind for the same reason (one shared blocker) or different reasons?
- Are they on the critical path, or do they have float?
- Is the total projected completion still within acceptable range, or are we heading for a significant miss?

Then act based on data:
1. **Critical path milestones behind**: escalate immediately with scope reduction options. "We can hit the date with X and Y de-scoped, or we hit the full scope at week 24."
2. **Off-critical-path milestones behind**: re-sequence. Move floating milestones later, protect the critical path.
3. **All milestones slipping by 20%**: the original estimate was wrong. Acknowledge it, re-baseline with evidence, present the new forecast with options to stakeholders now — not at week 18.

The worst outcome is staying silent until week 18 and delivering a surprise. The best outcome is surfacing it at week 10 with data and options.

**Q: How do you hold teams accountable for OKR commitments without creating a blame culture?**

Accountability without blame works when:
1. **The OKR was set collaboratively** — teams own their OKRs, not OKRs handed down
2. **Missing is expected** — 70% attainment is the target, not 100%. Missing isn't failure.
3. **Retrospective is systems-focused** — "what prevented us from hitting this?" not "whose fault is it?"
4. **Learning is the output** — each missed KR generates one improvement to the process or system

The accountability mechanism: every missed KR (< 0.5) gets a 30-minute retrospective. Output: one change to how we work next quarter. That's it. No blame, but also no free pass — missing without learning is the only unacceptable outcome.
