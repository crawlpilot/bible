# Steering Committee Updates

## What Is a Steering Committee?

A steering committee is a cross-functional group of senior leaders (VPs, Directors, PMs, Finance) that governs a major initiative. As the principal engineer, you are typically the technical DRI who presents to this body on a regular cadence (monthly or quarterly).

Your job: give them the information they need to unblock you, surface risks early, and make resource decisions — without overwhelming them with technical detail.

---

## Cadence and Format

| Cadence | Format | Duration | Audience |
|---------|--------|----------|---------|
| Monthly | Dashboard + narrative | 30 min | VP-level sponsors, PM leads |
| Quarterly | Full review deck | 60 min | VPs, Directors, Finance |
| Ad hoc | Incident brief or decision brief | 15-30 min | Decision owners only |
| Weekly | Async written update (no meeting) | Self-serve | Broad stakeholders |

**Principle:** Protect executive time. One async update per week. One live meeting per month maximum for a given initiative.

---

## Steering Committee Deck Structure

### Slide 1: Executive Summary (30 seconds)

```
[Project Name] — [Q3 2024] Steering Committee Review

Status: 🟢 On Track / 🟡 At Risk / 🔴 Critical

ONE SENTENCE: What is the current state?

Top 3 things to know today:
1. [Milestone/decision/risk — one line each]
2.
3.

Decision needed: [explicit ask, or "No decision needed today"]
```

### Slide 2: Progress vs. Plan

```
MILESTONE TRACKER

| Milestone | Plan Date | Actual/Forecast | Status |
|-----------|-----------|-----------------|--------|
| Alpha launch | Jun 1 | Jun 1 ✅ | Done |
| Beta: 10% traffic | Jul 15 | Jul 15 🟢 | On track |
| GA: 100% | Sep 1 | Sep 15 🟡 | 2-week slip |
| Deprecation of V1 | Q4 | TBD 🔴 | Blocked |

2-WEEK SLIP REASON:
[One sentence — what slipped, why, what's being done]
```

### Slide 3: Health Dashboard

A single-glance view of system and team health. Four quadrants:

```
┌────────────────────┬────────────────────┐
│  DELIVERY HEALTH   │  SYSTEM HEALTH     │
│                    │                    │
│  Velocity: ↑ 15%   │  Availability: 99.9│
│  Blockers: 2 open  │  p99 latency: 180ms│
│  Scope change: +5% │  Error rate: 0.01% │
│  Carry-over: 8%    │  On-call load: Low │
├────────────────────┼────────────────────┤
│  RISK REGISTER     │  TEAM HEALTH       │
│                    │                    │
│  🔴 Dependency X   │  Morale: 🟢        │
│  🟡 Scale risk Q4  │  Headcount: 2 open │
│  🟢 Security audit │  Attrition: 0 QTD  │
│     complete       │  Eng/PM ratio: 5:1 │
└────────────────────┴────────────────────┘
```

### Slide 4: Risk Register

Never present risks without mitigations. Never present mitigations without status.

```
RISK REGISTER — [Date]

| # | Risk | Likelihood | Impact | Owner | Mitigation | Status |
|---|------|-----------|--------|-------|-----------|--------|
| 1 | Auth service capacity insufficient for GA | High | Critical | [name] | Capacity scaling plan approved, provisioning in progress | 🟡 In progress |
| 2 | Mobile team dependency for SDK update | Med | High | [name] | Escalated to VP Mobile; aligned on Aug 15 release | 🟢 Resolved |
| 3 | Regulatory review may block EU launch | Low | High | [name] | Legal engaged; preliminary review positive | 🟢 Monitoring |

NEW this period: Risk #1 moved from Low → High due to load test results (see appendix).
```

**Risk log discipline:**
- Add new risks immediately, don't wait for the meeting
- Close risks explicitly (resolved vs. accepted vs. retired)
- Never have more than 5 active high/critical risks — if you do, reprioritize

### Slide 5: Decisions and Dependencies

```
OPEN DECISIONS

| Decision | Options | Recommendation | Owner | Needed By |
|----------|---------|----------------|-------|-----------|
| Database for user profiles | PostgreSQL vs DynamoDB | DynamoDB (see ADR-017) | VP Eng | Jul 1 |
| GA traffic ramp strategy | 10%/wk vs accelerated | 10%/wk (safer, minimal cost) | PM | Jul 15 |

CROSS-TEAM DEPENDENCIES

| Dependency | Team | Status | Risk if Late |
|-----------|------|--------|-------------|
| OAuth2 SDK update | Platform Team | On track ✅ | Blocks login flow |
| Billing API contract | Payments Team | 2-week delay 🟡 | Delays premium tier launch |
```

### Slide 6: Next Period Plan

```
NEXT 30 DAYS

Must-do (launch blockers):
□ [M1]: [owner], [target date]
□ [M2]: [owner], [target date]

Should-do (schedule risk if missed):
□ [S1]: [owner], [target date]

Decisions we need by next meeting:
□ [D1] — decision owner: [name]
□ [D2] — decision owner: [name]
```

---

## Dashboard Metrics: What to Track

### Delivery Metrics

| Metric | Description | Target |
|--------|-------------|--------|
| Planned vs. actual velocity | Story points delivered / committed | ≥ 90% |
| Scope creep % | Unplanned work added vs. original scope | ≤ 10% |
| Milestone slip count | Milestones that moved vs. original plan | ≤ 1/quarter |
| Blocker resolution time | Avg time from blocker raised to resolved | ≤ 3 days |

### System Health Metrics

| Metric | Description | Target |
|--------|-------------|--------|
| Availability | Monthly uptime SLA | ≥ 99.9% |
| p99 latency | 99th percentile response time | Per SLO |
| Error rate | 5xx rate | < 0.1% |
| Incident count | P0/P1 incidents per month | 0 P0, ≤ 2 P1 |
| On-call load | Alerts per week per on-call engineer | ≤ 5 actionable |

### Business Metrics (connect to why project exists)

| Metric | Example |
|--------|---------|
| Feature adoption | 30-day active users of new feature |
| Business outcome | Revenue enabled, cost saved, latency reduced |
| Customer impact | NPS delta, support ticket reduction |

---

## Common Steering Committee Pitfalls

### Pitfall 1: Burying the lede
Opening with 10 slides of context before getting to the status. Executives will interrupt or disengage.  
**Fix:** Status on slide 1, always.

### Pitfall 2: Reporting activity instead of outcomes
"We completed 47 tickets this sprint."  
**Fix:** "We launched the auth module to 10% of users with p99 = 150ms."

### Pitfall 3: Presenting risks without owners or mitigations
Executives hear: "There are problems and nobody owns them."  
**Fix:** Every risk has an owner, a mitigation plan, and a status.

### Pitfall 4: Asking for decisions in the meeting without pre-wiring
A surprise decision request in a committee meeting almost always gets deferred.  
**Fix:** Pre-wire all decisions async at least 48 hours before the meeting. The meeting is for confirmation, not deliberation.

### Pitfall 5: Tech jargon in an exec forum
"We're migrating from a monolith to microservices with an event-driven Kafka backbone."  
**Fix:** "We're rebuilding our core infrastructure to handle 10x more traffic, reduce deployment risk, and let teams ship independently."

---

## Pre-Meeting Checklist

```
48 hours before:
□ Send async update with deck draft to key stakeholders
□ Identify any decisions that need pre-wiring; schedule 1:1s
□ Get sign-off from PM/EM co-presenter on key messages

24 hours before:
□ Incorporate feedback from pre-wiring conversations
□ Confirm decision owners will attend
□ Prepare 2-3 likely questions and your answers

Day of:
□ 5-min tech check for screen share
□ Have appendix ready with technical detail for deep-dive questions
□ Know which risks you'll escalate if not resolved
```

---

## FAANG Interview Application

**When you'll be asked about this:**
- "Describe a time you drove alignment across multiple teams"
- "How do you keep senior leaders informed without overwhelming them?"
- "Tell me about a time you escalated a risk — what happened?"

**What they're evaluating:**
- Structured communication under complexity
- Ability to manage up and across without losing credibility
- Proactive risk management, not reactive firefighting

**Principal-level signal:**
You own the narrative. You don't just report status — you shape how the initiative is perceived, surface risks before they become crises, and make it easy for executives to make the decisions you need them to make.
