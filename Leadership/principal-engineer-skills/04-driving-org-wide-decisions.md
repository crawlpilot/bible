# Driving Large Technical Decisions Across Teams

**Category:** Principal Engineer Skills · Org-Wide Execution · Technical Leadership  
**Framework:** Identify → Assess → Coalition → Decide → Execute → Close  
**Interview context:** "Describe a major technical initiative you led." / "How do you deprecate a legacy system that 8 teams depend on?" / "Tell me about a time you drove an org-wide technical change."

> The gap between a great recommendation and an org-wide change is execution. Any senior engineer can identify a problem and propose a solution. The principal engineer closes the gap — from whiteboard to production across teams they don't control.

---

## Why Driving Org-Wide Decisions is a PE-Level Skill

Single-team technical problems have clear ownership: the team identifies the problem, proposes a solution, gets their EM's approval, and ships it. The whole process lives within a team's span of control.

Org-wide technical decisions don't:
- Multiple teams have to change their code, their processes, or their operations
- No single EM or director owns the entire scope
- Affected teams have competing priorities and no natural incentive to do the migration work
- The decision affects people who weren't in the room when it was made

This is where principal engineers create the most leverage — and where the most common failure modes live.

---

## The Anatomy of a Large Technical Decision

Every org-wide technical decision follows the same lifecycle, regardless of type:

```
IDENTIFY ──► ASSESS ──► COALITION ──► DECIDE ──► EXECUTE ──► CLOSE
   │             │            │           │           │          │
 Problem      True cost    Build        Formal     Migration   Sunset
 framing      & scope     support      approval    dashboard   ceremony
```

**Common types:**
- Platform migration (move from X to Y: message queue, auth system, DB engine)
- Standard adoption (logging format, API style, observability tooling)
- Architecture change (decompose a shared library, introduce a service mesh)
- Deprecation (sunset a shared service or legacy API that teams depend on)
- Security/compliance remediation (TLS upgrade, secret rotation, auth migration)

---

## Phase 1: Identify — Frame the Problem Precisely

The most common mistake at this phase: jumping to a solution before the problem is agreed.

**The problem statement must answer:**
- What is broken or suboptimal today?
- Who is affected and how? (Quantify: incidents per quarter, engineer-hours wasted, latency impact, cost)
- What is the consequence of not acting? (What does the problem look like in 12 months?)
- Is this the right problem, or is it a symptom of a deeper one?

**Example of weak problem framing:**  
"We should replace RabbitMQ with Kafka."  
(This is a solution. What's the problem?)

**Example of strong problem framing:**  
"Our messaging infrastructure saturates at 12K msg/s. Our traffic is growing at 40% MoM. We will hit the saturation point in 3 months. When we hit it, we have two recent incidents as examples: in August, we had 45 minutes of order processing degradation affecting 200K customers. Our current queue can't be horizontally scaled without a full rewrite of the broker layer."

Strong problem framing achieves two things: it makes the urgency undeniable, and it makes it hard for people to resist the solution without first disputing the problem.

---

## Phase 2: Assess — Know the True Scope Before Committing

Org-wide changes almost always take longer and cost more than the initial estimate. The principal engineer's job is to discover that before committing to leadership, not after.

**The dependency audit:**  
List every team, service, and system that will need to change. For each:
- What change is required?
- Who owns it?
- What is their current capacity?
- What are their competing Q-priorities?

A migration that affects 8 teams with 3 engineers each is not 24 engineer-weeks of work. It's 8 separate scheduling conversations, 8 separate PR review cycles, 8 separate deployment risks — with inter-team sequencing dependencies.

**The hidden dependencies:**  
For any significant change, there are always dependencies that don't appear in the codebase:
- SLAs with external consumers that depend on the current interface
- Monitoring/alerting rules that will break if the metric names change
- Documentation, runbooks, and on-call scripts that assume the current behaviour
- Audit logs that have compliance requirements tied to the current format

Find these before you commit. Talk to SRE, talk to the compliance team, talk to the engineers who've been on-call for the affected systems longest.

**Scope creep prevention:**  
Define the explicit boundary of this change. Write it down: "This migration covers internal services. External API consumers are out of scope. We will address external consumers in a separate RFC if needed." Scope creep is the primary reason org-wide migrations become multi-year projects.

---

## Phase 3: Coalition — Build Support Before the Formal Decision

The formal approval meeting should not be where you find out who opposes the change.

**Key stakeholders to engage before the formal process:**

| Stakeholder | What they care about | How to engage |
|-------------|---------------------|---------------|
| Tech leads of affected teams | Team capacity, migration risk, timeline pressure | 1:1 conversations, show them the scope estimate, ask for their input on the migration plan |
| Engineering managers | Team capacity, Q-priorities, dependency on the old system | Frame as platform investment; ask what would make this feasible given their roadmap |
| SRE / platform team | Operational complexity, runbooks, monitoring | Involve them in the design phase; they often identify hidden dependencies |
| Security / compliance | Audit trail, compliance requirements | Early consultation prevents late blockers |
| Product | Timeline impact, feature freezes during migration | Honest assessment of what can/can't be shipped during migration |

**The "willing early adopter" strategy:**  
Find one team that will volunteer to go first. They get the most support from you, the tightest collaboration, and the most influence on how the migration is designed. In exchange, their success (or failure) informs all subsequent teams. A successful early adopter is the strongest possible evidence for the migration; a failed one requires honest analysis before proceeding.

---

## Phase 4: Decide — Getting the Formal Decision

**Who makes the decision?**  
Match the scope of the decision to the level of the decision-maker. A change that affects 3 teams can be decided by those teams' EMs or a senior principal. A change that affects the entire platform requires a VP or Director-level sponsor. Without the right decision-maker in the room, the approval is not durable — it can be challenged and reversed by anyone who has equal or greater seniority.

**The decision document:**  
For major org-wide decisions, the RFC (see `02-rfc-writing.md`) formalises the technical decision. But the formal approval often happens in a meeting, not in a comment thread. Prepare for the meeting:

- One-slide summary: problem, proposed solution, scope, timeline, top risk
- Be explicit about what you're asking people to decide: "We need a yes/no on proceeding with the migration. The specific implementation details will be resolved in the RFC review."
- Separate the decision meeting from the design review meeting. Design review: does the technical approach work? Decision meeting: do we commit to proceeding?

**Handling "we need more information" as a delay tactic:**  
Some stakeholders use information requests to avoid making a decision. The way to distinguish legitimate information needs from delay tactics: "What specific information would change your decision?" If they can't answer specifically, it's a delay. If they can, go get that information.

---

## Phase 5: Execute — The Migration

This is where most org-wide changes die. The RFC is approved, the kickoff meeting is celebrated, and then 4 months later 3 of 8 teams have migrated and the others have deprioritised it.

### The Migration Dashboard

Track and publish migration status publicly. The dashboard is the primary forcing function for teams to stay on schedule.

```
Service Migration Status — Q3 2024
Goal: Migrate all 8 services from MQ v1 to MQ v2 by Sept 30

Service              | Team         | Status        | Target date | Notes
─────────────────────┼──────────────┼───────────────┼─────────────┼────────────────────
payment-service      | payments-eng | ✅ Done       | Jul 15      |
order-service        | orders-eng   | 🔄 In progress| Aug 15      | 60% complete
notification-svc     | notif-eng    | 🔄 In progress| Aug 31      |
auth-service         | auth-eng     | 🔴 Not started| Aug 31      | Blocked: staffing
inventory-service    | inventory    | ✅ Done       | Jul 30      |
recommendation-svc   | data-eng     | 🟡 At risk    | Sep 15      | Dep on order-svc
search-service       | search-eng   | 🔴 Not started| Sep 30      |
reporting-service    | data-eng     | 🟡 At risk    | Sep 30      | Low priority signal
```

Publish this dashboard to #engineering-migrations weekly. It creates social accountability — teams don't want to be the red row on a dashboard that leadership can see.

### The Weekly Sync (15 minutes, not 60)

Hold a short weekly check-in with the tech lead of each team in progress:
- What shipped this week?
- What's blocked?
- What do you need from me?

Your job in these syncs is to unblock, not to supervise. If a team is blocked on a dependency, your job is to clear the dependency — talk to the other team, escalate to EMs if needed, personally review PRs if that's the blocker. The principal engineer is the migration's quartermaster.

### Handling Teams That Fall Behind

**Step 1: Understand why.** Is it capacity? A technical problem? A dependency? A business priority conflict? Don't assume it's negligence before you understand the reason.

**Step 2: Remove the blocker if possible.** Can you contribute engineering time? Can you shift a dependency's sequence? Can you simplify the migration path for this specific team?

**Step 3: Escalate if necessary.** If a team is not progressing and the reason is a business priority conflict, escalate to the EM and the director: "The migration is blocked because the team has been asked to prioritise X. This affects the overall migration timeline and has these downstream consequences. I need a prioritisation decision." This is not going around the team — it's getting the right people to make the right trade-off decision.

**Step 4: Adjust the plan if the delay is systemic.** If multiple teams are behind, the problem may be with the migration plan, not the teams. Is the migration harder than estimated? Is the migration tooling inadequate? Is the timeline unrealistic? A good principal engineer recognises when the plan needs to change and changes it — rather than blaming teams for falling behind on an unrealistic plan.

---

## Phase 6: Close — The Sunset Ceremony

The migration is not complete until the old system is decommissioned. This is where most migrations stall indefinitely: 95% migrated, the old system still running, the 5% becomes permanent.

**The sunset date:**  
Set a decommission date at the beginning of the migration, not at the end. "The old system will be taken offline on October 31. Services still using it after that date will experience failures." This creates urgency throughout the migration, not just at the end.

**The hard cutoff:**  
On the sunset date, disable the old system. Send warnings at T-30 days, T-14 days, T-7 days, T-1 day. On the day, execute. A sunset date that passes without action is a promise you didn't keep — and it makes the next migration harder to schedule because teams don't believe the dates are real.

**The migration retrospective:**  
After closure, run a brief retrospective:
- What went well?
- What took longer than expected and why?
- What would we do differently for the next migration?
- Document the migration pattern that worked for future use

This is also the recognition moment. Acknowledge the teams that migrated early, the tech lead who led the cross-team coordination, the engineers who wrote the migration tooling. Visible recognition creates positive incentives for future migrations.

---

## PE vs. Mid-Level on Driving Org-Wide Decisions

| Dimension | Principal Engineer | Senior / Staff Engineer |
|-----------|-------------------|------------------------|
| **Problem framing** | Quantified, with forcing functions and consequence of inaction | "We should migrate to X" (solution-first) |
| **Scope assessment** | Full dependency audit before committing | Estimates the technical work, misses the coordination work |
| **Coalition building** | Builds support from tech leads before formal approval | Gets formal approval first, then expects adoption |
| **Migration dashboard** | Publicly tracks progress; creates social accountability | No visibility mechanism |
| **Handling delays** | Investigates cause, removes blocker, escalates if needed | Sends reminder emails |
| **Sunset execution** | Hard cutoff on the announced date | "We'll do it when everyone is ready" (indefinite) |
| **Credit** | Recognises teams that drove the migration; distributes credit | Takes credit for the initiative |
| **Learning** | Retrospective after each migration; improves the template | Moves on to the next thing |

---

## Common Interviewer Follow-Up Questions

**"Walk me through the largest cross-team technical migration you've led."**

> "We migrated 12 services from a custom in-house authentication system to our company's central IAM platform. The trigger was a security audit that found the in-house system hadn't been updated in 18 months and had two known vulnerabilities. The scope was significant: 12 services, 6 teams, 4 different programming languages. I started by building a migration guide before asking anyone to migrate — I did the first two migrations myself to identify the integration patterns and document the common failure modes. This made every subsequent team's migration significantly easier. I set up a migration dashboard visible to all engineering directors and made it the first agenda item at the monthly engineering review. We had one team that fell 6 weeks behind because of a dependency on a third-party library that didn't support our IAM's SDK. I worked with the security team to get a 6-week extension for that specific service while the library issue was resolved — rather than holding the whole migration open for the one blocker. We closed the old system 2 weeks ahead of the original schedule. The key was starting with a working migration example, not a migration plan."

**"What do you do when a team refuses to migrate even after the formal decision is made?"**

> "First I want to understand whether 'refusal' is the right frame. In my experience, what looks like refusal is usually a capacity problem that wasn't surfaced, a dependency that makes migration technically infeasible right now, or a miscommunication about timeline. I start with a direct conversation to understand the actual obstacle. If the issue is capacity, I go to the team's EM and engineering director and frame it as a resourcing question: 'The platform decision has been made. This team needs X engineer-weeks to implement it. Either we find the capacity or we discuss the timeline implications.' If the issue is a genuine technical blocker, I get into the code with them. If the issue is a team that simply disagrees with the decision and is using capacity as a cover — I escalate. The team's engineering director needs to have the 'this is not optional' conversation. My job is to make compliance as easy as possible; it's the manager's job to make it mandatory."

**"How do you set the sunset date for a legacy system without knowing exactly when all teams will be ready?"**

> "I set it based on the realistic migration timeline plus a buffer, announced at the beginning — not at the end when everyone is 'almost done.' The reason to announce it early is that a sunset date that teams know about from the start shapes their planning; a sunset date announced when you're 80% done feels arbitrary and creates resentment. For the specific date, I work backwards from the deadline that actually matters — a compliance requirement, a cost threshold, an infrastructure end-of-life — and set the sunset date to give teams enough time to migrate while preserving the forcing function. I also establish the 'what happens if you miss it' policy upfront: services that don't migrate by the sunset date will have outages. I'd rather have that conversation at the start than at T-0."
