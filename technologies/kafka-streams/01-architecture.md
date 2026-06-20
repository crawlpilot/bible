# Kafka Streams — Architecture

## Core Concepts

Kafka Streams models stream processing as a **directed acyclic graph of stream processors** (a topology). Each node in the graph is a processor; edges are the streams of records flowing between them.

```
Source Processor (reads from Kafka topic)
        │
        ▼
Stream Processor (filter, map, flatMap, join, aggregate...)
        │
        ▼
Sink Processor (writes to Kafka topic)
```

The topology is defined in code using either:
- **DSL (high-level)**: `KStream`, `KTable`, `GlobalKTable` with functional operators
- **Processor API (low-level)**: implement `Processor<K,V>` for custom logic, custom state stores

---

## KStream vs KTable vs GlobalKTable

This is the most important conceptual distinction in Kafka Streams.

| Abstraction | Semantics | Update semantics | Storage |
|------------|-----------|-----------------|---------|
| **KStream** | Unbounded event stream — each record is an independent event | Append: every record is processed | No state (stateless by default) |
| **KTable** | Partitioned changelog table — each record is an upsert (key → latest value) | Upsert: new record for key replaces previous | Local RocksDB + changelog topic |
| **GlobalKTable** | Same as KTable but replicated to ALL instances (all partitions) | Upsert (global) | Local RocksDB on every instance |

### Stream-Table Duality

```
KStream (event log view):          KTable (table view):
  offset 0: user:1 → {city: NY}     user:1 → {city: SF}   ← only latest
  offset 1: user:2 → {city: LA}     user:2 → {city: LA}
  offset 2: user:1 → {city: SF}     (user:1's NY entry superseded)
  offset 3: user:3 → {city: Chicago} user:3 → {city: Chicago}

  Converting:
  KStream → KTable: toTable()       → compact by key
  KTable  → KStream: toStream()     → emit all change events
```

**When to use each**:
- `KStream`: event logs (clicks, transactions, sensor readings) where every event matters
- `KTable`: reference data or mutable entity state (user profile, product price, order status)
- `GlobalKTable`: small-to-medium reference data needed by ALL instances for enrichment (avoids repartitioning on join)

---

## Topology Example

```java
StreamsBuilder builder = new StreamsBuilder();

// Source: raw order events from Kafka
KStream<String, Order> orders = builder.stream("order-events",
    Consumed.with(Serdes.String(), orderSerde));

// Reference table: latest user profile per userId (from Kafka topic, CDC-fed)
KTable<String, UserProfile> users = builder.table("user-profiles",
    Consumed.with(Serdes.String(), userSerde));

// Enrich orders with user profile
KStream<String, EnrichedOrder> enriched = orders
    .filter((key, order) -> order.getStatus().equals("PLACED"))
    .join(users,
          (order, user) -> new EnrichedOrder(order, user),    // joiner
          Joined.with(Serdes.String(), orderSerde, userSerde));

// Window: count orders per userId per 5-minute tumbling window
KTable<Windowed<String>, Long> orderCounts = enriched
    .groupByKey()
    .windowedBy(TimeWindows.ofSizeWithNoGrace(Duration.ofMinutes(5)))
    .count(Materialized.as("order-count-store"));   // named state store → queryable

// Sink: write enriched orders to output topic
enriched.to("enriched-orders", Produced.with(Serdes.String(), enrichedOrderSerde));

// Build and start
KafkaStreams streams = new KafkaStreams(builder.build(), config);
streams.start();
```

---

## Task Assignment and Partitioning

Kafka Streams assigns **tasks** (not threads) based on partition count. Each task owns one input partition (or one co-partitioned group of partitions for joins).

```
Input topic: "order-events" (4 partitions)
Input topic: "user-profiles" (4 partitions)  ← must be co-partitioned for KStream-KTable join

Tasks:
  Task 0 → order-events[0] + user-profiles[0]
  Task 1 → order-events[1] + user-profiles[1]
  Task 2 → order-events[2] + user-profiles[2]
  Task 3 → order-events[3] + user-profiles[3]

Instance A (2 stream threads): Task 0, Task 1
Instance B (2 stream threads): Task 2, Task 3

Scale to 4 instances: each instance gets 1 task (1 stream thread each).
Scale beyond 4 instances: extra instances are idle (no more tasks than partitions).
```

**Co-partitioning requirement**: For KStream-KTable joins, both topics must have the **same number of partitions** and use the **same partitioner** (default: hash of key). If they don't match, Kafka Streams will throw an error at topology validation.

---

## State Stores

State stores are per-task, per-key stores backed by **RocksDB** (persistent) or **in-memory HashMap** (dev only).

```
Task 0 owns:
  Local RocksDB store: "order-count-store"
    user:1 → 42 (orders in current window)
    user:3 → 17
    ...

  Kafka changelog topic: "my-app-order-count-store-changelog"
    Partition 0 (mirrors Task 0's state as a compacted Kafka topic)
    offset 0: user:1 → 42
    offset 1: user:3 → 17
```

On crash and reassignment:
1. New instance picks up Task 0
2. Restores state by replaying `order-count-store-changelog` partition 0 from offset 0
3. Resumes consuming from `order-events` partition 0 at the committed offset

**Standby replicas** (`num.standby.replicas=1`): A second instance pre-fetches the changelog and maintains a warm copy. On failover, standby instance is fully caught up → near-instant recovery.

---

## GlobalKTable

A `GlobalKTable` is populated from **all partitions** of a Kafka topic on every running instance. Useful for small reference data that every instance needs for joins without repartitioning.

```
GlobalKTable<String, Country> countries = builder.globalTable("countries");
// All instances read all 4 partitions of "countries"
// Every instance has the full dataset in local RocksDB

KStream<String, Order> orders = builder.stream("orders");
orders.join(countries,
    (orderId, order) -> order.getCountryCode(),   // key extractor from stream record
    (order, country) -> enrich(order, country));   // joiner

// No repartitioning needed: key lookup in local GlobalKTable RocksDB
```

**When to use GlobalKTable vs KTable**:
- `KTable`: large tables that need to be sharded (user profiles, product catalog)
- `GlobalKTable`: small-to-medium lookup tables where the full dataset fits in memory per instance (country codes, feature flags, currency rates — typically < 100MB)

---

## Exactly-Once Processing

```properties
# Enable exactly-once v2 (Kafka 2.5+, preferred)
processing.guarantee=exactly_once_v2
```

With exactly-once, each `poll → process → produce + commit` cycle is wrapped in a **Kafka transaction**:

```
For each poll batch:
  1. Begin Kafka transaction (producer.beginTransaction())
  2. Process records; write to state store (RocksDB local write)
  3. Produce output records to output topic (within transaction)
  4. Write state store changelog records to changelog topic (within transaction)
  5. Commit input offsets to __consumer_offsets (within transaction)
  6. Commit Kafka transaction (all-or-nothing)

On crash before step 6: transaction aborted → output and changelog rolled back
  → Replay from last committed offset → no duplicates, no data loss
```

**Overhead**: exactly-once v2 requires 1 transactional producer per stream thread. Each commit (default every 100ms) involves Kafka transaction coordination. Throughput overhead: ~10–20% vs at-least-once.

---

## Interactive Queries

Kafka Streams allows querying local state stores from outside the application:

```java
// In the application: expose a REST endpoint
ReadOnlyKeyValueStore<String, Long> store = streams.store(
    StoreQueryParameters.fromNameAndType("order-count-store", QueryableStoreTypes.keyValueStore()));

Long count = store.get("user:42");   // returns null if key not in this instance's partition

// Client: must query the right instance (which owns the partition for user:42)
// Kafka Streams metadata API reveals which instance owns which key:
KeyQueryMetadata metadata = streams.queryMetadataForKey("order-count-store", "user:42", Serdes.String().serializer());
HostInfo host = metadata.activeHost();  // → host:port of the instance owning this key
// Route REST request to that instance
```

This enables building **queryable microservices** where the service owns both the processing and the queryable state, without a separate cache or database.

---

## FAANG Interview Callout

> "Kafka Streams' architecture is elegantly simple: tasks map 1:1 to input partitions; each task owns a local RocksDB state store that is durably backed by a Kafka changelog topic; scaling is just adding instances up to the partition count. The stream-table duality is the key abstraction: a KTable is just a KStream compacted to keep only the latest value per key, and I can join a KStream of events with a KTable of reference data to enrich events without hitting a database. For exactly-once, Kafka Streams wraps each process-and-produce cycle in a Kafka transaction — if the instance crashes before committing, the transaction rolls back and the records are reprocessed from the last committed offset. The main operational concern is standby replicas: with `num.standby.replicas=1`, a second instance pre-warms the state from the changelog so failover is seconds, not minutes."

---

## Related Files

| File | Topic |
|------|-------|
| [02-read-write-path.md](02-read-write-path.md) | Record flow, join internals, windowing, state access |
| [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) | Kafka Streams vs Flink vs ksqlDB vs Faust |
| [04-tuning-guide.md](04-tuning-guide.md) | Thread count, cache, commit interval, RocksDB, standby replicas |
