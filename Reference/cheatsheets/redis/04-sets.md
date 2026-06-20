# Sets — Redis Reference

Unordered collection of unique strings. No duplicates, no guaranteed order. O(1) membership test. Ideal for tags, unique visitors, group membership, and set math.

**Encoding**: `listpack` (≤128 members AND each ≤64 bytes) → `hashtable` (above threshold).

---

## Quick Reference

| Command | Syntax | Returns | Complexity | Notes |
|---------|--------|---------|-----------|-------|
| SADD | `SADD key member [member ...]` | added count | O(N) | Duplicate members silently ignored |
| SREM | `SREM key member [member ...]` | removed count | O(N) | |
| SMEMBERS | `SMEMBERS key` | set of all members | O(N) | Avoid on large sets — use SSCAN |
| SCARD | `SCARD key` | integer | O(1) | Set cardinality (size) |
| SISMEMBER | `SISMEMBER key member` | 0 or 1 | O(1) | |
| SMISMEMBER | `SMISMEMBER key member [member ...]` | array of 0/1 | O(N) | Redis 6.2+ batch membership check |
| SPOP | `SPOP key [count]` | member(s) / nil | O(N) | Remove and return random members |
| SRANDMEMBER | `SRANDMEMBER key [count]` | member(s) / nil | O(N) | Return without removing; neg count=allow dups |
| SMOVE | `SMOVE src dst member` | 0 or 1 | O(1) | Atomic move from src to dst |
| SINTER | `SINTER key [key ...]` | set | O(N×M) | Intersection |
| SINTERSTORE | `SINTERSTORE dst key [key ...]` | count | O(N×M) | Store result in dst |
| SINTERCARD | `SINTERCARD numkeys key [key...] [LIMIT n]` | integer | O(N×M) | Count of intersection; Redis 7.0+ |
| SUNION | `SUNION key [key ...]` | set | O(N) | Union |
| SUNIONSTORE | `SUNIONSTORE dst key [key ...]` | count | O(N) | Store result in dst |
| SDIFF | `SDIFF key [key ...]` | set | O(N) | Difference: first key minus rest |
| SDIFFSTORE | `SDIFFSTORE dst key [key ...]` | count | O(N) | Store result in dst |
| SSCAN | `SSCAN key cursor [MATCH pat] [COUNT n]` | [cursor, members] | O(1)/call | Cursor-based iteration |

---

## Core Operations

```bash
# Add members (duplicates ignored)
SADD tags:post:1 "redis" "database" "cache"   # → 3
SADD tags:post:1 "redis"                       # → 0  (already exists)

# Remove members
SREM tags:post:1 "cache"                       # → 1
SREM tags:post:1 "missing"                     # → 0

# Check membership
SISMEMBER tags:post:1 "redis"                  # → 1
SISMEMBER tags:post:1 "cache"                  # → 0

# Batch membership check (Redis 6.2+)
SMISMEMBER tags:post:1 "redis" "database" "cache"
# → 1) 1   2) 1   3) 0

# Get all members (only for small/bounded sets)
SMEMBERS tags:post:1
# → 1) "redis"  2) "database"

# Count members
SCARD tags:post:1                              # → 2
```

---

## Set Math

```bash
SADD devs:team:alpha "alice" "bob" "carol"
SADD devs:team:beta  "bob" "dave" "carol"
SADD devs:team:gamma "alice" "eve"

# Intersection: members in ALL sets
SINTER devs:team:alpha devs:team:beta
# → 1) "bob"  2) "carol"

# Union: members in ANY set
SUNION devs:team:alpha devs:team:beta
# → alice, bob, carol, dave

# Difference: in first set but NOT in others
SDIFF devs:team:alpha devs:team:beta
# → alice, carol  (members of alpha not in beta)

SDIFF devs:team:beta devs:team:alpha
# → dave  (members of beta not in alpha)

# Store result for reuse
SINTERSTORE devs:team:overlap devs:team:alpha devs:team:beta
SCARD devs:team:overlap        # → 2

SUNIONSTORE devs:all devs:team:alpha devs:team:beta devs:team:gamma
SCARD devs:all                 # → 5

# Count intersection without fetching members (Redis 7.0+)
SINTERCARD 2 devs:team:alpha devs:team:beta          # → 2
SINTERCARD 2 devs:team:alpha devs:team:beta LIMIT 1  # → 1  (stop counting at 1)
```

---

## Random Sampling

```bash
SADD pool "a" "b" "c" "d" "e"

# Return 2 random members WITHOUT removing them
SRANDMEMBER pool 2            # → e.g. "b" "d"  (unique, no duplicates)

# Negative count: MAY return duplicates (draws with replacement)
SRANDMEMBER pool -7           # → 7 members, may repeat

# Remove and return 1 random member (dequeue randomly)
SPOP pool                     # → "c" (and removes it)

# Remove and return 3 random members
SPOP pool 3                   # → "a" "e" "b" (and removes them)
```

---

## Atomic Move

```bash
# Move a member from one set to another atomically
SADD pending "task1" "task2"
SMOVE pending processing "task1"   # → 1 (moved)
SMEMBERS pending                   # → "task2"
SMEMBERS processing                # → "task1"

# Returns 0 if member doesn't exist in src (no-op)
SMOVE pending processing "missing" # → 0
```

---

## Scanning Large Sets

```bash
# Never use SMEMBERS on a set with millions of members
# Use SSCAN for safe iteration

SSCAN tags:global 0 COUNT 100
# → 1) "384"              ← next cursor
#    2) 1) "redis"
#       2) "database"
#       ...

SSCAN tags:global 384 MATCH "red*" COUNT 100
# Continue until cursor returns "0"
```

---

## Unique Visitor Counting

```bash
# Track unique visitors per day
SADD visitors:2026-06-06 "user:42" "user:99" "user:42"  # → 2 (dup ignored)
SCARD visitors:2026-06-06    # → 2

# Weekly uniques: union of daily sets
SUNIONSTORE visitors:week:23 \
  visitors:2026-06-03 visitors:2026-06-04 \
  visitors:2026-06-05 visitors:2026-06-06
SCARD visitors:week:23       # total weekly unique visitors

# Were two users both active today AND yesterday? (intersection)
SINTERCARD 2 visitors:2026-06-05 visitors:2026-06-06
```

---

## Tags / Multi-label Index

```bash
# Index posts by tag
SADD tag:redis  "post:1" "post:3" "post:7"
SADD tag:kafka  "post:2" "post:3" "post:9"
SADD tag:system "post:1" "post:7" "post:9"

# Find posts tagged BOTH redis AND kafka
SINTER tag:redis tag:kafka
# → "post:3"

# Find posts tagged redis OR kafka
SUNION tag:redis tag:kafka

# Find posts tagged redis but NOT kafka
SDIFF tag:redis tag:kafka
# → "post:1" "post:7"
```

---

## Gotchas

```
SMEMBERS on a large set blocks Redis — use SSCAN for sets > 10K members
SRANDMEMBER positive count returns UNIQUE members (sample without replacement)
SRANDMEMBER negative count may return DUPLICATES (sample with replacement)
SPOP is destructive — use SRANDMEMBER if you want to keep the member
SDIFF order matters: SDIFF A B ≠ SDIFF B A
SUNIONSTORE/SINTERSTORE/SDIFFSTORE overwrites dst if it exists
Set is deleted automatically when last member is removed
```

---

→ **See also**: [05-sorted-sets.md](05-sorted-sets.md) for ordered unique collections | [01-strings.md](01-strings.md) for bitmap-based membership at massive scale | [10-patterns-recipes.md](10-patterns-recipes.md) for tag index pattern
