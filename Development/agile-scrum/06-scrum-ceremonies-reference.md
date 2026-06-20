# Scrum Ceremonies — Complete Reference

This file is the definitive ceremony playbook. Each Scrum ceremony has a specific purpose, a timebox, a set of participants, a facilitation agenda, and measurable success criteria. Use this as a practical guide before facilitating or participating in any ceremony.

---

## The Five Scrum Ceremonies

| Ceremony | When | Timebox (2-week sprint) | Owner |
|----------|------|------------------------|-------|
| **Sprint Planning** | Start of sprint | ≤ 2 hours | Scrum Master (facilitation), Team (content) |
| **Daily Scrum / Standup** | Every day | 15 minutes | Development Team |
| **Sprint Review / Demo** | End of sprint | ≤ 1 hour | Product Owner (facilitation), Team (demo) |
| **Sprint Retrospective** | After review | ≤ 90 minutes | Scrum Master |
| **Backlog Refinement** | Mid-sprint | ≤ 90 min × 1–2 sessions | Product Owner + Team |

---

## 1. Sprint Planning

**Purpose:** Create a plan for the sprint. Align on a sprint goal and select stories the team believes they can complete.

**Participants:** Scrum Master, Product Owner, full Development Team. Stakeholders are NOT invited.

**Timebox:** 2 hours for a 2-week sprint (4 hours for a 4-week sprint). Hard cap.

### Agenda

```
Part 1 — What (45–60 min)
  □ (5 min)  PO presents the sprint goal proposal
  □ (10 min) Team capacity review: who is available, what is the buffer?
  □ (30 min) Walk top backlog items: clarify, confirm DoR, agree on inclusion
  □ (5 min)  Agree on the sprint goal (team, not just PO)

Part 2 — How (45–60 min)
  □ (30 min) Break selected stories into tasks; surface hidden work
  □ (10 min) Name dependencies, risks, assumptions
  □ (5 min)  Final capacity check — does the task board match capacity?
  □ (5 min)  Team confidence vote (fist of five or thumbs up/down)
```

### Confidence Vote (Fist of Five)

```
5 fingers = "I'm confident and ready to go"
4 fingers = "I'm comfortable; minor uncertainties"
3 fingers = "I have some concerns but we can work through them"
2 fingers = "Significant concerns; we need to discuss further"
1 finger  = "I cannot commit to this; we need to revisit the plan"
```

Any vote of 1 or 2 should be surfaced and discussed before the session ends.

### Facilitator Checklist

- [ ] Backlog is sorted and DoR-passing items are at the top
- [ ] Capacity is calculated before the meeting starts, not during
- [ ] A printed or visible sprint goal draft is available
- [ ] Dependencies from the previous sprint are closed or carried forward explicitly
- [ ] Prior carryover is explicitly re-estimated, not just moved

### Success Criteria

- Sprint goal is written and agreed upon
- Team can articulate the goal in one sentence without looking at notes
- Task board is populated with enough detail for day-one work to begin
- No story is in the sprint without a named dependency owner (if dependencies exist)
- No engineer leaves uncertain about what they will work on first

---

## 2. Daily Scrum (Standup)

**Purpose:** Inspect progress toward the sprint goal and create a plan for the next 24 hours. Surface blockers.

**Participants:** Development Team. Scrum Master attends to remove blockers. Product Owner and stakeholders may observe but should not participate.

**Timebox:** 15 minutes. Hard cap. Same time, same place.

### The Three Questions (classic format)

1. What did I complete yesterday toward the sprint goal?
2. What will I complete today toward the sprint goal?
3. Is anything blocking me?

**Important:** questions are about the sprint goal, not individual task lists. If someone has no contribution to the goal that day, that is useful information.

### Improved Format — Walking the Board

A better format than three questions for most teams:

```
Walk each story on the board from right to left (Done → In Progress → To Do):

  For each in-progress story:
    - Who is working on it?
    - Is it on track to be done by end of sprint?
    - Are there blockers?

  For the sprint goal:
    - Are we on track overall?
    - What is the highest-leverage action for the team today?
```

Walking the board keeps discussion focused on completion rather than activity.

### Best Practices

- **Respect the timebox:** extended discussions should be parked and resolved in a follow-up ("let's take that offline")
- **No problem-solving in the standup:** raise the issue; schedule the solution
- **Update the board before the standup, not during:** everyone can see state as the meeting starts
- **Remote standup:** use video, not just text; mute when not speaking; shared board visible
- **Avoid status reporting to a manager:** the standup is the team talking to each other, not reporting upward

### Anti-Patterns

| Anti-pattern | Signal | Fix |
|-------------|--------|-----|
| Reporting to the PM/manager | Engineers look at the manager when speaking | Scrum Master physically moves to the side |
| "No blockers" every day | Blockers exist but aren't raised | Ask: "What would make today go faster?" |
| Standup runs 30–45 minutes | Team is problem-solving, not just syncing | Park extended discussions; enforce timebox |
| Remote team skips video | Less engagement; harder to read the room | Camera-on as a working agreement |
| Same two people speak; others passive | Not a team standup, it's a check-in | Walk-the-board format; direct questions to quiet members |

---

## 3. Sprint Review (Demo)

**Purpose:** Inspect the increment and adapt the product backlog. Present completed work to stakeholders and gather feedback.

**Participants:** Scrum Team + stakeholders + customers where possible. The more real users, the better the feedback.

**Timebox:** 1 hour for a 2-week sprint.

### Agenda

```
(5 min)  Sprint goal recap: what did we set out to achieve?
(5 min)  Capacity and delivery summary: what did we plan vs. what we delivered?
(40 min) Demo of completed increment (live, not slides)
          - Walk the user journey, not the implementation details
          - Show the happy path AND edge cases
          - Allow stakeholders to interact with the feature
(10 min) Feedback capture and backlog impact discussion
          - What should we do next based on what you've seen?
          - What questions does this raise?
```

### Demo Standards

**Do:**
- Demo against production or production-equivalent environment
- Show the feature as a user would experience it
- Invite stakeholders to click through the feature themselves
- Show what was NOT completed and why (transparency)

**Don't:**
- Present slides instead of a live demo
- Demo against a fake dataset that makes it look better than it is
- Skip the failure cases or edge conditions
- Block stakeholder questions until the end (let them interact in real time)

### Handling Incomplete Stories

If a story is not done per the Definition of Done, it is **not demoed**. Undone work is not value delivered.

```
Correct language: "We planned to complete the bank account validation story this sprint.
We completed the backend API but the UI is not done. This story will be carried forward
and is not part of this sprint's increment."

Incorrect language: "We mostly finished the bank account story — we'll show you the
backend and the UI will be done next week."
```

Demoing incomplete work misleads stakeholders about the definition of done and creates false confidence.

### Feedback Collection Template

```
After the demo, capture in the team's backlog management tool:

  What we heard:
    - [stakeholder quote or observation]

  What it means for the backlog:
    - [new story / change to existing story / no change needed]

  Decision:
    - Accepted as-is → [move to done]
    - Needs iteration → [add follow-up story]
    - Direction change → [update product goal]
```

---

## 4. Sprint Retrospective

**Purpose:** Inspect the team's process and relationships, and create a plan for improvements in the next sprint.

**Participants:** Scrum Team only (no stakeholders, no leadership unless they are part of the team).

**Timebox:** 90 minutes for a 2-week sprint.

See [04-retrospectives-and-continuous-improvement.md](04-retrospectives-and-continuous-improvement.md) for full format details, anti-patterns, and psychological safety guidance.

### Core Agenda (any format)

```
(10 min) Check-in and set the tone (prime directive)
(5 min)  Review previous sprint's action items — what was completed?
(20 min) Data gathering — what happened this sprint? (sticky notes, dot voting)
(15 min) Insight generation — group themes, identify patterns
(20 min) Action item definition — 1–2 items, owner, due date, done criteria
(5 min)  Appreciations — call out something a teammate did well
(5 min)  Close — confirm action items are recorded
```

### The Prime Directive

Read at the start of every retrospective:

> "Regardless of what we discover, we understand and truly believe that everyone did the best job they could, given what they knew at the time, their skills and abilities, the resources available, and the situation at hand."
> — Norman Kerth

---

## 5. Backlog Refinement (Grooming)

**Purpose:** Prepare the backlog so that sprint planning can run efficiently. Ensure upcoming stories meet the Definition of Ready.

**Participants:** Product Owner (required), tech lead or senior engineer (required), 1–2 additional engineers (rotating), Scrum Master (optional, for facilitation).

**Timebox:** 60–90 minutes, 1–2 sessions per sprint. Target: maintain 2 sprints of Ready stories at the top of the backlog.

### Agenda

```
(5 min)  Review open questions from the previous session
(10 min) Confirm top items are still in priority order (PO + team)
(50 min) Walk upcoming stories:
          For each story:
            □ Is the problem clear?
            □ Are acceptance criteria written?
            □ Are dependencies identified?
            □ Is it small enough to complete in one sprint?
            □ Ready to estimate? → estimate it
            □ Not ready? → document what's missing and assign an owner
(10 min) Identify spikes needed for upcoming work
(5 min)  Record open items with owners and deadlines
```

### Refinement Output

After a good refinement session:
- Top 10–15 stories are estimated
- Top 5 stories pass DoR
- At least one sprint's worth of stories is ready for planning
- Open questions have named owners and due dates

### Three Amigos Sessions

Before writing the acceptance criteria for a complex story, run a **three amigos** session:
- **Product Owner** — defines the why and the what
- **Developer** — explains the how and identifies technical constraints
- **Tester / QA** — identifies the edge cases and acceptance conditions

15–20 min per story. The output is a shared understanding before any code is written.

---

## Ceremony Timebox Quick Reference

```
Sprint length: 2 weeks

┌─────────────────────────────────┬──────────────────┐
│ Ceremony                        │ Timebox          │
├─────────────────────────────────┼──────────────────┤
│ Sprint Planning                 │ ≤ 2 hours        │
│ Daily Scrum                     │ 15 minutes       │
│ Sprint Review                   │ ≤ 1 hour         │
│ Sprint Retrospective            │ ≤ 90 minutes     │
│ Backlog Refinement (per session)│ ≤ 90 minutes     │
├─────────────────────────────────┼──────────────────┤
│ Total ceremony time per sprint  │ ~7–8 hours       │
│ % of 2-week sprint (1 engineer) │ ~7–8%            │
└─────────────────────────────────┴──────────────────┘
```

A well-run Scrum team spends < 10% of engineer time in ceremony. If ceremonies take more than 10%, the ceremonies are not well-run — not the answer is more ceremony.

---

## Ceremony Health Checklist

Use this quarterly to evaluate ceremony quality:

| Ceremony | Healthy signal | Warning signal |
|----------|---------------|---------------|
| Sprint Planning | Done in ≤ 2 hours; team is confident | Runs long; team leaves uncertain |
| Daily Scrum | 15 min; blockers raised and resolved | 30+ min; no real blockers ever raised |
| Sprint Review | Stakeholders provide actionable feedback | Only team present; no real feedback |
| Retrospective | Action items completed next sprint | Action items forgotten; same issues recur |
| Refinement | Top of backlog always ready | Stories arrive at planning unestimated |

---

## Scrum Roles — Responsibilities Summary

### Product Owner
- Owns the product vision and product goal
- Maintains and prioritises the product backlog
- Ensures stories meet the Definition of Ready before planning
- Accepts stories against the Definition of Done
- The single source of truth for "what to build next"
- **NOT** a project manager, a requirements secretary, or a proxy for a committee

### Scrum Master
- Servant-leader for the team; removes impediments
- Facilitates ceremonies (does not own content)
- Coaches the team on Scrum principles
- Shields the team from external interruptions during the sprint
- Does NOT manage the team, assign work, or make technical decisions

### Development Team
- Cross-functional: all skills needed to deliver the increment
- Self-organising: decides how to do the work
- Jointly owns the sprint commitment
- Accountable for the Definition of Done
- Typically 3–9 people (fewer lacks cross-functionality; more creates coordination overhead)

---

## FAANG Interview Framing

**"What makes a Daily Scrum effective?"**

> The purpose of the standup is for the team to inspect progress toward the sprint goal and update the plan for the day — not to give status reports to a manager. The most effective format I've used is walking the board from right to left: start with what's closest to done, surface blockers on in-progress items, and ask "what's the most important thing we can do today to advance the sprint goal?" That keeps it goal-focused and under 15 minutes. The anti-pattern I see most is engineers reporting to the Scrum Master or PM — the standup is the team talking to each other.

**"How do you run a Sprint Review that produces useful feedback?"**

> The review has to be a live demo against a production-equivalent environment, not a slide deck. I invite real stakeholders and customers, walk the user journey rather than the implementation details, and let stakeholders interact with the feature in real time. I also show what we didn't complete — transparency builds trust. The most valuable part is the discussion after: I ask explicitly "what should we do differently based on what you've seen?" and I capture those as backlog items or goal adjustments before the meeting ends. A review where no backlog changes are produced is a rubber-stamp ceremony, not an inspection.

**"How do you handle a Scrum Master who turns ceremonies into status reporting sessions?"**

> I address it directly and specifically. I describe what I observe: "I've noticed our standups run 30 minutes and most of the time is engineers reporting their task progress to you rather than the team planning together." Then I suggest the concrete change: walk-the-board format, with the Scrum Master physically stepping back and letting the team facilitate itself. If the behaviour continues, it's usually a role misunderstanding — the SM thinks their job is to collect information, not facilitate self-organisation. I clarify the role expectation one-on-one and follow up.
