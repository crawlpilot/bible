# Release Gates & SLO-Based Progressive Delivery

## The Core Problem

Manual deployment approval processes don't scale. At 50+ deploys/day across 200 services, you can't have an on-call engineer manually approve each one. But you also can't blindly auto-promote — a broken deploy needs to be caught before it reaches 100% traffic.

**The solution**: automated release gates that enforce service-level objectives as the acceptance criterion for promotion. Humans define the policy; the system executes it.

---

## SLI / SLO / SLA — Quick Reference

| Term | Definition | Example |
|------|-----------|---------|
| **SLI** (Service Level Indicator) | Measurement of service behavior | p99 latency, error rate, availability |
| **SLO** (Service Level Objective) | Internal target for an SLI | p99 latency < 200ms over 30 days, 99.9% availability |
| **SLA** (Service Level Agreement) | External contractual commitment | 99.9% uptime, or credits apply |
| **Error Budget** | Allowed failures before SLO violation | 43.8 min/month downtime for 99.9% SLO |

**Relationship**: SLI is what you measure. SLO is what you target. SLA is what you promise and are accountable for externally.

---

## Error Budget as a Deployment Gate

**Core idea** (from Google SRE): if your error budget is healthy, deploy freely. If it's burning fast, slow down or stop.

```
Error Budget = 1 - SLO target
Example: 99.9% SLO → 0.1% error budget = 43.8 min/month

Budget burn rate > 1× → consuming budget at expected rate
Budget burn rate > 2× → consuming budget 2× faster than expected → alert
Budget burn rate > 14× → 1-hour window would burn 1 month budget → page immediately
```

**Deployment gate logic**:
```
if error_budget_remaining < 5%:
    block_deployments()
    notify("Error budget nearly exhausted — no new deploys until budget recovers")
    
if error_budget_burn_rate > 5× over last 1 hour:
    block_deployments()
    escalate_to_oncall()
```

This is the Google SRE model. Error budget decisions are made by the team, not an approval committee.

---

## Release Gate Architecture

```
Build → [GATE 1] → Staging → [GATE 2] → Canary → [GATE 3] → Production

GATE 1: Unit test pass, lint pass, build success, SAST pass
GATE 2: Integration tests pass, contract tests pass, perf regression check
GATE 3: Canary SLO analysis — compare canary vs. baseline for N minutes
```

### Gate Types

**Hard gates** — block promotion entirely if failed:
- Test suite failure (any failure)
- Critical SAST finding (OWASP Top 10)
- Artifact signature invalid
- Error budget exhausted (≤ 5% remaining)

**Soft gates** — alert + require human approval to proceed:
- Performance regression > 10% vs. baseline
- New high-severity security finding
- Dependency vulnerability scan (new CVE)

**Automated progressive gates** (canary analysis):
- Success criteria must be defined before deploy starts
- System compares metrics: canary vs. control (same % of baseline traffic)
- Auto-promote if score ≥ threshold; auto-rollback if score ≤ fail threshold; human gate in between

---

## Canary Gate: Metric Analysis in Detail

Netflix's Kayenta and Spinnaker popularized this pattern. The idea:

```
Deploy canary at 5% of traffic.
Run for 30 minutes.
Compare these metrics between canary and control (baseline v1):

  error_rate         → canary 0.12%, baseline 0.10% → delta = +20% relative
  p99_latency_ms     → canary 185ms, baseline 180ms → delta = +2.7%
  cpu_utilization    → canary 42%, baseline 40%     → delta = +5%
  checkout_success   → canary 97.2%, baseline 97.1% → delta = +0.1%

Canary score = weighted average of per-metric pass rates
  error_rate weight 40%, p99 weight 30%, business KPI weight 30%
  
score = 0.4*(100-20) + 0.3*(100-2.7) + 0.3*(100+0.1)
      = 32 + 29.2 + 30.03 = 91.2 → PASS (threshold = 80)
```

**How to define success criteria**:
- Measure baseline variance before writing thresholds (p99 latency has natural ±5% variance)
- Set thresholds looser than variance to avoid false failures
- Weight business KPIs heavily — a canary with excellent latency but worse checkout rate should fail
- Start with human-tuned thresholds, iterate with data

---

## SLO Definitions for Common Services

### API Gateway / Frontend Service
```yaml
slo:
  availability:
    target: 99.95%
    window: 30d
    sli: sum(http_requests_total{status!~"5.."}) / sum(http_requests_total)
  
  latency:
    target: 95%   # 95% of requests
    threshold: 200ms
    window: 30d
    sli: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
```

### Asynchronous Worker / Queue Consumer
```yaml
slo:
  processing_freshness:
    target: 99.9%
    definition: 99.9% of messages processed within 60 seconds of enqueue
    
  processing_success:
    target: 99.5%
    definition: 99.5% of messages processed without error (DLQ rate < 0.5%)
```

### Batch Job
```yaml
slo:
  completion:
    target: 99%
    definition: daily job completes before 06:00 UTC, 99% of days
    
  correctness:
    target: 99.9%
    definition: output record count within ±0.1% of expected (data quality gate)
```

---

## Progressive Delivery: Traffic Ramp Schedule

```
Stage 0:  Internal testing   → canary flag on for employees only
Stage 1:  Shadow             → 0% of user traffic, 100% shadow (no user impact)
Stage 2:  5% canary          → 5 minutes, automated analysis
Stage 3:  25% canary         → 10 minutes, automated analysis
Stage 4:  50% canary         → 15 minutes, automated analysis
Stage 5:  100% rollout       → full traffic, continue monitoring for 1 hour
Stage 6:  Stabilization      → old pods decommissioned, rollback window closed
```

Ramp can be time-based (advance every N minutes) or event-based (advance when metrics pass).

### Risk-based ramp adjustment

Not all services need the same ramp:
- **Low risk** (internal tool, < 1000 users): skip canary, rolling update
- **Medium risk** (customer-facing feature, existing code path): 5% → 100% over 30 min
- **High risk** (payment, auth, new system): shadow → 5% → 25% → 100%, human gate at each stage
- **Emergency hotfix**: expedited ramp with heightened monitoring, skip shadow

---

## Runbook: Release Gate Failure

### Scenario: Canary gate fails due to elevated error rate

```
1. AUTOMATED: traffic routed back to 0% canary, 100% v1
2. AUTOMATED: PagerDuty alert fired to on-call
3. ON-CALL: confirm rollback is stable (verify error rate returned to baseline)
4. INVESTIGATION:
   a. Compare canary logs vs. baseline in same time window
   b. Check if new code path was exercised (feature flag coverage)
   c. Check if error is in canary service or downstream dependency
   d. Check deployment diff for risky changes
5. FIX: patch the code, create new artifact
6. RE-DEPLOY: restart progressive delivery from Stage 2
7. POST-MORTEM: why did this reach canary? Was it detectable in staging?
```

### Scenario: Error budget exhausted mid-release

```
1. POLICY: all non-emergency deploys halted automatically
2. TEAM ACTION: 
   a. Identify root cause of budget burn
   b. Assess: is it an existing incident or new deploy?
3. IF new deploy is causing burn → rollback immediately
4. IF existing issue → fix first, then re-evaluate budget
5. EXCEPTION PROCESS: emergency hotfix can proceed with on-call + engineering manager approval
6. POST-MORTEM: review SLO targets — are they too tight or is reliability genuinely degraded?
```

---

## Automation Tooling

| Tool | Use Case | FAANG Notes |
|------|----------|-------------|
| Spinnaker | CD orchestration, canary analysis | Netflix-originated, widely used |
| Argo CD / Argo Rollouts | GitOps, canary + blue-green for K8s | Increasingly common in cloud-native |
| Harness | Commercial CD with SLO gates | Enterprise adoption |
| Kayenta | Canary analysis (works with Spinnaker) | Netflix open-sourced |
| Flagger | K8s-native canary operator | Integrates with Istio/Linkerd |
| Google Cloud Deploy | Managed delivery pipeline with approvals | GCP-native |

---

## FAANG Interview Callouts

**Q: How do you balance deployment speed with reliability?**

Error budget is the mechanism. The SLO is agreed upon with stakeholders. Below that, the team deploys freely. Above it, reliability work takes priority over features. This converts a subjective debate ("should we deploy now?") into an objective one ("does our error budget support it?").

**Q: A team wants to skip canary analysis because "it's just a config change." How do you respond?**

Challenge the assumption. "Just a config change" has caused major incidents (Facebook's BGP config change in 2021 took down their entire network for 6 hours). Config changes should go through the same pipeline — at minimum, shadow + 5% canary with automated gate. The cost of one 5-minute canary is much lower than one P0 incident.

**Q: Your SLO is 99.9%. How do you set the canary success threshold?**

Start with the SLO target as the floor for availability metrics. For latency, measure variance in the baseline over 7 days. Set threshold at baseline p99 + 2× typical variance. For business KPIs, work with the product team to define "acceptable degradation" — often tighter than latency targets (a checkout success rate regression of 0.5% may be more severe than a 5% latency regression).
