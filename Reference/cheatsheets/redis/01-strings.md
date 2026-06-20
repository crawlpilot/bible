# Strings — Redis Reference

The default and most versatile type. Stores bytes: text, integers, floats, serialized JSON, binary blobs. Max value size: **512 MB**.

---

## Quick Reference

| Command | Syntax | Returns | Complexity | Notes |
|---------|--------|---------|-----------|-------|
| SET | `SET key value [EX sec] [PX ms] [NX\|XX] [GET] [KEEPTTL]` | OK / nil | O(1) | NX=only-if-not-exists, XX=only-if-exists |
| GET | `GET key` | value / nil | O(1) | nil if missing |
| MSET | `MSET k1 v1 k2 v2 ...` | OK | O(N) | Atomic, always succeeds |
| MSETNX | `MSETNX k1 v1 k2 v2 ...` | 0 or 1 | O(N) | Atomic all-or-nothing; 0 if any key exists |
| MGET | `MGET k1 k2 ...` | array | O(N) | nil for missing keys |
| GETSET | `GETSET key newval` | old value | O(1) | **Deprecated** — use `SET key val GET` |
| GETEX | `GETEX key [EX sec\|PX ms\|EXAT ts\|PXAT ts\|PERSIST]` | value | O(1) | Get and set/remove TTL atomically |
| GETDEL | `GETDEL key` | value / nil | O(1) | Get and delete atomically |
| SETNX | `SETNX key value` | 0 or 1 | O(1) | **Deprecated** — use `SET key val NX` |
| SETEX | `SETEX key sec value` | OK | O(1) | **Deprecated** — use `SET key val EX sec` |
| INCR | `INCR key` | integer | O(1) | Creates key at 0 if missing, then +1 |
| INCRBY | `INCRBY key delta` | integer | O(1) | Negative delta = decrement |
| INCRBYFLOAT | `INCRBYFLOAT key delta` | string | O(1) | Float stored as string; imprecise accumulation |
| DECR | `DECR key` | integer | O(1) | |
| DECRBY | `DECRBY key delta` | integer | O(1) | |
| APPEND | `APPEND key value` | new length | O(1) | Creates key if missing |
| STRLEN | `STRLEN key` | integer | O(1) | Byte length, not char length |
| SETRANGE | `SETRANGE key offset value` | new length | O(1) | Zero-pads if gap |
| GETRANGE | `GETRANGE key start end` | substring | O(N) | Inclusive both ends; negative = from end |
| BITCOUNT | `BITCOUNT key [start end [BYTE\|BIT]]` | integer | O(N) | Count set bits |
| BITOP | `BITOP AND\|OR\|XOR\|NOT dest k1 [k2...]` | length | O(N) | Bitwise ops; result in dest |
| SETBIT | `SETBIT key offset 0\|1` | old bit | O(1) | offset max 2^32-1 |
| GETBIT | `GETBIT key offset` | 0 or 1 | O(1) | |
| PFADD | `PFADD key elem [elem...]` | 0 or 1 | O(N) | HyperLogLog add; 1=approx changed |
| PFCOUNT | `PFCOUNT key [key...]` | integer | O(N) | ±0.81% error |
| PFMERGE | `PFMERGE dest src [src...]` | OK | O(N) | Merge HLLs |

---

## SET Options In Full

```bash
# Basic set, overwrite existing
SET session:u1 "data"

# Set with 300s TTL
SET session:u1 "data" EX 300

# Set with millisecond TTL
SET lock:seat:A1 "user42" PX 600000

# Set ONLY if key does not exist (atomic lock acquisition)
SET lock:seat:A1 "user42" NX EX 600
# → OK   (lock acquired)
# → nil  (key existed — someone else holds lock)

# Set ONLY if key already exists
SET config:feature "enabled" XX

# Set and return OLD value atomically (replaces GETSET)
SET counter 100 GET
# → "42"  (old value returned, key now holds "100")

# Update value but preserve existing TTL
SET session:u1 "new_data" KEEPTTL
```

---

## Counter Pattern

```bash
# Atomic counter (no race condition)
INCR page:views:home          # → 1 (created at 0, incremented)
INCR page:views:home          # → 2
INCRBY page:views:home 10     # → 12
DECRBY page:views:home 5      # → 7
INCR page:views:home          # → 8

# Counter with TTL (reset after window)
SET rate:user:u1 0 EX 60
INCR rate:user:u1             # → 1  (within 60s window)

# Check-and-reset pattern
GET rate:user:u1              # read current count
# (application logic decides if over limit)
```

---

## Batch Operations

```bash
# Atomic multi-set (always succeeds)
MSET user:1:name "Alice" user:1:email "alice@example.com" user:1:age "30"

# Atomic multi-set ONLY if none exist
MSETNX user:2:name "Bob" user:2:email "bob@example.com"
# → 1 (all set)  or  0 (none set, at least one existed)

# Batch get (returns nil for missing keys)
MGET user:1:name user:1:email user:9:name
# → 1) "Alice"
#    2) "alice@example.com"
#    3) (nil)
```

---

## Read-and-Update Atomically

```bash
# Read value and extend TTL in one atomic command (Redis 6.2+)
GETEX session:u1 EX 300       # returns value, resets TTL to 300s
GETEX session:u1 PERSIST      # returns value, removes TTL
GETEX session:u1 EXAT 1735689600  # returns value, sets TTL to Unix timestamp

# Read and delete atomically
GETDEL temp:token:xyz         # returns value then deletes key
```

---

## String as Bitmap

```bash
# Set individual bits (user feature flags: bit 0=darkmode, 1=beta, 2=admin)
SETBIT user:42:flags 0 1      # enable darkmode      → old bit value
SETBIT user:42:flags 2 1      # enable admin
GETBIT user:42:flags 0        # → 1 (darkmode on)
GETBIT user:42:flags 1        # → 0 (beta off)

# Count set bits (how many features enabled?)
BITCOUNT user:42:flags        # → 2

# Count bits in byte range (bit positions 0-7 = first byte)
BITCOUNT user:42:flags 0 0 BYTE

# Daily active users: one bit per user_id per day
SETBIT dau:2026-06-06 42 1    # user 42 was active
SETBIT dau:2026-06-06 99 1    # user 99 was active
BITCOUNT dau:2026-06-06       # → 2

# Users active on BOTH days (intersection)
BITOP AND active:both dau:2026-06-05 dau:2026-06-06
BITCOUNT active:both
```

---

## HyperLogLog (Cardinality Estimation)

```bash
# Count unique visitors (approximate, ±0.81%)
PFADD visitors:2026-06-06 user1 user2 user3 user2  # user2 duplicate
PFCOUNT visitors:2026-06-06   # → 3

# Merge HLLs (weekly unique from daily HLLs)
PFMERGE visitors:week:23 visitors:2026-06-03 visitors:2026-06-04 visitors:2026-06-05
PFCOUNT visitors:week:23
```

---

## Substring / Partial Update

```bash
# Overwrite part of a string (zero-indexed offset)
SET greeting "Hello World"
SETRANGE greeting 6 "Redis"   # → 11 (length)
GET greeting                  # → "Hello Redis"

# Read a substring
GETRANGE greeting 0 4         # → "Hello"
GETRANGE greeting 6 -1        # → "Redis"  (negative = from end)
GETRANGE greeting -5 -1       # → "Redis"
```

---

## Gotchas

```
INCR on a non-integer string → ERR value is not an integer
INCRBYFLOAT result is stored as string → floating point drift on many ops
APPEND + GETRANGE = cheap byte stream, but 512MB max size
SET with NX and EX is ONE atomic command — safe for distributed locks
SETNX + EXPIRE is TWO commands — NOT atomic, do not use for locks
MSET always succeeds; MSETNX is all-or-nothing
GETRANGE on missing key returns "" (not nil)
STRLEN on missing key returns 0 (not nil)
```

---

→ **See also**: [06-key-management.md](06-key-management.md) for TTL commands | [08-transactions-scripting.md](08-transactions-scripting.md) for atomic multi-command sequences | [10-patterns-recipes.md](10-patterns-recipes.md) for rate limiter and lock patterns
