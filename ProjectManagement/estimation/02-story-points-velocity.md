# Story Points & Velocity

## What Story Points Are (and Are Not)

Story points measure **relative effort complexity** — a combination of:
- **Effort**: how much work is involved
- **Complexity**: how difficult or unfamiliar the problem is
- **Uncertainty/Risk**: how much we don't know yet

Story points are **not** hours. They are not a measure of time. They are not comparable across teams. A "5" in Team A means nothing to Team B.

**Why not hours?** Hours anchor estimation to a specific person on a specific day. A story that takes a junior engineer 8 hours might take a senior engineer 2 hours. Points capture team-relative complexity, which is what matters for planning.

---

## The Fibonacci Scale

```
1  — trivial, fully understood, no risk
2  — simple, straightforward, maybe one small unknown
3  — moderate, known approach, few unknowns
5  — meaningful work, some design decisions needed
8  — complex, significant unknowns, cross-component impact
13 — very complex, major unknowns, needs spike or decomposition first
21 — too large to estimate reliably — must be broken down
```

**Why Fibonacci?** The gaps between numbers grow, reflecting that large estimates are inherently less precise. The difference between 8 and 13 is meaningful. The difference between 34 and 35 is not — both are "very large." Fibonacci forces honest acknowledgment of uncertainty.

**No half-points.** If a story feels like 4, the answer is 3 or 5. The ambiguity means something — surface it.

---

## Planning Poker

### How it works

1. Product/tech lead reads the story and acceptance criteria aloud.
2. Each engineer silently selects a card (physical or digital) — their estimate.
3. All cards are revealed simultaneously (**never sequentially** — anchoring bias is real).
4. If consensus: record the estimate and move on.
5. If divergence: the highest and lowest estimator explain their reasoning. One re-vote. If still split, take the higher estimate or schedule a spike.

### Why simultaneous reveal matters

```
Bad (sequential):
  Senior eng: "I think this is a 5."
  Everyone else: "...yeah, 5 sounds right."
  → No information gathered. The team just mirrored the senior engineer.

Good (simultaneous reveal):
  Senior eng reveals 5. Junior eng reveals 13.
  → Discussion: "Why did you say 13?"
  → "I was thinking about the migration of existing data — are we including that?"
  → "Oh. We weren't planning to. Now we need to decide."
  → The estimate revealed a scope gap that planning poker exposed.
```

The purpose of planning poker is not to get a number — it is to surface divergent assumptions.

### Digital tools

- **PlanningPoker.com** — simple, free, async-friendly
- **Linear** — native story points field, no poker ceremony
- **Jira** — story points + sprint velocity tracking built-in
- **Miro** — custom poker card frames for distributed teams

---

## Velocity

**Definition**: the sum of story points completed by a team in a sprint, measured over actual completed stories (not planned).

```
Sprint 1: planned 34 pts, completed 28 pts → velocity = 28
Sprint 2: planned 30 pts, completed 31 pts → velocity = 31
Sprint 3: planned 35 pts, completed 27 pts → velocity = 27
Sprint 4: planned 30 pts, completed 30 pts → velocity = 30

Rolling average velocity (last 4 sprints): (28+31+27+30)/4 = 29 pts/sprint
```

**Never use planned points as velocity.** Planned points include unfinished work. Velocity is what was actually shipped.

### Using velocity for forecasting

```
Remaining backlog: 145 story points
Average velocity: 29 pts/sprint (2-week sprints)
Forecast: 145 / 29 = ~5 sprints = ~10 weeks

With uncertainty range (velocity ranged 27–31):
  Optimistic: 145 / 31 = 4.7 sprints (~9.5 weeks)
  Pessimistic: 145 / 27 = 5.4 sprints (~11 weeks)
  
Communicate to stakeholders: "9.5–11 weeks at current velocity, assuming no scope changes."
```

### Velocity stability

A healthy velocity is **stable within ±15%** sprint over sprint. Large swings indicate:

| Swing type | Likely cause |
|-----------|--------------|
| Sudden drop | Unplanned work (incidents, tech debt fires), team member absent, scope was underestimated |
| Sudden spike | Stories were too easy, team padded estimates, sprint was unusually clean |
| Consistently low vs. committed | Estimation is optimistic; team is overcommitted; interrupt rate is high |
| Consistently high vs. committed | Team is under-committed; sandbagging |

---

## Story Points vs. Hours: The Manager Trap

Managers often ask: "How many hours is a 5-point story?"

The correct answer: **"It depends on the team and context, and that's the point."**

If you convert points to hours, you:
1. Lose the benefit of relative sizing (team-calibrated complexity)
2. Invite micromanagement of hours vs. delivery of value
3. Introduce false precision that destroys trust when actuals differ

**What to tell stakeholders instead**: "Our team completes approximately 28–32 points per sprint. A sprint is 2 weeks. That translates to roughly 5–7 completed stories per sprint of medium complexity."

---

## Velocity Anti-Patterns

### 1. Velocity as a performance metric

Using velocity to compare teams or evaluate engineers destroys the calibration. Engineers inflate point values to "hit targets." Within 2 quarters, velocity numbers are meaningless.

**Amazon and Google policy**: velocity is a planning tool, not a KPI. It is never used in performance reviews.

### 2. Committing to "N points this sprint"

Velocity is an average, not a target. Saying "we commit to 30 points this sprint" turns an estimation tool into a commitment mechanism — the opposite of its purpose.

Better: "Based on velocity, we plan to bring in ~30 points. We'll track what we complete."

### 3. Carrying over unfinished stories with full points

A 13-point story that is 80% done provides 0 user value. Do not count partial credit. Either:
- Split the story before the sprint ends so the completed part can be accepted
- Count 0 for the sprint, count 13 next sprint when done

### 4. Re-estimating mid-sprint

Never re-estimate a story mid-sprint to make velocity look better. Actuals are the calibration mechanism — inflating them breaks the feedback loop.

### 5. Splitting stories to "make velocity look good"

Splitting a 13 into five 3s and completing them all looks like 15 points of velocity when the work was actually 13. Honest accounting matters.

---

## Acceptance Criteria: The Foundation of Accurate Estimation

Stories with vague acceptance criteria produce wildly inaccurate estimates and cause mid-sprint surprises.

**Bad AC**: "User can reset their password."

**Good AC**:
```
Given a registered user who has forgotten their password
When they request a reset link
Then they receive an email within 60 seconds with a one-time link
  And the link expires after 24 hours
  And the link is invalidated after use
  And the previous password remains valid until the new one is set
  And the reset is logged in the audit trail
  And the user receives a confirmation email after successful reset
```

The difference in AC quality alone can shift the estimate from 3 to 8 — and the 8 is the honest number. Stories with weak AC will balloon mid-sprint.

**Principal engineer practice**: refuse to estimate stories without testable acceptance criteria. "Not ready for estimation" is a valid output of planning poker.

---

## Refining Estimates: When to Re-Estimate

| Trigger | Action |
|---------|--------|
| Story hasn't been touched in 3+ sprints | Re-estimate — context has changed |
| Scope changed materially after estimation | Re-estimate in next sprint planning |
| Engineer discovers 5-point story is actually 13 mid-sprint | Split into two stories; close the current sprint story |
| Tech discovery changes approach fundamentally | Remove from sprint, run a spike, re-estimate next sprint |

Never silently carry forward a stale estimate. It corrupts velocity and misleads forecasting.

---

## FAANG Interview Callouts

**Q: Your team's velocity is inconsistent — 22 pts one sprint, 38 pts the next. How do you stabilize it?**

Diagnose root cause before prescribing:
1. Check interrupt rate — unplanned work is the #1 velocity killer. If the team handles 20% of their time on incidents or ad-hoc requests, plan 80% capacity, not 100%.
2. Check story size distribution — large stories (13+) carry all-or-nothing risk. If a 13-point story slips, the sprint tanks. Break stories to ≤ 8 points.
3. Check estimation accuracy — compare estimated points vs. actual hours retrospectively. If team consistently underestimates a story type, recalibrate.
4. Check definition of done — are stories being "completed" before acceptance criteria are fully met? That's hidden rework accumulating.

**Q: An executive asks why your team ships fewer features than another team with the same headcount. They're referencing velocity numbers.**

Velocity is not comparable across teams. Team A's "5" might be Team B's "2" — they calibrated independently. You need a shared reference point:
- Show delivery of customer value instead: features shipped, user outcomes, system reliability
- If you must compare, use cycle time (from in-progress to deployed) — it's objective and doesn't depend on calibration
- Offer to co-size a set of stories with both teams to surface calibration differences
