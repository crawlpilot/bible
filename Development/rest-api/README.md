# REST & API Design — Master Reference

> Calibrated to principal engineer bar. Every API design decision carries long-term consequences; treat public API fields as database columns — expensive to remove, impossible to take back.

---

## Contents of This Folder

| File | Focus |
|---|---|
| [00-cheatsheet.md](00-cheatsheet.md) | One-page interview cheatsheet — all protocols, key numbers, trade-off seeds |
| [README.md](README.md) | Overview, quick-reference card, interview framing |
| [01-rest-best-practices.md](../best-practices/03-rest-api-best-practices.md) | REST principles, URL design, HTTP semantics, status codes, pagination, versioning, idempotency, security, rate limiting |
| [02-api-protocols.md](02-api-protocols.md) | Protocol comparison overview — REST vs gRPC vs GraphQL vs WebSocket, API Gateway, BFF |
| [03-grpc.md](03-grpc.md) | gRPC deep dive — Protobuf, 4 RPC types, deadlines, interceptors, load balancing, performance |
| [04-graphql.md](04-graphql.md) | GraphQL deep dive — schema, resolvers, N+1/DataLoader, Federation, security, FAANG patterns |
| [05-other-protocols.md](05-other-protocols.md) | Thrift, Avro, MessagePack, Twirp, Connect, SOAP — when each matters |

---

## API Quick-Reference Card

### URL Design Rules

```
Collection:         GET  /orders
Single resource:    GET  /orders/{id}
Nested resource:    GET  /customers/{id}/orders
Create:             POST /orders
Full replace:       PUT  /orders/{id}
Partial update:     PATCH /orders/{id}
Delete:             DELETE /orders/{id}
Action (non-CRUD):  POST /orders/{id}/submit
                    POST /orders/{id}/cancel
```

### HTTP Status Code Cheat Sheet

```
200  OK              — GET/PUT/PATCH succeeded
201  Created         — POST created resource; Location header set
202  Accepted        — async operation started
204  No Content      — DELETE succeeded
400  Bad Request     — malformed request or validation failure
401  Unauthorized    — not authenticated (send credentials)
403  Forbidden       — authenticated but not authorised
404  Not Found       — resource doesn't exist
409  Conflict        — state conflict (duplicate create, wrong state)
422  Unprocessable   — syntactically valid but semantically invalid
429  Rate Limited    — include Retry-After header
500  Server Error    — unexpected failure; alert on this
503  Unavailable     — circuit open / overloaded; include Retry-After
```

### Response Envelope

```json
{
  "data": { ... },
  "pagination": { "next_cursor": "...", "has_more": true },
  "meta": { "request_id": "abc123", "api_version": "2024-01" }
}
```

### Error Response (RFC 7807)

```json
{
  "type": "https://api.example.com/errors/validation-failed",
  "title": "Validation Failed",
  "status": 422,
  "detail": "One or more fields are invalid",
  "instance": "/orders",
  "request_id": "abc123",
  "errors": [
    { "field": "quantity", "code": "INVALID_RANGE", "message": "must be 1–100" }
  ]
}
```

---

## When to Use Which Protocol

| Signal | Use |
|---|---|
| Public API, browser clients, mobile, third-party integrations | REST |
| Internal service-to-service, low latency, streaming RPC | gRPC |
| Frontend with complex data requirements, multiple resource types per screen | GraphQL |
| Real-time push, one-to-many fan-out | WebSocket / SSE |
| Event-driven decoupling between services | Async messaging (Kafka, SQS) |

See [02-api-protocols.md](02-api-protocols.md) for the full comparison.

---

## Versioning Decision

```
URL versioning (/v1/, /v2/):  explicit, cacheable, easy to route — FAANG default
Header versioning:            Stripe-style date versioning (2024-01-15); clean URLs
No versioning:                only if you can guarantee additive-only changes forever
```

**Never break a published API field.** A field in a response is a contract. Removing it is a breaking change regardless of documentation.

---

## Idempotency Pattern

```
Client sends:  POST /payments + Idempotency-Key: <uuid>
Server:        1. Check Redis/DB for key
               2. If exists and complete → return stored response
               3. If exists and in-flight → return 409
               4. If not found → execute, store result with TTL
               5. Return result
```

TTL: 24 hours is standard. Stripe maintains idempotency keys for 30 days.

---

## Rate Limiting Headers

```
X-RateLimit-Limit:     1000     (requests allowed in window)
X-RateLimit-Remaining: 847      (requests left in current window)
X-RateLimit-Reset:     1705320000  (Unix epoch when window resets)
Retry-After:           30       (seconds to wait; only on 429)
```

---

## FAANG Interview Callouts

**"How do you handle an API that 50 internal services consume and you need to make a breaking change?"**
Version the API. Deploy v2 alongside v1. Give a 6–12 month migration window. Use `Deprecation` + `Sunset` response headers on v1. Instrument v1 call volume by caller — you cannot decommission until all callers have migrated and traffic is zero. Build self-service migration tooling to reduce friction.

**"REST vs gRPC — when do you choose which?"**
REST for public-facing APIs: human-readable, browser/mobile-friendly, HTTP tooling ecosystem. gRPC for internal services: strong typing via protobuf, bidirectional streaming, 5–10x better performance on high-volume paths. At Google, all internal services use gRPC; REST is only the external facade. A BFF (Backend for Frontend) layer commonly bridges them.

**"How would you design a payment API safe to retry?"**
Three mechanisms: (1) idempotency keys stored with the result, (2) state machine preventing double execution if already in terminal state, (3) unique constraint on idempotency key at the DB level so concurrent retries cannot both succeed. The database rejects the duplicate with a unique violation; the app catches it and returns the stored result.
