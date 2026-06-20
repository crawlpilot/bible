# Hashes — Redis Reference

A map of field→value pairs stored under one key. Efficient for objects: one Redis key = one entity (user, session, config). Fields and values are both strings.

**Encoding**: `listpack` (≤128 fields AND each value ≤64 bytes) → `hashtable` (above threshold). Listpack is far more memory-efficient.

---

## Quick Reference

| Command | Syntax | Returns | Complexity | Notes |
|---------|--------|---------|-----------|-------|
| HSET | `HSET key field val [field val ...]` | integer (added count) | O(N) | Replaces HMSET; variadic since Redis 4.0 |
| HGET | `HGET key field` | value / nil | O(1) | |
| HMGET | `HMGET key field [field ...]` | array | O(N) | nil for missing fields |
| HGETALL | `HGETALL key` | flat array [f,v,f,v...] | O(N) | Returns all field+value pairs |
| HDEL | `HDEL key field [field ...]` | integer (deleted) | O(N) | |
| HEXISTS | `HEXISTS key field` | 0 or 1 | O(1) | |
| HKEYS | `HKEYS key` | array of fields | O(N) | |
| HVALS | `HVALS key` | array of values | O(N) | |
| HLEN | `HLEN key` | integer | O(1) | Field count |
| HINCRBY | `HINCRBY key field delta` | integer | O(1) | Creates field at 0 if missing |
| HINCRBYFLOAT | `HINCRBYFLOAT key field delta` | string | O(1) | Float stored as string |
| HSETNX | `HSETNX key field value` | 0 or 1 | O(1) | Set only if field does not exist |
| HRANDFIELD | `HRANDFIELD key [count [WITHVALUES]]` | field(s) | O(N) | Negative count allows duplicates |
| HSCAN | `HSCAN key cursor [MATCH pat] [COUNT n]` | [cursor, [f,v...]] | O(1)/call | Cursor-based iteration |

---

## Core Operations

```bash
# Create / update fields (variadic — replaces HMSET)
HSET user:42 name "Alice" email "alice@ex.com" age "30" city "Mumbai"
# → 4  (number of NEW fields added; 0 if all already existed)

# Get single field
HGET user:42 name             # → "Alice"
HGET user:42 missing          # → (nil)

# Get multiple fields
HMGET user:42 name email missing
# → 1) "Alice"
#    2) "alice@ex.com"
#    3) (nil)

# Get ALL fields and values
HGETALL user:42
# → 1) "name"
#    2) "Alice"
#    3) "email"
#    4) "alice@ex.com"
#    5) "age"
#    6) "30"
#    7) "city"
#    8) "Mumbai"

# Delete fields
HDEL user:42 city             # → 1
HDEL user:42 city missing     # → 0 (city already gone)

# Check existence
HEXISTS user:42 name          # → 1
HEXISTS user:42 city          # → 0

# Count fields
HLEN user:42                  # → 3
```

---

## Counters in a Hash

```bash
# Atomic increment (creates field at 0 if not present)
HINCRBY stats:2026-06-06 page_views 1      # → 1
HINCRBY stats:2026-06-06 page_views 1      # → 2
HINCRBY stats:2026-06-06 signups 5         # → 5
HINCRBY stats:2026-06-06 page_views -10    # → -8 (decrement)

# Float increment
HINCRBYFLOAT product:99 avg_rating 4.5     # → "4.5"
HINCRBYFLOAT product:99 avg_rating 3.7     # → "8.2"

# Get all counters at once
HGETALL stats:2026-06-06
```

---

## Conditional Field Set

```bash
# Set field ONLY if it does not exist (like SET NX for a field)
HSETNX session:abc user_id "42"    # → 1 (set)
HSETNX session:abc user_id "99"    # → 0 (field exists, no change)
HGET session:abc user_id           # → "42"
```

---

## Keys / Values Only

```bash
HKEYS user:42     # → 1) "name"  2) "email"  3) "age"
HVALS user:42     # → 1) "Alice" 2) "alice@ex.com" 3) "30"
```

---

## Random Field Sampling

```bash
# Get 2 random fields
HRANDFIELD user:42 2
# → 1) "name"
#    2) "age"

# Get 2 random fields WITH values
HRANDFIELD user:42 2 WITHVALUES
# → 1) "age"
#    2) "30"
#    3) "email"
#    4) "alice@ex.com"

# Negative count: allow duplicates (useful for weighted sampling)
HRANDFIELD user:42 -5     # may return same field multiple times
```

---

## Scanning Large Hashes

Use `HSCAN` instead of `HGETALL` when a hash has thousands of fields (avoids blocking).

```bash
# First call: cursor = 0
HSCAN metrics:counters 0 COUNT 100
# → 1) "128"          ← next cursor (non-zero = more to fetch)
#    2) 1) "field1"
#       2) "val1"
#       3) "field2"
#       4) "val2"

# Continue with returned cursor
HSCAN metrics:counters 128 COUNT 100

# Filter by pattern
HSCAN metrics:counters 0 MATCH "page:*" COUNT 100

# Loop until cursor returns 0 (full iteration complete)
# cursor=0 on response means done
```

---

## Session Store Pattern

```bash
# Store session as hash (one key = one session)
HSET session:tok_abc123 \
  user_id    "42" \
  username   "alice" \
  role       "admin" \
  created_at "1717890000" \
  ip         "10.0.0.1"

# Set TTL on the entire hash key
EXPIRE session:tok_abc123 3600

# Read specific fields on each request
HMGET session:tok_abc123 user_id role

# Extend session on activity
EXPIRE session:tok_abc123 3600

# Destroy session
DEL session:tok_abc123
```

---

## Memory Encoding Notes

```bash
# Check current encoding
OBJECT ENCODING user:42
# → "listpack"   (≤128 fields, all values ≤64 bytes)
# → "hashtable"  (above threshold)

# listpack is 3-5× more memory-efficient than hashtable
# Threshold config (redis.conf):
#   hash-max-listpack-entries 128
#   hash-max-listpack-value   64
# Tune down if memory is critical; tune up if fields are many

# Check memory usage of one key
MEMORY USAGE user:42
# → 192  (bytes, approximate including key overhead)
```

---

## Gotchas

```
HGETALL on a hash with 100K fields blocks Redis — use HSCAN instead
HMSET is deprecated since Redis 4.0 — use variadic HSET
HINCRBY only works on integer strings — HINCRBYFLOAT for decimals
Deleting all fields does NOT delete the key — use DEL key
Hash TTL is on the KEY, not individual fields — no per-field expiry
HSETNX returns 0 (not nil) when field exists — unlike GET returning nil
Field names are case-sensitive: "Name" ≠ "name"
```

---

→ **See also**: [06-key-management.md](06-key-management.md) for EXPIRE on the hash key | [08-transactions-scripting.md](08-transactions-scripting.md) for atomic hash + other operations | [10-patterns-recipes.md](10-patterns-recipes.md) for session store pattern
