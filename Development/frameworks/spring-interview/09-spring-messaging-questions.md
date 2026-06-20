# Spring Messaging — Interview Questions

---

## Fundamentals (L3–L4)

**Q1. What is `@KafkaListener` and how does it work?**
`@KafkaListener` marks a method as a Kafka consumer. Spring creates a `KafkaMessageListenerContainer` that polls the Kafka broker in a background thread. When messages arrive, it deserializes them and invokes the annotated method. The `groupId` determines the consumer group — Kafka assigns partitions across all members.

**Q2. What is a consumer group in Kafka?**
Multiple consumers with the same `group.id` form a group. Kafka distributes partitions evenly across group members — each partition is consumed by exactly one member. Scaling: add consumers up to the partition count; beyond that, extras sit idle. This enables parallel consumption while guaranteeing each message is processed once per group.

**Q3. What is a Dead Letter Topic (DLT)?**
When a message fails to process after N retries, it's published to a DLT (e.g., `orders.created-dlt`). This prevents poison pill messages from blocking the partition. The DLT is monitored for investigation and replay. Spring Kafka's `DefaultErrorHandler` + `DeadLetterPublishingRecoverer` handles this automatically.

**Q4. What is the difference between RabbitMQ Direct, Topic, and Fanout exchanges?**
- **Direct**: routes to queue whose binding key exactly matches routing key — point-to-point
- **Topic**: routes to queues whose binding keys match a wildcard pattern (`*` = one word, `#` = zero or more) — flexible pub/sub
- **Fanout**: broadcasts to ALL bound queues, ignores routing key — pure broadcast

**Q5. What is `auto.offset.reset` in Kafka?**
When a consumer group starts for the first time (no committed offset), or when the committed offset is no longer valid (expired):
- `earliest`: start from the beginning of the partition — reads all historical messages
- `latest`: start from the end — reads only new messages published after consumer started
Production default: `earliest` to ensure no message is missed on service restart.

---

## Advanced (L5 Senior)

**Q6. What is exactly-once delivery in Kafka and how does Spring support it?**
Exactly-once requires:
1. **Producer**: `enable.idempotence=true` + `transactional.id` — ensures no duplicate on retry
2. **Consumer**: `isolation.level=read_committed` — only reads messages from committed transactions
3. **Processing**: idempotent business logic — even if delivered once, operation must be safe to re-execute

In Spring: `@Transactional("kafkaTransactionManager")` on the producer method publishes atomically. The consumer must be within the same Kafka transaction scope for true end-to-end exactly-once.

**Q7. How does `@RetryableTopic` work in Spring Kafka?**
Creates retry topics automatically: `orders.created-retry-0`, `orders.created-retry-1`, `orders.created-dlt`. Failed messages are published to retry topics with backoff headers. Separate consumer groups consume retry topics after the backoff delay. After N retries, message goes to DLT. Non-blocking — main partition consumers are not delayed.

**Q8. How do you ensure message ordering in Kafka?**
Ordering is guaranteed within a partition. To ensure ordered processing:
1. Use the same partition key for related messages: `kafkaTemplate.send(topic, customerId, event)` — all events for a customer go to the same partition
2. Single consumer per partition within a group (automatic via partition assignment)
3. Do NOT increase concurrency (`concurrency="1"` for ordered processing within a topic)

**Q9. What is the difference between `ack.acknowledge()` and auto-commit?**
- **Auto-commit** (`enable.auto.commit=true`): Kafka commits offsets on a timer (default 5s) — may commit before processing is done → message loss on crash
- **Manual ack** (`AckMode.MANUAL`): you call `ack.acknowledge()` after successful processing — offsets committed only after success; guarantees at-least-once delivery
- Production: always manual ack.

**Q10. How does Spring AMQP handle message acknowledgment?**
```java
@RabbitListener(queues = "orders")
public void handleOrder(Order order, Channel channel,
                         @Header(AmqpHeaders.DELIVERY_TAG) long tag) throws IOException {
    try {
        processOrder(order);
        channel.basicAck(tag, false);          // success: remove from queue
    } catch (BusinessException e) {
        channel.basicNack(tag, false, false);  // failure: don't requeue → DLX
    } catch (TransientException e) {
        channel.basicNack(tag, false, true);   // transient: requeue for retry
    }
}
```

---

## Principal Engineer Level

**Q11. How do you design an event-driven order processing system with Spring Kafka?**

```
[Order Service] → Kafka: orders.created
     |
     ├── [Inventory Service] consumes → reserves stock → publishes: inventory.reserved
     |        └── [Inventory DLT consumer] → alerts on failure
     |
     ├── [Payment Service] consumes → charges → publishes: payment.completed
     |        └── [Payment DLT consumer] → reversal saga + alert
     |
     └── [Notification Service] consumes → sends email/SMS
              └── @RetryableTopic (3 retries → DLT)
```

Principal considerations:
- **Saga pattern**: each service publishes success/failure events; compensating transactions on failure
- **Idempotency**: each service stores `orderId` as processed key; duplicate events are no-ops
- **Schema Registry**: Avro schemas with compatibility checks prevent breaking consumers
- **Partition count**: designed for peak throughput (target partitions = peak consumers × 2)
- **Consumer lag monitoring**: alert when lag exceeds 10K messages → scale consumers

**Q12. How do you handle out-of-order events in Kafka?**
Kafka guarantees order within a partition, but multi-partition setup can deliver related events out of order if they land on different partitions.

Solutions:
1. **Routing by entity key**: all events for the same entity use the same key → same partition → in-order
2. **Event versioning**: include `version` or `sequence` field; consumer checks sequence before processing
3. **Sequence buffer**: if event N+1 arrives before N, buffer it until N arrives (with TTL to avoid memory leak)
4. **Eventual consistency tolerance**: design the system to handle idempotent out-of-order events gracefully

**Q13. When would you choose a message queue (RabbitMQ) over an event log (Kafka)?**

| Need | Choose |
|------|--------|
| Task queue (work distributed across consumers) | RabbitMQ |
| Event replay (consumers can reread past events) | Kafka |
| Complex routing (by headers, priority, TTL) | RabbitMQ |
| High throughput (millions/sec) | Kafka |
| Short retention (delete after ack) | RabbitMQ |
| Long retention (days/weeks, audit trail) | Kafka |
| RPC pattern (request-reply) | RabbitMQ |
| Stream processing | Kafka |
| FAANG recommendation | Kafka for new systems; RabbitMQ for legacy or complex routing |

---

## Code Walkthroughs

**Q14. Why are messages being consumed twice?**
```java
@KafkaListener(topics = "orders", groupId = "fulfillment")
public void handle(OrderEvent event) {
    fulfillmentService.process(event);
    // No ack — using AckMode.MANUAL configured globally
}
```
**Answer**: With `AckMode.MANUAL`, if `acknowledge()` is never called, the offset is never committed. On service restart, Kafka redelivers from the last committed offset — all messages since the last commit are reprocessed. Fix: inject `Acknowledgment ack` parameter and call `ack.acknowledge()` after successful processing.

**Q15. What is wrong with this Kafka producer setup for financial transactions?**
```java
Map<String, Object> config = new HashMap<>();
config.put(ProducerConfig.ACKS_CONFIG, "1");  // only leader must ack
config.put(ProducerConfig.RETRIES_CONFIG, 0);  // no retries
```
**Answer**: Two critical problems: (1) `acks=1` — if the leader crashes before replicating to ISRs, the message is lost. Financial systems require `acks=all`. (2) `retries=0` — any transient network error permanently loses the message. Should be `retries=3` with `enable.idempotence=true` to prevent duplicates from retries. Correct config for financial: `acks=all`, `enable.idempotence=true`, `retries=Integer.MAX_VALUE`, `max.in.flight.requests.per.connection=5`.

---

## Common Mistakes

| Mistake | Problem | Fix |
|---------|---------|-----|
| Auto-commit with complex processing | Message loss on crash between commit and processing | Always `enable.auto.commit=false` with manual ack |
| Retrying non-idempotent operations | Double charges, duplicate orders | Use idempotency keys; only retry safe operations |
| No DLT configured | Poison pill blocks partition forever | Always configure DLT with `DefaultErrorHandler` |
| `acks=1` for critical messages | Data loss on leader failure | `acks=all` for financial/critical data |
| Wrong partition key | Related events on different partitions → out of order | Always use entity ID as partition key |
| No consumer lag monitoring | Processing backup not detected | Alert on consumer lag > threshold |
