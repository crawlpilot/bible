# AWS Kinesis: Data Streams & Data Firehose

## Overview

AWS Kinesis is a family of real-time data streaming services:

| Service | Purpose |
|---|---|
| **Kinesis Data Streams (KDS)** | Real-time, ordered, replayable data stream — the Kafka equivalent |
| **Kinesis Data Firehose** | Fully managed ETL delivery to S3, Redshift, OpenSearch, Splunk |
| **Kinesis Data Analytics** | SQL/Apache Flink queries on streaming data |
| **Kinesis Video Streams** | Ingest and process video streams |

This document covers **KDS** and **Firehose** — the two you need to know for principal engineer interviews.

---

## Kinesis Data Streams (KDS)

### Architecture
```
Producers (SDK, Kinesis Agent, Firehose, Lambda, IoT)
    ↓ PutRecord / PutRecords
  Kinesis Stream
  ├── Shard 1: sequence 1..N, partition key range 0-33%
  ├── Shard 2: sequence 1..N, partition key range 33-66%
  └── Shard 3: sequence 1..N, partition key range 66-100%
    ↓ GetRecords / GetShardIterator (polling) or Subscribe (enhanced fan-out)
  Consumers (Lambda, Kinesis Client Library, Analytics, Firehose)
```

**Shard**: the fundamental throughput unit.
- **Write**: 1 MB/s and 1,000 records/s per shard
- **Read (shared)**: 2 MB/s total across all consumers reading from one shard
- **Read (enhanced fan-out)**: 2 MB/s **per consumer** per shard — dedicated throughput

**Retention**: 24 hours (default) to 365 days. Extended retention costs extra (~$0.02/shard-hour for 7-day vs $0.015 for 24-hour).

**Ordering**: strict per shard. Records with the same partition key go to the same shard, guaranteeing per-entity ordering.

### On-Demand vs Provisioned Capacity

| Mode | Capacity management | Cost | Best for |
|---|---|---|---|
| **On-Demand** | Auto-scales up to 200 MB/s in, 400 MB/s out | $0.08/GB ingested + $0.08/GB retrieved | Variable, unknown, or bursty workloads |
| **Provisioned** | Manual shard management | $0.015/shard-hr + $0.014/million records | Predictable workloads; cost-optimised at scale |

For production workloads with known throughput, **Provisioned** is cheaper. For a new service or highly variable load, start with **On-Demand**.

### Partition Key Design
The partition key determines shard assignment via MD5 hash.

**Good partition keys**: entity ID (`user_id`, `device_id`, `order_id`) — distributes load evenly and co-locates related events on the same shard.

**Bad partition keys**: constant value (all records to one shard — hot shard); timestamp (hot shard for recent data); low-cardinality field (< number of shards).

**Hot shard detection**: `GetShardIterator` errors + write throttling on one shard while others are under-utilised → re-partition or add entropy to partition key.

### Enhanced Fan-Out
Default consumer (polling) shares 2 MB/s across all consumers per shard. If you have 10 consumers reading 10 shards, each consumer gets 200 KB/s/shard — may be insufficient.

**Enhanced Fan-Out**: each registered consumer gets a dedicated 2 MB/s per shard, delivered via HTTP/2 push. Cost: +$0.015/shard-hr per enhanced consumer + $0.013/GB data retrieved.

```
Standard polling: 2 MB/s shared across consumers (polling loop)
Enhanced Fan-Out: 2 MB/s dedicated per consumer (push, ~70ms lower latency)
```

Use Enhanced Fan-Out when you have multiple consumers that all need full throughput, or when latency matters (push vs. polling).

### Kinesis + Lambda
Lambda Event Source Mapping for Kinesis:

| Parameter | Recommendation |
|---|---|
| `BatchSize` | 100–10,000 records (start at 100) |
| `BisectBatchOnFunctionError` | **Enable** — splits batch on failure to isolate bad record |
| `MaximumRetryAttempts` | 3–10 (default: -1 = infinite, dangerous) |
| `DestinationConfig.OnFailure` | **SQS or SNS** — capture failed batches for debugging |
| `StartingPosition` | `TRIM_HORIZON` (all data) or `LATEST` (new data only) |
| `ParallelizationFactor` | 1–10 concurrent Lambda per shard (multiply shard throughput) |

**One Lambda per shard** by default. `ParallelizationFactor=10` runs 10 concurrent Lambdas per shard in parallel batches — multiplies throughput but loses strict ordering across parallel batches.

### Resharding
- **Shard split**: one shard → two shards; doubles write capacity for that hash range
- **Shard merge**: two adjacent shards → one shard; halves capacity, reduces cost
- Can only double/halve; no finer-grained control
- Resharding takes ~30 seconds; consumers must handle parent + child shard reads during transition
- Kinesis Client Library (KCL) handles resharding automatically

### KDS vs Kafka

| Dimension | Kinesis Data Streams | Apache Kafka (MSK) |
|---|---|---|
| Operations | Fully managed | Managed (MSK) or self-managed |
| Replay | Up to 365 days | Unlimited (disk-bound) |
| Ordering | Per-shard | Per-partition |
| Throughput scaling | Add shards (manual) or On-Demand | Add partitions (more flexible) |
| Consumer groups | Limited fan-out without Enhanced FO | Unlimited consumer groups, each full copy |
| Ecosystem | AWS-native (Lambda, Firehose integration) | Kafka Streams, Kafka Connect, ksqlDB |
| Cost | ~$0.015/shard-hr + data | ~$0.21/broker-hr (MSK) |
| Latency | 70–200ms | 10–50ms (lower) |
| Use when | AWS-native, fully managed, moderate throughput | Maximum throughput, rich ecosystem, long retention, OSS |

---

## Kinesis Data Firehose

### Overview
Firehose is a fully managed, serverless ETL delivery pipeline. Producers push data in; Firehose buffers, optionally transforms, and delivers to a destination. Zero infrastructure management.

**Sources**: Kinesis Data Streams, MSK (Kafka), Direct PUT (SDK/Agent), CloudWatch Logs, EventBridge, IoT Core

**Destinations**:
| Destination | Use case |
|---|---|
| **S3** | Data lake ingestion; most common |
| **Amazon Redshift** | DWH loading via S3 COPY |
| **OpenSearch** | Search and analytics |
| **Splunk** | SIEM / security logging |
| **HTTP endpoint** | Custom destination (Datadog, MongoDB Atlas, etc.) |
| **Snowflake / Iceberg** | Modern lakehouse format delivery |

### Buffering & Batching

Firehose buffers records before delivery. You control the buffer:

| Parameter | Range | Recommendation |
|---|---|---|
| `BufferingHints.SizeInMBs` | 1–128 MB | 64–128 MB for S3 (Parquet query performance) |
| `BufferingHints.IntervalInSeconds` | 0–900s | 60–300s depending on latency tolerance |

Buffer flushes when **either** the size OR the interval is reached. Lower interval = more frequent (smaller) files. Higher size = fewer, larger files (better for Athena queries).

**Target file size for Athena**: 64–512 MB per file. Files < 1 MB dramatically slow Athena queries (small file problem). Use Firehose Dynamic Partitioning + appropriate buffer size to balance.

### Dynamic Partitioning
Extracts fields from incoming records and uses them as S3 key prefixes dynamically:

```json
{
  "DynamicPartitioningConfiguration": {
    "Enabled": true,
    "Processors": [{
      "Type": "MetadataExtraction",
      "Parameters": [
        {"ParameterName": "JsonParsingEngine", "ParameterValue": "JQ-1.6"},
        {"ParameterName": "MetadataExtractionQuery", "ParameterValue": "{region:.region, event_type:.event_type}"}
      ]
    }]
  },
  "Prefix": "data/region=!{partitionKeyFromQuery:region}/event_type=!{partitionKeyFromQuery:event_type}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/"
}
```

Result: `s3://bucket/data/region=us-east-1/event_type=click/year=2024/month=01/` — Hive-partitioned for Athena.

### Inline Transformation (Lambda)
Firehose can invoke a Lambda to transform each record batch before delivery:

```python
def handler(event, context):
    output = []
    for record in event['records']:
        # Decode → transform → encode
        payload = base64.b64decode(record['data'])
        data = json.loads(payload)
        data['processed_at'] = datetime.utcnow().isoformat()
        encoded = base64.b64encode(json.dumps(data).encode()).decode()
        output.append({'recordId': record['recordId'], 'result': 'Ok', 'data': encoded})
    return {'records': output}
```

**Transformation Lambda must respond within 3 minutes**. For heavy transforms, use Glue instead and send raw data to S3 first.

### Data Format Conversion
Firehose can convert JSON → **Parquet** or **ORC** natively (no Lambda needed) using a Glue Data Catalog schema. This is the most cost-effective way to land Parquet in S3 without an ETL job.

```
Source: JSON events → Firehose (format conversion) → S3 as Parquet → Athena queries
Cost saving: ~10× reduction in S3 storage; ~10× reduction in Athena scan cost
```

### Firehose vs KDS vs Kafka (decision matrix)

| Need | Use |
|---|---|
| Deliver events to S3 with minimal code | Firehose direct PUT |
| Real-time processing with custom logic + delivery | KDS → Lambda/KDA → Firehose for S3 |
| Multiple independent consumers needing replay | KDS or MSK (Kafka) |
| Sub-second latency analytics | KDS or MSK (Firehose has 60s+ buffer) |
| Log delivery to S3 (CloudWatch, VPC Flow Logs) | Firehose subscription filter |
| Format conversion (JSON → Parquet) at scale | Firehose with Glue schema |
| Multi-region fan-out of stream | KDS with Firehose as consumer per region |

---

## Monitoring & Alerting

### KDS Metrics
| Metric | Alert condition |
|---|---|
| `WriteProvisionedThroughputExceeded` | > 0 → hot shard or insufficient shards |
| `ReadProvisionedThroughputExceeded` | > 0 → upgrade to Enhanced Fan-Out |
| `GetRecords.IteratorAgeMilliseconds` | P99 > 1 min → consumers falling behind |
| `PutRecord.Success` | Drop → producer issue |
| Shard-level `IncomingRecords` | Imbalance > 2× across shards → hot shard |

**Iterator Age** is the most important KDS metric: it measures how far behind the oldest unread position is from the latest record. High iterator age = consumers can't keep up.

### Firehose Metrics
| Metric | Alert condition |
|---|---|
| `DeliveryToS3.Success` | Drop below 100% → delivery failure |
| `DeliveryToS3.DataFreshness` | > buffer interval → delivery lag |
| `ThrottledRecords` | > 0 → Firehose input throttled |
| Lambda `Duration` (transform) | Near 3-min timeout |

---

## Best Practices

### KDS
1. **Use On-Demand mode** until traffic is predictable; switch to Provisioned for cost savings
2. **Choose partition keys** with high cardinality to avoid hot shards
3. **Set `MaximumRetryAttempts`** on Lambda ESM — infinite retries will stall the shard forever on poison-pill records
4. **Enable `BisectBatchOnFunctionError`** — isolates bad records by binary-searching the failing batch
5. **Configure DLQ** (`DestinationConfig.OnFailure`) — capture records that exhaust retries
6. **Monitor iterator age** — the primary health signal; set alarm at > 1 minute
7. **Use KCL** for complex consumer logic — handles shard enumeration, checkpoint, resharding automatically

### Firehose
1. **Use Dynamic Partitioning** for data lakes — Hive-partition by date and entity for Athena query pruning
2. **Enable Parquet format conversion** — eliminates separate ETL job; native, free with Glue schema
3. **Set buffer size to 64–128 MB** for S3 delivery — avoids small file problem
4. **Enable S3 backup** for raw records — even if transformation fails, raw data is preserved
5. **Use Kinesis Data Streams as source** (not direct PUT) for workloads needing replay capability
6. **Enable CloudWatch error logging** for Firehose delivery failures

---

## FAANG Interview Points

**"Design a real-time clickstream analytics pipeline"**: Browser → Kinesis Data Streams (PutRecord by user_id partition key) → Lambda (enrich + validate) → Firehose (Dynamic Partitioning + Parquet conversion) → S3 (partitioned by date/event_type) → Athena + QuickSight. For real-time aggregations: KDS → Kinesis Data Analytics (Flink) → DynamoDB for live dashboard.

**"How many shards for 100,000 events/second at 1KB each?"**: 100,000 events × 1 KB = 100 MB/s. Each shard: 1 MB/s write. Need 100 shards minimum for writes. For reads with 5 consumers (shared): 2 MB/s / 5 consumers = 400 KB/s/consumer/shard — may need Enhanced Fan-Out for real-time consumers.

**"KDS vs Kinesis Firehose"**: KDS = real-time, replayable, millisecond latency, requires consumer code. Firehose = managed delivery pipeline, 60s+ latency, no consumer code needed, direct to S3/Redshift/OpenSearch. Typical pattern: KDS for real-time consumers → Firehose as one of those consumers for S3 archival.

**"How do you handle a poison pill record in KDS?"**: Enable `BisectBatchOnFunctionError` to binary-search the failing batch. Set `MaximumRetryAttempts=3`. Configure `DestinationConfig.OnFailure` to SQS DLQ. Implement a dead-letter handler that saves the problematic record to S3 for manual inspection. Without these, a single bad record blocks the entire shard indefinitely.
