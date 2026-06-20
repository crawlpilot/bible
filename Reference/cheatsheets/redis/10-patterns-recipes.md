# Patterns & Recipes — Redis Reference

Production-ready patterns with complete `redis-cli` commands and Lua scripts. Copy-paste ready.

---

## Pattern 1: Distributed Lock

**Problem**: Only one process across N servers should execute a critical section at a time.

### Acquire

```bash
# Atomic: SET if Not eXists + EXpiry in one command
SET lock:resource_name "owner_identifier" NX EX 30
# → OK   (lock acquired; expires in 30s)
# → nil  (lock held by someone else)

# owner_identifier should be unique per caller (UUID or pod-id + thread-id)
# so you can safely release only your own lock
```

### Release (must verify ownership)

```bash
# WRONG — may release another process's lock if yours expired:
DEL lock:resource_name

# CORRECT — Lua ensures GET + DEL is atomic:
EVAL "
  if redis.call('GET', KEYS[1]) == ARGV[1] then
    return redis.call('DEL', KEYS[1])
  else
    return 0
  end
" 1 lock:resource_name "owner_identifier"
# → 1 (released)
# → 0 (not owner — lock expired and re-acquired, or never owned)
```

### Extend Lock (heartbeat while holding)

```bash
EVAL "
  if redis.call('GET', KEYS[1]) == ARGV[1] then
    return redis.call('EXPIRE', KEYS[1], ARGV[2])
  else
    return 0
  end
" 1 lock:resource_name "owner_identifier" 30
# → 1 (extended by 30s)
# → 0 (not the owner)
```

### Multi-Resource Lock (all-or-nothing)

```lua
-- Lock N keys atomically or lock none
local owner = ARGV[1]
local ttl   = tonumber(ARGV[2])

-- Check all are free
for i = 1, #KEYS do
    if redis.call('EXISTS', KEYS[i]) == 1 then
        return 0   -- at least one is taken; don't acquire any
    end
end

-- Acquire all
for i = 1, #KEYS do
    redis.call('SET', KEYS[i], owner, 'EX', ttl)
end
return 1
```

```bash
EVAL "<above script>" 3 \
  lock:seat:SHOW001:A1 \
  lock:seat:SHOW001:A2 \
  lock:seat:SHOW001:A3 \
  "booking_xyz" 600
```

---

## Pattern 2: Rate Limiter

### Fixed Window Counter

```bash
# Allows up to MAX_REQUESTS per WINDOW_SECONDS
EVAL "
  local current = redis.call('INCR', KEYS[1])
  if current == 1 then
    redis.call('EXPIRE', KEYS[1], ARGV[1])
  end
  if current > tonumber(ARGV[2]) then
    return {0, redis.call('TTL', KEYS[1])}
  end
  return {1, 0}
" 1 rate:user:42:api 60 100
# ARGV[1]=60 (window), ARGV[2]=100 (max)
# → {1, 0}    = allowed, 0 seconds until reset
# → {0, 45}   = blocked, 45 seconds until window resets

# Without Lua (two commands — tiny race on window start, acceptable):
INCR rate:user:42:api               # → N (current count)
EXPIRE rate:user:42:api 60          # (only sets TTL if key has none — set NX behavior not available for EXPIRE)
# Better: use the Lua version above
```

### Sliding Window (Token Bucket via Sorted Set)

```bash
# Add request timestamp to sorted set; count within window; trim old entries
MULTI
ZADD requests:user:42 1717890000000 "req_uuid_here"   # score=timestamp_ms
ZREMRANGEBYSCORE requests:user:42 0 1717889940000      # remove older than 60s ago
ZCARD requests:user:42                                  # current count in window
EXPIRE requests:user:42 70                              # cleanup TTL
EXEC
# If ZCARD result > limit → rate limited

# One-shot Lua version (atomic):
EVAL "
  local now = tonumber(ARGV[1])
  local window = tonumber(ARGV[2])
  local limit  = tonumber(ARGV[3])
  local req_id = ARGV[4]

  redis.call('ZADD', KEYS[1], now, req_id)
  redis.call('ZREMRANGEBYSCORE', KEYS[1], 0, now - window)
  local count = redis.call('ZCARD', KEYS[1])
  redis.call('EXPIRE', KEYS[1], math.ceil(window / 1000) + 1)

  if count > limit then
    return 0
  end
  return 1
" 1 requests:user:42 1717890000000 60000 100 "req_uuid_abc"
# ARGV: now_ms, window_ms, limit, unique_request_id
```

---

## Pattern 3: Cache-Aside (Lazy Population)

**Application logic** — Redis stores the cached value; DB is source of truth.

```bash
# Step 1: Try cache
GET cache:show:SHOW001:metadata
# → nil (miss)

# Step 2: On miss — fetch from DB, write to cache
SET cache:show:SHOW001:metadata '{"title":"Avengers","screen":"IMAX"}' EX 300
# TTL=300s: auto-invalidated without any explicit invalidation needed

# Step 3: Return to caller

# Invalidate explicitly on update:
DEL cache:show:SHOW001:metadata      # or UNLINK for async

# Cache stampede prevention (only one thread rebuilds cache):
SET loading_lock:show:SHOW001 1 NX EX 5
# → OK   (this process builds the cache)
# → nil  (another process is building — wait 100ms and retry GET)
```

---

## Pattern 4: Session Store

```bash
# Create session
HSET session:tok_abc123 \
  user_id    "42" \
  username   "alice" \
  role       "admin" \
  ip         "10.0.0.1" \
  created_at "1717890000"
EXPIRE session:tok_abc123 3600          # 1 hour TTL

# Read fields on each request (only what you need)
HMGET session:tok_abc123 user_id role
# → 1) "42"
#    2) "admin"

# Extend session on activity (sliding expiry)
EXPIRE session:tok_abc123 3600

# Read-and-extend atomically (Redis 6.2+, only works on String keys):
# For hash sessions, use pipeline:
MULTI
HGETALL session:tok_abc123
EXPIRE  session:tok_abc123 3600
EXEC

# Destroy session (logout)
DEL session:tok_abc123

# Check session exists before processing
EXISTS session:tok_abc123              # → 1 or 0

# All active sessions for a user (maintain index set)
SADD user:42:sessions "tok_abc123"
SREM user:42:sessions "tok_abc123"    # on logout
SMEMBERS user:42:sessions             # list all of user's sessions

# Invalidate all sessions for a user (force logout everywhere)
SMEMBERS user:42:sessions | xargs DEL
DEL user:42:sessions
```

---

## Pattern 5: Leaderboard

```bash
# Update score (use ZADD INCR for delta-based updates)
ZINCRBY leaderboard:game:weekly 150 "player:42"   # → new score
ZADD    leaderboard:game:weekly 5000 "player:42"  # → set absolute score

# Top 10 (rank 1 = highest score)
ZRANGE leaderboard:game:weekly 0 9 REV WITHSCORES
# → 1) "player:99"  2) "9800"
#    3) "player:42"  4) "5000"
#    5) ...

# Player's rank (1-indexed for display)
rank = ZREVRANK leaderboard:game:weekly "player:42"   # → 1  (0-indexed)
display_rank = rank + 1                                # → 2  (2nd place)

# Player's score
ZSCORE leaderboard:game:weekly "player:42"            # → "5000"

# Nearby players (±2 positions around the player)
# First get rank:
ZREVRANK leaderboard:game:weekly "player:42"          # → 1
# Then get surrounding slice (handle edge cases for rank=0 or near bottom):
ZRANGE leaderboard:game:weekly 0 3 REV WITHSCORES    # top 4 around rank 1

# Count players above a score threshold
ZCOUNT leaderboard:game:weekly 1000 +inf             # → N players with score > 1000

# Weekly reset: rename current to archive, start fresh
RENAME leaderboard:game:weekly leaderboard:game:week:23
DEL    leaderboard:game:weekly

# Percentile rank
total = ZCARD leaderboard:game:weekly
rank  = ZREVRANK leaderboard:game:weekly "player:42"
percentile = (total - rank) / total * 100             # application-side math
```

---

## Pattern 6: Pub/Sub Fan-Out (WebSocket Seat Map)

```bash
# --- Server: Publisher (on seat lock event) ---
PUBLISH seat-updates:SHOW001 '{"seats":[{"id":"A1","status":"LOCKED"},{"id":"A2","status":"LOCKED"}]}'
# → N  (number of WebSocket worker pods that received it)

# --- WebSocket Worker Pod: Subscriber ---
# Subscribe to channels for shows with active connections
SUBSCRIBE seat-updates:SHOW001 seat-updates:SHOW002

# Pattern subscribe (one connection subscribes to ALL shows)
PSUBSCRIBE "seat-updates:*"

# Messages received in subscriber loop:
# 1) "pmessage"
# 2) "seat-updates:*"          ← pattern that matched
# 3) "seat-updates:SHOW001"    ← actual channel
# 4) "{\"seats\":[...]}"       ← payload

# Inspect active channels
PUBSUB CHANNELS "seat-updates:*"
PUBSUB NUMSUB seat-updates:SHOW001
```

---

## Pattern 7: Bloom Filter Approximation (using Bitmaps)

Approximate membership: "is this item probably in the set?" Fast, memory-efficient, false-positives possible, no false-negatives.

```bash
# Using RedisBloom module (if available):
BF.ADD   deduplication:emails "user@example.com"   # → 1 (added)
BF.EXISTS deduplication:emails "user@example.com"  # → 1 (probably yes)
BF.EXISTS deduplication:emails "new@example.com"   # → 0 (definitely no)
BF.MADD  deduplication:emails "a@x.com" "b@x.com"
BF.MEXISTS deduplication:emails "a@x.com" "b@x.com"

# Without module — manual bitmap approach (simplified, 1 hash function):
# hash(email) → bit_position
# SETBIT bloom:emails {bit_position} 1
# GETBIT bloom:emails {bit_position}  → 0 = definitely not seen, 1 = probably seen
```

---

## Pattern 8: Write-Through Cache (Seat Availability Hash)

```bash
# Every seat state change: write DB first, then update Redis Hash immediately

# On seat LOCK:
# (Application) DB: UPDATE show_seats SET status='LOCKED' WHERE seat_id='A1'
HSET layout:SHOW001 A1 L                  # L = LOCKED
PUBLISH seat-updates:SHOW001 '{"seats":[{"id":"A1","status":"L"}]}'

# On seat BOOK:
# (Application) DB: UPDATE show_seats SET status='BOOKED' WHERE seat_id='A1'
HSET layout:SHOW001 A1 B                  # B = BOOKED
DEL lock:seat:SHOW001:A1                  # remove lock key

# On lock EXPIRE (background sweeper):
# (Application) DB: UPDATE show_seats SET status='AVAILABLE'
HSET layout:SHOW001 A1 A                  # A = AVAILABLE
PUBLISH seat-updates:SHOW001 '{"seats":[{"id":"A1","status":"A"}]}'

# Full layout read (single command — no N+1 queries):
HGETALL layout:SHOW001
# Returns flat array: [A1, A, A2, L, A3, B, ...]

# Cache miss rebuild:
# (Application) DB: SELECT seat_id, status FROM show_seats WHERE show_id='SHOW001'
# Then:
HSET layout:SHOW001 A1 A A2 L A3 B ...   # all seats in one HSET call
# No TTL on this hash — stays until show completes (then DEL layout:SHOW001)
```

---

## Pattern 9: Idempotency Key

```bash
# Before processing: check if request already processed
GET idempotency:req_uuid_abc
# → nil   (not seen before — process it)
# → "..." (seen before — return cached response)

# After processing: cache the response
SET idempotency:req_uuid_abc '{"booking_id":"BOOK123","status":"PENDING"}' EX 86400
# EX 86400 = 24h; client won't retry after that

# Pattern: SET NX to prevent race between two concurrent identical requests
SET idempotency:req_uuid_abc "PROCESSING" NX EX 30
# → OK   (first request gets to process)
# → nil  (second request — first is already processing; return 202 Retry-After)

# On completion: update with final response
SET idempotency:req_uuid_abc '{"booking_id":"BOOK123","status":"CONFIRMED"}' EX 86400
```

---

## Pattern 10: Atomic Counter with Reset

```bash
# Metrics counter: increment and read, reset on schedule
INCR metrics:orders:today                    # increment
GET metrics:orders:today                     # read current value

# Atomic read-and-reset (get current value and reset to 0)
EVAL "
  local val = redis.call('GET', KEYS[1])
  redis.call('SET', KEYS[1], 0)
  return val or 0
" 1 metrics:orders:today

# Alternative: rename to snapshot, start fresh
RENAME metrics:orders:today metrics:orders:snapshot:2026-06-06
SET metrics:orders:today 0
```

---

## Anti-Patterns to Avoid

```
# NEVER use KEYS in production
KEYS *                          ← blocks Redis for entire keyspace scan

# NEVER use SELECT in cluster mode
SELECT 2                        ← cluster only has DB 0

# NEVER use two-command lock
SETNX lock:key "owner"         ← non-atomic with EXPIRE below
EXPIRE lock:key 30             ← race: crash here = lock never expires

# NEVER trust Redis as sole source of truth for financial data
# Always have authoritative DB; Redis is cache/lock layer

# NEVER use large values in pub/sub messages
PUBLISH channel {10MB_payload}  ← copies to all subscribers; saturates network

# NEVER use HGETALL on unbounded hashes
HGETALL user:metrics            ← could have 1M fields; use HSCAN

# NEVER use SMEMBERS on large sets
SMEMBERS all_users              ← use SSCAN

# NEVER store sensitive data (passwords, PII) in Redis without encryption
# Redis is often accessible within a VPC with no per-key encryption at rest
```

---

→ **See also**: [08-transactions-scripting.md](08-transactions-scripting.md) for Lua details | [05-sorted-sets.md](05-sorted-sets.md) for leaderboard commands | [07-pub-sub-streams.md](07-pub-sub-streams.md) for pub/sub and streams
