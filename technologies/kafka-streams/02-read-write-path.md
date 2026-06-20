# Kafka Streams — Record Flow, Joins, and State

## Record Processing Loop

Kafka Streams runs a tight poll → process → produce loop per stream thread:

```
Stream Thread (one per num.stream.threads)
  │
  │  1. consumer.poll(Duration.ofMillis(100))
  │     → fetches records from assigned Kafka partitions
  │
  ▼
  RecordQueue (per partition, sorted by timestamp)
  │
  │  2. Select next record (partition with oldest timestamp → timestamp ordering)
  │
  ▼
  Source Processor
  │
  │  3. Deserialize key + value (configured Serde)
  │
  ▼
  Stream Processors (filter, map, join, aggregate...)
  │
  │  4. State store reads/writes (RocksDB local call — sub-ms)
  │
  ▼
  Sink Processor
  │
  │  5. Serialize + produce to output Kafka topic (via internal KafkaProducer)
  │
  ▼
  Commit (every commit.interval.ms, default 100ms):
    - Flush state store caches to RocksDB
    - Flush changelog producer (state changes to changelog topic)
    - Commit input consumer offsets
    (If exactly_once_v2: all of the above in one Kafka transaction)
```

### Timestamp Ordering Across Partitions

When a stream thread owns multiple tasks (multiple input partitions), Kafka Streams selects the next record to process from the **partition with the oldest timestamp** — ensuring approximate event-time ordering across partitions within a single thread.

---

## Joins

### KStream-KTable Join (Enrichment)

The most common join pattern: enrich a stream event with the latest value from a reference table.

```
KStream<String, Order>       orders  (key = orderId)
KTable<String, UserProfile>  users   (key = userId)

// Re-key orders by userId before joining
orders
    .selectKey((orderId, order) -> order.getUserId())    // triggers repartition
    .join(users,
          (order, user) -> new EnrichedOrder(order, user));
```

```
For each order event arriving:
  1. Look up users KTable local RocksDB store by userId (the re-keyed key)
  2. If found: emit enriched record downstream
  3. If not found: emit null (or filter out) — user not yet in the table
```

**Important**: KStream-KTable join is **non-windowed** and **lookup-based** (not symmetric). The KTable side is always the latest value. The KStream drives the join; KTable updates don't trigger new join output.

### KStream-KStream Join (Windowed)

Both sides are event streams. Records are matched if they share the same key AND arrive within a join window.

```java
orders.join(
    payments,
    (order, payment) -> new MatchedPair(order, payment),
    JoinWindows.ofTimeDifferenceWithNoGrace(Duration.ofMinutes(5)),
    StreamJoined.with(Serdes.String(), orderSerde, paymentSerde));
```

```
Window = 5 minutes:
  order(key=order:1, t=10:00) arrives → buffered in state store
  payment(key=order:1, t=10:03) arrives → match found (within 5min) → emit pair
  order(key=order:2, t=10:00) arrives → buffered
  payment(key=order:2, t=10:07) arrives → NO MATCH (7min apart > 5min window)
```

Both sides are buffered in **windowed state stores** (RocksDB). State expires when the window closes (+ grace period). Memory usage = records per key per window × window duration.

### KTable-KTable Join

Both tables are joined by key. Whenever either table is updated, the join is recomputed for that key.

```java
KTable<String, Order>       orders;    // latest order per orderId
KTable<String, Shipment>    shipments; // latest shipment per orderId

KTable<String, OrderWithShipment> joined = orders.join(shipments,
    (order, shipment) -> new OrderWithShipment(order, shipment));
// Output KTable: updated whenever order OR shipment changes for the same key
```

---

## Windowing

```java
// Tumbling window: 5-minute, non-overlapping
.windowedBy(TimeWindows.ofSizeWithNoGrace(Duration.ofMinutes(5)))

// Hopping window: 10-minute window, slides every 5 minutes
.windowedBy(TimeWindows.of(Duration.ofMinutes(10)).advanceBy(Duration.ofMinutes(5)))

// Session window: closes after 30min of inactivity per key
.windowedBy(SessionWindows.ofInactivityGapWithNoGrace(Duration.ofMinutes(30)))
```

**Grace period**: Allows late records to be incorporated into a window after it closes.

```java
// Allow events up to 1 minute late
TimeWindows.ofSizeAndGrace(Duration.ofMinutes(5), Duration.ofMinutes(1))
```

With no grace period: window closes immediately at end time; late records are **dropped**.

### Windowed Output Keys

Aggregation over windows produces `Windowed<K>` keys:

```
KTable<Windowed<String>, Long> counts = stream
    .groupByKey()
    .windowedBy(TimeWindows.ofSizeWithNoGrace(Duration.ofMinutes(5)))
    .count();

// Output record key: Windowed("user:1", [2024-01-15T10:00, 2024-01-15T10:05))
// Output record value: 42
```

---

## State Store Access

```java
// In a Processor or Transformer — direct state store access
public class DeduplicationProcessor implements Processor<String, Event, String, Event> {

    private KeyValueStore<String, Long> seenStore;

    @Override
    public void init(ProcessorContext<String, Event> context) {
        // Get the store registered in the topology
        seenStore = context.getStateStore("seen-events");
    }

    @Override
    public void process(Record<String, Event> record) {
        String eventId = record.value().getId();
        if (seenStore.get(eventId) == null) {
            seenStore.put(eventId, record.timestamp());   // mark as seen
            context().forward(record);                    // pass through
        }
        // else: duplicate — silently drop
    }
}
```

**State TTL**: Kafka Streams does not have native TTL on state stores. Common patterns:
- Use windowed stores (auto-expire by window close)
- Implement a scheduled cleanup via `punctuate()` (called on a timer)

```java
// Schedule periodic cleanup every 1 hour
context.schedule(Duration.ofHours(1), PunctuationType.WALL_CLOCK_TIME, timestamp -> {
    try (KeyValueIterator<String, Long> it = seenStore.all()) {
        while (it.hasNext()) {
            KeyValue<String, Long> kv = it.next();
            if (timestamp - kv.value > Duration.ofHours(24).toMillis()) {
                seenStore.delete(kv.key);
            }
        }
    }
});
```

---

## Repartitioning

Operations that change the key (`.selectKey()`, `.map()` that changes the key) trigger an **internal repartition topic**:

```
orders.selectKey((k, v) -> v.getUserId())   // changes key from orderId to userId
      .join(users, ...)

Internally:
  Step 1: Produce all orders to repartition topic ("my-app-orders-repartition") keyed by userId
  Step 2: Consume from repartition topic → ensures co-partitioning with users KTable
```

Repartition topics have the same partition count as the input. This guarantees that after repartitioning, records with the same key land on the same task as the KTable records for that key.

**Cost**: extra Kafka topic write + read; extra latency. Avoid unnecessary key changes.

---

## Changelog Topics

Every persistent state store has a corresponding **changelog topic** that acts as its durable backup:

```
State store: "order-count-store" (RocksDB, Task 0)
Changelog topic: "my-app-order-count-store-changelog" (Partition 0)

On every state write:
  RocksDB write (synchronous, local)
  Changelog produce (buffered in record cache, flushed at commit)

On restore (new instance takes over Task 0):
  Seek changelog partition 0 to beginning
  Replay all records → rebuild RocksDB store
  Resume consuming from order-events partition 0
```

Changelog topics are **compacted** (only latest value per key retained) to bound restore time.

---

## Interactive Queries in Detail

```java
// Expose local state via REST
get("/count/:userId", (req, res) -> {
    String userId = req.params("userId");

    // Find which instance owns this key
    KeyQueryMetadata metadata = streams.queryMetadataForKey(
        "order-count-store", userId, Serdes.String().serializer());

    if (metadata.activeHost().equals(myHostInfo)) {
        // This instance owns it — query locally
        ReadOnlyKeyValueStore<String, Long> store = streams.store(
            StoreQueryParameters.fromNameAndType("order-count-store",
                QueryableStoreTypes.keyValueStore()));
        return store.get(userId);
    } else {
        // Forward to the owning instance
        return httpClient.get("http://" + metadata.activeHost().host()
            + ":" + metadata.activeHost().port() + "/count/" + userId);
    }
});
```

This pattern turns your Kafka Streams application into a **queryable microservice** — no separate cache needed for reads.

---

## FAANG Interview Callout

> "Kafka Streams' processing loop is: poll records → process through the topology (state store reads/writes are local RocksDB calls — sub-millisecond) → produce output → commit. The commit atomically flushes the state changelog and commits the input offset, giving exactly-once semantics without an external coordinator. Joins in Kafka Streams require co-partitioning — both topics must have the same number of partitions and the same key. When enriching a KStream with a KTable, I re-key the stream by the join key first, which triggers an internal repartition topic. For interactive queries, the application exposes a REST endpoint; Kafka Streams' metadata API tells you which instance owns a given key, so you route the request to the right instance — this is the foundation for building a self-contained queryable microservice without a separate database."
