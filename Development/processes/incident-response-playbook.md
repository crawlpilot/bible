# Incident Response Playbook

**Category**: Engineering Operations · On-Call · Site Reliability
**Audience**: All engineers on rotation; escalation path for PE/Staff engineers
**Reference**: *Observability Engineering* (Majors/Fong-Jones/Miranda); Google SRE Book

> "Production is not the place to learn. MTTR beats root-cause-first. Restore service, then understand what happened."

---

## Incident Severity Framework

| Severity | User Impact | Response Time | Example |
|----------|------------|---------------|---------|
| **SEV-0** | Complete outage; all users; zero core functionality | Immediate; CEO-level comms | Checkout is completely down; auth unavailable for all users |
| **SEV-1** | Major degradation; >20% of users affected OR SLO error budget burning at >14.4× | < 5 min (auto-paged) | Payment error rate 5%; P99 checkout > 10s; entire region degraded |
| **SEV-2** | Partial degradation; <20% of users OR specific cohort | < 30 min (auto-paged) | Recommendations slow for mobile users; email notifications delayed |
| **SEV-3** | Minor; workaround available; no SLO impact | Business hours (ticketed) | Non-critical dashboard broken; deprecated endpoint still receiving calls |
| **SEV-4** | Cosmetic / informational | Next sprint | Typo in error message; outdated internal documentation |

**Severity determination decision tree**:
```
Is any user-facing functionality completely unavailable?
  Yes → SEV-0
  No ↓

Is SLO burn rate > 14.4× OR >20% of users impacted?
  Yes → SEV-1
  No ↓

Is a subset of users experiencing degraded functionality?
  Yes → SEV-2
  No ↓

Is there a bug or issue with a known workaround?
  Yes → SEV-3
  No → SEV-4
```

---

## Incident Roles

### Incident Commander (IC)

**Owns**: The incident process, not the investigation.

**Responsibilities**:
- Declare incident severity and open the incident channel
- Assign TL, Comms Lead, Scribe
- Drive the timeline — timeboxes on investigation, mitigation, escalation
- Make the call to escalate (up or out to other teams)
- Write and approve status page updates
- Declare resolution
- Schedule post-mortem

**Critical rule**: The IC does NOT investigate technically. The moment the IC starts debugging, coordination collapses. If you're the only person available, assign yourself as TL and find an IC.

### Technical Lead (TL)

**Owns**: The investigation and mitigation.

**Responsibilities**:
- Run hypothesis-driven investigation (scope → correlate → trace → hypothesize → test)
- Propose and execute mitigations
- Communicate findings to IC (concise status every 10 minutes minimum)
- Identify when additional SMEs are needed; request them through IC
- Own the technical post-mortem section

**Critical rule**: The TL does NOT write status updates or communicate to stakeholders — that context switch kills investigation focus.

### Comms Lead

**Owns**: All communication outside the incident channel.

**Responsibilities**:
- Write and post status page updates on IC's approval
- Update executive Slack channel every 15 minutes during SEV-0/1
- Respond to customer escalations with approved templated language
- Track questions from stakeholders; batch them to IC rather than interrupting TL

### Scribe

**Owns**: The real-time incident timeline.

**Responsibilities**:
- Record every significant action with UTC timestamp: who did what, what was the result
- Document hypotheses proposed and whether they were confirmed or ruled out
- Record all changes made to production (what, when, by whom, link to change)
- Document the mitigation that worked and when it was applied

**Why scribe matters**: Post-mortem reconstruction without a scribe is inaccurate and painful. Memory is unreliable under stress. The scribe doc is the source of truth for the post-mortem timeline.

---

## Phase 1: Triage (0–5 minutes)

**Goal**: Establish severity, open the incident, get the right people.

```
T+0: Alert fires / report received
  1. Acknowledge the alert in PagerDuty (stops escalation timer)
  2. Determine severity using the decision tree above
  3. Open incident Slack channel: #inc-YYYYMMDD-brief-description
     Example: #inc-20240115-checkout-errors
  4. Post the incident opener:

     @here SEV-[N] INCIDENT OPEN
     Summary: [one sentence - what is broken]
     User impact: [estimated scope]
     First symptom observed: [time] UTC
     IC: @[name]
     TL: @[name]
     Scribe: @[name]
     Bridge: [Zoom/Meet link]
     Status page: [link] - currently Investigating

  5. Post initial status page update (even if "investigating"):
     "We are investigating reports of [user-facing symptom]. More updates in 15 minutes."

  6. Notify:
     SEV-0/1: Post in #engineering-incidents, page EM/Director
     SEV-2: Post in #engineering-incidents
```

---

## Phase 2: Investigate (5–30 minutes)

**Goal**: Identify the blast radius and form a testable hypothesis.

### Scope First — Always

Before forming any hypothesis, establish the blast radius:

```
Questions to answer in the first 5 minutes of investigation:
□ Which users? (all vs cohort — e.g., mobile only, EU only, paid tier only)
□ Which endpoints? (all checkout vs /checkout/confirm only vs checkout + payment)
□ Which regions? (global vs us-east-1 only vs one AZ)
□ What is the symptom? (errors vs slow vs wrong data)
□ What percentage is affected? (1% vs 10% vs 100%)
□ When did it start? (exact timestamp from first alert or first trace)
```

Narrowing scope from "checkout is broken" to "payment confirmation is failing for Apple Pay users in EU" collapses the hypothesis space from thousands to a handful.

### Correlate with Changes — Always Before Deep Debug

```
First investigation step: What changed in the 30 minutes before the first symptom?

Check in this order:
  1. Deploy log: any service deploy in the window? → rollback candidate immediately
  2. Feature flags: any flag flipped? → turn off candidate immediately
  3. Config changes: any infra/config changes? (TF apply, k8s config, DB param)
  4. Cron jobs: any job that ran at the symptom time? (batch process, reindex, backup)
  5. Traffic pattern: any sudden spike or shape change? → capacity issue
  6. External dependencies: any upstream provider incident? (check status pages)

If you find a change that correlates with the symptom onset:
  → That is your primary hypothesis
  → Do NOT do 30 minutes of investigation before testing it
  → Test the hypothesis immediately: rollback the change or disable the flag
```

### Trace-First Debugging

After scoping and correlation, open distributed traces before touching any other tool:

```
Step 1: Find affected traces
  Query: error=true AND service=checkout AND timestamp > [incident start]
  Or: duration_ms > 5000 AND service=checkout (for latency incidents)

Step 2: Open the waterfall view
  → Immediately identifies which span is wide (slow) or red (error)
  → Identifies which service and which call is the bottleneck

Step 3: Compare with a healthy trace
  → Open a fast, successful trace from the same time period
  → Diff the two: which spans exist in one but not the other?
    Which spans are 10× longer in the slow trace?

Step 4: Read the structured event fields
  → What user_id, order_id, payment_method, feature flag values appear in failing traces?
  → Are failing traces clustered on a specific value? (all iOS users, all Stripe charges, all EU users)

Step 5: Form hypothesis from trace evidence
  "Hypothesis: Stripe API calls are timing out. Evidence: stripe_api_duration_ms = 2998ms
   (above our 2000ms timeout) in 94% of failing traces. Stripe calls are showing
   status=timeout in the span attributes. Stripe status page shows no incident."
```

### Investigation Anti-Patterns

| Anti-pattern | Why Wrong | Correct Approach |
|-------------|-----------|-----------------|
| "I need to understand root cause before mitigating" | Extends user impact; MTTR is the priority | Mitigate the known-correlated change; investigate root cause after |
| Opening a bash shell to a prod host as first step | Doesn't scale; misses cross-service view; leaves no audit trail | Traces first; structured logs second; SSH only if both fail |
| Changing multiple things at once to "see what helps" | Cannot attribute what fixed it; risks making things worse | One change at a time; observe for 2 minutes before next change |
| Investigating without narrating to IC | IC cannot coordinate without visibility into TL's progress | Narrate every hypothesis and its result to the incident channel |
| Running ad-hoc SQL on production databases | Risk of making incident worse; tables locked, added load | Read replicas only; prepared queries only; get approval from IC first |

---

## Phase 3: Mitigate (as fast as possible)

**Goal**: Restore service. Root cause can wait.

### Mitigation Hierarchy

Apply in order — fastest to implement first:

```
1. ROLLBACK (< 5 minutes if CI/CD pipeline is mature)
   When: a recent deploy correlates with the incident onset
   How:  trigger rollback in deployment system; monitor error rate recovery
   Risk: low — returns to last known-good state

2. FEATURE FLAG OFF (< 1 minute)
   When: the affected functionality is gated by a feature flag
   How:  toggle flag in feature flag system (LaunchDarkly, Statsig, etc.)
   Risk: low — users see old behavior instead of new

3. TRAFFIC SHIFT (< 5 minutes)
   When: issue is regional (one AZ or one DC is misbehaving)
   How:  update load balancer weights; shift traffic to healthy region
   Risk: low if target region has capacity; watch for overload

4. CIRCUIT BREAKER / GRACEFUL DEGRADATION (< 10 minutes)
   When: an upstream dependency (Stripe, Twilio, third-party API) is degraded
   How:  enable circuit breaker; serve cached/degraded response instead of failing
   Risk: users get degraded experience, not errors

5. SCALE UP (< 10 minutes for horizontal pod scaling)
   When: metrics show resource saturation (CPU > 90%, queue depth growing)
   How:  increase replica count or instance size
   Risk: low; watch for cascading if scaling triggers DB connection spike

6. CONFIG CHANGE (< 15 minutes)
   When: a configuration parameter (timeout, pool size, rate limit) is the cause
   How:  change config, roll out carefully
   Risk: medium; verify change is correct before applying

7. HOTFIX DEPLOY (30+ minutes — last resort)
   When: all faster mitigations are inapplicable or have failed
   How:  write fix, get expedited review, deploy with careful canary
   Risk: new code during an incident can worsen or introduce new issues
```

### Mitigation Execution Rules

```
□ Document the mitigation action in the incident channel BEFORE executing
  "I am initiating rollback of payment-service from v2.3.4 to v2.3.3 in us-east-1"

□ Monitor for 5 minutes after applying mitigation before declaring it successful
  Watch: error rate, latency P99, SLO burn rate

□ If mitigation succeeds: update status page; continue monitoring for 15 minutes
□ If mitigation fails: communicate clearly; move to next option; do NOT undo failed mitigation
  unless it actively made things worse

□ One change at a time — never two mitigations simultaneously
```

---

## Phase 4: Communicate

**Goal**: Maintain trust through consistent, factual updates.

### Status Page Cadence

```
T+5 min:    "We are investigating reports of [user-facing symptom]."
T+15 min:   "We have identified the issue and are working on a mitigation."
T+30 min:   "A mitigation is in place; we are monitoring for stability."
Resolution: "This incident has been resolved as of [time] UTC.
             Affected users: [scope]. Duration: [X] minutes.
             We will publish a post-mortem within 5 business days."
```

**Status page writing rules**:
- Never use technical jargon that users don't understand ("replication lag", "memtable flush")
- Focus on user impact, not system internals ("checkout is currently unavailable" not "payment-service pods are OOMing")
- Never speculate about root cause in external communications until confirmed
- Set a specific time for your next update — and keep it

### Internal Communication

```
SEV-0/1 internal cadence:
  Every 15 minutes: post status to #engineering-incidents
  Format:
    [TIME] UTC | SEV-[N] | [service]
    Status: [Investigating / Mitigating / Monitoring / Resolved]
    Current error rate: [X]%
    Budget burn rate: [X]×
    Current hypothesis: [one sentence]
    Next update in: 15 minutes

SEV-2 internal cadence:
  Every 30 minutes; same format
```

---

## Phase 5: Resolve and Hand-off

**Goal**: Confirm service is stable; set up post-incident tracking.

### Resolution Criteria (all must be true)

```
□ Error rate back within SLO (burn rate < 1× for at least 15 minutes)
□ Latency P99 back to pre-incident baseline
□ No active user complaints being escalated
□ Root cause understood OR active investigation assigned to a named owner
□ No open "we changed X and need to revert it if it doesn't hold" items
```

### Resolution Process

```
1. IC declares resolution in incident channel
2. Final status page update posted (resolution time, scope, duration, post-mortem ETA)
3. Executive stakeholder notification sent
4. Incident ticket created with:
   - Incident timeline doc link
   - SEV level
   - Duration
   - User impact
   - Post-mortem assigned (owner + due date: 5 business days)
5. Immediate action items logged (quick wins from investigation)
6. PagerDuty incident resolved
```

### Hand-off (if incident runs across on-call shifts)

```
Hand-off document (post in incident channel before leaving):
  Current status: [Resolved / Monitoring / Investigating / Mitigating]
  What was tried: [numbered list with outcomes]
  Current hypothesis: [one sentence]
  Next action: [specific, with owner]
  What to watch: [specific metrics, thresholds, links to dashboards]
  Who to escalate to: [name + contact]
  Outstanding risks: [anything that might cause recurrence]
```

---

## Post-Incident Actions (within 24 hours)

```
□ Immediate fixes deployed or ticketed (with owner + due date)
□ Monitoring gaps identified → create alert tickets
□ Runbook updated if it was missing or inaccurate
□ Post-mortem owner assigned; meeting scheduled within 5 business days
□ Incident metrics updated in incident tracking system (JIRA, Linear, etc.)
```

---

## Common Incident Scenarios — Quick Reference

### Error Rate Spike on Recent Deploy

```
Signal:      Error rate spiked at same time as deploy completed
Mitigation:  Rollback immediately — do not wait to understand why
Post-mitigation: Find the PR; identify the code change; write a proper fix
Root cause:  Always debug the old code in a branch, not in production
```

### External Dependency Degraded (Stripe, Twilio, SendGrid)

```
Signal:      Span showing external API call is slow/failing in traces
             Status page for vendor shows incident
Mitigation:  Enable circuit breaker → serve degraded experience
             "Payments temporarily unavailable; retry in 10 minutes"
Escalation:  Page vendor's enterprise support
Post-mitigation: Add vendor status page to alert runbook; improve fallback
```

### Database Connection Pool Exhausted

```
Signal:      Error: "too many connections"; DB connection count at max; query latency spikes
Mitigation:  1. Identify connection leaks (query pg_stat_activity for idle connections)
             2. Kill idle connections if safe (IC approval first)
             3. Increase pool size temporarily (config change, 5 min)
             4. Reduce pod count to reduce total connection demand
Post-mitigation: Audit connection pool configuration; add connection leak detection
```

### Kafka Consumer Lag Growing

```
Signal:      Consumer group lag metric growing; processing time increasing; SLI freshness degrading
Mitigation:  1. Check consumer CPU/memory (saturation before throughput drop)
             2. If CPU-bound: add consumer pods (< 5 min)
             3. If downstream slow: enable backpressure; alert on dependency
             4. If bug in consumer: rollback consumer
Post-mitigation: Set alert on lag rate of change, not just absolute lag
```

### Memory Leak / OOM

```
Signal:      Pod restarts increasing; memory usage trending up over hours/days; eventual OOM kill
Mitigation:  1. Restart affected pods to buy time (does NOT fix the leak)
             2. Enable horizontal scaling to reduce per-pod memory pressure
             3. Rollback if leak correlates with recent deploy
Root cause:  Profile heap dump (if language supports it); identify unclosed resources
Post-mitigation: Add memory trend alert (alert when memory grows >20% over 1h baseline)
```

---

## On-Call Hygiene

### Before Your On-Call Rotation Starts

```
□ Review the alert runbooks for the services you own — are they up to date?
□ Check that your PagerDuty escalation path is correctly configured
□ Know where the Grafana dashboards, trace queries, and log queries are for your services
□ Know the deployment rollback procedure for each service
□ Know who to escalate to for each service dependency
□ Test your alerting setup: fire a non-production test alert
```

### During On-Call

```
□ Keep your laptop within reach during primary hours
□ For SEV-2 and above: open a laptop, do not debug from phone
□ Respond to all pages within the acknowledgement window (typically 5 minutes)
□ If you cannot resolve within 15 minutes: escalate, do not solo
□ Document everything in the incident channel — future you will thank present you
□ After resolution: update the runbook with anything that was missing
```

### After On-Call

```
□ File an on-call report: alerts fired, actions taken, runbook gaps found
□ Turn low-signal alerts into tickets (alert fired but required no action → tune threshold)
□ Turn missing runbook sections into tickets
□ Flag toil to EM: manual interventions that happen weekly should be automated
```

---

## Principal Engineer On-Call Expectations

At PE level, you are the escalation path — you are paged when primary on-call cannot resolve. You are also expected to drive systemic improvements so that this class of incident does not recur.

**During escalation**:
- Arrive with your own context: read the incident channel from the beginning before speaking
- Ask: "What has been tried? What hypothesis are we on? What's the current blast radius?"
- Add value through: system-level context, creative hypotheses, authoritative decisions on risky mitigations
- Do NOT invalidate the on-call engineer's work; build on it

**After escalation involvement**:
- Own the post-mortem for systemic issues (the thing that made this hard to debug / prevented faster mitigation)
- Drive the architectural changes that prevent recurrence (not the bug fix — the systemic gap)
- Present findings at reliability review meetings; track action item completion at PE scope

**Reliability investment**:
- PE-level reliability work: eliminate classes of incidents, not individual incidents
- "Every time X, we have an incident" → design the system so X cannot cause an incident
- Propose automation: auto-rollback, auto-scaling, circuit breakers, canary analysis
- Track MTTR, MTTD (Mean Time to Detect), alert signal:noise ratio as engineering metrics
