# Lists — Redis Reference

Ordered sequence of strings. Insertion order preserved. Elements can repeat. Supports O(1) push/pop from both ends — ideal for queues, stacks, and activity feeds.

**Encoding**: `listpack` (≤128 elements AND each ≤64 bytes) → `quicklist` (above threshold, a linked list of listpacks).

---

## Quick Reference

| Command | Syntax | Returns | Complexity | Notes |
|---------|--------|---------|-----------|-------|
| LPUSH | `LPUSH key val [val ...]` | new length | O(N) | Prepend; multiple vals pushed left-to-right |
| RPUSH | `RPUSH key val [val ...]` | new length | O(N) | Append; creates key if missing |
| LPUSHX | `LPUSHX key val [val ...]` | new length / 0 | O(N) | Only if key exists |
| RPUSHX | `RPUSHX key val [val ...]` | new length / 0 | O(N) | Only if key exists |
| LPOP | `LPOP key [count]` | value / array / nil | O(N) | count param since Redis 6.2 |
| RPOP | `RPOP key [count]` | value / array / nil | O(N) | |
| LRANGE | `LRANGE key start stop` | array | O(S+N) | Inclusive both ends; -1 = last element |
| LLEN | `LLEN key` | integer | O(1) | 0 for missing key |
| LINDEX | `LINDEX key index` | value / nil | O(N) | 0=head, -1=tail; O(N) traversal |
| LSET | `LSET key index value` | OK | O(N) | Error if index out of range |
| LINSERT | `LINSERT key BEFORE\|AFTER pivot value` | new length / -1 | O(N) | -1 = pivot not found |
| LREM | `LREM key count value` | removed count | O(N+M) | count>0=from head, <0=from tail, 0=all |
| LTRIM | `LTRIM key start stop` | OK | O(N) | Keeps only [start,stop]; deletes rest |
| LPOS | `LPOS key element [RANK r] [COUNT n] [MAXLEN m]` | index / array / nil | O(N) | Redis 6.0.6+ |
| LMOVE | `LMOVE src dst LEFT\|RIGHT LEFT\|RIGHT` | element | O(1) | Atomic pop+push; Redis 6.2+ |
| LMPOP | `LMPOP numkeys key [key...] LEFT\|RIGHT [COUNT n]` | [key,[vals]] / nil | O(S+N) | Redis 7.0+ |
| BLPOP | `BLPOP key [key ...] timeout` | [key, val] / nil | O(N) | Blocking pop; 0 timeout = wait forever |
| BRPOP | `BRPOP key [key ...] timeout` | [key, val] / nil | O(N) | Blocking pop from tail |
| BLMOVE | `BLMOVE src dst LEFT\|RIGHT LEFT\|RIGHT timeout` | element / nil | O(1) | Blocking LMOVE |

---

## Push and Pop

```bash
# Queue: RPUSH to enqueue at tail, LPOP to dequeue from head
RPUSH jobs "job1" "job2" "job3"   # → 3
LPOP  jobs                         # → "job1"
LPOP  jobs 2                       # → 1) "job2"  2) "job3"  (pop 2 at once, Redis 6.2+)

# Stack: LPUSH to push, LPOP to pop
LPUSH stack "a" "b" "c"           # "c" is now at head
LPOP  stack                        # → "c"
LPOP  stack                        # → "b"

# Only push if key already exists
LPUSHX missing_key "val"          # → 0 (key doesn't exist, nothing pushed)
RPUSHX missing_key "val"          # → 0

# Pop multiple elements at once
RPOP notifications 5              # returns up to 5 elements from tail
```

---

## Range / Inspect

```bash
RPUSH feed "post1" "post2" "post3" "post4" "post5"

# Get all elements
LRANGE feed 0 -1
# → 1) "post1"  2) "post2"  3) "post3"  4) "post4"  5) "post5"

# Pagination: get elements 0–9 (first page)
LRANGE feed 0 9

# Last 3 elements
LRANGE feed -3 -1

# List length
LLEN feed                         # → 5

# Get element by index (O(N) — avoid in hot path for large lists)
LINDEX feed 0                     # → "post1"  (head)
LINDEX feed -1                    # → "post5"  (tail)
LINDEX feed 99                    # → (nil)
```

---

## Trim — Keep Only a Window

```bash
# Keep only the 100 most recent items (cap the list)
RPUSH activity_feed "event1"
LTRIM activity_feed -100 -1       # discard everything older than last 100
# Pattern: RPUSH then immediately LTRIM is idiomatic for capped feeds

# Trim to first 3 elements
LTRIM feed 0 2
LRANGE feed 0 -1                  # → post1, post2, post3 (post4, post5 gone)
```

---

## Search and Modify

```bash
# Find position of element
LPOS feed "post2"                 # → 1 (index)
LPOS feed "missing"               # → (nil)
LPOS feed "post2" COUNT 0         # → [1] (all occurrences, 0=all)
LPOS feed "post2" RANK 2          # find 2nd occurrence
LPOS feed "post2" MAXLEN 10       # only scan first 10 elements

# Remove occurrences of a value
RPUSH dupes "a" "b" "a" "c" "a"
LREM dupes 2 "a"                  # remove first 2 "a" from head → 2 removed
LREM dupes -1 "a"                 # remove last 1 "a" from tail
LREM dupes 0 "a"                  # remove ALL "a"

# Insert before or after a pivot value
LINSERT feed BEFORE "post2" "post1.5"   # insert before post2
LINSERT feed AFTER  "post2" "post2.5"   # insert after post2
# returns -1 if pivot not found

# Update element at index
LSET feed 0 "new_post1"
```

---

## Reliable Queue — LMOVE

Problem with `LPOP`: if worker crashes after pop but before processing, the job is lost.

```bash
# LMOVE atomically moves head of queue → processing list
LMOVE jobs processing LEFT LEFT     # pop from jobs head, push to processing head
# → "job1"  (atomically moved)

# Worker processes job1...
# On success: remove from processing
LREM processing 1 "job1"

# On crash: job1 remains in processing list for recovery
# Recovery job: LRANGE processing 0 -1 → re-queue stale items

# Blocking version (wait for a job to appear)
BLMOVE jobs processing LEFT LEFT 30  # wait up to 30s
```

---

## Blocking Consumers

```bash
# Wait for an item to appear in any of the listed keys (worker pattern)
BLPOP queue:high queue:medium queue:low 5
# → 1) "queue:high"   ← which key had data
#    2) "job_abc"
# Checks keys in order; blocks up to 5 seconds; returns nil on timeout

# 0 timeout = block forever (careful with connection limits)
BLPOP jobs 0

# Broadcast pattern: BRPOP for multiple consumers on same list (they race)
BRPOP shared_queue 10
```

---

## Activity Feed Pattern

```bash
# Append events, cap at 1000 items
RPUSH feed:user:42 '{"type":"like","post":99,"ts":1717890000}'
LTRIM feed:user:42 -1000 -1     # keep last 1000 only

# Read latest 20 events (most recent at tail)
LRANGE feed:user:42 -20 -1

# Read page 2 (events 20–39 from the end)
LRANGE feed:user:42 -40 -21
```

---

## Gotchas

```
LPUSH "a" "b" "c" pushes in order c→b→a (last arg ends up at head)
  LRANGE → [c, b, a]  — may surprise if you expect insertion order
LRANGE on missing key returns empty array (not nil)
LINDEX is O(N) — for frequent random access use Sorted Sets instead
BLPOP with multiple keys: Redis checks keys left-to-right, serves first non-empty
BLPOP/BRPOP hold a connection — use a dedicated connection pool for blocking ops
LMOVE src == dst rotates the list (valid, move from head to tail = rotate)
Key deleted automatically when last element is popped
```

---

→ **See also**: [05-sorted-sets.md](05-sorted-sets.md) for priority queues | [07-pub-sub-streams.md](07-pub-sub-streams.md) for durable consumer groups | [10-patterns-recipes.md](10-patterns-recipes.md) for reliable queue recipe
