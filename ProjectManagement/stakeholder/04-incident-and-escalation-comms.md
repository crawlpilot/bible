# Incident and Escalation Communications

## Why This Matters

How you communicate during and after an incident defines your leadership reputation more than the incident itself. Executives and peers form lasting impressions based on: Did you communicate proactively? Did you give accurate information under pressure? Did you own the outcome, or deflect?

Principal engineers own the narrative during major incidents — not the on-call rotation, not the PM.

---

## Incident Severity Classification

| Severity | Definition | Customer Impact | Response SLA |
|----------|-----------|-----------------|-------------|
| **P0 — Critical** | Complete outage or data loss | All users affected | Page immediately; war room in < 15 min |
| **P1 — High** | Major degradation affecting core flow | > 10% of users or key cohort | Response in < 30 min |
| **P2 — Medium** | Partial degradation, workaround exists | < 10% users; SLA at risk | Response in < 2 hours |
| **P3 — Low** | Minor issue, no SLA impact | Minimal or no visible impact | Next business day |

---

## The Three Phases of Incident Communication

```
┌──────────────────────────────────────────────────────────────────┐
│  PHASE 1: DETECT & DECLARE (0–15 min)                            │
│  Goal: Alert the right people; establish command structure        │
├──────────────────────────────────────────────────────────────────┤
│  PHASE 2: RESPOND & UPDATE (15 min – resolution)                 │
│  Goal: Regular status cadence; set expectations; unblock eng      │
├──────────────────────────────────────────────────────────────────┤
│  PHASE 3: RESOLVE & LEARN (post-resolution)                      │
│  Goal: Close the loop; document; prevent recurrence              │
└──────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Initial Incident Declaration

### Slack/Teams War Room Message (P0/P1)

```
🚨 INCIDENT DECLARED — [Severity]: [Short title]

What: [1 sentence — what is broken, not why]
Who's affected: [user cohort or % of traffic]
First detected: [HH:MM TZ]
Incident commander: [@name]
Status page: [link if public-facing]

Current hypothesis: [leading theory — be honest if unknown]
Immediate action: [what is being done RIGHT NOW]

Update in 30 minutes or when status changes.
[incident channel link]
```

**Principles for Phase 1:**
- Declare early, even with incomplete information — "under investigation" is better than silence
- Name one incident commander; avoid distributed ownership during a crisis
- Separate the investigation channel from the update channel

### Executive Notification (P0 only)

Send to direct manager + their manager within 15 minutes.

```
[P0 INCIDENT] [Service Name] — [Short description]

We are experiencing a [P0/P1] incident with [Service].
Impact: [customer-facing description of impact]
Started: [HH:MM TZ, MM/DD]
Incident commander: [Name]
Working on: [what the team is actively investigating]

Next update: [HH:MM] or sooner if resolved.
```

Short. No speculation on root cause. No technical jargon. No blame.

---

## Phase 2: Status Updates During the Incident

### Update Cadence

| Severity | Update interval | Channel |
|----------|----------------|---------|
| P0 | Every 20-30 min | War room + exec Slack |
| P1 | Every 30-45 min | War room + team Slack |
| P2 | Every 1-2 hours | Team Slack |

### Status Update Template

```
UPDATE [#N] — [HH:MM TZ]

Status: 🔴 Investigating | 🟡 Mitigating | 🟢 Resolved
Duration so far: [Xh Ym]

What we know:
- [Finding 1]
- [Finding 2]

What we're doing:
- [Action 1 — owner: @name]
- [Action 2 — owner: @name]

What we've tried that didn't work:
- [Attempt 1] — ruled out because [reason]

Current hypothesis: [best current theory]
ETA to resolution: [estimate or "unknown — re-evaluating in 30 min"]

Next update: [HH:MM]
```

**Critical discipline:** Always share what you've ruled out. This prevents others from re-investigating dead ends.

---

## Phase 3: Incident Resolution and Post-Mortem

### Resolution Announcement

```
✅ RESOLVED — [Incident Title]

Resolved at: [HH:MM TZ]
Total duration: [X hours Y minutes]
Root cause (preliminary): [1-2 sentences]
Fix applied: [what was done to restore service]

Customer impact:
- [N users affected] over [X hours]
- [Error rate peak] at [HH:MM]
- [Any data loss? Yes/No]

What's next:
- Post-mortem scheduled: [date/time]
- Short-term stability fixes: [owner, ETA]
- Long-term prevention: TBD in post-mortem

Thank you to everyone who responded: [@names]
```

---

## Post-Mortem Write-Up

The post-mortem is a **blameless learning document**, not a root cause report for punishment. Its purpose: prevent recurrence and build institutional knowledge.

### Post-Mortem Template

```markdown
# Post-Mortem: [Incident Title]
**Date of incident:** YYYY-MM-DD
**Duration:** HH:MM – HH:MM (X hours)
**Severity:** P0 / P1
**Author:** [Principal Engineer name]
**Review meeting:** [date]
**Status:** Draft | Under Review | Final

---

## Impact Summary

| Dimension | Details |
|-----------|---------|
| Users affected | [N users, % of total] |
| Revenue impact | [$X or N/A] |
| SLA breach | Yes / No — [SLO affected] |
| Data loss | Yes / No |
| Regions | [us-east-1, eu-west-1, etc.] |

---

## Timeline

All times in UTC.

| Time | Event |
|------|-------|
| HH:MM | First alert triggered |
| HH:MM | On-call acknowledged |
| HH:MM | Incident declared P1 |
| HH:MM | Root cause identified |
| HH:MM | Mitigation applied |
| HH:MM | Incident resolved |
| HH:MM | Post-mortem opened |

---

## Root Cause Analysis

### What happened
[2-3 paragraphs — factual, no blame, no editorializing]

### Why it happened (5 Whys)

1. **Why did users see errors?** Because the auth service returned 503s
2. **Why did auth return 503s?** Because its database connection pool was exhausted
3. **Why was the pool exhausted?** Because a slow query caused connections to back up
4. **Why did the slow query start?** Because a missing index on a 200M-row table after a schema migration
5. **Why was the index missing?** Because the migration script was reviewed but its performance impact on production data volume was not tested

**Root cause:** Missing index on high-cardinality column in a migration that was tested only on staging data (10k rows vs. 200M in production).

### Contributing factors
- [ ] No pre-migration load test on production-size data
- [ ] Connection pool exhaustion had no alerting before saturation
- [ ] Migration review checklist did not include index validation step

---

## Detection

- How was the incident detected? [Alert / customer report / automated monitoring]
- Time from first symptom to detection: [X minutes]
- Gap: [e.g., latency degradation started 8 minutes before the alert fired — alert threshold too high]

---

## Response Effectiveness

| Phase | Duration | What worked | What could improve |
|-------|---------|-------------|-------------------|
| Detection | 8 min | PagerDuty alert | Alert threshold should be lower |
| Diagnosis | 45 min | Query profiling tools available | No runbook for connection pool exhaustion |
| Mitigation | 12 min | Feature flag rollback worked | Rollback took 2 manual steps; should be one-click |
| Communication | Throughout | Exec updates every 30 min | First customer notification was 20 min late |

---

## Action Items

| # | Action | Owner | Priority | Due Date |
|---|--------|-------|----------|---------|
| 1 | Add index validation step to migration review checklist | [Eng] | P0 | [date] |
| 2 | Add connection pool saturation alert at 70% | [SRE] | P1 | [date] |
| 3 | Create runbook for database connection pool exhaustion | [Eng] | P1 | [date] |
| 4 | Automate pre-migration load test against production-size dataset | [Platform] | P2 | [date] |
| 5 | One-click rollback for schema migrations | [Eng] | P2 | [next Q] |

---

## Lessons Learned

What we learned (for the team's benefit):
1. [Lesson 1 — concrete and actionable]
2. [Lesson 2]

What we did well (reinforce this):
1. [Positive observation 1]
2. [Positive observation 2]

---

## Acknowledgements

[Short paragraph thanking responders by name. Recognizing effort during incidents builds psychological safety for the next one.]
```

---

## Escalation Communication Playbook

### When to escalate

Escalate when:
- A blocker has not been resolved in > 2 business days at peer level
- A risk is likely to breach a committed deadline and exec visibility is needed
- A decision requires authority that neither you nor your manager has
- Two teams are deadlocked and cannot self-resolve

Do **not** escalate when:
- You haven't attempted peer resolution
- You're frustrated but not blocked
- You want to apply pressure (this burns trust)

### Escalation Email Template

```
Subject: [ESCALATION] [Project] needs [specific ask] by [date]

[Recipient name],

I need your help resolving a blocker on [project] that we have been unable to 
resolve at the working level.

THE BLOCKER
[Team X] and [our team] have been unable to reach agreement on [Y] for [N weeks].
This is blocking [specific milestone], which will slip by [X weeks] without resolution.

THE DECISION NEEDED
[State the decision clearly — not a complaint, but a specific question that needs answering]

BACKGROUND
- We've attempted resolution via [N meetings, async threads, ADR review]
- The core disagreement is: [balanced one-paragraph summary of both sides]
- Our recommendation: [Option + one-sentence rationale]
- [Team X]'s position: [their position and rationale, fairly stated]

OPTIONS
A. [Option A] — consequences
B. [Option B] — consequences
C. [our recommendation — Option C] — consequences

I'm happy to set up a 30-minute call with all parties if that helps.
We need a resolution by [date] to avoid the milestone slip.

[Your name]
```

**The key discipline:** State the other team's position fairly and completely. If you misrepresent their view, you lose credibility even if you're right.

---

## FAANG Interview Application

**When you'll be asked about this:**
- "Tell me about a major incident you led — what did you do?"
- "How do you communicate technical failures to executive stakeholders?"
- "Describe a time you had to escalate a critical risk"

**What they're evaluating:**
- Incident command: did you provide structure or chaos?
- Communication under pressure: accurate, calm, timely updates
- Blameless culture: do you hunt root causes or scapegoats?
- Follow-through: did you drive action items to completion?

**Principal-level signal:**
A senior engineer fixes the incident. A principal engineer leads the response, manages the narrative with executives, runs a blameless post-mortem, and drives systemic changes that prevent the class of problem — not just this instance.
