# Team Health Metrics

## Why Team Health Is a Principal Engineer Concern

A principal engineer who delivers technically excellent systems on an exhausted, disengaged team is not succeeding — they're borrowing against the future. Team health predicts long-term delivery capacity far better than any sprint metric.

Symptoms of unhealthy teams show up 3–6 months before they show up in delivery outcomes. Tracking leading indicators of team health gives you time to intervene before engineers start leaving.

---

## The Team Health Hierarchy

```
LAGGING INDICATORS (slow to change, hard to fix)
  Attrition rate, hiring velocity, long-term velocity trend

       ↑ caused by

LEADING INDICATORS (change faster, easier to fix)
  On-call burden, interrupt rate, tech debt growth, PR review queue

       ↑ caused by

ROOT CAUSES (system-level)
  Process design, tooling quality, org structure, leadership behavior
```

Fix root causes. Monitor leading indicators. Don't be surprised by lagging indicators.

---

## Velocity Stability

**Why it's a health metric**: unstable velocity signals unpredictable interrupts, scope changes, or team coordination problems — not just "some sprints are harder."

```
Velocity over 8 sprints:
  Sprint 1: 32  Sprint 5: 28
  Sprint 2: 29  Sprint 6: 40  ← spike (why?)
  Sprint 3: 31  Sprint 7: 18  ← crash (why?)
  Sprint 4: 33  Sprint 8: 35

Coefficient of Variation (CV) = std dev / mean
  Mean: 30.75, Std Dev: 6.38, CV: 20.7%

Health target: CV < 15% for a stable team
```

**Interpreting spikes and crashes**:
- Spike (velocity >> mean): sprint had unusually easy stories, or stories were over-split artificially
- Crash (velocity << mean): unplanned interrupt work, key engineer absent, dependency delay, scope was underestimated

Run a brief retro on any sprint that deviates > 25% from the rolling average.

---

## PR Review Turnaround Time

**Definition**: time from PR opened to first review comment (responsiveness) and time from PR opened to merge (cycle time).

```
Measurement:
  TTFR (Time to First Review): PR open timestamp → first review comment
  TTM (Time to Merge):         PR open timestamp → merge timestamp
  
Healthy targets:
  TTFR: < 4 hours for same-day business hours
  TTM:  < 1 business day for PRs < 400 lines
  
Warning signs:
  TTFR > 24h:      reviewers are overloaded or PR is too large to start
  TTM > 3 days:    back-and-forth suggests unclear requirements or large scope
  PRs > 600 lines: a single PR is too large; split it
```

**Why it matters for team health**:
- Long review queues block engineers from moving to the next task (context switch cost)
- Long review times signal bottlenecks: one reviewer overloaded, or code ownership not distributed
- Consistently large PRs indicate stories are not being decomposed well

**Improvement levers**:
- Review rotation: distribute reviews across team members, not always to the most senior person
- PR size limits: team norm of < 400 lines; tooling to flag violations
- Async review culture: reviewers expected to start review within 4 hours of being assigned

---

## On-Call Burden

**Why it destroys teams**: unmanaged on-call is the fastest path to engineer burnout and attrition. Engineers who spend 2 nights per week getting paged will leave within 6 months.

**Measurement framework**:

```
Metrics to track per engineer per week:
  1. Number of pages received (total)
  2. Number of pages outside business hours (off-hours)
  3. Number of pages requiring > 30 min to resolve (high-severity)
  4. Total time spent on on-call incidents

Healthy targets:
  Pages per on-call rotation:    < 5 per week
  Off-hours pages:               < 2 per rotation
  Incident response time:        < 2h total per on-call week
  Rotations before same engineer repeats: > 6 (7+ engineers in rotation)
```

**Alert volume as a leading indicator**: if total alerts (including auto-resolved) are increasing, noisy alerts are coming, which leads to alert fatigue, which leads to real pages being missed.

```
Alert health targets:
  Alert-to-action ratio: > 50% of alerts require human action (rest = noise)
  Auto-resolved alerts: < 30% of total (too many = overly sensitive)
  False positive rate:  < 5% (paged for non-incident = destroys trust)
```

**SRE-inspired resolution**:
- Every on-call rotation, each engineer files a "on-call report" — number of pages, root causes, any toil they want automated
- Platform/SRE team tracks recurring toil and systematically eliminates it
- Target: 50% reduction in on-call interrupt rate per 6 months of investment

**Google's model**: each team has an SLO for on-call burden. If the rotation is too noisy, the team pauses feature work and invests in reliability. The SLO makes this non-negotiable — not a judgment call.

---

## Tech Debt Accumulation Rate

**Why it signals team health**: tech debt is a proxy for team sustainability. A team accumulating debt faster than they pay it down is borrowing against their future velocity.

```
Measurement approach:
  Tool: SonarQube "debt" metric in hours
  Track: debt added per sprint (new code introduced debt) 
         debt paid per sprint (refactoring, cleanup work)
  
  Net debt delta = debt added - debt paid
  
  Healthy: net delta ≈ 0 (debt stable)
  Warning: net delta > 5% of sprint capacity for 3+ sprints (debt accelerating)
  Critical: team is not allocating any capacity to debt payment
```

**Leading indicator relationship**: high tech debt → slower feature development → less capacity → more pressure → more shortcuts → more debt (doom loop).

Healthy teams reserve 10–15% of sprint capacity for tech debt and proactively track debt-to-velocity ratio.

---

## Engineer Satisfaction (eNPS)

**Definition**: Net Promoter Score applied to engineer satisfaction. "On a scale of 0–10, how likely are you to recommend working on this team to a colleague?"

```
eNPS = % Promoters (9–10) - % Detractors (0–6)

Benchmark:
  > 40:  Excellent — strong culture, high satisfaction
  20–40: Good — solid foundation, addressable concerns
  0–20:  Neutral — watch for attrition risk
  < 0:   Concerning — significant dissatisfaction, investigate urgently

Survey cadence: quarterly (not monthly — survey fatigue is real)
Response rate target: > 80% (low response rate itself is a signal)
```

**Follow-up questions to ask** (open text, anonymized):
- "What's the one thing we could change to make this team better?"
- "What's the one thing you'd hate to lose?"

Trends matter more than absolute scores. A team declining from 35 to 15 over 3 quarters needs intervention. A team stable at 25 is sustainable.

**At FAANG**: eNPS is tracked at team level by HR and engineering leadership. Teams below threshold get coaching; managers are accountable for team health scores in their performance review.

---

## Team Health Dashboard

**Spotify's Squad Health Check model** (adapted for principal engineer use):

Run quarterly with the team (anonymous voting):

| Dimension | 🟢 Healthy | 🟡 Some concerns | 🔴 Needs attention |
|-----------|-----------|-----------------|-------------------|
| **Easy to release** | Shipping feels smooth; pipeline < 15 min | Some friction; occasional painful deploys | Deploys are stressful events; failures common |
| **Suitable process** | Process supports the work; minimal overhead | Some overhead but manageable | Process feels like an obstacle; too much ceremony |
| **Tech quality** | Code is clean; easy to add features | Increasing complexity; some areas scary | Large areas of unmaintainable code |
| **Fun** | Team enjoys the work; positive energy | Some frustration; work is OK | Not fun; draining |
| **Health of codebase** | Easy to change; tests catch regressions | Mixed; some areas more risky | Fragile; changes break things often |
| **Learning** | Team is growing; learning opportunities exist | Learning is passive; few structured opportunities | No time to learn; same work every sprint |
| **Mission** | Team understands and is proud of impact | Some ambiguity about mission | Unclear what the team is building or why |
| **Support** | Management and platform support is good | Some gaps in support | Team feels unsupported |

Aggregate scores to identify systemic patterns. A team with three 🔴 dimensions needs immediate attention from the EM and principal engineer together.

---

## Attrition: The Lagging Indicator to Never Ignore

**Voluntary attrition** (engineers leaving by choice) is the most expensive lagging indicator:
- Replacement cost: 1.5–2× annual salary (recruiting, onboarding, ramp-up)
- Knowledge loss: departing engineers take context that takes 6–12 months to rebuild
- Team morale: attrition is contagious — one departure often triggers others

```
Track:
  Rolling 12-month voluntary attrition rate
  Regrettable attrition rate (high-performer departures specifically)

Healthy: < 10% annual voluntary attrition
Warning: 10–20% — investigate root causes
Critical: > 20% — team is in crisis; intervention required
```

**Leading indicators of attrition risk** (track these before people leave):
- eNPS declining for 2+ consecutive quarters
- On-call burden increasing without relief
- Velocity declining without external explanation
- Key engineers requesting fewer high-visibility projects (disengagement signal)
- Exit interview themes recurring in stay interviews

---

## FAANG Interview Callouts

**Q: You join a team as principal engineer. After 2 weeks you notice: 3 PRs sitting > 5 days without review, on-call engineer was paged 11 times last week, and the last 2 sprints completed < 70% of planned work. What do you do first?**

These are three independent symptoms that likely share a root cause: the team is chronically overloaded. Sequence:

1. **Immediate**: pair with the EM to audit the interrupt rate. 11 on-call pages in a week is an SRE emergency, not a "we'll fix it later" situation. Triage the alert sources — most are probably noisy alerts from one or two services.

2. **This week**: talk to engineers 1:1. Why are PRs sitting? Overloaded reviewers? No review ownership? Large PRs nobody wants to start? The data is the symptom; engineers know the cause.

3. **Next sprint**: propose one dedicated reliability/cleanup sprint. No new features. Reduce the on-call noise by 50%. Pay down the backlog of PRs. This buys goodwill and creates space for sustainable work.

4. **One month**: re-measure all three metrics. If they haven't improved, the root cause is structural (team understaffed, tech debt too deep) — escalate to hiring or a multi-quarter debt paydown initiative.

**Q: An engineer on your team is clearly burning out. eNPS has been declining, they've been on-call 3× in 2 months. What do you do as principal engineer?**

First — this is primarily the EM's responsibility, not the principal engineer's. But principal engineers have influence:

Immediate action (this week):
- Remove them from the next on-call rotation. Find cover.
- Reduce their sprint commitments by 30%. Protect space for recovery.
- Have a direct conversation: "I've noticed you seem stretched. What's actually going on? What would help most?"

Structural fix (next 4–6 weeks):
- On-call burden is a system problem: add engineers to the rotation, reduce alert noise, or both
- If the rotation is < 5 people: escalate to hire or transfer someone into the rotation
- Document on-call incidents and use them to drive a reliability OKR next quarter

What not to do: tell them to "push through" or imply the overload is temporary when it's been going on for months. Engineers experiencing burnout make that decision based on actions, not words.
