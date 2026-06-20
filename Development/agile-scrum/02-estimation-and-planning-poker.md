# Estimation and Planning Poker

Estimation is a communication tool for uncertainty. It is not a promise, a productivity score, or a substitute for good decomposition. Planning poker works when the team is forcing hidden assumptions into the open.

## What Story Points Measure

Story points are a relative measure of effort, uncertainty, and complexity compared to other work the team has already discussed. They are not hours.

| Dimension | What to ask |
|-----------|-------------|
| Complexity | How many moving parts does this story touch? |
| Uncertainty | What do we not know yet? |
| Risk | What could break in implementation or rollout? |
| Effort | How much engineering time is likely required? |

## Planning Poker Rules That Matter

1. Everyone estimates independently.
2. Reveal estimates at the same time.
3. Ask the highest and lowest estimates to explain their reasoning.
4. Re-estimate only after assumptions are clarified.
5. Stop when the team has enough convergence to plan, not when everyone agrees perfectly.

## Story Slicing Heuristics

- Each story should produce one observable outcome.
- A story should ideally fit within a few days of work.
- Separate backend, frontend, rollout, and observability when they are independently valuable.
- Slice by risk reduction when the uncertainty is high.
- If a story needs a cross-team dependency, split out the dependency work explicitly.

## Estimation Anti-Patterns

- Using story points to compare individual developers
- Reusing the same number just to avoid debate
- Estimating tasks before the story is understood
- Converting points to hours as a formal policy
- Making estimates tighter over time without improving input quality

## Good Facilitation Signals

- High spread in estimates usually means hidden complexity or different assumptions
- A story that cannot be estimated is usually too large or too vague
- If the discussion takes too long, the story probably needs slicing
- If the team is constantly surprised, the backlog is not refined enough

## Principal Engineer View

At scale, estimation is less about precision and more about risk disclosure. A strong engineer says, "This is probably a 5, but there are two unknowns we need to spike before we can trust that number."

## Interview Callout

Be ready to explain why velocity is useful for forecasting within a stable team, but dangerous as a KPI. The moment points become a performance target, they stop being a planning tool.

---

## The Fibonacci Scale — Why These Numbers

Planning poker uses the Fibonacci sequence (1, 2, 3, 5, 8, 13, 21) or a modified version (1, 2, 3, 5, 8, 13, 20, 40, 100). The non-linear spacing is intentional:

- Small differences in small stories matter: 1 vs. 2 is a real distinction
- Large stories have proportionally large uncertainty: the difference between 13 and 21 is already within the margin of error, which is the signal to split
- The gaps force honest conversation: if someone estimates 6, they must choose 5 or 8 — which forces them to decide whether the uncertainty pushes it up or down

**Extended scales for large work:**
| Value | Meaning |
|-------|---------|
| 1 | Trivial change; well-understood, minimal risk |
| 2 | Small; understood, low uncertainty |
| 3 | Moderate; mostly clear, minor unknowns |
| 5 | Medium; clear intent, some uncertainty |
| 8 | Large; significant unknowns or multi-day work |
| 13 | Very large; consider splitting |
| 21+ | Too large; must be split before committing |
| ? | Cannot estimate — need a spike |

---

## T-Shirt Sizing

Used for early-stage backlog or roadmap-level planning when precise estimates aren't needed.

| Size | Rough effort | Story points equivalent |
|------|-------------|------------------------|
| XS | Hours | 1 |
| S | < 1 day | 2–3 |
| M | 2–3 days | 5 |
| L | 4–5 days | 8 |
| XL | > 1 sprint | 13+ — must split |

T-shirt sizing is appropriate for PI Planning, quarterly roadmaps, and pre-refinement backlog triage. It is too coarse for sprint-level commitment.

---

## Reference Story Anchoring

The single most effective technique to improve estimation consistency is anchoring against a known reference story.

**How to establish anchor stories:**
1. Pick 3–4 completed stories from recent sprints that represent different sizes
2. Re-estimate them as a team and agree: "Story A is a 2, Story B is a 5, Story C is an 8"
3. Pin these as the team's reference baseline
4. In future planning, compare new stories to the reference: "Is this bigger or smaller than the 5?"

This converts estimation from an absolute judgment ("how many hours?") into a relative comparison ("bigger than Story B?"), which is more accurate and faster.

---

## Three-Point Estimation (PERT-style)

For high-uncertainty items or spike outcomes, use three-point estimation instead of a single number:

- **Optimistic (O):** best case — everything goes right
- **Most Likely (M):** expected case given typical conditions
- **Pessimistic (P):** worst case — significant unknowns materialise

**PERT weighted average:** $E = \frac{O + 4M + P}{6}$

**Standard deviation:** $\sigma = \frac{P - O}{6}$

```
Example: integrating a new payment provider
  Optimistic:   3 days (API is clean, sandbox works, no surprises)
  Most likely:  6 days (some quirks, minor debugging)
  Pessimistic: 15 days (undocumented edge cases, PCI compliance gaps)

  PERT estimate = (3 + 4×6 + 15) / 6 = 42/6 = 7 days
  Std dev = (15 - 3) / 6 = 2 days

  Plan for ~7 days; flag that it could run to 9 if pessimistic conditions emerge.
```

This is particularly useful when presenting forecasts to stakeholders — the range is more honest than a single number.

---

## Spike Stories

A spike is a time-boxed investigation to reduce estimation uncertainty. It is not a feature story.

**When to use a spike:**
- The team cannot estimate a story because of technical unknowns
- There are multiple implementation approaches with unclear trade-offs
- An external dependency (third-party API, vendor capability) is unverified

**Spike format:**
```
Title: [SPIKE] Evaluate Elasticsearch vs. OpenSearch for full-text search

Time box: 2 days (1 engineer)

Goal: Produce a recommendation with evidence on:
  - Query latency at our expected data volume (50M documents)
  - Managed offering cost comparison (AWS OpenSearch vs. Elastic Cloud)
  - Migration complexity from current Postgres full-text search

Output: A 1-page technical memo with a recommendation and open questions
```

**Rules for spikes:**
- Always time-boxed — never open-ended
- The output is knowledge or a decision, not production code
- The following story (the feature) gets estimated after the spike, not before

---

## Relative Estimation in Practice — Full Session Template

```
Planning poker session agenda (60 min for 10–15 stories)

Pre-requisites:
  □ All stories have been refined and meet DoR
  □ Reference anchor stories are visible to the team

Opening (5 min):
  □ Confirm anchor stories and their point values
  □ Remind the team: points = complexity + uncertainty + risk, not hours

Per story (3–5 min each):
  1. PO reads the story title and acceptance criteria
  2. Team members ask clarifying questions (1–2 max)
  3. Everyone votes simultaneously using cards or a tool
  4. If spread is ≤ 1 step (e.g., 3 and 5): take the higher, move on
  5. If spread is > 1 step: highest and lowest explain their reasoning
  6. Re-vote once; if still split, accept the higher estimate or split the story

Closing (5 min):
  □ Confirm estimates are recorded
  □ Flag any stories that require a spike before they are estimable
  □ Note open assumptions that could change the estimate
```

---

## #NoEstimates — When to Drop Points

Some high-performing teams move away from story points entirely and use **throughput** (stories completed per sprint) instead. Arguments for and against:

| #NoEstimates | Traditional story points |
|-------------|------------------------|
| Eliminates gaming | Provides size-adjusted forecasting |
| Forces consistent story slicing | Works even with mixed story sizes |
| Simpler to understand | Familiar to most teams and stakeholders |
| Reduces meeting time | Surfaces hidden disagreements on complexity |
| Requires disciplined story sizing | Requires disciplined calibration |

**When #NoEstimates works:** teams with very consistent story sizes, strong discipline on splitting, and a single team context.

**When story points still win:** forecasting across teams, teams with highly variable story sizes, or when stakeholder communication requires size context.

---

## Dealing with Estimation Disputes

| Dispute type | Resolution strategy |
|-------------|-------------------|
| Technical disagreement on approach | Timebox the discussion to 3 min; if unresolved, spike it |
| One engineer knows more than others | Ask them to share — that's the conversation worth having |
| PO and engineering disagree on scope | The scope disagreement is the real issue; clarify AC first |
| Chronically wide spread on every story | Stories are not refined enough; improve the DoR |
| Same engineer always estimates low | Coach separately; do not call out in planning |

---

## FAANG Interview Framing

**"How do you handle a team that treats velocity as a target?"**

> I redirect the conversation to outcome metrics instead of output metrics. If velocity is being tracked as a KPI, it will be gamed: stories get inflated, scope is cut at the end of the sprint to hit the number, and the metric stops measuring anything real. I reframe: the question is not "did we hit N points?" but "did we move the product metrics we care about?" I replace velocity reporting with cycle time, deployment frequency, and customer outcomes where I can. Velocity stays as an internal planning tool only.

**"What is the right response when a story cannot be estimated?"**

> A story that cannot be estimated tells you one of three things: the scope is ambiguous, the team lacks information, or the story is too large. In all three cases, the right action is a spike or a refinement session — not a planning poker re-vote. I treat "cannot estimate" as a blocker for the story entering the sprint, not as a reason to force a number.
