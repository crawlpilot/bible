# SSTAR: Driving Adoption of a Technical Standard Without Authority

**Category**: Leadership · Influence · Technical Strategy · Principal Engineer Scope  
**Framework**: SSTAR (Situation → Strategy → Task → Action → Result)  
**Interview context**: "Tell me about a time you influenced a decision you didn't have authority over" / "How do you drive alignment across teams when you can't mandate outcomes?" / "Describe a time you established a technical standard organization-wide"

> The PE-level version of this question is not about persuading one team. It's about creating the conditions where the right decision becomes the obvious decision — and then persisting through the organizational friction that change always produces.

---

## Why Influence Without Authority is a Core PE-Level Skill

At Staff/Principal level, most of your highest-impact work requires:
- Changing behavior in teams you don't manage
- Overcoming incumbency bias ("we've always done it this way")
- Aligning engineering teams whose incentive structures favor local optimization
- Sustaining momentum over months, not days

Interviewers are evaluating whether you have the tools and patience to drive change through influence, not just through technical correctness.

---

## SSTAR — Observability Standardization Across 12 Teams

### S — Situation

*"At [Company], we had 12 backend engineering teams running services across 4 different observability stacks: New Relic (3 teams), Datadog (5 teams), custom Prometheus+Grafana (3 teams), and one team using CloudWatch exclusively. When a request spanned multiple teams' services — which was the case for 80% of our user-facing flows — debugging required context-switching between 4 different monitoring tools and mentally correlating logs that had no common trace ID.*

*Our P99 MTTR for cross-service incidents was 4.2 hours. Our SRE team was spending 30% of their time in incidents just reconciling observability context across tools. We had a $1.2M annual observability spend with no unified picture of system health.*

*I was the Staff Engineer for Platform — I didn't manage any of these 12 teams, had no budget authority over their tooling choices, and had no mandate from leadership to 'fix observability.' I had two things: a strong prior that this was slowing us down, and the organizational trust to convene the conversation."*

---

### ST — Strategy

*"I've seen two failure modes for observability standardization: (1) mandate a tool from the top, and teams comply but don't adopt it properly, and (2) propose a 'framework' that nobody owns and nobody uses. Both produce the illusion of standardization without the benefit.*

*My strategy had three components: (1) prove the cost of fragmentation with data that teams couldn't dismiss, (2) propose a standard that was an evolutionary upgrade from what most teams were already using rather than a complete replacement, and (3) make adoption so low-friction that saying yes was easier than saying no.*

*The key insight was that I wasn't asking teams to give up their current tools in Phase 1 — I was asking them to add OpenTelemetry instrumentation so their traces, metrics, and logs could be correlated. Teams could keep Datadog, New Relic, or Prometheus as their backend — they just had to emit data in a common format.*

*This was important politically: 'adopt OpenTelemetry' was a much smaller ask than 'switch to Datadog.'"*

---

### T — Task

*"My responsibility was: (1) quantify the cost of fragmentation in terms engineering managers would take to their VPs, (2) design a phased migration path that respected existing team tooling choices, (3) write the RFC and socialize it through the right channels, (4) build the initial instrumentation library to reduce adoption cost, and (5) sustain momentum through a multi-quarter rollout that I wasn't managing day-to-day."*

---

### A — Action

**Step 1 — Quantify the cost:**

*"I spent 3 weeks pulling data from PagerDuty and our incident retrospective system. I built a dataset of 140 cross-service incidents from the previous 12 months and coded each by: how many distinct monitoring tools the incident involved, MTTR, and whether the root cause spanned team boundaries.*

*Finding: incidents involving 3+ monitoring contexts had a median MTTR of 4.8 hours. Incidents within a single monitoring context had a median MTTR of 52 minutes. The correlation was not subtle.*

*I wrote a 2-page 'State of Observability' document — not a proposal, just data — and shared it with all 12 engineering managers and the VP of Engineering. The document did not propose a solution. It ended with: 'I'd like to convene a working group to discuss options.' Three EMs responded within the hour. The VP responded within the day."*

**Step 2 — Convene, don't dictate:**

*"I formed an Observability Working Group with 8 volunteers — at least one from each of the 4 current monitoring stacks. I explicitly invited the most vocal critics of standardization (both of them) because I wanted their concerns on the table, not behind my back.*

*The working group met for 6 weeks. My role was facilitator, not advocate. I asked each representative to present their current setup's strengths and pain points. I shared the OpenTelemetry proposal in Week 3 as one option, along with two alternatives: a centralized Datadog mandate, and a custom correlation service that would translate between existing formats.*

*The custom correlation service was dismissed by the group quickly (too much maintenance burden). The Datadog mandate was favored by 5 of the 8 members but opposed by the Prometheus teams (they had already invested heavily in custom dashboards). OpenTelemetry — which let each team keep their existing backend while standardizing the instrumentation layer — built the broadest coalition.*

*I wrote up the working group recommendation in ADR format, listing the 3 options, the working group's reasoning, and the decision. All 8 members signed off. This gave me a document with cross-team authorship — not a Platform mandate, but a cross-team agreement."*

**Step 3 — Reduce adoption friction to near-zero:**

*"I spent 4 weeks building a shared instrumentation library that encapsulated the OpenTelemetry setup for our two primary languages (Java and Python). The library handled: SDK initialization, context propagation across our internal RPC framework, log correlation (injecting trace IDs into log lines), and export to each team's existing backend.*

*For a team already using Datadog, adopting OTel meant: add the library dependency, set 2 environment variables, remove 40 lines of Datadog SDK initialization code. Net change: teams spent less time on instrumentation setup than before.*

*I ran a 3-hour migration workshop with 2 representative teams. Both were fully instrumented and emitting correlated traces within the session. I published the recording and the workshop runbook.*

*I also created a migration tracker visible to all EMs — green/yellow/red per team, with the adoption criteria (distributed tracing enabled, trace IDs in logs, SLO dashboards using common metric names). Teams that finished early moved to green. Green teams got a shoutout in the weekly engineering newsletter. Small incentive, but it mattered for the competitive teams."*

**Step 4 — Handle the holdouts:**

*"3 of 12 teams were at 'yellow' status 4 months into the rollout. I held 1:1s with each EM to understand the blocker. Two were capacity-constrained — I arranged for 2 platform engineers to embed with each team for a week and do the migration alongside them. The third team's lead was philosophically opposed to centralized standards ('this is how it starts, next they tell us which IDE to use'). I heard him out, acknowledged the concern was real, and made the explicit commitment: OTel covers instrumentation only, and it's a standard, not a tool mandate. I asked what commitment he needed from me to move forward. He asked for a written guarantee that no additional standardization mandates would come from Platform without going through the working group. I agreed. He adopted OTel the following sprint."*

---

### R — Result

*"12-month outcome: all 12 teams on OpenTelemetry. Cross-service traces available in each team's existing backend with common trace IDs. For the first time, a single incident could be traced end-to-end across team boundaries in one tool.*

*Cross-service MTTR dropped from 4.2 hours median to 1.1 hours over the following 6 months — a 74% reduction. This was the primary metric I had committed to in the RFC.*

*Observability spend dropped by $280K/year — not because teams switched tools, but because OTel's sampling configuration allowed us to tune trace volume more precisely and reduce the per-event costs in Datadog and New Relic.*

*The working group format I used became the standard for cross-team technical decisions at [Company]. When we later needed to standardize on a secrets management approach and a feature flag framework, both initiatives used the same pattern: data-first, working group with cross-team authorship, low-friction adoption path. I was not involved in leading those — the EMs who were in my working group ran them independently.*

*The VP of Engineering cited the observability initiative in a company engineering all-hands as an example of 'how Platform should work: enabling teams, not mandating them.'"*

---

## Coaching Notes

| Dimension | PE-Level Signal | Mid-Level Signal |
|-----------|----------------|-----------------|
| **Starting point** | Quantified the cost with data before proposing the solution | Proposed the solution, then tried to justify it |
| **Coalition building** | Formed cross-team working group; included critics | Socialized with allies first; addressed critics later |
| **Proposal design** | OTel as instrumentation-only, preserving existing backends | "Everyone switch to Datadog" |
| **Adoption friction** | Built the library; running workshops; migration tracker | Published a doc and asked teams to read it |
| **Holdout management** | 1:1s, embedded engineers, and written commitments | Escalated to VP to mandate compliance |

---

## Common Follow-up Questions

**"What if the VP had just mandated the standard? Wouldn't that have been faster?"**
> "Faster compliance, yes. But the reason I deliberately didn't go that route is that mandated observability that isn't actually understood and used correctly is worse than fragmented observability — you end up with teams going through the motions of OTel while still relying on their own tool for real debugging. The working group process took 6 weeks longer but produced 12 teams that actually understood what they were doing and why. When the third-party tool we used for sampling later had an outage, teams knew enough to adjust their configuration independently, without coming to Platform."

**"How did you maintain momentum over a 12-month rollout when you weren't managing anyone?"**
> "Three mechanisms: (1) the public migration tracker made progress visible to EMs and VPs without me having to chase anyone — social accountability is more powerful than private reminders, (2) the working group had standing biweekly meetings where I reviewed progress and unblocked issues in real time, and (3) I made the 'done' state concrete enough that teams knew exactly what finishing looked like. Vague completion criteria are how long projects die quietly."

**"How do you handle a situation where you genuinely believe the technical decision is wrong?"**
> "If the working group had landed on a decision I thought was clearly inferior, I would have made that case directly in the group — not outside of it. If they still chose differently and I could articulate that the decision created a concrete risk (not just that I'd have chosen differently), I'd escalate to the VP with the full context, explain the risk, and let them decide. If the decision was suboptimal but not harmful, I'd implement the group's decision, document my dissent in the ADR, and revisit it at the 6-month review. Disagreeing and committing is a real skill — it means fully executing a decision you didn't choose, not just tolerating it."
