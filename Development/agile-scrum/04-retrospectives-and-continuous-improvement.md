# Retrospectives and Continuous Improvement

A retrospective should improve the system, not just the mood in the room. The best retros produce a small number of concrete experiments with owners, due dates, and measurable outcomes.

## Retrospective Goals

- Identify one or two systemic issues that mattered in the sprint
- Separate symptoms from causes
- Decide on actions the team can actually complete
- Reinforce positive behaviors that worked well

## A Useful Retro Structure

1. Set the tone: blameless, specific, and time-boxed.
2. Review facts: what happened, not what people think happened.
3. Group observations into themes.
4. Pick the highest-leverage issue.
5. Define an experiment with an owner and deadline.
6. Revisit prior action items before closing.

## Action Item Quality Bar

| Good action item | Weak action item |
|------------------|------------------|
| Add deployment checklist step for DB migrations | Be more careful with deployments |
| Create runbook for flaky test quarantine | Improve testing |
| Add alert for checkout error rate > 2% for 5 minutes | Improve observability |

## Common Anti-Patterns

- Turning retros into a complaint session
- Collecting too many action items to be realistic
- Assigning generic ownership to the whole team
- Repeating the same issue without tracking whether the fix worked
- Confusing correlation with root cause

## Measure Whether the Retro Worked

| Signal | What it means |
|--------|---------------|
| Action items completed | The team can change its environment |
| Fewer repeat incidents | The system is improving |
| Shorter cycle times on known bottlenecks | The fix had operational value |
| Better discussion quality | Psychological safety is improving |

## Principal Engineer Guidance

- Make the learning loop visible in team planning.
- If an issue repeats, treat it as a system design problem, not a morale problem.
- Tie retro actions to engineering metrics when possible.
- Keep the scope small enough that the team can finish the experiment in one sprint.

## Interview Callout

A strong answer explains how you would convert a recurring friction point into a measurable experiment. The interviewer is looking for systems thinking, not just facilitation skill.

---

## Retrospective Formats

Different formats surface different kinds of feedback. Rotate formats across sprints to prevent staleness.

### Format 1: Start / Stop / Continue

The simplest format. Suitable for a team new to retros or when time is limited.

| Column | Question |
|--------|---------|
| **Start** | What should we begin doing that we are not doing? |
| **Stop** | What are we doing that is not adding value or is actively harmful? |
| **Continue** | What is working well that we should protect? |

**Timebox:** 45 min. Sticky notes (physical or Miro/FigJam), dot voting for prioritisation.

---

### Format 2: 4Ls (Liked / Learned / Lacked / Longed For)

Useful when you want to capture knowledge transfer alongside process.

| Column | Question |
|--------|---------|
| **Liked** | What worked well? |
| **Learned** | What did we discover this sprint? |
| **Lacked** | What was missing that hurt us? |
| **Longed For** | What do we wish we had? |

---

### Format 3: Sailboat (Rose / Anchor / Wind / Iceberg)

Visual metaphor; works well for teams that are visual thinkers or for a change of pace.

```
         🌹 Rose (what helped us)   ⛵ Team
         💨 Wind (what pushed us)
         ⚓ Anchor (what slowed us)
         🧊 Iceberg (what could sink us)
```

Particularly effective for surfacing risks (iceberg) that standard formats miss.

---

### Format 4: Mad / Sad / Glad

Lightweight emotional check-in combined with action generation. Good for distributed teams.

| Column | Meaning |
|--------|---------|
| **Mad** | What frustrated the team? |
| **Sad** | What disappointed the team? |
| **Glad** | What made the team happy? |

Follow up with: "What is one action that would reduce Mad and Sad next sprint?"

---

### Format 5: 5 Whys — Root Cause Analysis

Use when a specific incident or recurring issue needs deeper analysis. Not a whole-retro format — use for one identified problem.

```
Example: "We missed the sprint goal for the second time."

Why 1: We underestimated the integration work.
Why 2: We did not spike the third-party API before planning.
Why 3: There is no standard in our DoR requiring API verification.
Why 4: Our DoR was written 6 months ago and hasn't been updated.
Why 5: We have no scheduled review of our DoR.

Root cause: DoR maintenance is not part of our process.
Action: Add quarterly DoR review to the team calendar with an owner.
```

The 5 Whys stops when you reach something the team can actually change, not just describe.

---

### Format 6: Team Health Check (Squad Health Check)

Spotify pioneered this format. Useful for quarterly deep-dives rather than every sprint.

Rate each dimension Green / Amber / Red and trend vs. last quarter:

| Dimension | Question |
|-----------|---------|
| **Delivering value** | Are we shipping things that matter to customers? |
| **Easy to release** | Is our release process smooth and low-risk? |
| **Fun** | Is the team enjoying the work? |
| **Health of codebase** | Are we proud of the code quality? |
| **Learning** | Are individuals and the team growing? |
| **Mission** | Do we understand and believe in what we are building? |
| **Pawns or players** | Do we feel ownership over our work? |
| **Speed** | Are we moving at a pace we are happy with? |
| **Support** | Do we get support when we need it? |
| **Teamwork** | Is collaboration working well? |

**Output:** a heatmap that shows where to invest next quarter.

---

## Psychological Safety — The Prerequisite

No retro format works without psychological safety. The team must believe they can speak honestly without career consequences.

**Signs of low psychological safety in a retro:**
- Everyone says things are "fine"
- Complaints only appear anonymously
- The same senior person dominates discussion
- Nothing negative is mentioned about the process
- Action items are always directed at processes, never at how leadership behaves

**How to build it:**
1. **Prime directive**: "Regardless of what we discover, we understand and truly believe that everyone did the best job they could, given what they knew at the time, their skills and abilities, the resources available, and the situation at hand." (Norman Kerth)
2. Name the rule: feedback is about systems and processes, not individuals
3. As a principal engineer, model vulnerability: share your own process failures first
4. Rotate facilitation so the retro is not always owned by the same person with authority
5. Follow through on action items — nothing kills safety faster than retros that produce no change

---

## The Retro Action Item Quality Bar

Every action item must have:
- A **specific outcome** (not "improve testing")
- A **single named owner** (not "the team")
- A **due date** (next sprint, next retro, end of quarter)
- A **way to verify** it was completed

```
Retro Action Item Template:

Action: [What will be done]
Owner: [Name of one person responsible]
Due:   [Sprint N / date]
Done when: [Verifiable condition]
Status: [ ] Open  [ ] In Progress  [ ] Complete
```

**Review prior action items at the start of every retro.** If actions are not being completed, the retro is producing theatre, not improvement.

---

## Retro Antipatterns — How Retros Fail

| Anti-pattern | What it looks like | Fix |
|-------------|-------------------|-----|
| **Groundhog Day** | Same issues surface every sprint with no resolution | Escalate to team charter or EM; block on this until resolved |
| **Action item graveyard** | Items from 4 sprints ago still open | Cap retro output to 1–2 items; don't add new until old are done |
| **Blame session** | Discussion names individuals, not systems | Reset with the prime directive; redirect to: "what process allowed this?" |
| **Positivity washing** | Only "Glad" items surface; no real issues raised | Switch format; ask anonymously; have EM step out |
| **No follow-through** | Actions are logged and forgotten | Owner presents status in next sprint planning |
| **Too many participants** | 15+ people, nobody says much | Split into sub-team retros; escalate systemic issues to a shared session |

---

## Continuous Improvement System

A single retro is not continuous improvement. The system is:

```
Sprint N retro
  │
  ├─ Identify 1–2 highest-leverage issues
  │
  ├─ Define experiments with owners + due dates
  │
  ├─ Execute experiments during Sprint N+1
  │
  ├─ Review outcomes in Sprint N+1 retro:
  │    Did the experiment produce the expected change?
  │    If yes → standardise (update DoD, DoR, working agreement)
  │    If no → diagnose and re-run or discard
  │
  └─ Repeat
```

This loop is the difference between a team that complains and a team that improves.

---

## Linking Retros to Engineering Metrics

The most credible retros tie action items to measurable signals:

| Retro complaint | Corresponding metric | Target experiment |
|----------------|---------------------|-------------------|
| "Too many bugs in prod" | Change failure rate (DORA) | Add mutation testing to CI; target > 80% coverage on critical paths |
| "PRs take too long to review" | Review turnaround time | Implement CODEOWNERS; add review SLA to team working agreement |
| "Deploys are stressful" | Deployment frequency + time to restore | Introduce feature flags; automate rollback test |
| "Sprint planning takes forever" | Planning session duration | Enforce DoR; reject unready stories before the meeting |
| "We keep carrying over stories" | Carryover rate | Split stories to max 3 days; track story size distribution |

---

## FAANG Interview Framing

**"How do you run a retro that actually produces change?"**

> Three things make retros produce change instead of just discussion. First, I enforce a small action item limit: maximum two items per retro, and we don't add new items until the previous ones are done. Second, every action item has a single named owner and a verifiable done condition — not "the team should be more careful." Third, I open every retro by reviewing the previous sprint's actions: if they weren't done, we discuss why and either close them or block on them. The format is secondary to this discipline.

**"What do you do when a team's retrospective keeps surfacing the same issue without resolution?"**

> A recurring issue is a system problem, not a conversation problem. If the same thing comes up three sprints in a row, I escalate: either the fix requires authority the team doesn't have (an EM decision, a budget ask, a change to another team's process), or the team hasn't committed to the right experiment. I ask explicitly: "Is this in our control to fix, or does it require someone outside this room?" If it's outside the room, I escalate with data. If it's inside the room, I block the team on implementing one specific change before moving on.
