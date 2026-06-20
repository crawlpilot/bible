# ZooKeeper — Tuning Guide

## Critical Configuration Parameters

### `zoo.cfg` Core Parameters

```properties
# ─── Timing ───────────────────────────────────────────────────────────────────
tickTime=2000
# Base time unit in ms. All timeouts derived from this.
# Rule: don't raise above 2000 ms. Lower (1000 ms) if you need faster session
# expiry detection. Raising inflates session timeout range unnecessarily.

initLimit=10
# How many ticks a follower can take to connect to and sync with the leader
# during initial sync after a leader election.
# Default: 10 ticks × tickTime = 20 s
# Raise if ensemble is on high-latency links or has a large dataset (slow SNAP transfer)
# Formula: initLimit × tickTime > max snapshot transfer time

syncLimit=5
# How many ticks a follower can lag behind the leader during steady-state
# before being dropped from the ensemble.
# Default: 5 ticks × tickTime = 10 s
# Raise if cross-AZ latency is high (> 50 ms round-trip)
# Lower if you want faster follower eviction on network issues

# ─── Data Directories ─────────────────────────────────────────────────────────
dataDir=/var/lib/zookeeper/data
# Snapshot files + myid + epoch files
# Use a dedicated disk/volume

dataLogDir=/var/lib/zookeeper/log
# TRANSACTION LOG — MUST be on a separate, dedicated SSD
# This is on the hot write path (fsync on every committed write)
# Sharing this with other I/O WILL cause write latency spikes

# ─── Client Connectivity ──────────────────────────────────────────────────────
clientPort=2181
maxClientCnxns=1000
# Max concurrent connections from a single client IP.
# Default: 60. Raise for high client-density deployments.
# Set to 0 to remove the limit (risky — can exhaust server threads)

# ─── Session Timeouts ─────────────────────────────────────────────────────────
minSessionTimeout=4000     # 2 × tickTime (minimum)
maxSessionTimeout=40000    # 20 × tickTime (maximum)
# Clients negotiate within this range.
# Critical: maxSessionTimeout must be > typical leader election duration
# Typical leader election: 200 ms – 2 s
# Recommended: maxSessionTimeout = 30,000–60,000 ms

# ─── Snapshot / Purge ─────────────────────────────────────────────────────────
snapCount=100000
# Trigger a new snapshot every N transactions.
# Lower (10,000–50,000) for faster restart recovery (smaller transaction replay)
# Higher (100,000) reduces snapshot I/O but increases recovery time on crash

autopurge.snapRetainCount=5
# Number of most recent snapshots + transaction logs to retain
# 3 is absolute minimum; 5–10 recommended for safety

autopurge.purgeInterval=24
# Hours between automatic purge runs
# Set to 1–6 for busy ensembles generating many snapshots
# 0 = disable autopurge (then you must run zkCleanup.sh manually)

# ─── Ensemble ─────────────────────────────────────────────────────────────────
server.1=zk1.internal:2888:3888
server.2=zk2.internal:2888:3888
server.3=zk3.internal:2888:3888
# Port 2888: follower-to-leader data channel
# Port 3888: leader election port

# ─── Observers ────────────────────────────────────────────────────────────────
# peerType=observer  (in observer's zoo.cfg)
# server.4=zk4.internal:2888:3888:observer  (in all servers' zoo.cfg)
# Observers do not vote; they scale read throughput without increasing quorum size
```

---

## JVM Tuning

ZooKeeper is a Java application and requires careful JVM configuration. The entire dataset lives in heap, so GC pauses directly translate to session timeouts.

### Recommended JVM Flags (ZooKeeper 3.6+, Java 11+)

```bash
# Set in zkServer.sh or JAVA_OPTS environment variable

# Heap size: rule of thumb = 2–4× the expected dataset size
# Typical production: 4–8 GB
-Xms4g -Xmx4g
# Always set Xms = Xmx to prevent heap resizing overhead

# Use G1GC (default in Java 11+, good for large heaps)
-XX:+UseG1GC
-XX:MaxGCPauseMillis=100
# Target GC pause time. ZooKeeper sessions can expire on GC pauses > sessionTimeout.
# For tickTime=2000 and minSessionTimeout=4000 ms, GC pauses > 4 s cause cascading expirations.

-XX:G1HeapRegionSize=16m
# Larger regions reduce region count for large heaps

-XX:+ParallelRefProcEnabled
-XX:+DisableExplicitGC
# Prevent System.gc() calls from disrupting the ensemble

# GC logging (essential for diagnosing session expiry issues)
-Xlog:gc*:file=/var/log/zookeeper/gc.log:time,level,tags:filecount=10,filesize=20m

# JMX for monitoring
-Dcom.sun.management.jmxremote
-Dcom.sun.management.jmxremote.port=9999
-Dcom.sun.management.jmxremote.authenticate=false
-Dcom.sun.management.jmxremote.ssl=false
```

### Heap Sizing Guidelines

| Dataset Size | Heap | Notes |
|-------------|------|-------|
| < 500 MB | 2 GB | Development / light production |
| 500 MB – 2 GB | 4 GB | Standard production |
| 2 GB – 5 GB | 8–12 GB | Large production; monitor GC |
| > 5 GB | Reconsider design | Data model is wrong if > 5 GB in ZooKeeper |

**Rule**: Never let heap utilisation exceed 60% at steady state. ZooKeeper's snapshot serialisation creates a spike in allocation; headroom prevents triggering a full GC during snapshot.

---

## Key Metrics to Monitor

### Server-Level Metrics (via `mntr` four-letter command or JMX)

```bash
# Four-letter commands (enable with 4lw.commands.whitelist=mntr,stat,ruok,dump in zoo.cfg)
echo mntr | nc zk1.internal 2181
```

| Metric | Meaning | Alert Threshold |
|--------|---------|----------------|
| `zk_avg_latency` | Average processing latency (ms) | > 10 ms warning |
| `zk_max_latency` | Max single-operation latency (ms) | > 100 ms critical |
| `zk_outstanding_requests` | Requests queued waiting for processing | > 100 warning; > 1000 critical |
| `zk_watch_count` | Total active watches across all sessions | > 1M — investigate |
| `zk_ephemerals_count` | Total ephemeral nodes | Baseline + alert on unexpected spikes (mass reconnects) |
| `zk_approximate_data_size` | Bytes of data in DataTree | Alert if > 70% of heap |
| `zk_open_file_descriptor_count` | Open FDs | > 80% of `ulimit -n` → increase ulimit |
| `zk_followers` | Number of followers (leader reports this) | Should equal N-1; 0 means isolated leader |
| `zk_synced_followers` | Followers caught up to leader | < `zk_followers` = replication lag |
| `zk_pending_syncs` | Outstanding snapshot transfers | > 0 means a follower is catching up |
| `zk_leader_uptime` | Seconds since last leader election | Track election frequency |

### Session and Watch Metrics (via `dump` command)

```bash
echo dump | nc zk1.internal 2181
# Lists all sessions and their ephemeral nodes
# Useful for debugging: finding zombie sessions, orphaned ephemeral nodes
```

---

## Anti-Patterns

### Anti-Pattern 1: Storing Application Data in ZooKeeper

```
WRONG:
  /user-profiles/user-123 → { full 4 KB user object as JSON }
  /products/sku-456      → { 10 KB product catalogue entry }

WHY IT FAILS:
  - All data is in RAM on every node — 100K users × 4 KB = 400 MB minimum
  - GC pressure from large DataTree → session timeouts
  - Node max size (1 MB default) may be hit

RIGHT:
  /user-profiles/user-123 → { "dbId": "123", "cacheKey": "user:123" }
  Store actual data in PostgreSQL/DynamoDB; ZooKeeper holds only pointer/coordination state
```

### Anti-Pattern 2: Unbounded Watch Accumulation

```
WRONG: Registering watches in a loop without checking for accumulation
  for (String node : nodes) {
      zk.getData(node, myWatcher, null); // each re-fires and re-registers forever
  }

RISK: 1M+ watches per ensemble → memory and CPU overhead for watch dispatch

RIGHT: Use Curator's caching abstractions (NodeCache, PathChildrenCache)
which manage the watch lifecycle correctly. Or periodically audit watch count
via `echo mntr | nc zkhost 2181 | grep zk_watch_count`
```

### Anti-Pattern 3: Sequential ZooKeeper Reads in Hot Path

```
WRONG: Every request to a microservice reads config from ZooKeeper
  public String getConfig(String key) {
      return new String(zk.getData("/config/" + key, false, null)); // called on every API request
  }

WHY: 1000 req/sec × 1 ms ZK read = adds 1 ms to every request; ZK gets 1000 reads/sec;
     if ZK has a GC pause, all in-flight API requests hang

RIGHT: Cache ZooKeeper data locally. Subscribe to watch for changes; reload on notification.
  private volatile Map<String, String> configCache;
  private void reloadConfig() {
      // called once at startup and on watch notification
      configCache = fetchAllConfig(); // single ZK read
  }
```

### Anti-Pattern 4: Using ZooKeeper Across Geographies Without Observers

```
WRONG: quorum = [us-east, eu-west, ap-south] — every write needs round-trips to all 3 DCs

LATENCY: us-east ↔ eu-west = ~90 ms; us-east ↔ ap-south = ~170 ms
         Write latency dominated by slowest quorum member: > 170 ms for every write

RIGHT: Keep quorum within a single DC or close AZs; add observers in remote DCs for reads
  zoo.cfg:
    server.1=zk-us1:2888:3888   # quorum member
    server.2=zk-us2:2888:3888   # quorum member
    server.3=zk-us3:2888:3888   # quorum member
    server.4=zk-eu1:2888:3888:observer  # observer, no vote
    server.5=zk-ap1:2888:3888:observer  # observer, no vote
```

### Anti-Pattern 5: Small Session Timeout

```
WRONG: sessionTimeout=2000 ms (2 seconds)

RISK: Leader election typically takes 200 ms – 2 s.
     With 2 s session timeout, sessions MAY expire during every leader election.
     Result: cascade of ephemeral node deletions → service deregistrations → reconnect storms

RIGHT: sessionTimeout = max(30,000 ms, 10× typical leader election time)
       maxSessionTimeout=60000 in zoo.cfg
       Let client request 30,000 ms or 60,000 ms
```

### Anti-Pattern 6: Running Even-Numbered Ensembles

```
WRONG: 4-node ensemble

WHY: A 4-node ensemble requires quorum of 3 (not 2) for safety.
     Tolerates only 1 failure — same as a 3-node ensemble.
     But you're paying for 4 nodes. No benefit over 3.

  2 nodes fail → quorum lost, same as 3-node ensemble
  Net result: more machines, more operational overhead, same fault tolerance

RIGHT: Always use odd numbers (3, 5, 7). If you want to tolerate 2 failures, use 5 nodes.
```

---

## OS / Infrastructure Tuning

```bash
# File descriptor limits (each client connection = 1 FD + files for txn log/snapshots)
# In /etc/security/limits.conf or systemd unit:
zookeeper soft nofile 65536
zookeeper hard nofile 65536

# Network buffer sizes (important for high client counts)
# In /etc/sysctl.conf:
net.core.somaxconn=65536          # listen backlog
net.ipv4.tcp_max_syn_backlog=65536
net.core.rmem_max=134217728
net.core.wmem_max=134217728

# Disable swap — ZooKeeper must not swap; swapping = GC pause = session timeouts
vm.swappiness=0
# Or use: swapoff -a

# Use deadline or noop I/O scheduler for SSD dataLogDir
echo deadline > /sys/block/nvme0n1/queue/scheduler

# NTP/chrony must be running and accurate (within 1 ms) on all ensemble nodes
# Clock skew causes false leader elections
```

---

## Production Checklist

| Item | Value / Setting | Why |
|------|----------------|-----|
| Ensemble size | 3 or 5 (odd only) | Quorum requires majority |
| `dataLogDir` | Dedicated SSD, separate volume | fsync on hot write path |
| `tickTime` | 2000 ms | Standard; lower only if you need < 4 s min session timeout |
| `maxSessionTimeout` | 60,000 ms (30–60 s) | Must exceed leader election duration |
| `snapCount` | 10,000–50,000 | Balance between I/O and recovery time |
| `autopurge.snapRetainCount` | 5 | Keep 5 snapshots for rollback |
| `autopurge.purgeInterval` | 1–6 hours | Prevent disk exhaustion |
| JVM heap | 4–8 GB (Xms = Xmx) | Prevent resizing; accommodate DataTree |
| GC algorithm | G1GC, MaxGCPauseMillis=100 | Keep GC pauses < minSessionTimeout |
| Swap | Disabled | Swapping = session timeouts |
| Client library | Apache Curator | Handles reconnection, watch re-registration |
| Monitoring | `mntr` + `zk_outstanding_requests` alert | Detect overload before cascades |
| Log retention | 5 snapshots + corresponding logs | Avoid manual cleanup emergencies |

---

## FAANG Interview Callout

> "The most common ZooKeeper production failure is session expiry cascades caused by either a GC pause or an undersized session timeout. If the JVM pauses for more than the session timeout, all ephemeral nodes are deleted — service registrations, acquired locks, leader assignments — and you get a thundering herd of reconnects. Prevention: set Xms=Xmx to avoid heap resizing, use G1GC with MaxGCPauseMillis=100, set session timeout to at least 30 seconds, and always put the transaction log on a dedicated SSD. The second most common failure is disk full — ZooKeeper doesn't stop generating transaction logs, and without autopurge or a monitoring alert on disk usage, you'll fill the disk and crash the ensemble."
