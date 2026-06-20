# Complexity Mapping & Cone of Uncertainty

## The Cone of Uncertainty

The Cone of Uncertainty is a visualization of how estimation error decreases as a project progresses and unknowns are resolved. It was formalized by Barry Boehm in *Software Engineering Economics* and is the empirical basis for why early estimates should always be given as ranges.

```
                          Early estimate error: ±400%
          ┌───────────────────────────────────────────────────────┐
          │                                                       │
 4×       ┤ ═══════════════════════════════════════════════════   │
          │ ╲                                                     │
          │  ╲                                                    │
 2×       ┤   ╲═══════════════════════════════════════           │
          │    ╲ ╲                                                │
 1× (plan)┤     ╲  ╲═══════════════════════════════              │
          │      ╲   ╲ ╲                                         │
 0.5×     ┤       ╲    ╲  ╲═══════════════════════               │
          │        ╲    ╲    ╲                                    │
 0.25×    ┤         ╲════╲════╲═════════════                     │
          │              ╲    ╲    ╲═════                        │
          └──────────────────────────────────────────────────────┘
          Concept     Requirements   Architecture   Implementation   Done
          (Phase 0)    (Phase 1)      (Phase 2)       (Phase 3)
```

**Reading the cone**:
- At concept phase: estimate could be 4× over or 0.25× under (16× spread)
- After architecture is defined: ±2× (4× spread)
- After implementation begins: ±1.25×
- Near completion: ±1.1× (mostly rework estimation)

**Principal engineer implication**: a date given at concept phase is not an estimate — it is a hope. The appropriate response to "when will this be done?" in Phase 0 is a range, not a point, along with a statement of what needs to be true to narrow that range.

---

## Complexity Mapping

Complexity mapping is a technique to visualize and communicate where in a project the hardest problems live — before they become surprises mid-sprint.

### The Cynefin Framework (applied to estimation)

Dave Snowden's Cynefin framework categorizes problems by their predictability:

```
              COMPLICATED                    COMPLEX
         ┌──────────────────────┬─────────────────────────┐
         │  Expert analysis     │  Probe → Sense → Respond│
         │  Good practices      │  Emergent practices      │
         │  Cause & effect      │  Unknown unknowns        │
         │  knowable in advance │                          │
         ├──────────────────────┼─────────────────────────┤
         │  Best practices      │  Act → Sense → Respond  │
         │  Cause & effect      │  Novel situation         │
         │  obvious             │  No established practice │
              SIMPLE/CLEAR              CHAOTIC
```

**Mapping your work items**:

| Domain | Estimation approach | Examples |
|--------|---------------------|---------|
| **Simple/Clear** | Historical analogy — look at similar past work | Add a CRUD endpoint, add a config flag |
| **Complicated** | Expert estimation + PERT | Implement a caching layer, write a batch job |
| **Complex** | Time-box a spike; do not estimate output | Design a new distributed system, ML model integration |
| **Chaotic** | Stabilize first, then estimate | Production incident, complete rewrite under pressure |

**Estimation error by domain**:
- Simple: ±20% (reliable)
- Complicated: ±50% (useful with PERT)
- Complex: ±200–400% (spike first)
- Chaotic: unknowable (do not estimate)

---

## Complexity Map for a Software Initiative

A complexity map plots tasks on two axes: **technical complexity** vs. **dependency complexity** (how many teams, systems, or external parties are involved).

```
High Technical    │  Risky but contained     │  High-risk, hard to plan
Complexity        │  (prototype → build)      │  (spike required, then phase)
                  │  e.g. ML inference        │  e.g. Cross-org data migration
                  │  engine rewrite           │  with external APIs
──────────────────┼───────────────────────────┼───────────────────────────────
                  │  Low risk, routine        │  Low tech risk, high coord cost
Low Technical     │  (estimate normally)      │  (plan around dependencies)
Complexity        │  e.g. Add API endpoint    │  e.g. Config change needing
                  │  to existing service      │  approval across 6 teams
                  └───────────────────────────┴───────────────────────────────
                       Low Dependency              High Dependency
                       Complexity                  Complexity
```

**How to use it**:
1. Plot every major work item on the map
2. Items in the top-right quadrant: require a spike, phase gate, or architectural decision before committing to a timeline
3. Items in the bottom-left: estimate normally with story points or PERT
4. Items in the top-left: prototype-first, then re-estimate after proof of concept
5. Items in the bottom-right: create a dependency resolution plan before estimating

---

## Risk-Adjusted Estimation

Standard estimation techniques assume a single outcome path. Risk adjustment explicitly accounts for events that could derail the estimate.

### Risk register for an initiative

| Risk | Probability | Impact (weeks) | Expected Impact (P × I) | Mitigation |
|------|-------------|----------------|-------------------------|------------|
| Third-party API breaks contract | 20% | +4 weeks | +0.8 wks | Contract testing + fallback design |
| Key engineer leaves mid-project | 15% | +3 weeks | +0.45 wks | Knowledge transfer, pair programming |
| Infrastructure provisioning delayed | 30% | +2 weeks | +0.6 wks | Pre-provision in sprint -1 |
| Scope creep from stakeholder | 40% | +2 weeks | +0.8 wks | Weekly scope review, change log |
| Performance requirements tightened | 25% | +3 weeks | +0.75 wks | Define perf SLOs in discovery |
| **Total risk exposure** | | | **+3.4 wks** | |

**Risk-adjusted estimate** = PERT expected duration + risk exposure
```
PERT expected: 12.4 weeks
Risk exposure: +3.4 weeks
Risk-adjusted: 15.8 weeks

Communicate: "We estimate 12–13 weeks under normal conditions.
              Accounting for identified risks, plan for 15–16 weeks."
```

### Monte Carlo simulation (advanced)

For large, multi-phase initiatives, Monte Carlo simulation runs thousands of random scenarios by sampling from each task's probability distribution. The output is a probability distribution of project completion dates.

```python
import random
import numpy as np

def pert_sample(optimistic, most_likely, pessimistic, n=10000):
    """Sample from a PERT/beta distribution."""
    alpha = 1 + 4 * (most_likely - optimistic) / (pessimistic - optimistic)
    beta  = 1 + 4 * (pessimistic - most_likely) / (pessimistic - optimistic)
    samples = np.random.beta(alpha, beta, n)
    return optimistic + samples * (pessimistic - optimistic)

# Tasks: (O, M, P) in weeks
tasks = [
    (1, 2, 5),    # WebSocket server
    (0.5, 1.5, 4), # Client SDK
    (1, 2.5, 7),  # Message fanout
    (2, 4, 10),   # Push integration
    (0.5, 1, 3),  # Load testing
]

simulations = sum(pert_sample(o, m, p) for o, m, p in tasks)

print(f"P50 (median):       {np.percentile(simulations, 50):.1f} weeks")
print(f"P70 (70% prob):     {np.percentile(simulations, 70):.1f} weeks")
print(f"P90 (90% prob):     {np.percentile(simulations, 90):.1f} weeks")
print(f"P95 (95% prob):     {np.percentile(simulations, 95):.1f} weeks")

# Output:
# P50 (median):    12.2 weeks
# P70 (70% prob):  13.8 weeks
# P90 (90% prob):  16.4 weeks
# P95 (95% prob):  18.1 weeks
```

This is actionable: "If you need 80% confidence, plan for 14 weeks. If you need 95% confidence, plan for 18 weeks."

---

## The Estimation Accuracy Lifecycle

Track estimation accuracy over time to calibrate your team:

```
For each completed project/epic:
  Record:
    - Initial estimate (at start of planning)
    - Mid-point estimate (at 50% completion)
    - Final actual duration

  Calculate:
    - Initial accuracy: actual / initial estimate
    - Mid-point accuracy: actual / mid-point estimate

Target calibration:
  Initial estimates: within 2× actual (i.e., actual / initial = 0.5–2.0)
  Mid-point estimates: within 1.25× actual
```

If your team's initial estimates are consistently 3× off in one direction, you have a systematic bias. Common causes:
- **Consistent underestimate**: ignoring integration, testing, and review time; not accounting for interrupts
- **Consistent overestimate**: padding for political safety; not understanding the domain well enough

Track this quarterly. Share results with the team. Calibration improves estimation quality faster than any technique.

---

## Complexity Signals That Should Trigger a Spike

| Signal | Example | Action |
|--------|---------|--------|
| "We've never done this before" | First time integrating a specific third-party API | 1-week spike |
| P/O ratio > 6 | O=1 week, P=8 weeks for a single task | Spike to resolve the ambiguity |
| Disagreement > 3× in planning poker | One person says 3 points, another says 13 | Spike or refinement session |
| Architecture decision unmade | Async vs. sync? Which database? | Architecture decision record (ADR) required first |
| External dependency unknown | "We think the payment provider supports this" | Verify before estimating |
| Regulatory/compliance unknown | "GDPR implications unclear" | Legal/compliance review before estimating |

---

## FAANG Interview Callouts

**Q: A project has a fixed date. Your complexity map shows three tasks in the high-complexity, high-dependency quadrant. How do you proceed?**

Address the quadrant-4 tasks first — before any sprint planning:

1. **Spike** each one to reduce technical uncertainty (time-box: 1 week per task)
2. **Dependency resolution plan**: identify the blocking teams, schedule alignment sessions, escalate if they can't commit within 2 weeks
3. **Re-estimate** after spikes with new information

If the deadline is still not achievable after de-risking: present data to stakeholders. "These three tasks carry 80% of the schedule risk. With them on the critical path, 90% confidence is Week 18, not Week 12. Here are the scope options."

**Q: How do you prevent scope creep from blowing up a well-estimated project?**

Two mechanisms:
1. **Scope baseline at kickoff**: written list of what is in and explicitly what is out. Signed off by product and engineering leads. Not a wish list — a boundary.
2. **Change control process**: any new requirement goes through a formal add/defer decision. The question is always "what comes out?" if something new comes in. This is not bureaucracy — it is respecting the integrity of the estimate.

Track scope change volume per sprint. If > 20% of sprint capacity is going to unplanned scope, the project is not being managed — it is reacting. Escalate.
