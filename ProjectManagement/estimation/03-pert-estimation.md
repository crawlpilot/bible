# PERT Estimation — Three-Point Estimation & Schedule Risk

## What PERT Is

PERT (Program Evaluation and Review Technique) was developed by the US Navy in the 1950s for the Polaris missile program — a project with massive uncertainty and no historical precedent. It works by collecting three estimates per task and deriving a probability-weighted expected duration with a standard deviation.

**Why it matters at principal level**: PERT converts vague uncertainty into quantified schedule risk. Instead of saying "it might take 4–12 weeks," you can say "expected duration is 6.3 weeks with a standard deviation of 1.3 weeks — there's a 90% probability we finish within 9 weeks." That is a useful statement for a stakeholder managing a product launch date.

---

## The Three-Point Model

For each task, collect:

| Estimate | Symbol | Definition |
|----------|--------|------------|
| **Optimistic** | O | Best-case: everything goes perfectly, no blockers |
| **Most Likely** | M | Realistic: normal amount of friction and minor surprises |
| **Pessimistic** | P | Worst-case: major blocker, wrong initial approach, key person unavailable |

**Rules for eliciting honest estimates**:
- Optimistic = "1 in 20 chance of finishing at or before this time"
- Pessimistic = "1 in 20 chance of taking longer than this"
- Most likely = the mode (peak of the distribution), not the average

---

## PERT Formulas

### Expected Duration (E)

```
E = (O + 4M + P) / 6
```

The most likely estimate is weighted 4× because the distribution is assumed to be approximately beta-shaped (not symmetric). Bad surprises are more common than windfall good luck — hence M is closer to the optimistic end in practice.

### Standard Deviation (σ)

```
σ = (P - O) / 6
```

Standard deviation captures the spread of uncertainty. A task with O=2, M=4, P=6 has σ=0.67 (tight). A task with O=1, M=4, P=15 has σ=2.33 (very uncertain).

### Variance (σ²)

```
σ² = ((P - O) / 6)²
```

Variance is additive across independent tasks — this is the key property that enables project-level risk aggregation.

---

## Worked Example: Feature Development Estimate

**Initiative**: Implement real-time notifications system (WebSocket + push infrastructure)

| Task | O (weeks) | M (weeks) | P (weeks) | E = (O+4M+P)/6 | σ = (P-O)/6 | σ² |
|------|-----------|-----------|-----------|----------------|-------------|-----|
| WebSocket server implementation | 1 | 2 | 5 | 2.33 | 0.67 | 0.44 |
| Client SDK + browser integration | 0.5 | 1.5 | 4 | 1.75 | 0.58 | 0.34 |
| Message fanout service | 1 | 2.5 | 7 | 2.83 | 1.00 | 1.00 |
| Push notification integration (iOS/Android) | 2 | 4 | 10 | 4.33 | 1.33 | 1.78 |
| Load testing + perf tuning | 0.5 | 1 | 3 | 1.17 | 0.42 | 0.17 |
| **Total** | **5** | **11** | **29** | **12.41** | | **3.73** |

**Project-level standard deviation** = √(sum of variances) = √3.73 = **1.93 weeks**

### Interpreting the result

```
Expected duration: 12.4 weeks
Standard deviation: 1.93 weeks

Confidence intervals (assuming normal distribution):
  68% confidence:  12.4 ± 1.93  →  10.5 – 14.3 weeks
  90% confidence:  12.4 + 1.65×1.93  →  completes by 15.6 weeks
  95% confidence:  12.4 + 1.96×1.93  →  completes by 16.2 weeks
```

**Stakeholder communication**:
> "Based on our current understanding, this initiative is expected to take 12–13 weeks. There is a 90% probability we complete it within 16 weeks. The push notification integration is the highest-risk task — if we de-scope mobile push for the initial launch, expected duration drops to 8 weeks with much lower variance."

This is a principal engineer conversation. You are giving the stakeholder a decision: scope vs. confidence.

---

## Critical Path Method (CPM) with PERT

PERT becomes more powerful when combined with the Critical Path Method on dependent tasks.

### Example: dependency graph

```
       ┌─────────────────────────────────────┐
       │                                     │
[A: WebSocket server]─►[C: Message fanout]─►[E: Load test]
                                             ▲
[B: Client SDK]─────────────────────────────┘
                    
[D: Push integration] ──────────────────────► (independent, parallel)
```

**Critical path**: the longest path from start to finish. Only tasks on the critical path determine the project end date.

```
Path 1 (A → C → E): 2.33 + 2.83 + 1.17 = 6.33 weeks
Path 2 (B → E):     1.75 + 1.17 = 2.92 weeks
Path 3 (D):         4.33 weeks (parallel to main path)

Critical path = Path 1 (6.33 weeks)
Total with D in parallel = max(6.33, 4.33) = 6.33 weeks

vs. naive sum (all sequential): 12.41 weeks
→ Parallelism saves 6 weeks on this initiative
```

**Principal insight**: the difference between sequential and parallel execution is often the biggest lever on project duration — more impactful than estimation accuracy. Identifying what can be parallelized is a principal engineer contribution.

---

## Float / Slack

Float (or slack) is how much a task can be delayed without delaying the project.

```
Float = Late Start - Early Start
     or
Float = Late Finish - Early Finish

Tasks on the critical path: Float = 0 (any delay = project delay)
Tasks off critical path: Float > 0 (buffer available)
```

**Using float in project management**:
- Float reveals which tasks have scheduling flexibility (can be moved, parallelized later, or assigned lower-priority resources)
- Tasks with float = 0 get your first attention in risk management
- If a task's float goes negative (it's already delayed), the critical path has shifted — recalculate

---

## Three-Point Estimation in Practice

### Where estimates come from

Estimates should come from the engineers doing the work. Never accept a project manager's estimate for technical work without engineer review — they lack the context to estimate effectively.

**Good elicitation technique**:
```
1. Ask "what would make this take much longer than expected?" 
   → surfaces P inputs and hidden risks

2. Ask "what would have to go perfectly for this to be done in half the time?"
   → surfaces O inputs and what assumptions optimism requires

3. Ask "what's the most common outcome for work like this?"
   → surfaces M inputs based on experience
```

### Decomposition before estimation

PERT accuracy degrades rapidly for tasks > 2 weeks. Decompose before estimating:

```
Bad:  "Implement payment service" → O=4wk, M=10wk, P=24wk → σ=3.3wk (useless)

Good: Break into 8 tasks, each ≤ 2 weeks
  → σ per task = 0.3–0.7wk
  → Project σ = √(sum of variances) = √2.8 ≈ 1.7wk (much more useful)
```

### When estimates are unreliable (high P/O ratio)

```
P/O ratio as uncertainty signal:
  P/O < 3:   Low uncertainty — team has done this before
  P/O = 3–6: Medium uncertainty — some unknowns, design decisions needed
  P/O > 6:   High uncertainty — time-box a spike before estimating
```

A task with O=1 week and P=12 weeks has P/O=12. That is not an estimate — that is a spike disguised as an estimate. Run the discovery work, reduce the ratio, then re-estimate.

---

## PERT vs. Other Methods

| | PERT | Story Points | T-Shirt Sizing |
|--|------|--------------|----------------|
| Output | Expected duration + confidence interval | Relative complexity units | Rough size bucket |
| Best for | Project scheduling, deadline risk | Sprint planning, velocity tracking | Roadmap prioritization |
| Time to estimate | 10–30 min per task | 2–5 min per story | 30 sec per item |
| Handles uncertainty | Explicitly (σ) | Implicitly (range between values) | Poorly (bucket hides spread) |
| Cross-team comparison | Yes (calendar time is objective) | No (calibration differs by team) | No |
| Executive communication | Excellent (confidence intervals) | Poor (points are meaningless to execs) | Acceptable (sizes + ranges) |

---

## PERT Output: Stakeholder Communication Templates

### Template 1: Single initiative

> **Initiative**: Real-Time Notifications  
> **Expected duration**: 12–13 weeks  
> **90% confidence interval**: completes within 16 weeks  
> **Key risk drivers**: push notification integration (highest variance task)  
> **Scope levers**: de-scoping mobile push reduces duration to ~8 weeks at 90% confidence  

### Template 2: Multi-initiative roadmap

| Initiative | Expected | 80% Confidence | 95% Confidence | Key Risk |
|------------|----------|----------------|----------------|----------|
| Notifications | 12.4 wks | 14.5 wks | 16.2 wks | Push integration |
| Search v2 | 8.2 wks | 10.0 wks | 11.1 wks | ML model accuracy |
| Auth migration | 6.8 wks | 8.1 wks | 8.9 wks | External IdP API stability |

"Presenting three scenarios per initiative — expected, high-confidence, and worst-case — is clearer than a single date and more honest than a range that nobody knows how to interpret."

---

## FAANG Interview Callouts

**Q: A product launch is scheduled in 10 weeks. Your PERT analysis shows 90% confidence at 14 weeks. How do you handle this?**

This is not an engineering problem — it is a product/business decision. Present options:
1. **Scope reduction**: which tasks can be cut or phased to fit within 10 weeks? What is the 70% confidence estimate with reduced scope?
2. **Parallel staffing**: can adding engineers to the critical path compress it? (Careful — Brooks' Law applies to coordination-heavy tasks)
3. **Risk acceptance**: launch at 10 weeks with reduced scope, deliver remaining features post-launch
4. **Date move**: present the cost of launching incomplete vs. launching late — stakeholder decides

Never accept a deadline-driven estimate that compresses your pessimistic scenario. That's not planning — it's wishful thinking. The PERT analysis is your credibility tool: you have data.

**Q: How do you estimate a project when you have no historical precedent?**

Spike first. A 1–2 week time-boxed discovery spike with a specific question ("can we integrate with this third-party API within these constraints?") converts P from 26 weeks to 6 weeks. The estimate is only as good as the assumptions underlying it — remove the largest assumptions before committing to a schedule.

If you must estimate without a spike: explicitly list your assumptions, weight P heavily (assume high uncertainty), and build in a formal checkpoint at 25% completion to re-estimate with real data. Communicate this clearly: "This is a rough estimate assuming X. We'll re-forecast at week 3 once we have more signal."
