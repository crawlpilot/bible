# Observability & Monitoring Best Practices

## Overview
Observability is not the same as monitoring. Monitoring asks "is the system up?" — it requires you to know in advance what can go wrong. Observability asks "why is the system misbehaving?" — it allows you to understand any system state by examining its outputs, without deploying new code. At FAANG scale, systems are too complex for exhaustive upfront monitoring; observability is the engineering discipline that lets teams understand distributed systems they didn't fully anticipate.

**The three pillars**: Metrics (what is happening), Logs (what happened in detail), Traces (how a request flowed through the system). All three are required; none substitutes for the others.

---

## The Observability Stack

```
                        ┌─────────────────────────────────────────┐
                        │  Dashboards & Alerting                   │
                        │  Grafana | PagerDuty | OpsGenie | Slack │
                        └────────────┬────────────────────────────┘
                                     │
        ┌────────────────────────────┼────────────────────────────┐
        ▼                            ▼                            ▼
┌──────────────┐          ┌──────────────────┐          ┌──────────────────┐
│   Metrics    │          │      Logs        │          │     Traces       │
│  Prometheus  │          │  Elasticsearch   │          │     Jaeger       │
│  Datadog     │          │  OpenSearch      │          │     Zipkin       │
│  CloudWatch  │          │  CloudWatch Logs │          │     Tempo        │
│  New Relic   │          │  Datadog Logs    │          │     X-Ray        │
└──────┬───────┘          └────────┬─────────┘          └────────┬─────────┘
       │                           │                              │
       └───────────────────────────┼──────────────────────────────┘
                                   ▼
                     ┌──────────────────────────┐
                     │   OpenTelemetry SDK       │
                     │   (single instrumentation │
                     │    layer for all three)   │
                     └──────────────────────────┘
```

---

## The Four Golden Signals (Google SRE)

The mandatory metrics for any production service:

| Signal | What it measures | Alert condition |
|---|---|---|
| **Latency** | Time to serve a request; distinguish success vs error latency | p99 latency > SLO threshold |
| **Traffic** | Requests per second; events per second; volume of demand | Spike above capacity model; drop below expected baseline |
| **Errors** | Rate of failed requests; distinguish 4xx (client) from 5xx (server) | Error rate > SLO budget burn rate |
| **Saturation** | How "full" the service is; CPU%, memory%, thread pool queue depth, disk I/O% | Any resource > 80% sustained |

**These four cover 80% of production incidents.** Add domain-specific metrics on top.

---

## RED Method (Services)

For every service in a microservice architecture, instrument these three:

| Metric | Description | Prometheus query example |
|---|---|---|
| **Rate** | Requests per second | `rate(http_requests_total[5m])` |
| **Errors** | Error percentage | `rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])` |
| **Duration** | Latency distribution | `histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))` |

---

## USE Method (Infrastructure/Resources)

For every resource (CPU, memory, disk, network, thread pool):

| Metric | Description |
|---|---|
| **Utilisation** | % of time the resource is busy |
| **Saturation** | Amount of queued work (queue depth, backlog) |
| **Errors** | Error rate on the resource |

---

## Metrics Design

### Naming Conventions

```
# Pattern: [namespace]_[subsystem]_[metric_name]_[unit]

# Good examples:
http_server_request_duration_seconds          # histogram; includes unit
http_server_requests_total                    # counter; _total suffix
order_processing_queue_depth                  # gauge; current depth
payment_gateway_calls_total                   # counter
payment_gateway_call_duration_seconds         # histogram
jvm_memory_used_bytes                         # gauge with unit

# Bad examples:
request_latency                               # no unit; no namespace
order_count                                   # ambiguous (gauge? counter? rate?)
```

### Metric Types

| Type | Definition | Use for |
|---|---|---|
| **Counter** | Monotonically increasing; resets on restart | Request count, error count, bytes sent |
| **Gauge** | Point-in-time value; can go up or down | Queue depth, cache size, active connections, CPU% |
| **Histogram** | Samples in configurable buckets; gives p50/p95/p99 | Latency, request size, response size |
| **Summary** | Pre-calculated quantiles on the client | Latency when cardinality is constrained; prefer histograms |

### Cardinality Control

```java
// WRONG: unbounded cardinality — will OOM Prometheus
Counter.builder("orders.processed")
    .tag("customer_id", customerId)    // millions of customers = millions of time series
    .register(registry);

// CORRECT: use only low-cardinality tags
Counter.builder("orders.processed")
    .tag("status", status.name())      // SUBMITTED/CONFIRMED/CANCELLED — finite
    .tag("region", region)             // us-east-1, eu-west-1 — finite
    .tag("order_type", orderType)      // STANDARD/EXPRESS — finite
    .register(registry);
```

**Rule**: every label value combination is a separate time series. Labels should have < 1000 unique values.

### Business Metrics (FAANG expectation)

Beyond infrastructure metrics, instrument business KPIs:

```
order_submission_rate          — orders submitted per second
order_fulfilment_rate          — orders fulfilled per second
payment_authorisation_rate     — payment authorisations per second
payment_decline_rate           — payment declines; segmented by decline reason
checkout_funnel_drop_rate      — % users abandoning at each checkout step
inventory_reservation_failures — stock-outs per minute
```

---

## SLIs, SLOs, and Error Budgets

### Service Level Indicators (SLIs)

An SLI is a quantitative measure of service behaviour:

```
SLI = good events / total events

Examples:
  Availability SLI = successful HTTP responses / total HTTP responses
  Latency SLI      = requests served in < 200ms / total requests
  Freshness SLI    = records updated within 60s / total records
```

### Service Level Objectives (SLOs)

```
SLO = SLI >= threshold over rolling window

Examples (FAANG typical):
  Order submission API:    99.9% of requests succeed, p99 < 500ms, 28-day rolling window
  Payment processing:      99.95% success, p99 < 1s
  Search autocomplete:     99.5% success, p99 < 100ms
  Reporting dashboards:    99.0% success, p99 < 5s
```

### Error Budget

```
Error budget = 1 - SLO

99.9% SLO → 0.1% error budget → 43.8 minutes downtime per 28 days
99.95% SLO → 0.05% → 21.9 minutes per 28 days
99.99% SLO → 0.01% → 4.4 minutes per 28 days

Error budget consumption rate:
  > 2× expected burn rate (fast burn):  page on-call immediately
  > 1.5× expected burn rate (slow burn): alert team (P2 ticket)
  Budget exhausted this window:           freeze all non-essential changes
```

**Multi-window burn rate alerting** (Google SRE recommendation):
- 1-hour window + 5-minute window both burning fast → page (catches acute incidents)
- 6-hour window + 30-minute window both burning moderately → ticket (catches slow degradation)

---

## Distributed Tracing

### Trace Anatomy

```
Trace: checkout flow (trace_id = abc123)
│
├─ Span: POST /orders (orders-service) [0ms → 230ms]
│  ├─ Span: validate order [2ms → 15ms]
│  ├─ Span: reserve inventory (inventory-service) [15ms → 80ms]
│  │   └─ Span: SELECT FROM inventory WHERE product_id = ... [16ms → 20ms]
│  ├─ Span: authorise payment (payment-service) [80ms → 200ms]
│  │   ├─ Span: check fraud score [81ms → 95ms]
│  │   └─ Span: POST stripe.com/charge [95ms → 195ms]  ← external call
│  └─ Span: publish OrderSubmitted event [200ms → 210ms]
```

### OpenTelemetry Instrumentation (Java)

```java
@Service
public class OrderSubmissionService {
    private final Tracer tracer;
    
    public OrderId submitOrder(SubmitOrderCommand command) {
        Span span = tracer.spanBuilder("OrderSubmissionService.submitOrder")
            .setAttribute("order.id", command.orderId().toString())
            .setAttribute("customer.id", command.customerId().toString())
            .startSpan();
        
        try (Scope scope = span.makeCurrent()) {
            Order order = orderRepository.findById(command.orderId())
                .orElseThrow(() -> new OrderNotFoundException(command.orderId()));
            
            order.submit();
            span.setAttribute("order.total_usd", order.total().amount().doubleValue());
            
            orderRepository.save(order);
            eventPublisher.publish(order.pullEvents());
            
            return order.id();
        } catch (Exception e) {
            span.setStatus(StatusCode.ERROR, e.getMessage());
            span.recordException(e);
            throw e;
        } finally {
            span.end();
        }
    }
}
```

### Context Propagation

```java
// Context flows via HTTP headers (W3C TraceContext standard):
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
//            version  trace_id (128-bit)               parent_span_id    flags

// All inter-service HTTP clients must propagate context:
@Bean
public RestTemplate restTemplate() {
    RestTemplate template = new RestTemplate();
    template.setInterceptors(List.of(new TracingInterceptor(tracer)));
    return template;
}
```

---

## Alerting Design

### Alert Quality Standards

**Alert fatigue is the #1 failure mode of monitoring systems**. Every false positive trains on-call engineers to ignore alerts.

| Principle | Rule |
|---|---|
| **Actionable** | Every alert must have a defined response; if you don't know what to do, delete the alert |
| **Customer-impacting** | Alert on SLO breach or SLO burn rate; not on internal metrics that don't affect users |
| **Non-redundant** | One alert per condition; no duplicate alerts from different systems |
| **Correct severity** | P1 = customer-impacting now; P2 = degraded; P3 = heads-up; P4 = backlog |
| **Self-documenting** | Alert message links to runbook; describes expected action |

### Alert Taxonomy

```
P1 (Page immediately — 24/7 on-call):
  - Error rate exceeds SLO error budget burn rate (fast burn)
  - Critical dependency down (payment gateway, auth service)
  - Data pipeline SLA breach

P2 (Page during business hours; wake on-call if unacknowledged after 1 hour overnight):
  - Slow burn SLO degradation
  - Elevated latency (not yet SLO breach but approaching)
  - Queue depth growing (backpressure building)

P3 (Slack notification; no on-call page):
  - Unusual traffic patterns
  - Memory/CPU trending toward threshold
  - Non-critical dependency degraded with fallback active

P4 (Dashboard / weekly review):
  - Resource usage trends
  - Non-critical deprecation warnings
  - Batch job latency increasing (not yet missed SLA)
```

### Runbook Linking

Every P1/P2 alert annotation must include:

```yaml
# Prometheus alerting rule example
groups:
  - name: orders-service
    rules:
      - alert: OrdersHighErrorRate
        expr: |
          rate(http_requests_total{job="orders-service",status=~"5.."}[5m])
          / rate(http_requests_total{job="orders-service"}[5m]) > 0.01
        for: 5m
        labels:
          severity: P2
          team: orders
        annotations:
          summary: "Orders service error rate > 1% for 5 minutes"
          description: "Error rate is {{ $value | humanizePercentage }} on {{ $labels.instance }}"
          runbook_url: "https://runbooks.internal/orders/high-error-rate"
          dashboard_url: "https://grafana.internal/d/orders-overview"
```

---

## Dashboard Design

### Dashboard Hierarchy

```
Level 1: Executive/Business (5 metrics)
  - Order submission rate
  - Payment success rate
  - Active sessions
  - Revenue per minute
  - SLO breach status

Level 2: Service Overview (RED metrics for every service)
  - Request rate, error rate, latency p50/p95/p99 per service
  - Dependency health status

Level 3: Service Deep-Dive (per-service detail)
  - Full histogram, error types, saturation metrics
  - Database connection pool, cache hit rate
  - JVM: heap usage, GC pause time, thread counts

Level 4: Infrastructure
  - Node CPU/memory/disk
  - Kubernetes pod restarts, HPA scaling events
  - Network I/O
```

---

## AWS Observability Stack

### AWS-Native Stack

```
Metrics:    CloudWatch Metrics + CloudWatch Container Insights (ECS/EKS)
Logs:       CloudWatch Logs + CloudWatch Logs Insights for query
Traces:     AWS X-Ray (native), OpenTelemetry Collector → X-Ray exporter
Alerting:   CloudWatch Alarms → SNS → PagerDuty / Slack
Dashboards: CloudWatch Dashboards or Grafana + CloudWatch data source
```

### OpenTelemetry Collector (preferred for vendor-agnostic setup)

```yaml
# otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 1s
    send_batch_size: 1024
  
  resource:
    attributes:
      - action: upsert
        key: deployment.environment
        value: production

exporters:
  prometheus:
    endpoint: "0.0.0.0:8889"
  
  jaeger:
    endpoint: jaeger-collector:14250
    tls:
      insecure: false
  
  awsxray: {}

service:
  pipelines:
    metrics:
      receivers: [otlp]
      processors: [batch, resource]
      exporters: [prometheus]
    traces:
      receivers: [otlp]
      processors: [batch, resource]
      exporters: [jaeger, awsxray]
```

---

## Trade-offs

| Decision | Option A | Option B | Recommendation |
|---|---|---|---|
| **Metrics system** | Prometheus (pull-based) | Datadog (push-based, managed) | Prometheus for full control and cost at scale; Datadog for fast time-to-value and ML anomaly detection |
| **Tracing** | Jaeger (open source) | Honeycomb / Lightstep (commercial) | Jaeger for cost control; Honeycomb for its BubbleUp analysis and wide events approach |
| **Sampling strategy** | Head-based (at ingestion) | Tail-based (after completion) | Tail-based: keeps all error traces and slow traces; head-based misses most interesting traces |
| **Log aggregation** | ELK stack | CloudWatch / Datadog | ELK for control; CloudWatch for simplicity on AWS; Datadog for correlation with metrics/traces |
| **Alert evaluation** | Prometheus Alertmanager | Datadog monitors | Prometheus: flexible; Datadog: easier to configure anomaly detection; both work |

---

## Best Practices Summary

1. **Instrument with OpenTelemetry** — vendor-neutral; one SDK for metrics, logs, traces
2. **Alert on SLO burn rate, not thresholds** — burn rate alerting catches both fast and slow degradations
3. **Every alert must have a runbook link** — on-call engineers must know what to do at 3am
4. **Control metric cardinality** — unbounded labels will OOM your metrics system
5. **Trace every inter-service call** — distributed tracing is the only way to diagnose cross-service latency
6. **Use tail-based sampling** — always keep error traces; sample success traces by volume
7. **Correlate metrics, logs, and traces** — common trace ID and request ID in all three pillars
8. **Build dashboards at three levels** — business/executive, service overview, service deep-dive
9. **Review and prune alerts quarterly** — delete alerts that never fire and those that fire without action
10. **Measure error budget consumption weekly** — the error budget review drives the reliability investment conversation

---

## FAANG Interview Points

**"How do you design an observability system for a microservice platform with 200 services?"**: Two-layer strategy. First layer: standardise instrumentation across all 200 services using OpenTelemetry SDK with a common base configuration — every service automatically emits RED metrics, request traces, and structured logs with the same correlation IDs. This is enforced via a shared service template or sidecar. Second layer: service-specific business metrics on top — each team instruments their key business events in addition to the infrastructure metrics. The correlation layer (same trace ID in metrics, logs, traces) means any incident can be started from a metric alert, correlated to the log, and traced to the root cause span — all three pillars linked.

**"How do you handle alert fatigue when a team's on-call is getting paged 20 times per night?"**: Three steps. Step one: triage all alerts into three buckets — fires and nobody does anything (delete), fires and requires investigation that leads nowhere (tune or delete), fires and requires specific action (keep and improve the runbook). Step two: switch alerting strategy from threshold-based to SLO burn rate — a CPU alert at 80% is meaningless; an SLO error budget consuming at 10× the expected rate means customers are affected now. Step three: establish an alert quality bar — every alert must be customer-impacting and actionable, or it is a P3/P4 notification rather than a page. Measure and report false positive rate monthly as an engineering metric.

**"What's the difference between monitoring and observability, and why does it matter at scale?"**: Monitoring requires knowing in advance what can go wrong — you define metrics, set thresholds, and alert when things cross them. Observability means you can understand any system state by examining its outputs, including states you didn't anticipate. At 10 services, monitoring is sufficient — the failure modes are enumerable. At 200 services with complex distributed interactions, you can't enumerate all failure modes in advance. Observability — high-cardinality metrics, full distributed traces, structured logs with rich context — lets you ask arbitrary questions about system state at investigation time rather than alert-definition time. The shift from monitoring to observability is the shift from "we detect the failures we expected" to "we can understand any failure."
