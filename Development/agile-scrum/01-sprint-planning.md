# Sprint Planning

Sprint planning is where the team converts a prioritized backlog into a realistic delivery forecast. At principal level, the goal is not to fill every hour of the sprint. The goal is to create a shared commitment that is constrained by capacity, risk, and dependencies.

## Outcomes of a Good Planning Session

- A sprint goal that can be stated in one sentence
- A backlog slice small enough to finish within the sprint window
- Explicitly identified risks, dependencies, and assumptions
- A visible trade-off between planned scope and reserved capacity for unplanned work
- Shared understanding of what is out of scope

## Inputs Required Before Planning

| Input | Why it matters |
|-------|----------------|
| Ranked backlog | Planning without priority is just discussion |
| Team capacity | Vacation, on-call, interviews, and support work reduce availability |
| Dependency map | Cross-team blockers should be surfaced before commitment |
| Definition of Done | Prevents hidden work from appearing late in the sprint |
| Recent carryover and interrupts | Historical reality is a better guide than idealized availability |

## Planning Flow

1. Review the sprint goal or propose one if none exists.
2. Confirm available capacity for each engineer.
3. Walk the highest-priority stories and confirm they are small enough.
4. Identify hidden work: testing, documentation, migrations, rollout, and observability.
5. Reserve capacity for support, review load, and unexpected work.
6. Lock the sprint only after the team understands the trade-offs.

## Capacity Model

For a 5-engineer team in a 2-week sprint, nominal capacity is often around 100 engineering-days only on paper. Realistic capacity is lower because of meetings, support, and context switching.

| Factor | Example impact |
|--------|----------------|
| 10 working days per engineer | 50 person-days nominal for 5 engineers |
| 20% meeting and coordination overhead | -10 person-days |
| 15% support/on-call/review load | -7.5 person-days |
| 10% risk buffer | -5 person-days |
| Realistic planning capacity | ~27.5 person-days |

This is why planning by intuition alone usually overcommits the sprint.

## Common Failure Modes

- Treating every story as equally certain
- Ignoring rollout and verification work
- Planning to 100% capacity with no interrupt buffer
- Accepting cross-team dependencies without an owner
- Turning the session into a negotiation over hours instead of scope

## Principal-Level Guidance

- Make the sprint goal the primary artifact, not the task list.
- Push back on stories that are too large to inspect meaningfully during the sprint.
- Reserve capacity explicitly for production support and review churn.
- If the team repeatedly misses commitments, reduce scope before increasing ceremony.

## Interview Callout

In a senior interview, explain how you would balance team autonomy with predictability. The strong answer is not "plan harder"; it is "improve slicing, protect capacity, and make risk visible early."

---

## INVEST Criteria — Story Readiness Standard

Every story entering a sprint should pass the INVEST checklist. This is the principal engineer's quality bar for backlog items.

| Letter | Criterion | What to check |
|--------|-----------|--------------|
| **I** | Independent | Can it be built and released without waiting on another story in this sprint? |
| **N** | Negotiable | Is the scope fixed before it's discussed, or is there room to trade off? |
| **V** | Valuable | Does it deliver observable value to a user, customer, or the system? |
| **E** | Estimable | Does the team have enough information to estimate it with confidence? |
| **S** | Small | Can it be completed within a sprint? (ideally 1–3 days of engineering work) |
| **T** | Testable | Can acceptance be verified against a clear, agreed condition? |

If a story fails two or more INVEST criteria, it should not enter the sprint. Send it back to refinement.

---

## Definition of Ready

Before a story can be included in sprint planning, it must meet the **Definition of Ready** (DoR). This prevents the team from planning work that is underspecified.

```
Definition of Ready — standard template

A story is READY for sprint planning when:
  □ It has a clear problem statement or user narrative
  □ Acceptance criteria are written and agreed upon by PO and team
  □ All upstream dependencies are resolved or have a named owner
  □ Design/UX artefacts are attached if the story has UI impact
  □ The story passes INVEST criteria
  □ It has been estimated in a refinement session
  □ Any spike or research work required has already been completed
  □ Data migration, rollback plan, and flag strategy noted (if applicable)
```

**Why DoR matters:** stories that skip this gate cause mid-sprint blockages — the engineering equivalent of starting a build without the spec. At Google, this is sometimes called "engineering readiness"; at Amazon it maps to "working backwards" — you write the press release before writing the code.

---

## Definition of Done

Done means the increment is releasable. Not "code merged." Not "in QA." Releasable.

```
Definition of Done — standard template

A story is DONE when:
  □ Code is merged to the main branch
  □ All automated tests pass (unit, integration, e2e where applicable)
  □ Code reviewed and approved (CODEOWNERS satisfied)
  □ Feature flag configured and tested (if applicable)
  □ Observability: metrics, logs, and alerts reviewed and deployed
  □ No new P0/P1 bugs introduced
  □ Documentation updated (API docs, runbooks, ADRs)
  □ Acceptance criteria signed off by Product Owner
  □ Deployed to staging / pre-prod and smoke-tested
  □ Performance benchmarked if latency-sensitive path changed
```

**Team-level DoD:** each team should own their DoD and evolve it in retros. The above is a starting template. Items like "deployed to production" may be appropriate for teams with continuous delivery.

---

## Sprint Goal Template

A sprint goal should be:
- Stated in business/user terms, not task terms
- Achievable within the sprint
- Flexible enough that the team can adjust scope while still meeting it

```
Bad sprint goal:
  "Complete JIRA tickets ENG-101, ENG-102, ENG-103, and ENG-104"

Good sprint goal:
  "Merchants can onboard with a bank account so we can pilot direct deposit payouts."

  Supporting stories:
  - ENG-101: API endpoint for bank account validation
  - ENG-102: PCI-compliant storage for routing/account numbers
  - ENG-103: Merchant dashboard UI for adding bank details
  - ENG-104: Payout scheduling job with bank account support
```

The goal survives; individual stories are negotiable within it.

---

## Two-Part Planning Ceremony

Scrum formally has two parts to planning. Most teams run them consecutively.

### Part 1 — What (30–60 min)
- Product Owner presents the sprint goal and top backlog items
- Team asks clarifying questions about scope and acceptance
- Team confirms capacity and agrees on the goal
- Outcome: sprint goal and list of stories selected

### Part 2 — How (30–60 min)
- Engineers break stories into tasks (1–4 hour chunks)
- Hidden work surfaces: API schema design, DB migration, rollout plan, tests
- Risks and dependencies are named
- Outcome: task board populated, team confident in the plan

**Timebox:** for a 2-week sprint, planning should not exceed 2 hours total. If it takes longer, stories are not refined enough.

---

## Working Agreements for Sprint Planning

Document and display these. They prevent the same debates every sprint.

```
Sprint Planning Working Agreements (example)

  1. No story enters planning without passing DoR
  2. If a story cannot be estimated, it goes back to refinement — not into the sprint
  3. We reserve 20% capacity for unplanned work (support, incidents, review)
  4. Cross-team dependencies must have a named external owner before we commit
  5. The sprint goal takes priority over individual story completion
  6. We commit as a team — "engineering said it would take X" is not acceptable
  7. If scope must change mid-sprint, the PO and EM make the trade-off visible
```

---

## Backlog Refinement (Grooming) — Best Practices

Refinement is not a sprint ceremony per se, but it is what makes planning work.

**When:** mid-sprint, 1–2 sessions per sprint, 60–90 min max  
**Who:** Product Owner, tech lead / principal, relevant engineers  
**Output:** a backlog where the top 2 sprints' worth of stories pass DoR

**Good refinement session agenda:**
1. (10 min) Review and close out action items from last refinement
2. (15 min) Groom the 1–3 stories that are most likely to be next sprint's focus — get them to Ready
3. (30 min) Walk upcoming stories: clarify scope, split if too large, identify dependencies
4. (10 min) Identify any spikes or research needed before stories can be estimated
5. (5 min) Record open questions with owners and deadlines

**Refinement health signals:**
- Top of backlog is always 2 sprints deep of Ready stories → healthy
- Team surprises in planning because stories weren't refined → refinement gap
- Refinement consistently runs over time → stories are still too large when they arrive

---

## Story Splitting Patterns

Large stories are the most common planning failure. Use these split patterns:

| Pattern | Example |
|---------|---------|
| **By workflow step** | Create order → Confirm order → Cancel order (3 stories) |
| **By user role** | Admin can X, Customer can X (2 stories) |
| **By data variation** | Happy path → Error cases → Edge cases |
| **By interface** | API first → UI separately |
| **By acceptance criteria** | Each criterion becomes its own story |
| **Spike first** | Research/proof-of-concept → implementation |
| **By environment** | MVP in prod-lite → full prod rollout |

**Rule:** if a story is more than 5 story points (or more than 3–4 engineer-days), look for a split.

---

## FAANG Interview Framing

**"How do you make sprint planning effective at scale?"**

> Sprint planning is only as good as the work that happens before it. I invest in refinement: stories must pass a Definition of Ready before entering planning, which means acceptance criteria, dependencies, and estimates are agreed upon upfront. In planning itself I focus on the sprint goal, not the task list — the goal survives; individual stories are negotiable within it. I also protect capacity explicitly: 20% for unplanned work. Teams that plan to 100% spend half the sprint negotiating scope changes rather than delivering.

**"What's the difference between a sprint commitment and a sprint forecast?"**

> A commitment is a promise to a fixed scope. A forecast is a probability-weighted prediction. I favour forecasts because they are honest about uncertainty. The sprint goal is the commitment — the team commits to achieving that outcome. The story list is a forecast — the team believes those stories will achieve the goal, but stories can be swapped or descoped without breaking the commitment. This distinction matters when stakeholders start treating a story list as a contract.
