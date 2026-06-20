# RICE Prioritization

## What RICE Is

RICE is a scoring framework for prioritizing features, initiatives, or projects developed by Intercom. It converts subjective priority debates into a structured, data-backed score that can be compared across items.

**RICE stands for**: Reach × Impact × Confidence ÷ Effort

**When to use it**: you have a backlog of 10–50 items competing for limited engineering capacity and need a defensible way to decide the order.

---

## The Formula

```
RICE Score = (Reach × Impact × Confidence) / Effort
```

---

## Each Component

### Reach
**How many people does this affect per time period?**

- Unit: number of users/customers per quarter (or per month — pick one and be consistent)
- Source: product analytics, sales data, support ticket volume
- Avoid: guessing — use actual data when possible

| Example | Reach |
|---------|-------|
| Change to a feature used by all users | 50,000 users/quarter |
| Feature only for enterprise tier (5% of base) | 2,500 users/quarter |
| Internal tooling used by 10 engineers | 10 users/quarter |
| API used by 200 third-party integrations | 200 integrations/quarter |

### Impact
**How much does this move the needle for each person it reaches?**

Use a standardized scale — Intercom's recommended values:

| Score | Meaning |
|-------|---------|
| 3 | Massive impact — likely drives significant conversion, retention, or satisfaction change |
| 2 | High impact — noticeably better experience or meaningful metric movement |
| 1 | Medium impact — users notice but it's incremental |
| 0.5 | Low impact — nice-to-have, marginal improvement |
| 0.25 | Minimal — barely noticeable |

**Avoid**: debating exact scores for 30 minutes. Use the nearest value. RICE is a ranking tool, not a precise measurement.

### Confidence
**How confident are you in your Reach and Impact estimates?**

| Confidence | Multiplier | Meaning |
|------------|------------|---------|
| High | 100% (1.0) | Strong data, user research validated, similar shipped features |
| Medium | 80% (0.8) | Some data, reasonable assumptions, one data source |
| Low | 50% (0.5) | Gut feeling, limited data, novel territory |

Confidence is an honesty mechanism. It prevents high-reach, high-impact scores from being trusted when the data behind them is weak.

### Effort
**How many person-weeks (or months) does this take?**

- Unit: total person-weeks across all roles (eng + design + PM)
- Use team estimate, not manager estimate
- Include: engineering, design, QA, documentation, deployment
- Exclude: ongoing maintenance (that's a different analysis)

---

## Full Scoring Example

**Backlog** (payments team):

| Item | Reach (users/qtr) | Impact | Confidence | Effort (person-wks) | RICE Score |
|------|-------------------|--------|------------|----------------------|------------|
| Retry failed payments automatically | 50,000 | 2 | 80% | 3 | (50,000 × 2 × 0.8) / 3 = **26,667** |
| Add Apple Pay support | 20,000 | 2 | 100% | 8 | (20,000 × 2 × 1.0) / 8 = **5,000** |
| Improve checkout error messages | 50,000 | 0.5 | 100% | 1 | (50,000 × 0.5 × 1.0) / 1 = **25,000** |
| Multi-currency display in cart | 5,000 | 1 | 80% | 4 | (5,000 × 1 × 0.8) / 4 = **1,000** |
| Saved payment methods | 40,000 | 3 | 50% | 10 | (40,000 × 3 × 0.5) / 10 = **6,000** |
| Fix timezone bug in receipts | 500 | 1 | 100% | 0.5 | (500 × 1 × 1.0) / 0.5 = **1,000** |

**Priority order by RICE**:
1. Retry failed payments — 26,667 ✓ high confidence, high reach, low effort
2. Improve error messages — 25,000 ✓ easy win, high reach
3. Saved payment methods — 6,000 (but lower confidence — de-risk with user research first)
4. Apple Pay — 5,000
5. Multi-currency / Receipt bug — 1,000

**Insight surfaced by RICE**: "Retry failed payments" beats "Apple Pay" by 5× even though Apple Pay sounds more exciting. Error message improvements score nearly as high as retry logic at 10% of the effort — this is the kind of hidden value RICE reveals.

---

## Variants and Adaptations

### WSJF (Weighted Shortest Job First) — SAFe/Lean

Used in SAFe (Scaled Agile Framework). Formula:

```
WSJF = Cost of Delay / Job Duration

Cost of Delay = User/Business Value + Time Criticality + Risk Reduction/Opportunity Enablement
```

WSJF emphasizes the cost of NOT doing something (Cost of Delay) — particularly useful when you have time-sensitive features (competitive risk, regulatory deadline).

### ICE Scoring (simpler RICE)

```
ICE Score = Impact × Confidence × Ease
```

- Drops Reach (useful when all items affect the same user base)
- Replaces Effort with Ease (inverted — high ease = good)
- Faster to calculate; less precise

Use ICE for rapid prioritization of 20+ items when reach is roughly equal across all of them.

### MoSCoW Method

Categorizes items rather than scores them:

| Category | Definition |
|----------|------------|
| **M**ust Have | Non-negotiable for launch; without it, the product fails |
| **S**hould Have | High value, but workarounds exist; include if capacity allows |
| **C**ould Have | Nice-to-have; drop if under pressure |
| **W**on't Have (this time) | Explicitly out of scope; prevents scope creep |

**When to use MoSCoW**: for launch/release scoping decisions, not backlog prioritization. "What do we need to ship v1?" → MoSCoW. "Which of 50 features do we build in Q3?" → RICE.

---

## RICE in Multi-Team Prioritization

RICE becomes politically powerful at the cross-team level. When 5 teams each want their initiative prioritized in the shared platform roadmap, scoring everything with RICE makes the conversation about data instead of politics.

**Process**:
1. Each team submits their top 3 requests with RICE scores (they fill in Reach + Impact + Confidence; platform team estimates Effort)
2. Platform team scores all requests in a shared spreadsheet
3. Prioritize by RICE score with a capacity cap (total effort budget for the quarter)
4. Decisions are visible, data-backed, and challengeable on the numbers — not politics

**What "challenging a RICE score" looks like**:
- "Your reach estimate is 5,000 but our analytics show 18,000 users hit this code path per month" → update reach
- "You scored confidence at 50% but we have user research from 200 interviews" → update confidence
- "You estimated 8 person-weeks but we can supply an engineer familiar with the system" → update effort

The debate moves from "our team's priority is more important" to "the data shows X, here's the correction." This is principal engineer-level influence: structured reasoning replaces political capital.

---

## When RICE Breaks Down

| Situation | Problem | Alternative |
|-----------|---------|-------------|
| All items affect different user populations | Reach isn't comparable across items | Normalize by % of user base, not absolute count |
| Strategic/foundational work has no direct user reach | Platform investments score near zero | Add a "strategic value" multiplier or use a separate track for enabling work |
| Security/compliance requirements | Non-negotiable — RICE is irrelevant | MoSCoW: these are "Must Have" by definition |
| Exploratory / research work | Effort is unknowable | Score conservatively or time-box the research separately |
| Highly political environment | Managers game the inputs | Require data sources for all estimates; audit Reach and Impact claims |

---

## FAANG Interview Callouts

**Q: Product wants to build Feature A. Engineering wants to address tech debt. How do you use RICE to resolve it?**

Apply RICE to both — including tech debt. The challenge is that tech debt doesn't have direct "reach" in the user-facing sense. Translate it:

- Reach: how many engineers does the tech debt slow down per week? (e.g., 20 engineers)
- Impact: how much does it reduce their velocity? (e.g., 0.5 = medium friction)
- Confidence: how certain are you of the impact? (e.g., 80% — you can measure it)
- Effort: how long to fix it? (e.g., 4 person-weeks)

RICE Score = (20 × 0.5 × 0.8) / 4 = 2.0 (low, because reach is internal)

If Feature A scores 15,000 — it beats tech debt on RICE. But this is where you add context: tech debt compounds. A 2.0 this quarter becomes a 4.0 next quarter. Present the full picture, not just the number.

**Q: How do you prevent RICE from being gamed?**

Three controls:
1. **Require data sources** for Reach and Impact — no estimates without analytics links, user research docs, or support ticket counts
2. **Effort is estimated by the team doing the work**, not the requestor — eliminates underestimating effort to inflate scores
3. **Score in a shared forum** — if everyone can see the scores and their inputs, gaming is visible and challengeable
