# API Lifecycle Management

## Why This Matters at Principal Engineer Level

APIs are long-lived contracts. A poorly designed API is technical debt that compounds across every consumer — internal teams, third-party integrators, and mobile clients you cannot force-upgrade. A principal engineer owns the API lifecycle: versioning strategy, deprecation process, breaking change communication, and the governance model that ensures APIs are designed for longevity from the start.

The cost of getting this wrong scales with adoption. A breaking change to an API used by 3 internal services is a planning problem. A breaking change to a public API used by 50,000 developers is a reputation and revenue event.

---

## API Versioning Strategies

### Strategy 1: URI Versioning (most common for REST)

Version included in the URL path.

```
https://api.example.com/v1/users
https://api.example.com/v2/users
```

**Pros**: Immediately visible; easy to route at the gateway; cacheable; simple for consumers  
**Cons**: URL is not the right place for content negotiation (purists object); resource duplication  
**Use when**: Public APIs, third-party integrators, mobile-consumed APIs

### Strategy 2: Header Versioning

Version specified in a request header.

```http
GET /users HTTP/1.1
Host: api.example.com
API-Version: 2024-01-15
Accept: application/json
```

**Pros**: Clean URLs; version is metadata (not part of the resource identity)  
**Cons**: Harder to debug (version not visible in URL); requires header-aware routing  
**Use when**: Internal APIs between services; GraphQL (schema evolution instead of versioning)  
**Real-world example**: Stripe uses date-based header versioning (`Stripe-Version: 2023-10-16`)

### Strategy 3: Content Negotiation (Accept header)

```http
GET /users HTTP/1.1
Accept: application/vnd.example.v2+json
```

**Pros**: REST-pure; version is tied to representation, not resource  
**Cons**: Complex for consumers; HTTP header values opaque to most tooling  
**Use when**: Rarely; mainly academic; not recommended for new APIs

### Strategy 4: No Versioning (additive-only evolution)

Design the API to evolve without version bumps by only making additive changes.

**Rules for additive-only evolution**:
- New fields can always be added to responses (consumers must ignore unknown fields)
- New optional fields can be added to requests
- New endpoints can always be added
- NEVER remove a field, NEVER change a field's type, NEVER change a field's semantics

**When it breaks down**: When a breaking change is genuinely required (security, compliance, fundamental redesign)

**Use when**: Internal APIs with disciplined consumers; event schemas (CloudEvents, Avro with schema registry)

---

## Breaking vs. Non-Breaking Changes

The most important skill in API lifecycle management: correctly classifying changes.

### Breaking Changes (require version bump or deprecation process)

```
Removal:
  - Remove an endpoint
  - Remove a field from a response
  - Remove a request parameter that was accepted (even if optional)
  - Remove an enum value

Type changes:
  - Change a field from string to integer
  - Change a field from nullable to required
  - Change a date format (ISO 8601 → Unix timestamp)
  - Narrow a field's range (was int64, now int32)

Semantic changes:
  - Change the meaning of a field without changing its name
    (e.g., "created_at" changed from UTC to local time)
  - Change pagination defaults (page size, cursor format)
  - Change sort order of a list endpoint
  - Change error codes or error response structure

Behavior changes:
  - Change idempotency semantics (was idempotent, now not)
  - Change rate limiting behavior
  - Change authentication requirements
  - Add required authentication to a previously public endpoint
```

### Non-Breaking Changes (safe to ship without versioning)

```
Additive changes:
  - Add a new optional field to response
  - Add a new optional request parameter
  - Add a new endpoint
  - Add a new enum value (consumers must handle unknown values)
  - Loosen validation (was required, now optional)
  - Increase rate limits
  - Add new error codes (consumers must handle unexpected codes gracefully)

Performance changes:
  - Change implementation without changing contract
  - Add caching (that doesn't change response)
  - Change infrastructure without changing behavior
```

**The Robustness Principle** (Postel's Law): Be conservative in what you send; be liberal in what you accept. Design consumers to tolerate unknown fields, unexpected error codes, and extended enum values.

---

## Deprecation Process

### The Deprecation Lifecycle

```
API Version State Machine:

  CURRENT ──────────────────────────────────────────► DEPRECATED
     │              (6-week notice minimum)                 │
     │                                                      │
     │                                             (deprecation period)
     │                                             (minimum 6 months)
     │                                                      │
     ▼                                                      ▼
  NEW VERSION                                          SUNSET (removed)
```

### Deprecation Notice Requirements

**What must happen when deprecating an API version**:

```
Week 0 — Announcement:
  □ Developer blog post / changelog entry (public APIs)
  □ Email to all registered API consumers (if email is available)
  □ In-product banner in developer portal
  □ Changelog updated with sunset date
  □ Migration guide published (how to move from v1 to v2)

Week 0+ — In-API signaling:
  □ Add Deprecation header to all responses from deprecated version:
    Deprecation: Sat, 01 Jan 2025 00:00:00 GMT
    Sunset: Tue, 01 Jul 2025 00:00:00 GMT
    Link: <https://developer.example.com/migrate-v1-to-v2>; rel="deprecation"
  □ Add warning to SDK and CLI clients

Sunset date:
  □ Minimum 6 months after announcement for external consumers
  □ Minimum 3 months for internal consumers (can coordinate directly)
  □ Minimum 12 months for consumers in regulated industries

Migration support:
  □ Office hours / Slack channel for migration questions
  □ Automated migration tool (if feasible)
  □ Migration validator: run consumer against v2, report compatibility gaps
```

### Tracking Consumer Migration

Before sunsetting a version, verify all consumers have migrated:

```
Migration Dashboard:
  v1 traffic over time:
    Week 0 (announcement):  100% of v1 consumers active
    Month 1:                 85% active
    Month 3:                 40% active
    Month 5:                 8% active → contact remaining consumers directly
    Sunset month:            0% (target) → turn off

Identification of laggard consumers:
  - Log consumer identity (API key, OAuth client ID) with version header
  - Generate weekly report: "These 12 API keys still calling v1"
  - Direct outreach to laggard consumers 30 days before sunset
  - Hard extension policy: 1 extension per consumer, max 90 days, requires justification
```

---

## API Design Governance

### API Design Review Process

Every new public or platform API should go through a review before implementation begins.

**When to require API design review**:
- New public external API endpoint
- New platform or shared internal API used by 3+ teams
- Breaking change to any existing API
- New API that will be embedded in an SDK

**API design review checklist**:

```
Resource Design:
□ Resources are nouns, not verbs (GET /orders, not GET /getOrders)
□ Resource hierarchy reflects domain model (/users/{id}/orders)
□ Collection endpoints return consistent pagination (cursor or offset, documented)
□ Singleton resources use singular path (/users/{id}/profile, not /profiles)

HTTP Semantics:
□ GET is safe and idempotent (no side effects, cacheable)
□ POST for creation (returns 201 + Location header)
□ PUT/PATCH for update (PUT replaces, PATCH partial update)
□ DELETE is idempotent (calling twice returns 204 or 404, never 500)
□ Status codes are semantically correct (not 200 for everything)

Request/Response Design:
□ Field names are camelCase (JSON) or snake_case (choose one, be consistent)
□ Timestamps are ISO 8601 UTC (2024-01-15T10:23:45Z)
□ IDs are strings (not integers) — allows future change to UUIDs without breaking type
□ Amounts are integers in smallest currency unit (cents, not dollars) or use decimal strings
□ Enums are strings (not integers) — "PENDING" not 1

Error Design:
□ Errors return structured body (not just HTTP status):
  { "error": { "code": "INVALID_PARAM", "message": "...", "field": "email" } }
□ Error codes are stable strings (not messages — messages can be translated)
□ 4xx errors include actionable information for the caller
□ 5xx errors include a request ID for correlation

Versioning:
□ Versioning strategy chosen before first release
□ Deprecation policy documented in API reference
□ Consumer impact analysis completed before any breaking change

Security:
□ Authentication required for all non-public endpoints
□ Authorization model documented (who can access what?)
□ Rate limiting defined (requests per minute per API key/user)
□ Sensitive data not in URL (tokens, PII go in headers or body, not query params)
□ No PII in response that caller doesn't need
```

### API Style Guide Enforcement

Enforce API design standards automatically, not just in review:

| Tool | What It Enforces |
|------|-----------------|
| **Spectral** | OpenAPI lint rules (field naming, required properties, error schema) |
| **openapi-diff** | Detects breaking changes between spec versions in CI |
| **Prism** | Mock server + contract testing from OpenAPI spec |
| **Pact** | Consumer-driven contract testing (consumer defines what it expects) |
| **Stoplight** | Design-first API workflow with governance rules |

**CI gate**: `openapi-diff` runs on every PR that touches API specs. Breaking changes require explicit override with EM approval.

---

## API Versioning Decision Matrix

| Signal | Recommended Strategy |
|--------|---------------------|
| Public API with third-party consumers | URI versioning (`/v1/`, `/v2/`) with 12-month deprecation period |
| Internal API between microservices | Header versioning OR additive-only evolution + schema registry |
| Mobile app API (iOS/Android) | URI versioning; longer deprecation window (18 months); old versions supported longer |
| GraphQL API | Schema evolution (additive-only); deprecation directives on fields; no version numbers |
| Webhook payloads / events | Schema registry (Avro, Protobuf, or JSON Schema with `$schema` + version field) |
| gRPC internal API | Protobuf backward compatibility rules; use `reserved` for removed fields |

---

## API Gateway and Traffic Management

At scale, API versioning is enforced at the gateway, not in the service:

```
Consumer Request
      │
      ▼
API Gateway (Kong / AWS API GW / Apigee)
      │
      ├── Route v1 → v1 service instances (or legacy code path)
      ├── Route v2 → v2 service instances (or new code path)
      ├── Enforce rate limits per API key
      ├── Authenticate (JWT validation, API key lookup)
      ├── Log version + consumer identity for migration tracking
      └── Inject deprecation headers for v1 responses
```

**Gateway-based versioning advantages**:
- Services don't need to understand versioning — they implement the current API
- Traffic can be shifted between versions without code changes
- A/B testing between versions is easy
- Usage metrics per version are automatically captured

---

## FAANG Interview Framing

### "How do you handle a breaking API change affecting 200 internal consumers?"

> "Breaking API changes at scale are a coordination problem, not a technical problem. My process: start with a deprecation announcement 6 weeks before the new version is available, so teams have a migration target. From day one of the new version being live, I instrument the old version to log every caller's identity — service name and team. I generate a weekly migration report showing which teams are still on v1, and I run automated contract tests to tell each team exactly what they need to change. The critical path is the slowest consumer: I identify the 3-5 teams that will be last to migrate and schedule 1:1 migration office hours with them. For the last 20% of consumers, direct outreach beats documentation. Sunset happens only after the migration dashboard shows zero traffic for 2 consecutive weeks. I've found that the teams that don't migrate aren't ignoring the change — they're prioritizing other work. Making their migration work visible to their EM is often the most effective lever."

### "How do you design an API for longevity?"

> "Longevity comes from two disciplines: additive-only evolution and semantic stability. Additive-only means I never remove a field or change a field's type — I only add. This lets me evolve the API without versioning for years. Semantic stability means field names and their meanings are locked at design time. The worst breaking changes are semantic ones: when 'amount' quietly changed from dollars to cents, or when 'status' started including new values that old clients didn't handle. I enforce this through API design review before implementation — once an API is in production, the design is frozen. For new capabilities that require breaking changes, I use URI versioning and a 12-month deprecation cycle, with automated consumer tracking to know exactly who still needs to migrate."

---

## Common API Anti-Patterns

| Anti-Pattern | Problem | Fix |
|-------------|---------|-----|
| **Versioning in response body** (`{"version": "v1", "data": ...}`) | Not a versioning strategy; mixing content and metadata | Use URL or header versioning |
| **Removing fields without deprecation** | Silent breaking change; consumers crash | Deprecation header + 6-month sunset minimum |
| **Verbs in URLs** (`/getUser`, `/createOrder`) | REST violation; not intuitive | Nouns + HTTP method (`GET /users`, `POST /orders`) |
| **Different error shapes per endpoint** | Consumers can't write generic error handling | Standard error envelope across all endpoints |
| **IDs as integers** | Leaks information (count of users); breaks when IDs exceed int32 | String IDs (UUID or opaque strings) |
| **Amounts as floats** | Floating point precision errors in financial calculations | Integer cents or decimal strings |
| **Versioning every service independently** | Consumers must track N version matrices | Facade / API gateway with single versioned surface |
| **No idempotency key support for mutations** | Retry storms create duplicate state | Idempotency key support on all POST/PUT operations |
