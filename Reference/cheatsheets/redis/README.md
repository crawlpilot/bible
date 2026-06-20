# Redis — Quick Reference

**Redis version coverage**: 6.2+ (sorted set unified ZRANGE), 7.0+ (sharded pub/sub), 7.2+ (ZRANK WITHSCORE)

---

## Data Types at a Glance

| Type | Internal Encoding | Typical Use Case | File |
|------|------------------|-----------------|------|
| String | raw / embstr / int | Cache, counter, lock, session token | [01-strings.md](01-strings.md) |
| Hash | listpack / hashtable | Object store, session, rate-limit fields | [02-hashes.md](02-hashes.md) |
| List | listpack / quicklist | Queue, stack, activity feed, job queue | [03-lists.md](03-lists.md) |
| Set | listpack / hashtable | Tags, unique visitors, intersection | [04-sets.md](04-sets.md) |
| Sorted Set | listpack / skiplist | Leaderboard, priority queue, time-window | [05-sorted-sets.md](05-sorted-sets.md) |
| Stream | stream (radix tree) | Durable event log, consumer groups | [07-pub-sub-streams.md](07-pub-sub-streams.md) |
| Bitmap | string (bitfield) | User flags, feature toggles, analytics | [01-strings.md](01-strings.md) |
| HyperLogLog | string | Cardinality estimation (unique count) | [01-strings.md](01-strings.md) |

---

## Connection

```bash
# Local default
redis-cli

# Remote with auth
redis-cli -h 10.0.0.1 -p 6379 -a <password>

# URL form
redis-cli -u redis://:password@host:6379/0

# Select database (0–15)
redis-cli -n 2

# TLS
redis-cli --tls --cert client.crt --key client.key --cacert ca.crt -h host -p 6380
```

---

## File Index

| File | Commands Covered |
|------|----------------|
| [01-strings.md](01-strings.md) | GET SET MGET MSET INCR DECR APPEND STRLEN GETEX GETDEL SETNX SETEX GETSET SETRANGE GETRANGE BITCOUNT BITOP PFADD PFCOUNT |
| [02-hashes.md](02-hashes.md) | HSET HGET HGETALL HMGET HDEL HEXISTS HKEYS HVALS HLEN HINCRBY HINCRBYFLOAT HSETNX HRANDFIELD HSCAN |
| [03-lists.md](03-lists.md) | LPUSH RPUSH LPOP RPOP LRANGE LLEN LINDEX LSET LINSERT LREM LTRIM LPOS LMOVE LMPOP BLPOP BRPOP |
| [04-sets.md](04-sets.md) | SADD SMEMBERS SCARD SREM SISMEMBER SMISMEMBER SINTER SINTERSTORE SUNION SUNIONSTORE SDIFF SDIFFSTORE SRANDMEMBER SPOP SSCAN SMOVE |
| [05-sorted-sets.md](05-sorted-sets.md) | ZADD ZRANGE ZRANGEBYSCORE ZRANGEBYLEX ZREVRANGE ZREVRANGEBYSCORE ZRANK ZREVRANK ZSCORE ZMSCORE ZREM ZREMRANGEBYSCORE ZREMRANGEBYRANK ZCOUNT ZLEXCOUNT ZINCRBY ZPOPMIN ZPOPMAX ZRANDMEMBER ZDIFF ZINTER ZUNION ZSCAN |
| [06-key-management.md](06-key-management.md) | DEL UNLINK EXISTS TTL PTTL EXPIRETIME PEXPIRETIME EXPIRE PEXPIRE EXPIREAT PEXPIREAT PERSIST RENAME RENAMENX TYPE OBJECT SCAN RANDOMKEY DUMP RESTORE COPY WAIT |
| [07-pub-sub-streams.md](07-pub-sub-streams.md) | SUBSCRIBE UNSUBSCRIBE PSUBSCRIBE PUNSUBSCRIBE PUBLISH PUBSUB XADD XTRIM XLEN XRANGE XREVRANGE XREAD XGROUP XREADGROUP XACK XPENDING XCLAIM XDEL XINFO |
| [08-transactions-scripting.md](08-transactions-scripting.md) | MULTI EXEC DISCARD WATCH UNWATCH EVAL EVALSHA EVALRO SCRIPT LOAD SCRIPT EXISTS SCRIPT FLUSH FCALL FUNCTION |
| [09-cli-admin.md](09-cli-admin.md) | redis-cli flags INFO CONFIG GET/SET/REWRITE DBSIZE SELECT FLUSHDB FLUSHALL DEBUG MONITOR SLOWLOG CLIENT ACL MEMORY LATENCY COMMAND RESET QUIT |
| [10-patterns-recipes.md](10-patterns-recipes.md) | Rate limiter, distributed lock, cache-aside, session store, leaderboard, pub/sub fan-out, bloom filter approximation |

---

## Key Rules (Always Remember)

```
NEVER use KEYS * in production  →  use SCAN with COUNT 100
NEVER use SELECT to switch DBs in cluster mode  →  cluster is DB 0 only
NEVER treat Redis as primary store for financial data  →  it's a cache/lock layer
SET NX EX is atomic  →  SETNX + EXPIRE is NOT (two commands)
UNLINK is async DEL  →  use for large keys to avoid blocking
```
