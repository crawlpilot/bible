# Flink — Production Use Cases & Research

## Origin Paper

**"Apache Flink™: Stream and Batch Processing in a Single Engine"**  
Paris Carbone, Asterios Katsifodimos, Stephan Ewen, Volker Markl, Seif Haridi, Kostas Tzoumas  
*IEEE Data Engineering Bulletin, 2015*

### Key Claims from the Paper

| Claim | Detail |
|-------|--------|
| Unified model | Single engine for batch (bounded) and streaming (unbounded); batch is a special case |
| Dataflow model | Full implementation of Google's Dataflow paper (2015): event time, watermarks, triggers |
| Exactly-once | Chandy-Lamport snapshots with O(state size) checkpoint, not O(stream size) |
| Low latency | Per-record processing; no micro-batch artificial boundary |
| Throughput | Competitive with Spark batch on TPC-H benchmarks |

### Core Design Principles (from the paper)

1. **Streams are the primitive**: everything is a stream; batch jobs are streams over bounded data
2. **Pipelined execution**: records flow between operators without waiting for upstream to complete
3. **Managed state with ownership**: Flink owns state lifecycle; operators never manage their own persistence
4. **Timely dataflow**: computation is driven by time (event time) not just arrival order

---

## Notable Subsequent Work

| Paper / Post | Year | Contribution |
|-------------|------|-------------|
| "Stateful Computations over Data Streams" — Carbone et al. | 2017 | Deep-dive on keyed state, state backends, and exactly-once semantics |
| "Flink Forward" conference talks (annual) | 2015–present | Production engineering: Alibaba's Blink fork, KRaft migration, Flink on K8s |
| "The Dataflow Model" — Akidau et al., Google | 2015 | Foundation paper that Flink's time/window model implements |
| "Lightweight Asynchronous Snapshots for Distributed Dataflows" — Carbone et al. | 2017 | Formal proof of Chandy-Lamport adaptation for Flink; ABS algorithm |

---

## Production at Scale: Companies and Use Cases

### Alibaba (Largest Flink Deployment in the World)

- **Scale**: 1 billion+ records/sec during Double 11 (Singles' Day shopping event); 100,000+ cores; petabytes of state
- **Blink**: Alibaba's internal fork of Flink (2016–2019), which they open-sourced and merged back into Apache Flink 1.9
- **Use cases**: Real-time inventory updates (product availability updated in <100ms after purchase), fraud detection on payment streams, real-time GMV (gross merchandise value) dashboards for executives during Double 11
- **Key insight**: Flink enabled Alibaba to replace batch pipelines that computed hourly inventory snapshots with a continuous stream that updated inventory in real-time — critical for 1B+ items sold in a few hours

### Uber

- **Use cases**: Real-time surge pricing (supply/demand ratio computed per geohash per minute), driver ETA computation, fraud detection on trip events, UberEats order state machine
- **Architecture**: Kafka → Flink → Pinot (OLAP) for real-time analytics dashboards; Kafka → Flink → Cassandra for operational state
- **Key insight**: Flink's stateful processing enabled Uber to compute complex per-driver and per-rider features in real-time that previously required batch jobs running on 15-minute delays

### Netflix

- **Use cases**: Keystone data pipeline (Kafka → Flink → S3/Iceberg for cold storage; → Elasticsearch for search), real-time playback quality monitoring (rebuffering rate, bitrate switches), anomaly detection on microservice metrics
- **Architecture**: Flink jobs consume from Kafka topics; output to both a serving layer (Elasticsearch, Cassandra) and a data lake (S3 via Iceberg)
- **Key insight**: Flink's exactly-once guarantee was critical for the playback quality metrics pipeline — duplicate counts in quality metrics would lead to incorrect decisions about CDN routing

### LinkedIn

- **Use cases**: Real-time feed ranking signal computation, member activity aggregation (profile views, connection requests), ad campaign delivery pacing
- **Architecture**: Kafka → Flink (feature computation) → Venice (LinkedIn's feature store) → online serving
- **Scale**: Processes 10+ trillion events/day across multiple Flink clusters

### ING Bank

- **Use cases**: Real-time fraud detection (pattern matching over account transactions); regulatory reporting (real-time trade reporting to EU regulators)
- **Key insight**: Flink CEP (Complex Event Processing) enabled ING to detect fraud patterns (e.g., multiple small transactions followed by a large one) in milliseconds — previously done in batch with a 15-minute delay, missing real-time intervention window

---

## Real-World War Stories (Operational Lessons)

### Alibaba: State Explosion from Missing TTL

> "A Flink job aggregating user click sessions forgot to set a TTL on session state. Over weeks, the state grew to hold sessions for every user who had ever clicked on any item — most sessions were days or weeks old and inactive. RocksDB compaction fell behind; checkpoint times grew from 2 minutes to 45 minutes, causing checkpoint timeouts and job restarts. The fix: add `StateTtlConfig` with a 2-hour TTL to expire inactive sessions."

**Lesson**: Every piece of keyed state must have a TTL. Unbounded state growth is the most common Flink production incident.

### Uber: Checkpoint Storm on Rescale

> "When Uber increased parallelism from 16 to 32 for a surge pricing job (via savepoint + rescale), the first checkpoint after rescale took 40 minutes instead of the usual 2 minutes. The cause: RocksDB on each TaskManager had to rebuild its state from the savepoint files — state was redistributed from 16 key groups to 32, requiring full restore and recompaction. During this window, the job was running but not checkpointing, so failure recovery would have replayed 40+ minutes."

**Lesson**: After rescaling via savepoint, the first checkpoint will be slow (full, not incremental). Plan maintenance windows for rescaling. Alert on checkpoint duration spikes post-rescale.

### Netflix: Watermark Misconfiguration Drops Late Events

> "A Flink job processing playback quality events used a 5-second bounded-out-of-order watermark. Mobile clients in poor network conditions buffered events locally and uploaded them 30–60 seconds late. These events were silently dropped as late data. Quality metrics for mobile users were systematically undercounted by ~15%. Fix: increase allowed lateness to 120 seconds; route late events to a side output; merge side output into daily recomputation."

**Lesson**: Measure your actual event lateness distribution (p50, p95, p99) before setting watermark bounds. Always use side outputs for late data — never silently drop.

---

## Flink Ecosystem: Key Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| **Flink SQL / Table API** | Declarative stream/batch processing | Unified API; supports CDC (changelog) semantics; production-ready since Flink 1.13 |
| **Flink CEP** | Complex Event Processing | Pattern detection across event sequences (login → failed → suspicious) |
| **Flink Kubernetes Operator** | K8s-native Flink deployment | Auto-scaling, rolling upgrades, savepoint lifecycle management |
| **Apache Iceberg + Flink** | Streaming writes to data lake | ACID writes to S3/HDFS; time-travel queries; schema evolution |
| **Flink CDC Connectors** | Debezium-based CDC sources | Capture DB changes → Flink pipeline without separate Debezium cluster |
| **PyFlink** | Python API for Flink | For ML teams; uses Beam runner or native Flink execution |

---

## FAANG Interview Framing

### What Interviewers Are Testing

| Question Type | What They're Probing |
|---------------|---------------------|
| "Design a real-time fraud detection system" | Stateful CEP patterns; keyed state; sub-second latency; exactly-once |
| "How would you compute real-time user features?" | Window types; event time vs processing time; watermarks |
| "What happens if a Flink job crashes?" | Checkpoint restore; replay semantics; recovery time estimation |
| "How do you handle late-arriving data?" | Watermarks; allowed lateness; side outputs |
| "How would you scale a Flink job?" | Parallelism; savepoint-based rescale; partition key choice |

### The 3-Part Flink Answer Framework

1. **Why Flink here?** — State the decision driver (sub-second latency, event-time correctness, large state, exactly-once) and why alternatives (Spark Streaming: micro-batch latency; Kafka Streams: per-service only) don't fit.

2. **Key design decisions** — Window type and trigger, state type (ValueState / RocksDB), watermark strategy (allowed lateness), parallelism and partition key, checkpoint interval.

3. **Failure and recovery** — How checkpoint enables exactly-once; what recovery time looks like; how to test that the job recovers correctly (inject failure in staging, measure recovery time).

### 30-Second Answer: "When would you choose Flink over Spark Streaming?"

> "I'd choose Flink when I need sub-100ms latency or correct event-time processing over out-of-order data. Spark Structured Streaming is fundamentally micro-batch — it processes data in 100ms–1s intervals, which is fine for most analytics but breaks down when you need real-time decisions per event. Flink processes each record as it arrives. The other differentiator is event-time support: Flink's watermark model correctly handles mobile clients or IoT sensors that send events out of order — you set a bound on allowed lateness and Flink ensures windows fire with the right data. For operational complexity, they're similar — both need a cluster. If the team already runs Spark, the bar to adopt Flink should be clear business justification: latency SLA below 1 second, or correctness requirements that micro-batch can't meet."
