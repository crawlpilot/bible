# AWS ElastiCache & MemoryDB — Deep Dive

## Overview

ElastiCache is AWS's managed in-memory caching service, offering Redis and Memcached engines. MemoryDB for Redis is the durable, multi-AZ version — a Redis-compatible database with transaction log persistence.

**Mental model:**
- **ElastiCache Redis** = fast cache; data loss on failure is acceptable
- **MemoryDB for Redis** = durable Redis; primary database use case (millisecond reads, durable writes)
- **ElastiCache Memcached** = simple distributed cache; multi-threaded; no persistence, no replication

---

## Redis vs Memcached

| Dimension | Redis | Memcached |
|-----------|-------|-----------|
| Data structures | Strings, hashes, lists, sets, sorted sets, streams, bitmaps, HyperLogLog | Strings only |
| Replication | Yes (primary + replicas) | No |
| Persistence | RDB snapshots + AOF | No |
| Pub/Sub | Yes | No |
| Lua scripting | Yes | No |
| Transactions | Yes (MULTI/EXEC) | No |
| Cluster mode | Yes (horizontal sharding) | Yes (client-side) |
| Threading | Single-threaded (I/O threaded in Redis 6+) | Multi-threaded |

**Choose Memcached only when:** you need pure horizontal scale for a simple key-value cache with no replication needs and your client handles sharding. In practice, Redis handles nearly every use case better — Memcached is legacy.

---

## ElastiCache Redis Architecture

### Cluster Mode Disabled (Classic Replication Group)

```
  [Primary Node]
       ↓ async replication
  [Replica 1]   [Replica 2]   ← up to 5 replicas
```

- Single shard, all data on one primary
- Replicas serve reads (eventual consistency)
- Max data size: limited to one node's memory
- Failover: automatic promotion of replica to primary (~30–60s)

### Cluster Mode Enabled (Horizontal Sharding)

```
  Shard 1: [Primary] [Replica]
  Shard 2: [Primary] [Replica]
  Shard N: [Primary] [Replica]
```

- Data distributed across N shards using consistent hashing (16,384 hash slots)
- Each shard holds a subset of keys
- Supports up to 500 nodes (250 shards × 2 replicas each)
- Scale out by adding shards (live resharding, minimal downtime)
- **Required for datasets > single node memory** or write throughput > single primary can handle

**Cluster mode tradeoff:** Multi-key commands (MGET, MSET, pipelines) require all keys to be in the same hash slot (use hash tags `{user}:session` and `{user}:profile` to co-locate). Cross-slot commands are not supported.

---

## ElastiCache Serverless

Launched 2023 — fully managed, auto-scales, no cluster/shard sizing:
- Pay per ECU (ElastiCache unit = 1 GECPU + 1 GB memory) consumed
- Minimum: 0 (scales to near-zero when idle)
- Supports Redis and Memcached protocols
- No cluster mode complexity — serverless handles sharding internally
- Latency: comparable to cluster mode (~sub-millisecond)
- **Best for:** variable workloads, dev/test, when sizing clusters is a burden

---

## MemoryDB for Redis

**Architecture:**
```
  [Primary]  →→→  [Multi-AZ Transaction Log (durability)]
  [Replica 1]
  [Replica 2]
```

- Every write is synchronously committed to a multi-AZ transaction log before ACK
- RPO = 0 (no data loss on node failure)
- Recovery: restore from transaction log, not snapshot
- **Use as a primary database** (session store, real-time leaderboard, gaming state, message queue)

| | ElastiCache Redis | MemoryDB |
|--|-------------------|----------|
| Durability | Best-effort (async replication, AOF optional) | Strong (sync transaction log) |
| Data loss on failure | Possible | None |
| Latency (writes) | ~microseconds | ~1ms (sync log) |
| Use case | Cache | Primary DB or cache |
| Cost | Lower | Higher (~2× ElastiCache) |

---

## Caching Patterns

### Cache-Aside (Lazy Loading)
```
read(key):
  val = cache.get(key)
  if val is None:
    val = db.get(key)
    cache.set(key, val, ttl=300)
  return val
```
- Most common pattern
- Pros: only caches what's requested; cache failure = DB hit (graceful degradation)
- Cons: first read always misses (cold start); stale data between TTL window

### Write-Through
```
write(key, val):
  db.write(key, val)
  cache.set(key, val)
```
- Cache always has fresh data
- Pros: eliminates cache misses for hot data
- Cons: write latency increases; cache fills with data never read

### Write-Behind (Write-Back)
```
write(key, val):
  cache.set(key, val)
  async_queue.enqueue(db.write, key, val)
```
- Fastest write path
- Pros: absorbs write bursts
- Cons: data loss risk if cache fails before async write completes; complex

### Read-Through
- Cache sits in front of DB, cache fetches from DB on miss automatically
- Requires cache layer to know DB schema — mostly used with specialized caching proxies

### Refresh-Ahead
- Cache proactively refreshes before TTL expires (based on access frequency)
- Complex to implement; useful for data with known high read frequency and costly recomputation

---

## Data Structures & Use Cases

| Redis Structure | Use case | Example |
|----------------|----------|---------|
| **String** | Simple cache, counters, rate limiting | `INCR rate:user:123` |
| **Hash** | Object storage (user profile, product) | `HSET user:123 name "Alice" age 30` |
| **List** | Message queue, activity feed (push/pop) | `LPUSH feed:123 post456` |
| **Set** | Unique visitors, tags, social graph | `SADD followers:alice bob` |
| **Sorted Set** | Leaderboard, delayed queue, geo-queries | `ZADD leaderboard 9500 "alice"` |
| **Bitmap** | User activity flags, bloom filter | `SETBIT active:2026-06-12 userId 1` |
| **HyperLogLog** | Approximate unique count | `PFADD visitors page1 user1 user2` |
| **Stream** | Event log, message bus (Kafka-lite) | `XADD events * type "click" item "p1"` |

---

## Rate Limiting with Redis

### Sliding Window Counter (Token Bucket)
```lua
-- Lua script for atomic rate check (runs server-side, no race conditions)
local key = KEYS[1]
local limit = tonumber(ARGV[1])
local window = tonumber(ARGV[2])
local current = redis.call('INCR', key)
if current == 1 then
  redis.call('EXPIRE', key, window)
end
if current > limit then
  return 0
end
return 1
```
- Use `INCR` + `EXPIRE` for fixed window
- Use sorted sets for sliding window: `ZADD` with current timestamp, `ZREMRANGEBYSCORE` to remove old entries, `ZCARD` for current count

---

## Session Store Design

```
Key:   SESSION#sid_abc123
Value: {user_id: u1, roles: ["admin"], cart: [...], expires: 1719000000}
TTL:   1800 seconds (30 min sliding)

On each request:
  cache.get("SESSION#sid_abc123")
  cache.expire("SESSION#sid_abc123", 1800)  # extend TTL on activity
```

- Store in Redis Hash for partial field updates without rewriting the full session
- Use MemoryDB if session loss is unacceptable (e.g., mid-checkout)
- Use ElastiCache for best-effort sessions (users just re-login)

---

## Sentinel (High Availability for Non-Cluster Mode)

AWS manages Sentinel internally — it monitors the primary, elects a new primary on failure, and updates DNS:
- Primary DNS endpoint always points to current primary
- Failover: ~30–60 seconds (automatic)
- Application must handle brief connection errors during failover
- Use retry logic with exponential backoff in client

---

## Replication & Persistence

### RDB Snapshots
- Point-in-time snapshot saved to disk (and S3 for ElastiCache)
- `BGSAVE` forks the Redis process — no blocking
- Snapshot intervals: every 1h, 6h, 24h (ElastiCache managed)

### AOF (Append-Only File)
- Logs every write operation — allows replay on restart
- `appendfsync always`: safest, most durable (1 fsync per write) — slowest
- `appendfsync everysec`: 1 fsync/second — default, at most 1 second of data loss
- `appendfsync no`: OS decides when to fsync — fastest, most data loss risk

For ElastiCache: AOF is optional (enabled per replication group). For MemoryDB, the transaction log replaces AOF.

---

## Eviction Policies

When `maxmemory` is reached, Redis uses an eviction policy:

| Policy | Behavior | Best for |
|--------|----------|----------|
| `noeviction` | Return error on write | Critical data that must not be lost |
| `allkeys-lru` | Evict least-recently-used across all keys | General cache |
| `volatile-lru` | Evict LRU among keys with TTL | Cache + durable data mix |
| `allkeys-lfu` | Evict least-frequently-used | Skewed access patterns |
| `volatile-ttl` | Evict key with shortest TTL first | Expire-aware cache |
| `allkeys-random` | Evict random key | Uniform access patterns |

**Default recommendation:** `allkeys-lru` for pure caches. `volatile-lru` if cache shares Redis with persistent data.

---

## Observability

Key CloudWatch metrics:

| Metric | Alarm threshold | Meaning |
|--------|-----------------|---------|
| `CacheHitRate` | <90% | Cache not effective; check TTL or access pattern |
| `Evictions` | >0 sustained | Memory pressure; scale up or reduce data set |
| `CurrConnections` | >threshold | Connection pool exhaustion |
| `ReplicationLag` | >10ms | Replica falling behind |
| `EngineCPUUtilization` | >80% | CPU-bound (large Lua scripts, sort operations) |
| `FreeableMemory` | <10% | Near OOM; scale up or adjust eviction |

---

## ElastiCache vs Alternatives

| | ElastiCache Redis | DynamoDB DAX | In-process cache |
|--|-------------------|--------------|-----------------|
| Shared across services | Yes | Yes (DynamoDB only) | No (per-process) |
| Latency | Sub-millisecond | Microseconds | Nanoseconds |
| Data consistency | Eventual | Eventual | Local only |
| Scale | Cluster mode: horizontal | Transparent | Limited to node RAM |
| Ops | Managed | Fully managed | None |
| Use case | Any data, cross-service | DynamoDB read acceleration | Hot paths, immutable data |

---

## FAANG Interview Callouts

**"Design a leaderboard for a game with 10 million players"**
→ Redis Sorted Set: `ZADD leaderboard <score> <userId>`. `ZRANGE leaderboard 0 99 WITHSCORES REV` for top 100. `ZRANK leaderboard userId` for rank of any player. Sub-millisecond for all operations. Shard by game/region if > single Redis instance. Back scores to DynamoDB or RDS for durability.

**"How do you implement rate limiting at 100k req/s?"**
→ Redis `INCR` + `EXPIRE` (fixed window) or sorted set (sliding window). Run logic as Lua script for atomicity. ElastiCache Cluster mode handles the throughput. For truly distributed global rate limiting, combine with DynamoDB atomic counters for cross-region.

**"Your service is hammering the DB at 500k reads/s during flash sale — what do you do?"**
→ Cache-aside pattern with ElastiCache. Pre-warm cache before the sale (load popular items into cache). Set appropriate TTLs. Use read-through to prevent thundering herd on TTL expiry (probabilistic early expiration or distributed locking around cache miss).

**"Cache invalidation — the hard problem. How do you handle it?"**
→ Three strategies: (1) TTL-based expiry — accept stale window, simplest; (2) Event-driven invalidation — write to DB triggers SNS/EventBridge → Lambda → delete cache key; (3) Cache versioning — embed a version in the key, new version = new key (old key naturally expires). For FAANG, prefer event-driven with fallback TTL.

**"MemoryDB vs ElastiCache — when do you choose MemoryDB?"**
→ MemoryDB when Redis is the primary database, not a cache — session store with zero-loss requirement, real-time leaderboard that can't be rebuilt from DB, gaming state, financial position data. ElastiCache when it's a cache fronting a DB (acceptable to rebuild from DB on failure).
