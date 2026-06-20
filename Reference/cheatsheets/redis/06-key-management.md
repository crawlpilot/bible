# Key Management — Redis Reference

Commands that operate on keys regardless of their type: existence, TTL, iteration, inspection, and migration.

---

## Quick Reference

| Command | Syntax | Returns | Complexity | Notes |
|---------|--------|---------|-----------|-------|
| DEL | `DEL key [key ...]` | deleted count | O(N) | Synchronous; blocks if value is large |
| UNLINK | `UNLINK key [key ...]` | deleted count | O(1) | Async delete; returns immediately |
| EXISTS | `EXISTS key [key ...]` | integer | O(N) | Count of existing keys (not 0/1 for multiple) |
| TYPE | `TYPE key` | string type | O(1) | none / string / list / set / zset / hash / stream |
| RENAME | `RENAME key newkey` | OK | O(1) | Overwrites newkey if exists |
| RENAMENX | `RENAMENX key newkey` | 0 or 1 | O(1) | Only rename if newkey does not exist |
| COPY | `COPY src dst [DB n] [REPLACE]` | 0 or 1 | O(N) | Redis 6.2+; cross-DB copy with DB option |
| TTL | `TTL key` | seconds | O(1) | -1=no TTL, -2=key missing |
| PTTL | `PTTL key` | milliseconds | O(1) | Millisecond precision |
| EXPIRETIME | `EXPIRETIME key` | Unix timestamp / -1 / -2 | O(1) | Redis 7.0+ |
| PEXPIRETIME | `PEXPIRETIME key` | Unix ms timestamp | O(1) | Redis 7.0+ |
| EXPIRE | `EXPIRE key seconds [NX\|XX\|GT\|LT]` | 0 or 1 | O(1) | Condition flags since Redis 7.0 |
| PEXPIRE | `PEXPIRE key milliseconds [NX\|XX\|GT\|LT]` | 0 or 1 | O(1) | |
| EXPIREAT | `EXPIREAT key unix-timestamp [NX\|XX\|GT\|LT]` | 0 or 1 | O(1) | |
| PEXPIREAT | `PEXPIREAT key unix-ms-timestamp [NX\|XX\|GT\|LT]` | 0 or 1 | O(1) | |
| PERSIST | `PERSIST key` | 0 or 1 | O(1) | Remove TTL; make key permanent |
| SCAN | `SCAN cursor [MATCH pat] [COUNT n] [TYPE type]` | [cursor, keys] | O(1)/call | Safe iteration — NEVER use KEYS in prod |
| KEYS | `KEYS pattern` | array | O(N) | BLOCKS Redis — dev/debug only |
| RANDOMKEY | `RANDOMKEY` | key / nil | O(1) | Random key from keyspace |
| OBJECT ENCODING | `OBJECT ENCODING key` | string | O(1) | Check internal encoding |
| OBJECT REFCOUNT | `OBJECT REFCOUNT key` | integer | O(1) | Reference count |
| OBJECT IDLETIME | `OBJECT IDLETIME key` | seconds | O(1) | Seconds since last access |
| OBJECT FREQ | `OBJECT FREQ key` | integer | O(1) | LFU frequency (requires lfu policy) |
| OBJECT HELP | `OBJECT HELP` | array | O(1) | |
| MEMORY USAGE | `MEMORY USAGE key [SAMPLES n]` | bytes | O(N) | Approx memory including overhead |
| DUMP | `DUMP key` | serialized string | O(N) | RDB serialization of a key |
| RESTORE | `RESTORE key ttl serialized [REPLACE] [ABSTTL] [IDLETIME s] [FREQ f]` | OK | O(N) | Deserialize a DUMP payload |
| WAIT | `WAIT numreplicas timeout` | integer | O(1) | Block until N replicas ack writes |
| OBJECT ENCODING | `OBJECT ENCODING key` | encoding string | O(1) | |

---

## Delete

```bash
# Synchronous delete (blocks if key holds a large list/hash/etc)
DEL user:42                         # → 1
DEL user:42 user:99 user:100        # → 3 (total deleted)
DEL nonexistent                     # → 0

# Async delete (returns immediately; memory reclaimed in background)
UNLINK session:tok_abc              # safe for large keys
UNLINK key1 key2 key3

# Check before delete (EXISTS + DEL, but not atomic — use pipeline or Lua if needed)
EXISTS user:42                      # → 1 or 0
```

---

## Existence and Type

```bash
# EXISTS counts how many of the listed keys exist
EXISTS user:42                      # → 1 or 0
EXISTS user:42 user:99 user:42      # → 3  (user:42 counted TWICE if it exists)
EXISTS user:42 user:99              # → 0, 1, or 2

# Get type
TYPE user:42                        # → "hash"
TYPE session:tok                    # → "string"
TYPE jobs:queue                     # → "list"
TYPE missing_key                    # → "none"
```

---

## TTL — Check and Set Expiry

```bash
# Read TTL
TTL  session:tok       # → 287  (seconds remaining)
TTL  permanent_key     # → -1   (no expiry set)
TTL  missing_key       # → -2   (key doesn't exist)

PTTL session:tok       # → 287341  (millisecond precision)

# Read absolute expiry Unix timestamp (Redis 7.0+)
EXPIRETIME  session:tok    # → 1717893600  (Unix seconds)
PEXPIRETIME session:tok    # → 1717893600000  (Unix ms)

# Set TTL
EXPIRE  session:tok 3600        # set 3600 second TTL → 1 (success) or 0 (key missing)
PEXPIRE session:tok 3600000     # set TTL in milliseconds
EXPIREAT  session:tok 1735689600          # expire at Unix timestamp
PEXPIREAT session:tok 1735689600000       # expire at Unix ms timestamp

# EXPIRE condition flags (Redis 7.0+)
EXPIRE key 300 NX   # set ONLY if key has no TTL currently
EXPIRE key 300 XX   # set ONLY if key already has a TTL
EXPIRE key 300 GT   # set ONLY if new TTL > current TTL (extend only)
EXPIRE key 300 LT   # set ONLY if new TTL < current TTL (shorten only)

# Remove TTL (make permanent)
PERSIST session:tok     # → 1 (TTL removed)  or  0 (key had no TTL / doesn't exist)

# Read-and-extend atomically (Strings only)
GETEX session:tok EX 3600
```

---

## SCAN — Safe Key Iteration

**Never use `KEYS *` in production.** `KEYS` blocks Redis for the entire scan (can take seconds on large keyspaces).

```bash
# Start scan (cursor = 0)
SCAN 0
# → 1) "128"              ← next cursor (0 = done)
#    2) 1) "user:42"
#       2) "session:tok"
#       3) "jobs:queue"

# Continue with returned cursor until cursor = 0
SCAN 128
SCAN 512
# ... repeat until response cursor = "0"

# Filter by pattern (glob syntax)
SCAN 0 MATCH "user:*" COUNT 100
SCAN 0 MATCH "session:*" COUNT 200

# Filter by type (Redis 6.0+)
SCAN 0 TYPE hash COUNT 100
SCAN 0 TYPE string MATCH "cache:*" COUNT 50

# COUNT is a HINT, not a guarantee — Redis may return more or fewer
# Always iterate until cursor = "0"

# Shell loop to collect all keys matching a pattern
# redis-cli --scan --pattern "user:*"
# redis-cli --scan --pattern "session:*" | wc -l   ← count matches
```

---

## KEYS — Dev/Debug Only

```bash
# NEVER in production — blocks until complete
KEYS *                     # all keys
KEYS user:*                # keys starting with "user:"
KEYS user:?                # user: + single char
KEYS user:[0-9]*           # user: + starts with digit
KEYS *:session:*           # any key with :session: in middle
```

---

## Key Inspection

```bash
# Internal encoding (affects memory usage and performance)
OBJECT ENCODING user:42        # → "listpack" or "hashtable"
OBJECT ENCODING counter        # → "int" (stored as integer, very compact)
OBJECT ENCODING big_string     # → "embstr" (≤44 bytes) or "raw" (>44 bytes)

# Encoding values per type:
# string: int | embstr | raw
# list:   listpack | quicklist
# hash:   listpack | hashtable
# set:    listpack | hashtable | intset
# zset:   listpack | skiplist

# Memory usage (approximate, includes key + value + overhead)
MEMORY USAGE user:42           # → 192  (bytes)
MEMORY USAGE big_hash          # → 4096
MEMORY USAGE key SAMPLES 0    # exact (scan all nested structures)
MEMORY USAGE key SAMPLES 5    # sample 5 nested elements (default)

# Idle time (seconds since last read/write)
OBJECT IDLETIME session:tok    # → 42  (seconds)

# LFU access frequency (only with maxmemory-policy allkeys-lfu or volatile-lfu)
OBJECT FREQ hot_key            # → 255  (max = highly accessed)
```

---

## Rename and Copy

```bash
# Rename a key (overwrites newkey if it exists)
RENAME old_key new_key         # → OK

# Rename only if newkey does NOT exist
RENAMENX old_key new_key       # → 1 (success) or 0 (newkey exists)

# Copy a key (Redis 6.2+)
COPY src_key dst_key           # → 1 (success) or 0 (dst_key exists)
COPY src_key dst_key REPLACE   # → 1 (overwrites dst_key if exists)
COPY src_key dst_key DB 1      # copy to database 1
```

---

## Migration Between Instances

```bash
# Serialize a key to binary (RDB format)
DUMP user:42                   # → "\x04\x01\x04name\x05Alice..."

# Restore on another instance
# (paste DUMP output as argument)
RESTORE user:42 0 <dump-payload>        # 0 = no TTL
RESTORE user:42 3600000 <dump-payload>  # TTL in ms
RESTORE user:42 0 <dump-payload> REPLACE  # overwrite if exists
RESTORE user:42 1735689600000 <dump-payload> ABSTTL  # absolute TTL timestamp

# Typical migration flow using redis-cli
redis-cli --pipe                # bulk insert mode
redis-cli DUMP user:42 | redis-cli -h new-host RESTORE user:42 0 -
```

---

## Replication Sync Wait

```bash
# Block until at least N replicas have acknowledged all pending writes
# Returns actual number of replicas that acked within timeout
WAIT 1 1000    # wait for 1 replica, timeout 1000ms
WAIT 0 0       # wait for all replicas, no timeout (risky)
```

---

## Key Naming Conventions

```
# Use colon as namespace separator
user:42:profile
session:tok_abc123
rate:limit:user:42
cache:show:SHOW_001:layout

# Include entity type for readability
seat_lock:SHOW_001:A1
booking:BOOKING_QRS456

# Include expiry semantics in name for self-documentation
temp:otp:user42        (implies short TTL)
perm:config:feature_flags  (implies no TTL)

# Avoid spaces, special chars except : _ -
# Keep key length < 128 bytes (memory overhead grows with key length)
```

---

## Gotchas

```
DEL key1 key1 → counts key1 twice (returns 2 if key existed)
EXISTS key1 key1 → returns 2 (counts duplicates)
RENAME to a key with a TTL: the destination's TTL is OVERWRITTEN, TTL comes from src
RENAME fails with error if src key doesn't exist
SCAN COUNT is a hint — you WILL get different counts per call; always loop to cursor=0
SCAN does not guarantee each key is returned exactly once (rare duplicates possible)
UNLINK is always preferred over DEL for large or complex values
```

---

→ **See also**: [09-cli-admin.md](09-cli-admin.md) for DBSIZE, FLUSHDB, SELECT | [08-transactions-scripting.md](08-transactions-scripting.md) for atomic key operations via Lua
