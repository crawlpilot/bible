# REST API Best Practices — FAANG Production Standards

## Overview
REST APIs are the primary integration surface between services and clients at FAANG scale. A poorly designed API is a permanent liability: once published and consumed, it is expensive to change. A well-designed API accelerates developer productivity, enables independent service evolution, and degrades gracefully under failure conditions. This document covers API design discipline calibrated to principal engineer expectations — not just HTTP semantics but versioning strategy, error design, security, contract testing, and operational concerns.

---

## REST Maturity Model (Richardson)

```
Level 0 — HTTP as transport tunnel (SOAP over HTTP, RPC-style)
Level 1 — Resources (URLs identify things, not verbs)
Level 2 — HTTP verbs + status codes used correctly ← minimum production bar
Level 3 — Hypermedia / HATEOAS (self-describing responses with links)
```

**FAANG standard**: Level 2 as the baseline. HATEOAS (Level 3) is rarely practical at scale — hypermedia adds response size and client complexity without proportional benefit. Design for Level 2 correctness.

---

## Resource Design

### URL Naming Conventions

```
CORRECT                                     WRONG
─────────────────────────────────────────────────────────────────────
GET /orders                                 GET /getOrders
GET /orders/{id}                            GET /order/{id}
GET /customers/{id}/orders                  GET /getOrdersByCustomer?customerId=x
POST /orders                                POST /createOrder
PUT /orders/{id}                            PUT /updateOrder/{id}
PATCH /orders/{id}                          POST /orders/{id}/update
DELETE /orders/{id}                         POST /orders/{id}/delete
POST /orders/{id}/submit                    POST /submitOrder
GET /orders?status=SUBMITTED&page=0&size=20 GET /orders/submitted
```

**Rules**:
- Nouns, not verbs (verbs belong in HTTP methods, not URLs)
- Plural collection names: `/orders`, not `/order`
- Kebab-case for multi-word resources: `/order-lines`, not `/orderLines`
- Hierarchy for ownership: `/customers/{id}/addresses` (addresses owned by customer)
- Actions that aren't CRUD: use sub-resource verbs: `POST /orders/{id}/submit`, `POST /orders/{id}/cancel`

---

### HTTP Method Semantics

| Method | Semantics | Idempotent | Safe (no side effects) | Request body | Response body |
|---|---|---|---|---|---|
| GET | Retrieve resource | Yes | Yes | No | Yes |
| POST | Create resource or trigger action | No | No | Yes | Yes (created resource) |
| PUT | Replace entire resource | Yes | No | Yes | Yes |
| PATCH | Partial update | No (ideally yes) | No | Yes | Yes |
| DELETE | Remove resource | Yes | No | No | Optional |
| HEAD | GET metadata only | Yes | Yes | No | No (headers only) |

**Idempotency matters for distributed systems**: PUT and DELETE should be safe to retry. POST is not idempotent — use idempotency keys for safe retry semantics.

---

## HTTP Status Code Standards

### The Correct Code for Every Situation

```
2xx Success
  200 OK              — GET, PUT, PATCH successful; body contains result
  201 Created         — POST created a resource; body contains resource; Location header set
  202 Accepted        — Async operation started; body contains reference to track progress
  204 No Content      — DELETE successful; no body; also PATCH with no response body

3xx Redirection
  301 Moved Permanently — resource URL changed permanently; update bookmarks
  304 Not Modified      — conditional GET; client cache is still fresh

4xx Client Errors (the CLIENT did something wrong)
  400 Bad Request       — malformed request, validation failure, missing required field
  401 Unauthorized      — no authentication credentials provided (misleading name: means "unauthenticated")
  403 Forbidden         — authenticated but not authorised to access this resource
  404 Not Found         — resource doesn't exist (be careful: don't use for business failures)
  405 Method Not Allowed — method not supported on this resource
  409 Conflict          — state conflict: order already submitted, duplicate creation
  410 Gone              — resource existed but was deleted (vs 404: definitely gone, not just not found)
  422 Unprocessable Entity — request is syntactically valid but semantically invalid (domain validation)
  429 Too Many Requests — rate limited; include Retry-After header

5xx Server Errors (the SERVER failed)
  500 Internal Server Error — unexpected server failure; don't return in happy paths
  502 Bad Gateway          — upstream dependency returned an error
  503 Service Unavailable  — overloaded, circuit open, maintenance; include Retry-After
  504 Gateway Timeout      — upstream timed out
```

**Common mistakes**:
- Using 200 with error in body (`{ "status": "error" }`) — violates HTTP semantics
- Using 500 for validation errors — that's a 400
- Using 404 for "business entity not found" when the resource URL is valid — contextual; document it

---

## Request and Response Design

### Standard Request Structure

```json
POST /orders
Content-Type: application/json
Authorization: Bearer eyJ...
Idempotency-Key: f7c4a8b2-1e3d-4f6a-9b2c-3d7e8f4a5b6c

{
  "customer_id": "cust_01h8xvr2",
  "lines": [
    {
      "product_id": "prod_abc123",
      "quantity": 2,
      "unit_price": { "amount": "19.99", "currency": "USD" }
    }
  ],
  "payment_method": "pm_stripe_tok_abc"
}
```

### Standard Response Structure

```json
HTTP 201 Created
Content-Type: application/json
Location: /orders/ord_7k2m9x
X-Request-ID: a8b3c4d5-e6f7-8901-b234-c5d6e7f8a9b0

{
  "data": {
    "id": "ord_7k2m9x",
    "status": "SUBMITTED",
    "customer_id": "cust_01h8xvr2",
    "total": { "amount": "39.98", "currency": "USD" },
    "created_at": "2025-01-15T10:30:00Z",
    "lines": [...]
  },
  "meta": {
    "request_id": "a8b3c4d5-e6f7-8901-b234-c5d6e7f8a9b0",
    "api_version": "2024-01"
  }
}
```

### Standard Error Response Structure

```json
HTTP 422 Unprocessable Entity
Content-Type: application/problem+json

{
  "type": "https://api.example.com/errors/validation-failed",
  "title": "Validation Failed",
  "status": 422,
  "detail": "One or more order lines failed validation",
  "instance": "/orders",
  "request_id": "a8b3c4d5-e6f7-8901-b234-c5d6e7f8a9b0",
  "errors": [
    {
      "field": "lines[0].quantity",
      "code": "INVALID_QUANTITY",
      "message": "quantity must be between 1 and 100"
    },
    {
      "field": "lines[0].product_id",
      "code": "PRODUCT_NOT_FOUND",
      "message": "Product prod_abc123 not found in catalogue"
    }
  ]
}
```

**Use RFC 7807 (Problem Details for HTTP APIs)**: `type`, `title`, `status`, `detail`, `instance`. Add `request_id` for traceability, `errors` array for multi-field validation.

---

## Pagination, Filtering, Sorting

### Cursor-Based Pagination (preferred at scale)

```
GET /orders?cursor=eyJpZCI6MTIzNCwiY3JlYXRlZF9hdCI6IjIwMjUtMDEifQ&limit=20

Response:
{
  "data": [...],
  "pagination": {
    "next_cursor": "eyJpZCI6MTI1NCwiY3JlYXRlZF9hdCI6IjIwMjUtMDEifQ",
    "has_more": true,
    "limit": 20
  }
}
```

**Why cursor over offset**: offset pagination degrades at large offsets (DB must scan N rows to skip). Cursor-based is O(1) for any page, handles concurrent inserts correctly, and prevents "phantom rows" (same row appearing on two pages due to inserts).

### Offset Pagination (acceptable for small datasets)

```
GET /orders?page=2&size=20&sort=created_at,desc

Response:
{
  "data": [...],
  "pagination": {
    "page": 2,
    "size": 20,
    "total_elements": 1547,
    "total_pages": 78,
    "has_next": true,
    "has_previous": true
  }
}
```

### Filtering and Sorting

```
GET /orders?status=SUBMITTED,CONFIRMED&customer_id=cust_abc&created_after=2025-01-01T00:00:00Z
GET /orders?sort=created_at,desc&sort=id,asc  (multi-field sort)
```

---

## API Versioning Strategy

### URL-Based Versioning (most common at FAANG)

```
https://api.example.com/v1/orders
https://api.example.com/v2/orders
```

**Pros**: explicit, cacheable, easy to route by API gateway, visible in logs
**Cons**: duplicates URL space; clients must migrate explicitly

### Header-Based Versioning (Stripe approach)

```
GET /orders
Stripe-Version: 2024-01-15
```

**Stripe model**: the API version is a date. Changes are additive for all versions. Breaking changes create a new version. Clients pin to a version; Stripe maintains backwards compatibility across years.

### When to increment the version

**Non-breaking changes (do NOT require version bump)**:
- Adding new optional fields to responses
- Adding new optional request parameters
- Adding new endpoints
- Relaxing validation rules

**Breaking changes (require version bump or migration strategy)**:
- Removing or renaming fields
- Changing field types (string → integer)
- Adding required request parameters
- Changing authentication scheme
- Changing error response structure

**Stripe versioning discipline**: treat API changes with the same seriousness as database schema changes. Every public field is a contract.

---

## Idempotency

### Idempotency Keys for POST Requests

```
POST /payments
Idempotency-Key: f7c4a8b2-1e3d-4f6a-9b2c-3d7e8f4a5b6c
```

Server stores the result of the first request keyed by `Idempotency-Key`. If the same key is received again (e.g., client retried after network timeout), the server returns the original response without executing the operation again.

```
Implementation:
1. Receive request + idempotency key
2. Check idempotency store (Redis / DynamoDB with TTL):
   - If key exists and request is complete: return stored response
   - If key exists and request is in-flight: return 409 Conflict (or wait)
   - If key not present: proceed
3. Execute operation
4. Store result in idempotency store with the key (TTL: 24 hours)
5. Return result
```

**Stripe**: all mutating API calls accept `Idempotency-Key`. Safe retry is a first-class API contract.

---

## API Security Standards

### Authentication and Authorisation

```
Authentication schemes (pick one):
  JWT Bearer tokens     — stateless; validate signature + expiry; no server state
  OAuth 2.0 + OIDC      — delegated auth; Google/GitHub login; standard for B2B
  API Keys              — server-to-server; rotatable; never expose in client-side JS
  mTLS                  — service-to-service; certificate-based; zero trust

Authorisation:
  RBAC (Role-Based):    user role → allowed operations
  ABAC (Attribute):     policy engine evaluates resource + user + environment attributes
  Scopes (OAuth):       fine-grained permission strings: read:orders, write:orders
```

### Security Headers

```
HTTP/1.1 200 OK
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
Content-Security-Policy: default-src 'self'
Cache-Control: no-store          (for sensitive data)
X-Request-ID: abc123             (tracing)
```

### Input Validation

```java
// Validate at the API boundary — never trust client input
public record CreateOrderRequest(
    @NotNull @Size(max = 50) String customerId,
    @NotEmpty @Size(max = 100) List<@Valid OrderLineRequest> lines,
    @NotNull @Valid PaymentMethodRequest paymentMethod
) {}

// Validate early: reject before business logic
@PostMapping("/orders")
public ResponseEntity<OrderResponse> createOrder(
        @Valid @RequestBody CreateOrderRequest request,
        BindingResult bindingResult) {
    if (bindingResult.hasErrors()) {
        throw new ValidationException(bindingResult.getFieldErrors());
    }
    // Proceed with validated input
}
```

---

## Rate Limiting

### Standard Headers

```
HTTP/1.1 200 OK
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 847
X-RateLimit-Reset: 1705320000

HTTP/1.1 429 Too Many Requests
Retry-After: 30
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1705320000
```

### Rate Limit Tiers (Stripe model)

```
API Key tier          Requests/second   Burst
Basic (free)          10                20
Standard (paid)       100               200
Enterprise (custom)   1000+             negotiated
Critical endpoints    separate limits   e.g., /payments: 20 RPS
```

---

## API Contract Testing

### Consumer-Driven Contract Tests (Pact)

```java
// Consumer (Orders service) defines the contract
@Pact(consumer = "orders-service", provider = "inventory-service")
public RequestResponsePact createPact(PactDslWithProvider builder) {
    return builder
        .given("product prod_abc123 is in stock with quantity 10")
        .uponReceiving("a request to reserve 2 units of prod_abc123")
            .path("/inventory/reservations")
            .method("POST")
            .body(new PactDslJsonBody()
                .stringValue("product_id", "prod_abc123")
                .integerType("quantity", 2))
        .willRespondWith()
            .status(201)
            .body(new PactDslJsonBody()
                .stringType("reservation_id")
                .stringValue("status", "RESERVED"))
        .toPact();
}
```

**Why contract tests beat integration tests**: integration tests require both services to be running. Contract tests let each team test independently against recorded expectations. When the contract breaks, the failure is caught before deployment — not in production.

---

## Operational Design

### Health Endpoints

```
GET /health/live   → 200 if process is running; 503 if not (Kubernetes liveness probe)
GET /health/ready  → 200 if ready to serve traffic (DB connected, caches warm); 503 if not
GET /health/status → detailed status (for monitoring dashboards, not Kubernetes probes)
```

```json
GET /health/status
{
  "status": "UP",
  "version": "1.4.2",
  "build": "a8b3c4d5",
  "uptime_seconds": 86400,
  "dependencies": {
    "database": { "status": "UP", "latency_ms": 3 },
    "cache": { "status": "UP", "hit_rate": 0.87 },
    "payment_gateway": { "status": "UP", "latency_ms": 45 }
  }
}
```

### Request Tracing Headers

```
X-Request-ID      — unique request ID; generated by API gateway; propagated through all services
X-Correlation-ID  — business operation ID; spans multiple request/response cycles
X-B3-TraceId      — Zipkin/OpenTelemetry distributed trace ID
```

---

## Trade-offs

| Decision | Option A | Option B | Recommendation |
|---|---|---|---|
| **Versioning** | URL versioning (`/v1/`) | Header versioning | URL versioning: explicit, cacheable, easy to route; header versioning only if Stripe-style date versioning is adopted |
| **Pagination** | Cursor-based | Offset-based | Cursor for > 10k records or high-write tables; offset for small, stable datasets |
| **Async responses** | Synchronous (wait for result) | Async (202 + polling or webhook) | Synchronous up to ~5s; async for longer-running operations |
| **Error format** | RFC 7807 Problem Details | Custom error JSON | RFC 7807: standard, tooling support; custom only if existing convention can't be changed |
| **Response envelope** | Wrap in `{ "data": {} }` | Return resource directly | Envelope: allows adding metadata (`pagination`, `meta`) without breaking clients |

---

## Best Practices Summary

1. **Design for the consumer, not the implementation** — the API is a contract, not an internal function exposure
2. **Use correct HTTP status codes** — not 200 for everything; 4xx for client errors, 5xx for server errors
3. **Never break a published API** — version or deprecate; never silently change semantics
4. **Validate at the boundary** — all input validated before entering the domain; return 400/422 for invalid input
5. **Always include a request ID in responses** — distributed tracing requires it
6. **Idempotency keys for all mutating operations** — clients must be able to retry safely
7. **Rate limit and document the limits** — return 429 with Retry-After; expose limits in headers
8. **Document with OpenAPI** — machine-readable spec enables client generation, contract tests, mock servers
9. **Paginate all collection endpoints** — never return unbounded lists
10. **Deprecate explicitly** — `Deprecation` header + `Sunset` header; email API consumers; maintain for agreed period

---

## FAANG Interview Points

**"How do you handle breaking API changes when a service is consumed by 50 other services?"**: Two approaches. First: additive-only changes — never remove or rename fields; only add new optional fields. Maintain this discipline and the API never breaks. Second: when a breaking change is unavoidable, version the API. Deploy v2 alongside v1; give consumers a documented migration window (typically 6–12 months for internal, longer for external); deprecate v1 with `Deprecation` and `Sunset` headers; alert API consumers in their dashboards. The key operational step: instrument who is calling v1 so you know when migration is complete and v1 can be decommissioned. Never decommission without verifying traffic is zero.

**"What's wrong with using 200 for all responses, with a status field in the body?"**: It breaks HTTP semantics in ways that affect the entire infrastructure. Caches (CDN, API gateway, browser) cache 200 responses — including your "error" 200. Load balancers use 5xx counts for health checks — a 200 error bypass health monitoring. Circuit breakers in client libraries (Resilience4j, Hystrix) trigger on 5xx, not on 200 with an error field. Log aggregators alert on 4xx/5xx patterns — your errors become invisible. Distributed tracing marks spans as success/failure based on status codes. Using 200 for errors is a short-term convenience that creates long-term observability blindness.

**"How would you design a payment API that is safe to retry?"**: Three elements. First: idempotency keys — the client generates a UUID per payment attempt; the server stores the result keyed by that UUID; subsequent calls with the same key return the same result without executing again. Second: state machine on the payment resource — the payment transitions through states (INITIATED → AUTHORISED → CAPTURED → SETTLED); a retry on an already-AUTHORISED payment returns the existing authorisation, not a double charge. Third: exactly-once semantics at the database level — use an upsert with the idempotency key as a unique constraint; concurrent retries cannot both succeed; the database rejects duplicates with a unique violation that the application maps to "return cached result."
