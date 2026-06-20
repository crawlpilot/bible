# Logging Best Practices — Production-Grade Standards

## Overview
Logging is the most fundamental observability tool — it's what engineers reach for first when something goes wrong. But logging done poorly creates the illusion of observability while providing none: log statements that lack context, noise that drowns signal, PII scattered through log files, and log volumes that exceed storage budgets. This document covers production-grade logging discipline at FAANG scale: structured logging, log levels, correlation, cardinality, security, and the operational systems that consume logs.

---

## The Fundamental Shift: Structured vs Unstructured Logging

### Unstructured (Legacy)

```java
// WRONG: unstructured — machine parsing is expensive; context is lost
log.info("Processing order " + orderId + " for customer " + customerId);
log.error("Order " + orderId + " failed: " + ex.getMessage());
```

This produces:
```
2025-01-15 10:30:00 INFO  Processing order ord_7k2m9 for customer cust_01h8x
2025-01-15 10:30:01 ERROR Order ord_7k2m9 failed: Payment declined
```

You can grep it, but you can't query, aggregate, or alert on it efficiently.

### Structured Logging (JSON)

```java
// CORRECT: structured — queryable fields; machine-parseable
log.info("order.processing",
    kv("order_id", orderId),
    kv("customer_id", customerId),
    kv("total_usd", order.total().amount()),
    kv("line_count", order.lines().size())
);
```

Produces:
```json
{
  "timestamp": "2025-01-15T10:30:00.123Z",
  "level": "INFO",
  "logger": "OrderSubmissionService",
  "message": "order.processing",
  "order_id": "ord_7k2m9",
  "customer_id": "cust_01h8x",
  "total_usd": 39.98,
  "line_count": 2,
  "trace_id": "4bf92f3577b34da6",
  "span_id": "00f067aa0ba902b7",
  "service": "orders-service",
  "env": "production",
  "host": "orders-7d8f9-abc12",
  "version": "1.4.2"
}
```

Now you can query: `total_usd > 1000 AND level=ERROR`, aggregate by `customer_id`, and correlate by `trace_id`.

---

## Log Levels — When to Use Each

| Level | When to use | Production volume |
|---|---|---|
| **ERROR** | Unrecoverable conditions; operation failed; engineer must investigate | Low; every ERROR should be investigated |
| **WARN** | Recoverable degraded state; unexpected but handled; approaching a limit | Low-medium; reviewed daily |
| **INFO** | Significant business events and state transitions; service lifecycle | Medium; the production narrative |
| **DEBUG** | Detailed diagnostic information; useful for development/troubleshooting | OFF in production; enable for targeted debugging |
| **TRACE** | Very fine-grained diagnostic; method entry/exit; loop iterations | Never in production |

### Level Assignment Rules

```java
// ERROR: operation failed; business impact; requires investigation
log.error("Payment authorisation failed", 
    kv("order_id", orderId),
    kv("decline_reason", result.declineReason()),
    kv("payment_provider", "stripe"),
    ex  // always include exception in ERROR logs
);

// WARN: degraded but handled; circuit open; rate limited; fallback active
log.warn("Payment gateway circuit open; using fallback response",
    kv("order_id", orderId),
    kv("circuit_state", "OPEN"),
    kv("fallback", "PENDING_MANUAL_REVIEW")
);

// INFO: significant state transition; business event; lifecycle
log.info("order.submitted",
    kv("order_id", orderId),
    kv("customer_id", customerId),
    kv("total_usd", total),
    kv("duration_ms", Duration.between(start, Instant.now()).toMillis())
);

// DEBUG: detailed flow; only enable for targeted investigation
log.debug("order.line.validation",
    kv("order_id", orderId),
    kv("line_index", i),
    kv("product_id", line.productId()),
    kv("quantity", line.quantity())
);
```

### The Most Common Mistake: Logging Too Much at INFO

Every INFO log line in a 100k RPS service produces 100k log events per second. At typical cloud storage costs that is:
- 100k events × 500 bytes average = 50 MB/s
- 50 MB/s × 86400 seconds = 4.3 TB/day
- At $0.03/GB/month: ~$4,000/month in log storage alone

**Rule**: INFO logs should be meaningful state transitions and business events, not entry/exit of every function.

---

## Standard Log Fields (Every Service)

Define these fields as base context, set once per request, inherited by all log statements:

```java
// MDC (Mapped Diagnostic Context) in Java — set at request entry point
MDC.put("request_id", requestId);         // UUID; unique per HTTP request
MDC.put("trace_id", traceId);             // OpenTelemetry trace ID
MDC.put("span_id", spanId);              // Current span ID
MDC.put("user_id", userId);              // Authenticated user (non-PII; internal ID)
MDC.put("session_id", sessionId);        // Session identifier
MDC.put("service", "orders-service");     // Service name
MDC.put("version", "1.4.2");             // Service version
MDC.put("env", "production");            // Environment

// Clear MDC at request end (critical for thread pool reuse)
try {
    // handle request
} finally {
    MDC.clear();
}
```

### Always-Present Fields (infrastructure-level)

| Field | Type | Description |
|---|---|---|
| `timestamp` | ISO 8601 UTC | Event time to millisecond precision |
| `level` | string | ERROR/WARN/INFO/DEBUG |
| `service` | string | Service name from deployment config |
| `version` | string | Deployed version/commit SHA |
| `env` | string | production/staging/development |
| `host` | string | Hostname or pod name |
| `request_id` | UUID string | Unique per HTTP request |
| `trace_id` | hex string | OpenTelemetry trace ID |
| `span_id` | hex string | Current span ID |

---

## What to Log and When

### Service Lifecycle

```java
@PostConstruct
public void onStartup() {
    log.info("service.startup",
        kv("version", applicationVersion),
        kv("config_source", configSource),
        kv("port", serverPort)
    );
}

@PreDestroy
public void onShutdown() {
    log.info("service.shutdown",
        kv("active_requests", activeRequestCount.get()),
        kv("uptime_seconds", uptimeSeconds())
    );
}
```

### Request Lifecycle

```java
// Log request receipt at INFO (not every field — avoid PII in request body)
log.info("request.received",
    kv("method", request.method()),
    kv("path", request.path()),
    kv("user_id", authenticatedUserId),
    kv("content_length", request.contentLength())
);

// Log request completion at INFO
log.info("request.completed",
    kv("method", request.method()),
    kv("path", request.path()),
    kv("status", response.status()),
    kv("duration_ms", durationMs),
    kv("response_size_bytes", response.contentLength())
);
```

### Business Events (always INFO)

```java
// State transitions are always logged
log.info("order.status_changed",
    kv("order_id", orderId),
    kv("from_status", fromStatus),
    kv("to_status", toStatus),
    kv("triggered_by", triggeredBy)
);

// External dependency calls
log.info("payment.authorisation.attempt",
    kv("order_id", orderId),
    kv("amount_usd", amount),
    kv("provider", "stripe")
);
log.info("payment.authorisation.result",
    kv("order_id", orderId),
    kv("result", result.status()),
    kv("duration_ms", durationMs)
);
```

### Errors (Always with Exception)

```java
// Include exception object — logging frameworks capture stack trace
try {
    processOrder(order);
} catch (InventoryUnavailableException e) {
    // Expected failure: WARN with context
    log.warn("inventory.unavailable",
        kv("order_id", orderId),
        kv("product_id", e.productId()),
        kv("requested", e.requestedQuantity()),
        kv("available", e.availableQuantity()),
        e  // exception included
    );
} catch (UnexpectedException e) {
    // Unexpected failure: ERROR with full context
    log.error("order.processing.failed",
        kv("order_id", orderId),
        kv("customer_id", customerId),
        kv("operation", "submit"),
        e  // exception — stack trace captured
    );
}
```

---

## What NOT to Log

### PII and Sensitive Data — NEVER log these

```java
// WRONG: PII in logs (GDPR/CCPA violation; security risk)
log.info("User {} logged in with password {}", email, password);
log.info("Processing card {}", cardNumber);
log.info("Customer address: {}", customer.address());
log.info("SSN for verification: {}", ssn);

// CORRECT: log IDs, not personal data
log.info("user.login",
    kv("user_id", userId),    // internal ID, not email/name
    kv("auth_method", "password"),
    kv("ip_hash", hashIp(ip)) // hashed if needed; not raw IP in some jurisdictions
);
log.info("payment.card.used",
    kv("card_last_four", card.lastFour()),  // OK: last 4 digits
    kv("card_brand", card.brand()),
    kv("order_id", orderId)
);
```

### Secrets and Credentials — Never in Logs

```java
// Actively prevent secret logging with masking in logging framework config
// logback.xml: define pattern converters that mask known secret patterns

// WRONG:
log.debug("Connecting to DB with URL: {}", dbUrl); // URL may contain password
log.info("Using API key: {}", apiKey);

// CORRECT:
log.info("database.connection",
    kv("host", dbHost),
    kv("port", dbPort),
    kv("database", dbName),
    // No password; no full URL
);
```

### High-Frequency Low-Value Events

```java
// WRONG: log every cache hit/miss at INFO (millions per second)
for (Product product : products) {
    Optional<Price> price = cache.get(product.id());
    log.info("Cache {} for {}", price.isPresent() ? "hit" : "miss", product.id());
    // 10k products × 100 RPS = 1M log lines/second
}

// CORRECT: aggregate; use metrics for rates; log anomalies only
// Track cache hit rate as a metric; log only cache errors or unusual patterns
log.debug("cache.lookup", kv("product_id", product.id()), kv("hit", price.isPresent()));
// DEBUG — not in production
```

---

## Log Configuration (Logback + SLF4J)

### Production Logback Configuration

```xml
<!-- logback.xml -->
<configuration>
    
    <!-- JSON encoder (Logstash) for structured logging -->
    <appender name="JSON_STDOUT" class="ch.qos.logback.core.ConsoleAppender">
        <encoder class="net.logstash.logback.encoder.LogstashEncoder">
            <includeMdcKeyName>request_id</includeMdcKeyName>
            <includeMdcKeyName>trace_id</includeMdcKeyName>
            <includeMdcKeyName>span_id</includeMdcKeyName>
            <includeMdcKeyName>user_id</includeMdcKeyName>
            <includeMdcKeyName>service</includeMdcKeyName>
            <includeMdcKeyName>version</includeMdcKeyName>
            <includeMdcKeyName>env</includeMdcKeyName>
            
            <!-- Never include raw exception message — may contain PII -->
            <throwableConverter class="net.logstash.logback.stacktrace.ShortenedThrowableConverter">
                <maxDepthPerThrowable>20</maxDepthPerThrowable>
                <maxLength>10000</maxLength>
            </throwableConverter>
        </encoder>
    </appender>
    
    <!-- Async appender — don't block request thread on log I/O -->
    <appender name="ASYNC" class="ch.qos.logback.classic.AsyncAppender">
        <queueSize>10000</queueSize>
        <discardingThreshold>0</discardingThreshold>  <!-- Don't discard under load -->
        <appender-ref ref="JSON_STDOUT" />
    </appender>
    
    <!-- Noisy dependencies → WARN only -->
    <logger name="org.springframework" level="WARN"/>
    <logger name="org.hibernate" level="WARN"/>
    <logger name="com.amazonaws" level="WARN"/>
    <logger name="io.netty" level="WARN"/>
    
    <!-- Application code → INFO in production -->
    <logger name="com.example.orders" level="INFO"/>
    
    <root level="WARN">
        <appender-ref ref="ASYNC"/>
    </root>
    
</configuration>
```

---

## Log Aggregation and Querying

### Stack Options

| Stack | Collection | Storage | Query |
|---|---|---|---|
| **ELK** | Filebeat/Fluentd → Logstash | Elasticsearch | Kibana / Lucene query |
| **EFK** | Fluentd → | Elasticsearch | Kibana |
| **AWS** | CloudWatch Logs Agent | CloudWatch | CloudWatch Logs Insights |
| **Datadog** | Datadog Agent | Datadog | Datadog Log Analytics |
| **Grafana Loki** | Promtail | Loki | Grafana LogQL |

### CloudWatch Logs Insights Example Queries

```sql
-- Error rate by service in the last 1 hour
fields @timestamp, level, service, message
| filter level = "ERROR"
| stats count(*) as error_count by service
| sort error_count desc

-- Slow requests (> 500ms) in orders service
fields @timestamp, request_id, path, duration_ms, user_id
| filter service = "orders-service" and duration_ms > 500
| sort duration_ms desc
| limit 50

-- Trace all events for a specific request
fields @timestamp, level, message, order_id, duration_ms
| filter trace_id = "4bf92f3577b34da6a3ce929d0e0e4736"
| sort @timestamp asc
```

---

## Log Retention and Cost Management

| Log tier | Retention | Storage | Access pattern |
|---|---|---|---|
| **Hot** (recent) | 7–14 days | Fast (Elasticsearch, CloudWatch hot) | Active querying during incidents |
| **Warm** (recent-ish) | 30–90 days | Medium (Elasticsearch warm tier, S3 with indexing) | Post-incident investigations |
| **Cold** (archive) | 1–7 years (compliance) | Cold (S3 Glacier, archive storage) | Compliance audits; rare access |

**Cost control rules**:
1. Never route DEBUG to production log aggregation pipeline
2. Sample high-volume INFO logs (e.g., health check endpoints): log 1 in 100
3. Route application logs to hot tier; access logs to warm tier
4. Use log-level routing: ERROR → hot + alert; INFO → hot; DEBUG → dev only

---

## Sampling Strategy

```java
// Sample high-frequency low-importance logs
@Component
public class SampledLogger {
    private final AtomicLong counter = new AtomicLong(0);
    
    public void logSampled(String message, int sampleRate, Object... args) {
        if (counter.incrementAndGet() % sampleRate == 0) {
            log.info(message, args);
        }
    }
}

// Health check requests: log 1 in 100
@GetMapping("/health/live")
public ResponseEntity<Void> liveness() {
    sampledLogger.logSampled("health.liveness.check", 100, kv("status", "UP"));
    return ResponseEntity.ok().build();
}
```

---

## Trade-offs

| Decision | Option A | Option B | Recommendation |
|---|---|---|---|
| **Format** | JSON structured | Plain text | JSON always in production; plain text only for local dev |
| **Log destination** | stdout (container stdout) | File-based | Stdout: twelve-factor app; collected by container runtime; simpler |
| **Async vs sync** | Async appender | Sync appender | Async: don't block request threads; size the queue appropriately |
| **Sampling** | Log everything | Sample by rate | Sample: high-volume health/metric endpoints; never sample ERROR |
| **Aggregation** | Centralised (ELK) | Per-service CloudWatch | Centralised for cross-service correlation; CloudWatch for simplicity on AWS |

---

## Best Practices Summary

1. **Use structured logging (JSON) everywhere** — queryable fields over plain text concatenation
2. **Set log levels correctly** — ERROR for failures; INFO for state transitions; DEBUG off in production
3. **Never log PII or secrets** — IDs, not personal data; configure masking in the logging framework
4. **Include correlation context (MDC)** — request_id, trace_id on every log line via MDC
5. **Always include the exception object in ERROR logs** — not just `ex.getMessage()`; the stack trace is the diagnostic
6. **Use async appenders** — never block request threads on log I/O
7. **Set noise-floor for dependencies** — Spring, Hibernate, AWS SDK should be WARN in production
8. **Sample high-frequency low-value logs** — health checks, cache hits; never sample errors
9. **Define retention tiers** — hot/warm/cold with cost-appropriate storage
10. **Correlate logs, metrics, and traces** — same trace_id and request_id in all three pillars

---

## FAANG Interview Points

**"How do you design a logging strategy that doesn't violate GDPR?"**: Three principles. First: log IDs, not data — log `user_id` (internal opaque ID) not names, emails, or addresses. If a GDPR request comes in, you can look up the ID; the log files themselves don't contain personal data. Second: classify data before logging — anything in the PII category (name, email, phone, address, location, financial data, health data) cannot appear in logs. Build a data classification taxonomy and enforce it in code review. Third: retention policy — even non-PII logs have retention limits under GDPR's storage minimisation principle; define hot/warm/cold tiers with automatic deletion.

**"How do you debug a production incident using logs when the request spans 8 microservices?"**: Distributed tracing is the primary tool — every request generates a trace_id at the API gateway and it propagates via HTTP headers to every downstream service. I pull all log lines for that trace_id from the central log aggregation system — one query, all 8 services, ordered by timestamp. The trace gives me the critical path; if a span shows unexpected latency, I drill into that service's logs for that trace. The reason this works is: every service includes trace_id in every log line (set via MDC at request entry). Without trace_id correlation, you're grepping across 8 separate log streams and manually joining on timestamps and IDs — which doesn't scale.

**"What's your approach to log volume at Google/Meta scale?"**: Four strategies. First: get the level distribution right — 90%+ of log lines should be INFO or higher; DEBUG/TRACE are development tools, not production tools. Second: sample high-volume, low-value events — health check pings and cache hit/miss events at 1:100 or 1:1000 sampling; always 100% for ERROR. Third: tiered retention — route logs to hot/warm/cold storage based on age; very old logs move to S3 Glacier and are almost never queried. Fourth: cardinality-aware logging — avoid logging per-entity-per-request information that creates linear volume growth with user base; aggregate into metrics instead. The goal is that log volume grows sub-linearly with user growth — most growth is captured in metrics and traces, not log lines.
