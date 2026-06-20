# ADR-001: Observability Stack Selection

**Title**: Adopt OpenTelemetry + Grafana Stack (Prometheus/Loki/Tempo) with Honeycomb for High-Cardinality Analysis
**Status**: Accepted
**Date**: 2024-01-15
**Authors**: [Principal Engineer], [SRE Lead]
**Reviewers**: [VP Engineering], [Engineering Manager], [Security Lead]
**Deciders**: [VP Engineering]

---

## Context

Our Payments Platform handles 8K RPS at peak, spanning 12 microservices across 3 AWS regions. We have experienced 3 SEV-1 incidents in the past quarter where:

1. Detection was slow (MTTD: 8–15 minutes) because alerts fired on raw metrics that required manual correlation with logs and traces
2. Root cause investigation took 30–90 minutes because we had no distributed tracing and no way to query high-cardinality fields (user_id, order_id, payment_provider) in our log aggregation system
3. Two of the three incidents were caused by a specific user cohort (payments above $1000) or a specific payment method (Apple Pay) — facts we could not surface with pre-aggregated metrics

Our current state:
- Metrics: Datadog APM (agent-based, SaaS) — $280K/year at current scale
- Logging: Splunk Enterprise — $180K/year; no structured log querying beyond keyword search
- Tracing: None — we have no distributed tracing instrumentation
- On-call: PagerDuty (alert routing only; no runbook integration)

We need to:
1. Instrument all 12 services with distributed tracing within 90 days
2. Enable high-cardinality querying for incident investigation
3. Establish SLO-based alerting (burn rate, not raw thresholds)
4. Reduce observability spend or justify current spend with meaningful capability improvements

**Constraint**: Our security policy prohibits sending PII (user_id, email, payment method tokens) to SaaS vendors without DPA (Data Processing Agreement). Datadog's DPA coverage for EU users is pending legal review (6-month ETA).

---

## Decision

**Adopt a hybrid observability stack**:

| Signal | Tool | Deployment |
|--------|------|-----------|
| Metrics | Prometheus + Thanos | Self-hosted on EKS |
| Dashboards + Alerting | Grafana + Grafana Alerting | Self-hosted on EKS |
| Logs | Loki | Self-hosted on EKS; S3-backed |
| Traces (operational) | Grafana Tempo | Self-hosted on EKS; S3-backed |
| Traces (analysis / high-cardinality) | Honeycomb | SaaS; EU data center; DPA in place |
| Instrumentation | OpenTelemetry SDK + Collector | Agent per node (daemonset) |
| On-call | PagerDuty | SaaS (existing; keep) |

**Sampling strategy**: Tail-based sampling in OTel Collector:
- 100% of traces with error=true or duration_ms > 2000
- 10% of normal, fast traces
- All traces stored in Tempo; "interesting" traces (error/slow) forwarded to Honeycomb for high-cardinality analysis

---

## Alternatives Considered

### Option A: Full Datadog (current trajectory)

**Description**: Continue with Datadog APM; add Datadog Logs; instrument with Datadog agent for tracing.

| Dimension | Assessment |
|-----------|-----------|
| Tracing capability | Good — flame graphs, service maps, APM correlation |
| High-cardinality querying | Limited — Datadog Logs supports 100 attributes per log; custom tag cardinality limits |
| Operational cost | Low — SaaS; no self-hosted infrastructure |
| Financial cost | $280K/year metrics; +$200K/year for logs + APM at full scale = $480K/year |
| PII / security | DPA for EU pending 6-month review — blocker for our EU user data |
| Vendor lock-in | High — proprietary agent format; migration would require re-instrumentation |

**Rejected because**: DPA blocker for EU data; high cost at scale; insufficient high-cardinality querying for unknown failure modes; proprietary instrumentation creates future lock-in risk.

### Option B: Full Honeycomb (SaaS only)

**Description**: Instrument with OpenTelemetry; send all telemetry to Honeycomb for unified storage and querying.

| Dimension | Assessment |
|-----------|-----------|
| High-cardinality querying | Excellent — the reference implementation of high-cardinality observability |
| Operational cost | Low — fully managed SaaS |
| Financial cost | ~$350K/year at 8K RPS × 100% sampling — can reduce with sampling to ~$120K/year at 10% |
| PII / security | DPA in place for EU data center; compliant |
| Long-term storage | Expensive — 90-day retention in paid tiers; longer retention prohibitively expensive |
| Metrics/Logs | Limited — Honeycomb is primarily a trace and event store; metrics dashboard in Grafana would still be needed |

**Rejected because**: Honeycomb is excellent for trace analysis but does not replace Prometheus for SLO burn rate alerting and infrastructure metrics. A Honeycomb-only strategy would still require Prometheus/Grafana for metrics. The hybrid approach gets the best of both.

### Option C: ELK Stack + Jaeger + Prometheus (fully self-hosted)

**Description**: Elasticsearch for logs, Jaeger for traces, Prometheus for metrics — all self-hosted.

| Dimension | Assessment |
|-----------|-----------|
| Capability | Good — full feature set for all three signal types |
| Operational cost | High — Elasticsearch cluster management is a significant operational burden; requires dedicated SRE time |
| Financial cost | Infrastructure ~$80K/year; 2 FTE SRE time allocated to observability infra: high hidden cost |
| High-cardinality querying | Limited — Elasticsearch supports it technically but query performance degrades without careful index management |
| Elasticsearch cost | Elasticsearch horizontal scaling for 8K RPS log volume requires 20+ nodes; expensive and operationally complex |
| Security | All data stays on-prem; PII compliance clear |

**Rejected because**: Elasticsearch operational overhead is prohibitive without a dedicated SRE team. Loki (label-indexed, not full-text by default) is operationally simpler and cheaper at scale. We do not have the SRE capacity to operate a production Elasticsearch cluster at this scale.

### Option D (Chosen): OTel + Grafana Stack + Honeycomb Hybrid

| Dimension | Assessment |
|-----------|-----------|
| High-cardinality querying | Excellent (Honeycomb) for trace analysis; Loki LogQL for structured log queries |
| Metrics / SLO alerting | Excellent (Prometheus + Grafana) — native PromQL burn rate alerting |
| Operational cost | Medium — Prometheus, Loki, Tempo require operational care; significantly simpler than Elasticsearch |
| Financial cost | Infrastructure ~$60K/year; Honeycomb ~$80K/year (with 10% sampling) = ~$140K/year total. vs $480K/year for full Datadog |
| Vendor lock-in | Low — OTel SDK is vendor-neutral; switching backends requires only Collector reconfiguration |
| PII / security | Self-hosted components hold EU data on-prem; Honeycomb DPA covers EU traces with PII redaction in Collector |
| Trace coverage | Tempo for 100% storage; Honeycomb for 100% error + slow traces |

---

## Decision Rationale

**Why not full Datadog**: DPA blocker for EU data (6-month ETA) is a hard blocker. Additionally, cost at full scale ($480K/year) is not justified given that Datadog's high-cardinality querying limitations mean we'd still be unable to answer the questions that caused 3 SEV-1 incidents.

**Why Loki over Elasticsearch**: Loki's label-indexed architecture is operationally simpler and costs 80% less at our log volume. We do not need full-text search across log bodies — we need structured field queries (trace_id lookup, user_id filter), which Loki's LogQL supports. If full-text search becomes critical, we can add it later with OpenSearch.

**Why Honeycomb for high-cardinality**: The three SEV-1 incidents in the past quarter would each have been resolved in < 5 minutes with Honeycomb's high-cardinality querying (all three were caused by specific user/payment cohorts invisible in pre-aggregated metrics). This is the highest-value capability gap. Honeycomb's BubbleUp feature would have automatically surfaced the "Apple Pay users in EU" correlation in one of those incidents.

**Why OpenTelemetry**: OTel is now the CNCF standard. Every major observability vendor supports it. Instrumenting with OTel SDK means we can switch backends by reconfiguring the Collector — no re-instrumentation required. Proprietary instrumentation (Datadog agent, Honeycomb Beeline) creates migration risk.

**Why tail-based sampling**: The incidents we care most about are in the long tail — errors and slow requests. Head-based random sampling at 10% would miss 90% of SEV-1 indicators. Tail-based sampling guarantees 100% retention of error and slow traces — the ones we actually need to debug.

---

## Consequences

### Positive

- **Cost**: ~$140K/year vs $480K/year trajectory → ~$340K/year savings
- **Capability**: High-cardinality trace analysis closes the investigation gap that caused 3 recent SEV-1 incidents to take 30–90 minutes to resolve
- **PII compliance**: Self-hosted components + Honeycomb DPA + OTel Collector PII scrubber provides EU data compliance immediately, not in 6 months
- **Vendor independence**: OTel instrumentation means future backend migration is a Collector config change, not a code change
- **SLO alerting**: Prometheus + Grafana enables burn rate alerting natively with PromQL; this was not achievable in our Datadog configuration

### Negative

- **Operational overhead**: Prometheus, Loki, and Tempo require ongoing operational care. We estimate 0.5 FTE SRE time per quarter for maintenance and upgrades.
- **Migration effort**: Migrating 12 services from Datadog agent to OTel SDK is a 3–4 month project. During migration, we run both stacks in parallel (adds ~$50K temporary cost).
- **Learning curve**: Engineering team must learn new tools: Grafana, PromQL, LogQL, Honeycomb query interface. Plan: 2 internal workshops + pair debugging sessions during the first 3 incidents after rollout.
- **Alert migration**: All existing Datadog alert rules must be recreated in Grafana Alerting + Alertmanager. Risk: gaps during migration. Mitigation: keep Datadog running in parallel until all alerts are validated.

### Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| OTel Collector becomes a SPOF | Medium | High | Deploy as daemonset (one per node); collector failure drops telemetry but does not affect service availability; buffering in SDK |
| Loki query performance under high log volume | Medium | Medium | Pre-allocate log shards by service; implement log sampling for high-volume low-value logs (health checks, metrics scrapes) |
| Honeycomb cost overrun if sampling is misconfigured | Low | High | Set hard spending alert in Honeycomb dashboard; review monthly for first 6 months |
| Team adoption slow (new tools, learning curve) | High | Medium | Champion program: 2 engineers become Honeycomb/Grafana experts; all runbooks updated to reference new tooling |

---

## Implementation Plan

### Phase 1 (Weeks 1–4): Foundation

```
□ Deploy OTel Collector as daemonset in all 3 regions
□ Configure tail-based sampling: 100% errors/slow, 10% normal
□ Deploy Prometheus + Thanos (metrics)
□ Deploy Grafana with Prometheus datasource
□ Migrate existing Datadog dashboards to Grafana (critical dashboards only)
□ Keep Datadog running in parallel
```

### Phase 2 (Weeks 5–10): Instrumentation

```
□ Instrument payment-service with OTel Java SDK (auto-instrumentation + manual spans)
□ Instrument checkout-service, inventory-service, notification-service
□ Validate trace correlation across service boundaries (check W3C traceparent propagation)
□ Deploy Honeycomb for payment-service traces; validate high-cardinality querying
□ Internal workshop: "Debugging with distributed traces in Honeycomb" (2 hours)
```

### Phase 3 (Weeks 11–16): Logs + SLO Alerting

```
□ Deploy Loki + promtail agents
□ Migrate structured log shipping from Splunk to Loki for payment-service, checkout-service
□ Implement SLO burn rate alerting in Grafana Alerting + Alertmanager
□ Migrate PagerDuty routing rules to new alert names
□ Instrument remaining 8 services with OTel
□ Internal workshop: "SLO burn rate alerting and runbooks" (2 hours)
```

### Phase 4 (Weeks 17–20): Cutover + Decommission

```
□ All 12 services instrumented with OTel
□ All critical dashboards migrated to Grafana
□ All alert rules validated in new stack (parallel alerts running for 4 weeks)
□ Decommission Datadog agent
□ Negotiate Splunk contract termination
□ 90-day retrospective: MTTD, MTTR, alert noise reduction metrics
```

---

## Success Metrics

| Metric | Baseline (current) | Target (90 days post-rollout) |
|--------|-------------------|-----------------------------|
| MTTD for SEV-1 incidents | 8–15 minutes | < 3 minutes |
| MTTR for SEV-1 incidents | 30–90 minutes | < 20 minutes |
| Alert signal:noise ratio | ~20% (200 alerts/week, 40 actionable) | > 70% |
| Observability cost | $480K/year trajectory | < $160K/year |
| Services with distributed tracing | 0 | 12 (100%) |
| Post-incident "could not determine root cause" | 2 of last 3 incidents | 0 of next 10 incidents |

---

## Review Schedule

- **30-day review**: Is OTel Collector stable? Are traces flowing correctly for payment-service? Is sampling configuration producing expected volume?
- **90-day review**: Is MTTD improving? Are engineers using Honeycomb effectively? Is Loki query performance acceptable?
- **6-month review**: Full cost accounting vs baseline; re-evaluate Honeycomb vs Tempo for all-traces storage; tighten or relax sampling rates based on 6 months of volume data.

---

## References

- [Observability Engineering](../../Books/summaries/observability-engineering-majors-fong-jones-miranda.md) — foundational principles
- [SLO Design Guide](../../HLD/designs/slo-design-guide.md) — SLI/SLO definitions and burn rate alerting
- [Incident Response Playbook](../../Development/processes/incident-response-playbook.md) — operational context for this decision
- [OpenTelemetry documentation](https://opentelemetry.io/docs/) — instrumentation reference
- [Grafana Loki best practices](https://grafana.com/docs/loki/latest/best-practices/) — deployment guidance
- Previous SEV-1 post-mortems: INC-2023-0421, INC-2024-0087, INC-2024-0115
