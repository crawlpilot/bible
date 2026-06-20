# Writing RFCs That Drive Decisions

**Category:** Principal Engineer Skills · Technical Communication · Alignment  
**Framework:** RFC (Request for Comments) process  
**Interview context:** "How do you drive technical alignment across teams?" / "Walk me through a significant technical proposal you led." / "How do you get buy-in for a major architectural change?"

> An RFC that gets 50 comments and no decision is a failure. An RFC that gets 5 comments and a clear decision is a success. The goal is a decision, not a discussion.

---

## Why RFC Writing is a PE-Level Skill

Any engineer can write a design document. The PE-level skill is writing one that:
- Gets read by the right people
- Produces a clear decision (not endless debate)
- Builds alignment even among those who voted against it
- Drives execution after the decision is made

Most RFCs fail — not because the technical content is wrong, but because the process around them is wrong. A principal engineer understands that an RFC is a **social and political instrument** as much as a technical one.

---

## When to Write an RFC (vs. Something Else)

Understanding when NOT to write an RFC is as important as knowing how to write one.

| Document type | When to use | Decision-making | Audience |
|--------------|-------------|----------------|---------|
| **RFC** | Cross-team change, significant trade-offs, needs formal buy-in | Required — RFC must produce a decision | Multiple teams, principals, leadership |
| **ADR** (Architecture Decision Record) | Single-team decision already made, needs documentation | Already decided — ADR records it | Current and future team members |
| **Design Doc** | Implementation detail for a feature, within one team's scope | Made by the team, no cross-team buy-in needed | The implementing team |
| **Tech Spec** | Detailed API/interface specification for consumers | Agreed separately, spec is the output | Consuming teams |
| **1-pager / Pre-RFC** | Early-stage idea that needs directional feedback before investment | No formal decision — directional signal | Key stakeholders only |

**RFC triggers:**
- The change affects more than one team's codebase or operations
- There are meaningful trade-offs where reasonable engineers can disagree
- The change cannot easily be reversed (database schema, public API, shared infra)
- The change requires 2+ weeks of engineering effort per team

If a decision is obviously correct and only affects your team — write an ADR, not an RFC. RFCs have a cost (time, coordination, attention); use them when the value of the coordination justifies that cost.

---

## Why RFCs Fail

Before the structure, understand the failure modes. Most RFC authors focus entirely on the technical content. Most RFC failures are process failures, not content failures.

**Failure mode 1: Written after the decision is made**  
The author has already decided and is writing the RFC to get formal sign-off. Reviewers sense this. They stop engaging seriously because they know the decision won't change. The RFC becomes theater. Solution: involve key stakeholders in the problem framing before writing the RFC — make them co-authors of the question, not just reviewers of your answer.

**Failure mode 2: Written for the wrong audience**  
A 30-page deep-dive written for other architects, when the actual blocker is getting EM and PM buy-in. Solution: know who is blocking the decision and write for them. It is fine to have a short executive summary + long technical appendix.

**Failure mode 3: No clear decision requested**  
The RFC ends with "thoughts welcome." This invites infinite discussion. Solution: state explicitly what you need the readers to decide, by when.

**Failure mode 4: Alternatives are strawmen**  
The RFC presents two "alternatives" that are both obviously worse than the proposal. Reviewers who favour a third option have nowhere to anchor their feedback. Solution: steelman the best alternative — find the engineer most likely to push the alternative approach and co-author that section with them.

**Failure mode 5: Too long to read**  
Reviewers skim and comment on the parts they skimmed. Discussion becomes a 50-comment thread where half the comments are based on misunderstandings of the proposal. Solution: impose a page limit on yourself (6–8 pages for the proposal, appendices for details). If the reader has to read all 30 pages to understand the proposal, the proposal isn't well-structured.

---

## RFC Structure That Works

```markdown
# RFC-NNNN: [Title — verb + noun + why]
# Good: "Migrate Order Service to Event-Driven Architecture for Independent Scaling"
# Bad: "Order Service Architecture"

**Status:** Draft | In Review | Accepted | Rejected | Superseded  
**Author:** @name  
**Reviewers:** @team1-lead @team2-lead @principal-group  
**Decision deadline:** YYYY-MM-DD  
**Discussion:** [link to comment thread / meeting invite]

---

## TL;DR (3 sentences max)
State the problem, the proposed solution, and the key trade-off.
A reader who only reads this section should be able to vote on the RFC.

## Problem Statement
What is broken or missing? Quantify it.
"Our order service handles 3,000 req/s at peak. Database write contention
causes P99 latency to spike to 2.1s during flash sales (SLO = 500ms).
Manual scaling takes 8 minutes — too slow for flash sale traffic."

Do NOT mention your solution here. This section should be agreeable to
someone who disagrees with your proposed solution.

## Motivation
Why does this need solving now? What happens if we don't act?
What are the forcing functions (scale, deadline, cost, risk)?
"Flash sale season starts in 6 weeks. Last year's equivalent event caused
42 minutes of degraded checkout and an estimated $1.2M in lost GMV."

## Proposed Design
Your solution. Include:
- Architecture diagram (Mermaid or ASCII — must be in the RFC, not linked)
- Key data flows
- Interface/API changes
- Migration path (if changing existing behaviour)

Be specific enough that a senior engineer could implement this.
But don't document every method — that's a design doc, not an RFC.

## Trade-offs
What are you giving up? What risks does this introduce?
Use a table:

| Dimension       | Proposed approach        | Current approach         |
|-----------------|-------------------------|--------------------------|
| Write latency   | Async (eventual)        | Sync (immediate)         |
| Operational cost| New Kafka cluster        | None                     |
| Failure modes   | Consumer lag, redelivery | Single DB contention point|
| Migration risk  | Medium (dual-write phase)| None (no change)         |

## Alternatives Considered
For each alternative: what it is, why we considered it, why we're not proposing it.
This section MUST be written seriously — not strawmen.
"We evaluated auto-scaling the database (rejected: takes 8 min, too slow for
flash sale spikes) and read replicas (rejected: the bottleneck is writes,
not reads — this doesn't address root cause)."

## Rollout Plan
Phase-by-phase implementation. Each phase should be independently deployable
and independently reversible.
"Phase 1: Introduce Kafka alongside existing sync path (no behaviour change).
Phase 2: Dual-write (sync + async) for 2 weeks — validate consumer correctness.
Phase 3: Async-only path. Old sync path behind feature flag for 2 weeks.
Phase 4: Remove sync path."

## Open Questions
Unresolved questions you want reviewer input on.
Mark each with [BLOCKING] if the answer changes the design, or [NON-BLOCKING].
"[BLOCKING] Should consumer retries use dead-letter queues or exponential backoff?
[NON-BLOCKING] Should we use Kafka Streams or a standalone consumer service?"

## What We Need from Reviewers
"Please indicate [APPROVE], [APPROVE WITH CONCERNS], or [BLOCK] and your reason.
Blocking concerns must be specific and actionable. 'I don't like Kafka' is not a
blocking concern. 'Kafka introduces at-least-once delivery which breaks our
billing deduplication logic in the following way...' is."
```

---

## Running the RFC Process

The document is half the work. The process is the other half.

### Timeline Template

```
Day 0:   Author shares RFC with 2–3 trusted reviewers for pre-review
         (before it goes wide — catch structural problems early)

Day 3:   RFC published to #engineering-rfcs channel
         + Direct message to required reviewers with deadline
         + 45-minute office hours slot booked for the following week

Day 3–8: Async comment period
         Author responds to all comments within 24 hours
         Author updates the RFC doc live as issues are resolved

Day 8:   Office hours / synchronous review meeting (optional, for complex RFCs)
         Purpose: resolve blocking concerns, not re-discuss non-blockers

Day 10:  Decision deadline
         Author reads the room: approve / approve-with-concerns / block?
         If blocking: explicit resolution step (not more async debate)

Day 11:  Decision posted to RFC doc (status updated to Accepted/Rejected)
         + Summary of key objections and how they were addressed
         + Next steps / implementation kickoff
```

**The decision meeting (for contested RFCs):**  
If the RFC has unresolved blocking concerns after the async period, hold a 60-minute synchronous meeting. Agenda: 10 min to restate the proposal (don't re-read the document), 40 min to address blocking concerns specifically, 10 min to call the decision. The decision-maker (typically the senior principal or the engineering director for the affected area) is in the room. The meeting ends with a decision — not "we'll continue the discussion."

---

## How to Get RFC Adoption Without Authority

You write the RFC. You don't own the teams that have to implement it. How do you get them to adopt it?

**1. Make them co-authors of the problem, not just reviewers of your solution**  
Before writing the RFC, talk to the tech leads of affected teams. Ask: "I've been thinking about X problem — do you see the same problem?" If they say yes, they're already invested in the solution. If they say no, you need to understand why before writing anything.

**2. Give the RFC to the team most likely to resist it, first**  
Ask them to review a draft before it goes wide. This accomplishes two things: they catch problems before they become public objections, and they feel heard before being presented with a fait accompli. Engineers who feel heard are more likely to accept decisions they don't fully agree with.

**3. Make the RFC easy to vote against, then address the objections**  
An RFC with obvious flaws that the author hasn't acknowledged doesn't build trust. An RFC that says "we know this approach has trade-off X, here's why we think it's worth it" does. Reviewers who planned to raise X now have to say "but you already acknowledged X — why do you still think it's worth it?" — a harder objection to sustain.

**4. Accept losing gracefully on non-essentials**  
If a reviewer's blocking concern is about a detail that doesn't affect the core proposal — give it to them. "You're right, we should use dead-letter queues rather than retry loops. I've updated the RFC." This builds political capital for the battles that matter. Engineers who feel like they've influenced the outcome are more likely to support the implementation.

**5. Make the "approved" state low-commitment**  
The RFC decision is a commitment to proceed with the approach, not a commitment to every detail of the implementation. "APPROVE" means "I think this direction is right," not "I have no further feedback on any aspect of this design." Reducing the stakes of the approval lowers the threshold for buy-in.

---

## PE vs. Mid-Level on RFC Writing

| Dimension | Principal Engineer | Senior / Staff Engineer |
|-----------|-------------------|------------------------|
| **Audience awareness** | Adjusts content and length for the actual blocking decision-maker | Writes the same document for all audiences |
| **Problem statement** | Fully separate from solution; quantified | Mixed in with the solution |
| **Alternatives** | Steelmanned — written with input from the people who favour them | Strawmen — obviously inferior options |
| **Process ownership** | Sets and enforces the deadline; owns the decision | Waits for feedback; decision happens when it happens |
| **Response to blockers** | Resolves or escalates within 24 hours | Engages when convenient |
| **Post-decision** | Updates RFC doc, announces decision, kicks off implementation | Moves on; RFC document is never updated |
| **Long-term** | RFC feeds into ADR catalogue and architecture documentation | RFC document is abandoned after decision |

---

## Common Interviewer Follow-Up Questions

**"Walk me through a significant RFC you drove. What was the key technical debate?"**

> "The RFC was to move our event publishing from synchronous DB writes (write to the events table in the same transaction as the entity write) to a transactional outbox pattern. The key debate was around exactly-once vs. at-least-once delivery semantics. One team argued that idempotent consumers are an unreasonable ask — they had 20 consumers that weren't idempotent. My response was: 'You're right, but the alternative — synchronous in-process event publishing — is the reason we had two incidents last quarter where a broker outage caused checkout writes to fail. The question is which risk is higher: retrofitting 20 consumers for idempotency or another checkout outage.' I quantified both: consumer idempotency work across all teams was ~6 engineer-weeks; the previous checkout incident was $800K GMV. The RFC was approved. I ran office hours for 3 weeks to help teams implement idempotency correctly."

**"What do you do when a senior engineer blocks your RFC and you think they're wrong?"**

> "First, I take the objection seriously regardless of my initial reaction — some of the best improvements to my proposals came from people I initially disagreed with. I ask for specifics: 'What would need to be true for you to change from BLOCK to APPROVE WITH CONCERNS?' This converts a vague 'I don't like this' into a specific, addressable concern. If I address the specific concern and they continue to block on the same grounds, I escalate to the decision-maker — not to overrule them, but to ask: 'Is this a blocking concern from the organization's perspective, or is this a concern we can accept and mitigate?' Most blocking concerns at the individual level are 'approve with concerns' at the organizational level. The decision-maker makes that call, not me."

**"How long should an RFC be?"**

> "Short enough to be read by the decision-makers, long enough to cover the real trade-offs. I use a TL;DR that a VP can read in 90 seconds, a 6–8 page proposal that a tech lead reads fully, and appendices with implementation details that the implementing engineers reference. I've seen RFCs that were 40 pages long and got 0 substantive reviews because no one read them. I've seen 3-page RFCs that drove clean decisions in a week. Length is not a signal of quality; clarity is."
