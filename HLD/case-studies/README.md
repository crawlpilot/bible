# HLD Case Studies — Real-World Architecture Breakdowns

Each case study follows a consistent structure:
1. **Problem & Scale** — what they were building and at what load
2. **Evolution** — what broke, what they tried, what they landed on
3. **Architecture Deep-Dive** — components, data flow, diagrams
4. **Key Trade-offs** — the actual decisions made and why
5. **Failure Modes** — how it breaks and how they handle it
6. **FAANG Interview Angle** — how to apply this in an interview

All case studies are calibrated to the **principal engineer bar**: concrete numbers, trade-off tables, failure analysis, and cross-company pattern recognition.

---

## Index

| Case Study | Company | Core Problem | Key Insight |
|-----------|---------|-------------|-------------|
| [Discord: Storing Billions of Messages](discord-message-storage.md) | Discord | NoSQL storage evolution at scale | Cassandra bucket-key design; Snowflake IDs; ScyllaDB migration |
| [Netflix: Chaos Engineering & Resilience](netflix-chaos-engineering.md) | Netflix | Cascading failure prevention in microservices | Hystrix circuit breaker; Simian Army; fault injection as discipline |
| [Uber: H3 Geospatial Indexing for Ride Matching](uber-geospatial-h3.md) | Uber | Real-time driver-rider matching at global scale | Hierarchical hexagonal grid; O(1) cell lookup; consistent hashing dispatch |
| [Meta: Scaling Memcached for 2B Users](meta-scaling-memcached.md) | Meta/Facebook | Distributed caching at social-graph scale | mcrouter; regional pools; lease-based thundering herd prevention |
| [Twitter: Timeline Fanout at Scale](twitter-timeline-fanout.md) | Twitter | Newsfeed delivery for 200M users | Fan-out on write vs read; celebrity hybrid; Redis timeline cache |
| [Stripe: Idempotency for Payment APIs](stripe-idempotency.md) | Stripe | Exactly-once semantics in distributed payment flows | Idempotency key pattern; atomic DB operations; retry-safe API design |

---

## Pattern Cross-Reference

| Pattern | Where It Appears |
|---------|-----------------|
| LSM tree / compaction | Discord (Cassandra), Meta (RocksDB), Uber (Schemaless) |
| Consistent hashing | Discord (Cassandra ring), Uber (Ringpop), Meta (Memcached sharding) |
| Circuit breaker | Netflix (Hystrix), Uber (dispatch fallback) |
| Fan-out on write vs read | Twitter (timeline), Meta (newsfeed), LinkedIn (FollowFeed) |
| Thundering herd prevention | Meta (Memcached leases), Netflix (staggered cache warm-up) |
| Idempotency keys | Stripe (payments), Discord (message dedup), Uber (ride creation) |
| Snowflake-style IDs | Discord (messages), Twitter (tweets, DMs) |
| Hexagonal grid indexing | Uber (H3), Google Maps (S2) |
