# Other API Protocols — Thrift, Avro, MessagePack, Twirp, Connect, SOAP

## Why These Matter

REST, gRPC, and GraphQL dominate new greenfield work, but legacy FAANG codebases (especially pre-2015) are full of Thrift and custom RPC. Knowing these protocols signals depth. More practically: Thrift is still in active production at Meta, Uber, and Twitter. Avro is standard in Kafka-based event streaming. A principal engineer chooses the right serialization format, not just the right API style.

---

## Apache Thrift

### What It Is

Facebook's original internal RPC framework, open-sourced in 2007. Defines services and data types in a `.thrift` IDL file. Generates client/server code in 20+ languages. Predates gRPC by ~8 years.

Thrift = IDL + serialization format + RPC transport. Unlike gRPC (which locks you to HTTP/2), Thrift is transport-agnostic: you can run it over TCP, HTTP, or even Unix sockets.

### IDL and Code Generation

```thrift
// orders.thrift

namespace java com.example.orders
namespace go orders
namespace py orders

// Exceptions (first-class citizens in Thrift, unlike gRPC)
exception OrderNotFoundException {
    1: required string order_id,
    2: required string message
}

exception ValidationException {
    1: required list<FieldError> errors
}

struct FieldError {
    1: required string field,
    2: required string message
}

enum OrderStatus {
    SUBMITTED = 1,
    CONFIRMED = 2,
    SHIPPED = 3,
    DELIVERED = 4,
    CANCELLED = 5
}

struct Money {
    1: required string amount,
    2: required string currency_code
}

struct OrderLine {
    1: required string product_id,
    2: required i32 quantity,
    3: required Money unit_price
}

struct Order {
    1: required string id,
    2: required string customer_id,
    3: required OrderStatus status,
    4: required list<OrderLine> lines,
    5: required Money total,
    6: required i64 created_at_ms      // epoch millis
}

// Service definition
service OrderService {
    Order getOrder(1: required string order_id)
        throws (1: OrderNotFoundException not_found, 2: ValidationException validation),

    Order createOrder(
        1: required string customer_id,
        2: required list<OrderLine> lines,
        3: required string payment_method_id
    ) throws (1: ValidationException validation),

    // Oneway: fire-and-forget (no response)
    oneway void notifyOrderShipped(1: required string order_id)
}
```

### Thrift Transport and Protocol Stack

```
┌───────────────────────────────────────┐
│             Application               │
├───────────────────────────────────────┤
│   Protocol (serialization format)     │
│     TBinaryProtocol  — compact binary │
│     TCompactProtocol — smaller binary │
│     TJSONProtocol    — human-readable │
├───────────────────────────────────────┤
│   Transport (byte mover)              │
│     TSocket       — raw TCP           │
│     TFramedTransport — message framing│
│     THttpTransport — over HTTP        │
│     TMemoryTransport — in-memory      │
├───────────────────────────────────────┤
│   Server (connection handler)         │
│     TSimpleServer    — single-threaded│
│     TThreadedServer  — thread/conn    │
│     TNonblockingServer — async I/O    │
│     THsHaServer      — half-sync/half-async│
└───────────────────────────────────────┘
```

### Thrift vs gRPC

| Dimension | Thrift | gRPC |
|---|---|---|
| **Transport** | TCP, HTTP, Unix socket (pluggable) | HTTP/2 only |
| **Serialization** | Binary, Compact, JSON (pluggable) | Protobuf only |
| **Streaming** | No native streaming | Bidirectional streaming |
| **Browser support** | Via HTTP transport | Via grpc-web proxy |
| **Exceptions** | First-class IDL citizens | Status codes only |
| **Ecosystem** | Older, smaller; Meta-maintained | Larger, actively growing |
| **Performance** | Comparable to gRPC/Protobuf | Slightly faster on HTTP/2 mux |
| **Schema evolution** | Field IDs (same as proto field numbers) | Field numbers |
| **Adoption** | Meta, Uber, Twitter, Evernote | Google, Netflix, Lyft, Square |

### FAANG Usage

**Meta**: All internal services still on Thrift. fbthrift (Meta's fork) adds features beyond Apache Thrift. Facebook's internal framework is "ServiceRouter over Thrift."

**Uber**: Migrated from Thrift to gRPC for new services after 2019. Legacy services remain on Thrift. Uses TChannel (Uber's custom transport) over Thrift for some paths.

**Twitter**: Internal services on Thrift + Finagle (Scala async RPC framework). Finagle provides service discovery, load balancing, circuit breaking — all over Thrift.

---

## Apache Avro

### What It Is

Avro is a serialization format (not an RPC framework) designed for Hadoop and Kafka. Schema is defined in JSON. Unlike Protobuf/Thrift, Avro requires the schema to be present at both read and write time — the schema is part of the contract, not just the field IDs.

Primary use case: Kafka event schemas. If you're publishing events to a Kafka topic, Avro + Schema Registry is the standard.

### Schema Definition

```json
{
  "type": "record",
  "name": "OrderEvent",
  "namespace": "com.example.orders",
  "doc": "Event emitted when an order changes state",
  "fields": [
    {
      "name": "event_id",
      "type": "string",
      "doc": "UUID of this event"
    },
    {
      "name": "event_type",
      "type": {
        "type": "enum",
        "name": "OrderEventType",
        "symbols": ["ORDER_SUBMITTED", "ORDER_CONFIRMED", "ORDER_SHIPPED", "ORDER_CANCELLED"]
      }
    },
    {
      "name": "order_id",
      "type": "string"
    },
    {
      "name": "customer_id",
      "type": "string"
    },
    {
      "name": "status",
      "type": "string"
    },
    {
      "name": "occurred_at_ms",
      "type": "long",
      "logicalType": "timestamp-millis"
    },
    {
      "name": "metadata",
      "type": {
        "type": "map",
        "values": "string"
      },
      "default": {}
    },
    {
      "name": "previous_status",
      "type": ["null", "string"],   // union: nullable string
      "default": null
    }
  ]
}
```

### Confluent Schema Registry

```
Producer                   Schema Registry            Consumer
   │                              │                       │
   │── register schema ──────────▶│                       │
   │◀─ schema_id: 42 ─────────────│                       │
   │                              │                       │
   │── publish to Kafka ─────────────────────────────────▶│
   │   [magic byte | schema_id | avro_bytes]               │
   │                              │                       │
   │                              │◀─ fetch schema(42) ───│
   │                              │── return schema ──────▶│
   │                              │   (cached after first) │
   │                              │                       │
   │                              │                       │── deserialize ──▶ OrderEvent

```

```java
// Producer (Java + Confluent Kafka)
Properties props = new Properties();
props.put("bootstrap.servers", "kafka:9092");
props.put("schema.registry.url", "http://schema-registry:8081");
props.put("key.serializer", StringSerializer.class);
props.put("value.serializer", KafkaAvroSerializer.class);

KafkaProducer<String, OrderEvent> producer = new KafkaProducer<>(props);
producer.send(new ProducerRecord<>("order-events", orderId, orderEvent));
```

### Safe Schema Evolution (Avro Compatibility Modes)

```
BACKWARD (default):
  New schema can read old data
  → Safe: add field with default, remove field without default
  → Unsafe: add field without default (old data has no value for it)

FORWARD:
  Old schema can read new data
  → Safe: add field without default, remove field with default
  → Unsafe: remove field without default (old consumers expect it)

FULL:
  Both backward and forward compatible
  → Only: add/remove fields with defaults

NONE:
  No compatibility checks — dangerous in production

Rule: always set FULL compatibility in production Schema Registry.
      Add new fields with defaults. Never remove required fields.
```

### Avro vs Protobuf vs JSON

| | Avro | Protobuf | JSON |
|---|---|---|---|
| **Schema definition** | JSON schema | .proto file | None (JSON Schema opt-in) |
| **Schema at runtime** | Required (stored separately) | Compiled into binary | Optional |
| **Payload size** | Smallest for many-field records | Small | Large |
| **Field identification** | Field names (schema handles mapping) | Field numbers (compact) | Field names |
| **Schema evolution** | Compatibility modes (backward/forward/full) | Field numbers + reserved | Manual |
| **Language support** | Java, Python, Go, C, C++, Ruby | 20+ languages | Universal |
| **Primary use case** | Kafka events, Hadoop, data lake | gRPC, internal RPC | REST APIs, general |
| **Dynamic schema** | Yes (schema can be read at runtime) | No (must recompile) | Yes |

### FAANG Usage

**LinkedIn**: Avro is the standard for all Kafka events at LinkedIn. Confluent (founded by LinkedIn Kafka team) built Schema Registry to manage Avro schemas.

**Netflix**: Kafka events at Netflix use Avro + Schema Registry for event streaming between microservices.

**Uber**: Hudi data lake on HDFS uses Avro as the storage format.

---

## MessagePack

### What It Is

Binary JSON. Same data model as JSON (objects, arrays, strings, numbers, booleans, null) but encoded in a compact binary format. No schema required. Drop-in replacement for JSON where you want smaller payloads and faster parsing without changing your data model.

```
JSON:      {"id":"ord_abc","status":"SUBMITTED","amount":39.99}
Size:      52 bytes

MessagePack equivalent:
Size:      ~30 bytes (42% smaller for this example)

Rule of thumb: MessagePack is ~30-50% smaller than JSON, 2-4x faster to parse.
```

### When to Use MessagePack

- Internal APIs where clients are controlled and you want JSON-equivalent semantics with better performance
- Caching (Redis values, in-memory caches) — store as MessagePack instead of JSON strings
- WebSocket messages — binary frames instead of text JSON
- Not worth it for: external APIs (schema-free binary is hard to debug), or when performance isn't constrained

**Used at**: Redis uses MessagePack-like encoding in RESP3. CouchDB supports MessagePack.

---

## Twirp

### What It Is

Twitch's RPC framework (open-sourced 2018). Defines services in `.proto` files (same as gRPC) but transports over plain HTTP/1.1 instead of HTTP/2. Supports both Protobuf and JSON encoding over the same service definition.

### Why Twirp Exists

gRPC requires HTTP/2, which breaks many HTTP/1.1 proxies, load balancers, and monitoring tools without configuration. Twirp uses HTTP/1.1 POST with clear URL semantics:

```
POST /twirp/orders.v1.OrderService/GetOrder
Content-Type: application/protobuf   (or application/json)

# URL format: /twirp/{package}.{Service}/{Method}
```

### Twirp vs gRPC

| | Twirp | gRPC |
|---|---|---|
| **Transport** | HTTP/1.1 (or 1.1 + TLS) | HTTP/2 required |
| **Streaming** | None (request/response only) | Bidirectional streaming |
| **Wire format** | Protobuf or JSON | Protobuf |
| **Load balancing** | Standard HTTP LBs work | Needs L7 gRPC-aware LB |
| **Debug with curl** | Yes (JSON mode) | Needs grpcurl |
| **Browser** | Native (HTTP/1.1) | Needs grpc-web proxy |
| **Performance** | Slightly lower (no HTTP/2 mux) | Better on high-volume paths |
| **Use when** | Simplicity > streaming | Performance + streaming needed |

**Used at**: Twitch. Also popular in Go ecosystems where gRPC complexity is overkill.

---

## Connect (Buf)

### What It Is

ConnectRPC (by Buf, 2022) is the next evolution beyond gRPC-web and Twirp. It uses `.proto` schemas but supports HTTP/1.1, HTTP/2, and HTTP/3. Natively compatible with standard gRPC clients. Fixes the key pain points of gRPC:

- Works in browsers natively over HTTP/1.1 (no grpc-web proxy needed)
- Compatible with standard reverse proxies (nginx, Envoy, AWS ALB) without extra config
- JSON encoding option for debugging
- Backwards compatible with gRPC — a gRPC client can call a Connect server

```
Connect supports three protocols simultaneously:
  1. Connect protocol (native, HTTP/1.1 and HTTP/2)
  2. gRPC protocol (HTTP/2, full compatibility)
  3. gRPC-Web protocol (browser-compatible)

One server, all three protocols — clients choose what they support.
```

**Status**: emerging (2022–), gaining adoption. Recommended for new Go + browser projects where gRPC complexity is a concern.

---

## SOAP / XML-RPC

### What It Is

SOAP (Simple Object Access Protocol): XML-based RPC protocol from the early 2000s. Defines service contracts in WSDL (Web Services Description Language). Heavy, verbose, but extremely formal — the schema is machine-readable and tooling can auto-generate clients.

### Why It Still Matters

Legacy FAANG enterprise integrations (banking, insurance, government) still expose SOAP endpoints. As a principal engineer you won't design new SOAP services, but you'll need to:
- Integrate with legacy SOAP services via a REST or gRPC adapter
- Explain why you're NOT using SOAP (verbosity, HTTP-unfriendly, no streaming)
- Design a migration path from SOAP to REST/gRPC

```xml
<!-- SOAP Request -->
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"
                  xmlns:ord="http://example.com/orders">
    <soapenv:Header>
        <ord:AuthHeader>
            <ord:Token>eyJ...</ord:Token>
        </ord:AuthHeader>
    </soapenv:Header>
    <soapenv:Body>
        <ord:GetOrderRequest>
            <ord:OrderId>ord_abc123</ord:OrderId>
        </ord:GetOrderRequest>
    </soapenv:Body>
</soapenv:Envelope>
```

**Compared to the equivalent REST**:
```
GET /orders/ord_abc123
Authorization: Bearer eyJ...
```

The verbosity is self-evident.

---

## Serialization Format Comparison

| Format | Size | Parse Speed | Schema | Human-readable | Primary Use |
|---|---|---|---|---|---|
| **JSON** | Large | Moderate | Optional | Yes | REST APIs, general |
| **Protobuf** | Small | Fast | Required (.proto) | No | gRPC, internal RPC |
| **Avro** | Smallest | Fast | Required (JSON schema) | No | Kafka events, data lake |
| **Thrift Binary** | Small | Fast | Required (.thrift) | No | Thrift RPC |
| **MessagePack** | Medium-small | Fast | None | No | Caching, WebSocket |
| **XML/SOAP** | Very large | Slow | Required (WSDL/XSD) | Yes (verbose) | Legacy enterprise |
| **CBOR** | Small | Fast | None | No | IoT, embedded |

---

## Protocol Decision Matrix

```
New public API (third parties, browsers):
  → REST + JSON + OpenAPI

New internal service-to-service (< 10k RPS, no streaming):
  → gRPC (Protobuf) — or Twirp if HTTP/2 complexity is unwanted

New internal service-to-service (high-throughput, streaming):
  → gRPC with bidirectional streaming

Browser-native real-time (no proxy budget):
  → Connect (HTTP/1.1 + proto) or REST + SSE/WebSocket

Kafka event schema:
  → Avro + Confluent Schema Registry

Legacy internal Meta/Twitter/Uber codebase:
  → Thrift (don't rewrite unless there's a performance or capability forcing function)

Legacy enterprise integration (bank, insurance):
  → SOAP adapter → wrap with REST or gRPC facade; don't expose SOAP externally

Caching or WebSocket where JSON schema isn't worth proto complexity:
  → MessagePack
```

---

## FAANG Interview Callout

**"How would you migrate a Thrift-based internal service fleet to gRPC without downtime?"**
Strangler fig migration: (1) generate both Thrift and gRPC stubs from a shared IDL adapter layer; (2) new services write gRPC, old services write Thrift — a translation sidecar converts between them at the network boundary; (3) migrate callers service-by-service rather than all-at-once; (4) once all callers are on gRPC, decommission the Thrift server and sidecar. Never do a big-bang migration — the translation layer allows incremental rollout with rollback at each step. At Uber, this migration took ~2 years across thousands of services.

**"Why would you choose Avro over Protobuf for Kafka?"**
Two reasons. First: Avro's schema is stored in Schema Registry and resolved at runtime — consumers fetch the exact schema that was used to produce each message, enabling schema evolution without redeploying consumers. Protobuf requires schema to be compiled into the binary; distributed Kafka consumers can't easily hot-swap schemas. Second: Avro's JSON-based schema is easier for data teams to read and evolve. Kafka's ecosystem (Kafka Connect, ksqlDB, Confluent Cloud) has first-class Avro support. For gRPC you'd use Protobuf; for event streaming you'd use Avro.
