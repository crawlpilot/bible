# Trade-off: Batch Processing vs Stream Processing

**Category**: HLD · Data Processing · Architecture Decision  
**FAANG interview trigger**: "How would you compute analytics on user events?" / "What's the architecture for real-time recommendations?" / "How would you build a fraud detection system?"

---

## Context

The Lambda architecture (batch + speed layer) was once the standard answer to "how do you process large-scale data." Modern systems increasingly use Kappa architecture (stream-only). Understanding when each applies — and what the real trade-offs are — is a principal engineer-level skill.

---

## Definitions

**Batch processing**: process a bounded dataset at scheduled intervals. Inputs are complete; outputs are produced after all inputs are processed. Examples: Hadoop MapReduce, Spark batch, Hive, dbt.

**Stream processing**: process an unbounded dataset event-by-event or in micro-batches as events arrive. Low latency; outputs are continuously produced. Examples: Apache Flink, Kafka Streams, Spark Streaming, Amazon Kinesis Data Analytics.

---

## Comparison

| Dimension | Batch | Stream |
|-----------|-------|--------|
| **Latency** | Minutes to hours | Milliseconds to seconds |
| **Throughput** | Very high — optimized for bulk I/O | Lower per-operation, but sustained |
| **Consistency** | Strong — processes complete dataset | Eventual — out-of-order events, late data |
| **Fault tolerance** | Replay entire job or checkpoint | Checkpointed offsets; exactly-once with effort |
| **State management** | No state between runs (usually) | Stateful aggregations (windowing, joins) |
| **Late data** | N/A — data is complete by definition | Must define handling (drop, update, reprocess window) |
| **Operational complexity** | Low — scheduled jobs, simple retry | High — stateful operators, watermarks, consumer lag |
| **Cost** | Cheap — use spot/preemptible instances | Expensive — always-on cluster |
| **Query flexibility** | High — SQL, arbitrary transformations | Limited — must define in advance |

---

## Batch Processing

### When Batch is the Right Choice

1. **Latency tolerance is high**: daily billing, weekly recommendation model training, monthly compliance reports. Users or downstream systems don't need results within seconds.

2. **Complete data is required**: end-of-day financial reconciliation must process all transactions for the day before running. Partial results would be wrong by definition.

3. **High-volume historical reprocessing**: backfilling a new feature's data from 2 years of logs, migrating from one schema to another, rebuilding a search index. Batch processes TB/PB of data efficiently with columnar formats (Parquet) and vectorized execution.

4. **ML model training**: training a neural network requires multiple passes over the full dataset (epochs) — inherently batch. Recommendation model weekly retraining, fraud model retraining on new labeled data.

5. **Cost-sensitive workloads**: Spark batch on spot instances is 60–80% cheaper than an always-on Flink cluster. If hourly latency is acceptable, batch wins on cost.

### Batch Processing Patterns

**ETL pipeline**: Extract from source (PostgreSQL, S3 events), Transform (aggregate, join, clean), Load to destination (data warehouse, report).

**Example — Daily Ad Revenue Report:**
```
00:00 UTC: Spark job triggers
           ├── Read yesterday's click events from S3 (Parquet)
           ├── Read ad prices from PostgreSQL
           ├── JOIN events with prices
           ├── GROUP BY advertiser, campaign
           └── Write results to Redshift
00:47 UTC: Dashboard shows yesterday's revenue
```

**Frameworks**: Apache Spark (most common), Hive (SQL on HDFS), dbt (SQL transforms on warehouse), Presto/Trino (interactive batch queries).

---

## Stream Processing

### When Stream is the Right Choice

1. **Latency requirement is seconds**: fraud detection (must reject fraudulent payment before it clears, not after), real-time dashboards, live leaderboards, operational alerting.

2. **Event-driven architecture**: react to events as they happen. "When a user adds 5 items in 1 minute, trigger an abandoned cart notification." This can't wait for a daily batch job.

3. **Continuous output is required**: live sports scores, stock price feeds, IoT sensor monitoring, real-time anomaly detection on metrics.

4. **Stateful aggregations over time windows**: "count page views per user in the last 5 minutes" requires maintaining state as events arrive. This is natural in stream processors (Flink, Kafka Streams) and complex in batch (you'd need near-real-time micro-batches).

5. **Joining streams**: "correlate login events with purchase events within 10 minutes" — streaming join with a windowed state store. Batch can do this only after the window closes.

### Stream Processing Patterns

**Windowing types:**
| Window | Description | Use Case |
|--------|-------------|----------|
| **Tumbling** | Fixed, non-overlapping windows (e.g., 5-min buckets) | Hourly aggregates, billing periods |
| **Sliding** | Overlapping windows (every 1 min, covering 5 min) | Real-time "last N minutes" metrics |
| **Session** | Gap-based: window ends after N sec of inactivity | User session analytics |
| **Global** | All events from the beginning | Running totals |

**Watermarks**: a stream processor's mechanism for handling late-arriving events. A watermark at time T means "I've processed all events with timestamps ≤ T." Events arriving late (after the watermark) can be dropped, updated in a late-data window, or trigger a correction output.

**Example — Real-time Fraud Detection:**
```
Kafka topic: payment_events
  → Flink consumer
      ├── Keyed by user_id
      ├── Count payments in 5-min tumbling window
      ├── Compute total amount in window
      ├── IF count > 10 OR amount > $5,000 → emit fraud signal
      └── Fraud signal → Kafka topic → Risk scoring service
Latency: ~200ms from payment event to fraud signal
```

---

## Lambda Architecture (Batch + Stream Hybrid)

Lambda solves the accuracy vs. latency trade-off by running both:
- **Speed layer** (stream): low latency, approximate results
- **Batch layer**: high accuracy, delayed results
- **Serving layer**: merges batch + speed results; batch overwrites speed when ready

**When Lambda is still useful**: when batch results are significantly more accurate than stream results (e.g., window aggregations that need to handle late data reliably), and you can tolerate the operational complexity of running two systems.

**Lambda's problems**:
- Two codebases for the same business logic (batch job + stream job)
- Synchronization complexity: merging batch and speed outputs
- Debugging is hard: a bug might only appear in one layer
- Expensive: two always-on systems

---

## Kappa Architecture (Stream-Only)

Replace the batch layer with a replayable stream. All historical processing is done by replaying the Kafka topic from the beginning with the current stream job.

**Requirements for Kappa**:
1. All historical data must be in the stream (Kafka topic retention: days to forever via Tiered Storage)
2. The stream processor must produce correct results on replay (idempotent or deduplicated output)
3. The stream job must be fast enough to replay historical data faster than real-time

**When Kappa is preferred**: the stream job produces correct results (not approximations), Kafka retention covers the historical window needed, and the team wants to maintain one codebase.

**Used by**: LinkedIn (the originators of Kappa), Uber (for most analytics pipelines), Confluent platform use cases.

---

## Decision Framework

```
What is the latency requirement?
├── Seconds or less → Stream (Flink, Kafka Streams, Kinesis)
├── Minutes → Micro-batch (Spark Streaming, 1-min Flink windows)
├── Hours or daily → Batch (Spark, dbt, Hive)
└── Ad-hoc / interactive → Batch query engine (Presto, BigQuery, Athena)

Does processing require the complete dataset?
├── Yes (reconciliation, model training) → Batch
└── No → Stream or micro-batch

Is there complex state over time windows?
├── Yes → Stream (stateful operators, windowing)
└── No → Batch

What is the cost constraint?
├── Cost is critical → Batch on spot instances
└── Latency is more important than cost → Stream
```

---

## Real Trade-off Table

| Scenario | Recommended | Why |
|----------|-------------|-----|
| Real-time fraud detection | Stream (Flink) | Sub-second decision required before payment clears |
| Daily revenue reporting | Batch (Spark + dbt) | Complete data required; latency not critical |
| Live recommendation updates | Stream (Kafka Streams) | "You just bought X, here's Y" needs <1s |
| Weekly ML model retraining | Batch (Spark ML) | Multiple passes over full dataset |
| Leaderboard (gaming) | Stream (Flink) | Near-real-time ranking |
| Monthly billing | Batch (Spark) | Must close the month completely |
| IoT anomaly detection | Stream (Flink / Kinesis) | Alert within seconds of sensor spike |
| Ad-hoc analytics query | Interactive batch (Presto/BigQuery) | Exploratory, no latency SLA |
| ETL into data warehouse | Batch (dbt + Spark) | Nightly incremental loads |

---

## FAANG Interview Callouts

**Demonstrate this thinking:**
- "For the fraud detection system, stream processing is required — we need to evaluate a transaction in <100ms before the payment network timeout. I'd use Flink with a keyed state store per user_id maintaining a sliding 5-minute window of recent transaction counts and amounts."
- "The analytics dashboard shows daily/weekly metrics, so a batch Spark job running at midnight UTC is the right call — it gives us complete data for the previous day, processes it with Presto or dbt, and loads results into Redshift. Running this as a stream would add operational complexity for no latency benefit."
- "We should consider Lambda architecture for the recommendation system: a streaming job provides real-time collaborative filtering based on the last hour of events, while a nightly batch job retrains the deep learning model. The serving layer blends both — real-time signals for recency, batch model for relevance."

**Red flags:**
- "I'll use Kafka for the batch analytics job" — Kafka is a streaming platform, not a batch processor
- Not addressing late data handling in stream designs
- Recommending Lambda architecture without acknowledging its operational complexity
- Saying "stream processing is always better because it's real-time" — batch is often more correct, cheaper, and simpler

**Key clarifying question to ask**: "What is the maximum acceptable delay between an event happening and the output reflecting it?" This directly maps to the batch/stream decision.
