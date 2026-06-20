# API Protocols — Interview Cheatsheet

> One-page quick reference. Review this the night before. Each row is an interview answer seed.

---

## Protocol at a Glance

| | REST | gRPC | GraphQL | Thrift | Avro | WebSocket |
|---|---|---|---|---|---|---|
| **Transport** | HTTP/1.1, HTTP/2 | HTTP/2 | HTTP/1.1, HTTP/2 | TCP, HTTP | N/A (serialization only) | TCP |
| **Schema** | OpenAPI (opt-in) | .proto (required) | Schema (required) | .thrift (required) | JSON schema (required) | None |
| **Wire format** | JSON | Protobuf (binary) | JSON | Binary/JSON | Binary | JSON or binary |
| **Browser** | Native | Needs proxy (grpc-web) | Native | Via HTTP | N/A | Native |
| **Streaming** | SSE / HTTP/2 push | 4 RPC types (bidi) | Subscriptions (WS) | No | N/A | Full duplex |
| **Caching** | HTTP-native (CDN) | Hard | Client-side only | No | N/A | No |
| **Code gen** | Optional | Required (.proto → stubs) | Optional | Required | Required | No |
| **Payload size** | Large (JSON) | Small (Protobuf) | Controlled | Small | Smallest | Varies |
| **Error model** | HTTP status codes | gRPC status codes | HTTP 200 + errors[] | Exceptions (IDL) | N/A | App-level |
| **Invented by** | REST (Fielding, 2000) | Google (2015) | Meta (2012, OSS 2015) | Facebook (2007) | Apache (Hadoop) | IETF (2011) |
| **Used at** | Universal | Google, Netflix, Lyft | Meta, GitHub, Shopify | Meta, Uber, Twitter | LinkedIn, Netflix | Slack, Discord |

---

## When to Use — One-Line Rule

| Protocol | Use When |
|---|---|
| **REST** | Public API, browser/mobile clients, third-party integrations, CDN caching needed |
| **gRPC** | Internal service-to-service, high throughput, streaming, polyglot environment |
| **GraphQL** | Multiple clients need different shapes; frontend owns queries; complex relationships |
| **Thrift** | You're in a Meta/Uber/Twitter codebase — don't rewrite unless forced |
| **Avro** | Kafka event schemas — pair with Confluent Schema Registry |
| **WebSocket** | Bidirectional real-time (chat, collaborative editing, gaming) |
| **SSE** | Server-push only (live feeds, notifications) — simpler than WebSocket |
| **MessagePack** | JSON semantics, binary performance — caching, WebSocket payloads |
| **Connect** | Browser + internal service with one codebase, no grpc-web proxy |

---

## REST Cheatsheet

### HTTP Methods

| Method | Idempotent | Safe | Body | Use |
|---|---|---|---|---|
| GET | Yes | Yes | No | Read |
| POST | No | No | Yes | Create / action |
| PUT | Yes | No | Yes | Full replace |
| PATCH | No | No | Yes | Partial update |
| DELETE | Yes | No | No | Delete |
| HEAD | Yes | Yes | No | Metadata only |

### Status Codes

```
200 OK              — GET/PUT/PATCH success
201 Created         — POST created; Location header set
202 Accepted        — Async started
204 No Content      — DELETE success
400 Bad Request     — Malformed / validation error
401 Unauthorized    — Not authenticated
403 Forbidden       — Authenticated but not authorised
404 Not Found       — Resource absent
409 Conflict        — State conflict / duplicate
422 Unprocessable   — Semantically invalid
429 Rate Limited    — Include Retry-After
500 Server Error    — Unexpected failure; alert on this
503 Unavailable     — Circuit open; include Retry-After
```

### URL Patterns

```
GET    /orders              — list
GET    /orders/{id}         — single
POST   /orders              — create
PUT    /orders/{id}         — full replace
PATCH  /orders/{id}         — partial update
DELETE /orders/{id}         — delete
GET    /customers/{id}/orders — nested
POST   /orders/{id}/submit  — action (non-CRUD)
```

### Idempotency Key Pattern

```
POST /payments
Idempotency-Key: <client-uuid>

Server: check store → if exists return cached result
        if not → execute, store result, return
TTL: 24 hours (Stripe: 30 days)
```

### Pagination

```
Cursor (preferred > 10k rows):
  GET /orders?cursor=<token>&limit=20
  Response: { data: [...], pagination: { next_cursor, has_more } }

Offset (small stable datasets):
  GET /orders?page=2&size=20&sort=created_at,desc
  Response: { data: [...], pagination: { page, total_pages, total_elements } }
```

### Rate Limit Headers

```
X-RateLimit-Limit:     1000
X-RateLimit-Remaining: 847
X-RateLimit-Reset:     1705320000   (Unix epoch)
Retry-After:           30           (on 429 only)
```

### Versioning

```
URL:    /v1/orders, /v2/orders  ← FAANG default; explicit, cacheable
Header: Stripe-Version: 2024-01-15  ← date-pinned, clean URLs
```

---

## gRPC Cheatsheet

### 4 RPC Types

```
Unary:              rpc Get(Req) returns (Resp)
Server streaming:   rpc Stream(Req) returns (stream Resp)
Client streaming:   rpc Upload(stream Req) returns (Resp)
Bidirectional:      rpc Sync(stream Req) returns (stream Resp)
```

### Key Status Codes

```
OK (0)              — success
INVALID_ARGUMENT(3) — bad input (don't retry)
NOT_FOUND (5)       — resource absent (don't retry)
ALREADY_EXISTS (6)  — duplicate
PERMISSION_DENIED(7)— not authorised (don't retry)
RESOURCE_EXHAUSTED(8)— rate limited (retry with backoff)
INTERNAL (13)       — server error
UNAVAILABLE (14)    — down (retry safe)
UNAUTHENTICATED(16) — no valid credentials (don't retry)
```

### Proto Evolution Rules

```
SAFE:   add field with new number, add enum value, add RPC method
UNSAFE: change field type, reuse deleted field number, rename package
Rule:   reserve deleted field numbers: reserved 8; reserved "old_name";
```

### Load Balancing

```
L4 (TCP) LB: WRONG — all requests from a client go to same server
L7 (Envoy/Linkerd): CORRECT — balances per RPC, not per connection
Client-side LB: gRPC native; client picks server per call
```

### Always Set Deadlines

```java
stub.withDeadlineAfter(500, TimeUnit.MILLISECONDS).getOrder(req);
// No default timeout — omitting it means infinite wait
```

---

## GraphQL Cheatsheet

### Operations

```
query   — read (can be batched, cached via persisted queries)
mutation — write (returns result + optional errors[])
subscription — real-time push (typically WebSocket)
```

### N+1 → DataLoader

```
Problem: 20 orders → 20 customer queries
Fix: DataLoader.load(customerId) deferred until end of tick
     → 1 batch SELECT * FROM customers WHERE id IN (...)
Rule: create DataLoader per request (never singleton)
```

### Security Checklist

```
☐ Persisted queries (only known query hashes)
☐ Depth limit (max 7 levels)
☐ Complexity scoring (reject > 1000 points)
☐ Rate limit on complexity cost per client
☐ Auth in context — not in resolvers
☐ Never expose internal errors (extensions.code safe; stack trace not)
```

### Error Format

```json
{ "data": { "order": null }, "errors": [{ "message": "...", "extensions": { "code": "NOT_FOUND" } }] }
```
Always HTTP 200. Errors coexist with partial data.

### Federation (scale)

```
Gateway (supergraph) → routes query fragments to subgraphs
Each team owns their subgraph (Orders, Customers, Inventory)
@key(fields: "id") — entity reference for cross-subgraph joins
```

---

## Thrift Cheatsheet

```
IDL:          .thrift file
Transports:   TCP, HTTP, Unix socket (pluggable — unlike gRPC)
Protocols:    Binary, Compact, JSON (pluggable)
Exceptions:   First-class IDL citizen (unlike gRPC status codes)
Evolution:    Field IDs (same semantics as proto field numbers)
Used at:      Meta (fbthrift), Uber (TChannel/Thrift), Twitter (Finagle/Thrift)
Streaming:    None
```

---

## Avro Cheatsheet

```
Schema:        JSON schema (not IDL file)
Schema storage: Confluent Schema Registry (schema_id in Kafka message header)
Evolution:     BACKWARD / FORWARD / FULL / NONE (set FULL in production)
Primary use:   Kafka events — not for synchronous RPC
Safe changes:  add field with default, remove field with default
Unsafe:        add field without default (BACKWARD mode), rename field
Wire format:   [magic byte 0x00 | 4-byte schema_id | avro_bytes]
```

---

## Serialization Format Size (same Order object)

```
JSON          ~480 bytes  (baseline)
Protobuf      ~58 bytes   (8x smaller)
Avro          ~45 bytes   (11x smaller — field names excluded)
Thrift Binary ~62 bytes   (8x smaller)
MessagePack   ~320 bytes  (1.5x smaller — JSON-equivalent schema-free)
XML/SOAP      ~1800 bytes (4x LARGER than JSON)
```

---

## Key Trade-off Comparisons

### REST vs gRPC

| Concern | REST | gRPC |
|---|---|---|
| Public/external | Yes | Only via REST facade |
| Performance | Good | 3–10x better |
| Browser native | Yes | No (grpc-web needed) |
| Streaming | SSE only | Native bidi |
| Caching | CDN-native | Hard |
| Contract enforcement | Optional (OpenAPI) | Mandatory (proto) |

**Choose**: REST for public; gRPC for internal high-throughput.

### gRPC vs Thrift

| Concern | gRPC | Thrift |
|---|---|---|
| Streaming | Yes (4 types) | No |
| Transport | HTTP/2 only | Pluggable (TCP, HTTP) |
| Ecosystem | Large, growing | Smaller, stable |
| Exceptions | Status codes | IDL-defined exceptions |

**Choose**: gRPC for new services; Thrift when inheriting existing codebase.

### GraphQL vs REST

| Concern | GraphQL | REST |
|---|---|---|
| Client flexibility | High (client owns query) | Low (server owns shape) |
| Over-fetching | Eliminated | Common |
| Caching | Hard (no GET caching by default) | HTTP-native |
| Rate limiting | Complexity-based (hard) | Request count (easy) |
| Error model | Always 200; errors in body | HTTP status codes |

**Choose**: GraphQL for multi-client frontends; REST for simple uniform APIs.

---

## FAANG Interview Seeds

**"REST vs gRPC for a new service?"**
> If internal + high throughput → gRPC: typed contracts, 3x CPU efficiency, native streaming. If public or browser client → REST: CDN caching, no proxy needed, universal tooling.

**"How does Meta serve 3 different clients (web/iOS/Android) efficiently?"**
> GraphQL BFF per client. Same schema, different query shapes. DataLoader eliminates N+1. Apollo Federation distributes schema ownership across teams.

**"How do you handle breaking REST API changes with 50 consumers?"**
> Version (/v2/), deploy alongside /v1/, give 6–12mo migration window, instrument v1 traffic by caller, decommission only when traffic → 0. Use `Deprecation` + `Sunset` headers. Never remove v1 while anyone is still calling it.

**"Why Avro over Protobuf for Kafka?"**
> Avro + Schema Registry: consumers fetch the exact schema used to produce each message at runtime — no recompile needed for schema evolution. Kafka ecosystem (Connect, ksqlDB) is first-class Avro. For RPC use Protobuf; for events use Avro.

**"How do you secure a GraphQL API?"**
> 4 layers: persisted queries (reject unknown hashes), depth limit (max 7), complexity scoring (reject > 1000), per-client rate limit on complexity. Plus: auth in context, field-level @auth directives, never expose stack traces.
