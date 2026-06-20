# AWS SQS (Simple Queue Service)

## Overview
SQS is a fully managed, durable message queue service. It decouples producers from consumers, absorbs traffic bursts, and enables reliable asynchronous processing. It is the backbone of virtually every event-driven workload on AWS.

**Two queue types**:
| | Standard Queue | FIFO Queue |
|---|---|---|
| **Ordering** | Best-effort (not guaranteed) | Strict FIFO within message group |
| **Delivery** | At-least-once (rare duplicates) | Exactly-once processing (deduplication) |
| **Throughput** | Unlimited | 3,000 msg/s with batching; 300 msg/s without |
| **Cost** | $0.40/million requests | $0.50/million requests |
| **Use when** | High throughput, order doesn't matter | Payments, inventory, ordered workflows |

---

## Architecture & Message Lifecycle

```
Producer → SQS Queue → Consumer polls → Message in-flight (visibility timeout) → Consumer deletes
                                                         ↓ (on failure)
                                              Visibility timeout expires → Message returns to queue
                                              (repeat up to maxReceiveCount) → Dead Letter Queue
```

**Visibility Timeout**: When a consumer receives a message, SQS hides it from other consumers for the visibility timeout duration. Consumer must delete the message before the timeout expires, or the message becomes visible again (retry).

- Default: 30 seconds; range: 0 – 12 hours
- Set slightly longer than your max processing time
- Consumer can extend dynamically via `ChangeMessageVisibility` API

**Long Polling**: Consumers wait up to 20 seconds for messages instead of returning empty immediately. Reduces empty API calls (cost) and latency.
- Always use `WaitTimeSeconds=20` in production — reduces cost by up to 95% vs short polling

---

## Key Configuration Parameters

| Parameter | Default | Recommendation |
|---|---|---|
| `VisibilityTimeout` | 30s | 1.5× your max processing time |
| `MessageRetentionPeriod` | 4 days | 14 days for critical queues; match your SLA |
| `ReceiveMessageWaitTimeSeconds` | 0 (short poll) | **20** (long poll) always |
| `MaximumMessageSize` | 256 KB | Use S3 + Claim Check for larger payloads |
| `DelaySeconds` (queue-level) | 0 | Use for retry backoff (up to 15 min) |
| `MessageGroupId` (FIFO) | — | One per independent entity (order_id, user_id) |
| `MessageDeduplicationId` (FIFO) | — | Hash of message content or business key |
| `maxReceiveCount` (DLQ redrive) | — | Set to 3–5; tune based on transient vs. permanent failures |

---

## Dead Letter Queue (DLQ)

Every SQS queue in production must have a DLQ. No exceptions.

**Configuration**:
```
Source Queue → redrive policy: maxReceiveCount=3, deadLetterTargetArn=arn:...dlq
DLQ: MessageRetentionPeriod=14 days (max)
```

**DLQ alarm** (CloudWatch):
```
Metric: ApproximateNumberOfMessagesVisible on DLQ
Alarm: threshold > 0 → SNS alert to PagerDuty
```

**DLQ redrive** (after fixing the bug): use SQS Console or `start-message-move-task` API to move messages from DLQ back to source queue for reprocessing.

**Separate DLQ per source queue** — never share a DLQ across queues (can't distinguish which queue the message came from without metadata).

---

## Fan-Out Pattern: SNS → SQS

SNS distributes to multiple SQS queues. Each SQS queue is an independent consumer with independent scaling, DLQ, and retry logic.

```
SNS Topic
  ├── SQS Queue (email-notification-consumer)
  ├── SQS Queue (push-notification-consumer)
  ├── SQS Queue (audit-log-consumer)
  └── SQS Queue (analytics-consumer)
```

Each SQS subscription can have an SNS filter policy to receive only a subset of messages.

---

## SQS + Lambda Integration

Lambda's SQS event source mapping is the standard serverless consumer pattern.

**Key settings**:
| Setting | Value | Notes |
|---|---|---|
| `BatchSize` | 1–10,000 | Start at 10; increase for high throughput |
| `MaximumBatchingWindowInSeconds` | 0–300 | Buffer messages before invoking Lambda; reduces invocations |
| `FunctionResponseTypes` | `[ReportBatchItemFailures]` | **Critical**: partial batch failure support |
| Concurrency | Up to 1,000 concurrent Lambdas per queue | Each shard/connection = one Lambda |
| Scaling | Lambda adds 60 pollers/min until max concurrency | Watch for downstream DB connection exhaustion |

**Partial batch failure** (`ReportBatchItemFailures`): Without this, a single failed message in a batch causes the entire batch to be retried, including already-successful messages. With it, Lambda returns only the failed message IDs for retry.

```python
def handler(event, context):
    failures = []
    for record in event['Records']:
        try:
            process(record['body'])
        except Exception:
            failures.append({"itemIdentifier": record['messageId']})
    return {"batchItemFailures": failures}
```

---

## FIFO Queue: Ordering & Deduplication

**Message Group ID**: Messages with the same group ID are delivered in order. Different group IDs process in parallel. Use entity ID (order_id, account_id) as the group ID.

**Deduplication**:
- Content-based: SQS hashes the message body; duplicates within 5-minute window are discarded
- Explicit ID: Producer sets `MessageDeduplicationId`; you control deduplication semantics

**FIFO throughput scaling**:
- Without batching: 300 msg/s per queue (across all groups)
- With batching (batch size 10): 3,000 msg/s
- High throughput mode: 30,000 msg/s (must enable; higher cost)
- For >30,000 msg/s with ordering: shard across multiple FIFO queues by a hash of the entity ID

---

## Use Cases

| Use case | Queue type | Key pattern |
|---|---|---|
| Background job processing (image resize, email send) | Standard | SQS + Lambda or ECS; Competing Consumers |
| Order/payment processing | FIFO | One message group per order; Idempotent consumer |
| Fan-out to multiple processors | Standard | SNS → multiple SQS |
| Rate limiting downstream API calls | Standard | Lambda concurrency limit controls call rate |
| Decoupling microservices during deploy | Standard | Producer keeps running; consumer can be down |
| Priority queue | Standard | Two queues (high/low priority); consumer drains high-priority first |
| Scheduled retries | Standard | DelaySeconds for initial delay; exponential backoff via DLQ redrive |

---

## Monitoring & Alerting

| Metric | Meaning | Alert threshold |
|---|---|---|
| `ApproximateNumberOfMessagesVisible` | Queue depth (unprocessed messages) | > steady-state + 2σ → consumer falling behind |
| `ApproximateAgeOfOldestMessage` | How old is the oldest message | > SLA time (e.g., > 60 seconds for real-time workloads) |
| `NumberOfMessagesSent` | Producer throughput | Sudden drop → producer issue |
| `NumberOfMessagesDeleted` | Consumer throughput | Should track sent; gap means queue growing |
| `ApproximateNumberOfMessagesNotVisible` | In-flight count | Near `maxReceiveCount` → consumers crashing |
| DLQ `ApproximateNumberOfMessagesVisible` | Failed messages | > 0 → immediate alert |
| Lambda `ConcurrentExecutions` | Consumer scaling | Near account limit → provision reserved concurrency |

**Auto-scaling rule (ECS consumers)**:
```
Scale out when: ApproximateNumberOfMessagesVisible / RunningTaskCount > 10
Scale in when: ApproximateNumberOfMessagesVisible / RunningTaskCount < 2
Cooldown: 60s out, 300s in
```

---

## Best Practices

1. **Always configure a DLQ** — without one, poison pill messages loop forever
2. **Use long polling** (`WaitTimeSeconds=20`) — eliminates empty API call costs
3. **Enable `ReportBatchItemFailures`** for Lambda — prevents successful-message re-processing on partial failure
4. **Set `MessageRetentionPeriod` to 14 days** for critical queues — gives recovery time after an outage
5. **Use SG + VPC Endpoint** for SQS — eliminate NAT Gateway in the data path
6. **Separate queues by priority** — don't mix fast (notification) and slow (batch report) on the same queue
7. **Idempotent consumers** — SQS standard delivers at-least-once; always design for duplicate receipt
8. **Monitor queue age, not just depth** — a queue of 1M messages with age < 1 second is healthy; 100 messages aged > 1 hour is an incident
9. **Use FIFO only when ordering is truly required** — standard queues are simpler and unlimited throughput
10. **Access via IAM resource policy** — grant `sqs:SendMessage` and `sqs:ReceiveMessage` with least-privilege

---

## FAANG Interview Points

**"SQS vs Kafka"**: SQS is operationally simpler, fully managed, cheaper at low-to-medium volume. Kafka wins for: replay/rewind capability, event sourcing, high-fan-out (many consumer groups), >3,000 msg/s ordered. SQS has no replay — once consumed and deleted, the message is gone.

**"How do you handle exactly-once processing with SQS?"**: FIFO queue + `MessageDeduplicationId` at the producer + idempotent consumer with DynamoDB conditional write. The deduplication window is 5 minutes; for longer windows, use the DynamoDB idempotency key pattern.

**"Lambda scaling with SQS"**: Lambda scales by adding pollers — up to 60 new concurrent executions per minute until reaching the queue's maximum. If your downstream database can't handle sudden bursts, set Lambda reserved concurrency to cap the scaling. Use `MaximumBatchingWindowInSeconds` to reduce invocation frequency.

**"SQS message size limit"**: 256KB. For larger payloads, use the **Extended Client Library** (Java) or manual Claim Check: write payload to S3, put S3 pointer in SQS message, consumer fetches from S3.
