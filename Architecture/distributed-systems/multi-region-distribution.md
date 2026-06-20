# Multi-Region Distribution

## The Core Problem (Start Here)

You've built a successful US-based service. Your EU users complain about 200ms latency (transatlantic round-trip). Then your US data center goes down for 2 hours — and all EU users lose access entirely. You also get a legal notice: GDPR requires that EU user data must not leave EU territory.

Three problems, all requiring multi-region architecture. But multi-region is hard:

```
Single-region (current state):
  EU User ────────────── 200ms ──────────────► US Data Center
                                                  [DB Master]
                                                  [API Servers]

Problem 1: latency — 200ms just to reach the server
Problem 2: availability — US outage = global outage
Problem 3: compliance — EU data stored in US = GDPR violation

Multi-region (desired state):
  EU User ──5ms──► EU Region         US User ──5ms──► US Region
                    [DB Replica]                         [DB Master]
                   ◄─── async replication (lag: 10-100ms) ────────
```

---

## Deployment Topologies

### Active-Passive (Single Master)

One region handles all writes. Other regions serve reads from replicas.

```
                       ┌──────────────────┐
                       │   US-East (Primary)│
     ┌─────────────────│   ● DB Master      │─────────────────┐
     │                 │   ● App Servers    │                 │
     │                 └──────────────────┘                 │
     │ async replication                    async replication│
     ▼                                                        ▼
┌──────────────────┐                              ┌──────────────────┐
│  EU-West (Replica) │                              │ AP-Southeast (Replica) │
│  ● DB Replica      │                              │  ● DB Replica    │
│  ● App Servers     │                              │  ● App Servers   │
│  READ ONLY         │                              │  READ ONLY       │
└──────────────────┘                              └──────────────────┘

Writes: All go to US-East (even from EU)
Reads: Served from nearest region (stale by replication lag)
```

**RPO (Recovery Point Objective):** How much data can you lose if primary fails?
- = replication lag at time of failure
- Async replication lag: typically 10–100ms at steady state
- Under heavy write load or network partition: can reach seconds/minutes

**RTO (Recovery Time Objective):** How long until you're back online after primary fails?
- Manual failover: 15–60 minutes (human decision required)
- Automated failover: 30 seconds – 5 minutes (tools: AWS RDS Multi-AZ, PgBouncer + Patroni, Route 53 health checks)

**Warm standby vs cold standby:**
| | Cold Standby | Warm Standby | Hot Standby |
|---|---|---|---|
| Replica running? | No | Yes, not serving traffic | Yes, serving reads |
| Failover time | 30–60 min | 5–15 min | 30s – 2 min |
| Cost | Low | Medium | High (full replica fleet) |
| Data loss risk | High | Low | Very low |

---

### Active-Active (Multi-Master)

All regions accept writes. Requires conflict resolution.

```
┌──────────────────┐       bidirectional       ┌──────────────────┐
│   US-East        │◄─── async replication ───►│   EU-West        │
│   ● DB Master    │                           │   ● DB Master    │
│   ● App Servers  │                           │   ● App Servers  │
│   READS+WRITES   │                           │   READS+WRITES   │
└──────────────────┘                           └──────────────────┘
```

**The core challenge: Write conflicts**

User updates their profile simultaneously in US and EU:
```
Time 0: User profile = { name: "Alice", country: "US" }

US write at T=100ms: { name: "Alice Smith", country: "US" }
EU write at T=120ms: { name: "Alice",       country: "DE" }

Which wins? You can't merge field-by-field easily — partial merge creates { name: "Alice Smith", country: "DE" } which neither user intended.
```

Conflict resolution strategies (in order of sophistication):
1. **Last Write Wins (LWW):** Choose by timestamp → requires synchronized clocks (dangerous — see `time-and-causality.md`)
2. **Region priority:** Designate US-East as "wins all conflicts" → unfair, business logic dependent
3. **Application-level merge:** Application defines merge function per data type
4. **CRDTs:** Mathematically conflict-free data structures (see `crdts-and-conflict-resolution.md`)
5. **Operational transformation:** Used by Google Docs, complex to implement

---

### Single-Region Writes + Global Reads (The Common Middle Ground)

Most companies start here. All writes go to one "home" region per user or per entity:

```
EU User:
  Writes → nearest write master in EU → async replication to all regions
  Reads  → any region (stale by lag)

US User:
  Writes → nearest write master in US → async replication to all regions  
  Reads  → any region (stale by lag)
```

**Routing by user "home" region:**
```python
def get_write_endpoint(user_id: str) -> str:
    region = user_profile.home_region(user_id)  # stored at signup
    return MASTER_ENDPOINTS[region]

def get_read_endpoint(request_context) -> str:
    nearest = geoip.nearest_region(request_context.ip)
    return REPLICA_ENDPOINTS[nearest]  # may return stale data
```

**Stale read problem:** After a user writes, they immediately read — but their read hits a replica that hasn't replicated the write yet. Common fix: **read-your-writes consistency** via session tracking:

```python
# After write, record the write LSN (log sequence number)
session.last_write_lsn = db.write(data)

# On subsequent read, ensure replica is caught up
def read(session):
    replica = get_nearest_replica()
    replica.wait_for_lsn(session.last_write_lsn, timeout_ms=500)  # wait up to 500ms
    return replica.read(...)
```

---

## Synchronous vs Asynchronous Replication

| | Synchronous | Asynchronous |
|---|---|---|
| Write latency | Write waits for replica ACK → adds round-trip (~10–100ms per region) | No wait → same as single-region |
| Durability | Data confirmed in N regions before ACK | Data may be lost if primary fails before replica catches up |
| Availability | Write blocked if any sync replica is down | Write succeeds even if replicas are behind |
| Use case | Financial data, strong consistency required | Social media, eventual consistency OK |
| Production example | Synchronous standby in PostgreSQL, Google Spanner | MySQL async replication, DynamoDB Global Tables |

**Semi-synchronous:** One replica is synchronous; others are async. Ensures data in 2 regions (durable) while limiting latency impact.

---

## Multi-Region Consensus

For strongly consistent multi-region systems (e.g., financial ledgers), you need consensus across regions. This is expensive but necessary.

### Cross-Region Quorum

A 3-region Raft/Paxos cluster (e.g., US-East, EU-West, AP-Southeast) requires a majority quorum (2/3). A write is committed when 2 regions acknowledge it:

```
Leader: US-East
  Write: Append to log
  Send to: EU-West and AP-Southeast in parallel

EU-West ACK: 20ms  ← first ACK → quorum! commit write
AP-Southeast ACK: 180ms ← second ACK (arrives later, already committed)

Client latency: 20ms (US→EU) + processing ≈ 50–70ms total
```

**Problem:** If you need ACK from regions in different continents:
- US-East to EU-West: ~80ms RTT
- US-East to AP-Southeast: ~180ms RTT

Every write sees at least the nearest inter-region RTT. This is why Spanner targets 2–5ms intra-zone and accepts 14ms cross-continent commits.

### Google Spanner Approach

Spanner uses:
1. **TrueTime API** — GPS + atomic clocks guarantee bounded clock uncertainty
2. **Commit wait** — Leader waits `2 * clock_uncertainty` (typically 7ms) before acknowledging → ensures causality
3. **Paxos groups per shard** — Quorum only required within a shard's replica set

Result: 14ms commit latency for global external consistency. See `time-and-causality.md` for TrueTime details.

---

## GDPR and Data Sovereignty

### The Constraint

GDPR Article 44–49: EU personal data cannot be transferred outside EU/EEA without adequate protection. This means:
- User PII (name, email, address, IP, device IDs) cannot be stored or processed in non-EU systems
- Violating this: up to €20M or 4% of global annual revenue fine

### Routing Architecture

```
Request from EU user (identified by geoIP):
  API Gateway → EU region only
    → EU-West database (PII stored here)
    → EU-West computation

Request from US user:
  API Gateway → US region
    → US-East database (US PII here)
```

**Multi-region data store with data residency:**
- DynamoDB Global Tables: configure which tables replicate to which regions → EU tables replicate only within EU regions
- CockroachDB: `CONFIGURE ZONE FOR TABLE ... CONSTRAINTS = [{+region=eu-west}]`
- PostgreSQL: logical replication with publication filtering — subscribe only to non-PII tables in cross-region replication

**Shared non-PII data:**
- Product catalog, content, feature flags → replicate globally (no residency constraint)
- Pricing, inventory → replicate globally with last-writer-wins

**User look-up routing:**
```python
# Home region lookup service — single global table mapping user_id → home_region
# This table contains no PII (only user_id which is opaque)
def get_user_home_region(user_id: str) -> str:
    return user_region_table.get(user_id)  # global, low-cardinality lookup
```

---

## CRDTs for Multi-Region Conflict-Free Writes

For data that can be expressed as a CRDT (see `crdts-and-conflict-resolution.md`), you get conflict-free multi-region writes:

### Shopping Cart (OR-Set CRDT)

```
US-East at T=100ms: add("milk", tag=uuid1)
EU-West at T=120ms: add("eggs", tag=uuid2)

Replication (async):
  US-East receives EU-West op: add("eggs", tag=uuid2) → merge: {milk, eggs}
  EU-West receives US-East op: add("milk", tag=uuid1) → merge: {milk, eggs}

Converged state (both regions): { milk, eggs }  ← no conflict resolution needed
```

### Counters (PN-Counter CRDT)

```
Like counter, upvote count, inventory delta:
Each region has its own increment register.
  US-East increments: delta_us += 1
  EU-West increments: delta_eu += 1
  Total = sum of all region deltas → always correct, always convergent
```

### What CRDTs Don't Cover

- Profile updates (last-write-wins is often wrong)
- Financial transfers (need atomic globally-ordered operations)
- Anything requiring global uniqueness (unique usernames, reservations)

For those, you still need synchronous cross-region coordination or route to a single authoritative region.

---

## Production Examples

### DynamoDB Global Tables

```
Fully managed active-active multi-region DynamoDB.
Each region has a full replica. Writes go to any region.
Conflict resolution: LWW (last write wins by timestamp).
Replication lag: typically < 1 second.
```

**Trade-off:** LWW conflict resolution means if two regions write the same item within ~1 second, one write is silently discarded. Acceptable for many use cases (user sessions, preferences); dangerous for financial data.

### CockroachDB Multi-Region

```sql
-- Assign table to home region
ALTER TABLE users SET LOCALITY REGIONAL BY ROW;  -- routes each row to its home region

-- Reads from any region are still strongly consistent (cross-region Raft quorum)
-- Reads from home region: ~10ms (local)
-- Reads from non-home region: ~80-180ms (cross-region quorum)
```

CockroachDB's "super region" feature can enforce data residency for GDPR.

### Cassandra Multi-Datacenter

```
Cassandra treats each region as a datacenter.
Replication factor per datacenter: replication_factor=3 means 3 replicas per datacenter.
Consistency levels:
  LOCAL_QUORUM: quorum within local DC only (no cross-region latency)
  EACH_QUORUM: quorum in EVERY DC (strong cross-region consistency, high latency)

Example:
  keyspace replication = {'class': 'NetworkTopologyStrategy', 'us-east': 3, 'eu-west': 3}
  Write with LOCAL_QUORUM: fast (within-DC only)
  Read with LOCAL_QUORUM: reads local replicas (may see stale data)
```

### Shopify: Single-Region per Shop

Shopify routes each merchant to a "home" region. All writes for that merchant go to that region's primary. Global replication for reads. This avoids multi-master conflicts entirely — each entity has exactly one home region.

---

## Failure Modes and Recovery

### Region Failure

**Active-passive failover:**
1. Health check detects primary region down
2. DNS/anycast routing redirects to DR region
3. DR region replica is promoted to master
4. Application reconnects

**Recovery time breakdown:**
- Health check detection: 10–30s
- DNS propagation: 30s – 5 min (depends on TTL; use low TTL ~30s for faster failover)
- Database promotion: 30s – 2 min
- Application reconnect: 5–30s
- **Total:** 1–8 minutes typical

**Data loss (RPO) on async replication:**
- Replication lag at time of failure = data loss
- Under write spike just before failure: potentially many seconds of data

### Network Partition Between Regions

**Example:** US-East and EU-West lose connectivity for 2 minutes.

Active-passive: EU-West serves reads (may be stale); writes fail (all go to US-East which EU can't reach)
Active-active: Both regions continue writes → diverge → need conflict resolution on reconnect

**Handling partitions in active-passive:**
```
Option A: Reject writes in all replicas during partition
  → High availability sacrificed, data consistency preserved

Option B: Allow reads with stale data; buffer writes until primary reachable  
  → Reads continue (stale), writes queued; risk of large lag on reconnect

Option C: Promote replica to master (split-brain)
  → Two masters, both accepting writes, diverge
  → DANGEROUS without fencing: two masters can conflict
  → Need fencing tokens and STONITH-style mechanisms (see failure-detection-and-recovery.md)
```

---

## Decision Framework

```
Do you need multi-region?
  ├─ User latency > 100ms across regions? → Yes
  ├─ Single region MTBF acceptable? (rare for >99.9% SLA) → No → Multi-region needed
  └─ Data residency regulations (GDPR, etc.)? → Yes → Must be multi-region

What topology?
  ├─ Can tolerate cross-region write latency? (financial, strong consistency)
  │   └─ Yes → Active-passive or synchronous replication with strong consistency
  ├─ Need low write latency globally?
  │   ├─ Can partition data by owner? (each user has a home region)
  │   │   └─ Yes → Single-region writes per entity (Shopify model)
  │   └─ Truly global concurrent writes on same data?
  │       ├─ Data expressible as CRDT? → Yes → CRDT-based active-active
  │       └─ Arbitrary writes? → LWW active-active (accept some data loss) or redesign

What consistency level?
  ├─ Financial/inventory: synchronous, cross-region consensus → Spanner/CockroachDB
  ├─ User profiles: async with read-your-writes → DynamoDB Global Tables + session tokens
  ├─ Social feeds: eventual consistency → Cassandra LOCAL_QUORUM
  └─ Shopping cart: CRDT-based → Riak, DynamoDB with custom CRDT
```

---

## Trade-off Summary

| Topology | Write Latency | Read Latency | Consistency | Complexity | Use Case |
|---|---|---|---|---|---|
| Active-passive (async) | Low (local) | Low (local replica) | Eventual (lag) | Low | Most apps |
| Active-passive (sync) | High (+cross-region RTT) | Low | Strong | Medium | Finance |
| Active-active LWW | Low | Low | Eventual (conflict) | Medium | Sessions, caches |
| Active-active CRDTs | Low | Low | Eventual (convergent) | High | Carts, counters |
| Home-region routing | Low (writes to home) | Low (local reads) | Read-your-writes | Medium | Multi-tenant SaaS |
| Spanner-style | High (~14ms) | Low | External consistency | Very High | Global financial |

---

## FAANG Interview Application

**Likely questions:**
- "How would you design a globally distributed service with low latency for all regions?"
- "What is RPO vs RTO? How do you minimize each?"
- "How does DynamoDB Global Tables work? What are the trade-offs?"
- "How do you handle GDPR data residency in a multi-region architecture?"
- "A user posts a tweet — their follower in the EU should see it with low latency. Walk me through the design."

**What interviewers evaluate:**
- Do you understand the CAP trade-off in multi-region context? (partition between regions is the 'P' in CAP)
- Can you articulate RPO vs RTO and how deployment topology affects each?
- Do you know about replication lag and how it affects consistency guarantees?
- Can you reason about data residency constraints (GDPR) and how they impact architecture?

**Principal-level signal:**
> "Multi-region is not a single pattern — it's a spectrum of trade-offs. At one extreme, synchronous multi-region consensus (Spanner) gives external consistency at ~14ms commit latency. At the other, active-active LWW gives low latency but silent data loss on conflict. The right answer depends on your data type: financial records need consensus; shopping carts can use CRDTs; social feeds can tolerate eventual consistency. For GDPR, the cleanest architecture is routing each user's writes to their home region's master — all EU data stays in EU, all writes to US data stay in US. The complexity is in the routing layer and in cross-region reads, not in conflict resolution. I'd start with active-passive, measure the actual latency impact, and only add active-active complexity if the business requirement genuinely demands it."
