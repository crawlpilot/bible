# System Design Interview — An Insider's Guide, Volume 1
**Author**: Alex Xu  
**Edition**: 2nd Edition  
**Category**: System Design · Distributed Systems · FAANG Interview Prep

> Covers 15 canonical system design problems. Every problem includes requirements, capacity estimation, high-level design, deep-dive decisions, trade-offs, failure modes, and principal-engineer follow-up questions.

---

## Why This Book Matters for FAANG PE Interviews

Vol. 1 is the most widely assigned pre-interview reading at Google, Meta, Amazon, and Stripe. Its 15 problems are the baseline: if you cannot walk through any of these end-to-end in 45 minutes, you are not ready. At the **principal engineer level**, you are expected to go beyond the book — call out its simplifications, propose alternative designs, quantify the trade-offs with real numbers, and proactively discuss failure modes the interviewer never asked about.

**How to use this summary**:
- Each chapter is structured as: Problem → Requirements → Estimation → Design → Deep Dives → Trade-offs → PE-Level Extensions
- Numbers given are from the book + real-world references — memorize the order of magnitude, not the exact digits

---

## Chapter 1 — Scale From Zero to Millions of Users

### The Problem
Design a system architecture that can grow from a single server to supporting millions of concurrent users. This is not a single "design X" problem — it is a mental model for how any system evolves under load.

### The Scaling Ladder

| Stage | Architecture | Bottleneck Resolved |
|-------|-------------|---------------------|
| **1 — Single Server** | Web + DB + everything on one box | None — this is day 0 |
| **2 — Separate DB** | App server ↔ database server | App and DB no longer compete for CPU/memory |
| **3 — Load Balancer + Multiple App Servers** | LB distributes traffic; app servers are stateless | Single point of failure in app layer |
| **4 — Database Replication** | Primary (writes) + replicas (reads); failover on primary failure | Read throughput; primary SPOF |
| **5 — Cache Layer** | Redis/Memcached sits between app and DB; cache-aside pattern | Database read hotspots; repeated queries |
| **6 — CDN** | Static assets (JS, CSS, images) served from edge nodes | Latency for geographically distributed users |
| **7 — Stateless Web Tier** | Sessions stored in shared cache (Redis), not local memory | Sticky sessions; horizontal scaling of web tier |
| **8 — Multiple Data Centers** | Active-active or active-passive; geo-DNS routing | Regional outage; latency for distant users |
| **9 — Message Queue** | Producers publish; consumers process async | Tight coupling; slow consumers blocking fast producers |
| **10 — Database Scaling** | Vertical → Horizontal sharding; denormalization | Write throughput ceiling of a single DB instance |
| **11 — Monitoring & Automation** | CI/CD, metrics, alerting, distributed tracing | Operational blindness at scale |

### Key Design Decisions at Each Stage

**Cache invalidation strategies**:
- **Cache-aside (lazy loading)**: App checks cache first; miss → fetch DB → populate cache. Simplest. Risk: cache stampede on cold start.
- **Write-through**: Write to cache and DB simultaneously. Cache always consistent. Wasted cache for write-heavy workloads.
- **Write-behind (write-back)**: Write to cache; async flush to DB. Low write latency. Risk: data loss if cache crashes before flush.

**Database replication failure modes**:
- Primary fails: promote a replica; application reconfigures write endpoint
- Replica fails: read traffic shifts to other replicas or primary temporarily
- Replication lag: reads from replica may return stale data → read-your-writes inconsistency

**Stateless vs stateful web tier**:
- Stateless: session data in Redis; any server handles any request; trivial horizontal scaling
- Stateful: sticky sessions via LB; server crash = lost session; anti-pattern for horizontal scaling

### Principal Engineer Extensions
- **How does sharding affect transactions?** Cross-shard transactions require 2PC or saga pattern — avoid whenever possible by designing shard keys so related data lives on the same shard.
- **When does a cache hurt?** Cache adds complexity, a potential SPOF, and inconsistency windows. Don't cache data that changes faster than the TTL or data that has complex invalidation dependencies.
- **What is the real bottleneck before adding CDN?** Profile first. CDN helps only when static asset delivery is the bottleneck — often the DB is the real issue.

---

## Chapter 2 — Back-of-the-Envelope Estimation

### Why This Chapter Exists
You cannot design a system you cannot size. Interviewers use estimation to see if you think in orders of magnitude and whether your design is calibrated to the problem.

### Power of Two Reference Table

| Unit | Value | Example |
|------|-------|---------|
| 1 KB | 10³ bytes | A tweet |
| 1 MB | 10⁶ bytes | A photo thumbnail |
| 1 GB | 10⁹ bytes | A 720p video minute |
| 1 TB | 10¹² bytes | 1,000 users × 1GB each |
| 1 PB | 10¹⁵ bytes | All Facebook photos in 2010 |

### Latency Reference Numbers (Google/Jeff Dean)

| Operation | Latency |
|-----------|---------|
| L1 cache reference | 0.5 ns |
| L2 cache reference | 7 ns |
| Main memory reference | 100 ns |
| SSD random read | 150 µs |
| Network round-trip (same DC) | 500 µs |
| HDD seek | 10 ms |
| Network round-trip (cross-continent) | 150 ms |

**Implications**:
- Memory is 20,000× faster than disk — prefer in-memory reads for hot data
- SSD is 200× faster than HDD — use SSDs for latency-sensitive storage
- Cross-DC round trip is 300× slower than in-DC — design for locality

### Estimation Template

**Step 1 — Clarify scale**: DAU, request types (read vs write ratio), payload sizes, retention period  
**Step 2 — Derive QPS**: `QPS = DAU × requests_per_user / 86,400`  
**Step 3 — Peak QPS**: `Peak QPS = QPS × 2` (rule of thumb)  
**Step 4 — Storage per day**: `QPS × payload_size × 86,400`  
**Step 5 — 5-year storage**: `daily_storage × 365 × 5`  
**Step 6 — Bandwidth**: `peak_QPS × payload_size`

### Worked Example — Twitter-Scale Feed

```
DAU: 300M users
Avg tweets per user per day: 0.5
Write QPS: 300M × 0.5 / 86,400 ≈ 1,700 writes/s; peak ≈ 3,400 writes/s

Avg tweet reads per user per day: 20 (home timeline refreshes)
Read QPS: 300M × 20 / 86,400 ≈ 70,000 reads/s; peak ≈ 140,000 reads/s
Read:write ratio ≈ 40:1

Tweet size: 280 chars = ~280 bytes + metadata ≈ 1 KB
Daily write storage: 1,700 × 1 KB × 86,400 ≈ 150 GB/day
5-year storage: 150 GB × 365 × 5 ≈ 270 TB (tweets only)

Media (assume 20% tweets have 1 image, avg 1 MB compressed):
1,700 × 0.2 × 1 MB × 86,400 ≈ 30 TB/day → 55 PB over 5 years
```

### Common Estimation Pitfalls
- Forgetting to multiply by replication factor (3× for most systems)
- Ignoring metadata overhead (indexes, timestamps, user IDs add ~30% to raw data)
- Not distinguishing read QPS from write QPS — most systems are read-heavy (10:1 to 100:1)
- Using 100,000 seconds/day instead of 86,400 (acceptable approximation for estimation)

---

## Chapter 3 — A Framework for System Design Interviews

### The RESHADED Framework (Extended from the book)

| Step | What to Do | Time Allocation (45 min) |
|------|-----------|--------------------------|
| **R** — Requirements | Clarify functional + non-functional; explicitly call out what is OUT of scope | 3–5 min |
| **E** — Estimation | QPS, storage, bandwidth; size each tier | 3–5 min |
| **S** — Storage & Data Model | Entity model, DB type choice, schema sketch | 3–5 min |
| **H** — High-Level Design | Component diagram; data flow; happy path | 8–10 min |
| **A** — APIs | REST/gRPC contracts for core operations | 3–5 min |
| **D** — Deep Dives | Pick 2–3 hard problems and go deep | 10–15 min |
| **E** — Evaluate | Bottlenecks, failure modes, monitoring | 3–5 min |
| **D** — Distinctive | One non-obvious design insight that shows PE-level thinking | 1–2 min |

### What Interviewers Score

| Dimension | What Good Looks Like |
|-----------|---------------------|
| **Problem clarification** | Asks the right 3–5 questions; doesn't over-clarify forever |
| **Communication** | Explains thinking before drawing; no silent coding |
| **Technical depth** | Can go deep on storage engine, consensus, or network protocol when asked |
| **Trade-off reasoning** | Names both sides of every decision; doesn't just pick "the best" answer |
| **Execution** | Finishes with time to spare; doesn't rabbit-hole on unimportant details |
| **Scope judgment** | Knows what to include and what to defer |

### Anti-Patterns to Avoid
- **Jumping to solutions**: Drawing boxes before clarifying requirements signals poor habits
- **Over-specifying early**: Debating PostgreSQL vs MySQL before the data model is clear wastes time
- **Ignoring non-functional requirements**: A design without SLAs, latency targets, and durability guarantees is incomplete
- **No estimation**: You cannot defend design decisions without capacity numbers
- **Single-mode thinking**: Only describing the happy path; never mentioning failure modes

---

## Chapter 4 — Design a Rate Limiter

### Problem Statement
Design a rate limiting service that throttles API requests based on configurable rules (e.g., 5 requests per second per user, 100 requests per hour per IP). The limiter should be placed at the API gateway layer.

### Requirements

**Functional**:
- Limit requests at multiple granularities: per user, per IP, per endpoint, per global service
- Return HTTP 429 with `Retry-After` header when rate limit exceeded
- Rules are configurable without code deployment (stored in a rules service)
- Support multiple throttling strategies: hard reject, soft throttle (queue), gradual degradation

**Non-Functional**:
- Latency overhead: < 1 ms added to every request
- Accuracy: allow at most X requests per window — no more than 0.1% error acceptable
- Availability: rate limiter failure should fail open (don't block traffic) or fail closed depending on policy
- Distributed: consistent decisions across all API gateway nodes

**Out of Scope**: IP allowlisting, DDoS protection at L3/L4 (handled by WAF/CDN), per-endpoint billing

### Capacity Estimation
```
100M DAU; avg 10 API calls/user/day
Write QPS to rate limiter: 100M × 10 / 86,400 ≈ 12,000 req/s
Peak: ~25,000 req/s

Each rate limit check: read counter + conditional increment in Redis
Redis latency: ~0.5 ms round-trip
Overhead per request: < 1 ms ✓
```

### Algorithm Comparison

| Algorithm | How It Works | Pros | Cons | Best For |
|-----------|-------------|------|------|---------|
| **Token Bucket** | Bucket holds N tokens; refilled at rate R/s; each request consumes 1 token | Smooth bursting allowed up to bucket size; memory efficient (2 vars per user) | Clock drift issues in distributed; burst at boundary | General-purpose; Stripe, AWS use this |
| **Leaky Bucket** | Requests enter a fixed-size queue; processed at fixed rate | Smooths out traffic spikes; predictable output rate | Stale requests at queue head block new ones; not good for bursty legitimate traffic | Outgoing request shaping |
| **Fixed Window Counter** | Divide time into windows (e.g., 1 min); count requests per window | Simple; memory-efficient | Boundary problem: 2× limit in 2× window boundary crossing | Simple use cases with tolerant SLAs |
| **Sliding Window Log** | Store timestamp of every request; count in rolling window | Exact; no boundary problem | High memory: O(max_requests) timestamps per user | High-accuracy; low-volume use cases |
| **Sliding Window Counter** | Combine fixed window + weighted overlap from previous window | Near-exact with O(1) memory per user | Small approximation error (~0.003%) | Best production choice: Cloudflare uses this |

**Principal recommendation**: **Token bucket for ingress throttling** (allows bursting, low memory); **sliding window counter for billing-accurate enforcement** (nearly exact, O(1) memory).

### High-Level Design

```
Client → API Gateway (rate limiter middleware) → Backend Services
                      ↓
               Redis Cluster (counters)
                      ↓
               Rules Service (rules cache; configurable TTL)
```

**Data flow**:
1. Request arrives at any gateway node
2. Gateway reads rules from local in-memory cache (refreshed every 60s from Rules Service)
3. Gateway atomically increments counter in Redis using Lua script (INCR + EXPIRE)
4. If counter > limit → return 429 with `Retry-After: X`
5. Else → forward to backend

### Deep Dive — Distributed Consistency Problem

**Problem**: Two gateway nodes read counter simultaneously (both see 99/100), both allow the request, counter becomes 101/100 — limit violated.

**Solutions**:

| Approach | Mechanism | Trade-off |
|---------|-----------|-----------|
| **Lua atomic script** | Single Redis `INCR + CHECK` in one atomic op | Eliminates race; Redis is SPOF if single node |
| **Redis cluster + consistent hashing** | Route `user_id` to specific Redis shard; all counter ops for a user go to same node | Eliminates cross-node race; shard failure = partial outage |
| **Redis Lua + SET NX** | Atomic compare-and-set for window initialization | Handles initialization race |
| **Sticky routing at LB** | LB routes user to same gateway node | Eliminates Redis need for per-user state; breaks if gateway scales |

**Best approach**: Redis cluster with consistent hashing on `user_id`; Lua script for atomicity.

**Script** (sliding window counter):
```lua
local key = KEYS[1]
local window = tonumber(ARGV[1])
local limit = tonumber(ARGV[2])
local now = tonumber(ARGV[3])
local prev_window_key = KEYS[2]

local curr = tonumber(redis.call('GET', key) or 0)
local prev = tonumber(redis.call('GET', prev_window_key) or 0)
local elapsed_ratio = (now % window) / window
local weighted = prev * (1 - elapsed_ratio) + curr

if weighted >= limit then
  return 0
end
redis.call('INCR', key)
redis.call('EXPIRE', key, window * 2)
return 1
```

### Failure Modes

| Failure | Behavior | Mitigation |
|---------|---------|-----------|
| Redis shard down | Rate limiter blind for that user partition | Fail open (allow requests) or fail closed (block); circuit breaker around Redis calls |
| Rules Service unreachable | Use cached rules; log staleness | TTL on cache; alert if rules > 5 min stale |
| Network partition between gateway and Redis | Increased latency; possible timeout | Timeout < 2ms; fail open on timeout |
| Clock drift across nodes | Incorrect window boundaries | Use Redis server time (`TIME` command), not client time |

### Principal Engineer Extensions
- **Multi-tier rate limiting**: API gateway (coarse) + service-level (fine-grained) + per-resource (DB writes)
- **Rate limit headers**: Always return `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset` — lets clients adapt
- **Adaptive rate limiting**: Reduce limits dynamically when backend latency increases (backpressure-aware limiting)
- **Rate limit exemptions**: Internal service-to-service calls should bypass user limits; use separate token with elevated quota

---

## Chapter 5 — Design Consistent Hashing

### Problem Statement
Design a hashing scheme that distributes keys across N nodes such that when nodes are added or removed, only K/N keys are remapped (where K = total keys, N = total nodes). Naive modulo hashing remaps all keys on any node change.

### Why Consistent Hashing Matters
- **Cache invalidation at scale**: Adding a cache node with naive modulo remaps ~50% of cache keys → thundering herd on DB
- **Partitioned databases**: Resharding Cassandra, DynamoDB, Redis Cluster without full data migration
- **Load balancing**: Even distribution of requests across a variable pool of servers

### The Algorithm

**Step 1 — Hash ring**: Map hash space [0, 2³²) as a circle  
**Step 2 — Node placement**: Hash each server (by IP or name) to a position on the ring  
**Step 3 — Key routing**: Hash key to a position; walk clockwise to find the first server  
**Step 4 — Node removal**: Keys previously served by the removed node go to the next clockwise server — only those keys are remapped  
**Step 5 — Node addition**: New server takes over keys between itself and the previous server — only those keys move

### Virtual Nodes (vnodes)

**Problem with basic ring**: If servers hash to adjacent positions, one server gets most of the load. Heterogeneous hardware means different servers should carry different loads.

**Solution**: Each physical server maps to V virtual nodes on the ring (V = 100–200 typical). The virtual nodes are distributed pseudo-randomly across the ring.

**Benefits**:
- More uniform key distribution (each server owns ~1/N of keys)
- Weighted capacity: a more powerful server gets 2V virtual nodes vs 1V for weaker servers
- Better failure handling: failing node's load distributes across all remaining servers (not just one neighbor)

**Trade-off**: More memory for routing table (O(N × V) entries vs O(N)). At 1,000 nodes × 200 vnodes = 200,000 entries — negligible.

### Real-World Usage

| System | How They Use It |
|--------|----------------|
| Cassandra | Partition tokens; configurable vnode count (default 256) |
| DynamoDB | Consistent hashing with preference lists; coordinator node selection |
| Akamai CDN | Origin server selection |
| Redis Cluster | 16,384 hash slots distributed across nodes |
| Chord DHT | Foundational use in peer-to-peer systems |

### Implementation Sketch

```python
import hashlib
import bisect

class ConsistentHashRing:
    def __init__(self, virtual_nodes=150):
        self.ring = {}       # hash → server
        self.sorted_keys = []  # sorted list of hashes
        self.virtual_nodes = virtual_nodes

    def add_server(self, server):
        for i in range(self.virtual_nodes):
            key = self._hash(f"{server}#{i}")
            self.ring[key] = server
            bisect.insort(self.sorted_keys, key)

    def remove_server(self, server):
        for i in range(self.virtual_nodes):
            key = self._hash(f"{server}#{i}")
            self.ring.pop(key)
            self.sorted_keys.remove(key)

    def get_server(self, key):
        h = self._hash(key)
        idx = bisect.bisect(self.sorted_keys, h) % len(self.sorted_keys)
        return self.ring[self.sorted_keys[idx]]

    def _hash(self, key):
        return int(hashlib.md5(key.encode()).hexdigest(), 16)
```

### Principal Engineer Extensions
- **Replication**: In Cassandra, a key is replicated to the next R clockwise nodes — this is the "preference list"
- **Bounded loads**: A server at capacity should be skipped (consistent hashing with bounded loads — Google paper 2017)
- **Jump consistent hashing**: O(ln N) time with no memory for the ring — used in Google Guice when N changes infrequently

---

## Chapter 6 — Design a Key-Value Store

### Problem Statement
Design a distributed key-value store (like DynamoDB, Cassandra, or Redis) supporting `get(key)` and `put(key, value)` operations with configurable consistency.

### Requirements

**Functional**:
- `put(key, value)` — store or update a key-value pair
- `get(key)` → value — retrieve value by key; return error if key not found
- Keys and values are opaque byte arrays (up to 10 KB)
- Configurable consistency: tunable quorum (one, quorum, all)

**Non-Functional**:
- High availability: 99.99% uptime
- Low latency: p99 < 10 ms for reads and writes
- Eventual consistency (strong consistency optional)
- Scale: handle 10 TB of data across a cluster

### Core Design Components

| Component | Responsibility |
|-----------|---------------|
| **Consistent hash ring** | Route requests to correct nodes; handle node membership changes |
| **Replication** | Each key replicated to N nodes (typically 3) for durability |
| **Coordinator node** | Any node receiving a request acts as coordinator; no single leader |
| **Quorum reads/writes** | W + R > N guarantees at least one node has latest version |
| **Vector clocks** | Track causality; detect concurrent writes; enable conflict resolution |
| **Gossip protocol** | Nodes propagate membership and heartbeat state to peers (not a central coordinator) |
| **Anti-entropy (Merkle trees)** | Background sync to detect and repair data divergence between replicas |
| **Hinted handoff** | If target node is down, a neighboring node stores the write temporarily and hands it off on recovery |
| **Read repair** | During reads, if replicas return different versions, coordinator writes the latest version back to stale replicas |

### Write Path
```
1. Client sends put(key, value) to any node (coordinator)
2. Coordinator hashes key → finds N nodes on ring (preference list)
3. Coordinator writes to W nodes in parallel
4. Each node:
   a. Appends to Write-Ahead Log (WAL) for durability
   b. Writes to in-memory MemTable
   c. Returns ACK
5. When W ACKs received → respond success to client
6. Background: MemTable flushes to SSTable on disk; compaction merges SSTables
```

### Read Path
```
1. Client sends get(key) to coordinator
2. Coordinator queries R nodes in parallel
3. Nodes return value + vector clock
4. If all values identical → return to client
5. If conflict (concurrent writes → different vector clocks):
   a. Return all conflicting values to client (like Dynamo)
   b. Client resolves (shopping cart merge) or last-write-wins
6. Read repair: coordinator writes winning version back to stale nodes
```

### Consistency Trade-offs (Quorum)

With N=3 replicas:

| Configuration | W | R | Guarantee |
|--------------|---|---|-----------|
| Strong consistency | 2 | 2 | W+R > N; always read latest write |
| Eventual consistency | 1 | 1 | Fastest; may read stale data |
| Write-optimized | 1 | 3 | Fast writes; slow reads |
| Read-optimized | 3 | 1 | Fast reads; slow writes; rare (write blocks until all replicas ACK) |

### Vector Clocks — Conflict Detection

Vector clock format: `{nodeA: 2, nodeB: 1}` means "version written at nodeA after 2 writes, nodeB after 1 write"

- Version A dominates B if all of A's counters ≥ B's counters
- Versions are concurrent (conflict) if neither dominates → client must resolve

**Conflict resolution strategies**:
- **Last-write-wins (LWW)**: Use wall clock or Lamport timestamp — simple but loses data
- **Client-side merge**: Return all conflicting versions to client (Dynamo's approach for shopping carts)
- **CRDT**: Data structure designed to merge automatically without conflicts (counters, sets, maps)

### Failure Modes

| Failure | Detection | Mitigation |
|---------|-----------|-----------|
| Node crash | Gossip heartbeat timeout | Hinted handoff; replication ensures data available on other nodes |
| Network partition | Unable to reach quorum | Sloppy quorum: write to any W available nodes; repair on recovery |
| Disk failure | Checksum on SSTable read | Replicate; Merkle tree anti-entropy detects divergence |
| Cascading failures | All replicas for a key fail | Hinted handoff to non-preference-list nodes as last resort |

### Principal Engineer Extensions
- **Sloppy quorum**: In a partition, write to W nodes not on the original preference list ("sloppy") to maintain availability; hand off on recovery
- **Merkle tree anti-entropy**: Compute hash of subtrees; exchange root hashes with peers; diverge only on differing subtrees — reduces anti-entropy bandwidth
- **Bloom filters**: Before reading from SSTables, check bloom filter to avoid disk I/O for missing keys
- **Tombstones**: Deletes are writes (tombstone marker) to ensure the deletion propagates to all replicas before garbage collection

---

## Chapter 7 — Design a Unique ID Generator in Distributed Systems

### Problem Statement
Design a system that generates globally unique, sortable IDs for distributed systems at high scale, without a single central coordinator.

### Requirements
- IDs must be globally unique across all nodes and all time
- IDs should be sortable by time (newer IDs > older IDs numerically)
- IDs fit in 64 bits (to store in `BIGINT`)
- System can generate 10,000 IDs/ms
- IDs generated without coordination between nodes

### Approaches Comparison

| Approach | Uniqueness | Sortable | Coordination Required | Pros | Cons |
|---------|-----------|---------|----------------------|------|------|
| **UUID v4** | Yes (128-bit) | No | None | Trivial to implement | 128-bit; not sortable; index fragmentation |
| **DB auto-increment** | Yes | Yes | Yes (central DB) | Simple | SPOF; write bottleneck |
| **DB auto-increment (multi-server)** | Yes (with step config) | Approx | Minimal | No SPOF | ID gaps; hard to add servers |
| **Redis INCR** | Yes | Yes | Redis node | Fast; simple | Redis SPOF |
| ⭐ **Snowflake (Twitter)** | Yes | Yes | None (clock-based) | No coordination; 64-bit; time-sortable | Clock drift; machine ID provisioning |
| **ULIDs** | Yes | Yes | None | 128-bit UUID-compatible; base32; sortable | Not 64-bit |

### Snowflake ID — Deep Dive

**Bit layout** (64 bits total):

```
|  Sign bit  |   Timestamp (ms)   |  Datacenter ID  |  Machine ID  |  Sequence  |
|  1 bit = 0 |  41 bits           |  5 bits         |  5 bits      |  12 bits   |
```

- **1 bit**: Always 0 (reserved for sign; makes all IDs positive)
- **41 bits timestamp**: Milliseconds since custom epoch (e.g., 2010-11-04). 2⁴¹ ms ≈ 69 years of unique IDs before overflow
- **5 bits datacenter ID**: 2⁵ = 32 datacenters
- **5 bits machine ID**: 2⁵ = 32 machines per datacenter
- **12 bits sequence**: 2¹² = 4,096 unique IDs per millisecond per machine

**Maximum throughput per machine**: 4,096 IDs/ms = 4.096M IDs/second  
**Maximum throughput (32 DCs × 32 machines)**: 1,024 machines × 4,096 IDs/ms = 4 billion IDs/second cluster-wide

### Clock Drift Problem

**Problem**: If a machine's clock moves backward (NTP correction), it might generate the same sequence number for the same millisecond → duplicate IDs.

**Mitigations**:
1. **Refuse to generate IDs until clock catches up**: Block generation until `current_time >= last_timestamp`; alert if wait > 1 ms
2. **Use NTP with `ntpd`** configured to never step backward (slew-only mode)
3. **Server-side epoch adjustment**: Store last-used timestamp; refuse backward timestamps
4. **Hybrid Logical Clocks (HLC)**: Track max of physical time and logical clock — more robust to NTP drift

### Machine ID Provisioning
- ZooKeeper assigns machine IDs at startup → registered in `/workers/machine_id`
- Simple database row per machine; mark as active/inactive
- Environment variable injection at container start (for Kubernetes deployments)

### Principal Engineer Extensions
- **Customizing bit layout**: More sequence bits if one machine generates more IDs; more timestamp bits for longer epoch; fewer machine bits if you have fewer nodes
- **Sonyflake**: Japanese variant — 39-bit time (10ms granularity), 8-bit sequence, 16-bit machine ID. Works for smaller clusters with longer generation windows
- **KSUID**: 160-bit sortable UID — 32-bit seconds + 128-bit random payload; human-readable base62

---

## Chapter 8 — Design a URL Shortener

### Problem Statement
Design a URL shortening service like bit.ly that takes a long URL and returns a short alias. When the short URL is visited, it redirects to the original URL.

### Requirements

**Functional**:
- `POST /shorten` → `{ "short_url": "https://short.ly/abc123" }`
- `GET /{short_code}` → HTTP 301 or 302 redirect to original URL
- Custom short codes optional (e.g., `short.ly/my-brand`)
- Expiration: links can be set to expire after a date

**Non-Functional**:
- 100:1 read-to-write ratio (redirects >> new links created)
- Write QPS: 100M URLs/day → 1,157 writes/s; peak ≈ 2,500/s
- Read QPS: 10B redirects/day → 115,000 reads/s; peak ≈ 230,000/s
- Availability: 99.99% (downtime = broken links everywhere)
- Short code: 7 characters from `[a-zA-Z0-9]` (62⁷ ≈ 3.5 trillion unique codes)
- Storage: 1 URL ≈ 500 bytes → 100M/day × 365 × 5 × 500 bytes ≈ 90 TB over 5 years

### API Design

```
POST /api/v1/urls
Body: { "long_url": "https://...", "custom_code": "optional", "expiry": "2025-12-31" }
Response: { "short_code": "abc1234", "short_url": "https://short.ly/abc1234" }

GET /{short_code}
Response: 301 (permanent) or 302 (temporary) redirect to long_url
```

**301 vs 302**:
- **301 Permanent**: Browser caches redirect → no server hit on repeat visit. Saves server load but breaks analytics (can't count repeat visits from same client)
- **302 Temporary**: Every visit hits the server → accurate click counting. Higher server load

**Principal choice**: Use 302 for analytics-sensitive links; 301 for throughput-optimized links. Return `Cache-Control: max-age=86400` on 302 for a middle-ground.

### Short Code Generation — Hash vs ID-Based

**Approach 1 — MD5 Hash**: Hash long URL → take first 7 chars
- Problem: collisions (different URLs → same 7-char prefix); handling collision is complex
- Problem: same URL by different users gets same short code — violates per-user customization

**Approach 2 — Base62 Encode a Distributed ID** (Book's preferred approach):
1. Generate globally unique 64-bit ID using Snowflake
2. Base62-encode the ID → 7-character short code
3. Store `(short_code, long_url, created_at, expires_at, user_id)` in DB

**Why Base62**: 62 chars (`a-z`, `A-Z`, `0-9`) — URL-safe without encoding. 62⁷ = 3.5T codes.

### Data Model

```sql
CREATE TABLE url_mappings (
    short_code    VARCHAR(10) PRIMARY KEY,
    long_url      TEXT NOT NULL,
    user_id       BIGINT,
    created_at    TIMESTAMP DEFAULT NOW(),
    expires_at    TIMESTAMP,
    click_count   BIGINT DEFAULT 0  -- or tracked async
);

CREATE INDEX idx_long_url ON url_mappings(MD5(long_url));  -- for deduplication
```

### High-Level Architecture

```
Write Path:
Client → LB → URL Shortener Service → ID Generator (Snowflake) → DB (primary)
                                    → Cache invalidation (if custom code)

Read Path:
Client → LB → URL Shortener Service → Redis Cache (short_code → long_url) → 302 redirect
                           ↓ (cache miss)
                        DB (read replica) → populate cache → redirect
```

**Cache strategy**: Cache-aside; TTL = 24 hours; LRU eviction; 80% of traffic goes to 20% of links (power law)

### Failure Modes

| Failure | Impact | Mitigation |
|---------|--------|-----------|
| ID generator down | Cannot create new short URLs | Multiple Snowflake instances; queue writes |
| DB primary down | Cannot read uncached links; no new writes | Read replicas for reads; failover primary within 30s |
| Cache down | Every redirect hits DB | DB read replicas handle load; cache auto-reconnect |
| Link expiry not cleaned up | Stale links redirect successfully | Background TTL cleanup job; check expiry on read |

### Principal Engineer Extensions
- **Analytics pipeline**: Click events → Kafka → Flink aggregation → Analytics DB (ClickHouse) → Dashboard
- **Bloom filter for deduplication**: Before DB write, check if long URL already exists in bloom filter — avoid DB lookup on hot paths
- **URL validation**: Validate long URLs before storing (HTTP HEAD check); block malicious/phishing URLs via reputation API
- **Geo-aware shortening**: Regional routing — `short.ly/abc` → different targets in US vs EU for marketing campaigns

---

## Chapter 9 — Design a Web Crawler

### Problem Statement
Design a scalable web crawler that downloads billions of web pages for a search engine index, starting from a seed set of URLs, following links, and respecting crawl policies.

### Requirements

**Functional**:
- Crawl 1 billion pages in 1 month
- Store raw HTML content and extracted URLs
- Respect `robots.txt` and crawl delays
- De-duplicate: don't re-crawl same URL within a crawl cycle
- Handle redirects (301/302) and error responses (retry 5xx; skip 404)

**Non-Functional**:
- Throughput: 1B pages/month ÷ 2.6M seconds/month ≈ 400 pages/second
- Storage: average page 500 KB → 400 × 500 KB × 2.6M s = 520 TB/month
- DNS: 400 DNS lookups/s (cache aggressively; DNS TTL respected)
- Politeness: max 1 request per domain per 10 seconds to avoid overloading origin servers

### Core Components

| Component | Responsibility |
|-----------|---------------|
| **Seed URL Set** | Initial set of authoritative URLs to begin crawl |
| **URL Frontier** | Priority queue of URLs to crawl; respects politeness delays; persisted to disk |
| **DNS Resolver** | Cached DNS lookups; avoid hitting upstream DNS at full crawl rate |
| **HTML Downloader** | Fetches pages; handles timeouts, redirects, auth |
| **Content Parser** | Extracts links from HTML; normalizes URLs |
| **URL Deduplicator** | Bloom filter + persistent hash set to detect previously visited URLs |
| **Content Deduplicator** | SimHash to detect near-duplicate pages (mirrors, scrapers) |
| **Link Extractor** | Canonical URL normalization; resolve relative → absolute; filter non-HTML |
| **Content Store** | S3 / GCS for raw HTML; DynamoDB/Cassandra for URL metadata |

### URL Frontier Design

**Problem**: Simple FIFO queue violates politeness (many URLs from same domain) and doesn't prioritize important pages.

**Solution — Two-tier frontier**:

```
URLs to crawl
      ↓
Front Queue (Priority) → Selects by page rank / importance score
      ↓
Back Queue (Politeness) → One queue per domain; enforces crawl delay
      ↓
Worker threads → Each worker always picks from a domain queue that is ready
```

**Priority function**: PageRank estimate + incoming link count + freshness signal + update frequency  
**Politeness enforcement**: Worker checks `last_crawl[domain]`; waits if within crawl delay window  
**Distributed frontier**: Kafka topic per priority level; URL → topic by `hash(hostname) % partitions` ensures one worker owns each domain

### Deduplication

**URL deduplication**:
1. **Bloom filter** (fast, probabilistic, in-memory): Check if URL seen before → false positives acceptable (skip 0.1% of new URLs)
2. **Persistent hash set** (exact): Cassandra/Redis; bloom filter false positives re-checked here
3. **URL normalization**: Lowercase scheme+host, remove default port, sort query params, remove fragments

**Content deduplication (SimHash)**:
- Hash each word in page → XOR into 64-bit fingerprint
- Hamming distance < threshold → near-duplicate
- Store fingerprints in LSH (Locality-Sensitive Hashing) index for fast approximate matching

### Handling Dynamic Content
- JavaScript-rendered pages: Use headless Chromium (Puppeteer); reserve for high-priority domains only (cost: 10× more CPU per page)
- Shadow DOM / SPAs: May miss content; acceptable for search engines (fallback to pre-rendered meta tags)

### Failure Modes

| Failure | Impact | Mitigation |
|---------|--------|-----------|
| Worker crashes mid-crawl | In-flight URLs lost | URL frontier is a persistent queue (Kafka); at-least-once delivery |
| Crawler trap (infinite URLs) | Fills frontier with garbage | Max URL depth limit; detect URL patterns (incrementing query params) |
| Spider trap (session IDs in URLs) | Same page crawled millions of times | Normalize URLs; limit unique URLs per domain |
| `robots.txt` fetch fails | Unknown crawl restrictions | Fail safe: respect conservative defaults until fetched |

### Principal Engineer Extensions
- **Distributed crawl coordination**: Use ZooKeeper to assign URL ranges to workers; each worker claims a range
- **Incremental crawling**: Track `Last-Modified` + `ETag` headers; use HTTP conditional GET (`If-Modified-Since`) to avoid re-downloading unchanged pages
- **Adaptive crawl rate**: Monitor origin server response latency; back off automatically if latency increases (politeness ++)
- **Freshness-aware re-crawling**: Pages that change frequently (news sites) get shorter recrawl interval; static pages recrawled less often

---

## Chapter 10 — Design a Notification System

### Problem Statement
Design a notification system that sends push notifications (iOS/Android), email, and SMS to users based on events generated by application services.

### Requirements

**Functional**:
- Deliver push notifications (iOS APNs, Android FCM), email (SendGrid/SES), and SMS (Twilio)
- Notification types: marketing, transactional (order update), alerts (fraud), social (likes/comments)
- User preference management: per-channel, per-notification-type opt-out
- Retry logic for failed deliveries; deduplication (don't send same notification twice)

**Non-Functional**:
- Scale: 10M mobile push, 1M SMS, 5M email per day
- Latency: transactional notifications < 1 second end-to-end; marketing batch < 30 minutes
- At-least-once delivery with idempotency
- Observability: delivery status tracking per notification

### Capacity Estimation
```
Daily: 16M total notifications = 16M/86,400 ≈ 185 notifications/second average
Peak (marketing blast to all users): 10M push in 30 min = 5,556/s for push
Email: 5M/day ÷ 86,400 ≈ 58/s average

Third-party API rate limits:
  APNs: ~20,000/s per connection (with HTTP/2 multiplexing)
  FCM: ~500/s per project (adjustable via Firebase support)
  SendGrid: varies by plan (500–10,000/s on paid plans)
```

### Architecture

```
Producers (Order Service, Social Service, etc.)
      ↓
Notification Service API → User Preferences DB (check opt-out)
      ↓
Kafka (per-channel topics: push_topic, email_topic, sms_topic)
      ↓
Workers: Push Worker | Email Worker | SMS Worker
      ↓        ↓            ↓
    APNs/FCM  SendGrid/SES  Twilio
      ↓
Delivery Status DB (notification_id, user_id, channel, status, timestamp)
      ↓
Retry Queue (DLQ for failed messages; exponential backoff)
```

### Critical Component — User Device Registry

Store device tokens that expire or become invalid when users uninstall apps or get new phones.

```sql
CREATE TABLE device_tokens (
    user_id    BIGINT,
    device_id  VARCHAR(64),
    platform   ENUM('ios', 'android'),
    token      VARCHAR(256),    -- APNs/FCM device token
    updated_at TIMESTAMP,
    is_active  BOOLEAN DEFAULT TRUE,
    PRIMARY KEY (user_id, device_id)
);
```

**Token invalidation**: APNs/FCM returns `InvalidToken` error → mark token inactive immediately

### Deduplication
- Generate `notification_id = hash(user_id, event_id, channel, notification_type)`
- Check Redis SET before sending: `SET NX notification_id EX 86400`
- If key exists → skip (already sent within 24h)
- Idempotency window configurable per notification type

### Retry Strategy

| Failure | Retry Policy |
|---------|-------------|
| APNs timeout | Exponential backoff: 1s, 2s, 4s, 8s, 16s; max 5 retries |
| FCM rate limit | Respect `Retry-After` header; honor Firebase backoff recommendation |
| Email bounce | Hard bounce → mark email invalid; remove from active list |
| SMS failure | Retry × 3; fallback to alternate number if available |

### Priority Queue for Transactional vs Marketing

- Separate Kafka topics: `notification.transactional` (high priority) vs `notification.marketing` (low priority)
- Workers consume from transactional first; process marketing only when transactional queue is empty
- Separate SLA monitoring per topic

### Failure Modes

| Failure | Impact | Mitigation |
|---------|--------|-----------|
| Kafka partition leader down | Brief message delay | Kafka automatic leader re-election; < 10s typically |
| APNs rate limit | Push notifications delayed | Exponential backoff; batch push where possible |
| Worker crash | In-flight notifications potentially lost | Kafka consumer group offset commit only after successful delivery |
| Preference DB down | Send all notifications (privacy risk) | Cache preferences locally; fail closed = don't send |

### Principal Engineer Extensions
- **Throttling per user**: Cap notifications per user per hour (notification fatigue); Redis counter per user
- **Notification bundling**: Aggregate 5 likes → "John and 4 others liked your post" to reduce notification count
- **Delivery receipt**: APNs supports silent push to confirm app is still installed; use for token validity
- **Analytics**: Funnel: sent → delivered → opened → clicked → converted. Track in ClickHouse; power A/B testing of notification copy

---

## Chapter 11 — Design a News Feed System

### Problem Statement
Design a social news feed (like Facebook's News Feed or Twitter's Home Timeline) that aggregates posts from people a user follows and shows them in ranked order.

### Requirements

**Functional**:
- Users can create posts (text, images, links)
- Home feed shows posts from followees, ranked by relevance/recency
- Support follow/unfollow; friend relationships (bidirectional) and follower (unidirectional)
- Pagination: cursor-based (not page-number based)

**Non-Functional**:
- 300M DAU; each user views feed 5 times/day = 1.5B feed reads/day ≈ 17,000 reads/s; peak 50,000/s
- Post creation: 5M posts/day ≈ 58 writes/s; peak 150/s
- Feed load latency: p99 < 200 ms
- Feed data consistency: eventual (seeing a post 1–2 seconds late is acceptable)

### The Core Challenge — Fan-Out

When user A posts, how do 500 followers see it on their next feed load?

**Fan-out on write (push model)**:
- On post creation, immediately write post_id to each follower's timeline cache
- Feed read is instant (pre-computed)
- Problem: celebrity with 50M followers → 50M write ops on every post (fan-out storm)

**Fan-out on read (pull model)**:
- On feed load, query posts from all followees; merge; rank
- Problem: 500 followees × DB query → 500 serial queries (or expensive JOIN); high read latency

**Hybrid (what Facebook and Twitter both use)**:
- **Regular users (< 10K followers)**: Fan-out on write — fast feed reads
- **Celebrities (> 10K followers)**: Fan-out on read — avoid write amplification
- Feed read merges pre-computed feed (from write fan-out) with live-fetched celebrity posts

### Data Model

```sql
-- Posts
CREATE TABLE posts (
    post_id    BIGINT PRIMARY KEY,  -- Snowflake ID (time-sortable)
    user_id    BIGINT NOT NULL,
    content    TEXT,
    media_urls JSON,
    created_at TIMESTAMP,
    INDEX idx_user_created (user_id, created_at DESC)
);

-- Social graph
CREATE TABLE follows (
    follower_id BIGINT,
    followee_id BIGINT,
    created_at  TIMESTAMP,
    PRIMARY KEY (follower_id, followee_id)
);

-- Timeline cache (Redis sorted set per user)
-- Key: timeline:{user_id}
-- Value: set of post_ids, scored by post creation timestamp
```

### Feed Generation Architecture

```
Write Path (post creation):
User → Post Service → DB write → Fanout Service → Worker Pool
                                     ↓
                          Fetch follower list from Graph DB
                                     ↓
                          Push post_id to each follower's
                          Redis sorted set (timeline cache)
                          (only for regular users)

Read Path (feed load):
User → Feed Service → Redis: ZREVRANGE timeline:{uid} 0 20
                    + Fetch celebrity posts from Post DB (live)
                    → Merge + deduplicate
                    → Ranking Service (ML scorer)
                    → Hydrate posts (fetch content from Post DB)
                    → Return to client
```

### Ranking Service

For simplicity (book level):
- Recency-based ranking: score = `post_timestamp`
- At PE level: ML ranking model with features: recency, relationship strength (interactions with poster), content quality signals, engagement velocity (likes/comments in first 5 minutes), media presence

**Online vs offline ranking**:
- Light features (recency, follows) → computed online at request time
- Heavy features (engagement velocity, ML model score) → pre-computed by background job; stored in feed feature cache

### Cursor-Based Pagination

```
GET /api/v1/feed?cursor=<encoded_timestamp>&limit=20

Response:
{
  "posts": [...],
  "next_cursor": "<encoded_timestamp_of_last_post>"
}
```

Cursor encodes the last seen `post_id` or timestamp. More stable than offset pagination — inserting new posts doesn't shift pages.

### Principal Engineer Extensions
- **Feed backfill on follow**: When user A follows B, should A immediately see B's historical posts? If yes → write B's last 100 posts to A's cache
- **Tombstoning deleted posts**: If post is deleted after appearing in feed caches, scrub post_id from all caches asynchronously; show "post deleted" placeholder on client
- **Read path optimization**: Redis pipeline for ZREVRANGE + batch HGET for post hydration; reduces round-trips from O(N) to O(1)

---

## Chapter 12 — Design a Chat System

### Problem Statement
Design a real-time chat system (like WhatsApp or Slack) supporting 1-on-1 and group messaging, online presence, and message history.

### Requirements

**Functional**:
- 1-on-1 and group chat (up to 500 members per group)
- Message delivery: sent → delivered → read receipts
- Message history: persistent; searchable
- Online presence: show who is online
- Push notifications for offline users

**Non-Functional**:
- 50M DAU; each sends 40 messages/day → 2B messages/day ≈ 23,000 msg/s; peak 100,000/s
- Latency: message delivery < 100 ms end-to-end
- Message durability: no message loss; at-least-once delivery
- History: messages retained indefinitely (or configurable per workspace)

### Connection Protocol Choice

| Protocol | How It Works | Pros | Cons |
|---------|-------------|------|------|
| HTTP polling | Client polls every N seconds | Simple; works everywhere | High latency; wasteful bandwidth |
| HTTP long polling | Client holds connection open until message arrives | Better latency; server pushes | Server must maintain pending responses; no server-push |
| ⭐ **WebSocket** | Full-duplex persistent TCP connection | Lowest latency; true bidirectional; server push | Connection management at scale; reconnect logic needed |
| SSE (Server-Sent Events) | Server pushes to client over HTTP | Simple; works through proxies | Client→server requires separate HTTP request; unidirectional |

**Choice**: WebSocket for chat clients; SSE acceptable for notification-only use cases.

### Architecture

```
Client ↔ WebSocket Gateway (Chat Server)
              ↓
         Presence Service → Redis (user_id → last_seen, connected_server)
              ↓
         Message Service → Kafka (message_stream) → Message DB (Cassandra)
              ↓
         Notification Service (for offline users) → APNs/FCM
```

### Message Storage — Cassandra Design

Cassandra is ideal for chat: high write throughput, time-range queries by channel, easy horizontal scaling.

```cql
CREATE TABLE messages (
    channel_id    UUID,            -- conversation or group ID
    message_id    BIGINT,          -- Snowflake ID (time-sortable)
    sender_id     BIGINT,
    content       TEXT,
    media_url     TEXT,
    created_at    TIMESTAMP,
    PRIMARY KEY ((channel_id), message_id)  -- partition by channel; cluster by time
) WITH CLUSTERING ORDER BY (message_id DESC);
```

**Read pattern**: `SELECT * FROM messages WHERE channel_id = ? AND message_id < ? LIMIT 50` — efficient range scan within partition

### Online Presence

**Problem**: 50M DAU; each user's presence state changes frequently. How to track and broadcast who is online?

**Solution**:
- User connects via WebSocket → WebSocket server updates Redis: `SET presence:{user_id} {server_id, timestamp} EX 60`
- User sends heartbeat every 30s → refresh TTL
- Key expires after 60s without heartbeat → user considered offline
- Querying friend presence: fetch presence keys for all friends → 500 Redis GET ops (use pipeline)
- Presence change events → publish to pub/sub channel → friends' WebSocket servers subscribe and push updates

**Scale**: 50M online users × 64 bytes/entry = 3.2 GB in Redis — trivially fits in memory

### Message Delivery Guarantees

**Sequence**:
1. Client A sends message to chat server
2. Chat server assigns Snowflake message_id; writes to Kafka
3. Message consumer writes to Cassandra
4. Chat server sends ACK to sender with message_id
5. Chat server pushes message to recipient (if online via WebSocket)
6. Recipient sends read receipt with message_id
7. If recipient offline → push notification service reads from Kafka and calls APNs/FCM

**At-least-once**: Kafka consumer commits offset only after Cassandra write confirmed  
**Client deduplication**: Client ignores messages with already-seen message_id  
**Offline message delivery**: On reconnect, client sends `last_seen_message_id` → server fetches and delivers missed messages from Cassandra

### Group Chat

- Group size ≤ 500 → fanout acceptable at the application layer
- Message written once to Cassandra with `group_id` as partition key
- Each group member's WebSocket server subscribes to group's pub/sub channel
- Server pushes message to all connected members in the group

**Scaling groups > 10,000**: Switch to fan-out on read (members query group messages on demand)

### Principal Engineer Extensions
- **End-to-end encryption**: Signal protocol (double ratchet); server stores ciphertext only; key exchange at client
- **Message search**: Elasticsearch index of messages (opt-in per workspace); privacy implications
- **Message edit/delete**: Soft delete with tombstone record; propagate deletion event to all clients
- **Multi-device sync**: User reconnects on new device → requests messages since `last_seen_message_id`; cursor-based sync

---

## Chapter 13 — Design a Search Autocomplete System

### Problem Statement
Design a search autocomplete (type-ahead) system that suggests search queries as users type, returning the top K most popular completions for the current prefix.

### Requirements

**Functional**:
- Return top 5 completions for any prefix in < 100 ms
- Completions ranked by historical search frequency
- Update suggestions based on new search trends (refresh hourly or daily)
- Support for multiple languages and Unicode

**Non-Functional**:
- 10M DAU; each performs 10 searches/day; 10 characters typed per search = 1B autocomplete requests/day ≈ 12,000 req/s; peak 30,000/s
- Data freshness: accept up to 24-hour lag in trending query updates
- High read:write ratio (millions of reads per write)

### The Trie Data Structure

A trie (prefix tree) stores all queries. Each node represents a character; path from root to node = prefix.

**Augmentation for top-K**: Each node stores the top K (e.g., 5) most frequent queries that start with that prefix. Pre-computed at build time.

```
Trie node:
{
  char: 'a',
  children: { 'p': ..., 'r': ..., ... },
  top_k: ["apple", "app store", "amazon", "airbnb", "aol"]  // pre-computed
}
```

**Time complexity**: O(prefix_length) to find node + O(1) to return top-K (pre-computed)  
**Space**: O(total_characters_in_all_queries) — for 10M unique queries averaging 20 chars ≈ 200 MB

### Architecture

```
Read path (autocomplete):
User types → API call GET /autocomplete?prefix=appl
          → Autocomplete Service → Redis cache (prefix → top_k_results)
          → Cache miss → Trie Service (reads serialized trie from storage)
          → Return top 5 results

Write path (update trie):
Search logs → Kafka → Aggregation job (Spark, hourly)
                              ↓
                     Updated query frequencies
                              ↓
                     Trie Builder (rebuild trie or incremental update)
                              ↓
                     Serialize trie → Object storage (S3)
                              ↓
                     Push updated trie to Autocomplete Service nodes
```

### Trie Partitioning

A single trie for all queries is too large to fit in one server's memory at scale (trillions of queries, hundreds of GBs).

**Shard by first 2 characters of prefix**:
- Prefix "ap*" → Shard 1; Prefix "ar*" → Shard 2
- Non-uniform character distribution → monitor and rebalance
- Hot shard risk: prefix "a" is very common → break down further ("aa", "ab", "ac"...)

**Alternative**: Store trie in Redis sorted sets per prefix: `ZREVRANGEBYSCORE prefix:{prefix} +inf -inf LIMIT 0 5`

### Optimization — Filter Harmful Content

Query suggestions must be filtered for hate speech, adult content, private data:
- Blocklist filter applied at serving time
- ML-based toxicity classifier on new trending queries before they enter trie
- Manual review queue for borderline cases

### Principal Engineer Extensions
- **Personalization**: Blend global top-K with user's personal search history (weighted average)
- **Spell correction**: Before trie lookup, apply spell-check (Norvig's algorithm or SymSpell); suggest corrected prefix
- **Incremental trie updates**: Instead of full rebuild every hour, apply delta updates for queries that crossed a frequency threshold
- **Distributed trie with Zookeeper**: Each autocomplete service node holds a full copy of the trie (several GBs); ZooKeeper notifies nodes to reload from S3 when updated

---

## Chapter 14 — Design YouTube

### Problem Statement
Design a video streaming platform at YouTube scale supporting upload, transcoding, storage, and adaptive streaming.

### Requirements

**Functional**:
- Upload videos (up to 1 GB raw)
- Transcode to multiple resolutions (360p, 720p, 1080p, 4K) and formats (MP4, WebM)
- Stream videos adaptively (ABR — switch quality based on network)
- Support comments, likes, subscriptions, recommendations

**Non-Functional**:
- 2B DAU; 500 hours of video uploaded per minute
- Streaming: 99.99% availability; < 2s start time; smooth playback (< 1% rebuffering)
- Uploads: durability 99.999%; process within 5 minutes of upload
- Storage: 500 hrs/min × 60 min/hr × 1 GB/hr raw = 30 TB raw uploads/hour (before compression)
- CDN delivery: video traffic is 80%+ of internet bandwidth (Netflix/YouTube combined)

### Upload & Transcoding Pipeline

```
User → Upload Service → Pre-signed S3 URL (large file chunked upload)
                ↓
Raw video stored in S3 (original bucket)
                ↓
Upload complete event → SQS/Kafka → Transcoding Worker Pool
                ↓
FFmpeg transcodes: 360p, 720p, 1080p, 4K (each resolution = parallel worker)
                ↓
Multiple resolutions stored in S3 (CDN bucket)
                ↓
Generate HLS manifest (.m3u8) pointing to segments for each resolution
                ↓
Update Video DB: status = READY; CDN URLs populated
                ↓
CDN pre-warms popular videos (top 1% of uploads); rest served on-demand
```

**Chunked upload**: Client splits video into 5 MB chunks; uploads in parallel; server reassembles. Supports resume on network interruption.

**Why message queue between upload and transcoding**: Decouples upload latency from transcoding time; transcoding can take minutes; queue absorbs bursts; workers scale independently.

### Adaptive Bitrate Streaming (ABR)

HLS (Apple) or MPEG-DASH (cross-platform) segments video into 2–10 second chunks at each quality level. Client player monitors download speed and switches resolution dynamically.

```
video.m3u8 (master playlist)
  └── 360p.m3u8
        ├── segment_0001.ts (360p, 2s)
        ├── segment_0002.ts
        └── ...
  └── 720p.m3u8
        ├── segment_0001.ts (720p, 2s)
        └── ...
  └── 1080p.m3u8
        └── ...
```

**Why segment-based**: Player buffers ahead by downloading next N segments; seamless resolution switch at segment boundary.

### CDN Strategy

- **Popular videos** (top 1% by views): Pre-pushed to all CDN PoPs globally; zero origin fetches
- **Long-tail videos** (99% of catalog): Served from nearest CDN PoP; cache miss → fetch from S3 origin
- **Cache key**: `{video_id}/{resolution}/{segment_number}.ts` — deterministic; easily cacheable
- **CDN selection**: Multiple CDN providers (Akamai + Cloudflare + AWS CloudFront); geo-DNS routes users to nearest provider; failover between providers if one degrades

### Storage Architecture

| Tier | What | Storage | Cost/GB |
|------|------|---------|---------|
| Hot | Segments for videos < 30 days old | S3 Standard | $0.023 |
| Warm | Videos 30–365 days | S3-IA | $0.012 |
| Cold | Videos > 1 year | S3 Glacier | $0.004 |
| Archive | Raw originals, rarely accessed | S3 Glacier Deep Archive | $0.00099 |

Lifecycle policy: auto-transition objects based on age.

### Video Metadata DB

Read-heavy (100:1 read:write). Use a combination:
- **Video metadata** (title, description, owner, status): MySQL with read replicas
- **View counts**: Redis counter with periodic flush to DB (eventual consistency acceptable)
- **Watch history**: Cassandra (time-series per user)
- **Search index**: Elasticsearch for title/description/tag search

### Principal Engineer Extensions
- **Recommendation system**: Two-tower model; candidate retrieval (embedding similarity) → re-ranking (multi-feature ML model) → diversity injection
- **Video deduplication**: Perceptual hashing (pHash) to detect re-uploads of same content; submit to Content ID for copyright matching
- **Live streaming**: RTMP ingest → transcoding pipeline with < 5s latency → HLS/DASH output; separate from VOD pipeline; peer-to-peer distribution for massive live events (Super Bowl)
- **Hate speech / CSAM detection**: Frame-level ML classifier on upload; Google SafeSearch API; human review queue for borderline cases

---

## Chapter 15 — Design Google Drive

### Problem Statement
Design a cloud file storage service like Google Drive or Dropbox supporting upload, download, sync across devices, sharing, and collaboration.

### Requirements

**Functional**:
- Upload, download, delete files (up to 5 GB each)
- Sync changes across multiple devices automatically
- Share files/folders with granular permissions (view, comment, edit)
- File versioning: access previous versions for up to 30 days
- Real-time collaboration on documents (stretch goal)

**Non-Functional**:
- 50M DAU; average user stores 10 GB → 500 PB total storage
- Upload/download: optimized for large files; chunked, resumable
- Sync latency: changes reflect on other devices within 5 seconds
- Durability: 99.9999999% (11 nines) — equivalent to replicating across 3+ AZs
- Availability: 99.99%

### File Storage Architecture

**Chunking strategy**:
- Files split into 4 MB chunks on the client before upload
- Each chunk identified by its SHA-256 hash (content-addressed storage)
- Deduplication: if two users upload the same file (or same chunk), store only once

```
Client                    Block Service           Object Storage
  ↓                           ↓                       ↓
Compute chunk hashes      Check which hashes      S3 / GCS
  ↓                       already exist               ↓
Upload only missing       Upload missing chunks   Store chunk by hash
chunks (delta sync)       Return pre-signed URL   as key
```

**Why chunking**:
- **Resumability**: Upload failure resumes from last successful chunk
- **Parallel upload**: Multiple chunks upload concurrently (5–10 parallel)
- **Delta sync**: Only changed chunks uploaded on modification (Dropbox: 85% bandwidth reduction)
- **Deduplication**: Same content = same hash = stored once

### Metadata DB

```sql
CREATE TABLE files (
    file_id        UUID PRIMARY KEY,
    owner_id       BIGINT NOT NULL,
    name           VARCHAR(255),
    size           BIGINT,
    checksum       CHAR(64),     -- SHA-256 of full file
    created_at     TIMESTAMP,
    updated_at     TIMESTAMP,
    is_deleted     BOOLEAN DEFAULT FALSE
);

CREATE TABLE file_versions (
    version_id     UUID PRIMARY KEY,
    file_id        UUID REFERENCES files,
    created_at     TIMESTAMP,
    size           BIGINT,
    chunk_ids      JSON    -- ordered list of chunk hashes
);

CREATE TABLE file_chunks (
    chunk_hash     CHAR(64) PRIMARY KEY,  -- SHA-256
    size           INT,
    storage_url    TEXT    -- S3 key
);

CREATE TABLE sharing (
    file_id        UUID,
    shared_with_id BIGINT,
    permission     ENUM('view', 'comment', 'edit'),
    PRIMARY KEY (file_id, shared_with_id)
);
```

### Sync Protocol

**Problem**: User edits file on laptop. How does the phone get the update within 5 seconds?

**Solution — Long polling + delta sync**:
1. Each client maintains a sync client that holds a long-poll connection to the Notification Service
2. File saved on laptop → Upload changed chunks → Metadata Service records new version → Publishes event to Message Queue → Notification Service pushes event to all user's devices
3. Phone receives notification → Sync client fetches metadata diff → Downloads only changed chunks

**Conflict resolution**:
- Same file edited simultaneously on two offline devices → both versions uploaded → conflict file created: `document (conflict 2024-01-15).docx`
- OT/CRDT (operational transformation / conflict-free data types) for real-time collaborative docs

### Security

- Files encrypted at rest (AES-256) and in transit (TLS 1.3)
- Chunk encryption: each chunk encrypted with a per-file key; key stored in Key Management Service
- Deduplication challenge: two users with same chunk → same encrypted content IF using same key. Solution: use per-user encryption key → lose cross-user dedup but gain privacy (trade-off)
- Sharing: don't share encryption keys; re-encrypt for recipient OR use envelope encryption with ACL

### Failure Modes

| Failure | Impact | Mitigation |
|---------|--------|-----------|
| Upload interrupted mid-chunk | Partial data in S3 | Client retries; content-addressed chunks are idempotent |
| Metadata DB down | Cannot create/list files | Read replicas handle reads; queue writes; circuit breaker |
| Sync notification lost | Client doesn't detect change | Periodic reconciliation: client compares local metadata hash with server metadata hash every 5 min |
| Storage tier failure | File unavailable | S3 Cross-Region Replication; multi-AZ within region |

### Principal Engineer Extensions
- **Content-addressed garbage collection**: Chunk is unreferenced when no file version references it → safe to delete. Run reference counting; collect unreferenced chunks older than 7 days
- **Streaming large files**: Don't buffer entire file in memory; use presigned S3 URLs and stream directly from client to S3 (bypasses application servers entirely)
- **Full-text search**: Extract text from documents (PDF, DOCX) → index in Elasticsearch with ACL filtering → search returns only files user has access to

---

## Summary: Key Patterns Across All Chapters

| Pattern | Where It Appears | What It Solves |
|---------|-----------------|---------------|
| **Snowflake ID** | Ch. 7, 8, 11, 12 | Globally unique, time-sortable IDs without coordination |
| **Consistent hashing** | Ch. 5, 6 | Even data distribution with minimal remapping on node changes |
| **Fan-out on write vs read** | Ch. 11 (news feed) | Trade-off between write amplification and read latency |
| **Cache-aside pattern** | Ch. 1, 8, 13 | Lazy cache population; DB as source of truth |
| **Message queue decoupling** | Ch. 10, 14, 9 | Absorb bursts; decouple producers from slow consumers |
| **Content-addressed storage** | Ch. 15 | Deduplication by content hash; idempotent uploads |
| **Chunked + resumable upload** | Ch. 14, 15 | Large file uploads that survive network interruption |
| **Hybrid fan-out (celebrity problem)** | Ch. 11 | Different strategies for high-follower vs low-follower accounts |
| **Vector clocks + quorum** | Ch. 6 | Conflict detection in leaderless replication |
| **Bloom filter** | Ch. 6, 9, 15 | Fast probabilistic membership test; avoid expensive lookups |
| **HLS/DASH segmented streaming** | Ch. 14 | Adaptive bitrate; CDN-cacheable segments |
| **Sliding window rate limiting** | Ch. 4 | Near-exact rate enforcement with O(1) memory |
