# Azure Messaging — Service Bus, Event Grid, Event Hubs

**AWS Equivalents**:  
- Azure Service Bus Queues → Amazon SQS  
- Azure Service Bus Topics → Amazon SNS  
- Azure Event Grid → Amazon EventBridge  
- Azure Event Hubs → Amazon Kinesis Data Streams / Amazon MSK  

**Mental model**: Azure has three messaging services with distinct guarantees. Service Bus = reliable enterprise messaging (transactions, dead-letter, sessions). Event Grid = lightweight event notification (push, serverless). Event Hubs = high-throughput event streaming (Kafka-compatible).

---

## AWS ↔ Azure Messaging Map

| Use Case | AWS | Azure | Key Difference |
|----------|-----|-------|----------------|
| Work queue (at-least-once delivery) | SQS Standard | Service Bus Queue | Service Bus adds sessions, dead-letter queue, duplicate detection |
| Ordered queue (FIFO) | SQS FIFO | Service Bus Queue with sessions | Both guarantee per-group ordering |
| Pub/sub fan-out | SNS | Service Bus Topics | Service Bus Topics support SQL-based subscription filters |
| Event-driven integration | EventBridge | Event Grid | Event Grid is push-only; EventBridge has richer routing and schema registry |
| Event streaming (high throughput) | Kinesis Data Streams | Event Hubs | Event Hubs is Kafka-protocol compatible — same client library |
| Managed Kafka | Amazon MSK | Event Hubs (Kafka surface) | Event Hubs = managed Kafka without cluster ops |
| Dead-letter handling | SQS DLQ | Service Bus Dead-Letter Sub-Queue | Both native; Service Bus has richer dead-letter reasons |
| Message scheduling | SQS (delay up to 15 min) | Service Bus (schedule to any future time) | Service Bus has arbitrary future scheduling |

---

## 1. Azure Service Bus

### What It Is

Enterprise message broker supporting queues and topics with transactional delivery guarantees. The equivalent of SQS + MQ + partially SNS.

**Tiers**:

| Tier | Max Message Size | Features |
|------|-----------------|---------|
| **Standard** | 256 KB | Queues, Topics, shared infrastructure |
| **Premium** | 100 MB | Dedicated resources, VNet, geo-recovery, large messages |

### Queues

**Key properties**:

| Property | Default | Max | Notes |
|----------|---------|-----|-------|
| Lock duration (visibility timeout) | 60s | 5 min | Extend with `RenewMessageLockAsync()` |
| Max delivery count | 10 | 2,000 | After max, moves to Dead-Letter Queue |
| Message TTL | 14 days | Unlimited | Messages expire if not consumed |
| Max queue size | 1 GB | 80 GB (Premium) | Storage quota |
| Duplicate detection window | Disabled | 7 days | De-dupe by MessageId |

**vs SQS**:

| Feature | SQS Standard | SQS FIFO | Service Bus Queue |
|---------|-------------|---------|-----------------|
| Ordering | Best-effort | Per-group FIFO | Per-session FIFO |
| Deduplication | No | Content-based or dedup ID | MessageId-based window |
| Max message size | 256 KB | 256 KB | 256 KB (Standard), 100 MB (Premium) |
| Max visibility timeout | 12 hours | 12 hours | 5 minutes (extendable) |
| Dead-letter | SQS DLQ (separate queue) | SQS DLQ | Automatic sub-queue (same namespace) |
| Message scheduling | Delay (0–15 min only) | Delay (0–15 min only) | Any future DateTime |
| Transactions | No | No | Yes (atomic send + complete across entities) |

### Sessions (FIFO within a Group)

Service Bus sessions give ordered processing within a logical group, with parallel processing across groups — equivalent to SQS FIFO message groups.

```python
# Publisher: set session ID for order grouping
await sender.send_messages(
    ServiceBusMessage("Order event", session_id="customer-12345")
)

# Consumer: accept a specific session — gets exclusive lock
async with await receiver.accept_next_session() as session:
    async for msg in session.receive_messages():
        print(f"Session {session.session_id}: {msg}")
        await receiver.complete_message(msg)
```

Sessions use case: All events for `customer-12345` must be processed in order, but `customer-67890` events can be processed concurrently.

### Topics and Subscriptions

```
Publisher → Topic
              │
    ┌─────────┼──────────┐
    ▼         ▼          ▼
  Sub A     Sub B      Sub C
(all msgs) (SQL filter) (SQL filter)

Sub B filter: "priority = 'high'"
Sub C filter: "region = 'EU'"
```

**SQL filter example**:
```sql
priority = 'high' AND amount > 1000
```

Topic subscriptions support:
- **SQL filter**: Property-based filtering (strings, numbers, booleans)
- **Correlation filter**: Match on `CorrelationId`, `To`, `ReplyTo`, `Label` (fast, O(1) matching)
- **True filter**: Receive all messages (default)
- **False filter**: Receive no messages (disable subscription temporarily)

**vs SNS + SQS fan-out**: SNS delivers to SQS queues with basic attribute filtering. Service Bus Topics have richer SQL filtering and are a single managed unit (no separate SQS queue per subscriber needed).

### Dead-Letter Queue

Every queue and subscription has an automatic Dead-Letter Sub-Queue (DLQ):

```
Queue: orders
  └── Dead-Letter Sub-Queue: orders/$DeadLetterQueue

Reasons messages move to DLQ:
1. MaxDeliveryCount exceeded (default 10)
2. TTL expired (message expired before processing)
3. FilterEvaluation failed (topic subscription filter error)
4. DeadLetterOnMessageExpiration = true + TTL expired
5. Manual: receiver.dead_letter_message(msg, reason="invalid payload")
```

**vs SQS DLQ**: SQS DLQ is a separate queue configured manually. Service Bus DLQ is automatic, same namespace, contains dead-letter reason and error description in system properties — richer diagnostics.

---

## 2. Azure Event Grid

### What It Is

Event-driven notification service. Sources push events to Event Grid; Event Grid pushes to subscribers (HTTP webhooks, Azure Functions, Service Bus, etc.). Push-based — consumers don't poll.

**Mental model**: CloudWatch Events → EventBridge equivalent, but simpler. Event Grid = notifications; not for guaranteed delivery of high-volume streams.

### Event Schema

```json
{
  "id": "abc-123",
  "source": "/subscriptions/{sub}/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/myaccount",
  "subject": "/blobServices/default/containers/images/blobs/photo.jpg",
  "type": "Microsoft.Storage.BlobCreated",
  "time": "2024-01-15T10:00:00Z",
  "data": {
    "api": "PutBlockList",
    "url": "https://myaccount.blob.core.windows.net/images/photo.jpg"
  },
  "dataVersion": "1.0"
}
```

### Built-in Event Sources

| Source | Example Events |
|--------|---------------|
| Azure Blob Storage | BlobCreated, BlobDeleted |
| Azure Cosmos DB | Document changes |
| Azure Service Bus | ActiveMessagesAvailableWithNoListeners |
| Azure Container Registry | ImagePushed, ImageDeleted |
| Azure Event Hubs | CaptureFileCreated |
| Azure Kubernetes Service | NodePoolRollingStarted |
| **Custom Topic** | Your application events (publish via HTTP) |

### vs AWS EventBridge

| Feature | Event Grid | EventBridge |
|---------|-----------|-------------|
| Delivery | Push (HTTP webhook) | Push (Lambda, SQS, SNS, etc.) |
| Event filtering | Subject prefix/suffix matching | Rich JSON pattern matching |
| Schema registry | No (use Event Hubs with Schema Registry) | Yes (EventBridge Schema Registry) |
| Cross-account delivery | Via webhook | Native (event buses) |
| Replay | Not supported | Yes (archive + replay) |
| Transformation | No | Yes (InputTransformer) |
| Dead-letter | Dead-letter storage account | Dead-letter SQS queue |
| Retention | No (events pushed immediately) | 24h archive by default |
| Max event size | 1 MB | 256 KB |

**Event Grid is better for**: Azure service integrations (Blob created → trigger Function)  
**EventBridge is better for**: Complex routing, cross-account, schema registry, event replay

---

## 3. Azure Event Hubs

### What It Is

High-throughput, low-latency event streaming platform. The Kinesis equivalent — but with Kafka protocol compatibility.

**Key differentiator**: Event Hubs exposes the Apache Kafka API. Existing Kafka producers/consumers work without code changes — just change the broker endpoint.

### Architecture

```
Producers → Event Hub (Namespace → Event Hub) → Consumer Groups → Consumers
                          │
                    Partitions (1–32 standard, up to 2000 Premium/Dedicated)
                          │
                    Retention: 1–90 days (standard), unlimited (Capture to ADLS)
```

### Throughput Units (TUs)

| Unit | Standard | Premium | Dedicated |
|------|---------|---------|----------|
| **Throughput Unit** | 1 TU = 1 MB/s in, 2 MB/s out | Processing Unit (PU) | Capacity Unit (CU) |
| Max TUs (standard) | 40 (auto-inflate to 20) | N/A | N/A |
| Max partitions | 32 | 100 | 2,000 |
| Retention | 7 days max | 90 days | Unlimited |
| Kafka compat | Yes | Yes | Yes |
| VNet integration | No | Yes | Yes |

**Auto-inflate**: Standard tier auto-scales TUs up to configured max on ingress spike. No manual intervention needed.

### vs Kinesis Data Streams

| Feature | Event Hubs | Kinesis Data Streams |
|---------|-----------|---------------------|
| Kafka compatibility | **Yes** — native | No (custom SDK only) |
| Partition unit | Partition | Shard |
| Max throughput per partition | 1 MB/s in, 2 MB/s out | 1 MB/s in, 2 MB/s out (same) |
| Ordering | Within partition | Within shard |
| Max retention | 90 days (Standard), unlimited (Dedicated) | 365 days (extended retention) |
| Max message size | 1 MB | 1 MB |
| Consumer groups | Supported (multiple parallel readers) | Supported (Enhanced Fan-out) |
| Enhanced fan-out equivalent | Multiple consumer groups | Enhanced Fan-out (2 MB/s per shard per consumer) |
| Server-side encryption | At-rest encryption | At-rest + KMS |
| Schema registry | Yes (Event Hubs Schema Registry — Avro/JSON/Protobuf) | No (use Glue Schema Registry) |

**Winner for Kafka migration**: Event Hubs — Kafka clients work with endpoint change only.  
**Winner for long retention (1 year)**: Kinesis — 365-day extended retention vs Event Hubs 90-day max.

### Event Hubs Capture

Automatically archive event stream to Azure Blob Storage or ADLS Gen2 in Avro format. The Kinesis Firehose equivalent.

```
Event Hubs → Capture (automatic) → Azure Blob Storage / ADLS Gen2
                                    (folder structure: namespace/eventhub/year/month/day/hour/minute/second)
```

### Consumer Groups

Multiple consumer groups = multiple independent readers of the same stream. Each consumer group maintains its own offset.

```
Event Hub: telemetry-stream
├── Consumer Group: $Default (offset tracking per partition)
├── Consumer Group: analytics-team (separate offset)
└── Consumer Group: alerting-service (separate offset)
```

**Maximum consumer groups**: 20 per event hub (Standard), 100 (Premium/Dedicated).

---

## Decision Framework

```
Need to send a message to one consumer?
  └── Yes → Service Bus Queue
      └── Need ordering within a group? → Enable sessions
      └── Need transactions? → Service Bus Premium

Need to fan-out to multiple consumers?
  ├── Heavy business logic + filtering? → Service Bus Topics (SQL filters)
  └── Lightweight notification (Azure events)? → Event Grid
      └── Need schema registry or event replay? → EventBridge (if on AWS) / Event Hubs (if on Azure)

Need high-throughput streaming?
  └── Yes → Event Hubs
      └── Existing Kafka producers? → Event Hubs (no code change)
      └── Already on AWS? → Kinesis Data Streams
      └── Need managed Kafka ecosystem? → Event Hubs Kafka surface or Amazon MSK
```

---

## Comparison: Which to Use

| Requirement | Winner |
|------------|--------|
| Reliable ordered processing within a group | Service Bus Queue with sessions |
| Fan-out with SQL-based subscriber filtering | Service Bus Topics |
| Trigger Azure Function on Blob upload | Event Grid |
| High-throughput telemetry ingestion (>1 MB/s) | Event Hubs |
| Kafka migration without code changes | Event Hubs (Kafka protocol) |
| Enterprise transactions (send + receive + complete atomically) | Service Bus Premium |
| Cross-cloud or vendor-neutral messaging | Event Hubs (Kafka) or AWS MSK (Kafka) |
| Lowest cost for simple queue | Storage Queue (basic; not Service Bus) |

---

## Key Numbers for Interviews

| Service | Key Number | Significance |
|---------|------------|-------------|
| Service Bus max message size (Premium) | **100 MB** | Eliminates Claim Check for most payloads |
| Service Bus max delivery count | 10 (default) | After 10 failures → Dead-Letter Queue |
| Service Bus lock duration max | 5 minutes | Must call `RenewMessageLockAsync()` for long processing |
| Event Grid max event size | 1 MB | SQS-compatible; sufficient for notifications |
| Event Grid max events per request | 1 MB total batch | Batch publish up to 1 MB |
| Event Hubs max partitions (Standard) | 32 | Can't increase after creation |
| Event Hubs max throughput per TU | 1 MB/s in, 2 MB/s out | 40 TUs = 40 MB/s in, 80 MB/s out |
| Event Hubs max retention (Standard) | 7 days | Use Premium/Dedicated for 90 days |
| Event Hubs consumer groups (Standard) | 20 per event hub | Plan consumer group count upfront |

---

> **FAANG Interview Callout**: "On Azure I think of messaging as three distinct tiers: Service Bus for business transactions requiring guaranteed delivery and ordering (orders, payments), Event Grid for reactive integration between Azure services (blob created → trigger processing), Event Hubs for high-throughput telemetry where Kafka compatibility matters. The biggest AWS-to-Azure gotcha: SQS visibility timeout max is 12 hours; Service Bus lock duration max is 5 minutes — for long-running consumers you must heartbeat `RenewMessageLockAsync()`. This is why for very long processing jobs I use Event Hubs with offset checkpointing instead, which doesn't have a lock concept."
