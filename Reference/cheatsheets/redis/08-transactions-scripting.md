# Transactions & Scripting — Redis Reference

Two mechanisms for multi-command atomicity:
- **MULTI/EXEC**: Queue commands, execute as a block. Optimistic CAS with WATCH.
- **EVAL / Lua**: Single atomic script. More flexible. The standard for complex atomic operations.

---

## MULTI / EXEC Quick Reference

| Command | Syntax | Returns | Notes |
|---------|--------|---------|-------|
| MULTI | `MULTI` | OK | Begin transaction block |
| EXEC | `EXEC` | array of replies / nil | Execute queued commands; nil if WATCH triggered |
| DISCARD | `DISCARD` | OK | Abandon queued commands |
| WATCH | `WATCH key [key ...]` | OK | Optimistic lock: abort EXEC if any watched key changed |
| UNWATCH | `UNWATCH` | OK | Cancel all watches |

---

## Lua / EVAL Quick Reference

| Command | Syntax | Returns | Notes |
|---------|--------|---------|-------|
| EVAL | `EVAL script numkeys [key...] [arg...]` | script result | Execute Lua script atomically |
| EVALSHA | `EVALSHA sha1 numkeys [key...] [arg...]` | script result | Execute cached script by SHA |
| EVALRO | `EVALRO script numkeys [key...] [arg...]` | script result | Redis 7.0+; read-only script |
| SCRIPT LOAD | `SCRIPT LOAD script` | sha1 | Cache script without executing |
| SCRIPT EXISTS | `SCRIPT EXISTS sha1 [sha1...]` | array of 0/1 | Check if cached |
| SCRIPT FLUSH | `SCRIPT FLUSH [ASYNC\|SYNC]` | OK | Clear script cache |
| SCRIPT DEBUG | `SCRIPT DEBUG YES\|SYNC\|NO` | OK | Enable Lua debugger |
| FCALL | `FCALL func numkeys [key...] [arg...]` | result | Redis 7.0+ Functions API |
| FUNCTION LOAD | `FUNCTION LOAD [REPLACE] lib-payload` | lib name | Redis 7.0+ load a library |
| FUNCTION LIST | `FUNCTION LIST [LIBRARYNAME pat] [WITHCODE]` | info | Redis 7.0+ |
| FUNCTION DELETE | `FUNCTION DELETE lib-name` | OK | Redis 7.0+ |
| FUNCTION DUMP | `FUNCTION DUMP` | binary | Redis 7.0+ export |
| FUNCTION RESTORE | `FUNCTION RESTORE payload [FLUSH\|APPEND\|REPLACE]` | OK | Redis 7.0+ import |

---

## MULTI / EXEC Basics

```bash
# Simple transaction (no WATCH)
MULTI
SET counter 0
INCR counter
INCR counter
GET counter
EXEC
# → 1) OK
#    2) (integer) 1
#    3) (integer) 2
#    4) "2"

# Abandon transaction
MULTI
SET foo "bar"
DISCARD           # → OK; no commands executed

# Error inside EXEC: other commands still run
MULTI
SET str_key "hello"
INCR str_key      # will fail (not an integer) — queued regardless
INCR counter      # will succeed
EXEC
# → 1) OK
#    2) (error) ERR value is not an integer...
#    3) (integer) 3
# EXEC always runs ALL queued commands; individual errors don't abort the block
```

---

## WATCH — Optimistic CAS (Compare-And-Swap)

WATCH turns EXEC into conditional: if any watched key changed between WATCH and EXEC, EXEC returns nil (aborted).

```bash
# Pattern: read → modify → write with conflict detection
WATCH balance:user42
current = GET balance:user42      # read current value

MULTI
SET balance:user42 (current - 100)   # modify
EXEC
# → array of replies  (success — key not changed between WATCH and EXEC)
# → nil               (abort — someone else changed balance:user42)

# On nil (conflict): retry the whole flow
# 1. WATCH again
# 2. GET again
# 3. MULTI → commands → EXEC
# Typical retry loop: 3–5 attempts with exponential backoff

# UNWATCH to cancel watches without EXEC/DISCARD
WATCH key1 key2
UNWATCH          # cancel all watches (e.g., decided not to transact)
```

---

## EVAL — Lua Scripting

Lua scripts are **atomic**: no other Redis command executes between the first and last line of the script. No WATCH needed — no concurrent modification possible.

```lua
-- Script syntax:
-- KEYS[1], KEYS[2], ... = the key arguments
-- ARGV[1], ARGV[2], ... = the non-key arguments
-- redis.call() = execute a Redis command (errors propagate)
-- redis.pcall() = execute, catch errors (returns error table)
-- return = what EVAL returns to the caller
```

```bash
# Simplest EVAL
EVAL "return 'hello'" 0
# → "hello"

# With keys and args
EVAL "return redis.call('GET', KEYS[1])" 1 mykey
# → value of mykey

# SET + EXPIRE atomically (not normally atomic together)
EVAL "
  redis.call('SET', KEYS[1], ARGV[1])
  redis.call('EXPIRE', KEYS[1], ARGV[2])
  return 1
" 1 session:tok "user_data" 3600
# → 1

# Conditional set: set value if key doesn't exist, else return existing
EVAL "
  local val = redis.call('GET', KEYS[1])
  if val then
    return val
  end
  redis.call('SET', KEYS[1], ARGV[1])
  return ARGV[1]
" 1 mykey "default_value"
```

---

## EVALSHA — Use Cached Scripts

Loading a script gives you its SHA1 hash. Use EVALSHA in production to avoid sending the script text on every call.

```bash
# Load script and get SHA
SCRIPT LOAD "return redis.call('GET', KEYS[1])"
# → "e0e1f9fabfa9d353e5f33d1af1e9e4a9d4a5b2c1"

# Use by SHA (no script text sent over network)
EVALSHA e0e1f9fabfa9d353e5f33d1af1e9e4a9d4a5b2c1 1 mykey

# Check if script is cached
SCRIPT EXISTS e0e1f9fabfa9d353e5f33d1af1e9e4a9d4a5b2c1
# → 1) 1   (cached)
# → 1) 0   (not cached — after SCRIPT FLUSH or Redis restart)

# If NOSCRIPT error: fall back to EVAL, then EVALSHA again
# Scripts survive restart via AOF (if SCRIPT LOAD was AOF-logged) — not guaranteed
# Best practice: always have fallback to EVAL
```

---

## Production Lua Patterns

### Atomic Distributed Lock Acquire

```bash
EVAL "
  if redis.call('SET', KEYS[1], ARGV[1], 'NX', 'EX', ARGV[2]) then
    return 1
  else
    return 0
  end
" 1 lock:seat:SHOW001:A1 "booking_id_xyz" 600
# → 1 (lock acquired)
# → 0 (lock already held)
```

### Atomic Distributed Lock Release (Only by Owner)

```bash
EVAL "
  if redis.call('GET', KEYS[1]) == ARGV[1] then
    return redis.call('DEL', KEYS[1])
  else
    return 0
  end
" 1 lock:seat:SHOW001:A1 "booking_id_xyz"
# → 1 (released — we were the owner)
# → 0 (not released — someone else owns it or key expired)
# CRITICAL: always pass the owner ID to prevent releasing another owner's lock
```

### Atomic Multi-Seat Lock (All-or-Nothing)

```lua
-- Lock N seats atomically; if any is already locked, release all acquired locks
local seats = KEYS
local user_id = ARGV[1]
local ttl = tonumber(ARGV[2])

-- Phase 1: check all seats are free
for i = 1, #seats do
    if redis.call('EXISTS', seats[i]) == 1 then
        -- Seat already locked — release any we already locked in a previous call
        -- (This script is called fresh each time; we check before setting)
        return 0
    end
end

-- Phase 2: acquire all (atomically — no other command can run between these)
for i = 1, #seats do
    redis.call('SET', seats[i], user_id, 'EX', ttl)
end

return 1
```

```bash
EVAL "<above script>" 3 \
  lock:seat:SHOW001:A1 lock:seat:SHOW001:A2 lock:seat:SHOW001:A3 \
  "booking_xyz" 600
# → 1 (all 3 locked)
# → 0 (at least one was locked; none were set)
```

### Atomic Rate Limiter (Fixed Window)

```bash
EVAL "
  local current = redis.call('INCR', KEYS[1])
  if current == 1 then
    redis.call('EXPIRE', KEYS[1], ARGV[1])
  end
  if current > tonumber(ARGV[2]) then
    return 0
  end
  return 1
" 1 rate:user:42 60 100
# ARGV[1]=60 (window seconds), ARGV[2]=100 (max requests)
# → 1 (allowed)
# → 0 (rate limit exceeded)
```

### Atomic Counter with Max (for seat reservation count)

```bash
EVAL "
  local count = redis.call('GET', KEYS[1])
  if count == false then count = 0 else count = tonumber(count) end
  if count >= tonumber(ARGV[1]) then
    return -1   -- at capacity
  end
  return redis.call('INCR', KEYS[1])
" 1 seat_count:SHOW001 200
# → -1 (show full: 200 already reserved)
# → N  (new count after increment)
```

---

## Lua: Redis Call Reference

```lua
-- Call with error propagation (raises error on Redis error reply)
redis.call('SET', KEYS[1], ARGV[1])

-- Call with error capture (returns {err="..."} table on error)
local ok, err = pcall(redis.call, 'SET', KEYS[1], ARGV[1])

-- Return types from Redis commands:
--   Strings → Lua string
--   Integers → Lua number
--   Arrays  → Lua table
--   Nil     → Lua false  (NOT nil)
--   Errors  → Lua error (with redis.call) or {err=...} (with pcall)

-- redis.status_reply() and redis.error_reply() for custom return types
return redis.status_reply("OK")
return redis.error_reply("ERR invalid argument")

-- Logging (only visible with SCRIPT DEBUG or in Redis log at debug level)
redis.log(redis.LOG_WARNING, "Something went wrong: " .. tostring(val))

-- Time (not affected by system clock changes)
local time = redis.call('TIME')   -- returns {seconds, microseconds}
```

---

## MULTI vs EVAL — Which to Use?

| Concern | MULTI/EXEC | EVAL Lua |
|---------|-----------|----------|
| **Atomicity** | Yes (no interleaving) | Yes (no interleaving) |
| **Conditional logic** | Requires WATCH + retry | Native if/else |
| **Loop over N keys** | No | Yes |
| **Error handling** | Partial exec on command errors | Full control via pcall |
| **Network round-trips** | 3 min (MULTI + commands + EXEC) | 1 (everything in one call) |
| **Readability** | Simple sequences | Better for complex logic |
| **Cluster support** | All keys must be in same slot | All KEYS[] must be in same slot |
| **Best for** | Simple atomic multi-key sets | Locking, CAS, rate limiting, complex logic |

**Rule of thumb**: Use MULTI/EXEC for simple "do these 3 things together". Use EVAL when you need `if`, loops, or read-then-write atomically.

---

## Gotchas

```
MULTI queues commands but does NOT execute them — no rollback on EXEC error
Individual command errors in EXEC don't abort the transaction (unlike SQL)
WATCH is connection-scoped — a DISCARD/EXEC/error clears all watches
EVAL: all KEYS[] must hash to the same cluster slot in cluster mode
EVAL: avoid blocking commands (BLPOP etc.) inside a script — blocks all of Redis
EVAL: script timeout defaults to 5s (lua-time-limit) — kills long-running scripts
EVALSHA NOSCRIPT error = script not in cache; always have EVAL fallback
Lua numbers are doubles — safe up to 2^53 for integers
```

---

→ **See also**: [10-patterns-recipes.md](10-patterns-recipes.md) for complete lock/rate-limiter/leaderboard recipes | [06-key-management.md](06-key-management.md) for key TTL commands used in scripts
