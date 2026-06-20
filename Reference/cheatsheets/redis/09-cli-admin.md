# CLI & Admin — Redis Reference

`redis-cli` flags, server inspection, configuration, monitoring, and operational commands.

---

## redis-cli Connection Flags

```bash
redis-cli                              # local, default port 6379, db 0
redis-cli -h 10.0.0.1                 # remote host
redis-cli -p 6380                     # non-default port
redis-cli -n 2                        # database number (0–15)
redis-cli -a mypassword               # password (shows in ps — use env var instead)
redis-cli --no-auth-warning           # suppress "Warning: Using a password..." message
redis-cli -u redis://:pass@host:6379/0  # URI form (cleaner for scripts)

# TLS
redis-cli --tls \
  --cert client.crt \
  --key  client.key \
  --cacert ca.crt \
  -h redis.example.com -p 6380

# Execute a single command and exit (useful in scripts)
redis-cli GET mykey
redis-cli SET mykey "val" EX 300
redis-cli -n 1 FLUSHDB               # flush db 1

# Pipe input (bulk load)
echo -e "*3\r\n\$3\r\nSET\r\n\$3\r\nfoo\r\n\$3\r\nbar\r\n" | redis-cli --pipe

# Interactive mode with prompt showing db number
redis-cli --prompt "%h:%p[%n]> "
```

---

## Scan / Iterate from CLI

```bash
# Safe key listing (never use KEYS in production)
redis-cli --scan                      # all keys
redis-cli --scan --pattern "user:*"   # filtered
redis-cli --scan --pattern "user:*" | wc -l   # count

# Count keys in current database
redis-cli DBSIZE

# All keys with TTL (pipeline output)
redis-cli --scan --pattern "*" | xargs -L 1 -I {} redis-cli TTL {}
```

---

## INFO — Server Statistics

```bash
# All sections
redis-cli INFO

# Specific sections
redis-cli INFO server          # version, OS, uptime, executable
redis-cli INFO clients         # connected_clients, blocked, tracking
redis-cli INFO memory          # used_memory, rss, peak, fragmentation
redis-cli INFO stats           # total_commands, keyspace_hits, misses, evictions
redis-cli INFO replication     # role, master/replica info, replication offset
redis-cli INFO keyspace        # per-database key count and TTL stats
redis-cli INFO cpu             # user/system CPU usage
redis-cli INFO commandstats    # per-command call count and latency
redis-cli INFO latencystats    # latency distribution (requires latency-tracking yes)
redis-cli INFO persistence     # RDB and AOF state
redis-cli INFO cluster         # cluster_enabled, cluster_state
```

### Key INFO Fields

```
# INFO memory
used_memory: 2097152              # bytes allocated by Redis
used_memory_human: 2.00M
used_memory_rss: 4194304          # bytes from OS perspective (includes fragmentation)
mem_fragmentation_ratio: 2.00     # rss/used; >1.5 = high fragmentation
maxmemory: 0                      # 0 = no limit
maxmemory_policy: noeviction

# INFO stats
total_commands_processed: 1234567
keyspace_hits: 900000             # cache hits
keyspace_misses: 100000           # cache misses
hit_rate = hits / (hits + misses) = 90%
evicted_keys: 0                   # keys evicted due to maxmemory
expired_keys: 4321                # keys removed by TTL

# INFO replication
role: master
connected_slaves: 2
slave0: ip=10.0.0.2,port=6379,state=online,offset=12345,lag=0
master_repl_offset: 12345
repl_backlog_size: 1048576
```

---

## CONFIG — Live Configuration

```bash
# Get a config value
CONFIG GET maxmemory
CONFIG GET save
CONFIG GET maxmemory-policy
CONFIG GET hash-max-listpack-entries
CONFIG GET *                      # all config params

# Set config value at runtime (no restart needed)
CONFIG SET maxmemory 2gb
CONFIG SET maxmemory-policy allkeys-lru
CONFIG SET hash-max-listpack-entries 128
CONFIG SET hash-max-listpack-value 64
CONFIG SET slowlog-log-slower-than 10000    # log commands > 10ms
CONFIG SET slowlog-max-len 128

# Persist runtime changes to redis.conf
CONFIG REWRITE                    # writes current config back to conf file

# Reset stats
CONFIG RESETSTAT                  # resets keyspace hits/misses, evictions, etc.
```

---

## SLOWLOG — Slow Command Log

```bash
# How many slow commands logged
CONFIG SET slowlog-log-slower-than 10000   # threshold: 10ms (microseconds unit)
CONFIG SET slowlog-max-len 128

# Read slow log (most recent first)
SLOWLOG GET                       # all entries
SLOWLOG GET 10                    # last 10

# Each entry:
# 1) (integer) 14                 ← unique ID
# 2) (integer) 1717890000         ← Unix timestamp
# 3) (integer) 15234              ← execution time in MICROSECONDS
# 4) 1) "KEYS"                   ← command + args
#    2) "*"

# Length of slow log
SLOWLOG LEN

# Reset slow log
SLOWLOG RESET
```

---

## MONITOR — Live Command Stream

```bash
# Stream every command received (DEBUG ONLY — severe performance impact)
redis-cli MONITOR

# Filter output (pipe through grep)
redis-cli MONITOR | grep "XADD"

# Stop with Ctrl+C
# NEVER leave MONITOR running in production — it copies every command to the monitoring client
```

---

## LATENCY — Latency Analysis

```bash
# Enable latency monitoring
CONFIG SET latency-monitor-threshold 10    # ms threshold

# Show latest latency event per event type
LATENCY LATEST
# → 1) 1) "command"
#       2) (integer) 1717890000  ← timestamp
#       3) (integer) 15          ← latest event latency (ms)
#       4) (integer) 45          ← max ever

# Show history for an event type
LATENCY HISTORY command

# Reset latency stats
LATENCY RESET

# Text graph of latency
LATENCY GRAPH command
```

---

## CLIENT — Connection Management

```bash
# List all connected clients
CLIENT LIST
# Each line: id=1 addr=127.0.0.1:52345 fd=8 name= age=0 idle=0 flags=N
#            db=0 sub=0 psub=0 multi=-1 watch=0 qbuf=0 obl=0 oll=0 omem=0
#            events=r cmd=client|list user=default lib-name= lib-ver=

# Name current connection (useful for CLIENT LIST identification)
CLIENT SETNAME myworker
CLIENT GETNAME

# Kill a client connection
CLIENT KILL ID 5                    # by client ID
CLIENT KILL ADDR 10.0.0.1:52345    # by address
CLIENT KILL LADDR 0.0.0.0:6379 ID 5  # by local address + ID

# Count connected clients
CLIENT NO-EVICT ON                  # prevent this client from being evicted
CLIENT NO-TOUCH ON                  # don't update LRU/LFU on this client's access
CLIENT INFO                         # info about current connection

# Pause all client commands (for maintenance window)
CLIENT PAUSE 5000                   # pause non-admin clients for 5 seconds
CLIENT UNPAUSE
```

---

## ACL — Access Control Lists

```bash
# List ACL rules
ACL LIST
# → user default on nopass ~* &* +@all

# Show current user info
ACL WHOAMI                          # → "default"

# Get ACL info for a user
ACL GETUSER default
ACL GETUSER myuser

# Create/update a user
ACL SETUSER readonly on >password ~cache:* +GET +MGET
# on=enabled, >password=password, ~cache:*=key pattern, +GET +MGET=allowed commands

ACL SETUSER writer on >password ~user:* +SET +GET +HSET +HGET
ACL SETUSER admin on >adminpass allkeys allcommands  # full access

# Delete a user
ACL DELUSER myuser

# List all users
ACL USERS

# Log authentication failures
ACL LOG                             # view recent failures
ACL LOG RESET

# Save ACL to file (if using aclfile config)
ACL SAVE
ACL LOAD                            # reload from file
```

---

## Database Selection and Flush

```bash
# Select database (0–15); only for standalone — not supported in cluster
SELECT 1
SELECT 0

# Count keys in current database
DBSIZE

# Flush current database (irreversible)
FLUSHDB               # synchronous
FLUSHDB ASYNC         # async (returns immediately; flush in background)

# Flush ALL databases (all 0–15)
FLUSHALL
FLUSHALL ASYNC

# Move a key to another database
MOVE mykey 2          # move to DB 2; fails if key exists in DB 2
```

---

## MEMORY — Detailed Memory Analysis

```bash
# Memory usage summary
MEMORY USAGE key                    # bytes for a single key
MEMORY USAGE key SAMPLES 0         # exact (traverse entire value)

# Full memory report
MEMORY DOCTOR                       # diagnostic report
MEMORY STATS                        # detailed stats dict

# Defragmentation (active defrag must be enabled in config)
CONFIG SET activedefrag yes
CONFIG SET active-defrag-ignore-bytes 100mb
CONFIG SET active-defrag-threshold-lower 10   # start at 10% fragmentation
MEMORY PURGE                        # trigger jemalloc purge manually
```

---

## COMMAND — Command Introspection

```bash
# List all commands
COMMAND                             # full list with arity, flags, complexity
COMMAND COUNT                       # → 246 (total commands)

# Get info about specific commands
COMMAND INFO get set hset zadd
# → command name, arity, flags, first/last/step key positions

# Find commands that touch certain keys
COMMAND GETKEYS SET mykey value    # → 1) "mykey"
COMMAND GETKEYS MSET k1 v1 k2 v2  # → 1) "k1"  2) "k2"

# List commands by category
COMMAND DOCS set                    # Redis 7.0+: full documentation for a command
```

---

## DEBUG (use with extreme caution)

```bash
# Simulate OOM
DEBUG OOM

# Force a segfault crash (testing only)
DEBUG SEGFAULT

# Sleep for N seconds (testing slow command path)
DEBUG SLEEP 5

# Get detailed info about a key's internals
DEBUG OBJECT mykey
# → Value at: 0x... refcount:1 encoding:embstr serializedlength:5 lru:... lru_seconds_idle:0

# Reload RDB from disk (for testing persistence)
DEBUG RELOAD
DEBUG LOADAOF
```

---

## RESET — Connection Reset

```bash
# Reset connection to initial state (Redis 6.2+)
# Exits sub/pub mode, clears MULTI, resets AUTH, sets db=0
RESET
```

---

## Common One-Liners

```bash
# Count all keys
redis-cli DBSIZE

# Find keys by pattern safely
redis-cli --scan --pattern "session:*"

# Delete all keys matching pattern (careful!)
redis-cli --scan --pattern "temp:*" | xargs redis-cli DEL

# Check memory per key (top 10 largest)
redis-cli --scan | xargs -L 1 redis-cli MEMORY USAGE | sort -n | tail -10

# Monitor hit rate
redis-cli INFO stats | grep -E "keyspace_hits|keyspace_misses"

# Check replication lag
redis-cli INFO replication | grep "lag"

# Flush slowlog and watch for slow commands
redis-cli SLOWLOG RESET
redis-cli SLOWLOG GET 20

# Live command monitor with filter
redis-cli MONITOR | grep --line-buffered "EVAL"

# Get all config
redis-cli CONFIG GET "*" | paste - -

# Benchmark
redis-benchmark -h localhost -p 6379 -c 50 -n 100000 -t set,get
```

---

→ **See also**: [06-key-management.md](06-key-management.md) for key-level commands | [08-transactions-scripting.md](08-transactions-scripting.md) for EVAL | [10-patterns-recipes.md](10-patterns-recipes.md) for operational recipes
