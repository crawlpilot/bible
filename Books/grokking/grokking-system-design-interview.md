# Grokking the System Design Interview
**Author**: Educative.io  
**Edition**: Educative, 2023 (continuously updated)  
**Category**: System Design · High-Level Design · Distributed Systems · Interview Preparation

> "A system design interview is not a test of knowledge — it is a test of judgment. The candidate who asks the right questions and makes the right trade-offs beats the candidate who memorises the most components."

---

## Why This Book Matters for FAANG PE Interviews

Grokking the System Design Interview is the single most-cited resource for FAANG system design preparation. It does two things that most books do not: it gives you an explicit step-by-step framework to structure any design problem, and it grounds each step in 15 production-scale case studies that cover the most commonly asked systems.

At the principal engineer level, the framework matters more than the case studies. Interviewers are not asking you to recite a known design — they are asking you to think through an unfamiliar problem under time pressure with incomplete information. The 7-step methodology in this book is the structured approach that stops you from freezing when the interviewer gives you an underspecified prompt.

**Direct interview mapping:**
- "Design a URL shortening service" → TinyURL case study, consistent hashing for distribution
- "Design a distributed cache" → Caching building block + sharding patterns
- "How would you build a news feed?" → Facebook Newsfeed case study, fanout strategies
- "Design a messaging system" → Facebook Messenger case study, WebSocket vs. polling
- "Scale this API to 10M users" → Back-of-envelope estimation + horizontal scaling patterns

---

## TL;DR — 4 Ideas to Internalize

1. **Start with requirements, not components.** Every design decision is an implicit trade-off; you cannot make good trade-offs without first knowing what you are optimising for.
2. **Back-of-envelope estimation is a first-class skill.** A candidate who says "we'll need roughly 10 TB/day" before designing storage signals more credibility than one who starts drawing boxes.
3. **Sharding and caching solve different problems.** Sharding addresses write scalability and data volume; caching addresses read latency and DB load. Confusing them in an interview is a red flag.
4. **Every building block has a failure mode.** The best candidates proactively name what breaks — cache stampede, hot partition, clock skew — before the interviewer asks.

---

## Part 1 — The 7-Step System Design Framework

The framework is a structured conversation guide, not a rigid sequence. In a 45-minute interview, Steps 1–3 take roughly 10 minutes, Steps 4–6 take 25 minutes, and Step 7 is woven throughout.

---

### Step 1: Requirements Clarification

**What to do:** Ask explicit questions to bound the problem. Never assume.

**Functional requirements** — what the system must do:
- What are the primary use cases? (read-heavy vs. write-heavy)
- What does "success" look like for the user? (latency, consistency, availability)
- Any specific features in scope or explicitly out of scope?

**Non-functional requirements** — at what scale and quality:
- How many users? DAU / MAU?
- Read/write ratio?
- Latency SLA? (P99 < 100ms? P99 < 1s?)
- Consistency requirement? (strict ACID? eventual consistency acceptable?)
- Availability target? (99.9%? 99.99%?)
- Data retention? Regulatory constraints?

**What interviewers look for:** A candidate who asks the right clarifying questions before touching the whiteboard signals they understand that system design is requirements-driven, not component-driven.

**Common mistake:** Skipping clarification and jumping straight to components. The interviewer will often give an underspecified prompt on purpose. Diving into a design for the wrong requirements is a fast failure.

---

### Step 2: System Interface Definition

**What to do:** Define the APIs the system must expose before designing its internals.

Defining APIs first forces you to think about the contract — what data goes in, what comes back, what the caller experiences. This is the "outside-in" design discipline.

**URL Shortener API example:**
```
createURL(api_key, original_url, custom_alias=None, expire_date=None)
  → short_url | Error

deleteURL(api_key, url_key)
  → 200 | 404 | 403

resolveURL(short_url)
  → 301 redirect | 404
```

**What interviewers look for:** Does the candidate think about authentication (api_key)? Rate limiting? Error cases? Expiry?

**Common mistake:** Treating API design as an afterthought. The API contract is the single most stable artifact in a system — downstream services, mobile clients, and external partners all depend on it. Getting it wrong is expensive.

---

### Step 3: Back-of-the-Envelope Estimation

**What to do:** Estimate QPS, storage, bandwidth, and memory before drawing a single component. These numbers drive every subsequent architectural decision.

**The estimation toolkit:**

| Number to know | Value |
|----------------|-------|
| DAU → QPS | DAU × actions/day ÷ 86,400 seconds |
| 1 million req/day | ~12 req/s |
| 1 billion req/day | ~12,000 req/s |
| Average tweet size | ~200 bytes |
| Average photo | ~300 KB |
| 1 TB storage | 10⁹ KB |
| SSD read latency | ~0.1 ms |
| Network round-trip (same DC) | ~0.5 ms |
| Network round-trip (cross-continent) | ~150 ms |

**URL shortener example:**
```
Assumptions:
- 500M new URLs/month, 100:1 read:write ratio
- URL record: ~500 bytes

Writes:
  500M / (30 × 86,400) ≈ 200 writes/s

Reads:
  200 × 100 = 20,000 reads/s

Storage (5 years):
  500M × 12 months × 5 years × 500 bytes ≈ 15 TB

Bandwidth:
  Read: 20,000 × 500 bytes = 10 MB/s
  Write: 200 × 500 bytes = 0.1 MB/s
```

**What interviewers look for:** Round numbers, explicit assumptions stated out loud, conclusions that drive design (e.g., "at 20K reads/s, we definitely need a caching layer").

**Common mistake:** Skipping estimation entirely, or estimating without drawing a conclusion. The numbers are only useful if they inform the design.

---

### Step 4: Defining the Data Model

**What to do:** Define the entities, their attributes, and how they relate. Choose a storage type and justify it.

**Key questions:**
- What are the primary entities? What fields does each have?
- What are the access patterns? (lookup by ID, range scan, full-text search?)
- What is the read/write ratio per entity?
- What are the consistency requirements per entity?

**URL shortener data model:**
```
URL Table:
  id            BIGINT PRIMARY KEY   # internal auto-increment
  url_key       VARCHAR(6)           # the short code (hash or encoded ID)
  original_url  VARCHAR(4096)
  created_at    DATETIME
  expire_at     DATETIME
  user_id       BIGINT               # FK to users table

User Table:
  user_id       BIGINT PRIMARY KEY
  email         VARCHAR(256) UNIQUE
  api_key       VARCHAR(64) UNIQUE
  created_at    DATETIME
```

**Storage choice decision:**

| Need | Choose |
|------|--------|
| Relational data, ACID transactions | SQL (Postgres, MySQL) |
| High write throughput, horizontal scale | NoSQL KV (DynamoDB, Cassandra) |
| Graph relationships | Neo4j, or adjacency list in SQL |
| Full-text search | Elasticsearch / OpenSearch |
| Blob/file storage | S3 / GCS / Azure Blob |
| Time-series metrics | InfluxDB, TimescaleDB, Prometheus |
| Caching layer | Redis, Memcached |

**What interviewers look for:** Did the candidate choose storage based on access patterns, not habit? Can they justify SQL vs. NoSQL?

---

### Step 5: High-Level Design

**What to do:** Draw the major components and data flows. 5–8 boxes maximum at this stage.

The standard components in most designs:
```
Client
  │
  ▼
Load Balancer (L7 / ALB)
  │
  ▼
Application Servers (stateless, horizontally scalable)
  │              │
  ▼              ▼
Cache (Redis)   Primary Database
                    │
                    ▼
                Replica(s)
                    │
                    ▼
                CDN (for static assets)
```

**URL shortener high-level design:**
```
Client
  │ POST /api/create  GET /short_code
  ▼
Load Balancer
  │
  ▼
Write Servers ──────────────────► SQL DB (URL mapping)
                                      │
Read Servers ──► Cache (Redis) ──► SQL DB (on cache miss)
  │
  ▼ 301 Redirect
Client
```

**What interviewers look for:** Can the candidate separate read and write paths? Do they think about statelessness so servers can be scaled horizontally?

---

### Step 6: Detailed Design

**What to do:** Deep-dive on the 2–3 most interesting or hardest components. The interviewer will often steer this.

**Where to focus:**
- The bottleneck you identified (usually: DB writes, cache invalidation, or data distribution)
- The component with the most interesting trade-offs (usually: the storage or messaging layer)
- The component the interviewer asks about

**URL shortener — key-generation deep dive:**

Option A: MD5 hash of URL, take first 6 characters
```
hash("https://www.example.com/...") → "a9b5c2"
Problem: collision probability at 500M URLs with 6-char base62 space (62^6 = 56B) is low but non-zero.
Solution: check for collision before inserting; regenerate on collision.
```

Option B: Counter-based encoding (base62 of auto-increment ID)
```
ID: 1,000,000 → base62: "4c92"
Advantages: no collisions, predictable. 
Disadvantages: sequential — IDs are guessable; single point of failure if centralized counter.
Solution: distributed counter using Zookeeper or pre-generated key DB.
```

Option C: Key Generation Service (KGS)
```
Offline worker pre-generates 6-char keys, stores in "unused keys" table.
On request: application server marks one key used and returns it.
Advantages: fast O(1) reads, no collision risk.
Disadvantages: single point of failure for KGS — mitigated by replica + in-memory buffer.
```

**What interviewers look for:** Multiple options considered, trade-offs named, a recommendation made with rationale.

---

### Step 7: Identifying and Resolving Bottlenecks

**What to do:** Proactively name the failure modes and hot paths in your design. Don't wait for the interviewer to poke holes.

**Standard bottleneck checklist:**
- Single point of failure — every critical component has a replica?
- Hot partition — does consistent hashing distribute load evenly?
- Cache stampede — what happens when the cache is cold (cold start)?
- N+1 query problem — are there implicit fan-out patterns?
- Thundering herd — what happens after a deployment when many clients reconnect simultaneously?
- Cascading failure — if DB is slow, do servers back up with queued connections?
- Clock skew — if using timestamps for ordering, are clocks synchronized (NTP)?

**URL shortener bottlenecks:**
- If DB is down, redirect service fails → add read replicas + circuit breaker
- Cache eviction during traffic spike → pre-warm cache; use Redis Cluster for capacity
- KGS is single point → run two KGS instances, each with its own key range

**FAANG signal:** "Design this system for 100x the traffic you just designed for." If your design can be scaled by adding more instances of stateless components and sharding the DB, you have a good foundation.

---

## Part 2 — Core Building Blocks

Each building block is a standalone pattern. Know the trade-offs cold — interviewers probe these explicitly.

---

### Building Block 1: Load Balancing

**Purpose:** Distribute traffic across multiple servers to avoid single-point overload.

**Algorithms:**

| Algorithm | How it works | Best for |
|-----------|-------------|----------|
| Round-robin | Requests distributed sequentially | Homogeneous servers, equal request cost |
| Weighted round-robin | Proportional to server weight | Heterogeneous server capacity |
| Least connections | Route to server with fewest active connections | Variable request duration |
| IP hash | Hash of client IP → same server | Session stickiness (no cookie needed) |
| Random | Random selection | Simple; equivalent to round-robin at scale |

**L4 vs. L7:**
- L4 (TCP level): faster, no HTTP awareness, preserves client IP. AWS NLB.
- L7 (HTTP level): path/header routing, TLS termination, WAF integration. AWS ALB.

**Health checking:** Load balancer removes a backend from rotation when health check fails (TCP connect or HTTP GET /health → 200). Re-adds when it recovers.

---

### Building Block 2: Caching

**Purpose:** Reduce database load and decrease read latency by storing frequently accessed data in fast memory.

**Cache placement strategies:**

| Strategy | Where | Latency | Consistency |
|----------|-------|---------|-------------|
| Client-side | Browser / mobile | Near-zero | Stale by design |
| CDN | Edge PoP | ~10ms | TTL-based |
| Reverse proxy cache | Nginx / Varnish | ~1ms | TTL-based |
| Application cache | Redis / Memcached | ~0.5ms | Application-controlled |
| DB query cache | DB internal | ~0.1ms | Invalidated on writes |

**Cache invalidation strategies:**

| Strategy | Mechanism | Pro | Con |
|----------|-----------|-----|-----|
| **Write-through** | Write to cache + DB simultaneously | Cache always fresh | Write latency 2× |
| **Write-around** | Write to DB only; cache populated on next read | No write amplification | Cold start on first read |
| **Write-back (write-behind)** | Write to cache first; flush to DB async | Lowest write latency | Risk of data loss if cache crashes |

**Cache eviction policies:**

| Policy | How it works | Best for |
|--------|-------------|----------|
| LRU (Least Recently Used) | Evict item not accessed longest | General purpose — most common |
| LFU (Least Frequently Used) | Evict item accessed least often | Skewed access patterns (Zipf) |
| FIFO | Evict oldest inserted item | Time-ordered data |
| Random | Evict random item | Simple; similar to LRU in practice |

**Cache stampede / thundering herd:** When a popular cache entry expires, thousands of concurrent requests hit the DB simultaneously. Solutions:
1. **Mutex/lock:** First request acquires a lock and fetches; others wait.
2. **Probabilistic early expiry:** Re-compute cache before TTL expires based on staleness probability.
3. **Cache warming:** Pre-populate cache before expiry using a background job.

---

### Building Block 3: Data Partitioning (Sharding)

**Purpose:** Distribute data across multiple databases to scale beyond a single machine's capacity.

**Partitioning strategies:**

| Strategy | How | Pro | Con |
|----------|-----|-----|-----|
| **Horizontal (range)** | Rows with key A–M → shard 1; N–Z → shard 2 | Simple range queries | Hot partitions (popular letters) |
| **Horizontal (hash)** | hash(key) % N → shard index | Uniform distribution | No range queries; rebalancing hard |
| **Vertical** | Table A on DB1; table B on DB2 | Simple; good for different access patterns | Cross-table joins require application-level join |
| **Directory-based** | Lookup table maps key → shard | Flexible rebalancing | Lookup table is single point of failure |
| **Consistent hashing** | Keys and nodes on a ring; each key → nearest clockwise node | Minimal re-mapping when nodes added/removed | Requires virtual nodes for uniform distribution |

**Consistent hashing detail:**
```
Ring: 0 ─── 100 ─── 200 ─── 300 ─── 360(=0)
Nodes: A@50, B@150, C@250, D@350

key hash=80 → node A (nearest clockwise after 80)
key hash=170 → node C (nearest clockwise after 170)

Adding node E@100: only keys 51–100 move from A to E. Not a full reshuffle.
```

Virtual nodes: each physical node gets K positions on the ring. Ensures more uniform distribution and better load balancing when node capacities differ.

---

### Building Block 4: Indexes

**Purpose:** Speed up read queries at the cost of write performance and storage.

| Index type | Use case | Notes |
|------------|----------|-------|
| B-tree (default) | Range queries, ORDER BY, =, <, > | Postgres/MySQL default; balanced tree |
| Hash | Exact equality only (=) | Faster than B-tree for pure lookups |
| Composite | Multiple columns, left-prefix rule | `(user_id, created_at)` supports queries on user_id or user_id+created_at |
| Inverted | Full-text search | Elasticsearch, Postgres tsvector |
| Bitmap | Low-cardinality columns (status, boolean) | OLAP systems; column stores |

**Trade-off:** Every index slows writes (the index must be updated on insert/update/delete) and uses storage. Add indexes only for columns that appear in WHERE, JOIN, or ORDER BY on hot query paths.

---

### Building Block 5: Proxies

| Type | Direction | What it does |
|------|-----------|-------------|
| **Forward proxy** | Client → Internet | Client-side; anonymisation, outbound filtering |
| **Reverse proxy** | Internet → Servers | Server-side; TLS termination, LB, caching |
| **Sidecar proxy** | Service ↔ Service | East-west traffic; mTLS, circuit breaking (Envoy) |

---

### Building Block 6: SQL vs. NoSQL

| Dimension | SQL | NoSQL |
|-----------|-----|-------|
| **Data model** | Relational tables, fixed schema | Document, KV, wide-column, graph |
| **Consistency** | ACID by default | BASE (Basically Available, Soft state, Eventual) |
| **Scaling** | Vertical primary; sharding is hard | Horizontal by design |
| **Query flexibility** | Arbitrary SQL joins, aggregations | Limited to defined access patterns |
| **Schema changes** | Migrations required | Flexible / schemaless |
| **Best for** | Financial data, inventory, user profiles (complex joins) | High write throughput, flexible schema, geographic distribution |

**Decision rule:** If you need multi-entity ACID transactions → SQL. If you need horizontal write scalability with a known access pattern → NoSQL.

---

### Building Block 7: CAP Theorem

In any distributed system with network partitions (P), you can guarantee at most 2 of: Consistency (C) and Availability (A).

| Choice | What it means | Examples |
|--------|--------------|---------|
| **CP** | Consistent responses or no response during partition | HBase, ZooKeeper, etcd, Spanner |
| **AP** | Always responds, may return stale data | Cassandra, DynamoDB (eventually consistent), CouchDB |
| **CA** | Consistent + available — only possible with no partitions | Single-node SQL (technically not distributed) |

**Interview framing:** "Given this is a social network (news feed), eventual consistency is acceptable — AP. For a payment system, we need CP. I'll design with Cassandra for the feed and Postgres for payments."

---

### Building Block 8: Consistent Hashing

See Partitioning section above. Key points to cite in interviews:
- Standard hash (key % N) requires full reshuffle when N changes. Consistent hashing remaps only K/N keys (K = keys, N = nodes).
- Virtual nodes solve uneven distribution.
- Used in: Amazon Dynamo, Apache Cassandra, Memcached (ketama), CDN routing.

---

### Building Block 9: Long-Polling vs. WebSockets vs. Server-Sent Events

| Mechanism | Direction | Connection | Best for |
|-----------|-----------|------------|----------|
| **Short polling** | Client pulls | New HTTP req each poll | Simple, low-frequency updates; high waste |
| **Long polling** | Client pulls (held open) | HTTP req held until data or timeout | Chat (simple), notifications |
| **Server-Sent Events (SSE)** | Server → Client | Single HTTP connection, server streams | One-way: live feeds, dashboards |
| **WebSocket** | Bidirectional | Persistent TCP connection | Chat, gaming, collaborative editing |

**Decision rule:**
- Bidirectional real-time (chat, multiplayer) → WebSocket
- One-directional server push (notifications, live scores) → SSE
- Simple low-frequency updates → long polling
- Legacy / corporate network restrictions → SSE or long polling (WebSocket may be blocked by proxies)

---

## Part 3 — 15 Case Study Reference Cards

Each card: scale numbers, core design insight, FAANG interview angle.

---

### 1. URL Shortener (TinyURL)
- **Scale:** 500M new URLs/month; 100:1 read:write; 15 TB in 5 years
- **Core insight:** Key generation is the hardest part, not the redirect. Use a Key Generation Service (KGS) with pre-computed base62 keys to avoid collision and hash computation on the hot path.
- **FAANG angle:** "How do you guarantee uniqueness at this scale?" → KGS + unused/used keys table. "How do you handle redirects for billions of lookups/day?" → Cache (Redis) in front of DB; 301 vs. 302 trade-off (301 = cached at browser; 302 = tracked every time).

### 2. Pastebin
- **Scale:** 1M new pastes/day; 5:1 read:write; 10 years retention
- **Core insight:** Separate metadata (DB) from content (object store — S3). Content is immutable once created; metadata (key, URL, expiry) is small and relational.
- **FAANG angle:** "How do you handle large pastes efficiently?" → Store content in S3, store S3 path in DB. "How do you handle expiry?" → TTL column + background cleanup job or DynamoDB TTL.

### 3. Instagram
- **Scale:** 1B users; 100M photos/day; 500M DAU; read >> write
- **Core insight:** Photos are write-once, read-many → CDN is the dominant read path. The news feed is the hardest part (fan-out on write vs. fan-out on read).
- **FAANG angle:** "How do you handle celebrity accounts (1M+ followers) posting?" → Fan-out on read for celebrities; fan-out on write for regular users (hybrid approach). Tiered follower list.

### 4. Dropbox
- **Scale:** 500M users; 100M DAU; petabytes of files
- **Core insight:** Chunking (4MB blocks). Only changed chunks are uploaded. Each chunk is content-addressed (hash) — deduplication is free. Delta sync on mobile.
- **FAANG angle:** "How do you handle large file uploads efficiently?" → Chunked upload with resumability. "How do you handle sync conflicts?" → Vector clocks or last-write-wins with conflict UI.

### 5. Facebook Messenger
- **Scale:** 1B users; 100B messages/day; P99 delivery < 500ms
- **Core insight:** Message delivery is a fan-out + delivery receipt problem. Use message queues (per user) + WebSocket connections for real-time delivery. Persistent storage for message history.
- **FAANG angle:** "How do you guarantee message ordering?" → Sequence IDs per conversation. "How do you handle offline users?" → Push notification on reconnect + pull on open.

### 6. Twitter
- **Scale:** 300M MAU; 500M tweets/day; 300K QPS read; 6K QPS write
- **Core insight:** Timelines are pre-computed (fan-out on write) for regular users, computed on read for celebrities. Timelines are stored in Redis (in-memory sorted set).
- **FAANG angle:** "How do you handle the celebrity fan-out problem?" → Separate the < 1M follower path (pre-compute) from the celebrity path (pull and merge at read time). "How do you handle trending topics?" → Count-min sketch for approximate real-time frequency counting.

### 7. YouTube / Netflix
- **Scale:** 2B users; 500 hours of video uploaded/min; 1B hours watched/day
- **Core insight:** Video transcoding is CPU-intensive and async. Upload → Object store → Transcoding farm → CDN. The CDN does 90% of all reads. Adaptive bitrate (ABR) streaming.
- **FAANG angle:** "How do you reduce buffering?" → ABR (HLS/DASH): client switches between 240p/480p/720p/1080p based on bandwidth. "How do you handle global distribution?" → Multi-region CDN PoPs with geo-routing.

### 8. Typeahead Suggestion
- **Scale:** Google search: 3.5B queries/day; P99 suggestion latency < 100ms
- **Core insight:** Trie data structure for prefix matching, but trie is stored in memory and replicated. Pre-compute top-K suggestions per prefix offline; only serve from in-memory cache at runtime.
- **FAANG angle:** "How do you keep suggestions fresh?" → Offline batch job recomputes top-K daily. For breaking news, biased toward recent queries using exponential decay weighting.

### 9. API Rate Limiter
- **Scale:** 100K+ API keys; per-key, per-IP, per-endpoint limits
- **Core insight:** The algorithm is the key decision. Sliding window log is most accurate but memory-heavy. Token bucket handles bursts. Fixed window has edge-case overflows.
- **FAANG angle:** "How do you rate limit across a cluster of API servers?" → Centralized counter in Redis (atomic INCR with TTL). "How do you handle the edge case of fixed window?" → Sliding window counter = fixed window with two-window weighted average.

**Rate limiting algorithms:**

| Algorithm | Burst handling | Memory | Notes |
|-----------|---------------|--------|-------|
| Fixed window | Allows 2× limit at window boundary | Low | Simple; race condition at boundary |
| Sliding window log | Exact | High (stores all request timestamps) | Most accurate |
| Sliding window counter | Approx | Low | Weighted average of current + previous window |
| Token bucket | Yes | Low | Allows burst up to bucket size |
| Leaky bucket | No (smooths to constant rate) | Low | Constant outflow; queues bursts |

### 10. Twitter Search
- **Scale:** 500M tweets/day; search queries across all tweets
- **Core insight:** Inverted index. Each word maps to a list of tweet IDs that contain it. Index is sharded by word. Query fan-out across shards → merge results → sort by relevance.
- **FAANG angle:** "How do you index tweets in near-real-time?" → Log aggregation (Kafka) → indexer workers → Elasticsearch. "How do you rank results?" → TF-IDF baseline + engagement signals (retweets, likes).

### 11. Web Crawler
- **Scale:** 15B pages; 1M pages/s peak crawl rate
- **Core insight:** Frontier (URL queue) management is the bottleneck. BFS traversal with priority queue. Politeness: limit requests to same domain (robots.txt, 1 req/s per domain). Deduplication with Bloom filter.
- **FAANG angle:** "How do you avoid crawling the same URL twice?" → URL fingerprint (MD5) stored in Bloom filter (fast, memory-efficient). "How do you prioritize fresh content?" → PageRank-like priority score + recrawl scheduling.

### 12. Facebook Newsfeed
- **Scale:** 2B users; ~200 friends/user; 1,500 posts/day in feed
- **Core insight:** Fan-out on write vs. fan-out on read trade-off. For most users: pre-compute feed on post creation (push model, write-time fan-out). For celebrities: pull and merge at read time.
- **FAANG angle:** "How do you handle feed ranking?" → ML model (EdgeRank successor) scoring posts by relevance, recency, engagement. Pre-rank at write time; re-rank at serve time based on fresh engagement.

### 13. Yelp / Proximity Service
- **Scale:** 100M places; 500M queries/day; search by location + category
- **Core insight:** Geospatial indexing. Two options: QuadTree (divide space recursively until < N points per region) or Geohash (encode lat/lng into a base32 string — nearby locations share prefix).
- **FAANG angle:** "How do you find all restaurants within 5 miles?" → Geohash: expand to K-length prefix, query all cells at that radius. "How do you handle uneven point density?" → QuadTree adapts to density automatically; Geohash cells are fixed size.

### 14. Uber Backend
- **Scale:** 100M trips/day; real-time location tracking; sub-second driver matching
- **Core insight:** Two problems: (1) location tracking — high-write KV store (driver position updates 4x/sec); (2) matching — spatial index of available drivers, queried per rider request.
- **FAANG angle:** "How do you match a rider to a driver in sub-second?" → H3 hexagonal index (Uber's open source): divide earth into hexagons, query all hexagons within radius. "How do you handle high-write location updates?" → Cassandra write path (MemTable → SSTable, tunable consistency).

### 15. Ticketmaster / Event Booking
- **Scale:** Flash sales: 10M concurrent users for a Taylor Swift concert in 60 seconds
- **Core insight:** Inventory is a finite, highly-contended resource. Two approaches: optimistic locking (attempt purchase, detect conflict, retry) vs. virtual waiting room (throttle entry into the purchase flow).
- **FAANG angle:** "How do you prevent overselling?" → Redis DECR on available inventory (atomic). "How do you handle a 10M concurrent spike?" → Virtual waiting room + queue; rate-limit buyers into checkout flow.

---

## Part 4 — Quick-Reference: Which Building Block for Which Problem?

```
Need to distribute traffic across servers?
  └──► Load Balancer (L4 for TCP, L7 for HTTP routing)

Need to reduce DB reads / reduce latency?
  └──► Cache (Redis for hot data; CDN for static assets)

Need to scale writes beyond a single DB?
  └──► Sharding (consistent hashing for KV; range for time-series)

Need to find nearby items by location?
  └──► Geospatial index (QuadTree or Geohash)

Need real-time bidirectional communication?
  └──► WebSocket (chat, gaming, collaborative editing)

Need server-push notifications (one-way)?
  └──► SSE or long-polling

Need approximate membership check (has this URL been crawled?)?
  └──► Bloom filter

Need to count frequencies approximately (trending topics)?
  └──► Count-Min Sketch

Need distributed coordination / leader election?
  └──► ZooKeeper / etcd

Need message queue / async decoupling?
  └──► Kafka (high throughput, replay) or SQS/RabbitMQ (simpler)

Need to pre-compute aggregations on large datasets?
  └──► Batch processing (MapReduce / Spark) + result cache

Need to handle thundering herd on cache expiry?
  └──► Mutex lock on cache refill or probabilistic early expiry
```

---

## Actionable Takeaways for FAANG Preparation

1. **Memorise the estimation reference numbers.** In an interview, estimating storage or QPS quickly and correctly is a credibility signal. Know: 1M req/day ≈ 12 req/s; a tweet is ~200 bytes; a photo is ~300 KB; a video minute at 720p is ~50 MB.

2. **Know the cache invalidation strategies cold.** Write-through vs. write-back vs. write-around and their failure modes appear in almost every design problem that involves a cache.

3. **For every case study, know one non-obvious design insight.** TinyURL → KGS. Twitter → hybrid fan-out for celebrities. Dropbox → content-addressed chunking. These are the details that distinguish a prepared candidate.

4. **Always end with failure modes.** Before the interviewer asks "what breaks?" — name it yourself. "One thing I'd want to revisit is the cache stampede behaviour when this cache tier restarts after a deploy." This is the principal engineer signal.

---

## Common Interviewer Follow-Up Questions

**"Walk me through how you'd design a URL shortener."**

> "First, I want to clarify: are we optimising for read latency (many redirects) or write throughput (many URL creations)? At 500M new URLs/month with a 100:1 read:write ratio, reads dominate, so I'd architect around that. The write path creates a short code — I'd use a Key Generation Service that pre-computes base62 keys offline, avoiding collision computation on the hot path. The read path is a lookup of short code → original URL, which I'd cache aggressively in Redis with a 24-hour TTL. The DB is just there for persistence and for cache misses. I'd shard by hash of the short code for uniform distribution. The interesting failure mode is KGS — I'd run two instances with non-overlapping key ranges, each buffering 1M keys in memory so a KGS failure doesn't immediately impact write throughput."

**"What are the trade-offs between fan-out on write vs. fan-out on read for a news feed?"**

> "Fan-out on write: when User A posts, we immediately write to each follower's feed queue. Pro: read is fast (O(1) — just read your queue). Con: celebrity with 100M followers creates 100M writes per post — that's a massive write amplification problem. Fan-out on read: we store the post once and compute each user's feed by querying who they follow and merging their posts. Pro: no write amplification. Con: read is expensive O(followers). The hybrid approach — used by Twitter and Instagram — is fan-out on write for users with < 1M followers, fan-out on read for celebrities. At read time, you merge the pre-computed feed with the celebrity posts pulled separately."

**"How would you handle rate limiting across a distributed cluster?"**

> "Single-server rate limiting is easy — keep a counter in memory. Distributed is the challenge because request 1 might hit server A and request 2 might hit server B. Three approaches: (1) Centralized Redis counter — atomic INCR+EXPIRE on a key like `rate_limit:user_id:window`; very accurate but Redis becomes a dependency. (2) Local approximate limiting — each server maintains its own counter; accept that the real limit is approximately N × servers. Works for loose limits. (3) Sticky routing — route requests from the same user to the same server via consistent hashing on user ID; keeps the counter local. I'd use Redis for strict per-user limits with token bucket algorithm, accepting the Redis latency (~0.5ms) as the trade-off."

**"What's the difference between sharding and replication?"**

> "Replication solves availability and read scalability — you have copies of the same data on multiple nodes. If one node fails, another takes over. Read replicas can serve read traffic. But all replicas have all the data, so you're not solving storage or write scalability. Sharding solves write scalability and storage volume — each node has a different subset of the data. You can spread writes across shards. But sharding complicates cross-shard queries and makes rebalancing hard. In practice, you combine both: each shard is a replication group. The shard owns a key range, and that shard runs as a 3-node Raft group with a leader (writes) and followers (reads + failover)."
