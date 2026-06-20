# OKRs — Objectives & Key Results

## Origin and Adoption

OKRs were invented by Andy Grove at Intel in the 1970s, introduced to Google by John Doerr in 1999, and subsequently adopted by virtually every major tech company: Google, LinkedIn, Twitter, Uber, Airbnb, Spotify. The book *Measure What Matters* (Doerr, 2018) documented the framework and drove widespread adoption.

**Why OKRs dominate tech**: they solve the alignment problem at scale. With 10,000 engineers across 200 teams, how do you ensure everyone is pulling in the same direction without micromanaging? OKRs create a visible, shared goal structure that cascades from company → org → team → (optionally) individual.

---

## The Structure

### Objective
A qualitative, aspirational, time-bound statement of **what** you want to achieve.

Rules for a good objective:
- Inspirational — should motivate the team, not describe tasks
- Qualitative — no numbers in the objective itself (numbers belong in KRs)
- Achievable in the timeframe (typically one quarter)
- Clear without context — someone from another team should understand it

**Bad objective**: "Improve the payment service"
**Good objective**: "Make the checkout experience fast and reliable enough that payment errors stop being a customer complaint"

### Key Results
Quantitative, measurable outcomes that prove you achieved the objective.

Rules for a good key result:
- Measurable — a specific number you can track
- Outcome-focused, not output-focused (measure impact, not activity)
- 2–5 per objective (more is dilution)
- Ambitious but achievable — should require real effort; 100% attainment means too easy
- Graded 0.0–1.0 at end of quarter

**Bad KR**: "Launch new payment retry logic" — this is a task (output), not an outcome
**Good KR**: "Reduce payment timeout errors from 2.1% to < 0.5%"

### Initiatives / Projects
The work (tasks, projects, features) you plan to do in order to achieve the KRs. These are not OKRs — they are the "how," not the "what."

```
Objective: Make checkout fast and reliable
  KR1: Reduce payment timeout errors from 2.1% → 0.5%
  KR2: Reduce checkout p99 latency from 3.2s → 1.0s
  KR3: Increase payment success rate from 97.8% → 99.2%

  Initiatives (the work):
    - Implement retry logic with exponential backoff
    - Migrate payment service to async processing
    - Add circuit breaker for downstream payment provider
    - Optimize DB query in checkout critical path
```

---

## OKR Levels and Cascading

```
Company OKR (annual or semi-annual)
  "Become the most trusted payment platform in Southeast Asia"
         │
         ▼
Org/Division OKR (quarterly)
  "Achieve 99.9% payment reliability across all markets"
         │
         ▼
Team OKR (quarterly)
  "Make checkout fast and reliable..."
  KR1: timeout errors < 0.5%
  KR2: p99 latency < 1.0s
         │
         ▼
Individual OKR (optional — many companies skip this level)
  Engineer owns KR1 as their focus for the quarter
```

**Key principle**: team OKRs should directly contribute to org OKRs. If you can't draw a clear line from a team KR to an org KR, question whether that team OKR is the right priority.

---

## Grading OKRs

OKRs are graded 0.0–1.0 at end of quarter.

| Score | Meaning |
|-------|---------|
| 1.0 | Fully achieved — rare and should prompt reflection: was it too easy? |
| 0.7 | Stretch goal achieved — the target zone for most KRs |
| 0.5 | Partial progress — worth analyzing blockers |
| 0.3 | Little progress — serious concerns about priority or feasibility |
| 0.0 | No progress — requires explanation |

**The 70% rule**: OKRs are designed to be stretch goals. If a team consistently scores 1.0, their OKRs are too conservative. The target average score is 0.6–0.7. Scoring 0.4 on a genuinely ambitious KR is not failure — it's information.

**Never use OKR scores for performance reviews.** OKRs are organizational tools. Using them to evaluate individuals destroys honest goal-setting — teams will set conservative KRs they know they can hit.

---

## OKR Cadence

### Annual OKRs (company/org level)

- Set in Q4 for the following year
- Directional, qualitative, stable for the year
- "North star" that quarterly OKRs cascade from

### Quarterly OKRs (team level)

```
Week 1–2 of quarter:
  - Review previous quarter's OKR grades
  - Retrospective on what drove success/failure
  - Draft new quarter OKRs (top-down context + bottom-up input)
  - Align with adjacent teams for dependencies

Week 2–3:
  - Cross-team alignment session — check for conflicts and gaps
  - Leadership review — do team OKRs add up to org OKR?
  - Finalize and publish

Mid-quarter check-in (week 6–7):
  - Score each KR on current trajectory (0.0–1.0)
  - Are we on track? What's blocking?
  - Scope adjustments (not goal downgrades — scope of initiatives)

End of quarter:
  - Final grade each KR
  - Write brief retrospective per KR
  - Feed learnings into next quarter planning
```

---

## Engineering OKR Examples

### Platform / Infrastructure Team

```
Objective: Give every product team a reliable, self-service deployment experience

KR1: Reduce mean deploy pipeline duration from 45 min → 15 min
KR2: Increase golden-path adoption from 60% → 90% of services
KR3: Reduce pipeline-related on-call interruptions from 8/week → 2/week
KR4: 100% of new services onboard via self-service (zero tickets to platform team)
```

### Security Team

```
Objective: Make security a frictionless part of every team's development workflow

KR1: Critical CVEs remediated within 72 hours (from avg 18 days)
KR2: SAST integrated into 100% of service pipelines (from 40%)
KR3: Security review cycle time reduced from 3 weeks → 3 days
KR4: Zero high-severity security findings in external penetration test
```

### Data Platform Team

```
Objective: Enable data-driven decisions for every product team without data eng bottleneck

KR1: Self-service dashboard creation covers 80% of analyst use cases (from 30%)
KR2: Data pipeline SLA violations reduced from 12/month → 2/month
KR3: Time to first data insight for new product teams reduced from 4 weeks → 3 days
KR4: Data quality score (% of pipelines with passing quality checks) from 65% → 95%
```

---

## Common OKR Anti-Patterns

### 1. Output OKRs (task lists disguised as KRs)

```
Bad:  KR1: "Launch feature X"
      KR2: "Complete migration Y"
      KR3: "Hire 2 engineers"
      → These are todos, not outcomes. Completing them proves nothing about impact.

Good: KR1: "Feature X reduces support ticket volume by 30%"
      KR2: "Migration Y reduces infrastructure cost by $200K/quarter"
      KR3: "Team capacity increases to sustain 20% more planned work per sprint"
```

### 2. Too many OKRs (dilution)

3 objectives × 4 KRs = 12 things to care about. Everything is important = nothing is important.

**Google's guidance**: max 3–5 objectives per quarter per team. Max 4 KRs per objective. If you have more, prioritize ruthlessly.

### 3. OKRs that don't cascade

A team sets OKRs in isolation. At quarter-end, the team scores 0.8 across all KRs — but the org failed its objectives. The work was good; it just wasn't the right work.

**Fix**: before finalizing team OKRs, each team lead must draw a line from every KR to the org OKR it contributes to. If the line doesn't exist — question the KR.

### 4. Set-and-forget OKRs

OKRs are written in week 1, never reviewed until week 13. By then it's too late to course-correct.

**Fix**: mandatory mid-quarter check-in with a written update per KR. Score it as of today — is it trending to 0.4 or 0.7? What changed?

### 5. Sandbagging (conservative OKRs)

Teams write OKRs they know they'll hit at 1.0. Leadership celebrates. Nothing ambitious was attempted.

**Fix**: if a team consistently scores > 0.85, ask them to raise their KR targets 25–30%. Calibrate over 2–3 quarters until average scores settle at 0.6–0.7.

---

## OKRs vs. KPIs

These are often confused. They serve different purposes and run in parallel.

| | OKRs | KPIs |
|--|------|------|
| Purpose | Drive change toward a goal | Monitor ongoing health |
| Cadence | Quarterly, set at start | Continuously measured |
| Content | Ambitious targets | Operational thresholds |
| Target | ~70% achievement (stretch) | 100% (maintain) |
| Example | "Reduce p99 latency to 200ms" | "p99 latency < 500ms (SLO)" |
| Action on miss | Adjust strategy | Investigate, incident response |

OKRs improve the baseline. KPIs guard the baseline. Both are needed. A team that only runs OKRs might break reliability while chasing improvements. A team that only runs KPIs never gets better.

---

## FAANG Interview Callouts

**Q: How do you use OKRs to align 5 teams that have conflicting priorities?**

OKRs surface the conflict — they don't resolve it automatically. The resolution process:

1. Have each team draft their OKRs independently
2. Run a cross-team OKR alignment session: each team presents, others flag conflicts and gaps
3. Map every KR to the shared org objective — if two teams have conflicting KRs, at least one doesn't map correctly
4. Escalate to the org leader who owns the objective: "Teams A and B are pulling in opposite directions on X — which KR takes priority?"

The org leader's job is to make that call. The OKR process is what surfaces it in week 2 of the quarter instead of week 10.

**Q: A VP says "just give me a date, I don't want to hear about OKRs." How do you respond?**

OKRs and dates are not in conflict. OKRs define what success looks like (the outcome). A project plan defines when you'll get there (the schedule). If the VP wants a date, the question is: "a date for what, specifically?" Use the KR as the success criterion and provide the PERT estimate for reaching it. The OKR makes the date meaningful — "we'll hit this metric by end of Q2" is more useful than "we'll be done with Feature X by June 30" because it defines what "done" actually means in terms of outcome.
