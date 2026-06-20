# Elasticsearch — Tuning Guide

## JVM Heap Sizing

### The 50% Rule

```
Available RAM: 64 GB
ES Heap:       32 GB   (50% of RAM)
OS page cache: 32 GB   (remaining 50% — DO NOT steal this)

Why: Lucene relies heavily on the OS page cache to memory-map segment files.
     Giving ES more than 50% of RAM starves the page cache and forces disk reads.
```

### The 32 GB Ceiling

```
Heap < 32 GB:  JVM uses compressed ordinary object pointers (OOPs) → 4 bytes per reference
Heap ≥ 32 GB:  JVM switches to full 64-bit pointers → 8 bytes per reference + 30–40% more GC pressure

If you need more than 32 GB ES heap: use two nodes instead of one large node.
```

### Recommended Heap Settings

```bash
# /etc/elasticsearch/jvm.options
-Xms31g
-Xmx31g    # Always set Xms == Xmx to prevent heap resizing pauses

# NEVER exceed 50% of physical RAM
# NEVER exceed ~31 GB (leave headroom below compressed OOP boundary)
```

---

## Key Index-Level Settings

### Indexing Performance

| Setting | Default | Recommended (Bulk Load) | Explanation |
|---------|---------|------------------------|-------------|
| `index.refresh_interval` | `1s` | `-1` (disable during load) | Disable refresh to prevent per-second segment creation; re-enable after |
| `index.number_of_replicas` | `1` | `0` (during initial load) | Skip replication overhead; set to 1+ after load |
| `index.translog.durability` | `request` | `async` (during load) | Skip fsync per-write; risk: lose last 5s on crash |
| `index.translog.sync_interval` | `5s` | `60s` (during load) | Reduce fsync frequency |
| `index.merge.scheduler.max_thread_count` | `max(1, min(4, CPU/2))` | `1` on spinning disk, higher on SSD | Concurrent merges |
| `index.codec` | `default` | `best_compression` (cold indices) | LZ4 vs. DEFLATE; 25–35% space saving at 10–15% CPU cost |

### Shard and Segment Settings

| Setting | Default | Recommended | Explanation |
|---------|---------|-------------|-------------|
| `index.number_of_shards` | `1` (since 7.0) | `ceil(total_GB / 30)` | Primary shard count — fixed after creation |
| `index.number_of_replicas` | `1` | `1` (production) | One replica = 1 failure tolerance + 2× read throughput |
| `index.merge.policy.max_merged_segment` | `5gb` | `5gb`–`10gb` | Cap on max merged segment size |
| `index.merge.policy.segments_per_tier` | `10` | `5` (read-heavy) | Fewer segments = faster search; more merges during indexing |

---

## Cluster-Level Settings

```yaml
# elasticsearch.yml

# Memory locking — prevent ES heap from being swapped to disk
bootstrap.memory_lock: true
# Verify in Linux: ulimit -l unlimited; /etc/security/limits.conf: elasticsearch - memlock unlimited

# Thread pool sizing (default is usually correct; tune if profiling shows queue buildup)
thread_pool.write.queue_size: 1000    # Default 200; increase for burst indexing
thread_pool.search.queue_size: 1000   # Default 1000

# Shard allocation throttling (prevent recovery from saturating network)
cluster.routing.allocation.node_concurrent_recoveries: 2   # Default 2
indices.recovery.max_bytes_per_sec: 40mb                   # Default 40mb; raise on 10GbE

# Shard rebalancing (prevent too-aggressive rebalancing during rolling restarts)
cluster.routing.allocation.cluster_concurrent_rebalance: 2
```

---

## Index Lifecycle Management (ILM)

ILM is the production standard for time-series indices (logs, metrics, events). It automates the hot-warm-cold-delete tiering:

```
┌──────────────────────────────────────────────────────────────────────┐
│                         ILM Phases                                   │
│                                                                      │
│  HOT              WARM              COLD               DELETE        │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐         ┌───────┐    │
│  │ Active   │ →  │ Read-    │ →  │ Frozen / │  →      │ Drop  │    │
│  │ indexing │    │ only,    │    │ searchable│         │ index │    │
│  │ (SSD,    │    │ merged   │    │ on object │         │       │    │
│  │ replica) │    │ segments │    │ storage   │         └───────┘    │
│  │          │    │ (SSD or  │    │ (cold     │                      │
│  │ rollover │    │ HDD)     │    │ storage)  │                      │
│  │ at 50GB  │    │          │    │           │                      │
│  └──────────┘    └──────────┘    └──────────┘                      │
│    0–7 days        7–30 days       30–90 days         > 90 days     │
└──────────────────────────────────────────────────────────────────────┘
```

**ILM policy example (logs)**:
```json
PUT /_ilm/policy/logs-policy
{
  "policy": {
    "phases": {
      "hot": {
        "actions": {
          "rollover": { "max_size": "50gb", "max_age": "1d" },
          "set_priority": { "priority": 100 }
        }
      },
      "warm": {
        "min_age": "7d",
        "actions": {
          "shrink": { "number_of_shards": 1 },
          "forcemerge": { "max_num_segments": 1 },
          "set_priority": { "priority": 50 }
        }
      },
      "cold": {
        "min_age": "30d",
        "actions": {
          "freeze": {},
          "set_priority": { "priority": 0 }
        }
      },
      "delete": {
        "min_age": "90d",
        "actions": { "delete": {} }
      }
    }
  }
}
```

**Key ILM actions**:
- `rollover`: Creates a new index when size/age threshold hit; old index becomes read-only
- `shrink`: Reduces primary shard count (useful for warm: 10 shards → 1 shard)
- `forcemerge`: Collapses to 1 segment per shard (maximises read efficiency, removes tombstones)
- `freeze`: Closes file handles; index still searchable but requires extra heap on access

---

## Monitoring Metrics

### Must-Watch Metrics

| Metric | Healthy Range | Alert Threshold | What It Means |
|--------|:--------------|:---------------|---------------|
| **JVM Heap Used %** | < 75% | > 85% | GC pressure imminent; risk of OOM |
| **GC Old Gen Collection Duration** | < 200ms | > 500ms / frequent | Major GC pauses affect latency; heap too small or fielddata bloat |
| **Search Latency (p99)** | < 200ms | > 1s | Too many shards, large segments, or missing doc values |
| **Indexing Rate (docs/s)** | Per capacity plan | < 50% of baseline | Possible merge throttling or JVM GC stop |
| **Merge Time** | Low | Spikes during high write | Segments accumulating; consider throttling or reducing refresh rate |
| **Pending Tasks** | 0–5 | > 50 | Master node overloaded; dynamic mapping or shard allocation storm |
| **Unassigned Shards** | 0 | > 0 | Shard in red state; node failure or disk full |
| **Fielddata Cache Size** | < 20% heap | > 40% heap | fielddata on text fields accumulating; GC risk |
| **Rejected Indexing Requests** | 0 | > 0 | Write thread pool queue full; bulk indexing too fast |

---

## Anti-Patterns

### 1. Mapping Explosion
```
Symptom: Cluster goes red; master OOM; "max total fields limit exceeded"
Cause:   Dynamic mapping + user-generated field names (e.g., logging JSON with arbitrary keys)
Fix:     
  - Set "dynamic": "strict" in mappings
  - Use "dynamic": "false" for unknown sub-objects
  - Flatten log data to known schema before indexing
  - Raise index.mapping.total_fields.limit only as last resort (> 1000 is a smell)
```

### 2. Over-Sharding (Shard Proliferation)
```
Symptom: Slow cluster state updates; high GC; search latency increases despite low data volume
Cause:   Too many small indices (e.g., 1 index per hour for logs) with default 1 shard each
Fix:     
  - Use ILM with rollover (daily indices, not hourly)
  - Use data streams (ES 7.9+) — auto-managed time-series with rollover
  - Target: ≤ 20 shards per GB of heap
```

### 3. Large Heap with Old GC
```
Symptom: Stop-the-world GC pauses > 5s; cluster loses master heartbeat → node ejected
Cause:   > 32 GB heap + high fielddata + large aggregations
Fix:     
  - Cap heap at 31 GB
  - Use G1GC (default in ES 7.0+): -XX:+UseG1GC
  - For ES on JDK 17+: ZGC is an option for sub-ms GC pauses (experimental in ES)
  - Eliminate fielddata on text fields; use keyword sub-fields
```

### 4. Updating Documents Frequently
```
Symptom: High merge pressure; segment count spikes; disk write amplification
Cause:   ES updates are delete + re-index at the Lucene level
Fix:     
  - For counters/state that update frequently, pre-aggregate before indexing
  - Use Elasticsearch update_by_query sparingly; prefer full re-indexing for bulk updates
  - Consider Cassandra or Redis for high-update entities; sync to ES periodically
```

### 5. Using _source: false
```
Symptom: Cannot re-index, cannot update fields, cannot run expensive re-index migrations
Cause:   Disabling _source saves disk but loses the original document
Fix:     
  - Only disable _source on metrics/analytics indices that are never re-indexed and never updated
  - Use includes/excludes in _source to store partial documents if space is critical
```

### 6. Not Setting replica=0 During Initial Bulk Load
```
Symptom: Bulk indexing at 20% of expected speed; replicas receiving same data in parallel
Fix:     
  PUT /my-index/_settings { "index.number_of_replicas": 0 }
  // bulk load
  PUT /my-index/_settings { "index.number_of_replicas": 1 }
  // Wait for green before opening to traffic
```

### 7. Scroll API in Production Applications
```
Symptom: Heap pressure on data nodes; "context missing" errors; scroll timeout storms
Cause:   Scroll keeps a snapshot of shard state in memory per active scroll context
Fix:     Replace Scroll with PIT (Point In Time) + search_after for pagination
         Scroll is appropriate only for offline export / re-indexing jobs, not user-facing pagination
```

---

## FAANG Interview Callout: Tuning

**What interviewers test**: Do you know the real operational knobs, not just "scale horizontally"?

**What to say on the 50% heap rule**: "Elasticsearch uses Lucene, which memory-maps segment files via the OS page cache. If you allocate more than 50% of RAM to the JVM heap, you starve the page cache. A warm page cache means Lucene reads from RAM. A cold page cache means disk I/O on every query. I've seen clusters go from 200ms to 20ms p99 search latency just by reducing heap from 60% to 50% of RAM and letting the OS cache the hot segments."

**Tuning story for interviewers**: "During a bulk re-index of 500M documents, I disabled refresh (set to -1), set replicas to 0, and used the bulk API with 10MB batch sizes and 8 parallel threads. This raised throughput from 80K docs/min to 1.2M docs/min — a 15× improvement. After load, I re-enabled refresh and replicas, force-merged each shard to 1 segment, and ran a health check before cutting traffic. The full re-index took 7 hours instead of the original estimate of 4 days."
