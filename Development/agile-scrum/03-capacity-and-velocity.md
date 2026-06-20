# Capacity and Velocity

Capacity answers the question: how much work can the team realistically take on this sprint? Velocity answers the question: how much work did the team historically complete? They are related, but they are not interchangeable.

## Capacity vs Velocity

| Concept | What it tells you | What it does not tell you |
|---------|-------------------|---------------------------|
| Capacity | How much work is available to the team now | Whether the team will finish a specific story |
| Velocity | Historic completion rate of the team | Whether a future sprint will match the average |

## Why Averages Can Mislead

If a team's last six sprints were 38, 41, 35, 28, 44, and 19 points, the average is 34.2 points. That does not mean the next sprint will be 34 points. The variance matters, especially when support load, holidays, and dependencies are changing.

## Capacity Inputs

| Factor | Typical planning treatment |
|--------|----------------------------|
| PTO and holidays | Remove from capacity entirely |
| On-call / support | Reserve a fixed buffer |
| Large meetings | Reduce effective capacity |
| New hires | Discount initial capacity due to ramp-up |
| Planned upgrades / migrations | Treat as explicit capacity consumers |

## Forecasting Practices

- Use recent velocity as a signal, not a target.
- Use capacity-based forecasting when the team composition changes.
- Reforecast when interrupt load changes materially.
- Prefer ranges over single-point commitments.
- Track carryover separately from new scope.

## What a Healthy Team Does

- Keeps some capacity uncommitted for urgent work
- Reviews trend lines over multiple sprints instead of one outlier
- Uses carryover as a diagnostic, not a reason for blame
- Explicitly plans for testing, review, and release work

## When Velocity Breaks Down

- The team is reorganized or partially reassigned
- The backlog is unstable or poorly refined
- A large incident or migration changes the interrupt rate
- Story sizing is inconsistent across the team
- External dependencies dominate throughput

## Principal Engineer Takeaway

If you cannot explain why velocity changed, then you do not understand the system producing it. The point is not to defend the number. The point is to understand the constraint.

## Interview Callout

When asked how you would predict delivery, lead with capacity first and velocity second. Capacity handles the current state of the team; velocity helps calibrate the forecast.

---

## Flow Metrics — Beyond Story Points

Story points measure estimated size. Flow metrics measure real delivery behaviour. At FAANG scale, flow metrics are more actionable because they reflect the actual system rather than estimates about it.

### Lead Time vs. Cycle Time

| Metric | Starts | Ends | Measures |
|--------|--------|------|---------|
| **Lead time** | Story created in backlog | Delivered to production | Total wait + work time |
| **Cycle time** | Work started (In Progress) | Delivered to production | Active work time only |

**Target:** cycle time should be short (days, not weeks); the gap between lead time and cycle time reveals queue time — stories waiting in the backlog, waiting for review, or waiting for deployment.

```
Example:
  Story created:          Monday week 1
  Story started:          Tuesday week 2  ← 6 days queue time
  Story merged:           Thursday week 2
  Story deployed:         Friday week 2   ← 3 days cycle time

  Lead time: 9 days
  Cycle time: 3 days
  Queue time: 6 days — this is where to focus improvement
```

### Throughput

Throughput = number of stories completed per sprint (not story points). Useful when stories are consistently sized.

**When to use throughput over velocity:** when the team has strong story splitting discipline and wants to remove estimation overhead (#NoEstimates approach).

---

## Little's Law Applied to Engineering Teams

> *WIP = Throughput × Cycle Time*

Little's Law says: if you know any two of (Work In Progress, Throughput, Cycle Time), you can calculate the third.

**Practical implication:** reducing WIP is the fastest way to reduce cycle time. If a team has 8 stories in progress simultaneously among 4 engineers, context switching is destroying throughput. The fix is a **WIP limit**.

```
WIP Limit Rule of Thumb: number of engineers + 1 or 2 buffer items

  5-engineer team → WIP limit ~6–7 active stories
```

Teams that exceed WIP limits consistently have a deeper problem: stories are too large, unblocked stories are not being prioritised, or the pull system is broken.

---

## Cumulative Flow Diagram (CFD)

A CFD plots the count of stories in each state (Backlog, In Progress, Review, Done) over time. It makes flow problems visible that velocity hides.

```
What a healthy CFD looks like:
  - Bands are roughly consistent in width (stable WIP)
  - The "Done" band grows steadily
  - No one band bulges (no queue building up)

What an unhealthy CFD looks like:
  - "In Review" band widens → review is a bottleneck
  - "In Progress" band widens → engineers are context-switching, not finishing
  - "Done" flatlines then spikes → batch delivery, not continuous flow
```

**How to use it in practice:** review the CFD weekly in planning. If any band is widening, name the blocker and assign an owner. Don't wait for the retrospective.

---

## Monte Carlo Forecasting

Instead of a single-point velocity forecast, use Monte Carlo simulation to produce a probability distribution over delivery dates.

**How it works:**
1. Take the last 8–12 sprints of actual throughput data (stories completed per sprint)
2. Randomly sample from that distribution 10,000 times
3. Simulate sprints until the backlog is exhausted in each simulation
4. Plot the distribution of completion dates

**Output:** "There is a 50% probability we complete this scope by Sprint 12, and an 85% probability by Sprint 15."

**Why it's better than averaging:**
- Respects the variance in historical throughput
- Accounts for sprint-to-sprint variability automatically
- Produces honest confidence intervals instead of false precision
- Does not assume the team will perform at the average going forward

**Tooling:** Actionable Agile, Nave, or a simple Python/spreadsheet simulation.

---

## DORA Metrics — Engineering Team Health

The DORA (DevOps Research and Assessment) metrics are the most widely validated measures of software delivery performance. They are what Google and DORA researchers found distinguish elite teams from low-performing ones.

| Metric | Elite | High | Medium | Low |
|--------|-------|------|--------|-----|
| **Deployment frequency** | On-demand (multiple/day) | Weekly–monthly | Monthly | < Monthly |
| **Lead time for changes** | < 1 hour | 1 day – 1 week | 1 week – 1 month | > 6 months |
| **Change failure rate** | 0–15% | 16–30% | 16–30% | 16–30% |
| **Time to restore service** | < 1 hour | < 1 day | 1 day – 1 week | > 6 months |

**How to use DORA in sprint planning:**
- High deployment frequency → WIP limits work, CI/CD is healthy
- High change failure rate → quality gates need investment; protect sprint capacity for test automation
- Long lead time for changes → backlog is too large or reviews are bottlenecked

DORA metrics belong on the team dashboard alongside velocity and cycle time.

---

## Velocity Health Indicators

| Signal | Healthy interpretation | Warning interpretation |
|--------|----------------------|----------------------|
| Consistent velocity ±15% | Stable, predictable team | Over-fitted to a narrow work type |
| Velocity drops after new hire | Normal ramp-up | Hire has no onboarding plan |
| Velocity spikes at end of sprint | Good sprint execution | Stories being closed prematurely or scope-cut |
| Velocity drops after incident | Normal post-incident stabilisation | Systemic reliability problem |
| Velocity varies > 30% sprint-to-sprint | High interrupt load | Backlog is unstable or stories are inconsistently sized |

---

## Capacity Model — Detailed Template

```
Team: 5 engineers, 2-week sprint (10 working days)

Person-days available: 5 × 10 = 50

Deductions:
  - PTO / holidays:                      -4 (confirmed)
  - Sprint ceremonies (planning, retro,
    standup, review):                    -2 per engineer = -10
  - On-call rotation (1 engineer):       -3
  - Planned leave or interview panels:   -2
  - 20% interrupt buffer (incidents,
    urgent bug fixes, review load):      -7

Available engineering-days: 50 - 4 - 10 - 3 - 2 - 7 = 24

At 6 story points per engineer-day (team calibration),
target sprint capacity: ~24 × (6/5) ≈ 29 story points

Rule: never plan above 90% of this number without explicit acknowledgement.
```

This model is far more honest than saying "we usually do 40 points" and then being surprised at 28.

---

## FAANG Interview Framing

**"How do you forecast a release date for a large feature?"**

> I use Monte Carlo simulation over historical throughput rather than a simple average. I pull the last 8–10 sprints of actual story completions, run a simulation of the remaining backlog, and present a probability distribution: "85% confidence we finish by date X, 50% confidence by date Y." This is more honest than a single-point estimate and helps stakeholders make risk-informed decisions — do they want to reduce scope to hit the 50th percentile date, or are they comfortable with the 85th percentile buffer?

**"What flow metrics do you track for a team?"**

> I track four: cycle time (from started to deployed), lead time (from created to deployed), throughput per sprint, and WIP at any point in time. I look at the cumulative flow diagram weekly — it makes queue buildups visible that velocity hides. If review is the bottleneck, I'll see the review band widening. If too many stories are in flight simultaneously, I'll impose a WIP limit. I also track the four DORA metrics quarterly as a health check on the overall delivery system.
