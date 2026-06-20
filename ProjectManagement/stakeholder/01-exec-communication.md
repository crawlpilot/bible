# Executive Communication for Principal Engineers

## Why This Matters at the Principal Level

Principal engineers operate in the executive information flow — you write docs that VPs forward without editing, you present in QBRs, and your written assessment shapes budget decisions. Poor exec communication kills otherwise excellent technical work. Good exec communication multiplies your influence.

---

## Core Principle: The Pyramid Structure

Every exec communication starts with the conclusion, not the journey.

```
┌─────────────────────────────────────────────────────┐
│  RECOMMENDATION / ASK (one sentence)                 │
├─────────────────────────────────────────────────────┤
│  KEY SUPPORTING ARGUMENT 1 | 2 | 3                  │
├─────────────────────────────────────────────────────┤
│  Evidence, data, context (optional — appendix)       │
└─────────────────────────────────────────────────────┘
```

Rule: If someone reads only the first paragraph, they must understand what you want and why.

---

## Template 1: One-Pager Briefing

Used for: new initiative proposal, technology decision needing exec sign-off.

```
Title: [Decision or Initiative Name]
Date: YYYY-MM-DD
Authors: [Principal Engineer] + [PM/EM sponsor]
Status: Requesting Approval | FYI | Discussion

─── TLDR ───────────────────────────────────────────
[2-3 sentences: what we want to do, why now, and what we need from the reader]

─── BUSINESS CONTEXT ───────────────────────────────
Problem: [Business problem in business language — not tech jargon]
Cost of inaction: [What happens if we do nothing? Revenue risk, reliability, attrition]
Opportunity: [What does success look like in customer or revenue terms?]

─── PROPOSED APPROACH ──────────────────────────────
[What we will build or change, in 3-5 bullet points]
Timeline: [Quarters or milestones, not weeks]
Investment: [Eng headcount, infra cost, opportunity cost]

─── RISKS ──────────────────────────────────────────
| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| [R1] | Med | High | [M1] |
| [R2] | Low | High | [M2] |

─── SUCCESS METRICS ────────────────────────────────
- Primary: [the one number that proves success]
- Secondary: [1-2 supporting metrics]
- 90-day checkpoint: [early signal metric]

─── ASK ────────────────────────────────────────────
[Explicit ask: approve headcount, unblock dependency, make a prioritization call]
Decide by: [date — why this date matters]
```

---

## Template 2: Weekly/Bi-Weekly Status Update

Used for: recurring stakeholder updates on a major initiative.

```
[Project Name] — Status Update [Week/Sprint #]

Status: 🟢 On Track | 🟡 At Risk | 🔴 Blocked

─── THIS WEEK ──────────────────────────────────────
✅ Completed: [2-3 bullet points — outcomes, not tasks]
🚧 In Progress: [2-3 active threads]
🔜 Next Week: [top priority items]

─── KEY NUMBERS ────────────────────────────────────
| Metric | Target | Actual | Trend |
|--------|--------|--------|-------|
| [M1]   | [X]    | [Y]    | ↑/↓/→ |
| [M2]   | [X]    | [Y]    | ↑/↓/→ |

─── DECISIONS NEEDED ───────────────────────────────
1. [Decision]: [options + recommendation] — need answer by [date]

─── RISKS / BLOCKERS ───────────────────────────────
🔴 BLOCKER: [what is blocked, what is needed to unblock, owner]
🟡 RISK: [risk description, probability, mitigation plan]

─── LINKS ──────────────────────────────────────────
Design doc | Jira board | Dashboard | Slack channel
```

**What NOT to include:**
- Lists of completed Jira tickets
- Technical implementation details (save for appendix)
- Problems without recommended solutions
- Blame or finger-pointing

---

## Template 3: Escalation Email

Used for: unblocking a dependency, surfacing a risk that needs exec intervention.

```
Subject: [ESCALATION] [Project] — [Decision needed] by [Date]

[Name],

I need your help unblocking [X] to keep [Project] on track for [Q3/Launch/etc].

THE SITUATION
[Team/dependency X] and [our team] have been unable to align on [Y] for [N weeks].
This is blocking us from [outcome], which puts [business impact] at risk.

THE ASK
I need you to [specific action: make a call, connect me with Z, unblock resource Y]
by [date], otherwise we will [consequence: slip launch by 2 weeks, incur $X infra cost].

BACKGROUND
- We've had [N] sync meetings with [team]; last meeting [date] ended without resolution
- Root cause of disagreement: [one paragraph, balanced view of both sides]
- Options we've considered: [2-3 brief options]
- Our recommendation: [option + one-sentence rationale]

I'll send a follow-up with the outcome either way.

[Your name]
[Slack handle]
```

**Escalation anti-patterns to avoid:**
- Escalating before attempting peer resolution (always try first)
- Escalating with a complaint, not a decision request
- CC'ing too many people (creates politics, not resolution)
- Emotional language or assigning blame

---

## Template 4: Go/No-Go Decision Brief

Used for: launch readiness reviews, release decisions.

```
[Feature/System] — Go/No-Go Brief
Decision needed: [date]
Decision owner: [VP/Director name]

RECOMMENDATION: GO | NO-GO | CONDITIONAL GO

─── READINESS SUMMARY ──────────────────────────────
| Dimension | Status | Notes |
|-----------|--------|-------|
| Functional completeness | ✅ | All P0/P1 complete |
| Performance targets | ✅ | p99 < 200ms at 10k QPS |
| Security review | ✅ | No critical findings |
| On-call runbook | ✅ | Reviewed and tested |
| Rollback plan | ✅ | Feature flagged, 5-min rollback |
| Customer support readiness | 🟡 | Training in progress |
| Capacity provisioned | ✅ | 2x headroom for launch |

─── OUTSTANDING ITEMS ──────────────────────────────
| Item | Severity | Owner | ETA | Launch Blocker? |
|------|----------|-------|-----|----------------|
| [I1] | P2 | [eng] | [date] | No |

─── RISK ACCEPTANCE ────────────────────────────────
Known risks we are accepting at launch:
1. [Risk]: [why we're accepting, mitigation in place]

─── LAUNCH PLAN ────────────────────────────────────
- Stage 1 (Day 0): 1% traffic, internal users only
- Stage 2 (Day 2): 10% if no P0 incidents
- Stage 3 (Day 5): 100% with automated rollout
```

---

## Writing Calibration: Tech vs Exec Language

| Don't say (tech) | Say instead (exec) |
|---|---|
| We have P99 latency of 800ms | Users experience 0.8s delays, impacting checkout completion |
| We're hitting OOM errors under load | The system fails under Black Friday traffic levels |
| The schema migration will take 2 weeks | We need a 2-week code freeze to upgrade the database safely |
| We have 40% test coverage | We have limited ability to detect regressions before they reach customers |
| The monolith is unmaintainable | Adding features takes 3x longer than our competitors; this gap widens each quarter |
| Kafka consumer lag is 500k messages | Notifications are delayed up to 90 minutes during peak load |

---

## FAANG Interview Application

**When you'll be asked about this:**
- "Tell me about a time you influenced a decision without authority"
- "How do you communicate technical complexity to non-technical stakeholders?"
- "Describe a time you escalated a risk — what happened?"

**What they're evaluating:**
- Can you translate engineering work to business outcomes?
- Do you communicate proactively (not reactively)?
- Can you drive alignment across organizational boundaries?
- Do you make decisions easy for executives, or harder?

**Principal-level signal:**
A senior engineer explains the technical decision. A principal engineer explains the *business consequence* of the technical decision, gives executives a clear choice with explicit trade-offs, and pre-wires alignment before the meeting.
