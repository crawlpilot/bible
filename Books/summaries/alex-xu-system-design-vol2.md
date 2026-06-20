# System Design Interview — An Insider's Guide, Volume 2
**Authors**: Alex Xu & Sahn Lam  
**Edition**: 1st Edition  
**Category**: System Design · Distributed Systems · FAANG Interview Prep

> 13 harder system design problems. Each assumes Vol. 1 foundations. Covers geospatial systems, distributed queues, ML infra, financial systems, and exchange-grade concurrency.

---

## Why This Book Matters for FAANG PE Interviews

Vol. 2 targets Staff and Principal Engineer bars — the problems are harder, less cookbook-like, and require you to make genuine architectural trade-offs with incomplete information. Interviewers use Vol. 2 problems to distinguish senior engineers (who know Vol. 1 cold) from principal engineers (who can reason about the Vol. 2 problems they've never seen). Key differences from Vol. 1:
- Problems have higher ambiguity — more clarification work needed
- Estimation is harder — requires domain-specific knowledge
- Failure modes are nastier — financial correctness, geospatial edge cases, exchange ordering guarantees
- Trade-offs have real cost ($) and compliance (regulatory) dimensions

---

## Chapter 1 — Proximity Service

### Problem Statement
Design a service that returns all Points of Interest (restaurants, stores, etc.) within a given radius of the user's location. Used by Yelp, Google Maps "nearby" search, and delivery apps.

### Requirements

**Functional**:
- `GET /v1/search?lat={lat}&lng={lng}&radius={meters}&type={category}` → list of businesses
- Business CRUD for operators (add, update, delete a business)
- Results sorted by distance

**Non-Functional**:
- 100M DAU; peak QPS: 5,000 searches/s
- Latency: p99 < 200 ms
- Read:write ratio: 1000:1 (searches >> business updates)
- Business count: 200M worldwide
- Geospatial accuracy: radius is approximate (within 20% is acceptable)

### Geospatial Index Algorithms

| Algorithm | How It Works | Pros | Cons |
|-----------|-------------|------|------|
| **Evenly divided grid** | Divide world into fixed-size cells; index businesses by cell | Simple | Uneven density; city = thousands per cell; desert = 0 |
| ⭐ **Geohash** | Encode (lat, lng) as a base32 string; each char adds precision; adjacent cells share prefix | Simple; prefix matching in any KV store; 12 precision levels | Grid boundary problem: close points can have different prefixes across boundaries |
| **Quadtree** | Recursively divide into 4 quadrants until each cell has ≤ N businesses | Adapts to density; good precision in cities | Complex to maintain; expensive to update dynamically |
| **R-Tree** | Tree structure for spatial data; stores minimum bounding rectangles | Exact queries; standard in PostGIS | Complex; hard to shard across distributed system |
| **S2 (Google)** | Map sphere to cube; Hilbert space-filling curve for ordering; hierarchical cells | Best for global-scale geo; preserves spatial locality | More complex than Geohash |

**Recommendation for this problem**: **Geohash** — simple, works with any K-V store (Redis, DynamoDB), and prefix matching covers "all businesses in cell and neighboring cells" efficiently.

### Geohash Deep Dive

Each character doubles precision:

| Geohash Length | Cell Size (approx) |
|---------------|-------------------|
| 1 | 5,000 km × 5,000 km |
| 4 | 39 km × 20 km |
| 5 | 4.9 km × 4.9 km |
| 6 | 1.2 km × 0.6 km |
| 7 | 153 m × 153 m |

**For 500m radius search**: Geohash length 6 (1.2 km cells). Search the user's cell + 8 neighbors (9 total) to avoid boundary misses.

**Boundary problem**: Two points 10m apart can have different geohash prefixes if they straddle a cell boundary. Solution: always query 9 cells (center + all 8 neighbors).

### Architecture

```
Client → LB → Search Service → Geospatial DB (Redis Geo or MySQL + geohash index)
                             → Business Service (metadata: name, address, hours, rating)
                             → Cache (top queries by geohash)
```

**Redis Geo commands** (alternative to custom geohash):
```
GEOADD locations lng lat business_id
GEOSEARCH locations FROMLONLAT lng lat BYRADIUS 500 m ASC COUNT 20
```

Redis Geo internally uses a sorted set with geohash as the score — same O(log N) complexity.

### Data Model

```sql
CREATE TABLE businesses (
    business_id   BIGINT PRIMARY KEY,
    name          VARCHAR(255),
    lat           DECIMAL(9,6),
    lng           DECIMAL(9,6),
    geohash6      CHAR(6),    -- indexed; for proximity search
    category      VARCHAR(100),
    rating        DECIMAL(2,1),
    updated_at    TIMESTAMP
);

CREATE INDEX idx_geohash ON businesses(geohash6);
-- Query: WHERE geohash6 IN ('9q8yy', '9q8yz', '9q8yr', ... 8 neighbors)
```

### Principal Engineer Extensions
- **Dynamic radius adjustment**: If < 10 results in 500m, expand to 1km, 5km (reduce geohash prefix length by 1)
- **Personalization ranking**: Blend distance with user preference signals (cuisine type history, ratings, price)
- **Real-time business status**: Redis pub/sub for "currently open" flag; avoid caching closed businesses
- **Quadtree for uneven density**: Geohash cells are too large in Manhattan, too small in rural areas. Quadtree adapts dynamically.

---

## Chapter 2 — Nearby Friends

### Problem Statement
Design a feature (like Snapchat's Snap Map or Facebook's Nearby Friends) that shows your friends who are physically nearby, updated in real-time as users move.

### Requirements

**Functional**:
- User sees friends within 5 miles, updated every 30 seconds
- Friend's location shown as distance + direction (no exact coordinates shared)
- User can opt out of location sharing
- Friend list: up to 500 friends

**Non-Functional**:
- 1B total users; 100M DAU with location enabled; peak: 10M active simultaneously
- Location update rate: each active user sends location every 30s
- Update QPS: 10M users / 30s = 333,000 location writes/s
- Nearby query QPS: 10M users × 2 queries/min = 333,000 reads/s
- Latency: updates visible to friends within 10 seconds

### Core Challenge — Scalability of Fan-Out

When user A moves, up to 500 friends must be notified. With 10M active users:
- 10M updates/30s × 500 friends = 5 billion notifications/30 seconds = 167M notifications/s — impossible to fan-out directly

**Solution**: Don't fan-out all updates. Friends check in on demand.

**Pull model**: Friend opens Nearby screen → app queries "which of my friends are near me?" — server computes on demand.

**Push model**: WebSocket to each active user; server pushes nearby friend updates.

**Hybrid (this design)**:
- Location stored in Redis (in-memory, low latency)
- Each user gets a WebSocket to a Location Server
- Location Server manages a pub/sub channel per user in Redis
- When A updates location → publish to A's pub/sub channel → A's friends who are online subscribe to A's channel → they receive update on their WebSocket

### Architecture

```
User A moves → Mobile App → Location API → Redis Pub/Sub Channel for A
                                         → Location Cache: SET location:{A} {lat,lng,ts} EX 60

User B (friend of A) → WebSocket → Location Server B
                                   → Subscribe to location:{A} channel (on friend list load)
                                   → Receives pushed update when A publishes
                                   → Computes distance: if < 5 miles → push to B's client
```

### Location Storage — Redis Design

```
Key: location:{user_id}
Value: {lat, lng, timestamp}
TTL: 60 seconds (user considered inactive after 60s without update)

# For geospatial queries (alternative):
GEOADD active_users lng lat user_id
GEOSEARCH active_users FROMLONLAT lng lat BYRADIUS 8 km ASC  # 5 miles ≈ 8 km
```

**Why Redis over DB**: Location updates are ephemeral (30s TTL acceptable), extremely high write rate, and must support sub-second reads. Redis handles 333K writes/s trivially with a cluster.

### Privacy Design

- Location precision reduced before sharing: show "~2 miles away" not exact coordinates
- User opt-out: remove from `active_users` geospatial index; don't publish to pub/sub
- Ghost mode: still receive friend locations; don't publish your own
- Fuzzing: add random ±0.5 mile noise to displayed distance

### WebSocket Server Scaling

- Each WebSocket server manages N active connections (N ≈ 100,000 with optimized Linux networking)
- 10M concurrent → 100 servers
- User's location server is known from their WebSocket connection → route location updates to correct server
- Server metadata (which user is on which server) stored in Redis: `SET ws_server:{user_id} {server_id}`

### Failure Modes

| Failure | Impact | Mitigation |
|---------|--------|-----------|
| Location Server crash | Users lose WebSocket; miss updates | Clients reconnect in 5s; resync friend list subscriptions |
| Redis pub/sub overloaded | Location updates delayed | Shard pub/sub by user_id range; limit subscription fan-out |
| Client location staleness | Friend appears in wrong place | TTL on location records; UI shows "last seen X min ago" |

---

## Chapter 3 — Google Maps

### Problem Statement
Design a mapping and navigation service covering map rendering, turn-by-turn navigation with ETA, and real-time traffic integration.

### Requirements

**Functional**:
- Render maps at any zoom level globally
- Turn-by-turn navigation: fastest route from A to B
- Real-time ETA with traffic conditions
- Location search (forward + reverse geocoding)

**Non-Functional**:
- 1B DAU; peak navigation QPS: 1M requests/s
- Map data: 100 PB of raw map data (OSM or proprietary)
- Route computation: < 2s for cross-city routes; < 500ms for local routes
- Map tile latency: < 100 ms at CDN edge
- High accuracy: route should be within 5% of actual travel time

### Map Tile System

Maps rendered as a grid of tiles at each zoom level. Zoom level Z has 4^Z tiles covering the world.

| Zoom | Tiles | Coverage per Tile | Use Case |
|------|-------|-------------------|---------|
| 0 | 1 | Entire world | World map |
| 5 | 1,024 | Continental | Continent view |
| 10 | ~1M | City | City view |
| 15 | ~1B | Neighborhood | Street level |
| 20 | ~1T | Building | Building detail |

**Tile naming**: Tile identified by `(z, x, y)` — zoom, column, row. URL: `/tiles/{z}/{x}/{y}.png`

**Storage**: 100 PB raw data → compressed PNG tiles ≈ 100 TB total (most zoom levels are empty ocean/desert)

**CDN strategy**: Tiles are static, cacheable, and accessed by lat/lng → deterministic URLs. Push all tiles to CDN edge nodes. Cache hit rate > 99.9% for popular areas.

**Tile generation**: Batch job converts raw map data (OSM PBF format) → tiles at each zoom level (Mapnik, Tippecanoe). Incremental updates when map data changes.

### Routing Engine — Graph Design

Map = directed weighted graph: nodes = intersections; edges = road segments with weights.

**Edge weight**: Time-based (not distance): `weight = distance / speed_limit × traffic_multiplier`

**Graph size**:
- OpenStreetMap: ~7 billion nodes, ~800M edges
- Too large to fit in single machine RAM (at ~100 bytes/edge = 80 GB)
- Partition graph by geographic regions (hierarchical: continent → country → city)

### Routing Algorithms

| Algorithm | Time Complexity | Handles Traffic | Notes |
|-----------|----------------|----------------|-------|
| **Dijkstra** | O((V+E) log V) | Recompute on traffic update | Correct; too slow for global graph |
| **A\*** | O((V+E) log V) with heuristic | Recompute on traffic update | Faster than Dijkstra; heuristic must be admissible |
| ⭐ **Contraction Hierarchies (CH)** | O(log V) query after preprocessing | Precompute shortcuts; fast queries | Used in OSRM, Graphhopper; 1000× faster than Dijkstra |
| **Customizable CH (CCH)** | O(log V) query | Traffic multipliers applied at query time without full recomputation | Used by Apple Maps, Microsoft Bing |

**Contraction Hierarchies key idea**:
1. Preprocess: rank nodes by importance; add "shortcut" edges that bypass unimportant intermediate nodes
2. Query: bidirectional Dijkstra restricted to upward graph (importance-ordered) → O(log V) instead of O(V)
3. Traffic update: only update edge weights; shortcuts remain valid (CCH allows edge weight changes without re-preprocessing)

### Real-Time Traffic Integration

Data sources:
- **GPS probes**: GPS pings from navigation users → aggregate speed on each road segment
- **Historical data**: expected travel time by day-of-week and hour
- **Incident reports**: user-reported accidents/road closures (Waze model)
- **Traffic cameras/sensors**: government data feeds

Processing pipeline:
```
GPS pings → Kafka → Stream processor (Flink)
                → Map-match GPS to road segment (HMM - Hidden Markov Model)
                → Aggregate speed per segment (sliding 5-min window)
                → Update traffic weight DB
                → Routing engine refreshes edge weights
```

**Map-matching**: GPS coordinates don't land exactly on roads. Hidden Markov Model finds most likely road sequence given noisy GPS readings.

### ETA Computation

Raw Dijkstra weight = free-flow time. ETA =
`sum(segment_length / current_speed_on_segment)`

Uncertainty: Add confidence interval (±5%) based on traffic data freshness and historical variance.

Machine learning ETA refinement:
- Features: time of day, day of week, weather, incidents, historical ETA accuracy for this route
- Model: predict correction factor for raw graph-computed ETA
- Result: 20–30% reduction in ETA prediction error vs raw graph

### Principal Engineer Extensions
- **Offline maps**: Tile + routing graph downloaded per region; client-side graph traversal for offline navigation; sync delta when online
- **Multi-modal routing**: Combine walking + transit + driving in one route (RAPTOR algorithm for public transit)
- **Isochrone computation**: "What areas can I reach in 30 minutes?" — reverse Dijkstra from destination; used for real estate, logistics planning

---

## Chapter 4 — Distributed Message Queue

### Problem Statement
Design a distributed message queue system (like Apache Kafka or Amazon SQS) that decouples producers from consumers, provides persistence, and supports at-least-once delivery at high throughput.

### Requirements

**Functional**:
- Producers publish messages to named topics
- Consumers subscribe to topics and consume messages
- Message ordering guaranteed within a partition
- Message retention: configurable (e.g., 7 days); consumers can replay historical messages
- Consumer groups: multiple consumers share load; each message delivered to one consumer per group

**Non-Functional**:
- Throughput: write 1 MB/s per partition; 100 partitions per topic → 100 MB/s per topic
- Latency: p99 produce < 5 ms; consume < 10 ms
- Durability: messages replicated to 3 nodes; tolerate 1 node failure without data loss
- Scale: 100 topics × 100 partitions = 10,000 partitions per cluster

### Core Data Structure — The Commit Log

Messages appended to an immutable, ordered, persistent log (append-only file on disk).

**Why append-only**:
- Disk sequential writes are 100–1000× faster than random writes
- No index maintenance on write
- Consumers track position (offset) — no state in the broker about what has been "consumed"

**Segment files**: Log split into segment files (e.g., 1 GB each). Active segment written to; old segments are read-only. Old segments deleted after retention period or compacted.

**Offset**: Integer index of message position in partition log. Consumer owns its offset — stored in a special `__consumer_offsets` topic.

### Architecture

```
Producer → Leader Broker (partition N) → Follower Broker 1 (replica)
                                       → Follower Broker 2 (replica)
                     ↓ (ISR = in-sync replicas)
Consumer Group → Fetch from Leader (or follower for read scaling)
                     ↓
              Commit offset to __consumer_offsets topic
```

**ISR (In-Sync Replicas)**: Set of replicas that are caught up with the leader. Producer ACK policy:
- `acks=0`: Fire and forget; maximum throughput; potential message loss
- `acks=1`: Leader ACK only; fast; lose message if leader fails before replication
- `acks=all`: All ISR must ACK; maximum durability; higher latency

### Partition Leader Election — ZooKeeper vs KRaft

**Old (ZooKeeper-based)**: Controller elected via ZooKeeper; controller assigns partition leaders; ZooKeeper is external dependency and bottleneck.

**New (KRaft — Kafka Raft Metadata)**: Kafka manages its own consensus using Raft; no ZooKeeper dependency; faster leader election; simpler operations.

### Consumer Group Rebalancing

When a consumer joins or leaves, partitions are reassigned. During rebalance, no consumption happens (stop-the-world).

**Strategies**:
- **Eager rebalance**: All consumers stop; all partitions unassigned; then reassigned. Simple; brief full outage.
- **Cooperative rebalance** (Incremental): Only move partitions that need to move; consumers continue processing un-moved partitions. Complex; no stop-the-world.

**Consumer count vs partition count**:
- Consumers > Partitions: Excess consumers are idle (waste)
- Partitions > Consumers: Each consumer handles multiple partitions (acceptable)
- Rule: provision partitions = 2–3× expected max consumers

### Message Delivery Semantics

| Semantics | Producer | Consumer | How |
|-----------|---------|----------|-----|
| **At-most-once** | Fire and forget | Don't retry on failure | `acks=0`; don't retry failed fetches |
| **At-least-once** | Retry on failure | May re-process duplicates | `acks=all`; idempotent consumer |
| ⭐ **Exactly-once** | Idempotent producer (sequence numbers) + transactional API | Transactional consumer commit | `enable.idempotence=true`; consumer+producer in same transaction |

**Exactly-once in practice**: Producer assigns sequence numbers; broker deduplicates. Consumer uses Kafka transactions to atomically commit offset + write results.

### Push vs Pull for Consumers

Kafka uses **pull**:
- Consumer controls its consumption rate; no broker-side overwhelm
- Consumer can batch-fetch for efficiency
- Consumer can pause/resume independently
- Trade-off: consumer must poll continuously even when no messages (configurable with `max.poll.interval.ms`)

SQS uses a hybrid (long-poll pull):
- Consumer sends pull with `WaitTimeSeconds=20` → broker holds if no messages; responds when message arrives or timeout
- Reduces empty polls; lower cost

### Principal Engineer Extensions
- **Log compaction**: For event sourcing, keep only the latest value per key; old log segments compacted to retain only the latest offset per key. Enables Kafka as a database (Kafka Streams state stores).
- **Tiered storage**: Hot segments on fast NVMe; cold segments on S3. Infinite retention at low cost; consumers can replay from S3. Used in Confluent Platform and AWS MSK Tiered Storage.
- **Backpressure**: Consumer slows down → partition lag grows → alert; autoscale consumer group; circuit break upstream producer if lag > threshold.

---

## Chapter 5 — Metrics Monitoring and Alerting System

### Problem Statement
Design a metrics monitoring system (like Prometheus + Grafana + Alertmanager, or Datadog) that ingests time-series metrics from thousands of services, stores them efficiently, and evaluates alert rules.

### Requirements

**Functional**:
- Ingest metrics: gauges (CPU%), counters (request count), histograms (latency distribution)
- Query: time-range queries, aggregations (avg, p99, sum by label)
- Alert rules: if `avg(cpu) > 80% for 5 min` → trigger alert → notify PagerDuty/Slack
- Dashboard visualization

**Non-Functional**:
- Scale: 1,000 services × 100 metrics each = 100,000 time-series
- Ingestion rate: 100,000 metrics × 10 samples/min = 16,667 data points/s
- Retention: raw data 7 days; 1-min aggregates 30 days; 1-hour aggregates 1 year
- Query latency: dashboard queries < 1s; alert evaluation < 30s

### Time-Series Data Model

A time-series is identified by:
- **Metric name**: e.g., `http_requests_total`
- **Labels**: key-value pairs e.g., `{service="payment", region="us-east-1", status="200"}`
- **Samples**: (timestamp, float64_value) pairs

```
http_requests_total{service="payment", region="us-east-1", status="200"} @1704067200 = 5842
http_requests_total{service="payment", region="us-east-1", status="500"} @1704067200 = 12
```

A unique combination of (metric name + label set) = one time-series.

**Cardinality explosion**: Adding high-cardinality labels (user_id, request_id) multiplies time-series count exponentially. 100K users × 10 metrics = 1M time-series — expensive. Rule: never use unbounded labels (user_id, session_id, request_id).

### Storage — Time-Series DB Design

**Why not general-purpose DB?**
- MySQL: B-Tree random writes for each data point → IOPs exhausted quickly
- Cassandra: Time-series writes are sequential; good fit but high compression overhead without columnar layout

**Columnar compression**:
- Timestamps: delta encoding + variable-length encoding (consecutive timestamps differ by fixed interval)
- Values: XOR encoding (Gorilla compression — Facebook 2015): consecutive floats share most bits; 1.37 bytes/sample average vs 12 bytes/sample uncompressed

**Time-Series DB choices**:

| DB | Architecture | When to Use |
|----|-------------|------------|
| **Prometheus** | Local pull-based; TSDB; 2-byte/sample storage | Single-cluster monitoring; < 1M series; self-hosted |
| **Thanos / Cortex** | Prometheus + object storage (S3) for long-term; horizontally scalable | Multi-cluster; long retention; HA |
| **InfluxDB** | Push-based; IOx (Apache Arrow + Parquet); SQL-like query | General time-series; IoT; high ingestion rate |
| **TimescaleDB** | PostgreSQL extension; hypertable chunking; SQL | Already on Postgres; complex joins with relational data |
| **ClickHouse** | Columnar OLAP; excellent for metrics + aggregation | High cardinality; complex aggregation queries; analytics |

### Downsampling for Long-Term Retention

Raw 1-second data is expensive to store long-term. Solution:
- **Raw (7 days)**: Every sample stored
- **1-minute rollup (30 days)**: Background job computes min/max/avg/p50/p99 per 1-min window; store rollup; drop raw
- **1-hour rollup (1 year)**: Further aggregate 1-min rollups into hourly summaries

Storage reduction: 1-min rollup stores 7 numbers vs 60 raw samples → 8.5× compression (beyond columnar compression).

### Alert Evaluation Architecture

```
Rules DB (YAML alert rules) → Alert Evaluator (runs every 30s)
                                     ↓
                            Query TSDB for each rule's metric
                                     ↓
                            Evaluate threshold condition
                                     ↓ (if firing)
                            Alert Manager → deduplication + grouping
                                     ↓
                            Notification: PagerDuty, Slack, Email
```

**Alert deduplication**: Same alert firing from multiple evaluator replicas → deduplicated by `(alert_name, labels, fingerprint)` in Alert Manager

**Flap prevention**: Alert must be in firing state for N consecutive evaluations before triggering notification (configurable: `for: 5m` in Prometheus rule)

### Principal Engineer Extensions
- **Exemplars**: Attach a trace_id to a histogram sample → click on a high-latency data point → jump directly to the corresponding distributed trace (OpenTelemetry exemplars)
- **Anomaly detection**: ML-based alerting (Prophet, LSTM) to detect unusual patterns without fixed thresholds; reduces alert fatigue
- **High-cardinality handling**: Stream data through aggregation pipeline (Kafka → Flink) before storing in TSDB; aggregate away high-cardinality dimensions at ingest time

---

## Chapter 6 — Ad Click Event Aggregation

### Problem Statement
Design a system that aggregates ad click events in real-time for reporting (e.g., "how many clicks did ad #12345 get in the last 5 minutes?") and billing (charge advertisers per click).

### Requirements

**Functional**:
- Ingest click events from web/mobile clients
- Query: `clicks(ad_id, start_time, end_time)` → count
- Real-time window: last 1 minute aggregation (for ad dashboards)
- Historical: store aggregated counts for up to 7 years (billing)
- Support filter by country, device type

**Non-Functional**:
- Scale: 10B ad clicks/day → 115,000 clicks/s; peak 3× = 345,000 clicks/s
- Exactly-once aggregation for billing accuracy (financial data)
- Query latency: real-time dashboard < 1s; historical queries < 10s
- Late events: clicks can arrive up to 15 minutes late (mobile offline then syncs)

### Why This Is Hard

1. **Exactly-once at 345K events/s**: Any duplicate click = overbilling advertiser; any missed click = underbilling
2. **Late events**: Mobile client offline for 10 minutes → syncs 1000 clicks → must attribute to correct time window
3. **Reconciliation**: Independently verify aggregated counts match raw logs for audit

### Event Ingestion

```
Client → CDN / LB → Click Collector (validate, deduplicate, enrich)
                         ↓ (Kafka Producer, acks=all, idempotent)
                    Kafka Topic: raw_clicks (partitioned by ad_id)
                         ↓
                 Stream Processor (Apache Flink)
                         ↓              ↓
               Aggregated counts    Raw events
               (ClickHouse/TSDB)    (S3 cold storage for audit)
```

**Click deduplication at collector**:
- Generate `click_id = hash(user_id + ad_id + timestamp_bucket + session_id)`
- Check Redis SET: `SET NX click_id EX 300` (5-min dedup window)
- If key existed → duplicate; drop

### Stream Processing with Apache Flink

**Windowing strategies**:

| Window Type | Description | Use Case |
|-------------|-------------|---------|
| **Tumbling** | Fixed non-overlapping windows (e.g., every 1 min) | Billing: each minute is independent |
| **Sliding** | Overlapping windows (e.g., 5-min window every 1 min) | Dashboards: "clicks in last 5 min" |
| **Session** | Variable-length; end when gap > threshold | User session analysis |

**Flink job**:
```java
DataStream<ClickEvent> clicks = kafka.read("raw_clicks");

clicks
  .keyBy(click -> click.adId)
  .window(TumblingEventTimeWindows.of(Time.minutes(1)))
  .aggregate(new ClickCountAggregator())
  .addSink(clickhouseSink);
```

### Late Event Handling — Watermarks

**Watermark**: Signal to Flink that "all events with timestamp < watermark have arrived." Flink closes window when watermark passes window end time.

**Strategy**:
- **Max lateness**: Allow events up to 15 minutes late (Flink `allowedLateness`)
- **Watermark = max_observed_event_time - 15_minutes**
- Late events trigger window recomputation and update the stored aggregate

**Tradeoff**: Waiting 15 min for late events delays billing report by 15 min. Balance between freshness and completeness.

### Reconciliation (Audit)

Batch job runs nightly:
1. Read raw click events from S3 (Hive/Spark)
2. Aggregate counts by (ad_id, 1-hour window)
3. Compare with streaming aggregates stored in ClickHouse
4. Discrepancies > 0.01% trigger reconciliation alert and reprocessing

**Why necessary**: Streaming has bugs (wrong watermarks, processing errors); batch is the source of truth for billing.

### Billing Accuracy — Exactly-Once

Flink → ClickHouse:
- Use Flink checkpointing (savepoints) + idempotent ClickHouse write
- Each checkpoint snapshot captures Kafka offsets + aggregation state
- On failure: restore from checkpoint; replay from Kafka offset → same aggregated result (idempotent)
- `acks=all` on Kafka producer ensures no click loss in transit

### Principal Engineer Extensions
- **Click fraud detection**: ML model on click features (user-agent, IP, click velocity); flag suspicious patterns; withhold from billing; manual review queue
- **Multi-level aggregation**: Pre-aggregate by (minute, ad_id); allow client to query (hour, campaign_id) by summing minute aggregates — OLAP rollup
- **ClickHouse MergeTree**: Stores aggregates in columnar format; background merges combine incremental updates into final counts; eventual consistency for reads during merge

---

## Chapter 7 — Hotel Reservation System

### Problem Statement
Design a hotel booking system (like Booking.com or Hotels.com) that allows users to search for available rooms and make reservations, handling inventory management and concurrent booking conflicts.

### Requirements

**Functional**:
- Search hotels by location, dates, number of guests
- View room availability and prices for specific dates
- Book a room: reserve and confirm within a transaction
- Cancel reservation with refund policy
- Double booking prevention: same room cannot be booked twice for the same night

**Non-Functional**:
- 5,000 hotels; 1M rooms globally
- Read:write = 10:1 (search >> booking)
- Booking QPS: 300 bookings/s; search QPS: 3,000/s
- Correctness: zero double bookings (inventory must be exact)
- Availability: 99.99%; bookings must complete or fail cleanly (no partial state)

### The Core Challenge — Concurrency

Two users book the last room simultaneously. Both read availability (1 room), both proceed, both commit → double-booked.

**Solutions**:

| Approach | Mechanism | Pro | Con |
|---------|-----------|-----|-----|
| **Pessimistic locking** | `SELECT ... FOR UPDATE` locks room row; prevents others from reading until released | Prevents all concurrency conflicts | Deadlock risk; high contention degrades performance |
| **Optimistic locking** | Read version number; update only if version unchanged; retry on conflict | No locking; high throughput when conflicts are rare | High retry rate under contention; poor UX during flash sales |
| ⭐ **Database constraints + idempotent writes** | `INSERT INTO reservations (room_id, date) VALUES (...)` with UNIQUE (room_id, date) | DB enforces at data layer; no application-level lock | Requires careful schema design; error handling on constraint violation |
| **Redis distributed lock** | `SET lock:room:{id}:{date} NX EX 30` before booking | Fast; distributable | Redis SPOF; lock expiry edge cases |

**Book's recommendation**: Optimistic locking with version column for the inventory table + database UNIQUE constraint as safety net.

### Data Model

```sql
CREATE TABLE room_inventory (
    hotel_id      BIGINT,
    room_type_id  BIGINT,
    date          DATE,
    total_rooms   INT,
    reserved_rooms INT,
    version       INT DEFAULT 0,  -- for optimistic locking
    PRIMARY KEY (hotel_id, room_type_id, date)
);

CREATE TABLE reservations (
    reservation_id BIGINT PRIMARY KEY,
    user_id        BIGINT,
    hotel_id       BIGINT,
    room_type_id   BIGINT,
    check_in       DATE,
    check_out      DATE,
    status         ENUM('PENDING', 'CONFIRMED', 'CANCELLED'),
    created_at     TIMESTAMP,
    UNIQUE INDEX uix_room_date (hotel_id, room_type_id, check_in)  -- prevent double booking
);
```

### Booking Flow with Optimistic Locking

```sql
-- 1. Read current inventory
SELECT total_rooms, reserved_rooms, version
FROM room_inventory
WHERE hotel_id = ? AND room_type_id = ? AND date = ?;

-- 2. Verify availability: total_rooms - reserved_rooms > 0

-- 3. Update with version check (atomic)
UPDATE room_inventory
SET reserved_rooms = reserved_rooms + 1, version = version + 1
WHERE hotel_id = ? AND room_type_id = ? AND date = ? AND version = {read_version};

-- If 0 rows affected → conflict; retry or fail with "room no longer available"

-- 4. Insert reservation record
INSERT INTO reservations (user_id, hotel_id, room_type_id, ...) VALUES (...);
```

### Search Architecture

Search by location + dates requires geospatial + availability join — hard to do in one DB.

```
Search: location + dates → Search Service
                        → Geo Index (Elasticsearch: hotel by lat/lng)
                        → Availability Cache (Redis: hot dates for popular hotels)
                        → Availability DB (MySQL: for less popular hotels / long dates)
                        → Merge: nearby hotels with available rooms
                        → Ranking (price, rating, distance)
```

**Availability cache**: For the next 90 days, cache availability for each (hotel, room_type, date) in Redis. Invalidate on every booking.

### Overbooking Prevention — Saga Pattern

Booking crosses multiple services (Inventory, Reservation, Payment). Need atomicity without distributed transaction.

```
1. Reserve inventory (decrement available rooms)
   ↓ success
2. Create reservation record (status=PENDING)
   ↓ success
3. Process payment
   ↓ success
4. Confirm reservation (status=CONFIRMED)
   ↓ failure at any step → compensating transaction (rollback inventory, cancel reservation)
```

Each step publishes event to Kafka; next step triggered by event. Failure → compensation events fire in reverse order.

### Principal Engineer Extensions
- **Flash sale / popular event**: Distributed lock per room per date; Redis SETNX with 10s TTL; prevents thundering herd of optimistic retries
- **Price fluctuation**: Room prices change based on demand. Store prices separately per date in `room_pricing` table; pricing service updates based on occupancy rate
- **Multi-room booking**: Booking 5 rooms of same type → all-or-nothing; requires locking across date range; saga coordinates multi-step inventory reservation

---

## Chapter 8 — Distributed Email Service

### Problem Statement
Design a distributed email system (like Gmail) covering sending, receiving (SMTP/IMAP), storage, search, and attachment handling.

### Requirements

**Functional**:
- Send and receive emails via standard protocols (SMTP, IMAP, MIME)
- Store messages with attachments (up to 25 MB per email)
- Folder management: inbox, sent, drafts, labels, spam
- Search: full-text search across all emails
- Real-time push: new email notification without polling

**Non-Functional**:
- 1B users; 5B emails/day sent/received → 58,000 emails/s
- Storage: average email 50 KB → 5B × 50 KB/day = 250 TB/day → 90 PB/year
- Search latency: < 500 ms
- Delivery reliability: at-least-once delivery; Gmail advertises 99.9% delivery SLA
- Anti-spam: must classify 95%+ of spam before delivery to inbox

### Email Protocol Stack

| Protocol | Role | Port | Notes |
|---------|------|------|-------|
| **SMTP** | Send mail (client→server, server→server) | 25 (server), 587 (submission) | MTA (Mail Transfer Agent) uses SMTP for relay |
| **IMAP** | Retrieve mail; server stores state; sync across devices | 993 (SSL) | Modern standard; server is source of truth |
| **POP3** | Download and delete from server | 995 (SSL) | Legacy; not recommended; no sync |
| **MIME** | Format for attachments, HTML, multi-part | — | Base64 encoding of binary attachments |

### Architecture

```
Send path:
User → SMTP Submission Server → Antispam check → Message Queue (Kafka)
                                                → Outbound MTA (SMTP relay to recipient's MX)
                                                → Store in Sent folder

Receive path:
Sender's MTA → Inbound MTA (our SMTP listener) → Antispam + Antivirus
                                               → Content parsing (extract attachments)
                                               → Store message in Email Storage
                                               → Deliver to user's inbox (IMAP notification)
                                               → Push notification to mobile client
```

### Email Storage — Per-User Mailbox

**Key challenge**: Billions of small objects (emails) vs traditional object storage which optimizes for large files.

**Options**:

| Storage | Pros | Cons |
|---------|------|------|
| **POSIX filesystem** | Simple; per-user Maildir format | Doesn't scale to billions of files; inode exhaustion |
| **NoSQL (Cassandra)** | High write throughput; partition by (user_id, folder) | Blob storage not native; 10 MB row limit |
| **MySQL + S3 hybrid** | Metadata (header, labels) in MySQL; body + attachments in S3 | Best of both; complex implementation |
| ⭐ **Purpose-built (Gmail's Colossus + Bigtable)** | Custom; optimized for email access patterns | Only feasible at Google scale |

**Practical design** (book's approach):
```sql
CREATE TABLE email_metadata (
    user_id     BIGINT,
    email_id    BIGINT,        -- Snowflake ID
    folder      VARCHAR(50),
    subject     TEXT,
    from_addr   VARCHAR(255),
    to_addrs    JSON,
    body_ref    VARCHAR(255),  -- S3 key for body
    attachment_refs JSON,      -- S3 keys for attachments
    received_at TIMESTAMP,
    read        BOOLEAN DEFAULT FALSE,
    labels      JSON,
    PRIMARY KEY (user_id, folder, email_id)  -- Cassandra partition
);
```

### Search Design

Full-text search across billions of emails per user:

- **Option 1 — Elasticsearch**: Index each email's body + subject + from/to. Per-user index or shared index with user_id filter. Challenge: 1B users × N emails = massive index; per-user search requires ACL filtering.
- **Option 2 — Client-side search index**: On mobile, index emails locally (SQLite FTS5); works offline; scalable. Limited to downloaded emails.
- **Option 3 — Hybrid**: Server-side Elasticsearch for header search (subject, from, to) + client-side for body search.

**Index schema** (Elasticsearch):
```json
{
  "user_id": "...",
  "email_id": "...",
  "subject": "Project proposal",
  "from": "alice@example.com",
  "body": "Please find attached...",
  "labels": ["work", "important"],
  "received_at": "2024-01-15T10:00:00Z"
}
```

Routing by `user_id` ensures user's emails land on same shard → efficient user-scoped search.

### Anti-Spam Pipeline

```
Inbound email → SPF/DKIM/DMARC validation (sender authentication)
             → IP reputation check (blocklist lookup)
             → Content analysis (ML classifier: spam probability score)
             → URL scanning (check links against phishing databases)
             → Antivirus (attachment scanning via ClamAV or commercial)
             → Decision: deliver / spam folder / reject
```

**DKIM**: Sender signs email headers with private key; recipient verifies with public key from DNS TXT record → proves email wasn't tampered in transit.

### Principal Engineer Extensions
- **Email threading**: Group replies into threads. Thread ID = first email's message-id; each reply's `In-Reply-To` header chains to parent. Store `thread_id` on all messages; query by thread_id.
- **Large attachment handling**: Upload attachment separately to S3; email body contains Content-ID reference; streaming download direct from S3 → email delivery server never touches attachment bytes.
- **Delivery failure handling**: SMTP `5xx` = permanent failure → send bounce; `4xx` = temporary → retry queue with exponential backoff × 4 days max.

---

## Chapter 9 — S3-Like Object Storage

### Problem Statement
Design a scalable object storage system (like Amazon S3, Google Cloud Storage) that stores arbitrary binary objects accessed via HTTP with high durability and availability.

### Requirements

**Functional**:
- `PUT /bucket/key` — upload object (up to 5 TB with multipart)
- `GET /bucket/key` — download object
- `DELETE /bucket/key` — delete
- `LIST /bucket/?prefix=...` — list objects with optional prefix filter
- Bucket policies, ACLs, versioning (optional)

**Non-Functional**:
- Scale: 100M buckets; 1T objects; 1 EB total data
- Durability: 11 nines (99.999999999%) — comparable to S3 Standard
- Availability: 99.99%
- Throughput: 100 GB/s aggregate read/write
- Latency: first-byte < 200 ms for objects < 1 MB

### Durability Design — Erasure Coding

**Replication (3×)**: 3 copies = 200% storage overhead. 11 nines requires 8+ replicas. Too expensive.

**Erasure coding (Reed-Solomon)**:
- Split object into K data chunks + M parity chunks
- Any K of K+M chunks can reconstruct the object
- Storage overhead: (K+M)/K

Common configuration: `RS(6,3)` — 6 data + 3 parity = 50% overhead vs 200% for 3-way replication, with comparable durability.

**Durability calculation** (RS 6,3):
- Need to lose 4+ specific chunks simultaneously for data loss
- Annual failure rate per disk ≈ 1%
- P(lose any 4 of 9 chunks in same year) ≈ 10⁻¹¹ ≈ 11 nines ✓

**Trade-off**: Erasure coding = higher compute cost on read (reconstruct from K chunks); replication = trivial reads (serve any replica directly).

### Architecture

```
Client → LB → API Service (metadata lookup + routing)
                   ↓              ↓
            Metadata Store    Data Store
            (MySQL cluster)   (Chunk Servers)
            object metadata:  Store erasure-coded
            key, checksum,    chunks on local disk
            location of chunks
```

**Data flow — write**:
```
1. Client: PUT /bucket/key (headers: Content-Length, Content-MD5)
2. API Service: check ACL, allocate object_id, determine data nodes
3. API Service streams data to 9 chunk servers (6 data + 3 parity) in parallel
4. Chunk servers write to local disk; return ACK
5. API Service writes metadata: (object_id, bucket, key, size, checksum, chunk_locations) to MySQL
6. Return HTTP 200 with ETag (MD5 of object)
```

**Data flow — read**:
```
1. Client: GET /bucket/key
2. API Service: look up metadata → get chunk locations
3. Fetch K chunks in parallel from chunk servers (only need 6 of 9)
4. Reconstruct object (or stream directly if all K data chunks available)
5. Verify checksum; return to client
```

### Metadata Design

```sql
CREATE TABLE objects (
    object_id   BIGINT PRIMARY KEY,
    bucket_id   BIGINT,
    key         VARCHAR(1024),
    size        BIGINT,
    checksum    CHAR(64),   -- SHA-256
    created_at  TIMESTAMP,
    version     INT DEFAULT 1,
    is_deleted  BOOLEAN DEFAULT FALSE,
    UNIQUE (bucket_id, key, version)
);

CREATE TABLE object_chunks (
    object_id   BIGINT,
    chunk_index INT,
    server_id   INT,
    chunk_path  VARCHAR(255),
    PRIMARY KEY (object_id, chunk_index)
);
```

### Multipart Upload (Large Files)

1. `POST /bucket/key?uploads` → initiate; get `upload_id`
2. `PUT /bucket/key?partNumber=1&uploadId=...` → upload each 5–500 MB part; get ETag
3. `POST /bucket/key?uploadId=...` with all ETags → complete; server assembles
4. `DELETE /bucket/key?uploadId=...` → abort; clean up partial parts

Client uploads parts in parallel → 10 parallel × 100 Mbps = 1 Gbps effective upload.

### Garbage Collection

- Deleted objects: mark `is_deleted=true`; GC job runs nightly to reclaim chunks
- Multipart aborts: orphaned part chunks cleaned up after 7 days
- Versioned objects: expired versions collected based on lifecycle policy

### Principal Engineer Extensions
- **Pre-signed URLs**: API generates time-limited signed URL for private objects → client downloads directly from data nodes, bypassing API server (reduces API server bandwidth)
- **Cross-region replication**: Asynchronously replicate objects to another region; uses change data capture on metadata DB → triggers replication workers
- **Storage tiering**: Hot tier (SSD, low latency) → Warm tier (HDD, 90-day-old objects) → Cold tier (tape/Glacier, 1-year-old) based on access patterns. Lifecycle policies automate transitions.

---

## Chapter 10 — Real-Time Gaming Leaderboard

### Problem Statement
Design a real-time leaderboard for a game showing top 10 players globally and a user's rank among their percentile. Score updates happen frequently; rank must be computed in real-time.

### Requirements

**Functional**:
- `POST /score` — update a player's score
- `GET /leaderboard/top?n=10` → top N players globally
- `GET /leaderboard/rank/{user_id}` → rank and score for a specific user
- Leaderboard reflects score changes within 1 second

**Non-Functional**:
- Scale: 25M DAU; 5M concurrent players during peak
- Score updates: 5M updates/s during tournaments
- Query latency: top-10 and rank queries < 100 ms
- Accuracy: exact rank is required (no approximation)

### Data Structure — Redis Sorted Set

Redis Sorted Set (ZSET) is the perfect data structure for leaderboards:
- `ZADD leaderboard score user_id` — add/update score: O(log N)
- `ZREVRANK leaderboard user_id` — rank (0-indexed, highest first): O(log N)
- `ZREVRANGE leaderboard 0 9 WITHSCORES` — top 10: O(log N + 10)
- `ZREVRANGEBYSCORE leaderboard +inf -inf LIMIT 0 100` — top 100: O(log N + 100)

**With 25M players** in a single sorted set:
- Memory: ~25M × (8 bytes score + 8 bytes pointer + ~50 bytes user_id) ≈ 1.65 GB — fits in RAM
- ZADD at 5M ops/s: single Redis node tops out at ~100K ops/s → need to shard or pipeline

### Sharding the Sorted Set

**By score range**:
- Shard 1: scores 0–10,000
- Shard 2: scores 10,001–50,000
- Shard N: scores 50,001+
- `ZREVRANK` on sharded set: query the shard containing the player's score; count players in higher shards → global rank = `players_in_higher_shards + rank_within_shard`

**By user_id (hash-based)**:
- All shards have the same score distribution
- `ZREVRANGE` (top 10) requires querying all shards + merge sort → expensive
- Best for write throughput; poor for global top-N queries

**Best choice**: Score range sharding for this problem — top-N query is efficient (only the top shard), and global rank is computable in O(shards × log N) time.

### Near Real-Time Updates Pipeline

For 5M score updates/s, Redis can't handle directly. Use a stream:

```
Game Server → Kafka (score_updates topic, partitioned by user_id)
                   ↓
            Score Aggregation Service (Flink, 1-second window)
            Aggregates: take max score per user per window
                   ↓
            Redis ZADD (batched; pipeline multiple updates)
                   ↓
            MySQL (persistent storage; sync every 5 min for durability)
```

**Why aggregate before Redis**: 1M score updates for 1M users in 1 second → can batch ZADD pipeline → 1 Redis round-trip for N updates vs N round-trips.

### Data Persistence

Redis is in-memory. On crash, sorted set is lost. Solutions:
- **Redis persistence (RDB + AOF)**: RDB snapshots every 5 min + AOF for every write → reconstruct after restart. Restart takes several minutes for 1.65 GB dataset.
- **MySQL as persistent backup**: Every score update also written to MySQL `player_scores(user_id, score)`. On Redis restart, reload from MySQL and rebuild sorted set.
- **Redis Cluster**: Automatic failover to replica in < 30s; no data loss if replica is in-sync.

### Principal Engineer Extensions
- **Friends leaderboard**: `ZINTERSTORE friend_leaderboard:{user_id} {user's friends' ZSETs}` → subset sorted set for friends-only view. Expensive if many friends; precompute for active users.
- **Tournament leaderboard**: Create new sorted set per tournament with TTL; auto-expire after tournament end; archive final standings to MySQL.
- **Segment rank**: "Your rank in the 25–34 age group" — maintain separate sorted sets per demographic segment; trade storage for query speed.

---

## Chapter 11 — Payment System

### Problem Statement
Design a payment processing system (like PayPal, Stripe, or an internal payments platform) that handles money movement between accounts with strong correctness guarantees.

### Requirements

**Functional**:
- Initiate payment: debit payer, credit payee (or external bank via PSP)
- Payment methods: credit card (via PSP), bank transfer (ACH), wallet balance
- Refunds, chargebacks, dispute handling
- Transaction history

**Non-Functional**:
- Correctness: zero money creation or destruction; double-spend impossible
- Exactly-once execution: network retries must not duplicate charges
- Consistency: strong; financial data cannot be eventually consistent
- Audit: every state change immutably recorded
- Regulatory: PCI-DSS compliance (no raw card numbers stored); SOC2

### Idempotency — The Most Critical Property

**Problem**: Client sends payment request → network timeout → did it process? Client retries → double charge.

**Solution**: Idempotency key
- Client generates `idempotency_key = UUID` for each payment attempt
- Server stores `(idempotency_key, response)` before returning
- If request received again with same key → return cached response immediately without re-executing

```sql
CREATE TABLE idempotency_keys (
    key         VARCHAR(64) PRIMARY KEY,
    response    JSON,
    created_at  TIMESTAMP,
    expires_at  TIMESTAMP    -- cleanup after 7 days
);

-- Before processing payment:
INSERT INTO idempotency_keys (key, response) VALUES (?, NULL)
ON DUPLICATE KEY UPDATE key=key;  -- no-op if exists

-- If insert succeeded (new key): process payment; store response
-- If insert failed (existing key): return stored response
```

### Double-Entry Bookkeeping

**Invariant**: `sum(all_debit_entries) = sum(all_credit_entries)`

Never modify account balances directly. Every transaction creates two ledger entries:

```sql
CREATE TABLE ledger_entries (
    entry_id       BIGINT PRIMARY KEY,
    transaction_id BIGINT NOT NULL,
    account_id     BIGINT NOT NULL,
    amount         DECIMAL(19,4),  -- positive = credit; negative = debit
    currency       CHAR(3),
    created_at     TIMESTAMP,
    CONSTRAINT no_orphan_entry FOREIGN KEY (transaction_id) REFERENCES transactions
);

-- Example: User A pays User B $100
-- Transaction 1:
--   Entry 1: account_A, -100.00 (debit)
--   Entry 2: account_B, +100.00 (credit)
-- Sum of entries for txn = 0 ✓ (invariant maintained)

-- Account balance = computed: SELECT SUM(amount) FROM ledger_entries WHERE account_id = ?
```

### Payment Flow — PSP Integration

```
User → Payment Service → Idempotency check
                       → Create payment record (status=PENDING)
                       → PSP API call (Stripe/Braintree) with idempotency_key
                       ← PSP returns: charge_id, status=SUCCEEDED
                       → Create ledger entries (debit user, credit merchant)
                       → Update payment record (status=COMPLETED)
                       → Webhook: notify merchant (async)
```

**PSP failure handling**:
- PSP timeout: check PSP status endpoint with charge_id; don't retry blindly
- PSP returns error: mark payment FAILED; refund if already debited
- PSP returns success but our DB write fails: write succeeds on retry because idempotency_key already exists in PSP; our DB write is idempotent via conflict handling

### Reconciliation

Daily batch job:
1. Fetch all transactions from PSP settlement report
2. Compare with internal ledger entries
3. Discrepancies → alert + manual investigation
4. "Soft" discrepancies (timing) auto-resolve within 48h; "hard" discrepancies escalate

**Reconciliation is mandatory** even with strong consistency — PSP's DB and your DB are separate systems; no distributed transaction between them.

### Failure Modes

| Failure | Risk | Mitigation |
|---------|------|-----------|
| Charge created but DB write fails | PSP charged user; no internal record | Reconciliation detects; refund issued |
| Duplicate charge (no idempotency) | User charged twice | Idempotency key on all PSP calls |
| Currency conversion error | Wrong amount charged | Immutable exchange rate stored at time of transaction; never recomputed |
| Partial refund edge case | Refund > original charge | Validate: refund_amount ≤ original_amount at application layer |

### Principal Engineer Extensions
- **FX (Foreign Exchange)**: Store amount in user's currency AND merchant's currency at time of transaction; use locked exchange rate for settlement; store both for audit
- **Payout scheduling**: Merchants paid daily/weekly; batch ledger → ACH file → bank transfer; reconcile against bank statement
- **Chargeback handling**: Card network initiates chargeback; freeze merchant funds; evidence submission window (7–30 days); dispute resolution flow

---

## Chapter 12 — Digital Wallet

### Problem Statement
Design a digital wallet system (like PayPal Balance, Venmo, or Apple Pay Cash) enabling peer-to-peer fund transfers between wallet accounts with real-time balance updates.

### Requirements

**Functional**:
- Transfer money between wallet accounts (same currency)
- Deposit from bank account; withdraw to bank account
- View transaction history and current balance
- Real-time balance update on receiver's end

**Non-Functional**:
- Correctness: zero money loss or duplication; strong consistency required
- Transfer QPS: 1,000 transfers/s; burst to 10,000/s
- Latency: transfer completes in < 1s
- Audit trail: every balance change immutably recorded
- Scalability: 100M wallet users

### Correctness Requirements — The Hard Part

Unlike eventual consistency systems, wallets require:
1. **Atomicity**: Debit A and credit B in the same atomic operation — if either fails, both fail
2. **Isolation**: Concurrent transfers must not interfere (no negative balances; no double spend)
3. **Consistency**: `sum(all_wallet_balances)` never changes (money is conserved)

**The fundamental challenge**: Distributed transactions. User A's wallet and User B's wallet may be on different database shards. Atomic cross-shard updates are expensive.

### Design Approaches

**Approach 1 — Same-shard transfers**:
- Shard users such that friends/frequent transfer partners are co-located (graph partitioning)
- Cross-shard transfers are rare; handle via saga
- Limitation: social graph is dynamic; hard to pre-partition

**Approach 2 — Centralized ledger (book's preferred)**:
- All transfers go through a single global ledger service
- Ledger uses double-entry bookkeeping (see Ch. 11)
- Ledger is sharded by account range; transfers between accounts on different shards use 2PC within the ledger service

**Approach 3 — Saga pattern with compensating transactions**:
- Debit A → if success → Credit B → if success → complete
- If Credit B fails → compensating: Refund A
- Challenge: visible intermediate state (A debited but B not yet credited)

### Distributed Transaction — 2PC vs Saga

| Approach | Consistency | Availability | Latency | Use When |
|---------|------------|-------------|---------|---------|
| **2PC (Two-Phase Commit)** | Strong | Low (coordinator SPOF; lock held during second phase) | High | Short transactions; same DB vendor; internal services |
| **Saga (choreography)** | Eventual | High | Low | Long transactions; cross-service; acceptable intermediate states |
| **Saga (orchestration)** | Eventual with compensation | High | Medium | Complex workflows; need central visibility |

**For wallet transfers** (duration < 1s, internal system): 2PC is acceptable — locks are brief; both shards are internal services. Use a transaction coordinator service.

### Balance Computation

**Option 1 — Materialized balance**: Store current balance as a column. Fast reads; risky writes (balance can drift from ledger on crash).

**Option 2 — Ledger-derived balance**: Balance = `SELECT SUM(amount) FROM ledger_entries WHERE account_id = ?`. Always correct; slow for large accounts (millions of entries).

**Option 3 — Hybrid**: Checkpoint balance periodically (e.g., daily); balance = checkpoint + sum of entries since checkpoint. Best of both: fast reads, correct on recovery.

```sql
CREATE TABLE balance_checkpoints (
    account_id     BIGINT PRIMARY KEY,
    balance        DECIMAL(19,4),
    as_of_entry_id BIGINT,    -- last ledger entry included in checkpoint
    computed_at    TIMESTAMP
);

-- Current balance query:
SELECT bc.balance + COALESCE(SUM(le.amount), 0)
FROM balance_checkpoints bc
LEFT JOIN ledger_entries le ON le.account_id = bc.account_id
    AND le.entry_id > bc.as_of_entry_id
WHERE bc.account_id = ?
GROUP BY bc.balance;
```

### Real-Time Balance Push

When B receives a transfer:
1. Transfer completes → ledger entries written → publish `balance_updated` event to Kafka
2. Notification Service consumes event → pushes WebSocket update to B's active client
3. B's wallet app balance refreshes in real-time

### Principal Engineer Extensions
- **Negative balance prevention**: Application-layer check before debit; DB CHECK constraint `CONSTRAINT positive_balance CHECK (balance >= 0)` as safety net
- **Multi-currency wallet**: Each wallet has sub-accounts per currency; FX conversion uses locked exchange rate; store original amount in source currency for audit
- **Regulatory holds**: Freeze portion of balance (fraud investigation, legal hold); freeze ledger entries marked `FROZEN`; balance query excludes frozen entries

---

## Chapter 13 — Stock Exchange

### Problem Statement
Design a stock exchange system (like NYSE or NASDAQ) supporting order submission, matching, and real-time market data distribution with microsecond-level latency.

### Requirements

**Functional**:
- Order types: market order (execute immediately at best available price), limit order (execute only at specified price or better)
- Order book: maintain bids and asks sorted by price/time priority
- Matching engine: match buy and sell orders; generate trades
- Market data: broadcast order book updates and trade confirmations in real-time
- Cancel and modify orders

**Non-Functional**:
- Latency: order to match < 1ms (microsecond target for HFT); market data < 500µs
- Throughput: 100,000 orders/s; 500,000 market data events/s
- Correctness: deterministic matching — same orders in same sequence must always produce same trades
- Durability: zero order loss; orders persisted before matching
- Fairness: strict price-time priority (FIFO at same price level)

### Order Book Design — In-Memory Priority Queue

An order book for one stock = two priority queues (heaps):
- **Bid side**: max-heap by price (highest bid at top); ties broken by FIFO
- **Ask side**: min-heap by price (lowest ask at top); ties broken by FIFO

**Matching rule**: If best bid ≥ best ask → trade executes at the resting order's price.

**Data structure choice**:
- `std::map<price, deque<Order>>` in C++: O(log N) insert/cancel; O(1) best-price lookup; cache-friendly within price level
- Red-black tree (or skip list) for price levels; deque for orders at same price level

**Performance target**: 1M orders/s per stock → 1µs per order → no garbage collection, no lock contention, no system calls in hot path.

### Matching Engine Architecture

```
[Sequencer] → [Order Book (in-memory)] → [Trade Publisher]
     ↓                  ↓                       ↓
  WAL log          Matching logic          Kafka (market data)
  (persistence)    (deterministic)         → Market Data Feed Handler → Clients
```

**Sequencer**: Assigns globally monotonic sequence number to each order. Critical: the same sequence = the same order = the same match result. All replicas process orders in the same sequence.

**Why single-threaded matching engine**: Locking at microsecond scale is catastrophically expensive. Exchange matching engines are single-threaded, process one order at a time, achieve determinism and high throughput via mechanical sympathy (cache-resident data, no memory allocation in hot path).

### Persistence — Write-Ahead Log

```
Order arrives → Sequencer assigns seq_num → WAL write (to disk/SSD)
             → ACK to client (order received; seq_num returned)
             → Order forwarded to Matching Engine
             → Match result written to trade log
```

**WAL ensures**: If matching engine crashes and restarts, replay WAL from last committed position → rebuild in-memory order book deterministically.

### Market Data Distribution

```
Matching Engine → Trade/Quote events → Multicast UDP (LAN; ultra-low latency)
                                     → Kafka (reliable distribution; slightly higher latency)
                     ↓                      ↓
          Co-located HFT firms        Retail brokers / apps
          (µs latency)                (ms latency acceptable)
```

**Multicast UDP**: No TCP handshake; no ACK; broadcast to all subscribers simultaneously. Packet loss handled by client-side sequence number gap detection + retransmit request.

**Market data protocol**: FIX protocol (Financial Information eXchange) — industry standard binary format for order and trade messages. Ultra-compact; no JSON overhead.

### FIFO Queue — Sequence Matching

**Price-Time Priority (FIFO at same price)**:
1. Best price level wins (highest bid, lowest ask)
2. Among orders at same price level → earliest arrival wins (FIFO)
3. No priority inversions allowed — exchange is liable for market manipulation if FIFO violated

**Partial fills**: Order for 1000 shares; only 300 available at matching price → execute 300-share trade; leave 700-share residual order in book.

### Exchange Resilience

| Failure | Impact | Mitigation |
|---------|--------|-----------|
| Matching engine crash | Market halted | Hot standby replayed from WAL; failover < 1s |
| Network partition (sequencer ↔ engine) | Order processing stops | Sequencer rejects new orders; drain; reconnect |
| Clock skew | Order priority incorrect | Hardware timestamping (PTP/IEEE 1588); accurate to < 1µs |
| Runaway algorithm (HFT bug) | Flood of orders; market disruption | Order rate limit per client; circuit breaker (halts trading if price moves > X% in Y seconds) |

### Principal Engineer Extensions
- **Co-location service**: Allow HFT firms to place their servers in the same data center as the exchange; sell rack space; further reduces network latency from 500µs to < 50µs
- **Dark pool**: Alternative trading venue; orders hidden from public order book; match at midpoint of bid-ask spread; reduces market impact for large block trades
- **Risk checks**: Before order enters sequencer, risk engine checks: buying power, position limits, order size limits, velocity limits. Must run in < 100µs to not add meaningful latency.
- **Audit trail**: Regulatory requirement (SEC Rule 17a-4); every order/trade event stored immutably with microsecond timestamp for 7 years; object storage with WORM (Write Once Read Many) locking.

---

## Summary: Key Patterns and Themes in Vol. 2

| Pattern | Where It Appears | What It Solves |
|---------|-----------------|---------------|
| **Geohash / Quadtree** | Ch. 1 (Proximity), Ch. 2 (Nearby Friends), Ch. 3 (Maps) | Efficient geospatial indexing and proximity queries |
| **Redis Pub/Sub + WebSocket** | Ch. 2 (Nearby Friends), Ch. 12 (Wallet) | Real-time push to connected clients |
| **Watermarks + event-time windowing** | Ch. 6 (Ad Clicks), Ch. 5 (Metrics) | Handle late-arriving events in stream processing |
| **Optimistic locking + DB UNIQUE constraint** | Ch. 7 (Hotel), Ch. 11 (Payment) | Prevent double-booking / double-spend without global locks |
| **Idempotency key** | Ch. 11 (Payment), Ch. 12 (Wallet) | Exactly-once semantics across retries |
| **Double-entry bookkeeping** | Ch. 11 (Payment), Ch. 12 (Wallet) | Immutable audit trail; money conservation invariant |
| **WAL + deterministic replay** | Ch. 13 (Exchange), Ch. 4 (Queue) | Crash recovery + exactly-once processing guarantee |
| **Erasure coding** | Ch. 9 (Object Storage) | 11-nines durability at 50% overhead vs 200% for 3× replication |
| **Contraction Hierarchies** | Ch. 3 (Maps) | Sub-millisecond routing on billion-node graph |
| **Redis Sorted Set** | Ch. 10 (Leaderboard) | O(log N) rank queries; O(1) score updates; native top-N |
| **Saga pattern** | Ch. 7 (Hotel), Ch. 11 (Payment), Ch. 12 (Wallet) | Multi-service transactions without 2PC |
| **Single-threaded matching engine** | Ch. 13 (Exchange) | Determinism + microsecond latency without lock contention |

## Vol. 1 vs Vol. 2 — What's Different at the PE Bar

| Dimension | Vol. 1 | Vol. 2 |
|-----------|--------|--------|
| **Correctness tolerance** | Eventual OK (feed 1s stale) | Zero tolerance (double charge; wrong rank) |
| **Domain knowledge required** | General distributed systems | Financial regulation; geospatial; exchange mechanics |
| **Algorithm depth** | Hash ring, Bloom filter, BFS | Contraction Hierarchies, erasure coding, HMM map-matching |
| **Failure mode complexity** | Single-service failures | Multi-service atomic failure; regulatory consequences |
| **Scale** | Millions of users | Microsecond latency; exact financial figures |
| **Trade-off stakes** | Performance vs cost | Correctness vs latency (no compromise on correctness) |
