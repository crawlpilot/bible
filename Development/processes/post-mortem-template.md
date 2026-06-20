# Post-Mortem Template — Principal Engineer Standard

**Category**: Engineering Operations · Incident Documentation · Reliability
**Reference**: *Observability Engineering* (Majors/Fong-Jones/Miranda); Google SRE Book Chapter 15

> "The post-mortem is not a blame session. It is a structured retrospective that asks: what does this incident teach us about our system, our processes, and our assumptions? The system is the defendant — not the engineer."

---

## When to Write a Post-Mortem

| Condition | Post-Mortem Required? |
|-----------|----------------------|
| SEV-0 or SEV-1 incident | Yes — always, within 5 business days |
| SEV-2 incident | Yes — within 10 business days |
| Near-miss (almost caused user impact) | Yes — these are the highest-value learning opportunities |
| SEV-3 or lower | Optional; use judgment based on novelty or systemic concern |
| Repeated SEV-3 of same type (3+) | Yes — treat as a systemic reliability gap |

**Who writes it**: The Incident Commander (IC) owns the post-mortem and is accountable for its completion. The Technical Lead (TL) writes the root cause and contributing factors sections. Both review and approve before publishing.

---

## The Blameless Principle — Before You Write

Read this before writing or reviewing any post-mortem:

**Blameless means**: Assume engineers acted with the best intentions, with the information they had at the time, within the system they inherited. If a human action caused damage, the system allowed that action to cause damage — fix the system.

**Blameless does NOT mean**: Consequences-free. Engineers are accountable for post-mortem quality, follow-through on action items, and changing their behavior based on learnings.

**Red flags in a post-mortem draft** (ask the author to revise):
- "The engineer forgot to..." → "Our process does not require verification of..."
- "The developer should have known..." → "Our documentation did not make clear that..."
- "This was a careless mistake" → "Our system allowed this operation without validation"
- Naming individuals as causes rather than as actors in a systemic context

---

## Post-Mortem Template

Copy and fill this out. Sections marked **(required)** must be completed for all SEV-0/1 post-mortems.

---

```markdown
# Post-Mortem: [Incident Title — be specific, e.g. "Checkout Payment Failures due to Stripe Timeout Regression"]

**Incident ID**: INC-YYYY-NNNN
**Date of incident**: YYYY-MM-DD
**Severity**: SEV-[0/1/2]
**Duration**: HH:MM UTC to HH:MM UTC ([X] hours [Y] minutes)
**Post-mortem author(s)**: [IC name], [TL name]
**Post-mortem reviewer(s)**: [EM name], [PE/Staff name]
**Status**: Draft / In Review / Approved
**Published**: YYYY-MM-DD

---

## Impact (required)

**User impact**:
- [N users] affected, or [N%] of [user segment]
- [Specific functionality] was [unavailable / degraded / incorrect] for [duration]
- [Specific user experience]: e.g., "Users received HTTP 504 errors when attempting to complete checkout"

**Revenue / business impact**:
- Estimated [revenue/GMV] at risk: $[X] (based on [avg revenue/min × downtime minutes])
- Customer escalations received: [N]
- Refunds or credits issued: [N / $X]

**SLO impact**:
- [SLO name]: burned [X.X]% of [30-day] error budget
  - Budget before incident: [X]% remaining
  - Budget after incident: [Y]% remaining
- Burn rate at peak: [X]× (threshold for page: 14.4×)

**External communication**:
- Status page updated: [Yes / No]; first update at T+[N] minutes
- Customer-facing status page URL: [link]

---

## Timeline (required)

All times in UTC. Be precise and factual — this is not a narrative, it is a log.

| Time (UTC) | Event | Actor |
|-----------|-------|-------|
| HH:MM | [what happened — factual, non-judgmental] | [system / person] |
| HH:MM | Alert fired: [alert name] — [metric value] | PagerDuty |
| HH:MM | On-call engineer [name] acknowledged alert | [name] |
| HH:MM | Incident channel #inc-[name] opened; IC and TL assigned | [IC name] |
| HH:MM | First status page update posted | [comms lead] |
| HH:MM | TL identified [finding] by [method — e.g., "examining traces in Honeycomb"] | [TL name] |
| HH:MM | Hypothesis formed: [one sentence hypothesis] | [TL name] |
| HH:MM | [Mitigation action] initiated — e.g., "Rollback of payment-service v2.3.4 to v2.3.3 initiated" | [name] |
| HH:MM | Rollback complete; error rate returning to baseline | system |
| HH:MM | Error rate at [X]%; SLO burn rate [X]× (below page threshold) | monitoring |
| HH:MM | 15-minute stability window started | [IC name] |
| HH:MM | Incident resolved; status page updated | [IC name] |

**Detection gap**: First user impact at [T] UTC; first alert at [T+N] minutes UTC.
  → [Acceptable / Needs improvement — if >5 minutes, explain why and add action item]

**Mitigation gap**: Incident opened at [T]; mitigation applied at [T+N] minutes.
  → [Fast (< 15 min) / Acceptable (< 30 min) / Slow (> 30 min — add action item)]

---

## Root Cause (required)

Write one precise paragraph. The root cause is the single change or condition that, if different, would have prevented the incident.

**Template**: "[What changed or failed] caused [what broke], because [the mechanism]. The gap that allowed this to reach production was [the missing test / review / safeguard]."

**Example**:
> payment-service v2.3.4 introduced a Stripe API timeout of 500ms (changed from the previous 3000ms) in PR #4521. Stripe's normal P99 response latency during EU business hours is 800–1200ms, causing all EU payment requests to timeout. The change was intended to fail fast on Stripe slowness, but the timeout value was not validated against Stripe's actual latency profile. The CI/CD pipeline did not test against a realistic Stripe latency simulation; the staging environment uses a local Stripe mock with sub-10ms response times.

**Root cause**: [Your paragraph here]

**Is this root cause a recurrence?**
- First occurrence: [Yes / No]
- If No: previous incident: [INC-YYYY-NNNN]; previous action items that should have prevented recurrence: [list]
  → [Were those action items completed? If not, why not?]

---

## Contributing Factors (required)

Systemic gaps that made the incident worse or harder to detect. Each factor should map to an action item.

- [ ] **Detection gap**: [First alert fired at T+8 minutes; users were impacted from T+0 — describe why]
- [ ] **Missing test coverage**: [Staging environment did not simulate realistic Stripe latency]
- [ ] **Runbook gap**: [Runbook for `checkout_error_rate_high` did not include Stripe timeout as a scenario]
- [ ] **Review gap**: [PR reviewer approved timeout change without verifying against Stripe P99 baseline]
- [ ] **Rollback delay**: [Rollback took 12 minutes because staging canary verification is required — was appropriate but slowed MTTR]
- [ ] **Communication gap**: [First status page update was at T+22 minutes, not T+5 target — describe why]

---

## Action Items (required)

Every action item must be: specific (what exactly), owned (one name), and dated (concrete deadline).

| # | Action | Owner | Due Date | Priority | Status |
|---|--------|-------|----------|----------|--------|
| 1 | Add Stripe latency simulation (P95=400ms, P99=1200ms) to staging integration test suite | @alice | YYYY-MM-DD | P1 | Open |
| 2 | Add config validation for Stripe timeout: assert timeout > (Stripe P99 latency + 200ms buffer) | @bob | YYYY-MM-DD | P1 | Open |
| 3 | Add Stripe-specific error scenario to checkout runbook with pre-built trace query | @charlie | YYYY-MM-DD | P2 | Open |
| 4 | Implement SLO-based auto-rollback: if error rate > 2% within 5 min of deploy, trigger automatic rollback | @alice | YYYY-MM-DD | P2 | Open |
| 5 | Add alert for Stripe P99 latency > 800ms (early warning before our timeout threshold is hit) | @bob | YYYY-MM-DD | P3 | Open |

**Action item quality check** (before publishing):
- [ ] Each action is specific enough that completion is unambiguous
- [ ] Each action has exactly one named owner (not "team X" or "we")
- [ ] Each action has a concrete due date
- [ ] P1 items address the root cause or critical contributing factors
- [ ] At least one action addresses the detection gap if MTTD was > 5 minutes
- [ ] No action is "be more careful" or "improve code quality" — these are not actionable

---

## What Went Well (required)

Celebrate effective responses — this creates positive feedback for future incidents.

- **Fast rollback**: Rollback of payment-service completed in 3 minutes — investment in deployment pipeline maturity is paying off
- **Trace-first debugging**: TL identified the slow Stripe span within 2 minutes of opening Honeycomb — distributed tracing is effective for this class of issue
- **IC/TL separation**: Clear role separation prevented the coordination collapse that happened in the previous incident
- **Blameless tone**: PR author proactively shared context about the timeout change without being asked — psychological safety is working
- **On-call response**: Engineer acknowledged within 90 seconds; incident channel open within 5 minutes

---

## What Could Have Gone Better

- **Status page delay**: First external update was at T+22 minutes against our T+5 target. Comms Lead was waiting for IC to draft the language rather than using the template.
- **Hypothesis testing delay**: TL spent 15 minutes investigating the database before checking traces. Trace-first should be the instinct, not the afterthought.
- **Missing runbook scenario**: Runbook did not include Stripe timeout as a cause, requiring manual investigation that could have been pre-scripted.

---

## Lessons Learned (required)

2–3 generalizable insights. These should be shareable with engineers who were not involved.

1. **External API timeout values must be validated against the vendor's actual P99 latency baseline**. "Fail fast" configurations are beneficial — but the threshold must be set with knowledge of the dependency's real-world performance, not an arbitrary number.

2. **Trace-first debugging saves 10–15 minutes in latency incidents**. The Stripe span was the root cause signal, visible within 30 seconds of opening Honeycomb. Grep-first or dashboard-first approaches would have taken much longer.

3. **Status page templates must be pre-approved and require no new content for the first two updates**. The T+5 update should be formulaic: "We are investigating [X]. Next update in 15 minutes." No drafting required — just fill the template.

---

## Long-term Reliability Investment (optional, required for PE-authored post-mortems)

This section identifies the architectural or process gap that this incident class reveals — and the investment required to eliminate it.

**Pattern**: "Every time we change a timeout or rate limit for an external API, we risk this class of incident because [mechanism]. The architectural fix is [what] which [prevents the mechanism]. Estimated effort: [M/L/XL]. Priority: [High/Medium/Low]."

**Example**:
> This is the third incident caused by a misconfigured external API timeout in 18 months (INC-2023-0421, INC-2024-0087, INC-2024-0115). The pattern: an engineer changes a timeout to a value that seems reasonable but exceeds the vendor's actual latency, causing widespread failures. The root cause is that we have no mechanism to validate that timeout configurations are compatible with observed vendor latency. The architectural fix is a timeout policy service that: (1) continuously measures P99 latency for each external API, (2) enforces that configured timeouts are > (measured P99 + 20% buffer) via deploy-time validation. Estimated effort: L (3–4 weeks). Priority: High — we are statistically due for another incident within 6 months at the current rate.

---

## Appendix

### Useful Links
- Incident channel: [Slack link]
- Incident timeline doc (scribe notes): [Google Doc or Notion link]
- Grafana SLO dashboard (incident period): [link with time range]
- Relevant traces (Honeycomb / Jaeger query): [link]
- Deploy log (payment-service v2.3.4): [link]
- PR #4521 (the causal change): [link]
- Stripe status page (incident period): [link]
- Previous related incidents: [INC-YYYY-NNNN links]

### Metrics at Incident Peak

| Metric | Pre-incident baseline | Peak during incident | Post-mitigation |
|--------|----------------------|---------------------|-----------------|
| checkout error rate | 0.03% | 6.8% | 0.02% |
| checkout P99 latency | 340ms | 3,100ms | 280ms |
| SLO burn rate | 0.3× | 68× | 0.2× |
| Stripe API P99 (via traces) | 350ms | 2,998ms | 340ms |

```

---

## Post-Mortem Review Checklist

Before publishing, the reviewer (EM or PE) should confirm:

```
Content quality:
□ Timeline is factual and complete — a reader who was not present can reconstruct events
□ Root cause is a single precise statement, not a list of failures
□ Root cause identifies the mechanism ("because X caused Y"), not just what failed
□ Contributing factors each map to a specific action item
□ Action items are specific, owned, and dated — none are vague
□ "What went well" section is genuine — not performative
□ Lessons learned are generalizable — not just "this specific thing won't happen again"

Blameless check:
□ No individual is named as a cause — only as an actor in a systemic context
□ Language does not imply carelessness, negligence, or "should have known"
□ Post-mortem would not make the involved engineer feel targeted if they read it

Process check:
□ Post-mortem is published within 5 business days of incident (10 for SEV-2)
□ Action items have been entered into the team's tracking system
□ P1 action items have owners who have acknowledged and accepted them
□ Meeting scheduled to review action item progress in 30 days
```

---

## Post-Mortem Archive and Learning Culture

**Searchable archive**: All post-mortems should be indexed in a searchable wiki (Confluence, Notion, or equivalent). Engineers should be able to search by: service, incident type, root cause category, contributing factor.

**Recurring patterns**: At quarterly reliability review, identify incident themes:
- "3 incidents caused by timeout misconfigurations" → architectural fix needed
- "5 incidents detected first by customer reports, not alerts" → monitoring gap
- "4 incidents whose P1 action items were never completed" → process gap

**Sharing**: Significant post-mortems should be shared beyond the team — across engineering, at all-hands if PE-level scope. The sharing of learning is the point. Hoarding post-mortems within one team is a reliability anti-pattern.

**Staff/PE-level post-mortem**:
At PE level, your post-mortems are read by VPs and CTOs. They should demonstrate:
- Systems-level root cause analysis (not just "there was a bug")
- Identification of architectural gaps (not just process gaps)
- Action items that close entire incident classes (not just prevent recurrence of this specific incident)
- Long-term reliability investment framing — what does this incident reveal about our system's maturity?
