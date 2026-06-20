# On-Call Rotation Design and Management

**Category**: Engineering Operations · Team Health · SRE Practices  
**Audience**: Principal / Staff Engineers designing on-call programs and driving reliability culture  
**Related**: [Incident Response Playbook](incident-response-playbook.md) · [Observability & CI](observability-incident-continuous-improvement.md)

> "On-call is not a punishment. It is the mechanism by which engineers are invested in the reliability of what they build. A healthy on-call rotation is a signal that the system is well-designed and the team is operating well. A brutal on-call rotation is a signal that something is broken — in the system, the alerts, or the team's reliability practices."

---

## On-Call Program Goals

A well-designed on-call program achieves four goals simultaneously:

1. **Service reliability**: Incidents are detected and responded to within SLO-defined timelines
2. **Engineer wellbeing**: On-call burden is sustainable; engineers are not burning out
3. **System improvement**: Every incident drives a learning cycle that makes the next incident less likely or less severe
4. **Team scaling**: On-call coverage scales with the organization without linear headcount growth

If any one of these is failing, the program has a design problem.

---

## On-Call Coverage Models

### Model 1: Follow-the-Sun (Distributed)

**Design**: Separate on-call shifts for each major timezone region. Engineers only carry on-call during business hours in their region.

```
Americas team: 8am–8pm Pacific (UTC-7)
EMEA team:     8am–8pm CET     (UTC+1)
APAC team:     8am–8pm SGT     (UTC+8)
```

**Pros**: No sleep-hour pages for any engineer; maximum alertness during on-call  
**Cons**: Requires global team; handoff overhead; may not be feasible for small teams  
**Use when**: Team has engineers across 3+ timezones; product has global user base with uniform demand

### Model 2: Primary + Secondary (Most Common)

**Design**: One primary on-call at all times (24/7), backed by a secondary who escalates to if primary doesn't respond within N minutes.

```
Primary: Pages 24/7 within the shift (typically 1 week)
Secondary: Pages only when primary doesn't acknowledge within 5 minutes
Escalation: EM / PE / Staff if neither responds within 10 minutes
```

**Pros**: Simple; scales to small teams; clear accountability  
**Cons**: Sleep-hour pages possible; burnout risk for small rotations  
**Sustainable rotation size**: Minimum 6 engineers per rotation (1 week on, 5 weeks off); 8+ is comfortable

### Model 3: Business Hours + PagerDuty Escalation

**Design**: Active on-call only during business hours. Off-hours incidents escalate to a standby engineer who is compensated for availability.

```
Business hours (9am–6pm local): Normal on-call rotation
Off-hours: Escalation-only path with designated standby engineer
            Standby compensated with on-call pay; not paged unless SEV-1
```

**Pros**: Protects engineer sleep; appropriate for services with low off-hours SEV-1 risk  
**Cons**: Response time slower off-hours; may not meet SLAs for high-criticality services  
**Use when**: Service has minimal user activity off-hours; business impact of off-hours incidents is low

### Model 4: Tiered Coverage (Large Organizations)

**Design**: L1 (front-line) handles well-understood incidents from runbook. L2 (senior) handles complex incidents. L3 (PE/Staff) handles platform-level incidents.

```
L1 (primary on-call): Can handle 70% of incidents from runbook alone
L2 (escalation): Handles complex investigations; paged by L1 when runbook is insufficient
L3 (PE/Staff escalation): Handles platform failures, data loss, security incidents
```

**Pros**: Scales to large fleets; protects senior engineers from routine incidents  
**Cons**: Requires investment in runbook quality and L1 training; handoff latency  
**Use when**: Large service portfolio; many services with similar failure patterns; large team

---

## Rotation Design

### Sizing the Rotation

**Minimum viable rotation** (to avoid burnout):

| On-Call Intensity | Minimum Rotation Size | Reasoning |
|-----------------|---------------------|-----------|
| Low (< 1 page/shift) | 4 engineers | 1 week on, 3 weeks off |
| Medium (1-3 pages/shift) | 6-8 engineers | 1 week on, 5-7 weeks off |
| High (3-5 pages/shift) | 8-10 engineers | More recovery time needed |
| Very high (> 5 pages/shift) | Fix the alerts and system — rotation size alone doesn't solve this |

**Rule of thumb**: If on-call duty means a significant chance of being paged at night more than once per week, the rotation is too small or the system is too noisy.

### Shift Scheduling

**Standard: 1-week shifts**
- Simple calendar; engineers can plan around their week
- Enough time to build context within the shift
- Handoff happens once per week

**Alternative: 12-hour shifts (for global teams)**
- Day shift engineer: 8am–8pm local time
- Night shift: covered by another timezone
- Requires strong handoff documentation

**Shift handoff protocol**:
```
Outgoing on-call documents (sent 30 min before shift end):
1. Active incidents or ongoing investigations (status, current hypothesis, next step)
2. Recent alerts that triggered (what happened, what was done, is it resolved?)
3. System changes deployed this week that are still being monitored
4. Known fragile areas right now ("Redis is at 85% memory; watch for eviction spike")
5. Anything unusual observed that doesn't need immediate action but is worth watching
```

### Rotation Schedule Anti-Patterns

| Anti-Pattern | Impact | Fix |
|-------------|--------|-----|
| Engineer on-call same week as major deployment they own | Cognitive overload | No-deploy week for on-call engineer (or separate ownership) |
| On-call during planned leave | Engineer works during vacation | Swap enforcement; PagerDuty vacation blocking |
| Back-to-back shifts for one engineer | Burnout | Minimum 2-week gap between shifts |
| No escalation path | Incident stuck with one engineer | Always define: primary → secondary → EM/PE |
| New hire on-call alone in first 90 days | Over their head; poor experience | Shadow shift first; buddy on-call second; solo after 90 days |

---

## Alert Design for On-Call Health

On-call health is a direct function of alert quality. Most on-call burnout comes from bad alerts, not bad systems.

### Alert Quality Criteria (Every Alert Must Pass)

```
1. Is it actionable?
   If an engineer gets this alert at 3am, is there an action they can take that makes things better?
   If no: remove the alert; monitor async.

2. Does it have a runbook?
   The runbook should be linked in the alert body. Not: "go check the wiki."

3. Is it measuring user impact?
   Alert fires when users are suffering. Not when a metric is "unusual."

4. Is it low-noise?
   Does it fire < 2× per on-call week for normal operations?

5. Is there a single owner?
   One team. One rotation. No ambiguity about who responds.
```

### Alert Tuning Process

Run a quarterly alert audit:

```
For each alert that fired in the last quarter:
  □ Did a human take an action as a result? (If no: remove or auto-remediate)
  □ Did the alert fire during the right time window? (Too early = false alarm; too late = useless)
  □ Did the alert correlate with user impact? (If alert fired but users were fine: too sensitive)
  □ Was the runbook used? Did it help? (If no: update runbook)

Target metrics:
  - Pages per on-call shift (12h): ≤ 2 actionable
  - Alert signal:noise ratio: > 80% of pages require human action
  - Off-hours pages: ≤ 1 per week per engineer
  - Alert → runbook open rate: > 80%
```

---

## On-Call Compensation and Culture

### Compensation Models

| Model | How It Works | When to Use |
|-------|-------------|------------|
| **On-call pay** | Per-shift stipend regardless of pages | Fair; rewards availability not just incidents |
| **Page-based pay** | Compensation per incident response | Perverse incentive (don't want more incidents) |
| **Time off in lieu** | Hour-for-hour on-call time converted to additional PTO | Simple; valued by engineers |
| **Rotation reduction** | Reduce on-call frequency for engineers who invest in reliability | Aligns incentives correctly |

**Principle**: Compensation should make on-call feel worth it, not offset burnout. If engineers feel they need to be compensated for suffering, the system needs to be fixed, not the compensation model.

### Building On-Call Culture

**What good on-call culture looks like**:
- Engineers treat on-call as investment in the quality of what they build, not a tax for being on the team
- Incidents are learning opportunities, not reasons for blame
- System improvements from incidents are visible and celebrated
- On-call burden is transparently tracked and actively reduced over time
- New engineers are onboarded gradually; nobody is thrown in alone

**What principal engineers do to build this culture**:
1. Lead by example: write post-mortems that are systems-focused, not blame-focused
2. Make reliability work visible in sprint planning: "20% of this sprint is reliability investment"
3. Track and celebrate alert reduction: "We reduced pages per shift from 5 to 1.5 this quarter"
4. Escalate toil to EM when it's unsustainable: on-call health is a team-level problem, not an individual problem
5. Invest in automation: every manual intervention is a toil item to automate

---

## On-Call Onboarding Program

### Shadow → Buddy → Solo Progression

**Phase 1: Shadow (weeks 1-4)**
```
□ New engineer shadows an experienced on-call engineer for one full shift
□ Observes all alert responses without taking action
□ Reviews incident channel from past incidents
□ Reads all runbooks for services they'll own
□ Asks: "What would I do if this alert fired?" (gets feedback in real-time)
```

**Phase 2: Buddy On-Call (weeks 5-8)**
```
□ New engineer is the primary responder with an experienced engineer as backup
□ Handles alerts independently but with backup available immediately (not escalation path — direct support)
□ Writes post-mortem for any incident they handled (with review)
□ Creates or updates runbooks for any gap discovered
```

**Phase 3: Solo On-Call (week 9+)**
```
□ Standard escalation path only (not buddy support)
□ Full incident command capability
□ Post-mortem ownership
□ Expected to identify and drive reliability improvements
```

**Graduation criteria for solo**:
- Has handled at least 3 incidents during buddy phase
- All runbooks for owned services reviewed and updated
- Can explain failure modes and recovery procedures for each service
- Comfortable with the diagnostic toolchain (traces, logs, metrics)

---

## On-Call Metrics and Reporting

### Track These Per Engineer Per Rotation

```
On-Call Health Report (shared with team monthly):
  Total pages this quarter: [N]
  Pages per shift (avg): [N]
  Sleep-hour pages (10pm–7am): [N]
  Alert → action required rate: [N]%
  Mean time to acknowledge: [Nm]
  Total incident time: [Nh]
  Runbook gaps found: [N]
  Alerts tuned/removed: [N]
```

**Trend to drive toward**:

| Metric | Current | Target | Priority |
|--------|---------|--------|----------|
| Pages per 12h shift | 4.2 | ≤ 2 | P1 |
| Sleep-hour pages per engineer per week | 2.1 | ≤ 0.5 | P1 |
| % alerts requiring no action | 30% | < 10% | P2 |
| MTTA (mean time to acknowledge) | 8 min | < 5 min | P3 |

**If pages per shift > 4**: Mandatory reliability sprint; no new features until under 2  
**If sleep-hour pages > 1/week/engineer**: Engineering manager escalation; this is burnout territory

---

## Escalation Design

### Escalation Matrix

```
Level | Who | When | SLA
------|-----|------|----
L1 Primary | On-call engineer | Alert fires | Acknowledge: 5 min
L2 Secondary | Backup on-call | L1 no response in 5 min | Acknowledge: 5 min
L3 EM | Engineering Manager | SEV-0/1 declared OR L2 no response | Available: 10 min
L4 PE/Staff | Principal Engineer | Platform-level / data loss / security | Available: 15 min
L5 Director | Engineering Director | SEV-0 > 30 min unresolved; customer data loss | Notified: 30 min
```

**Escalation rules**:
- Escalation is not failure. Escalating early saves MTTR.
- Never feel bad for escalating. The cost of not escalating (longer incident) always exceeds the cost of escalating.
- Escalate when: you've been stuck on the same hypothesis for 15 minutes; you don't understand the system well enough to form a hypothesis; the blast radius is growing and you need more capacity.

---

## FAANG Interview Framing

### "How do you design a sustainable on-call program?"

> "I design on-call around three constraints: the system must be debuggable from signals alone (no SSH required), alerts must be actionable (every page has a runbook and requires human action), and the rotation must be large enough that no engineer is paged during off-hours more than once per week on average. In practice, this means investing heavily in observability and runbooks before the rotation goes live, and then running monthly alert audits to remove or tune anything that's creating noise. The leading indicator of rotation health is pages per shift — I target ≤ 2 actionable pages per 12-hour shift. Above that, we have a system quality problem, not a headcount problem. At PE level, I also track whether on-call incidents are driving lasting improvements — if the same incident type keeps recurring, that's a sign the post-mortem action items aren't being completed or the root cause was misidentified."

### "What do you do when on-call is burning out your team?"

> "Burnout means the on-call burden is unsustainable, and the root cause is almost always one of three things: the alert volume is too high (fix the alerts), the incidents are too complex (fix the runbooks and the system), or the rotation is too small (grow the rotation or reduce scope). I start by measuring: how many pages per shift, how many require action, how many happen off-hours. Then I identify the top 3 noisiest alert categories and either automate the response or remove the alert entirely. I track this as an engineering metric — we report on-call health monthly at team level. The goal is to make on-call feel like occasional professional engagement, not constant crisis response. If the system fundamentally can't be made reliable enough for sustainable on-call, that's an architecture investment conversation with leadership."
