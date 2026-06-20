# System Component: Distributed Cache

**Category**: LLD · System Components · Caching  
**Eviction Policies**: LRU, LFU, TTL, LFRU  
**Write Policies**: Cache-Aside, Write-Through, Write-Behind, Refresh-Ahead  
**Real-world implementations**: Redis, Memcached, Hazelcast, Apache Ignite, Caffeine (in-process)

---

## Problem Statement

A distributed cache stores frequently accessed data in memory across multiple nodes, reducing database load and improving read latency from 1–100ms (DB) to <1ms (memory). The key design decisions are:
1. **Where to cache** (client-side, server-side, CDN)
2. **When to populate the cache** (on read miss, on write, proactively)
3. **How to handle eviction** (which items to remove when memory is full)
4. **How to handle consistency** (when do reads see writes?)

---

## Cache Write Policies

### Cache-Aside (Lazy Loading)
The application manages the cache explicitly. Most common pattern.

```python
class CacheAsideRepository:
    def __init__(self, cache: Cache, db: Database, ttl_s: int = 300):
        self._cache = cache
        self._db = db
        self._ttl = ttl_s

    def get(self, key: str):
        # 1. Try cache
        value = self._cache.get(key)
        if value is not None:
            return value
        # 2. Cache miss → read from DB
        value = self._db.get(key)
        if value is not None:
            # 3. Populate cache
            self._cache.set(key, value, ttl=self._ttl)
        return value

    def update(self, key: str, value):
        # Write to DB first, then invalidate cache
        self._db.put(key, value)
        self._cache.delete(key)   # invalidate; next read will repopulate
```

**Pros**: cache only contains data that's actually requested; DB is the source of truth; resilient to cache failure.  
**Cons**: cache miss penalty (DB read + cache write on first access); stale data window between DB update and cache invalidation; "thundering herd" on cold start.

**The thundering herd problem**: if a popular key expires, multiple concurrent requests all miss the cache simultaneously and hit the DB. Solutions:
- **Mutex/lock**: first request acquires a lock and fills the cache; others wait.
- **Probabilistic early expiration**: re-compute the value slightly before it expires.
- **Stale-while-revalidate**: return stale data and refresh in background.

### Write-Through
Write to cache and DB synchronously on every write.

```python
class WriteThroughRepository:
    def update(self, key: str, value):
        # Write to both simultaneously (or DB first, then cache)
        self._db.put(key, value)
        self._cache.set(key, value, ttl=self._ttl)
```

**Pros**: cache always consistent with DB; no stale reads after a write.  
**Cons**: write latency includes both DB + cache write; cache fills with data that may never be read.

### Write-Behind (Write-Back)
Write to cache first, asynchronously persist to DB later.

```python
class WriteBehindRepository:
    def __init__(self, cache, db, flush_interval_s=5):
        self._dirty: dict = {}   # keys pending DB flush
        self._lock = threading.Lock()
        # Background thread flushes dirty keys every flush_interval_s

    def update(self, key: str, value):
        self._cache.set(key, value)
        with self._lock:
            self._dirty[key] = value   # mark dirty

    def _flush(self):
        with self._lock:
            dirty_copy = dict(self._dirty)
            self._dirty.clear()
        for key, value in dirty_copy.items():
            self._db.put(key, value)
```

**Pros**: lowest write latency; absorbs write bursts (multiple writes to same key → one DB write).  
**Cons**: data loss risk if cache fails before flush; complex consistency guarantees.  
**Use when**: write-heavy workloads, high write throughput to same keys (counters, aggregations).

### Refresh-Ahead
Proactively refresh cache entries before they expire.

```python
class RefreshAheadCache:
    def get(self, key: str):
        value, ttl_remaining = self._cache.get_with_ttl(key)
        if value and ttl_remaining < self._refresh_threshold:
            # Proactively refresh in background
            self._executor.submit(self._refresh, key)
        return value
```

**Use when**: predictable access patterns, cannot afford cache miss latency (e.g., authentication tokens).

---

## Eviction Policies

### LRU (Least Recently Used)

Implementation using `OrderedDict` (Python's built-in maintains insertion order):

```python
from collections import OrderedDict
import threading

class LRUCache:
    def __init__(self, capacity: int):
        self._capacity = capacity
        self._cache: OrderedDict[str, any] = OrderedDict()
        self._lock = threading.Lock()

    def get(self, key: str):
        with self._lock:
            if key not in self._cache:
                return None
            self._cache.move_to_end(key)   # mark as most recently used
            return self._cache[key]

    def set(self, key: str, value) -> bool:
        with self._lock:
            if key in self._cache:
                self._cache.move_to_end(key)
                self._cache[key] = value
            else:
                if len(self._cache) >= self._capacity:
                    self._cache.popitem(last=False)   # evict LRU (first item)
                self._cache[key] = value
        return True

    def delete(self, key: str):
        with self._lock:
            self._cache.pop(key, None)
```

**LRU is O(1)** get/set using `OrderedDict` (doubly-linked list + hash map internally).

**Weakness**: LRU is vulnerable to cache scans — a sequential scan of many keys evicts everything in the cache even if those keys are never accessed again. Solution: LRU-K or Segmented LRU (S-LRU).

### LFU (Least Frequently Used)

```python
from collections import defaultdict

class LFUCache:
    def __init__(self, capacity: int):
        self._capacity = capacity
        self._key_to_val: dict = {}
        self._key_to_freq: dict[str, int] = defaultdict(int)
        self._freq_to_keys: dict[int, OrderedDict] = defaultdict(OrderedDict)
        self._min_freq = 0
        self._lock = threading.Lock()

    def get(self, key: str):
        with self._lock:
            if key not in self._key_to_val:
                return None
            self._increment_freq(key)
            return self._key_to_val[key]

    def set(self, key: str, value):
        with self._lock:
            if self._capacity <= 0:
                return
            if key in self._key_to_val:
                self._key_to_val[key] = value
                self._increment_freq(key)
            else:
                if len(self._key_to_val) >= self._capacity:
                    self._evict()
                self._key_to_val[key] = value
                self._key_to_freq[key] = 1
                self._freq_to_keys[1][key] = None
                self._min_freq = 1

    def _increment_freq(self, key: str):
        freq = self._key_to_freq[key]
        self._key_to_freq[key] = freq + 1
        self._freq_to_keys[freq].pop(key)
        if not self._freq_to_keys[freq] and freq == self._min_freq:
            self._min_freq += 1
        self._freq_to_keys[freq + 1][key] = None

    def _evict(self):
        keys_at_min_freq = self._freq_to_keys[self._min_freq]
        evict_key, _ = keys_at_min_freq.popitem(last=False)  # LRU among min-freq
        del self._key_to_val[evict_key]
        del self._key_to_freq[evict_key]
```

**When LFU beats LRU**: workloads with stable "hot" keys (Zipf-distributed access — top 20% of keys get 80% of requests). LFU resists cache scans better.  
**When LRU beats LFU**: workloads with temporal locality (recently accessed items are likely to be accessed again, even if not frequently).

---

## Eviction Policy Comparison

| Policy | Best For | Weakness |
|--------|---------|----------|
| **LRU** | Temporal locality, general-purpose | Cache scans evict hot data |
| **LFU** | Stable hot keys (Zipf distribution) | Cold start (new popular items take time to build frequency) |
| **TTL** | Data with natural expiry (sessions, tokens) | Doesn't adapt to access patterns |
| **LFRU** | Hybrid — protected + probationary segments | More complex, higher overhead |
| **Random** | Simplest, low overhead | Unpredictable hit rate |

---

## Distributed Cache Architecture

### Consistent Hashing for Distribution

```
             Hash Ring
    +--------+--------+--------+
    | Node A | Node B | Node C |
    +--------+--------+--------+

key("user:123")  → hash → position on ring → Node B
key("session:X") → hash → position on ring → Node C
```

On node failure: only the keys that hashed to that node are remapped to the next node on the ring (~1/N of all keys). Other nodes' data is unaffected.

### Replication for Availability

Redis Sentinel / Redis Cluster: each primary node has N replicas. Reads can be served from replicas (eventual consistency). Writes go to the primary. On primary failure, Sentinel promotes a replica.

**Read-your-writes consistency**: route reads for a key to the same primary that handled the write. Otherwise, a replica may lag and return stale data within milliseconds of the write.

---

## Cache Consistency Problems

### Cache Stampede (Thundering Herd)
Multiple requests simultaneously miss on an expired hot key.

**Solution — Mutex lock with singleflight**:
```python
import threading

class SingleflightCache:
    def __init__(self, cache, loader):
        self._cache = cache
        self._loader = loader
        self._inflight: dict[str, threading.Event] = {}
        self._lock = threading.Lock()

    def get(self, key: str):
        value = self._cache.get(key)
        if value is not None:
            return value
        with self._lock:
            if key in self._inflight:
                event = self._inflight[key]
            else:
                event = threading.Event()
                self._inflight[key] = event
                first = True
        if not first:
            event.wait()
            return self._cache.get(key)
        # This goroutine loads the value
        value = self._loader(key)
        self._cache.set(key, value)
        with self._lock:
            del self._inflight[key]
        event.set()
        return value
```

### Stale-While-Revalidate
Return stale data immediately; refresh in background:
```python
def get_with_swr(self, key: str):
    value, remaining_ttl = self._cache.get_with_ttl(key)
    if remaining_ttl < self._stale_threshold and not self._refreshing.get(key):
        self._refreshing[key] = True
        self._executor.submit(self._refresh_async, key)
    return value   # return stale value immediately
```

---

## FAANG Interview Callouts

**The cache invalidation problem** ("There are only two hard things in computer science: cache invalidation and naming things"):
- Write-through + version key: `user:123:v5` — increment version on write; old keys become stale automatically via TTL
- Event-driven invalidation: DB writes publish an event; cache consumers delete the key
- Short TTL + tolerate staleness: for many use cases (product catalog, config), 5-minute staleness is acceptable

**Common system design patterns:**
- User session store: Redis with TTL, `EXPIRE` command resets on each request (sliding TTL)
- Rate limiter: Redis `INCR` + `EXPIRE` (token bucket or fixed window counter)
- Leaderboard: Redis Sorted Set (`ZADD`, `ZRANK`, `ZRANGE`) — O(log N) operations
- Distributed lock: Redis `SET key value NX PX 30000` (atomic set-if-not-exists with expiry)
- Pub/Sub: Redis Pub/Sub or Streams for fanout to cache consumers

**Key questions to ask in the interview:**
- "What's the tolerable staleness window?" (determines TTL and invalidation strategy)
- "What's the read:write ratio?" (high reads → cache-aside; high writes → write-behind)
- "What happens on cache miss — can we tolerate the latency?" (determines whether refresh-ahead is needed)
