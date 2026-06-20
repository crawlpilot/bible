# Migrating from Direct CloudWatch to OpenTelemetry — AWS Observability Modernisation

**Domain:** Platform Engineering / Observability  
**Pattern:** Vendor Decoupling + Centralised Telemetry  
**Stack:** AWS (ECS/EKS), OpenTelemetry Collector, Prometheus, Grafana, CloudWatch (retained as a backend)  
**Problem solved:** Fragmented, vendor-locked observability that scaled cost linearly with service count, required per-service SDK changes to move between backends, and had no central control plane for metric cardinality, retention, or routing

---

## Problem Statement

### What We Had: Direct CloudWatch Integration

Every service emitted telemetry directly to AWS CloudWatch using the CloudWatch SDK or the CloudWatch Agent:

```
Service A ──► CloudWatch SDK ──► CloudWatch Metrics
Service B ──► CloudWatch SDK ──► CloudWatch Metrics
Service C ──► CloudWatch SDK ──► CloudWatch Logs
Service D ──► X-Ray SDK ──────► X-Ray Traces
...
Service N ──► CloudWatch SDK ──► CloudWatch Metrics
```

This worked at small scale. It became a principal-level problem at 40+ services across 6 teams.

### The Pain Points

**1. Vendor lock-in at the SDK level**  
Every service imported `aws-sdk` CloudWatch clients directly. Moving any metric to a different backend (Prometheus, Datadog, a cheaper time-series store) required modifying the service code. There was no abstraction layer — the observability destination was baked into the application.

**2. No centralised control over metric cardinality**  
Individual teams added high-cardinality dimensions (e.g., `customerId` as a CloudWatch dimension) without understanding the cost implication. CloudWatch pricing is `$0.30 per metric per month` — a single service emitting 200 custom metrics with 50 unique dimension combinations = 10,000 metric streams = $3,000/month from one service.

**3. Cost scaled with service count, not value**  
CloudWatch custom metrics: every distinct `(metric name, dimension set)` is a separate billable metric stream. As services grew and teams added dimensions, the bill grew non-linearly. No team had visibility into their own CloudWatch spend.

**4. No cross-service correlation**  
Metrics in CloudWatch, logs in CloudWatch Logs, traces in X-Ray — three separate systems with no unified context. Debugging a latency spike required: CloudWatch dashboard for metrics → CloudWatch Logs Insights for logs → X-Ray console for traces. No single pane, no correlated trace IDs in logs.

**5. Operational complexity: tuning was per-service**  
Every change to what metrics were collected, at what resolution, or with what dimensions required a code change, PR review, deployment. There was no runtime control plane.

**6. No multi-backend capability**  
Two teams wanted Grafana/Prometheus for engineering dashboards while keeping CloudWatch for AWS-native alarms (EC2 health, ECS service alarms). The direct-SDK model forced a choice — there was no way to fan out to multiple backends without duplicating emission code.

---

## The Decision: OpenTelemetry as the Observability Abstraction Layer

**OpenTelemetry (OTel)** is the CNCF standard for telemetry instrumentation: a vendor-neutral SDK and collector that separates *instrumentation* (what you measure in your code) from *destination* (where the data goes).

```
Service A ──► OTel SDK ──► OTel Collector ──► CloudWatch
Service B ──► OTel SDK ──►      │          ──► Prometheus
Service C ──► OTel SDK ──►      │          ──► Grafana Tempo (traces)
...                             │          ──► S3 (archival)
Service N ──► OTel SDK ──►      └──► Any future backend
```

The Collector is the key: a standalone process that receives telemetry, processes it (filter, transform, enrich, sample), and exports it to one or many backends. **No service code changes required to change backends.**

---

## Architecture: Before vs After

### Before

```
┌───────────────────────────────────────────────────────────┐
│  ECS / EKS Cluster                                        │
│                                                           │
│  ┌──────────┐   AWS SDK   ┌─────────────────────────┐    │
│  │ Service A├────────────►│ CloudWatch Custom Metrics│    │
│  └──────────┘             └─────────────────────────┘    │
│  ┌──────────┐   AWS SDK   ┌─────────────────────────┐    │
│  │ Service B├────────────►│ CloudWatch Custom Metrics│    │
│  └──────────┘             └─────────────────────────┘    │
│  ┌──────────┐   X-Ray SDK ┌─────────────────────────┐    │
│  │ Service C├────────────►│ X-Ray                    │    │
│  └──────────┘             └─────────────────────────┘    │
│                                                           │
│  Per-service config, per-service billing, no central view │
└───────────────────────────────────────────────────────────┘
```

### After

```
┌────────────────────────────────────────────────────────────────────┐
│  ECS / EKS Cluster                                                 │
│                                                                    │
│  ┌──────────┐  OTLP   ┌──────────────────────────────────────┐   │
│  │ Service A├─────────►                                        │   │
│  └──────────┘         │   OTel Collector (DaemonSet / Sidecar) │   │
│  ┌──────────┐  OTLP   │                                        │   │
│  │ Service B├─────────►  Pipeline:                             │   │
│  └──────────┘         │  - Receive (OTLP, Prometheus scrape)   │   │
│  ┌──────────┐  OTLP   │  - Process (filter, enrich, sample,   │   │
│  │ Service C├─────────►             aggregate, drop)           │   │
│  └──────────┘         │  - Export (fan-out to N backends)      │   │
│       ...             └────────────────┬───────────────────────┘   │
│                                        │                            │
└────────────────────────────────────────┼────────────────────────────┘
                                         │
              ┌──────────────────────────┼────────────────────────┐
              ▼                          ▼                         ▼
   ┌──────────────────┐    ┌──────────────────────┐   ┌──────────────────┐
   │  CloudWatch EMF  │    │  Prometheus (AMP)    │   │  Grafana Tempo   │
   │  (AWS alarms,    │    │  (Engineering        │   │  (Distributed    │
   │   AWS dashboards)│    │   dashboards, SLOs)  │   │   tracing)       │
   └──────────────────┘    └──────────────────────┘   └──────────────────┘
```

---

## Phase 1: Instrument with OTel SDK (No Behaviour Change)

The first phase added OTel instrumentation alongside existing CloudWatch SDK calls. This allowed A/B comparison before cutting over.

### Java Service Instrumentation

```java
// Before: direct CloudWatch SDK
cloudWatchClient.putMetricData(PutMetricDataRequest.builder()
    .namespace("MyService/Orders")
    .metricData(MetricDatum.builder()
        .metricName("OrderProcessingTime")
        .value(latencyMs)
        .unit(StandardUnit.MILLISECONDS)
        .dimensions(Dimension.builder().name("Environment").value("prod").build())
        .build())
    .build());

// After: OTel SDK — vendor-agnostic
OpenTelemetry otel = GlobalOpenTelemetry.get();
Meter meter = otel.getMeter("com.company.order-service");

LongHistogram processingTime = meter
    .histogramBuilder("order.processing.duration")
    .setDescription("Time to process an order end-to-end")
    .setUnit("ms")
    .ofLongs()
    .build();

// Record — SDK handles batching, export, retry
processingTime.record(latencyMs,
    Attributes.of(
        AttributeKey.stringKey("environment"), "prod",
        AttributeKey.stringKey("order_type"), orderType
    ));
```

### Auto-Instrumentation (Zero Code Change for Common Libraries)

For Spring Boot, Kafka, JDBC, HTTP clients — OTel Java agent instruments automatically:

```bash
# ECS task definition — add Java agent as JVM arg
JAVA_TOOL_OPTIONS="-javaagent:/otel/opentelemetry-javaagent.jar"

# Environment variables configure the agent
OTEL_SERVICE_NAME=order-service
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_TRACES_SAMPLER_ARG=0.1   # 10% trace sampling
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=prod,team=orders
```

This auto-instruments: Spring MVC (HTTP spans), RestTemplate/WebClient (outbound spans), JDBC (SQL spans), Kafka consumer/producer (messaging spans) — with **zero application code changes**.

---

## Phase 2: Deploy the OTel Collector

The Collector is the control plane. Deployed as a **DaemonSet** on EKS (one per node) or as a **Sidecar** on ECS (one per task).

### Collector Pipeline Configuration

```yaml
# otel-collector-config.yaml

receivers:
  # Receive OTLP from services (gRPC port 4317, HTTP port 4318)
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

  # Scrape Prometheus endpoints (for services that expose /metrics)
  prometheus:
    config:
      scrape_configs:
        - job_name: service-discovery
          kubernetes_sd_configs:
            - role: pod
          relabel_configs:
            - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
              action: keep
              regex: "true"

  # Collect host metrics (CPU, memory, disk, network) from the node
  hostmetrics:
    collection_interval: 60s
    scrapers:
      cpu:
      memory:
      disk:
      network:
      load:

processors:
  # ── Enrichment ─────────────────────────────────────────────────────
  # Add resource attributes from EC2/EKS metadata
  resourcedetection:
    detectors: [ec2, ecs, eks]
    timeout: 5s

  # Add standard attributes to all telemetry
  resource:
    attributes:
      - key: service.environment
        value: ${ENV}
        action: upsert
      - key: cloud.region
        value: ${AWS_REGION}
        action: upsert

  # ── Cardinality Control ────────────────────────────────────────────
  # Drop high-cardinality attributes that blow up metric streams
  attributes/drop_high_cardinality:
    actions:
      - key: customer_id       # would create millions of metric streams
        action: delete
      - key: request_id
        action: delete
      - key: user_session_id
        action: delete

  # ── Filtering ──────────────────────────────────────────────────────
  # Drop noisy health-check metrics (not business value)
  filter/drop_health_checks:
    metrics:
      exclude:
        match_type: regexp
        metric_names:
          - ".*health.*"
          - ".*ping.*"
          - ".*liveness.*"
          - ".*readiness.*"

  # Drop low-value, high-volume JVM GC pause detail metrics
  filter/drop_jvm_noise:
    metrics:
      exclude:
        match_type: regexp
        metric_names:
          - "jvm.gc.duration.bucket"    # keep _count and _sum, not all buckets

  # ── Metric Aggregation ─────────────────────────────────────────────
  # Pre-aggregate before export to reduce CloudWatch custom metric count
  metricstransform:
    transforms:
      - include: order.processing.duration
        action: update
        operations:
          - action: aggregate_labels
            label_set: [environment, order_type]   # drop other dimensions for CloudWatch
            aggregation_type: sum

  # ── Sampling (traces) ──────────────────────────────────────────────
  # Tail-based sampling: keep 100% of error traces, 5% of success traces
  tail_sampling:
    decision_wait: 10s
    policies:
      - name: errors-policy
        type: status_code
        status_code: {status_codes: [ERROR]}
      - name: slow-traces-policy
        type: latency
        latency: {threshold_ms: 1000}
      - name: sample-rest
        type: probabilistic
        probabilistic: {sampling_percentage: 5}

  # ── Batching and Memory ────────────────────────────────────────────
  batch:
    timeout: 10s
    send_batch_size: 1000

  memory_limiter:
    limit_mib: 512
    spike_limit_mib: 128
    check_interval: 5s

exporters:
  # ── CloudWatch (AWS-native alarms + dashboards) ────────────────────
  awsemf:
    namespace: "Production/Services"
    region: ${AWS_REGION}
    log_group_name: "/metrics/production"
    dimension_rollup_option: "NoDimensionRollup"
    metric_declarations:
      - dimensions: [[service.name, environment]]
        metric_name_selectors:
          - "order.processing.duration"
          - "http.server.request.duration"
          - "kafka.consumer.lag"

  # ── Prometheus / Amazon Managed Prometheus (AMP) ──────────────────
  prometheusremotewrite:
    endpoint: https://aps-workspaces.${AWS_REGION}.amazonaws.com/workspaces/${AMP_WORKSPACE_ID}/api/v1/remote_write
    auth:
      authenticator: sigv4auth
    resource_to_telemetry_conversion:
      enabled: true

  # ── Traces → Grafana Tempo ─────────────────────────────────────────
  otlp/tempo:
    endpoint: http://tempo:4317
    tls:
      insecure: true

  # ── Debug (dev environments only) ─────────────────────────────────
  debug:
    verbosity: detailed

extensions:
  sigv4auth:
    region: ${AWS_REGION}
    service: "aps"

  health_check:
    endpoint: 0.0.0.0:13133

  pprof:
    endpoint: 0.0.0.0:1777

service:
  extensions: [sigv4auth, health_check, pprof]

  pipelines:
    # Metrics pipeline: fan-out to CloudWatch + Prometheus
    metrics:
      receivers: [otlp, prometheus, hostmetrics]
      processors:
        - resourcedetection
        - resource
        - attributes/drop_high_cardinality
        - filter/drop_health_checks
        - filter/drop_jvm_noise
        - metricstransform
        - batch
        - memory_limiter
      exporters: [awsemf, prometheusremotewrite]

    # Traces pipeline: tail sampling → Tempo
    traces:
      receivers: [otlp]
      processors:
        - resourcedetection
        - resource
        - tail_sampling
        - batch
        - memory_limiter
      exporters: [otlp/tempo]

    # Logs pipeline: enrich → CloudWatch Logs
    logs:
      receivers: [otlp]
      processors:
        - resourcedetection
        - resource
        - batch
        - memory_limiter
      exporters: [awscloudwatchlogs]
```

---

## Decoupling from the Underlying Technology

### The Core Abstraction

The OTel Collector is a **router with a processing pipeline**. No service knows or cares what happens downstream of the Collector.

**What this enabled:**

| Scenario | Without OTel (before) | With OTel (after) |
|----------|----------------------|-------------------|
| Add Grafana as a second dashboard | Modify every service to emit to Prometheus | Add `prometheusremotewrite` exporter to Collector config |
| Move from CloudWatch to Datadog | Rewrite SDK calls in 40 services | Swap `awsemf` exporter for `datadog` exporter |
| Add trace sampling for cost | Each service implements its own sampler | Configure `tail_sampling` processor once in Collector |
| Stop emitting noisy metrics | PR per service | Add `filter` processor to Collector config |
| Add new attribute to all metrics | PR per service | Add `resource` processor to Collector config |
| Switch from ECS to EKS | Reconfigure CloudWatch Agent per task | Update `resourcedetection` processor |

**The decoupling property:** Application teams own the *what* (what they instrument). The platform team owns the *where* and *how* (where data goes, how it's processed). These concerns are completely separated by the Collector boundary.

---

## Cost Improvements

### CloudWatch Custom Metrics Cost Model

**Before migration:**
```
CloudWatch pricing: $0.30 per metric stream per month
(A metric stream = unique combination of metric name + dimension set)

Example: order-processing-duration × {env, region, service, customer_tier, order_type}
= 1 metric name × 2 envs × 3 regions × 8 services × 4 tiers × 5 types
= 960 metric streams
= $288/month from ONE metric
```

Teams were emitting 150+ custom metrics with 4–6 dimensions each — without understanding that each dimension combination was a separate billing unit.

**After migration — three levers applied:**

**Lever 1: Cardinality control in the Collector**
```yaml
# Drop dimensions before CloudWatch export
metricstransform:
  transforms:
    - include: order.processing.duration
      action: update
      operations:
        - action: aggregate_labels
          label_set: [environment, service.name]  # only 2 dimensions in CloudWatch
```
Result: 960 streams → 16 streams (env × service). Same business signal, 98% fewer metric streams.

**Lever 2: Route high-cardinality metrics to Prometheus (cheap) not CloudWatch (expensive)**

CloudWatch custom metrics: $0.30/stream/month  
Amazon Managed Prometheus (AMP): $0.90 per million samples ingested + $0.03/GB storage

High-cardinality metrics (many dimension combos, engineering use) → AMP  
Low-cardinality metrics (CloudWatch Alarms, AWS console) → CloudWatch

**Lever 3: Drop noise at the Collector**
```yaml
filter/drop_health_checks:
  metrics:
    exclude:
      match_type: regexp
      metric_names: [".*health.*", ".*ping.*"]
```
Health check endpoints emitting 60 metrics/minute × 40 services = 86,400 metric data points/minute pushed into CloudWatch. None of this was used in any alarm or dashboard.

**Cost results:**

| Category | Before | After | Saving |
|----------|--------|-------|--------|
| CloudWatch Custom Metrics | 14,200 metric streams | 1,800 metric streams | 87% reduction |
| CloudWatch monthly bill | ~$4,260/month | ~$540/month | $3,720/month |
| X-Ray trace cost (no sampling) | ~$800/month | ~$140/month (5% + error sampling) | 82% reduction |
| Total observability AWS spend | ~$5,600/month | ~$980/month (+ AMP ~$200) | **~78% reduction** |

---

## Centralisation of Metrics — Single Control Plane

### Before: Fragmented and Uncontrolled

Every team had their own observability configuration, embedded in service code. To answer "what metrics are we paying for?" required reading every service's codebase.

To enforce a standard like "no customer IDs as dimensions" required code review catch — not systematic enforcement.

### After: Centralised Collector Configuration

The Collector config is a single, version-controlled, team-reviewed artifact. It is the **one place** where:

- Metric routing is defined
- Cardinality limits are enforced
- Cost controls are applied
- Attribute enrichment happens
- Sampling rates are set

```
Collector config repo (platform team owns):
  config/
    base.yaml           ← shared processors (enrichment, memory limits)
    exporters/
      cloudwatch.yaml   ← what goes to CloudWatch, at what resolution
      prometheus.yaml   ← what goes to AMP
      tempo.yaml        ← trace routing
    filters/
      drop-noise.yaml   ← what to discard
      cardinality.yaml  ← high-cardinality dimension removal
    sampling/
      traces.yaml       ← tail sampling policies
```

**Governance model:**
- Platform team owns the Collector config repo
- Service teams can propose additions via PR (adding new metric routing)
- Platform team reviews for cost, cardinality, naming convention
- Changes deploy in minutes — no service deployment required

**Naming convention enforcement:**
```yaml
# transform/naming-convention.yaml
# Enforce snake_case dot-notation names before any export
metricstransform:
  transforms:
    - include: "orderProcessingTime"      # Java camelCase from old SDK
      action: update
      new_name: "order.processing.duration"
    - include: "Order_Processing_Time"    # legacy inconsistency
      action: update
      new_name: "order.processing.duration"
```

All services converge on OTel semantic conventions regardless of what name the application emits.

---

## Centralised Tuning

### Resolution Tuning per Destination

CloudWatch charges more for high-resolution (1-second) metrics than standard (60-second). Most metrics don't need 1-second resolution.

```yaml
# Collector: downsample before CloudWatch export
# High-resolution metrics: only for latency SLO tracking
awsemf:
  metric_declarations:
    - dimensions: [[service.name]]
      metric_name_selectors: ["http.server.request.duration"]
      label_matchers:
        - label_names: [service.name]
          regex: "payment-.*"      # payment services get 10s resolution
    - dimensions: [[service.name]]
      metric_name_selectors: [".*"]
      # Everything else: default 60s resolution
```

Before: teams set `StorageResolution: 1` (high-resolution, expensive) by default because they didn't know about the cost difference. The Collector config made this a deliberate, centralised decision.

### Trace Sampling Tuning (Tail-Based)

Head-based sampling (in-process) samples at the start of a request before you know if it's interesting. Tail-based sampling (in Collector) waits until the trace is complete:

```yaml
tail_sampling:
  decision_wait: 10s     # wait 10s for all spans to arrive
  policies:
    - name: always-keep-errors
      type: status_code
      status_code: {status_codes: [ERROR]}     # 100% of errors

    - name: always-keep-slow
      type: latency
      latency: {threshold_ms: 2000}            # 100% of P99+ traces

    - name: keep-payment-traces
      type: string_attribute
      string_attribute:
        key: service.name
        values: ["payment-service"]
        enabled_for_sampling: true
      # + probabilistic 20% for payment service traces

    - name: sample-rest
      type: probabilistic
      probabilistic: {sampling_percentage: 2}  # 2% of everything else
```

Changing the sampling rate for any policy is a Collector config PR — no service deployment, no code change, no coordination with 6 teams.

---

## Operational Reduction

### Before: Per-Service Observability Toil

| Task | Effort before |
|------|--------------|
| Add a new metric backend | 40 service PRs + 40 deployments |
| Change metric sampling rate | 1 service PR per service |
| Fix naming convention inconsistency | Manual grep + multi-service PRs |
| Debug why a metric stopped appearing | SSH to instance + check CW agent config |
| Enforce cardinality limits | Code review (manual, inconsistent) |
| Update CloudWatch namespace | 40 config changes across services |

### After: Collector is the Leverage Point

| Task | Effort after |
|------|-------------|
| Add a new metric backend | 1 Collector config PR + deploy Collector |
| Change metric sampling rate | 1 line in Collector config |
| Fix naming convention inconsistency | `metricstransform` in Collector |
| Debug why a metric stopped | Collector `debug` exporter + health check endpoint |
| Enforce cardinality limits | `attributes` processor in Collector config |
| Update CloudWatch namespace | 1 line in `awsemf` exporter config |

**Collector health monitoring:**
```yaml
# Collector exposes its own metrics on port 8888
# Monitor the monitor
- alert: CollectorDroppingData
  expr: rate(otelcol_processor_dropped_metric_points[5m]) > 0
  severity: warning

- alert: CollectorExportError
  expr: rate(otelcol_exporter_send_failed_metric_points[5m]) > 0
  severity: critical

- alert: CollectorMemoryPressure
  expr: otelcol_process_memory_rss > 450 * 1024 * 1024  # 450MB of 512MB limit
  severity: warning
```

---

## Extension Points Built In

### Adding a New Backend (No Service Changes)

Example: adding Datadog for a subset of services after the migration:

```yaml
# Add to Collector config — zero service-side changes
exporters:
  datadog:
    api:
      key: ${DATADOG_API_KEY}
      site: datadoghq.com
    metrics:
      namespace: "production"

service:
  pipelines:
    metrics/datadog:
      receivers: [otlp]
      processors:
        - filter/payment-service-only    # only payment team metrics
        - batch
      exporters: [datadog]
```

### Adding a New Signal Type: Profiling (Future)

OTel is adding continuous profiling as a signal type (alongside metrics, traces, logs). When it's stable, adding it requires:
- Update the OTel SDK version (or auto-instrumentation agent)
- Add a `profiling` pipeline in the Collector
- No service code changes

### Custom Processors for Business Logic

The Collector's processor model is extensible. A custom processor was written to redact PII from log bodies before export:

```go
// custom processor: redact credit card numbers from log bodies
func (p *piiRedactProcessor) processLogs(ctx context.Context, ld plog.Logs) (plog.Logs, error) {
    for i := 0; i < ld.ResourceLogs().Len(); i++ {
        for j := 0; j < ld.ResourceLogs().At(i).ScopeLogs().Len(); j++ {
            for k := 0; k < ld.ResourceLogs().At(i).ScopeLogs().At(j).LogRecords().Len(); k++ {
                record := ld.ResourceLogs().At(i).ScopeLogs().At(j).LogRecords().At(k)
                body := record.Body().Str()
                redacted := p.ccnRegex.ReplaceAllString(body, "[REDACTED]")
                record.Body().SetStr(redacted)
            }
        }
    }
    return ld, nil
}
```

This applies to all services uniformly without any service-side code — the Collector is the enforcement point for security and compliance requirements too.

---

## Unified Observability: Linking Metrics, Traces, Logs

With OTel, every span, log record, and metric shares common resource attributes:

```
service.name = "order-service"
service.version = "2.4.1"
deployment.environment = "prod"
cloud.region = "us-east-1"
k8s.pod.name = "order-service-abc123"
trace.id = "4bf92f3577b34da6"
span.id = "00f067aa0ba902b7"
```

In Grafana:
- Select a metric spike → click "Explore traces" → filtered to `service.name + time range`
- Select a trace → click "Explore logs" → filtered by `trace.id`
- All three signals are correlated through shared context — no manual copy-pasting of IDs

Before OTel: metrics in CloudWatch, traces in X-Ray, logs in CloudWatch Logs — three consoles, no shared identifiers. An on-call engineer debugging a P1 spent 15–20 minutes correlating data across tools manually.

---

## Migration Phasing

### Phase 1 (Weeks 1–4): Instrument and Run in Parallel
- Deploy OTel SDK alongside existing CloudWatch SDK (dual-emit)
- Deploy Collector in passthrough mode (OTLP in → CloudWatch out, same as before)
- Validate parity: OTel metrics match CloudWatch metrics
- No cost reduction yet — running both stacks

### Phase 2 (Weeks 5–8): Activate Collector Processing
- Enable `filter`, `attributes`, `metricstransform` processors
- Remove high-cardinality dimensions from CloudWatch path
- Route engineering metrics to AMP / Prometheus
- First cost reduction visible in AWS bill

### Phase 3 (Weeks 9–12): Remove Direct CloudWatch SDK
- Services remove `aws-sdk` CloudWatch import
- Only OTel SDK remains in application code
- CloudWatch Agent removed from ECS tasks / EKS nodes
- OTel Collector is the sole telemetry pipeline

### Phase 4 (Weeks 13–16): Unified Dashboards + Alerting
- Grafana dashboards replace CloudWatch dashboards for engineering use
- CloudWatch alarms retained for AWS-native health (EC2, ECS, RDS)
- Distributed tracing in Grafana Tempo replaces X-Ray console
- On-call runbooks updated to Grafana links

### Phase 5 (Ongoing): Optimise and Extend
- Quarterly cost review of metric cardinality
- Collector config tuning based on usage data
- Add new signal types as OTel spec matures (profiling)
- onboard new services directly to OTel — no legacy path

---

## Key Design Decisions

### ADR 1: OTel Collector as a DaemonSet (not Sidecar)

**Context:** EKS workloads. Choice between DaemonSet (one Collector per node) or Sidecar (one per pod).  
**Decision:** DaemonSet on EKS, Sidecar on ECS (ECS has no DaemonSet equivalent).  
**Why:** DaemonSet reduces resource overhead — 1 Collector per node instead of 1 per pod. A node with 10 pods uses 1/10th the Collector resources. Sidecar is better for noisy-neighbour isolation (one service can't starve another's telemetry).  
**Trade-off:** DaemonSet: one Collector failing impacts all pods on that node. Sidecar: failure is isolated per pod.

### ADR 2: Tail-Based Sampling in Collector over Head-Based in SDK

**Context:** Need to reduce trace volume without losing error traces.  
**Decision:** Tail-based sampling via `tail_sampling` processor in Collector.  
**Why:** Head-based sampling (in application) makes the sampling decision at request start — before knowing if the request will error or be slow. Tail-based sampling sees the complete trace, enabling "keep 100% of errors, 5% of success." This is higher signal per trace than any head-based approach.  
**Trade-off:** Tail-based sampling requires holding spans in memory for `decision_wait` seconds — increases Collector memory usage. Mitigation: set `decision_wait: 10s` (not too long).

### ADR 3: Retain CloudWatch for AWS-Native Alarms

**Context:** CloudWatch alarms integrate directly with ECS service health, EC2 auto-scaling, and RDS Enhanced Monitoring.  
**Decision:** Keep CloudWatch as one of the export destinations, not eliminate it.  
**Why:** AWS-native alarms (ECS service in stopped state, RDS failover) are only available in CloudWatch. Replacing them with Prometheus alerting would require custom exporters and lose AWS-native integration. The Collector fans out — both CloudWatch and Prometheus receive metrics.

### ADR 4: Amazon Managed Prometheus (AMP) over Self-Hosted

**Context:** Need a Prometheus-compatible backend. Self-hosted Prometheus vs AMP.  
**Decision:** AMP (managed Prometheus).  
**Why:** Self-hosted Prometheus at scale requires: storage sizing, compaction tuning, HA setup, backup. AMP handles all of this as a managed service. Cost for our volume: ~$200/month vs ~2 weeks of SRE time to set up and maintain self-hosted.

---

## Results

| Dimension | Before | After |
|-----------|--------|-------|
| AWS observability cost | ~$5,600/month | ~$1,180/month | 
| CloudWatch metric streams | 14,200 | 1,800 |
| Backends supported | 1 (CloudWatch) | 3 (CW + AMP + Tempo), extensible |
| Time to add new backend | 2–3 weeks (multi-service PRs) | 1 day (Collector config + deploy) |
| Time to change sampling rate | 1–2 days (per service, per team) | 30 minutes (Collector config PR) |
| Mean time to correlate trace + log + metric during incident | 15–20 minutes | 2–3 minutes (unified in Grafana) |
| Services with consistent naming conventions | ~40% | 100% (enforced in Collector) |
| Cardinality enforcement | Manual (code review) | Systematic (Collector processors) |
| PII redaction in logs | Per-service (inconsistent) | Collector-level (uniform) |

---

## Interview Angles

**On the decision to adopt OpenTelemetry:**
> The core insight was that observability was a cross-cutting concern that 6 teams were solving independently and badly. Every team embedded CloudWatch SDK calls directly — tight coupling between instrumentation and destination. When we wanted to add Grafana, we faced 40 service PRs. When a team added `customerId` as a CloudWatch dimension, we got a surprise bill. OTel's value proposition is the separation of instrumentation from routing. The Collector is a control plane: platform team owns it, and we can change destinations, apply sampling, enforce cardinality limits, and add enrichment without touching application code.

**On cost reduction:**
> The CloudWatch cost problem was architectural, not behavioural. Teams weren't being reckless — they didn't know that a dimension with 50 unique values creates 50× the metric streams. The fix wasn't education; it was making it structurally impossible to emit high-cardinality data to CloudWatch by intercepting at the Collector. We also introduced routing: high-cardinality engineering metrics go to AMP (cheap per sample), while low-cardinality operational metrics go to CloudWatch (expensive per stream but fewer streams). The 78% cost reduction came from these two controls, not from reducing what we measured.

**On tail-based trace sampling:**
> Head-based sampling is a coin flip at request entry — you keep 10% of all traces, including boring successes, and accidentally drop 90% of errors. Tail-based sampling inverts this: you see the complete trace before deciding. The policy is "keep all errors, keep all slow traces, keep 2% of everything else." This means our trace storage actually increased in signal density after the migration despite 95% reduction in volume — because we kept exactly what matters for debugging.

**On operational reduction:**
> Before, changing anything about observability required coordination with multiple teams, PRs, reviews, and deployments. After, the Collector config is a single PR in a single repo, deployed centrally. The platform team has a lever on the entire observability pipeline. That's the principal engineer's goal: create leverage. One config change should affect all 40 services simultaneously — not require 40 individual changes.
