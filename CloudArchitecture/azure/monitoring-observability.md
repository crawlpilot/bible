# Azure Monitoring & Observability — Azure Monitor, Application Insights, Log Analytics

**AWS Equivalents**:  
- Azure Monitor → Amazon CloudWatch (umbrella service)  
- Azure Monitor Metrics → Amazon CloudWatch Metrics  
- Azure Monitor Logs (Log Analytics) → Amazon CloudWatch Logs + CloudWatch Logs Insights  
- Application Insights → AWS X-Ray + CloudWatch Application Insights  
- Azure Monitor Alerts → Amazon CloudWatch Alarms + SNS  
- Azure Dashboards → Amazon CloudWatch Dashboards  
- Azure Workbooks → Amazon CloudWatch Dashboards (richer)  

**Mental model**: Azure Monitor is the umbrella service for all observability, equivalent to CloudWatch. Within it: Log Analytics is the log storage and query engine (CloudWatch Logs + Insights), and Application Insights is the APM layer (X-Ray + Application Performance Monitoring). The key differentiator: Log Analytics uses KQL (Kusto Query Language), which is significantly more powerful than CloudWatch Logs Insights' query language.

---

## Azure Monitor Architecture

```
Data Sources                  Azure Monitor                    Consumption
──────────────         ─────────────────────────         ──────────────────
VMs, AKS, Functions  →  Metrics (time-series)      →   Dashboards / Alerts
App Insights SDK     →  Logs (Log Analytics WS)    →   Workbooks / Queries
Activity Logs        →  Traces (App Insights)      →   Alerts / KQL queries
Diagnostic Settings  →  Distributed traces         →   Azure Workbooks
Azure services       →  Change tracking            →   Power BI
External (Prometheus)→                             →   Grafana (native integration)
```

---

## 1. Azure Monitor Metrics

### What It Is

Time-series metrics store. 93-day retention, sub-minute granularity for most services.

**vs CloudWatch Metrics**:

| Feature | Azure Monitor Metrics | CloudWatch Metrics |
|---------|----------------------|-------------------|
| Retention | 93 days | 15 months (1-min for 15d, then aggregated) |
| Resolution | 1-minute (most services) | 1-minute standard, 1-second high-resolution |
| Dimensions | Yes (filter/split by dimension) | Yes (dimensions) |
| Custom metrics | Yes (via REST API, SDK, Prometheus) | Yes (PutMetricData API) |
| Prometheus scraping | **Native (Azure Managed Prometheus)** | Via CloudWatch agent |
| Multi-dimensional queries | Yes | Yes |
| Metric Math | Yes | Yes (metric math) |
| Cost for custom metrics | First 10 metrics free, then per metric/month | $0.30/metric/month standard |

**Azure Managed Prometheus**: Fully managed Prometheus-compatible endpoint for Kubernetes metrics. Integrates with Azure Managed Grafana. CloudWatch equivalent: CloudWatch Container Insights (different paradigm, not Prometheus-compatible natively).

### Metric Alerts

```
Alert Rule:
  Condition: Average CPU > 80% for 5 minutes
  Frequency: Evaluate every 1 minute
  Action Group:
    ├── Email: ops-team@company.com
    ├── SMS: +1-555-0100
    ├── Azure Function: auto-scale trigger
    └── Webhook: PagerDuty integration

Severity: 1 (Critical), 2 (Error), 3 (Warning), 4 (Informational)
```

**Alert dimensions**: Alert on metric split by dimension (e.g., CPU per AKS node, HTTP 5xx per API endpoint).

---

## 2. Log Analytics (Azure Monitor Logs)

### What It Is

Centralized log storage and query engine. All Azure service diagnostic logs, VM logs, and application logs land here. Queried with KQL.

**vs CloudWatch Logs**:

| Feature | Log Analytics | CloudWatch Logs |
|---------|--------------|----------------|
| Query language | **KQL (Kusto)** — very powerful | CloudWatch Logs Insights — simpler |
| Log retention | 30 days (interactive), 7 years (archive) | 1 day – 10 years (configurable) |
| Log export | Diagnostic Settings → Storage / Event Hubs / Log Analytics | Export to S3 |
| Multi-workspace query | Yes (cross-workspace queries) | Limited (cross-log group with Log Insights) |
| Alerts from logs | Yes (Log Alert rules) | Yes (Metric Filters + Alarms) |
| Live tail | Log Analytics Live Tail | CloudWatch Logs Live Tail |
| Structured logging | JSON fields auto-parsed | JSON parsing in Insights queries |
| Cost model | Per GB ingested + retention | Per GB ingested + stored |
| Grafana integration | Native (Azure Data Source) | Via CloudWatch plugin |

### KQL Quick Reference

KQL is the most important Azure observability skill to demonstrate in interviews.

```kusto
// Basic query: last 24h errors in a Function App
FunctionAppLogs
| where TimeGenerated > ago(24h)
| where Level == "Error"
| project TimeGenerated, FunctionName, Message, ExceptionDetails

// Aggregation: error rate per hour
requests
| where timestamp > ago(7d)
| summarize 
    total = count(),
    errors = countif(success == false)
    by bin(timestamp, 1h)
| extend error_rate = 100.0 * errors / total
| render timechart

// Join: correlate requests with dependencies
requests
| where timestamp > ago(1h) and success == false
| join kind=inner dependencies on operation_Id
| project timestamp, name, duration, dependencyType, dependencyTarget

// Top N: slowest endpoints by P95 latency
requests
| where timestamp > ago(24h)
| summarize p95 = percentile(duration, 95) by name
| top 10 by p95 desc

// Parse JSON in log message
AppTraces
| extend parsed = parse_json(Message)
| where parsed.userId == "user-12345"
| project timestamp, parsed.action, parsed.latencyMs
```

**vs CloudWatch Logs Insights syntax**:
```
# CloudWatch Logs Insights equivalent
fields @timestamp, @message
| filter @message like /ERROR/
| stats count() as error_count by bin(1h)
| sort error_count desc
```

KQL has significantly richer join, aggregation, and rendering capabilities than CloudWatch Logs Insights.

### Workspace Design

**Single workspace** (recommended for most): Centralize all logs from all resources in one workspace. Simplifies KQL queries (join across services) and cost management.

**Multi-workspace** use cases:
- Separate workspaces per region (data sovereignty)
- Separate workspaces per team (billing isolation, RBAC control)

```
Log Analytics Workspace: prod-logs-eastus
├── AKS diagnostic logs
├── Azure SQL audit logs
├── Application Insights (linked)
├── VM performance counters
├── Azure Activity Log
└── Custom application logs
```

---

## 3. Application Insights

### What It Is

APM (Application Performance Monitoring) integrated with Log Analytics. Tracks requests, dependencies, exceptions, page views, custom events, and distributed traces.

**Two deployment modes**:
1. **SDK-based**: Add Application Insights SDK to your app code. Auto-instruments .NET, Java, Node.js, Python.
2. **Auto-instrumentation**: Enabled on Azure App Service / AKS without code changes (agent injection).

### What Application Insights Collects

| Data Type | Description | AWS X-Ray Equivalent |
|-----------|-------------|---------------------|
| **Requests** | Incoming HTTP requests (URL, duration, response code) | Segments |
| **Dependencies** | Outgoing calls (SQL, HTTP, Service Bus, Redis) | Subsegments |
| **Exceptions** | Unhandled exceptions with stack traces | Exception metadata |
| **Traces** | Application logs correlated to requests | Log groups (separate in X-Ray) |
| **Custom Events** | Business events (`telemetryClient.trackEvent()`) | Custom metadata in annotations |
| **Custom Metrics** | Business metrics (`telemetryClient.trackMetric()`) | Custom metrics (separate CloudWatch call) |
| **Page Views** | Browser telemetry (JavaScript SDK) | CloudWatch RUM |
| **Availability** | Synthetic probes to URLs (ping tests) | CloudWatch Synthetics |

### Application Map

Visual dependency map auto-generated from distributed traces:

```
Browser → Web App → SQL Database
                 → Redis Cache
                 → Payment API → Stripe
                             → Bank API (slow! 3.2s p95 highlighted in red)
```

**AWS X-Ray Service Map** is the equivalent — same visual concept, different UI and data model.

### Application Insights vs AWS X-Ray

| Feature | Application Insights | AWS X-Ray |
|---------|---------------------|-----------|
| Distributed tracing | Yes (W3C TraceContext) | Yes (X-Ray trace format) |
| Auto-instrumentation | .NET, Java, Node, Python | Java, Node, Python (via SDK) |
| Sampling | Adaptive sampling (auto) | Fixed rate or reservoir sampling |
| SQL query capture | **Yes** (full SQL text, obfuscated) | Yes |
| Log correlation | Native (same workspace) | Manual (CloudWatch Logs) |
| Custom events | `trackEvent()` / `trackMetric()` | `putAnnotations()` / `putMetadata()` |
| Retention | 90 days (default), configurable | 30 days |
| Analytics query language | KQL | X-Ray Analytics (limited) |
| Live Metrics Stream | **Yes** (real-time, 1-second refresh) | No equivalent |
| Cost | Per GB ingested | $5/million traces recorded |
| Browser tracking | Yes (JavaScript SDK) | No (CloudWatch RUM is separate) |

**Live Metrics Stream**: Real-time view of requests, failures, dependencies, and server health — useful during deployments to watch for regressions. No AWS equivalent at this level of integration.

### Smart Detection (Anomaly Detection)

Application Insights automatically detects anomalies and sends proactive alerts:
- **Failure Anomalies**: Unusual rise in failed requests or dependency failures
- **Performance Anomalies**: Degradation in response time compared to baseline
- **Trace Severity Volume**: Unusual spike in error traces

**vs CloudWatch Anomaly Detection**: CloudWatch has metric-level anomaly detection via ML bands. Application Insights is request/trace-aware — understands HTTP semantics.

### Sampling

To control ingestion cost, Application Insights samples telemetry:

| Sampling Type | How It Works | When to Use |
|--------------|-------------|------------|
| **Adaptive sampling** | Auto-adjusts rate to stay under target throughput | Default — recommended |
| **Fixed-rate sampling** | Sample X% of all telemetry | Predictable volume |
| **Ingestion sampling** | Applied after data sent — at Log Analytics ingestion | Cost control without SDK changes |

**AWS X-Ray**: Fixed rate + reservoir sampling. No adaptive equivalent.

---

## 4. Azure Monitor Dashboards and Workbooks

### Azure Dashboards (Quick Sharing)

Basic: pin metrics charts and Log Analytics queries to a shared dashboard. CloudWatch Dashboards equivalent.

### Azure Workbooks (Rich Analysis)

Interactive reports combining metrics, queries, text, and parameters. More powerful than CloudWatch Dashboards — closer to Grafana notebooks or Jupyter + CloudWatch.

```
Workbook: API Health Report
├── Time range parameter (dropdown: 1h, 6h, 24h, 7d)
├── Metrics section: Request rate + Error rate (time charts)
├── Log section: KQL query for top error messages (table)
├── Dependency section: P95 latency per downstream service (bar chart)
└── Availability section: Synthetic test results (map)
```

### Azure Managed Grafana

Fully managed Grafana. Native data sources:
- Azure Monitor (metrics + logs)
- Azure Data Explorer
- Prometheus (via Azure Managed Prometheus)
- Azure Managed InfluxDB

**vs AWS Managed Grafana**: Both are managed Grafana. AWS supports CloudWatch, Prometheus, X-Ray as data sources. Azure supports Azure Monitor, Prometheus, ADX — better integration with Azure services.

---

## Observability Stack Reference

### Full Azure Observability Stack

```
Instrumentation:
  App → Application Insights SDK
  K8s → Azure Managed Prometheus + Container Insights
  Infra → Azure Monitor Agent (on VMs)
  Azure services → Diagnostic Settings → Log Analytics

Storage:
  Metrics → Azure Monitor Metrics (93 days)
  Logs → Log Analytics Workspace (30 days interactive, 7 years archive)
  Traces → Application Insights (90 days)

Visualization:
  Ad-hoc → Log Analytics KQL queries
  Dashboards → Azure Managed Grafana (Prometheus) + Azure Workbooks (KQL)
  Alerts → Azure Monitor Alerts → Action Groups (email/SMS/PagerDuty/webhook)

SLO Tracking:
  Azure Monitor SLO feature (GA 2024) or custom KQL + Workbooks
```

### AWS Equivalent Stack

```
Instrumentation:
  App → AWS X-Ray SDK
  K8s → CloudWatch Container Insights
  Infra → CloudWatch Agent (on EC2)
  AWS services → CloudWatch Logs (automatic)

Storage:
  Metrics → CloudWatch Metrics (15 months)
  Logs → CloudWatch Logs (configurable)
  Traces → X-Ray (30 days)

Visualization:
  Ad-hoc → CloudWatch Logs Insights
  Dashboards → AWS Managed Grafana / CloudWatch Dashboards
  Alerts → CloudWatch Alarms → SNS → Lambda/PagerDuty

SLO Tracking:
  CloudWatch Application Signals (SLO feature, GA 2024)
```

---

## Key Numbers for Interviews

| Service | Number | Notes |
|---------|--------|-------|
| Log Analytics retention (interactive) | 30 days | Default; configurable up to 730 days |
| Log Analytics retention (archive) | 7 years | Compressed archive, query with Restore |
| Application Insights retention | 90 days | Default; configurable up to 730 days |
| Azure Monitor Metrics retention | 93 days | After which metrics are purged |
| Log Analytics max query result | 30,000 rows | Use summarize to avoid hitting this |
| Application Insights sampling default | Adaptive (targets ~5 items/second) | Adjust for high-traffic apps |
| Managed Prometheus retention | 18 months | Longer than self-hosted typical default |
| Action Group max actions | 10 (email), 10 (SMS), 10 (webhooks) | Per action group |
| Log Analytics ingestion SLA | 5 minutes | p95 data availability after ingestion |

---

> **FAANG Interview Callout**: "When designing observability for a distributed system on Azure, I follow the three pillars — metrics in Azure Monitor (for alerts and dashboards), logs in Log Analytics (for root-cause analysis with KQL), and traces in Application Insights (for distributed request tracing). The capability I highlight most is KQL: being able to do multi-table joins, percentile calculations, and time-series rendering in a single query is a 10× productivity gain over CloudWatch Logs Insights syntax. For alerting strategy, I use metrics alerts for high-frequency conditions (CPU, memory, RPS) because they evaluate faster and cheaper than log-based alerts, and save log-based alerts for business-logic conditions (specific error patterns, SLA breach indicators) that don't exist as pre-built metrics."
