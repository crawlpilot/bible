# AWS CloudWatch

## Overview
CloudWatch is AWS's observability platform — metrics, logs, alarms, dashboards, events, and synthetic monitoring in a single service. For principal engineers, CloudWatch is not just "the place where alarms live" — it is the operational lens through which the health of every production system is understood and managed.

**Five pillars**:
| Pillar | Service component | Purpose |
|---|---|---|
| Metrics | CloudWatch Metrics | Time-series numerical data from AWS services and applications |
| Logs | CloudWatch Logs | Structured and unstructured log ingestion, storage, querying |
| Alarms | CloudWatch Alarms | Threshold-based and anomaly detection alerts |
| Events/Scheduling | EventBridge (originally CloudWatch Events) | Event routing and cron-based triggers |
| Dashboards | CloudWatch Dashboards | Real-time operational visualisation |
| Synthetics | CloudWatch Synthetics | Canary scripts for endpoint monitoring |
| Service Lens | CloudWatch ServiceLens | Distributed tracing + metrics + logs unified view |
| Container Insights | CloudWatch Container Insights | ECS/EKS container-level metrics |

---

## CloudWatch Metrics

### Namespaces and Dimensions
Every AWS service publishes metrics under a namespace (`AWS/EC2`, `AWS/Lambda`, `AWS/SQS`). Custom application metrics go under a custom namespace (`MyApp/Payments`).

Dimensions are key-value filters: e.g., `InstanceId=i-xxxx`, `QueueName=orders-queue`.

### Resolution
- **Standard resolution**: 1-minute granularity; stored for 63 days
- **High resolution**: 1-second granularity (custom metrics only); stored for 3 hours then rolled up

### Custom Metrics
```python
import boto3
cloudwatch = boto3.client('cloudwatch')
cloudwatch.put_metric_data(
    Namespace='MyApp/Payments',
    MetricData=[{
        'MetricName': 'PaymentProcessingLatency',
        'Dimensions': [{'Name': 'Environment', 'Value': 'prod'}],
        'Value': 245.3,
        'Unit': 'Milliseconds',
        'StorageResolution': 1  # 1-second resolution
    }]
)
```

**Custom metric cost**: $0.30/metric/month for first 10,000; $0.01/1,000 API calls for PutMetricData. For high-volume applications, use **CloudWatch EMF (Embedded Metric Format)** — write structured JSON to stdout from Lambda/ECS; CloudWatch extracts metrics automatically from logs (no PutMetricData API calls).

### EMF (Embedded Metric Format)
```json
{
  "_aws": {
    "Timestamp": 1615233050000,
    "CloudWatchMetrics": [{
      "Namespace": "MyApp/Payments",
      "Dimensions": [["PaymentMethod"]],
      "Metrics": [{"Name": "ProcessingTime", "Unit": "Milliseconds"}]
    }]
  },
  "PaymentMethod": "credit_card",
  "ProcessingTime": 142
}
```
Lambda and ECS output EMF to stdout → CloudWatch Logs picks it up → automatically extracts the metric. Zero API call overhead. Standard CloudWatch Logs pricing applies.

---

## CloudWatch Logs

### Log Groups and Retention
- Every application should write to a named log group: `/aws/lambda/function-name`, `/app/payments/api`
- **Set retention on every log group** — default is Never Expire (perpetual cost). Set 7–90 days for app logs, 1 year for audit/compliance logs.

### Structured Logging
Write JSON logs. CloudWatch Logs Insights can query any JSON field:
```json
{"timestamp": "2024-01-15T10:00:00Z", "level": "ERROR", "service": "payments", "user_id": "u123", "error": "InsufficientFunds", "latency_ms": 342}
```

### CloudWatch Logs Insights — Query Language
```sql
-- Find slowest requests in the last 1 hour
fields @timestamp, service, latency_ms, user_id
| filter level = "ERROR"
| filter service = "payments"
| sort latency_ms desc
| limit 20

-- P99 latency per service
stats pct(latency_ms, 99) as p99, count(*) as requests by service
| sort p99 desc

-- Error rate over time
filter level = "ERROR"
| stats count(*) as errors by bin(5m)
```

**Key Insights functions**: `stats`, `filter`, `sort`, `limit`, `fields`, `parse` (regex extraction), `pct()`, `avg()`, `count()`, `bin()`.

### Log Subscriptions
Forward logs to Lambda, Kinesis Data Streams, or Firehose in near-real-time:
- **Lambda subscription filter**: real-time processing, alerting, or routing
- **Firehose subscription filter**: archive logs to S3 for long-term storage at scale (VPC Flow Logs, CloudTrail, ALB access logs)

### Contributor Insights
Automatically identifies top contributors to metrics — e.g., "which user_id is generating the most 5xx errors?", "which endpoint has the highest latency?" Uses rule-based sampling, not full log scanning.

---

## CloudWatch Alarms

### Alarm States
- **OK**: metric within threshold
- **ALARM**: metric breached threshold
- **INSUFFICIENT_DATA**: not enough data points to evaluate

### Alarm Types

**Static threshold alarm**:
```json
{
  "MetricName": "ApproximateAgeOfOldestMessage",
  "Namespace": "AWS/SQS",
  "Threshold": 300,
  "ComparisonOperator": "GreaterThanThreshold",
  "EvaluationPeriods": 2,
  "Period": 60,
  "Statistic": "Maximum",
  "TreatMissingData": "notBreaching"
}
```

**Anomaly detection alarm**: CloudWatch learns the metric's baseline using ML (seasonality, trends). Alarm fires when the metric deviates beyond a band.
```
Band width = 2 standard deviations of historical data (configurable)
Good for: request rates, latency — where absolute thresholds are hard to set
```

**Composite alarm**: combine multiple alarms with AND/OR logic:
```
PaymentService_Degraded = (HighErrorRate OR HighLatency) AND NOT Maintenance_Mode
```
Reduces alert fatigue; a single pager notification for "service degraded" rather than 5 separate alarms.

**Metric Math alarm**: apply formulas to metrics before comparing:
```
Error rate = (5xx_count / total_request_count) * 100
Alarm: error_rate > 5
```

### Alarm Actions
| Action | Use case |
|---|---|
| SNS notification → PagerDuty/Slack | On-call alerting |
| Auto Scaling policy | Scale EC2 ASG or ECS service |
| Lambda invocation | Custom remediation (restart task, update DNS) |
| EC2 recover/stop/terminate | Self-healing instances |
| SSM Automation | Run Systems Manager runbooks on alarm |

---

## Dashboards

Best practices for operational dashboards:
1. **Service health dashboard** (top-level): request rate, error rate, latency P50/P95/P99, saturation (CPU, memory)
2. **Service-level dashboard**: break down by endpoint, by region, by customer tier
3. **Infrastructure dashboard**: per-instance/task metrics, auto-scaling events, deployment markers
4. **Business dashboard**: orders/minute, payment success rate, revenue — tie technical metrics to business impact

**Dashboard annotations**: mark deployments with vertical lines (`PutDashboard` annotation). Make it easy to correlate "error spike at 14:23" with "deploy of version 3.14 at 14:20".

**Cross-account dashboards**: aggregate metrics from multiple accounts into a single dashboard via CloudWatch cross-account observability.

---

## CloudWatch Synthetics (Canaries)

Scriptable canaries that simulate user interactions on a schedule:
- **Heartbeat monitor**: HTTP GET to endpoint, check status code and latency
- **API canary**: sequence of HTTP calls simulating a user flow (login → search → checkout)
- **Broken link checker**: crawl a web page and verify all links return 200
- **Visual monitoring**: screenshot comparison against baseline

```javascript
// Heartbeat canary example
const { URL } = require('url');
const synthetics = require('Synthetics');
const apiCanaryBlueprint = async function () {
  await synthetics.executeHttpStep('Verify payments API', {
    hostname: 'api.example.com',
    protocol: 'https:',
    path: '/health',
    method: 'GET'
  });
};
exports.handler = async () => { return await apiCanaryBlueprint(); };
```

Canaries run from a different VPC than your application — they detect external availability even when internal monitoring shows healthy.

---

## Container Insights (ECS/EKS)

Provides CPU, memory, disk, network metrics at the container, task, service, and cluster level.

**ECS**: enable Container Insights per cluster (console or `aws ecs update-cluster-settings`)
**EKS**: deploy CloudWatch agent + Fluent Bit daemonset via AWS add-on

Key metrics:
- `pod_cpu_utilization` / `pod_memory_utilization` (EKS) — set HPA thresholds
- `service_number_of_running_tasks` (ECS) — scaling decisions
- `cluster_failed_node_count` — node health
- `node_cpu_utilization` — cluster-level saturation

---

## X-Ray Integration (ServiceLens)

CloudWatch ServiceLens integrates X-Ray traces with metrics and logs for end-to-end request tracing.

- Enable X-Ray on Lambda, ECS tasks, API Gateway, App Mesh sidecars
- Service map: visual topology of all services and their error/latency relationships
- Trace: drill from a CloudWatch alarm into specific request traces
- Insights: X-Ray automatically identifies anomalies in trace groups

---

## Key Metrics to Monitor (Per Service)

| Service | Critical metrics |
|---|---|
| **API Gateway** | `5XXError`, `4XXError`, `Latency` P99, `Count` |
| **Lambda** | `Errors`, `Duration` P99, `Throttles`, `ConcurrentExecutions` |
| **SQS** | `ApproximateAgeOfOldestMessage`, DLQ `ApproximateNumberOfMessagesVisible` |
| **RDS** | `CPUUtilization`, `DatabaseConnections`, `FreeStorageSpace`, `ReadLatency` |
| **ElastiCache** | `CacheHits`, `CacheMisses`, `CurrConnections`, `Evictions` |
| **ECS/EKS** | `CPUUtilization`, `MemoryUtilization`, running task count |
| **ALB** | `HTTPCode_Target_5XX_Count`, `TargetResponseTime`, `UnHealthyHostCount` |
| **Kinesis** | `GetRecords.IteratorAgeMilliseconds`, `WriteProvisionedThroughputExceeded` |
| **DynamoDB** | `ConsumedReadCapacityUnits`, `ThrottledRequests`, `SystemErrors` |

---

## Best Practices

1. **Set retention on all log groups** — unset retention defaults to infinite, silently accumulating cost
2. **Use structured (JSON) logging** — enables powerful Logs Insights queries without regex parsing
3. **Use EMF for custom metrics from Lambda/ECS** — no extra API calls, no extra cost beyond logs
4. **Use composite alarms** to reduce alert fatigue — one "service degraded" alarm beats five individual metric alarms paging on-call
5. **Use anomaly detection** for metrics with natural variation (request rate, latency) — better than static thresholds
6. **Mark deployments in dashboards** — correlate every metric spike with the code change that caused it
7. **Set up synthetic canaries** for critical user flows — detect external availability before users do
8. **Enable Container Insights** for every ECS/EKS cluster
9. **Use CloudWatch cross-account observability** for multi-account visibility from a central monitoring account
10. **Archive logs to S3 via Firehose subscription** for long-term retention at 10× lower cost than CloudWatch Logs

---

## FAANG Interview Points

**"How would you monitor a payment processing service?"**: Four golden signals (latency, traffic, errors, saturation) as CloudWatch alarms. Custom metric: payment_success_rate (EMF). Composite alarm: (error_rate > 5% OR p99_latency > 1s) AND NOT deployment_in_progress → PagerDuty. X-Ray tracing for every payment request. Synthetic canary: full checkout flow every 60 seconds.

**"How do you find which user is causing 90% of 5xx errors?"**: CloudWatch Logs Insights query: `filter status = 500 | stats count(*) as errors by user_id | sort errors desc | limit 10`. Or enable Contributor Insights on the log group with a rule targeting `user_id` — auto-populates top contributors continuously.

**"CloudWatch vs Datadog"**: CloudWatch is AWS-native, no agent needed for AWS services, tightly integrated with alarms/scaling/SSM. Datadog has richer APM, better multi-cloud, more integrations, and superior UX for distributed tracing. Large FAANG shops typically use CloudWatch for infrastructure metrics and a vendor (Datadog/Grafana) for APM and correlation. Don't frame it as OR — frame it as CloudWatch for AWS-native metrics, Datadog/Grafana for cross-cloud and APM.
