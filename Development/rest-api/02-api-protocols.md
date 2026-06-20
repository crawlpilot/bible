# API Protocols: REST vs gRPC vs GraphQL vs WebSocket

## Context

No single protocol dominates FAANG architectures. Each solves a different problem. Principal engineers choose deliberately based on constraints — client type, latency budget, payload characteristics, team ownership, and operational tooling — not habit or ecosystem familiarity.

---

## Protocol Comparison at a Glance

| Dimension | REST (HTTP/1.1–2) | gRPC (HTTP/2) | GraphQL (HTTP) | WebSocket |
|---|---|---|---|---|
| **Transport** | HTTP/1.1, HTTP/2 | HTTP/2 (required) | HTTP/1.1, HTTP/2 | TCP (ws://) |
| **Payload format** | JSON (default), XML | Protobuf (binary) | JSON | JSON, binary |
| **Schema / contract** | OpenAPI (opt-in) | .proto (mandatory) | Schema (mandatory) | None (informal) |
| **Streaming** | HTTP/2 server push; SSE | Bidirectional streaming | Subscriptions | Full duplex |
| **Latency** | Moderate | Low (binary, HTTP/2 mux) | Moderate | Very low |
| **Payload size** | Larger (JSON verbosity) | 3–10x smaller (Protobuf) | Controllable (field selection) | Depends on format |
| **Browser support** | Native | Limited (grpc-web proxy) | Native | Native |
| **Tooling** | Excellent (Postman, curl, proxies) | Good (grpcurl, grpcui) | Good (GraphiQL, Apollo Studio) | Basic |
| **Error model** | HTTP status codes | gRPC status codes | HTTP 200 + errors in body | Application-level |
| **Caching** | HTTP-native (CDN, ETags) | Difficult (HTTP/2 stream) | Complex (client-side only) | Not applicable |
| **Code generation** | Optional (OpenAPI → SDK) | Mandatory (.proto → stubs) | Optional (Apollo codegen) | None |
| **Backwards compat** | URL versioning / additive fields | Proto field numbers (safe evolution) | @deprecated directive | Application contract |

---

## REST

### When REST is the Right Choice

- Public API consumed by browsers, mobile apps, or third parties
- Team doesn't control clients — broad HTTP ecosystem compatibility matters
- Cache-ability is critical (CDN, ETags, Conditional GET)
- Human readability matters (debugging, third-party integrations)
- Simple CRUD operations dominate the access pattern

### REST at FAANG Scale

**Twitter**: public REST API v2 — JSON, OAuth 2.0, cursor pagination, rate limit headers. Internal services migrated to Thrift/gRPC but the public surface stayed REST.

**Stripe**: REST with date-based header versioning. Every field is a contract maintained across years. Idempotency keys as a first-class API primitive.

**AWS SDK pattern**: REST endpoints with SigV4 signing. URL versioning for major changes (rarely). Highly additive — new fields appear but old fields are never removed.

### REST Weaknesses

- Chattiness: multiple round-trips for related resources (N+1 problem)
- Over-fetching: fixed response shapes return more data than clients need
- Under-fetching: clients need to call multiple endpoints to assemble a view
- No streaming primitives in HTTP/1.1 (workarounds: SSE, long polling)
- Schema validation only with tooling (OpenAPI); not enforced by protocol

---

## gRPC

### When gRPC is the Right Choice

- Internal service-to-service calls where you control both ends
- High-throughput, low-latency paths where JSON overhead matters
- Streaming use cases: real-time data feeds, file transfer, bidirectional chat
- Polyglot environments — Protobuf generates typed clients in 10+ languages
- Strong contract enforcement at build time (proto schema changes fail builds)

### gRPC Performance Characteristics

```
Benchmark: 1000 RPS, simple request/response

Protocol          Payload size    p50 latency    p99 latency    CPU (server)
──────────────────────────────────────────────────────────────────────────────
REST (JSON)       ~400 bytes      8 ms           22 ms          100% (baseline)
gRPC (Protobuf)   ~50 bytes       2 ms           8 ms           35%
```

HTTP/2 multiplexing eliminates head-of-line blocking on a single connection. Protobuf binary encoding is faster to serialize/deserialize than JSON.

### gRPC Service Definition

```protobuf
syntax = "proto3";

package orders.v1;

service OrderService {
    // Unary RPC
    rpc GetOrder (GetOrderRequest) returns (Order);
    
    // Server streaming (real-time updates)
    rpc StreamOrderUpdates (OrderId) returns (stream OrderUpdate);
    
    // Client streaming (bulk upload)
    rpc BatchCreateOrders (stream CreateOrderRequest) returns (BatchResult);
    
    // Bidirectional streaming
    rpc SyncInventory (stream InventoryUpdate) returns (stream InventorySyncResult);
}

message Order {
    string id = 1;
    string customer_id = 2;
    OrderStatus status = 3;
    repeated OrderLine lines = 4;
    google.protobuf.Timestamp created_at = 5;
}

enum OrderStatus {
    ORDER_STATUS_UNSPECIFIED = 0;
    ORDER_STATUS_SUBMITTED = 1;
    ORDER_STATUS_CONFIRMED = 2;
    ORDER_STATUS_SHIPPED = 3;
}
```

**Field number evolution**: add new fields with new numbers; never reuse field numbers from deleted fields. Old clients ignore unknown fields. New clients handle missing fields as zero-values. This is why Proto is safe to evolve without versioning.

### gRPC at FAANG Scale

**Google**: all internal services use gRPC (the "G" stands for Google — it originated there). External APIs proxy through Endpoints or API Gateway to REST/JSON.

**Netflix**: migrated from REST to gRPC for most service-to-service calls. Measured 65% reduction in inter-service bandwidth at their scale.

**Uber**: uses gRPC with TChannel for critical paths. Protobuf schema registry enforces contract compatibility before deployment.

### gRPC Weaknesses

- No native browser support: requires grpc-web + Envoy proxy
- Binary format: harder to debug without tooling (grpcurl, grpcui)
- Load balancing: requires L7 gRPC-aware LB (Envoy, Nginx) — L4 LBs cause connection imbalance
- Streaming at scale requires careful flow control
- Not CDN-cacheable

---

## GraphQL

### When GraphQL is the Right Choice

- Frontend teams want to own their data fetching without waiting for backend API changes
- Multiple clients (web, mobile, TV) need different shapes of the same data
- Resource relationships are complex and result in N+1 REST calls
- API aggregation layer (BFF pattern) over multiple downstream services

### GraphQL Core Concepts

```graphql
# Schema definition (server-side contract)
type Order {
    id: ID!
    status: OrderStatus!
    customer: Customer!          # resolved by CustomerResolver
    lines: [OrderLine!]!         # resolved by OrderLineResolver
    total: Money!
    createdAt: DateTime!
}

# Query — client specifies exactly what fields it needs
query GetOrderWithCustomer($orderId: ID!) {
    order(id: $orderId) {
        id
        status
        customer {
            id
            name
            email              # only name and email — not address, preferences, etc.
        }
        lines {
            productId
            quantity
        }
    }
}

# Mutation
mutation SubmitOrder($orderId: ID!) {
    submitOrder(id: $orderId) {
        id
        status
    }
}

# Subscription (real-time)
subscription OnOrderStatusChange($orderId: ID!) {
    orderStatusChanged(id: $orderId) {
        id
        status
        updatedAt
    }
}
```

### The N+1 Problem and DataLoader

```
Naive resolver:
  query { orders { customer { name } } }
  → 1 query for orders (returns 20)
  → 20 queries for each customer (N+1)
  Total: 21 database queries

With DataLoader (batching):
  → 1 query for orders (returns 20)
  → 1 batch query for all 20 customers (WHERE id IN (...))
  Total: 2 database queries
```

DataLoader is mandatory for production GraphQL. Without it, a single query can trigger hundreds of database round-trips.

### GraphQL at FAANG Scale

**Meta (Facebook)**: GraphQL was invented at Facebook in 2012. The original use case was the News Feed — different clients needed radically different views of the same data. The Graph API for Facebook Platform is GraphQL.

**GitHub**: migrated from REST API v3 to GraphQL API v4. Clients can fetch a PR with its comments, reviews, and file changes in one query — instead of 5+ REST calls.

**Shopify**: Storefront API is GraphQL. The admin API has both REST and GraphQL, with GraphQL being the recommended path for new integrations.

### GraphQL Weaknesses

- **Caching**: HTTP GET caching doesn't apply to POST queries. Requires client-side cache (Apollo Client, Relay) or persisted queries with GET.
- **Rate limiting complexity**: per-field depth/complexity scoring needed, not simple request counting
- **Overly flexible queries**: a poorly shaped query from a client can be expensive to resolve — query complexity limits required
- **Error handling**: always returns HTTP 200; errors appear in the `errors` array — breaks standard observability tooling
- **N+1 without DataLoader**: trivially easy to write resolvers that hammer the database

---

## WebSocket

### When WebSocket is the Right Choice

- True bidirectional real-time communication (chat, collaborative editing, live auctions)
- Low-latency game state synchronization
- Server-push without client polling overhead (stock tickers, live sports scores)
- Streaming large amounts of data where HTTP request-response overhead is prohibitive

### WebSocket vs SSE (Server-Sent Events)

| | WebSocket | SSE |
|---|---|---|
| **Direction** | Bidirectional | Server → Client only |
| **Protocol** | WebSocket (TCP upgrade) | HTTP/1.1 or HTTP/2 |
| **Reconnect** | Manual | Automatic (browser native) |
| **Firewalls/proxies** | Issues with some proxies | HTTP (generally fine) |
| **Multiplexing** | Per-connection | HTTP/2 multiplexing |
| **Use when** | Client also sends real-time data | Server-only push events |

**Recommendation**: prefer SSE for server-push only (live feeds, notifications). Use WebSocket only when the client must also stream data to the server.

### At Scale: Connection Management

At 1M concurrent WebSocket connections:
- Each connection holds state on the server (user context, subscriptions)
- Horizontal scaling requires pub/sub backend (Redis, Kafka) to fan-out messages across nodes
- Session affinity (sticky sessions) or stateless connection brokers (Ably, Pusher, AWS API Gateway WebSockets)

---

## Choosing the Right Protocol: Decision Flowchart

```
Is the client a browser or third-party with no protocol control?
  → YES → REST (with JSON)
  → NO ↓

Is the use case real-time bidirectional or streaming?
  → YES → gRPC (streaming RPC) or WebSocket (if browser client needed)
  → NO ↓

Is the consumer a frontend team that needs flexible data fetching?
  → YES → GraphQL (with DataLoader + complexity limits)
  → NO ↓

Is the use case internal service-to-service at high throughput?
  → YES → gRPC
  → NO → REST (simpler, better tooling, good enough)
```

---

## API Gateway Pattern

The API gateway is the single entry point for all external clients. It sits in front of your internal services (which may use gRPC internally) and exposes REST or GraphQL externally.

```
┌─────────┐         ┌──────────────────────────────┐
│ Browser │──REST──▶│         API Gateway           │
│ Mobile  │──REST──▶│  - Auth (JWT validation)      │──gRPC──▶ Order Service
│ Partner │──REST──▶│  - Rate limiting               │──gRPC──▶ Inventory Service
└─────────┘         │  - Request routing             │──gRPC──▶ Payment Service
                    │  - Response translation        │──REST──▶ Legacy Service
                    │  - Observability               │
                    └──────────────────────────────┘
```

**Gateway responsibilities** (what belongs here vs. in services):
- Auth token validation — yes; auth token issuance — no (auth service)
- Rate limiting — yes, at the aggregate and per-client level
- Request routing — yes; business logic — never
- Protocol translation (REST → gRPC) — yes, with caution (adds latency, complexity)
- SSL termination — yes
- Request/response logging and tracing — yes

**What NOT to put in the gateway**: business logic, data aggregation, fan-out. These belong in a BFF layer.

### BFF (Backend for Frontend)

```
                    ┌─────────────────────┐
Mobile App ─REST──▶ │   Mobile BFF        │──gRPC──▶ Services
                    │ (lean, optimized     │
                    │  for mobile payload) │
                    └─────────────────────┘

                    ┌─────────────────────┐
Web App ──GraphQL──▶│   Web BFF           │──gRPC──▶ Services
                    │ (flexible queries,   │
                    │  DataLoader, caching)│
                    └─────────────────────┘
```

Each client type owns a BFF that aggregates, transforms, and optimises responses for that specific consumer. Eliminates the "one-size-fits-all" API problem at scale.

---

## Trade-off Summary

| Decision | Recommendation | When to Reconsider |
|---|---|---|
| REST vs gRPC for internal | gRPC: typed, performant, streaming | Use REST if teams lack Protobuf familiarity or need browser access without proxy |
| REST vs GraphQL for external | REST: simpler, cacheable, standard tooling | Switch to GraphQL if multiple clients need very different data shapes from the same source |
| URL versioning vs header versioning | URL (`/v1/`): explicit, cached, routeable | Header versioning only if you adopt Stripe-style date versioning with strict additive-only discipline |
| API Gateway vs BFF | API gateway for cross-cutting (auth, rate limit); BFF for aggregation | Skip BFF if only one client type; it's unnecessary complexity for uniform clients |
| WebSocket vs SSE | SSE unless client must stream data to server | Use WebSocket for collaborative editing, gaming, or bidirectional real-time |

---

## FAANG Interview Callouts

**"How does Meta/Facebook serve different clients (web, iOS, Android) from the same backend?"**
GraphQL BFF per client. Each client sends a query specifying exactly the fields it needs. The GraphQL layer aggregates from multiple microservices. DataLoader batches database calls. Apollo Federation (or Meta's equivalent) distributes schema ownership across teams while presenting a unified graph to clients.

**"Why did Netflix migrate internal APIs to gRPC?"**
At Netflix's scale, JSON parsing CPU overhead across billions of internal calls is non-trivial. gRPC with Protobuf reduced inter-service bandwidth 65% and CPU by ~40% on high-frequency paths. HTTP/2 multiplexing eliminated the connection-per-request overhead. Typed proto contracts also caught API mismatches at compile time instead of runtime.

**"How would you design an API for a real-time collaborative document editor (like Google Docs)?"**
Three-layer approach: (1) REST API for document CRUD, user management, sharing — stateless, cacheable; (2) WebSocket connection per editing session for operational transforms (OT) or CRDT deltas — low latency, bidirectional; (3) SSE or WebSocket for presence indicators (who else is in the document, cursor positions). The WebSocket server is stateful per session; horizontal scaling via Redis pub/sub to fan out changes to all co-editors on different server nodes.
