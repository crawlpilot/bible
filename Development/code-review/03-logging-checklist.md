# Logging — Code Review Checklist

> Use this checklist when reviewing any PR that adds or changes log statements. Logging errors are silent in the short term and expensive in the long term: PII in logs, wrong log levels, and missing context only become apparent during an incident or audit.

---

## Quick Checklist

```
Structure
  ☐ All log statements use structured (JSON) logging — no string concatenation
  ☐ Log event names are snake_case descriptive strings ("order.submitted", "payment.failed")
  ☐ Relevant business context is included as key-value fields
  ☐ No duplicate fields — MDC context is not re-stated in log call

Levels
  ☐ ERROR: only for unrecoverable failures that require human investigation
  ☐ WARN: recoverable degraded state (circuit open, retry, fallback active)
  ☐ INFO: meaningful state transitions and business events only — not function entry/exit
  ☐ DEBUG: diagnostic detail — confirm it is disabled in production config
  ☐ No TRACE in production code paths

PII and Security
  ☐ No email addresses, names, addresses, phone numbers in log fields
  ☐ No passwords, tokens, API keys, or secrets
  ☐ No full credit card numbers (last 4 digits and brand are OK)
  ☐ No Social Security Numbers, national ID numbers, or health data
  ☐ No raw IP addresses if operating in GDPR jurisdictions (hash or omit)
  ☐ User identified by internal opaque ID only (user_id, customer_id — not email)

Exceptions
  ☐ ERROR and WARN logs include the exception object (not just getMessage())
  ☐ Exception is the last argument in the log call (framework captures stack trace)
  ☐ Exception message is not concatenated into the log message string

Context
  ☐ request_id / trace_id is present (set by MDC at request entry — not per-log-call)
  ☐ Sufficient context to reproduce the issue without adding another log line
  ☐ order_id, customer_id, etc. are logged at the point of failure

Performance
  ☐ No logging inside tight loops at INFO or above
  ☐ High-frequency endpoints (health checks, metrics scrape) are sampled or at DEBUG
  ☐ Log statement arguments are not evaluated if the level is disabled
  ☐ Async appender is used — log I/O does not block request threads
```

---

## Anti-Patterns with Examples

### 1. String Concatenation Instead of Structured Fields

```java
// [BLOCK] Unstructured — not queryable; slow to parse
log.info("Processing order " + orderId + " for customer " + customerId + " amount " + amount);

// [BLOCK] SLF4J format string (slightly better but still unstructured)
log.info("Processing order {} for customer {} amount {}", orderId, customerId, amount);
// These produce a flat string — you cannot filter by orderId in a log query

// CORRECT: structured key-value fields
log.info("order.processing",
    kv("order_id", orderId),
    kv("customer_id", customerId),
    kv("amount_usd", amount)
);
// Produces: {"message":"order.processing","order_id":"ord_abc","customer_id":"cust_1","amount_usd":39.99}
// Queryable: filter order_id = "ord_abc" — instant result in CloudWatch/Kibana
```

### 2. Wrong Log Level

```java
// [BLOCK] ERROR for expected / handled scenarios
try {
    Order order = orderRepository.findById(orderId)
        .orElseThrow(() -> new OrderNotFoundException(orderId));
} catch (OrderNotFoundException e) {
    log.error("Order not found", kv("order_id", orderId), e);
    // This is expected — callers pass invalid IDs; ERROR triggers an alert
}
// CORRECT: 404 Not Found is WARN or INFO (not an error in the server sense)
log.warn("order.not_found", kv("order_id", orderId));

// [BLOCK] INFO for a recoverable degraded state
try {
    paymentGateway.charge(order);
} catch (PaymentGatewayTimeoutException e) {
    log.info("Payment gateway timed out", kv("order_id", orderId));
    // This should be WARN — the operation was not completed
}

// [BLOCK] WARN for a data corruption / unrecoverable failure
if (orderState.isCorrupted()) {
    log.warn("Order state corrupted", kv("order_id", orderId));
    // Data corruption requires immediate investigation — this must be ERROR
}

// [WARN] INFO for detailed flow that adds noise at production volume
log.info("Entering validateOrder method", kv("order_id", orderId));
log.info("Validated line 1 of 3", kv("order_id", orderId));
log.info("Validated line 2 of 3", kv("order_id", orderId));
// At 10k RPS each of these generates 10k lines/second
// CORRECT: log the outcome ("order.validation.passed"), not each step
```

### 3. PII in Logs

```java
// [BLOCK] Personal data in log fields — GDPR violation
log.info("user.login",
    kv("email", user.getEmail()),          // PII
    kv("full_name", user.getName()),       // PII
    kv("date_of_birth", user.getDob())     // PII / sensitive
);

// CORRECT: log opaque internal IDs only
log.info("user.login",
    kv("user_id", user.getId()),           // internal opaque ID
    kv("auth_method", "password"),
    kv("ip_region", ip.getRegion())        // region, not full IP
);

// [BLOCK] Payment card data
log.info("payment.card",
    kv("card_number", card.getNumber()),   // PAN — never log
    kv("cvv", card.getCvv())              // never log
);
// CORRECT:
log.info("payment.card",
    kv("card_last_four", card.getLastFour()),
    kv("card_brand", card.getBrand()),
    kv("card_expiry_month", card.getExpiryMonth())  // month+year OK; full date OK
);

// [BLOCK] Credentials or tokens
log.debug("API call to Stripe",
    kv("api_key", stripeApiKey),          // secret — NEVER log
    kv("auth_header", request.getHeader("Authorization"))  // bearer token — NEVER log
);
// CORRECT: log that a call was made, not the credentials used
log.debug("stripe.api.call",
    kv("endpoint", "/v1/charges"),
    kv("method", "POST")
);
```

### 4. Exception Handling in Logs

```java
// [BLOCK] Exception message only — stack trace lost, root cause invisible
} catch (Exception e) {
    log.error("Order processing failed: " + e.getMessage());
}

// [BLOCK] Exception message in the structured message field
} catch (Exception e) {
    log.error("order.processing.failed: " + e.getMessage(),
        kv("order_id", orderId));
}

// CORRECT: pass exception as the last argument — framework captures full stack trace
} catch (Exception e) {
    log.error("order.processing.failed",
        kv("order_id", orderId),
        kv("customer_id", customerId),
        e   // ← exception object, not e.getMessage()
    );
}
```

### 5. Missing Context

```java
// [WARN] Log message without enough context to investigate
log.error("Payment failed", e);
// If this fires in production: which order? which customer? which payment provider?
// You need to add more logs or deploy a new version just to investigate

// CORRECT: log all relevant identifiers at the point of failure
log.error("payment.authorisation.failed",
    kv("order_id", orderId),
    kv("customer_id", customerId),
    kv("payment_provider", provider.getName()),
    kv("amount_usd", amount),
    kv("decline_code", result.getDeclineCode()),
    kv("idempotency_key", idempotencyKey),
    e
);
```

### 6. Logging Inside Loops

```java
// [BLOCK] INFO log per item in a collection — volume explosion
for (Order order : orders) {
    // At 10k RPS with 20 items/order: 200k log lines/second
    log.info("Processing order line",
        kv("order_id", order.getId()),
        kv("line_count", order.getLines().size())
    );
    process(order);
}

// CORRECT: log the batch operation result, not each item
log.info("order.batch.processing.started",
    kv("batch_size", orders.size())
);
// process...
log.info("order.batch.processing.completed",
    kv("batch_size", orders.size()),
    kv("success_count", successCount),
    kv("failure_count", failureCount),
    kv("duration_ms", durationMs)
);
```

### 7. Lazy Evaluation Not Used

```java
// [WARN] Expensive computation always runs, even if DEBUG is disabled
log.debug("Order serialized for audit",
    kv("order_json", objectMapper.writeValueAsString(order))  // always serializes
);

// CORRECT: check level first, or use lambda (where supported)
if (log.isDebugEnabled()) {
    log.debug("Order serialized for audit",
        kv("order_json", objectMapper.writeValueAsString(order))
    );
}
// Or with SLF4J fluent API (avoids string formatting if level disabled):
log.atDebug()
    .addKeyValue("order_json", () -> objectMapper.writeValueAsString(order))
    .log("Order serialized for audit");
```

### 8. MDC Not Cleaned Up

```java
// [BLOCK] MDC not cleared in thread pool — values leak to next request
@Override
public void doFilter(ServletRequest request, ...) {
    MDC.put("request_id", UUID.randomUUID().toString());
    MDC.put("user_id", getUserId(request));
    chain.doFilter(request, response);
    // MISSING: MDC.clear() — next request on this thread inherits stale values
}

// CORRECT: always clear MDC in finally
try {
    MDC.put("request_id", UUID.randomUUID().toString());
    chain.doFilter(request, response);
} finally {
    MDC.clear();  // critical for thread pool reuse
}
```

---

## Log Level Decision Guide

```
Is the operation unrecoverable and does it require engineer action?
  → ERROR

Is the operation degraded but handled (fallback active, circuit open, retry scheduled)?
  → WARN

Is this a significant business event or state transition?
  → INFO

Is this detailed diagnostic information for debugging?
  → DEBUG (disabled in production)

Is this method entry/exit or per-iteration loop data?
  → Don't log it, or TRACE (never in production)
```

---

## Reviewer Severity Summary

| Issue | Severity |
|---|---|
| PII or secret in log field | `[BLOCK]` |
| Exception object not passed (only message) | `[BLOCK]` |
| String concatenation in log (unstructured) | `[BLOCK]` |
| MDC not cleared in filter/interceptor | `[BLOCK]` |
| ERROR used for expected/handled failure | `[WARN]` |
| Logging inside a loop at INFO level | `[WARN]` |
| Missing context (order_id, customer_id) at error site | `[WARN]` |
| DEBUG not guarded by level check (expensive arg) | `[WARN]` |
| INFO log without meaningful business context | `[NIT]` |
| Inconsistent log event naming convention | `[NIT]` |
