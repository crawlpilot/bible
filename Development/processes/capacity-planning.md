# Capacity Planning Process

**Category**: Engineering Operations · Infrastructure · Growth Planning  
**Audience**: Principal / Staff Engineers owning service reliability and infrastructure strategy  
**Related**: [PRR](production-readiness-review.md) · [SLO Definition](slo-definition-process.md)

> "Capacity planning is not about predicting the future precisely. It is about ensuring you never run out of runway before you can add more. The goal is a buffer between current capacity and saturation that is always larger than your provisioning lead time."

---

## Why Capacity Planning Matters

**The cost of getting it wrong**:

| Failure Mode | Cost |
|-------------|------|
| **Over-provisioned** | Wasted infrastructure cost; technical debt (over-complex infra to serve load it doesn't receive) |
| **Under-provisioned** | Outages, degraded performance, user churn, SLO breaches, on-call incidents |
| **Under-provisioned at wrong moment** | Launch event, seasonal peak, viral moment — the worst time to be out of capacity |

**The provisioning lead time problem**: Adding capacity takes time. Cloud compute can be provisioned in minutes; database storage can take hours; network bandwidth upgrades can take weeks; data center capacity can take months. Capacity planning ensures you initiate provisioning before you need it, not after.

---

## The Capacity Planning Framework

### Step 1: Understand Current State

Before projecting, measure what you have and how much of it you're using.

**Resource inventory per service**:

```
Compute:
- Instance type + count
- CPU utilization: P50, P95, P99 over last 30 days
- Memory utilization: P50, P95, P99 over last 30 days
- Network I/O: bytes in/out, P95 over last 30 days

Storage:
- Database: storage used, storage growth rate (GB/day), IOPS used vs. provisioned
- Cache: memory used, eviction rate (evictions = undersized)
- Object storage: total bytes, ingestion rate

Queues / Streams:
- Kafka: partition count, messages per second, consumer lag (baseline)
- SQS/PubSub: queue depth baseline, processing rate

Throughput:
- Current QPS (P50, P95, peak) per service
- Current P99 latency per service
- Error rate at current load

Saturation indicators (warning signs):
- CPU consistently > 70% → plan to scale
- Memory consistently > 80% → risk of OOM; scale
- Connection pool utilization consistently > 80% → bottleneck risk
- Disk I/O wait consistently > 5% → storage bottleneck
- Cache eviction rate > 5% → cache undersized
```

### Step 2: Project Future Load

**Three horizons for capacity planning**:

| Horizon | Timeframe | Method | Precision |
|---------|-----------|--------|-----------|
| **Short-term** | 0-3 months | Trend extrapolation from current growth | High |
| **Medium-term** | 3-12 months | Traffic model + product roadmap assumptions | Medium |
| **Long-term** | 1-3 years | Business growth projections + architecture assumptions | Low — scenario planning |

**Traffic projection methods**:

**Method 1: Linear trend extrapolation** (for stable growth)
```
Current QPS: 1,000 req/s
30-day growth rate: +3% per week
Projection at 3 months (12 weeks): 1,000 × (1.03)^12 = 1,426 req/s
Projection at 6 months (24 weeks): 1,000 × (1.03)^24 = 2,033 req/s
```

**Method 2: Event-driven projection** (for launch/marketing events)
```
Baseline: 1,000 req/s
Expected peak multiplier from marketing event: 5×
Peak capacity needed: 5,000 req/s
Buffer required: 20% headroom above expected peak = 6,000 req/s capacity
```

**Method 3: Product roadmap projection** (for new features)
```
Feature X launches in Q3 → expected to add 500 req/s to checkout flow
Feature Y launches in Q4 → expected to add 200 req/s to auth flow
Traffic model:
  - Q3 start: current 1,000 + 500 (Feature X) = 1,500 req/s
  - Q4 start: 1,500 + 200 (Feature Y) = 1,700 req/s
```

**Back-of-envelope capacity math** (the interview essential):

```
Given: 
  - 10M daily active users (DAU)
  - Average user makes 5 requests per session
  - Average session: 2 per day per user

QPS calculation:
  Total requests/day = 10M × 2 sessions × 5 requests = 100M req/day
  Average QPS = 100M / 86,400s ≈ 1,157 req/s
  Peak QPS (assume 3× average during peak hour) ≈ 3,500 req/s

Storage calculation (if storing 1KB per request payload, 30-day retention):
  100M req/day × 1KB × 30 days = 3TB raw storage
  With 3× replication: 9TB

Bandwidth calculation:
  3,500 req/s × 10KB average response = 35 MB/s ≈ 280 Mbps
```

### Step 3: Map Load to Resources

**Resource projection formula**:

```
Instances needed = ceil(peak_QPS / requests_per_instance_per_second)

Where requests_per_instance_per_second is determined by load testing.
Example: load test shows one instance handles 200 req/s at P99 < 200ms

At peak_QPS = 3,500 req/s:
Instances needed = ceil(3,500 / 200) = 18 instances
With 20% headroom: 22 instances
With failure tolerance (N+1 across 3 AZs, each AZ needs to survive 2-AZ failure):
  Per-AZ instances: ceil(22 / 3) = 8 per AZ → any 1 AZ can handle 100% of traffic? No.
  For 2-AZ failure tolerance: each AZ must handle 100% of load = 22 instances per AZ = 66 total
  For 1-AZ failure tolerance: each AZ handles 50% of remaining (2 AZ × 100%) = 22 per AZ = 66 total
  Common approach: 22 total, designed to tolerate 1 AZ loss (remaining 2 AZs absorb load with ~33% surge headroom)
```

**Database capacity projection**:

```
Storage growth:
  Current size: 500GB
  Growth rate: 5GB/day
  At 6 months: 500 + (5 × 180) = 1,400GB = 1.4TB
  Provision: 2TB (40% headroom)
  Action trigger: 80% of provisioned = alert when at 1.6TB → order more capacity

IOPS:
  Current read IOPS: 5,000 / write IOPS: 500
  Growth at 3× traffic: 15,000 read / 1,500 write
  Provisioned: 20,000 read / 3,000 write IOPS with headroom
  
Connection pool:
  Current: 50 active connections, 100 max pool size
  At 3× instances: 3× application instances × (50 connections/instance) = 150 connections
  Database max connections: 200 (verify with DBA)
  Warning: 150 connections approaching 200 DB limit → need DB read replicas or connection proxy
```

---

## Step 4: Identify Bottlenecks

Every service has a limiting resource. Capacity planning means knowing which resource hits its limit first.

**Bottleneck identification matrix**:

| Service Type | Most Common Bottleneck | Second Bottleneck |
|-------------|----------------------|------------------|
| Compute-heavy (encoding, ML inference) | CPU | Memory |
| Data-heavy (aggregation, joins) | Database IOPS / CPU | Network bandwidth |
| High-concurrency (API gateway, proxies) | Network connections | Memory |
| Cache-heavy (Redis, Memcached) | Memory (eviction) | Network bandwidth |
| Write-heavy (ingestion pipelines) | Database write IOPS | Kafka partition throughput |
| Storage-heavy (data lake, analytics) | Storage capacity | Read IOPS |

**Saturation thresholds** (plan provisioning when these are hit):

| Resource | Warning Threshold | Critical Threshold |
|----------|------------------|-------------------|
| CPU utilization | 70% P95 | 85% P95 |
| Memory utilization | 75% P95 | 85% P95 |
| DB connection pool | 70% | 85% |
| Disk utilization | 70% | 80% |
| Network bandwidth | 60% | 80% |
| Cache memory | 80% | 90% (evictions starting) |
| Queue lag (Kafka) | 5min processing lag | 15min lag (freshness SLO risk) |

---

## Step 5: Plan Provisioning Actions

**Provisioning options by resource**:

| Need | Option | Lead Time | Cost Impact |
|------|--------|-----------|------------|
| More compute | Add instances (horizontal scaling) | Minutes | Linear |
| More compute per instance | Increase instance size (vertical scaling) | Minutes (restart needed) | Stepped |
| More DB read capacity | Add read replicas | Hours | Linear |
| More DB write capacity | Shard or migrate to distributed DB | Weeks–months | High |
| More DB storage | Storage auto-expansion (cloud) | Minutes | Linear |
| More cache memory | Increase Redis node size | Minutes | Stepped |
| More cache capacity | Add Redis cluster nodes | Minutes | Linear |
| More Kafka throughput | Add partitions | Minutes | Low |
| More network bandwidth | Upgrade NIC or add load balancer nodes | Hours–days | Stepped |

**Make vs. buy decision for capacity**:
- Cloud-native scaling (auto-scaling groups, serverless) vs. pre-provisioned: choose auto-scaling for variable load, pre-provisioned for predictable load with low latency tolerance
- On-demand vs. reserved instances: reserve for baseline load (save 40-60%), on-demand for burst

---

## Capacity Planning for Events

High-traffic events (product launches, marketing campaigns, seasonal peaks) require dedicated capacity planning.

### Event Capacity Playbook

**T-4 weeks before event**:
```
□ Estimate traffic multiplier (use data from similar past events)
□ Load test at expected peak + 20% buffer
□ Identify the bottleneck at peak load
□ Request reserved instance capacity (cloud providers sometimes require lead time for large spikes)
□ Pre-scale databases and caches (they have slower scaling paths than compute)
```

**T-1 week before event**:
```
□ Scale to 50% of event capacity (warm up, verify systems behave at higher load)
□ Verify auto-scaling policies are correct (test a scaling event manually)
□ Disable non-essential batch jobs scheduled during event window
□ Brief on-call team on expected traffic pattern
□ Prepare rollback plan for any features launching alongside the event
□ Confirm CDN is pre-seeded for static assets
```

**Event day**:
```
□ Heightened monitoring: all SLO dashboards open
□ On-call engineer on standby (not just on-pager)
□ Manual scaling trigger ready (don't rely entirely on auto-scaling during critical events)
□ Status page updated: "Higher than normal traffic expected"
□ Executive communication plan ready
```

**Post-event**:
```
□ Review actual peak vs. projected peak (improve future projections)
□ Review which resource was the actual bottleneck
□ Scale down after traffic normalizes (avoid over-provisioning indefinitely)
□ Update capacity model with event data
```

---

## Capacity Planning for Data

Data growth is often the hardest capacity problem because it is one-directional and affects many layers simultaneously.

### Data Growth Modeling

```
Storage growth model:
  Data ingested per day: D_daily (GB/day)
  Replication factor: R (typically 3 for durability)
  Compression ratio: C (typically 0.3-0.5 for structured data)
  Retention period: T (days)

  Raw storage needed = D_daily × T
  Actual storage needed = (D_daily × T) / C × R

Example:
  100GB/day × 365 days = 36.5TB raw
  With 3× replication: 109.5TB
  With 2:1 compression: 54.75TB

Plan to provision 70% capacity (provision more before hitting 70%):
  Provision: 78TB today, with trigger to expand when reaching 54TB
```

### Database Scaling Decision Framework

| Situation | Solution | Trigger |
|-----------|---------|---------|
| Read-heavy, write scale OK | Add read replicas | Read QPS > 70% of primary capacity |
| Storage growing fast | Vertical storage expansion | Disk > 70% full |
| Write-heavy, reads OK | Write sharding | Write IOPS > 70% of capacity |
| Both read and write scaling needed | Horizontal sharding | Both above thresholds |
| Hot partition / row | Application-level caching | Specific key accounts for > 10% of reads |
| Query complexity overwhelming DB | CQRS + read-optimized store | Query timeout rate > 1% |

---

## Capacity Planning Reporting

### Quarterly Capacity Review

**Report structure** (for EM/Director audience):

```
Service: checkout-service
Period: Q3 2024

Current State:
  Peak traffic: 2,500 req/s (P95 day)
  Current capacity: 3,200 req/s
  Headroom: 28%

Growth Trend:
  QoQ traffic growth: +35%
  Projected Q4 peak: 3,375 req/s (35% above current peak)
  Current capacity would be insufficient by: November 2024

Resource Breakdown:
  Compute: OK (headroom until Q1 2025 if we add 5 instances in October)
  Database: WARNING — storage at 65% of provisioned; will hit 80% in 6 weeks
  Cache: OK (45% utilized)

Actions Required:
  P1: Expand DB storage from 2TB to 4TB (owner: Bob, due: October 15)
  P2: Add 5 compute instances (auto-scaling update) before November traffic peak (owner: Alice, due: October 31)
  P3: Review database sharding strategy for 2025 planning (owner: Carol, Q4)

Cost Projection:
  Current monthly infra cost: $45,000
  Q4 projected cost: $58,000 (+29%)
  Full-year 2025 projection (at current growth): $90,000/month
```

---

## Capacity Anti-Patterns

| Anti-Pattern | Consequence | Correct Approach |
|-------------|------------|-----------------|
| **Reactive capacity planning** | Adding capacity during an incident | Plan 3 months ahead; trigger provisioning at 70% utilization |
| **Vertical scaling only** | Single large instance becomes SPOF | Horizontal scaling preferred; vertical for stateful systems with care |
| **No headroom** | Any traffic spike causes outage | Maintain ≥ 30% headroom at P95 traffic |
| **Ignoring tail latency** | P99 is terrible but average looks fine | Size for P99 latency requirements, not P50 |
| **Over-relying on auto-scaling** | Auto-scaling can't outrun a viral traffic spike | Pre-provision for known events; auto-scaling handles organic growth |
| **Separate DB per service with tiny instance** | Database is undersized; can't handle correlation queries | Right-size DB instances; consider service mesh for cross-service queries |
| **Ignoring data growth** | Disk full = outage; schema migrations at scale = hours | Capacity plan storage 12 months ahead |

---

## FAANG Interview Framing

### "How do you handle capacity planning for a system at 100M users?"

> "I work three horizons simultaneously. For the next 90 days, I extrapolate from current growth trends and known product launches. For 6-12 months, I work with the product roadmap to model traffic for planned features. For 1-3 years, I do scenario planning — what does the architecture look like at 10× current scale, and what investments do I need to make now to avoid a rewrite at that scale? The key discipline is tracking utilization per resource class and triggering provisioning actions at 70% saturation — not 90%, because you need headroom for both traffic spikes and provisioning lead time. The most common mistake I see is teams planning compute capacity but forgetting database IOPS and storage, which have much longer lead times and more constrained scaling paths."

### "Walk me through back-of-envelope for a system like Instagram Stories."

> "500M DAU × 2 stories viewed per session × 3 views per day = 3B story views/day. Average QPS = 3B / 86,400 = 34,700 req/s. Peak QPS (3× average) = 104,000 req/s. Storage: if each story is 5MB media, and 500M users post 1 story/day on average, that's 2.5PB/day of raw storage. With replication and 30-day retention: 2.5PB × 3 × 30 = 225PB of total storage. This tells me immediately that the critical architectural decisions are: aggressive CDN caching for reads (to avoid 104K req/s hitting origin), distributed object storage for media, and a hot/cold storage tiering strategy because keeping 225PB in 'hot' storage would be prohibitively expensive."
