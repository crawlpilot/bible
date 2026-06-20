# gRPC — Deep Dive

## What Is gRPC

gRPC is Google's open-source RPC framework. It uses HTTP/2 as transport and Protocol Buffers (Protobuf) as the interface definition language and wire format. All internal Google services run on gRPC. It was open-sourced in 2015.

---

## Architecture

```
┌──────────────┐     .proto schema     ┌──────────────┐
│   Client     │◀─── shared contract ──▶│   Server     │
│              │                        │              │
│  Generated   │────── HTTP/2 ─────────▶│  Generated   │
│  Stub (sync/ │◀─── Protobuf frames ───│  Skeleton    │
│  async)      │                        │              │
└──────────────┘                        └──────────────┘

HTTP/2 features used:
  - Multiplexing: multiple streams on one TCP connection
  - Header compression (HPACK): repeated headers not re-sent
  - Binary framing: lower overhead than HTTP/1.1 text
  - Server push: (not commonly used by gRPC)
```

---

## Protocol Buffers (Protobuf)

### Schema Definition

```protobuf
syntax = "proto3";

package orders.v1;

option java_package = "com.example.orders.v1";
option java_outer_classname = "OrderProto";

import "google/protobuf/timestamp.proto";

// Field numbers (not names) identify fields on the wire
// NEVER reuse a field number after deletion — use reserved
message Order {
    string id = 1;
    string customer_id = 2;
    OrderStatus status = 3;
    repeated OrderLine lines = 4;
    Money total = 5;
    google.protobuf.Timestamp created_at = 6;
    google.protobuf.Timestamp updated_at = 7;

    // Deleted field — reserved to prevent accidental reuse
    reserved 8;
    reserved "legacy_reference";
}

message OrderLine {
    string product_id = 1;
    int32 quantity = 2;
    Money unit_price = 3;
}

message Money {
    string amount = 1;        // string to avoid floating-point issues
    string currency_code = 2; // ISO 4217
}

enum OrderStatus {
    ORDER_STATUS_UNSPECIFIED = 0;   // proto3: zero-value must be defined
    ORDER_STATUS_SUBMITTED = 1;
    ORDER_STATUS_CONFIRMED = 2;
    ORDER_STATUS_SHIPPED = 3;
    ORDER_STATUS_DELIVERED = 4;
    ORDER_STATUS_CANCELLED = 5;
}
```

### Safe Schema Evolution Rules

```
SAFE (backwards compatible):
  ✓ Add new optional fields with new field numbers
  ✓ Add new enum values
  ✓ Rename a field (field number stays; old clients ignore name changes)
  ✓ Add new RPC methods to a service

UNSAFE (breaking change):
  ✗ Change a field's type
  ✗ Reuse a deleted field number
  ✗ Rename a package/message (breaks generated code)
  ✗ Remove a required field (proto2 only; proto3 has no required)
  ✗ Change field from singular to repeated (or vice versa) — data loss

Rule: treat field numbers like database column IDs. They are permanent.
```

---

## Service Definition — All Four RPC Types

```protobuf
service OrderService {

    // 1. Unary RPC — one request, one response (most common)
    rpc GetOrder (GetOrderRequest) returns (Order);
    rpc CreateOrder (CreateOrderRequest) returns (Order);
    rpc UpdateOrderStatus (UpdateOrderStatusRequest) returns (Order);

    // 2. Server streaming — one request, stream of responses
    //    Use: real-time order status updates, large data download
    rpc StreamOrderUpdates (OrderId) returns (stream OrderStatusEvent);
    rpc ExportOrders (ExportOrdersRequest) returns (stream Order);

    // 3. Client streaming — stream of requests, one response
    //    Use: bulk upload, telemetry ingestion, file upload
    rpc BatchCreateOrders (stream CreateOrderRequest) returns (BatchCreateResult);
    rpc UploadInventory (stream InventoryRecord) returns (UploadResult);

    // 4. Bidirectional streaming — stream both ways, independently
    //    Use: real-time collaborative features, game state sync, live chat
    rpc SyncInventory (stream InventoryUpdate) returns (stream InventorySyncAck);
}
```

### Unary RPC Flow

```
Client                          Server
  │─── HEADERS (method, auth) ──▶│
  │─── DATA (Protobuf request) ──▶│
  │                               │ (process)
  │◀── HEADERS (status 200) ─────│
  │◀── DATA (Protobuf response) ──│
  │◀── HEADERS (grpc-status 0) ──│ (trailer — marks end)
```

### Server Streaming Flow

```
Client                          Server
  │─── HEADERS ─────────────────▶│
  │─── DATA (request) ──────────▶│
  │◀── HEADERS ──────────────────│
  │◀── DATA (response 1) ────────│
  │◀── DATA (response 2) ────────│
  │       ...N messages           │
  │◀── DATA (response N) ────────│
  │◀── HEADERS (grpc-status 0) ──│
```

---

## gRPC Status Codes

```
Code            Integer  Meaning
─────────────────────────────────────────────────────────────
OK              0        Success
CANCELLED       1        Client cancelled the request
UNKNOWN         2        Unknown error (unmapped server exception)
INVALID_ARGUMENT 3       Client sent invalid input (≈ HTTP 400)
DEADLINE_EXCEEDED 4      Deadline passed before operation completed
NOT_FOUND       5        Resource not found (≈ HTTP 404)
ALREADY_EXISTS  6        Resource already exists (≈ HTTP 409)
PERMISSION_DENIED 7      Caller lacks permission (≈ HTTP 403)
RESOURCE_EXHAUSTED 8     Rate limited or quota exceeded (≈ HTTP 429)
FAILED_PRECONDITION 9    Wrong state for operation (≈ HTTP 409)
ABORTED         10       Concurrency conflict — retry at higher level
OUT_OF_RANGE    11       Value outside valid range
UNIMPLEMENTED   12       Method not implemented (≈ HTTP 501)
INTERNAL        13       Internal server error (≈ HTTP 500)
UNAVAILABLE     14       Service unavailable — retry (≈ HTTP 503)
DATA_LOSS       15       Unrecoverable data loss
UNAUTHENTICATED 16       No valid credentials (≈ HTTP 401)
```

**Retry safe**: UNAVAILABLE and RESOURCE_EXHAUSTED are safe to retry.
**Do not retry**: INVALID_ARGUMENT, NOT_FOUND, PERMISSION_DENIED, UNAUTHENTICATED.

---

## Deadlines and Cancellation

```java
// Always set a deadline — gRPC does NOT have a default timeout
OrderServiceGrpc.OrderServiceBlockingStub stub = OrderServiceGrpc
    .newBlockingStub(channel)
    .withDeadlineAfter(500, TimeUnit.MILLISECONDS);  // 500ms deadline

try {
    Order order = stub.getOrder(GetOrderRequest.newBuilder()
        .setOrderId("ord_abc123")
        .build());
} catch (StatusRuntimeException e) {
    if (e.getStatus().getCode() == Status.Code.DEADLINE_EXCEEDED) {
        // Deadline passed — do NOT retry blindly (operation may have succeeded server-side)
    }
}
```

**Deadline propagation**: when Service A calls Service B with a 500ms deadline, and B calls C, B should propagate the *remaining* deadline to C — not start a fresh deadline. Otherwise B might complete within 500ms but C runs past the client's original deadline.

```java
// Propagate context (includes deadline) downstream automatically
Context.current().run(() -> {
    serviceC.doWork(request);
});
```

---

## Interceptors (Middleware)

```java
// Server-side interceptor — applies to all RPCs
public class AuthInterceptor implements ServerInterceptor {

    @Override
    public <Req, Resp> ServerCall.Listener<Req> interceptCall(
            ServerCall<Req, Resp> call,
            Metadata headers,
            ServerCallHandler<Req, Resp> next) {

        String token = headers.get(AUTHORIZATION_KEY);
        if (!isValid(token)) {
            call.close(Status.UNAUTHENTICATED.withDescription("Invalid token"), headers);
            return new ServerCall.Listener<>() {};
        }
        return next.startCall(call, headers);
    }
}

// Client-side interceptor — adds auth header to every outbound call
public class AuthClientInterceptor implements ClientInterceptor {

    @Override
    public <Req, Resp> ClientCall<Req, Resp> interceptCall(
            MethodDescriptor<Req, Resp> method,
            CallOptions callOptions,
            Channel next) {

        return new ForwardingClientCall.SimpleForwardingClientCall<>(next.newCall(method, callOptions)) {
            @Override
            public void start(Listener<Resp> responseListener, Metadata headers) {
                headers.put(AUTHORIZATION_KEY, "Bearer " + getToken());
                super.start(responseListener, headers);
            }
        };
    }
}
```

Common interceptors: auth, logging, tracing (OpenTelemetry), retry, deadline propagation, metrics.

---

## Load Balancing

gRPC's use of HTTP/2 long-lived connections breaks standard L4 load balancing.

```
Problem: L4 LB (AWS NLB, HAProxy TCP mode) distributes connections, not requests.
If 10 clients connect to 3 servers, distribution might be 8/1/1 — not balanced.
gRPC clients hold one long-lived connection → all requests from that client hit one server.

Solution options:

1. Client-side load balancing (gRPC native)
   - Client resolves service → list of server IPs (via DNS or service registry)
   - Client picks a server per RPC using a policy (round-robin, least-loaded)
   - Pros: zero LB latency; no single point of failure
   - Cons: client complexity; requires service discovery integration

2. Proxy-based L7 load balancing (Envoy / Linkerd)
   - Proxy understands HTTP/2 framing → balances at the RPC level
   - Service mesh (Istio + Envoy) is the standard FAANG approach
   - Pros: transparent to application code
   - Cons: adds ~1ms proxy hop latency

3. gRPC-LB protocol
   - Lookaside load balancer: client asks an LB service which backend to use
   - Used internally at Google
```

---

## gRPC vs REST Performance

```
Benchmark environment: AWS c5.xlarge, 1000 RPS sustained

Metric                  REST/JSON       gRPC/Protobuf   Delta
─────────────────────────────────────────────────────────────────
Payload (Order object)  ~480 bytes      ~58 bytes       8x smaller
Serialization time      ~12 µs          ~2 µs           6x faster
p50 latency             6 ms            1.8 ms          3.3x lower
p99 latency             22 ms           7 ms            3x lower
Server CPU (1000 RPS)   100% (baseline) 32%             68% reduction
Throughput (same CPU)   1000 RPS        ~3100 RPS       3x more
```

Numbers vary with payload size and hardware. The gap narrows for large payloads where network dominates.

---

## grpc-gateway: Serve Both REST and gRPC

```protobuf
import "google/api/annotations.proto";

service OrderService {
    rpc GetOrder (GetOrderRequest) returns (Order) {
        option (google.api.http) = {
            get: "/v1/orders/{order_id}"
        };
    }

    rpc CreateOrder (CreateOrderRequest) returns (Order) {
        option (google.api.http) = {
            post: "/v1/orders"
            body: "*"
        };
    }
}
```

grpc-gateway generates a reverse proxy that translates HTTP/JSON ↔ gRPC/Protobuf. One implementation, two protocols. Used at Lyft, Docker, and many others.

---

## Production Patterns

### Health Checking

```protobuf
// Standard gRPC health protocol
import "grpc/health/v1/health.proto";
// Service: grpc.health.v1.Health
// RPC: Check(HealthCheckRequest) returns (HealthCheckResponse)
// RPC: Watch(HealthCheckRequest) returns (stream HealthCheckResponse)
```

```bash
# Check health via grpc_health_probe
grpc_health_probe -addr=:50051

# Or via grpcurl
grpcurl -plaintext localhost:50051 grpc.health.v1.Health/Check
```

### Reflection (for debugging)

```java
// Enable server reflection — allows grpcurl and grpcui to discover services
ServerBuilder.forPort(50051)
    .addService(new OrderServiceImpl())
    .addService(ProtoReflectionService.newInstance())
    .build();
```

```bash
# List services (requires reflection enabled)
grpcurl -plaintext localhost:50051 list

# Describe a method
grpcurl -plaintext localhost:50051 describe orders.v1.OrderService.GetOrder

# Call a method
grpcurl -plaintext -d '{"order_id": "ord_abc123"}' \
  localhost:50051 orders.v1.OrderService/GetOrder
```

---

## FAANG Usage

| Company | How They Use gRPC |
|---|---|
| **Google** | All internal microservices. External APIs exposed as REST via gRPC-gateway |
| **Netflix** | gRPC for high-frequency internal paths; measured 65% bandwidth reduction |
| **Uber** | gRPC + Thrift hybrid; migrated critical dispatch paths to gRPC |
| **Lyft** | gRPC for all internal services; open-sourced Envoy partly to solve gRPC LB |
| **Stripe** | Internal services use gRPC; external-facing API stays REST |
| **Dropbox** | gRPC for internal services; replaced in-house RPC framework |

---

## Trade-offs

| Dimension | gRPC Wins | gRPC Loses |
|---|---|---|
| **Performance** | 3–10x better CPU, bandwidth, latency vs REST/JSON | — |
| **Typing** | Proto schema enforced at compile time | Schema changes need coordination |
| **Streaming** | Native 4 RPC types including bidi streaming | REST can't do this natively |
| **Browser** | — | No native browser support; needs grpc-web + Envoy proxy |
| **Debugging** | grpcurl, grpcui (good once set up) | Binary format: harder than curl + JSON |
| **Ecosystem** | 10+ language support, official Google libs | Smaller ecosystem than REST |
| **Caching** | — | Not HTTP-cache-friendly |
| **Evolution** | Field numbers enable safe evolution | Proto schema registry needed at scale |
| **Load balancing** | Client-side LB or service mesh | L4 LBs don't work; need L7 (Envoy) |

---

## When to Use gRPC

**Use gRPC when:**
- Internal service-to-service at high throughput (>1k RPS or latency-sensitive)
- You need streaming (real-time feeds, bulk transfer, bidirectional)
- Polyglot environment — proto generates typed clients in every language
- You want compile-time contract enforcement between services

**Don't use gRPC when:**
- The consumer is a browser and you can't run a grpc-web proxy
- The API is public and third parties must integrate without your tooling
- Team lacks proto toolchain experience and the performance gain isn't critical
- You need HTTP-native caching (CDN, ETags)
