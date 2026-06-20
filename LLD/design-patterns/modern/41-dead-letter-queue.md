# 41. Dead Letter Queue (DLQ)
**Category**: Modern / Enterprise  
**GoF**: No (Enterprise Messaging)  
**Complexity**: Low  
**Frequency in FAANG interviews**: Common

> Route messages that cannot be processed successfully (after N retry attempts or due to structural failure) to a separate queue — preventing poison-pill messages from blocking the main queue indefinitely while preserving them for inspection, alerting, and manual replay.

---

## Problem It Solves

An `OrderPlaced` event has a malformed `customerId` (null pointer in downstream serialization). The consumer throws `NullPointerException`, the message is re-enqueued, the consumer throws again — infinite retry loop, consuming CPU, blocking all later messages, and filling logs with noise. Without DLQ: one bad message (poison pill) can halt the entire consumer indefinitely. With DLQ: after 3 failures the message is moved to `order-placed.dlq`; the consumer continues processing valid messages; on-call is alerted; the bad message is inspected and either fixed-and-replayed or discarded.

## Structure (Participants)

```
   Producer ──► Main Queue ──► Consumer
                     │              │
                     │  on failure  │ fails N times
                     │  (retry 1)   │
                     │  (retry 2)   │
                     │  (retry N)   ▼
                     └──────► Dead Letter Queue ──► Alert + Inspector
                                                        │
                                          fix payload   │ replay
                                                        ▼
                                                  Main Queue
```

Key participants:
- **Main Queue**: the primary message channel; holds messages awaiting processing
- **Consumer**: processes messages; signals failure (throw / nack); broker counts retry attempts
- **Retry Policy**: configures max delivery attempts and backoff between retries
- **Dead Letter Queue**: separate queue/topic holding unprocessable messages with full metadata
- **DLQ Consumer / Inspector**: alerts on-call; allows inspection, correction, and replay

---

## Real-World Use Case: Order Processing DLQ

Order consumer processes `OrderPlaced` events. Some orders have corrupted payment data (schema mismatch after a deploy). Those messages should be quarantined, not retried forever. SLA: main queue processing must not be blocked for more than 30 seconds by a single bad message.

### Implementation

```java
// Retry policy per error type
public enum RetryPolicy {
    TRANSIENT(3, Duration.ofSeconds(5)),   // network blips → retry 3 times
    VALIDATION(1, Duration.ZERO),          // bad schema → DLQ immediately after 1 attempt
    BUSINESS_RULE(0, Duration.ZERO);       // domain violation → DLQ immediately

    final int maxAttempts;
    final Duration backoff;

    RetryPolicy(int maxAttempts, Duration backoff) {
        this.maxAttempts = maxAttempts;
        this.backoff     = backoff;
    }
}

// DLQ metadata envelope — preserves full context for debugging
public record DeadLetter<T>(
    String   originalMessageId,
    String   originalTopic,
    int      originalPartition,
    long     originalOffset,
    T        originalPayload,
    String   errorType,        // exception class name
    String   errorMessage,
    String   stackTrace,
    int      attemptCount,
    Instant  firstAttemptAt,
    Instant  deadLetteredAt,
    String   consumerGroup,
    String   consumerHost
) {}

// DLQ writer
public class DeadLetterWriter<T> {
    private final KafkaTemplate<String, DeadLetter<T>> kafkaTemplate;
    private final String dlqTopicSuffix;  // e.g. ".dlq"
    private final MeterRegistry metrics;

    public DeadLetterWriter(KafkaTemplate<String, DeadLetter<T>> kafkaTemplate,
                            String dlqTopicSuffix,
                            MeterRegistry metrics) {
        this.kafkaTemplate  = kafkaTemplate;
        this.dlqTopicSuffix = dlqTopicSuffix;
        this.metrics        = metrics;
    }

    public void send(ConsumerRecord<String, T> original, Throwable error, int attemptCount) {
        String dlqTopic = original.topic() + dlqTopicSuffix;

        DeadLetter<T> deadLetter = new DeadLetter<>(
            extractMessageId(original),
            original.topic(),
            original.partition(),
            original.offset(),
            original.value(),
            error.getClass().getName(),
            error.getMessage(),
            ExceptionUtils.getStackTrace(error),
            attemptCount,
            Instant.ofEpochMilli(original.timestamp()),
            Instant.now(),
            "order-processor",
            InetAddress.getLocalHost().getHostName()
        );

        kafkaTemplate.send(dlqTopic, original.key(), deadLetter)
            .addCallback(
                success -> log.info("Message dead-lettered: topic={} partition={} offset={}",
                    original.topic(), original.partition(), original.offset()),
                failure -> log.error("CRITICAL: Failed to write to DLQ — message will be lost!", failure)
            );

        metrics.counter("consumer.dlq.sent",
            "original_topic", original.topic(),
            "error_type", error.getClass().getSimpleName()).increment();
    }
}

// Retry-aware consumer with DLQ integration
public abstract class ResilientConsumer<T> {
    private final DeadLetterWriter<T> dlqWriter;
    private final RetryTemplate       retryTemplate;

    protected ResilientConsumer(DeadLetterWriter<T> dlqWriter, RetryPolicy defaultPolicy) {
        this.dlqWriter     = dlqWriter;
        this.retryTemplate = buildRetryTemplate(defaultPolicy);
    }

    // Template method: subclasses implement processMessage()
    public final void handle(ConsumerRecord<String, T> record, Acknowledgment ack) {
        AtomicInteger attempts = new AtomicInteger(0);

        try {
            retryTemplate.execute(ctx -> {
                attempts.incrementAndGet();
                RetryPolicy policy = classifyError(ctx.getLastThrowable());
                if (ctx.getRetryCount() >= policy.maxAttempts) {
                    throw ctx.getLastThrowable();  // exhaust retries → DLQ
                }
                processMessage(record.value());
                return null;
            });
            ack.acknowledge();

        } catch (ValidationException e) {
            // Structural error — no point retrying; DLQ immediately
            dlqWriter.send(record, e, attempts.get());
            ack.acknowledge();  // ack to prevent infinite redelivery

        } catch (Exception e) {
            // Exhausted retries
            dlqWriter.send(record, e, attempts.get());
            ack.acknowledge();
        }
    }

    protected abstract void processMessage(T payload) throws Exception;

    protected RetryPolicy classifyError(Throwable t) {
        if (t instanceof ValidationException)    return RetryPolicy.VALIDATION;
        if (t instanceof BusinessRuleException)  return RetryPolicy.BUSINESS_RULE;
        return RetryPolicy.TRANSIENT;
    }

    private RetryTemplate buildRetryTemplate(RetryPolicy policy) {
        RetryTemplate tmpl = new RetryTemplate();
        tmpl.setRetryPolicy(new SimpleRetryPolicy(policy.maxAttempts + 1));
        FixedBackOffPolicy backoff = new FixedBackOffPolicy();
        backoff.setBackOffPeriod(policy.backoff.toMillis());
        tmpl.setBackOffPolicy(backoff);
        return tmpl;
    }
}

// ─── DLQ Inspector / Replay Tool ─────────────────────────────────────────────

@Component
public class DlqInspector<T> {
    private final KafkaConsumer<String, DeadLetter<T>> consumer;
    private final KafkaTemplate<String, T>             mainTopicTemplate;
    private final ObjectMapper                         mapper;

    // List all messages in the DLQ
    public List<DeadLetter<T>> listMessages(String dlqTopic, int maxMessages) {
        consumer.subscribe(List.of(dlqTopic));
        List<DeadLetter<T>> messages = new ArrayList<>();
        ConsumerRecords<String, DeadLetter<T>> records =
            consumer.poll(Duration.ofSeconds(5));
        records.forEach(r -> messages.add(r.value()));
        return messages.stream().limit(maxMessages).collect(Collectors.toList());
    }

    // Fix and replay a dead-lettered message
    public void replay(DeadLetter<T> deadLetter, T fixedPayload) {
        mainTopicTemplate.send(deadLetter.originalTopic(),
            deadLetter.originalMessageId(), fixedPayload);
        log.info("Replayed dead letter: id={} to topic={}",
            deadLetter.originalMessageId(), deadLetter.originalTopic());
    }

    // Bulk replay (e.g. after a bad deploy rollback)
    public ReplayResult replayAll(String dlqTopic, Predicate<DeadLetter<T>> filter) {
        List<DeadLetter<T>> messages = listMessages(dlqTopic, Integer.MAX_VALUE);
        int replayed = 0;
        int skipped  = 0;
        for (DeadLetter<T> dl : messages) {
            if (filter.test(dl)) {
                replay(dl, dl.originalPayload());  // replay as-is; fix upstream first
                replayed++;
            } else {
                skipped++;
            }
        }
        return new ReplayResult(replayed, skipped);
    }
}
```

### AWS SQS Configuration

```java
// SQS DLQ wiring (declarative)
@Bean
public Queue mainQueue() {
    return QueueBuilder.durable("order-placed")
        .withDeadLetterQueue()
        .maxReceiveCount(3)                          // move to DLQ after 3 failed attempts
        .build();
}

@Bean
public Queue deadLetterQueue() {
    return QueueBuilder.durable("order-placed.dlq")
        .build();
}

// CloudFormation equivalent
// Properties:
//   RedrivePolicy:
//     deadLetterTargetArn: !GetAtt OrderPlacedDLQ.Arn
//     maxReceiveCount: 3
```

### DLQ Monitoring and Alerting

```yaml
# CloudWatch alarm on DLQ depth
- alarm_name: OrderPlacedDLQNotEmpty
  metric: ApproximateNumberOfMessagesVisible
  queue: order-placed.dlq
  threshold: 1           # alert on first message
  comparison: GreaterThanOrEqualToThreshold
  period: 60s
  evaluation_periods: 1
  alarm_actions: [PagerDutyARN]

# Datadog monitor
monitors:
  - name: "DLQ message count"
    type: metric alert
    query: max(last_5m):aws.sqs.approximate_number_of_messages_visible{queue_name:order-placed.dlq} > 0
    message: "@pagerduty Dead Letter Queue has messages — check order consumer"
```

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | `DeadLetterWriter` handles routing to DLQ; `ResilientConsumer` handles retry logic; business logic in subclass |
| Open/Closed | ✅ | New error classification rules via `classifyError()` override — no core changes |
| Liskov Substitution | ✅ | Any `ResilientConsumer` subclass processes messages with the same retry + DLQ contract |
| Interface Segregation | ✅ | `DeadLetterWriter` has one responsibility: `send()` |
| Dependency Inversion | ✅ | Consumer depends on `DeadLetterWriter` abstraction — not tied to Kafka or SQS |

---

## When to Use

- Message brokers deliver messages at-least-once (Kafka, SQS, RabbitMQ, Pub/Sub)
- Consumer failures can be caused by bad data (poison pills) or transient errors
- You need a separate channel to quarantine, alert on, and replay failed messages
- Processing SLA requires the main queue to remain unblocked even under poison-pill conditions

## When NOT to Use

- Every message failure is a transient retry (no distinction between transient and structural errors)
- Messages are small enough that discarding and reprocessing from source is cheaper
- The use case has strict ordering requirements and DLQ re-insertion would violate ordering

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Main queue unblocked — one bad message does not halt all processing | DLQ is a queue, not a system — requires operational tooling (inspector, replay) to be useful |
| Full fidelity preservation — original payload + error + metadata retained | Alert fatigue: DLQ alarms fire on every schema mismatch; distinguish severity in alerts |
| Safe retry surface: replay after fix without re-ingesting from source | Ordering is lost on replay: replayed messages interleave with current messages |
| Audit trail: failed messages visible in DLQ for post-mortems | DLQ size is bounded by retention, not processing — messages pile up without active triage |

---

**FAANG interview application**: "DLQ is the standard resilience mechanism for any event-driven system. The SLA is: no single bad message should block the main queue for more than max-retries × backoff seconds. For Kafka, implement retry as a retry topic chain (order-placed → order-placed.retry-1 → order-placed.retry-2 → order-placed.dlq) rather than in-consumer sleep — this lets other partitions make progress. For SQS, use the managed `RedrivePolicy.maxReceiveCount`. The most important operational requirement: DLQ must have an alarm that pages on-call when depth > 0, and there must be a self-service replay tool so on-call can unblock without an engineer writing custom scripts at 3am."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Idempotent Consumer](40-idempotent-consumer.md) | Complementary: Idempotent Consumer handles duplicates; DLQ handles unprocessable messages — apply both in every consumer |
| [Retry with Backoff](34-retry-backoff.md) | DLQ is the final destination after Retry with Backoff exhausts its attempts |
| [Circuit Breaker](29-circuit-breaker.md) | Circuit Breaker detects systematic downstream failure; DLQ captures the individual messages that failed during an open circuit |
| [Outbox Pattern](28-outbox-pattern.md) | Outbox guarantees publication; DLQ guarantees no message is silently lost during consumption — together they provide end-to-end delivery reliability |
