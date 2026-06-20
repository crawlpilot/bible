# T-Shirt Sizing

## What It Is

T-shirt sizing assigns relative complexity categories (XS, S, M, L, XL, XXL) to work items. It is a **rough-order-of-magnitude** technique — not a commitment, not a schedule. It is designed for speed at the cost of precision.

**Primary use case**: roadmap planning, portfolio prioritization, and cross-team initiative scoping where getting to < 50% error in minutes is more valuable than getting to < 20% error over hours.

---

## The Scale

| Size | Rough Duration | Characteristics |
|------|---------------|-----------------|
| XS | Hours to 1 day | Fully understood, no dependencies, single engineer |
| S | 1–3 days | Straightforward, known approach, minimal coordination |
| M | 1–2 weeks | Some unknowns, one team, maybe one dependency |
| L | 2–6 weeks | Significant unknowns, multi-engineer, cross-team coordination likely |
| XL | 1–3 months | High complexity, multiple teams, architecture decisions needed |
| XXL | 3+ months | Transformational, org-wide, split into sub-initiatives before estimating |

**Key rule**: if a team can't agree on XS vs. L, the item is not understood well enough to estimate. That is the signal — do a spike first.

---

## How to Run a T-Shirt Sizing Session

### Setup (before the session)

1. Write a one-paragraph description for each item — what it does, who it affects, what done looks like.
2. Identify a **reference item**: a previously completed piece of work that everyone agrees is "M." All items are sized relative to this anchor.
3. Bring the people who will do the work, not just their managers.

### Session flow (30–60 minutes for 10–15 items)

```
For each item:
  1. Read the description aloud (60 seconds)
  2. Silent independent sizing (30 seconds) — everyone writes on a card/sticky
  3. Reveal simultaneously — avoid anchoring bias
  4. If consensus (within one size): record it, move on
  5. If divergence (e.g., one says S, another says XL):
       → ask the outliers to explain their reasoning
       → surface the assumption gap
       → re-vote once after discussion
       → if still split after two rounds: record the larger estimate or schedule a spike
```

### Tools

- Physical: index cards or sticky notes (fastest, least ceremony)
- Remote: PlanningPoker.com, Miro dot voting, Linear estimate fields, Jira story points field
- Async: Notion table with each team member dropping their estimate, then sync to resolve splits

---

## Sizing Reference Examples (Platform Engineering Context)

| Item | Size | Reasoning |
|------|------|-----------|
| Add a new field to an existing REST API | XS | Well-understood, backward compatible, tests exist |
| Migrate a service from HTTP to gRPC | M | Known approach but requires client changes |
| Implement distributed tracing across 5 services | L | New infra, coordination across teams, rollout risk |
| Extract a module from a monolith into a microservice | XL | Data migration, API contract changes, traffic cutover |
| Re-platform from VMs to Kubernetes | XXL | Multi-team, multiple phases, unknown blast radius |
| Add a feature flag to an existing feature | XS | Flag SDK already in place, one-line change |
| Build a feature flag system from scratch | L | Architecture decisions, SDK, control plane, ops |

---

## Mapping T-Shirt Sizes to a Roadmap

T-shirt sizes convert directly into roadmap confidence bands:

```
Q1 (weeks 1–13):
  - Include: XS + S + M items with high confidence
  - Limit: no more than 1 L item per team without a discovery spike completed
  - Exclude: XL and XXL — they belong in a separate initiative track

Q2:
  - L items planned in Q1 should now be broken down (post-discovery)
  - XL items: first phase only (discovery + scoping) in Q1, execution in Q2
```

### Capacity planning with t-shirt sizes

Assign points to sizes for rough capacity math:

```
XS = 1 pt
S  = 2 pts
M  = 4 pts
L  = 8 pts
XL = 16 pts

Team of 5 engineers, 2-week sprint:
  Velocity ≈ 20–24 pts (empirically measured over prior sprints)
  
Roadmap load for Q1 (6 sprints):
  Total capacity ≈ 120–144 pts
  Planned load should be ≤ 80% of capacity (reserve for unplanned + rework)
  Target planned load: ~96–115 pts
```

This is rough — the point is capacity reasonableness, not precise scheduling.

---

## When T-Shirt Sizing Breaks Down

| Situation | Problem | Fix |
|-----------|---------|-----|
| Team has never done this type of work | No reference frame | Time-box a 2-day spike first, then re-size |
| Items keep landing on L/XL/XXL | Not decomposed enough | Break down into sub-tasks before sizing |
| Strong anchor bias (senior eng speaks first) | Others conform to their estimate | Silent simultaneous reveal, always |
| Sizing used as a commitment | Engineers pad estimates defensively | Re-establish: "this is a roadmap input, not a contract" |
| Cross-team items sized by one team | Missing dependencies | Include reps from all affected teams |

---

## T-Shirt Sizing vs. Story Points

| | T-Shirt Sizing | Story Points |
|--|----------------|--------------|
| Granularity | 6 sizes | Fibonacci: 1,2,3,5,8,13,21 |
| Use case | Roadmap / portfolio | Sprint planning |
| Time to estimate | Seconds per item | 2–5 minutes per story |
| Accuracy | ±50–100% | ±30–50% |
| Good for | "Should we do this quarter?" | "Can we fit this in the sprint?" |
| Velocity tracking | Not used | Core usage |

Use t-shirt sizes for anything more than 4 weeks out. Switch to story points when work enters the sprint planning horizon.

---

## FAANG Interview Callouts

**Q: A PM asks you to estimate a quarter-long initiative in a single meeting. How do you approach it?**

Run a t-shirt sizing session for the major workstreams, not the whole initiative as one item:
1. Break the initiative into 8–15 distinct deliverables first
2. Size each independently using t-shirts + reference anchors
3. Sum the sizes, compare against team capacity
4. Flag any item larger than L — that's a scope risk; drive a spike before committing
5. Present back as a range: "Based on current understanding, 10–16 weeks. The L and XL items carry the uncertainty — here's what we'd need to learn to narrow it."

Never give a single-point estimate for a novel, multi-team initiative. It will be wrong and you will own that commitment.

**Q: Two senior engineers keep disagreeing on estimate sizes. How do you resolve it?**

Disagreement on size almost always means disagreement on scope or assumptions — not subjective difficulty. Surface this explicitly:
- "You said S. You said XL. What are you each assuming about the scope?"
- One usually assumes the happy path; the other is including migration, testing, and rollout.

Once you surface the assumption gap, the estimate resolves itself. The outcome is often: "We need to do X before we can estimate this accurately" — which is more valuable than a false consensus number.
