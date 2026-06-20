# 37. Competing Consumers
**Category**: Modern / Enterprise (Enterprise Integration Patterns)  
**GoF**: No (Hohpe & Woolf 2003, "Enterprise Integration Patterns")  
**Complexity**: Medium  
**Frequency in FAANG interviews**: Common

> Allow multiple worker instances to compete for messages from a shared queue so that work is processed concurrently and load is distributed across consumers — scaling throughput horizontally without coordination overhead.

---

## Problem It Solves

The notification service must send 500,000 transactional emails after a flash sale. A single sender processes 100 emails/s — it would take 83 minutes. Each email is independent; there's no reason work must be serialized. Multiple consumer instances each pull from the same SQS queue; the queue guarantees each message is delivered to exactly one consumer (via visibility timeout). Adding more consumers linearly increases throughput. The queue absorbs traffic bursts; consumers process at their own pace.

## Structure (Participants)

```
  OrderService ──► SQS Queue (email-notifications)
                        │
              ┌─────────┼──────────┐
              ▼         ▼          ▼
         Worker 1   Worker 2   Worker 3   ← competing consumers
           │           │          │         (each in a separate pod/instance)
           ▼           ▼          ▼
      send email   send email  send email
        (SMTP)       (SMTP)      (SMTP)
```

**Message visibility timeout prevents double-processing**:
```
Queue: [msg-A] [msg-B] [msg-C] [msg-D] [msg-E]

Worker 1 receives msg-A → msg-A becomes invisible (30s timeout)
Worker 2 receives msg-B → msg-B becomes invisible
Worker 3 receives msg-C → msg-C becomes invisible

Worker 1 processes msg-A successfully → deletes msg-A from queue
Worker 2 crashes → msg-B becomes visible again after 30s → Worker 3 picks it up
```

Key participants:
- **Message Queue** (SQS, RabbitMQ, Kafka): holds messages; guarantees at-least-once delivery; prevents double-processing via visibility timeout or consumer group offsets
- **Consumers** (`NotificationWorker`): multiple identical instances pulling from the same queue
- **Dead Letter Queue (DLQ)**: messages that fail repeatedly are moved here for investigation
- **Producer** (`OrderService`): enqueues messages; doesn't know which consumer processes them

---

## Real-World Use Case: Email Notification Service

### Implementation

```java
// Message format (envelope + payload)
public record EmailNotificationMessage(
    String messageId,           // idempotency key
    String toAddress,
    String templateId,
    Map<String, String> variables,
    String orderId,
    Instant enqueuedAt
) {}

// Consumer (Spring + SQS)
@Component
public class EmailNotificationWorker {
    private final EmailSender emailSender;
    private final TemplateEngine templateEngine;
    private final ProcessedMessageRepository processed;  // idempotency store
    private final MeterRegistry metrics;

    // @SqsListener auto-scales acknowledgment and visibility timeout management
    @SqsListener(value = "email-notifications", deletionPolicy = ON_SUCCESS)
    public void processMessage(EmailNotificationMessage msg) {
        Timer.Sample timer = Timer.start(metrics);

        try {
            // Idempotency guard — at-least-once delivery means duplicates are possible
            if (processed.exists(msg.messageId())) {
                log.info("Skipping duplicate message {}", msg.messageId());
                metrics.counter("email.duplicate", "template", msg.templateId()).increment();
                return;
            }

            String renderedBody = templateEngine.render(msg.templateId(), msg.variables());

            emailSender.send(EmailRequest.builder()
                .to(msg.toAddress())
                .body(renderedBody)
                .messageId(msg.messageId())  // SMTP dedup key
                .build());

            processed.markProcessed(msg.messageId(), Instant.now());

            timer.stop(metrics.timer("email.processing", "status", "success", "template", msg.templateId()));
            metrics.counter("email.sent", "template", msg.templateId()).increment();

        } catch (EmailSendException e) {
            timer.stop(metrics.timer("email.processing", "status", "failure"));
            metrics.counter("email.failed", "template", msg.templateId()).increment();
            log.error("Failed to send email for order {}: {}", msg.orderId(), e.getMessage());
            throw e;  // re-throw causes SQS to make message visible again (retry)
        }
    }
}

// Producer: enqueue notification on order completion
@Service
public class OrderCompletionService {
    private final SqsTemplate sqsTemplate;

    public void onOrderCompleted(Order order) {
        EmailNotificationMessage msg = new EmailNotificationMessage(
            UUID.randomUUID().toString(),   // idempotency key
            order.customerEmail(),
            "order-confirmation",
            Map.of("orderId", order.id(), "total", order.total().format()),
            order.id(),
            Instant.now()
        );
        sqsTemplate.send("email-notifications", msg);
    }
}

// Consumer scaling: Kubernetes HPA based on SQS queue depth
/*
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: email-worker-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: email-notification-worker
  minReplicas: 2
  maxReplicas: 50
  metrics:
  - type: External
    external:
      metric:
        name: sqs_approximate_number_of_messages_visible
        selector:
          matchLabels:
            queue_name: email-notifications
      target:
        type: AverageValue
        averageValue: "100"   # scale up when each worker has >100 messages waiting
*/

// Dead Letter Queue handling
@Component
public class EmailDlqProcessor {
    private final SqsTemplate sqs;
    private final AlertService alerts;

    @SqsListener("email-notifications-dlq")
    public void processDead(EmailNotificationMessage msg, @Header("ApproximateReceiveCount") int receiveCount) {
        log.error("Message {} moved to DLQ after {} attempts. Order: {}",
            msg.messageId(), receiveCount, msg.orderId());

        alerts.page(PagerDutyAlert.builder()
            .severity(CRITICAL)
            .summary("Email notification permanently failed for order " + msg.orderId())
            .details(msg.toString())
            .build());

        // Optionally: compensate — queue for manual retry or alternative channel (SMS)
        sqs.send("sms-notifications-fallback", toSmsMessage(msg));
    }
}

// Ordered processing variant: partition messages by key
// (when you need all messages for a given orderId to be processed in order)
@Configuration
public class KafkaConsumerConfig {

    // Kafka competing consumers — partition assignment ensures ordering per key
    @KafkaListener(
        topics = "order-events",
        groupId = "order-processor",    // competing consumers within same group
        concurrency = "10"              // 10 threads, each assigned subset of partitions
    )
    public void processOrderEvent(OrderEvent event, @Header(KafkaHeaders.RECEIVED_PARTITION) int partition) {
        // Messages for same orderId always go to same partition (keyed by orderId)
        // → ordering preserved per order; parallelism across orders
        orderProcessor.process(event);
    }
}
```

### How It Works (walkthrough)

1. 500,000 email messages enqueued to SQS after flash sale completes
2. HPA detects queue depth > 100 × 2 (current pods) = 200 → scales to max 50 pods
3. 50 workers each receive up to 10 messages in long-poll batches
4. Worker 1 receives msg-A; msg-A invisible for 30s. Worker processes in 200ms → deletes msg-A
5. Worker 7 crashes mid-processing: msg-G visibility expires after 30s → re-enqueued → Worker 12 picks it up
6. Worker 12 checks `processed.exists(msg-G.messageId())` → false (was never completed) → processes normally
7. Message fails 3 times → SQS moves to DLQ after `maxReceiveCount=3` → alert fires → DLQ processor runs fallback

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | `EmailNotificationWorker` processes one message; scaling is handled by HPA; queue handles delivery |
| Open/Closed | ✅ | Add a new consumer type (SMS, push) by adding a new `@SqsListener` without touching the queue or producer |
| Liskov Substitution | ✅ | Any worker instance is substitutable — stateless design ensures uniform behavior |
| Interface Segregation | ✅ | Producer and consumer only interact through the queue contract (message schema) |
| Dependency Inversion | ✅ | Worker depends on `EmailSender` interface — actual transport (SES, SendGrid) injected |

---

## When to Use

- Work items are independent (no ordering requirement or ordering is per-key)
- Processing throughput needs to scale horizontally beyond a single thread/process
- Producers spike (burst load) and consumers should smooth processing out over time
- Work items must survive consumer failures (queue persistence provides durability)
- You want decoupled deployment: producer and consumer can be deployed independently

## When NOT to Use

- Strict global ordering required across all messages (use a single consumer or Kafka with 1 partition)
- Messages have transactional dependencies — consumer failure mid-workflow requires Saga, not just retry
- Latency requirements are <10ms — queue round-trip overhead is too high (use synchronous call instead)
- Work items are very short-lived and the queue coordination overhead exceeds processing time

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Horizontal scale: adding consumers linearly increases throughput | At-least-once delivery requires idempotent consumers — duplicate processing must be safe |
| Queue absorbs producer spikes — consumers process at stable rate | Ordering not guaranteed across consumers (SQS FIFO or Kafka partitioning needed if order matters) |
| Consumer failures are transparent — visibility timeout requeues for another worker | Operational complexity: monitor queue depth, DLQ size, consumer lag, and message age |

---

**FAANG interview application**: "Competing Consumers is the fundamental pattern for async work distribution — it appears in almost every FAANG system design that involves background jobs, notifications, or data pipelines. The three things that must be explicitly designed: (1) idempotency — because at-least-once delivery means duplicate messages; use a messageId + dedupe store; (2) visibility timeout — must be longer than worst-case processing time (if a message takes 60s to process, set visibility to 90s); (3) DLQ — messages that repeatedly fail must not block the queue; alert on DLQ depth and implement fallback logic. At Amazon, SQS + competing consumers is the default pattern for any work that can be async — it's the decoupling primitive that makes independent service scaling possible."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Outbox Pattern](28-outbox-pattern.md) | Outbox reliably enqueues messages that Competing Consumers process |
| [Saga](26-saga.md) | When multiple queue-based steps must form a transaction, Saga coordinates the Competing Consumers |
| [Circuit Breaker](29-circuit-breaker.md) | Guard consumer's downstream calls (email sending) with a Circuit Breaker to prevent cascading into the SMTP provider |
| [Bulkhead](33-bulkhead.md) | Each consumer type (email, SMS, push) should have its own queue and consumer pool — a form of bulkhead isolation |
