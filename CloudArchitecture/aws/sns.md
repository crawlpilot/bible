# AWS SNS (Simple Notification Service)

## Overview
SNS is a fully managed pub/sub messaging service for fan-out, notifications, and decoupled event distribution. A single message published to an SNS topic is delivered to all subscribed endpoints simultaneously.

**Core model**: One producer publishes → N subscribers receive independently.

**Supported subscription protocols**:
| Protocol | Use case |
|---|---|
| SQS | Durable fan-out; most common for service-to-service |
| Lambda | Serverless fan-out; no queue buffering |
| HTTP/HTTPS | Webhooks to external services |
| Email / Email-JSON | Human notification; alerts |
| SMS | Mobile alerting (via SNS + Pinpoint for large-scale) |
| Mobile Push (APNS, FCM, ADM) | iOS, Android, Kindle push notifications |
| Firehose | Direct fan-out to S3/Redshift/OpenSearch via Kinesis Data Firehose |

---

## Architecture Patterns

### Standard Fan-Out: SNS → SQS
```
Event Producer
      ↓ Publish
  SNS Topic
  ├── SQS Queue A (service A consumer — with DLQ + retry)
  ├── SQS Queue B (service B consumer — with DLQ + retry)
  └── Lambda C (real-time processor — with DLQ)
```
SNS itself is fire-and-forget (no persistence). The SQS subscriptions add durability. **Never subscribe Lambda directly to SNS for critical workloads** — Lambda invocation failures from SNS have no built-in retry mechanism beyond the SNS retry policy.

### Message Filtering
Each SQS/Lambda/HTTP subscription can define a **filter policy** — only matching messages are delivered to that subscriber. This eliminates the need for consumers to receive and discard irrelevant messages.

```json
// SNS filter policy on a subscription (JSON):
{
  "event_type": ["ORDER_PLACED", "ORDER_CANCELLED"],
  "region": ["us-east-1"],
  "amount": [{"numeric": [">=", 1000]}]
}
```

- Filter on message attributes (not message body — body filtering available via `FilterPolicyScope=MessageBody`)
- Up to 5 filter policy attributes per subscription
- No extra cost for filtering

**Body filtering** (newer feature): filter on JSON fields within the message body itself. Enables content-based routing without adding message attributes.

---

## SNS FIFO Topics

For ordered, deduplicated fan-out. Pairs with SQS FIFO queues only.

| | Standard Topic | FIFO Topic |
|---|---|---|
| Ordering | No | Strict per message group |
| Deduplication | No | Yes (5-minute window) |
| Throughput | 300 publishes/s per account (soft limit) | 300 publishes/s |
| Subscribers | SQS, Lambda, HTTP, Email, SMS, Push | **SQS FIFO only** |
| Use when | Fan-out notifications, high-volume events | Ordered event distribution to multiple services |

---

## Key Configuration Parameters

| Parameter | Default | Recommendation |
|---|---|---|
| `MessageRetentionPeriod` | N/A (SNS doesn't store) | Add SQS subscribers for durability |
| Delivery retry policy | 3 retries immediately, then exponential (20 attempts total over 23 days for HTTP) | Tune per subscriber protocol |
| Dead-letter queue for subscription | Not configured | Always configure subscription-level DLQ for Lambda/HTTP subscribers |
| Encryption (SSE) | Disabled | Enable KMS encryption for sensitive topics |
| Access policy | Deny all | Least-privilege: only named IAM roles/accounts can publish |
| `RawMessageDelivery` | false | Set to **true** for SQS subscribers to avoid SNS envelope wrapping |
| Cross-account publishing | Via resource policy | Allow specific account IDs; restrict to VPC endpoint |

**Raw message delivery**: By default, SNS wraps the message in a JSON envelope with metadata. Set `RawMessageDelivery=true` on SQS subscriptions to deliver the raw message body directly — simplifies consumers.

---

## SNS vs EventBridge: When to Use Each

| Dimension | SNS | EventBridge |
|---|---|---|
| **Subscriber types** | SQS, Lambda, HTTP, SMS, Push | 20+ AWS services + SQS + Lambda + API destinations |
| **Content-based routing** | Attribute filtering only | Full JSON rule matching on body |
| **Schema registry** | No | Yes — EventBridge Schema Registry |
| **Event archives + replay** | No | Yes — archive and replay any event |
| **Event bus types** | Single topic model | Default bus, custom buses, partner event buses |
| **Cross-account delivery** | Via SQS subscription | Native cross-account bus |
| **Throughput** | Very high | 10,000 events/s per bus (soft limit) |
| **Latency** | Sub-second | ~500ms typical |
| **Cost** | $0.50/million publishes | $1.00/million events |
| **Use when** | Simple fan-out; very high throughput; mobile push | Complex routing rules; AWS service integration; schema evolution |

**Rule**: Use SNS for high-volume simple fan-out (100K+ msg/s). Use EventBridge for event-driven architectures where you need rule-based routing, replay, and schema registry.

---

## Mobile Push Architecture

SNS supports direct mobile push to iOS (APNS), Android (FCM), Windows (WNS), and Kindle (ADM).

```
Backend → SNS Platform Application
              ├── Device Token Registry (per device endpoint ARN)
              └── Publish to endpoint ARN → APNS/FCM → Device

For broadcast to all devices:
Backend → SNS Topic (subscribed by all device endpoint ARNs) → all devices
```

**At scale (100M+ devices)**:
- Use SNS `CreatePlatformEndpoint` + `SetEndpointAttributes` to manage device token rotation
- Handle `EndpointDisabled` errors — device token changed or app uninstalled
- Use SNS + Pinpoint for advanced segmentation, analytics, A/B testing on push campaigns
- Throughput limit: 10 million push/second (SNS + FCM combined)

---

## Use Cases

| Use case | Pattern |
|---|---|
| Microservice event fan-out | SNS → multiple SQS queues (each with DLQ) |
| User notification (email + push + SMS) | SNS → 3 separate Lambda/SQS per channel |
| Broadcast to filtered audiences | SNS FIFO + filter policies per subscription |
| CloudWatch alarm notification | CloudWatch → SNS → PagerDuty/Slack via HTTP subscription |
| Cross-account event delivery | SNS resource policy allows account B to subscribe |
| High-throughput event distribution | SNS → Kinesis Firehose subscription (direct to S3) |
| Transactional SMS | SNS SMS with Sender ID and dedicated origination number |

---

## Monitoring & Alerting

| Metric | Meaning | Alert condition |
|---|---|---|
| `NumberOfMessagesPublished` | Producer throughput | Sudden drop → producer issue |
| `NumberOfNotificationsDelivered` | Successful deliveries | Should track published |
| `NumberOfNotificationsFailed` | Failed deliveries | > 0 for SQS/Lambda → investigate subscription |
| `NumberOfNotificationsFilteredOut` | Filtered by policy | Useful for debugging filter rules |
| `SMSSuccessRate` | SMS delivery rate | < 95% → carrier issue or invalid numbers |
| Subscription DLQ `ApproximateNumberOfMessagesVisible` | Failed deliveries | > 0 → alert |

**Enable delivery status logging** on Lambda/SQS/HTTP subscriptions — logs every delivery outcome to CloudWatch Logs.

---

## Best Practices

1. **Add SQS between SNS and Lambda** for critical paths — SQS adds durability, retry, and DLQ. Direct SNS→Lambda has limited retry (3 attempts for async invocations).
2. **Configure subscription-level DLQ** for all HTTP and Lambda subscriptions
3. **Use filter policies** to reduce consumer load — don't make consumers filter themselves
4. **Enable `RawMessageDelivery`** for SQS subscribers unless you need the SNS metadata envelope
5. **Encrypt topics with KMS** for any message containing PII, financial, or health data
6. **Restrict topic access via resource policy** — never allow `sns:Publish` from `*` (anyone)
7. **Use VPC endpoint for SNS** — eliminates NAT Gateway in the publish path
8. **Use SNS FIFO + SQS FIFO for ordered fan-out** — standard SNS does not guarantee order
9. **Monitor `NumberOfNotificationsFailed`** — SNS silently drops messages if subscribers are unreachable
10. **For mobile push at scale**, manage device token lifecycle: rotate on re-install, disable on uninstall

---

## FAANG Interview Points

**"SNS vs SQS"**: SNS is push-based pub/sub (N subscribers, concurrent delivery, no persistence). SQS is pull-based queue (one consumer wins, persistent, retry). They are complementary, not competing — the canonical pattern is SNS + SQS.

**"How do you fan-out a payment event to 10 services?"**: SNS topic → 10 SQS queues (one per service). Each SQS has its own DLQ, retry policy, and consumer scaling. SNS filter policies ensure each service only receives relevant subtypes.

**"How would you send a notification to 50M mobile users?"**: SNS Platform Application (store device endpoints) + SNS Topic with all endpoints subscribed for broadcast, or SNS + Pinpoint for segmented campaigns. Throttle publishes to respect FCM/APNS rate limits; handle EndpointDisabled callbacks.

**"What happens if an SNS subscriber is unavailable?"**: For HTTP: SNS retries with exponential backoff for up to 23 days. For SQS: SQS is durable — message waits in queue. For Lambda: 3 async retry attempts, then optional DLQ. For email/SMS: best effort, no retry guarantees.
