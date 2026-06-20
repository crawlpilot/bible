# HLD Engineering Resources — Case Studies, Papers, Cloud Patterns & Interview Prep

Curated resources for high-level system design at the principal engineer bar. Covers seminal papers, real-world case studies, cloud design patterns, books, practice platforms, and engineering blogs.

> Legend: ⭐ = essential / must-read | 🎓 = course/tutorial | 📄 = paper | 🛠 = tool/platform | 📏 = standard/guideline | 🏢 = from a major company

---

## Table of Contents

1. [Seminal Distributed Systems Papers](#1-seminal-distributed-systems-papers)
2. [Real-World Architecture Case Studies](#2-real-world-architecture-case-studies)
3. [Cloud Architecture Design Patterns](#3-cloud-architecture-design-patterns)
4. [Books](#4-books)
5. [Courses & Practice Platforms](#5-courses--practice-platforms)
6. [Engineering Blogs by Company](#6-engineering-blogs-by-company)
7. [GitHub Repositories & Study Guides](#7-github-repositories--study-guides)
8. [Quick-Access by Topic](#8-quick-access-by-topic)

---

## 1. Seminal Distributed Systems Papers

Every principal engineer candidate is expected to know these by name, author, and key contribution. Know the problem solved, the design decision, and the trade-off — not just the title.

### Storage & Databases

| Paper | Company | Year | Key Contribution | What to Know for Interviews |
|-------|---------|------|-----------------|----------------------------|
| ⭐ [Dynamo: Amazon's Highly Available Key-Value Store](https://www.allthingsdistributed.com/files/amazon-dynamo-sosp2007.pdf) | Amazon | 2007 | Consistent hashing, vector clocks, eventual consistency, sloppy quorum | "Why not use strong consistency?" → availability/partition tolerance trade-off; leaderless replication |
| ⭐ [Bigtable: A Distributed Storage System for Structured Data](https://static.googleusercontent.com/media/research.google.com/en//archive/bigtable-osdi06.pdf) | Google | 2006 | Wide-column store, SSTable, tablet server model, compaction | Foundation of HBase, Cassandra; row key design, LSM tree basics |
| ⭐ [Spanner: Google's Globally Distributed Database](https://static.googleusercontent.com/media/research.google.com/en//archive/spanner-osdi2012.pdf) | Google | 2012 | TrueTime API, external consistency, globally distributed SQL | "How do you do distributed transactions at global scale?" |
| [Cassandra: A Decentralized Structured Storage System](https://www.cs.cornell.edu/projects/ladis2009/papers/lakshman-ladis2009.pdf) | Facebook/Apache | 2010 | Merges Dynamo's distribution with Bigtable's data model; tunable consistency | When to choose Cassandra over DynamoDB; write-heavy time-series workloads |
| ⭐ [F1: A Distributed SQL Database That Scales](https://static.googleusercontent.com/media/research.google.com/en//pubs/archive/41344.pdf) | Google | 2013 | Spanner-based SQL layer for Google Ads; strong consistency at scale | Example of OLTP at planetary scale; schema changes without downtime |
| [CRDT: Conflict-Free Replicated Data Types](https://arxiv.org/abs/1805.06358) | Research | 2018 | Mathematical framework for eventual consistency without conflict resolution | Collaborative editing (Google Docs, Figma), offline-first apps |
| [TAO: Facebook's Distributed Data Store for the Social Graph](https://www.usenix.org/system/files/conference/atc13/atc13-bronson.pdf) | Facebook | 2013 | Read-heavy social graph; follower-leader caching; objects + associations | "Design Facebook's social graph storage" |

### Distributed Processing

| Paper | Company | Year | Key Contribution | What to Know for Interviews |
|-------|---------|------|-----------------|----------------------------|
| ⭐ [MapReduce: Simplified Data Processing on Large Clusters](https://static.googleusercontent.com/media/research.google.com/en//archive/mapreduce-osdi04.pdf) | Google | 2004 | Programming model for large-scale batch processing; fault tolerance via re-execution | Foundation of Hadoop; "How do you design a batch analytics pipeline?" |
| ⭐ [The Google File System](https://static.googleusercontent.com/media/research.google.com/en//archive/gfs-sosp2003.pdf) | Google | 2003 | Single master, chunk servers, append-only writes, relaxed consistency | Foundation of HDFS; design decisions for write-once read-many workloads |
| [Dremel: Interactive Analysis of Web-Scale Datasets](https://static.googleusercontent.com/media/research.google.com/en//pubs/archive/36632.pdf) | Google | 2010 | Columnar storage for nested data, multi-level serving tree | Foundation of BigQuery; columnar storage trade-offs |
| [Pregel: A System for Large-Scale Graph Processing](https://dl.acm.org/doi/10.1145/1807167.1807184) | Google | 2010 | Vertex-centric graph computation (think-like-a-vertex) | "Design a system to run PageRank on a billion-node graph" |
| [MillWheel: Fault-Tolerant Stream Processing at Internet Scale](https://static.googleusercontent.com/media/research.google.com/en//pubs/archive/41378.pdf) | Google | 2013 | Exactly-once stream processing, low watermarks | Foundation of Dataflow/Beam; "design a streaming pipeline" |
| [Kafka: A Distributed Messaging System for Log Processing](https://www.microsoft.com/en-us/research/wp-content/uploads/2017/09/Kafka.pdf) | LinkedIn | 2011 | Durable log, consumer groups, sequential disk I/O for high throughput | "Design an event streaming platform"; partitioning, offset management, consumer lag |

### Consistency & Consensus

| Paper | Company/Author | Year | Key Contribution | What to Know for Interviews |
|-------|--------------|------|-----------------|----------------------------|
| ⭐ [In Search of an Understandable Consensus Algorithm (Raft)](https://raft.github.io/raft.pdf) | Stanford | 2014 | Leader election, log replication, safety; simpler alternative to Paxos | How etcd, Consul work; quorum writes; split-brain prevention |
| ⭐ [Paxos Made Simple](https://lamport.azurewebsites.net/pubs/paxos-simple.pdf) | Lamport | 2001 | Distributed consensus via prepare/promise/accept/commit phases | Foundation of Chubby, Zookeeper; know the phases not just the name |
| ⭐ [Brewer's CAP Theorem (SIGACT)](https://www.cs.berkeley.edu/~brewer/cs262b-2004/PODC-keynote.pdf) | Eric Brewer | 2000 | Consistency, Availability, Partition tolerance — pick 2; partitions are mandatory | Must state CAP position in every system design answer |
| [PACELC: An Extension to the CAP Theorem](https://dl.acm.org/doi/10.1109/MC.2012.33) | Abadi | 2012 | Even without partitions, choose between latency and consistency | More nuanced than CAP; use for DynamoDB (EL) vs Spanner (CL) comparison |
| [Consistent Hashing and Random Trees](https://dl.acm.org/doi/10.1145/258533.258660) | Karger et al. | 1997 | Minimize remapping when nodes join/leave; virtual nodes | Foundation of DHTs, Dynamo, Cassandra ring; explain in any cache/shard design |
| [Time, Clocks, and the Ordering of Events in a Distributed System](https://lamport.azurewebsites.net/pubs/time-clocks.pdf) | Lamport | 1978 | Logical clocks (Lamport timestamps); happens-before relationship | "How do you order events across distributed nodes without a global clock?" |
| [Vector Clocks](https://en.wikipedia.org/wiki/Vector_clock) | Fidge / Mattern | 1988 | Per-node counter vectors; detect concurrent updates | Conflict detection in Dynamo, CRDTs; "how does DynamoDB detect conflicts?" |

### Infrastructure & Operations

| Paper | Company | Year | Key Contribution | What to Know for Interviews |
|-------|---------|------|-----------------|----------------------------|
| ⭐ [Dapper: A Large-Scale Distributed Systems Tracing Infrastructure](https://static.googleusercontent.com/media/research.google.com/en//pubs/archive/36356.pdf) | Google | 2010 | Trace context propagation; sampling; low-overhead instrumentation | Foundation of Jaeger, Zipkin, OpenTelemetry; "design distributed tracing" |
| [Borg: Large-Scale Cluster Management at Google](https://dl.acm.org/doi/10.1145/2741948.2741964) | Google | 2015 | Workload classification (long-running vs batch), bin-packing, priority preemption | Kubernetes lineage; "how does a cluster scheduler work?" |
| [Chubby: The Chubby Lock Service for Loosely-Coupled Distributed Systems](https://static.googleusercontent.com/media/research.google.com/en//archive/chubby-osdi06.pdf) | Google | 2006 | Coarse-grained distributed lock service via Paxos; ephemeral nodes | Foundation of ZooKeeper; leader election, service discovery patterns |
| [Monarch: Google's Planet-Scale In-Memory Time Series Database](https://www.vldb.org/pvldb/vol13/p3181-adams.pdf) | Google | 2020 | In-memory hierarchical time series at global scale; leaves + roots model | "Design a metrics collection system at Google scale" |
| [Zanzibar: Google's Consistent, Global Authorization System](https://research.google/pubs/pub48190/) | Google | 2019 | Relationship-based access control (ReBAC); consistent global reads; zookies | "Design a permissions system like Google Drive sharing"; used by Auth0 FGA |

---

## 2. Real-World Architecture Case Studies

Organized by company. Each entry includes the architectural decision, the scale context, and the interview angle.

### Netflix

| Topic | Resource | Key Insight | Interview Angle |
|-------|---------|-------------|----------------|
| ⭐ [Netflix Microservices Migration](https://netflixtechblog.com/the-netflix-simian-army-16e57fbab116) | Netflix Tech Blog | Chaos Monkey, Simian Army; built chaos engineering discipline | "How do you ensure resilience in a microservices architecture?" |
| ⭐ [Netflix CDN (Open Connect)](https://netflixtechblog.com/how-netflix-works-with-isps-around-the-globe-to-deliver-a-great-viewing-experience-56ccff8f61e) | Netflix Tech Blog | ISP-embedded appliances; pre-positioning content; BGP routing | "Design a CDN for video streaming at Netflix scale" |
| [Netflix API Gateway Evolution](https://netflixtechblog.com/optimizing-the-netflix-api-5c9ac715cf19) | Netflix Tech Blog | Aggregation layer → GraphQL Federated → Falcor → gRPC | "How do you design an API gateway for 200+ microservices?" |
| [Netflix Recommendation System](https://netflixtechblog.com/netflix-recommendations-beyond-the-5-stars-part-1-55838468f429) | Netflix Tech Blog | Collaborative filtering + content signals; A/B at scale | "Design a recommendation engine for 250M users" |
| [Netflix Keystone Real-Time Stream Processing](https://netflixtechblog.com/keystone-real-time-stream-processing-platform-a3ee651812a) | Netflix Tech Blog | Kafka + Flink; backpressure handling; consumer group design | "Design Netflix's real-time event processing pipeline" |
| ⭐ [Netflix Hystrix Circuit Breaker](https://github.com/Netflix/Hystrix/wiki/How-it-Works) | GitHub | Thread isolation, circuit states, fallback strategies | "How do you prevent cascading failures in microservices?" |

### Uber

| Topic | Resource | Key Insight | Interview Angle |
|-------|---------|-------------|----------------|
| ⭐ [Uber H3 Geospatial Indexing](https://www.uber.com/blog/h3/) | Uber Engineering | Hierarchical hexagonal grid for location indexing; O(1) cell lookup | "How does Uber match drivers to riders efficiently?" |
| ⭐ [Uber's Dispatch System (Ringpop)](https://www.uber.com/blog/introducing-ringpop-consistent-hash-ring/) | Uber Engineering | Consistent hash ring for dispatch; actor model; SWIM protocol | "Design Uber's driver dispatch system" |
| [Uber Surge Pricing System](https://www.uber.com/blog/engineering/) | Uber Engineering | Real-time demand/supply signals; geographic aggregation | "Design a real-time pricing system that reacts to demand" |
| [Uber's Migration from Monolith to Microservices](https://www.uber.com/blog/microservice-architecture/) | Uber Engineering | Domain-oriented microservice architecture (DOMA); 2000+ services | "What are the failure modes when migrating to microservices?" |
| [Uber Schemaless (Cassandra-backed)](https://www.uber.com/blog/schemaless-part-one-mysql-datastore/) | Uber Engineering | MySQL sharding → Schemaless → Docstore; why relational wasn't enough | "When do you abandon your relational database?" |
| [Uber Peloton Resource Manager](https://www.uber.com/blog/peloton/) | Uber Engineering | Hybrid scheduler: stateless services + Spark/Presto jobs on shared cluster | "How do you run mixed workloads on a shared compute cluster?" |

### Meta / Facebook

| Topic | Resource | Key Insight | Interview Angle |
|-------|---------|-------------|----------------|
| ⭐ [Facebook's TAO Social Graph](https://www.usenix.org/conference/atc13/technical-sessions/presentation/bronson) | USENIX ATC | Read-heavy social graph; leader-follower sharded cache; objects + associations | "Design Facebook's newsfeed storage" |
| ⭐ [Scaling Memcached at Facebook](https://www.usenix.org/system/files/conference/nsdi13/nsdi13-final170_update.pdf) | NSDI 2013 | Cache invalidation protocol; regional pools; mcrouter; thundering herd mitigation | "Design a caching layer for 2B users" |
| [Facebook's Newsfeed (FeedRank)](https://engineering.fb.com/2021/01/26/ml-applications/news-feed-ranking/) | Meta Engineering | Ranking signals, story scoring, integrity filtering; real-time + batch | "Design a social media news feed" |
| [Messenger's Architecture](https://engineering.fb.com/2018/06/26/core-infra/migrating-messenger-storage-to-optimize-performance/) | Meta Engineering | Migration from HBase to MyRocks; inbox storage design | "Design a chat system like Facebook Messenger" |
| [Facebook's Haystack (Photo Storage)](https://www.usenix.org/legacy/event/osdi10/tech/full_papers/Beaver.pdf) | OSDI 2010 | Object storage for billions of photos; CDN + Haystack + F4 | "Design Instagram's photo storage system" |
| [Meta's Scuba: Diving into Data at Facebook](https://research.facebook.com/publications/scuba-diving-into-data-at-facebook/) | Meta Research | In-memory time-series for log analytics; approximate queries | "Design a real-time log analytics system" |

### Google

| Topic | Resource | Key Insight | Interview Angle |
|-------|---------|-------------|----------------|
| ⭐ [Gmail Architecture](https://sre.google/sre-book/case-studies/) | Google SRE Book | Colossus + Bigtable for mail storage; 99.9% SLA design | "Design Gmail's storage architecture" |
| [Google Search Indexing Pipeline](https://research.google/pubs/pub37043/) | Google Research | Web crawl → Caffeine continuous indexing pipeline; freshness vs stalability | "How does Google keep search results fresh?" |
| [Google Ads Click Aggregation](https://static.googleusercontent.com/media/research.google.com/en//pubs/archive/40671.pdf) | Google Research | MapReduce + Streaming hybrid; idempotent aggregation | "Design an ad click counting system" |
| [Google Cloud Spanner's TrueTime](https://cloud.google.com/spanner/docs/true-time-external-consistency) | Google Cloud | GPS + atomic clocks for bounded clock uncertainty; external consistency | "How do you achieve linearizability globally?" |

### LinkedIn

| Topic | Resource | Key Insight | Interview Angle |
|-------|---------|-------------|----------------|
| ⭐ [LinkedIn's Feed Architecture](https://engineering.linkedin.com/blog/2016/03/followfeed--linkedin-s-feed-made-faster-and-smarter) | LinkedIn Engineering | Fan-out on write vs read; "FollowFeed" hybrid; push for celebrities vs pull for everyone | "Design LinkedIn's activity feed" |
| [Voldemort: LinkedIn's Distributed Key-Value Store](https://engineering.linkedin.com/distributed-systems/log-what-every-software-engineer-should-know-about-real-time-datas-unifying) | LinkedIn Engineering | Eventually consistent KV store; Dynamo-inspired | Pre-DynamoDB distributed KV design decisions |
| ⭐ [The Log: What every software engineer should know](https://engineering.linkedin.com/distributed-systems/log-what-every-software-engineer-should-know-about-real-time-datas-unifying) | Jay Kreps (LinkedIn) | Unified theory of data systems via the log abstraction; Kafka origin story | "What is the single most important primitive in distributed systems?" |
| [LinkedIn's Norbert (Search)](https://engineering.linkedin.com/search/did-you-mean-galene) | LinkedIn Engineering | Galene search: Lucene + federated search; freshness guarantees | "Design LinkedIn's job and people search" |

### Discord

| Topic | Resource | Key Insight | Interview Angle |
|-------|---------|-------------|----------------|
| ⭐ [How Discord Stores Billions of Messages](https://discord.com/blog/how-discord-stores-billions-of-messages) | Discord Blog | Cassandra → ScyllaDB; snowflake IDs; bucket-based message storage | "Design Discord's message storage" |
| [Discord's Real-Time Messaging via WebSockets](https://discord.com/blog/how-discord-scaled-elixir-to-5-000-000-concurrent-users) | Discord Blog | Elixir + Phoenix; 5M concurrent users; the actor model for presence | "How do you maintain 5M persistent WebSocket connections?" |
| [How Discord Handles Push Notifications at Scale](https://discord.com/blog/how-discord-handles-two-and-half-million-concurrent-voice-users-using-webrtc) | Discord Blog | WebRTC at scale; selective forwarding unit (SFU) architecture | "Design a voice chat system like Discord" |

### Stripe

| Topic | Resource | Key Insight | Interview Angle |
|-------|---------|-------------|----------------|
| ⭐ [Stripe's Idempotency Keys](https://stripe.com/blog/idempotency) | Stripe Blog | Idempotency layer for payment APIs; exactly-once semantics | "How do you prevent duplicate charges in a payment system?" |
| [Stripe's Rate Limiting](https://stripe.com/blog/rate-limiters) | Stripe Blog | Token bucket + leaky bucket hybrid; Redis-backed; gradual degradation | "Design a rate limiter for an API gateway" |
| [Stripe's Distributed Tracing](https://stripe.com/blog/distributed-tracing) | Stripe Blog | OpenTracing adoption; sampling strategy; trace storage | "How do you debug latency issues across 300 microservices?" |

### Airbnb

| Topic | Resource | Key Insight | Interview Angle |
|-------|---------|-------------|----------------|
| ⭐ [Airbnb's Search Architecture](https://medium.com/airbnb-engineering/airbnb-search-architecture-4d0aa73fea8c) | Airbnb Engineering | Elasticsearch for full-text + geo; ML ranking; experiment infrastructure | "Design Airbnb's search and ranking system" |
| [Airbnb's Payments Infrastructure](https://medium.com/airbnb-engineering/scaling-airbnbs-payment-platform-43ebfc99b324) | Airbnb Engineering | Multi-currency; fraud detection; payout scheduling | "Design a two-sided marketplace payment system" |
| [Airbnb's Migration to SOA](https://medium.com/airbnb-engineering/loosely-coupled-domains-the-three-principles-of-service-oriented-architecture-at-airbnb-a07d2c1b99d5) | Airbnb Engineering | 3-tier SOA: domains, services, experiences; how they sliced the monolith | "What principles do you use to define service boundaries?" |

### Twitter / X

| Topic | Resource | Key Insight | Interview Angle |
|-------|---------|-------------|----------------|
| ⭐ [Twitter's Snowflake ID Generator](https://blog.twitter.com/engineering/en_us/a/2010/announcing-snowflake) | Twitter Engineering | 64-bit IDs: timestamp + machine ID + sequence; sortable at scale | "How do you generate globally unique IDs at Twitter scale?" |
| [Twitter's Timeline Architecture](https://www.infoq.com/presentations/Twitter-Timeline-Scalability/) | InfoQ | Fan-out on write (Redis); celebrity fan-out on read hybrid | "Design Twitter's home timeline" |
| [Twitter's Manhattan Distributed KV](https://blog.twitter.com/engineering/en_us/a/2014/manhattan-our-real-time-multi-tenant-distributed-database-for-twitter-scale) | Twitter Engineering | Multi-tenant Dynamo-like store; low-latency reads for tweets | "What database would you use to store tweets?" |

### Amazon

| Topic | Resource | Key Insight | Interview Angle |
|-------|---------|-------------|----------------|
| ⭐ [Amazon's SQS Architecture](https://www.usenix.org/legacy/event/usenix09/tech/slides/hamilton.pdf) | Jim Hamilton / Amazon | Distributed queue internals; at-least-once delivery; visibility timeout | "Design an async job queue at Amazon scale" |
| [Amazon's Two-Pizza Team Model](https://aws.amazon.com/executive-insights/content/two-pizza-team/) | Amazon | Team ownership → service ownership; single-threaded ownership | "How do you structure teams around microservices?" |

---

## 3. Cloud Architecture Design Patterns

### AWS Well-Architected Framework

| Pillar | Key Patterns | AWS Resources |
|--------|-------------|---------------|
| ⭐ **Operational Excellence** | Infrastructure as Code, small reversible changes, runbooks | [AWS OE Pillar](https://docs.aws.amazon.com/wellarchitected/latest/operational-excellence-pillar/welcome.html) |
| ⭐ **Security** | Least privilege, defense in depth, data classification | [AWS Security Pillar](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/welcome.html) |
| ⭐ **Reliability** | Auto-scaling, multi-AZ, circuit breakers, chaos engineering | [AWS Reliability Pillar](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/welcome.html) |
| ⭐ **Performance Efficiency** | Right-sizing, caching, async, CDN | [AWS Performance Pillar](https://docs.aws.amazon.com/wellarchitected/latest/performance-efficiency-pillar/welcome.html) |
| **Cost Optimization** | Reserved/spot instances, storage tiering, rightsizing | [AWS Cost Pillar](https://docs.aws.amazon.com/wellarchitected/latest/cost-optimization-pillar/welcome.html) |
| **Sustainability** | Workload consolidation, efficient instance types | [AWS Sustainability Pillar](https://docs.aws.amazon.com/wellarchitected/latest/sustainability-pillar/welcome.html) |

### Cloud Reference Architectures

| Pattern | Description | Cloud Docs | When to Use |
|---------|-------------|------------|-------------|
| ⭐ [Serverless Web Application](https://aws.amazon.com/lambda/resources/reference-architectures/) | API GW + Lambda + DynamoDB + S3 + CloudFront | AWS | < 1M req/day; variable traffic; no ops overhead |
| ⭐ [Event-Driven Architecture](https://aws.amazon.com/event-driven-architecture/) | SQS/SNS/EventBridge + Lambda/ECS consumers; loose coupling | AWS | Decoupled services; async workflows; audit trail |
| [CQRS + Event Sourcing](https://learn.microsoft.com/en-us/azure/architecture/patterns/cqrs) | Separate read/write models; store events not state | Azure | High read-write asymmetry; audit requirements; eventual consistency acceptable |
| [Saga Pattern](https://learn.microsoft.com/en-us/azure/architecture/reference-architectures/saga/saga) | Choreography or orchestration for distributed transactions | Azure | Multi-service transactions without 2PC |
| [Strangler Fig Pattern](https://learn.microsoft.com/en-us/azure/architecture/patterns/strangler-fig) | Incrementally replace legacy system; route traffic via façade | Azure | Monolith → microservices migration |
| [Bulkhead Pattern](https://learn.microsoft.com/en-us/azure/architecture/patterns/bulkhead) | Isolate failure; separate thread pools or services per tenant | Azure | Noisy neighbor prevention; SLA differentiation |
| [Circuit Breaker Pattern](https://learn.microsoft.com/en-us/azure/architecture/patterns/circuit-breaker) | Open circuit on repeated failures; half-open probe | Azure | Cascading failure prevention; dependency failures |
| [Competing Consumers](https://learn.microsoft.com/en-us/azure/architecture/patterns/competing-consumers) | Multiple consumers pull from queue; horizontal scale | Azure | Work queue processing; auto-scaling throughput |
| [Sidecar Pattern](https://learn.microsoft.com/en-us/azure/architecture/patterns/sidecar) | Auxiliary container shares lifecycle with main container | Azure | Logging, service mesh (Envoy), secrets injection |
| [Ambassador Pattern](https://learn.microsoft.com/en-us/azure/architecture/patterns/ambassador) | Proxy handles cross-cutting concerns (auth, retry, circuit break) | Azure | Legacy service modernization; proxy-offloaded resilience |
| [Anti-Corruption Layer](https://learn.microsoft.com/en-us/azure/architecture/patterns/anti-corruption-layer) | Translation layer between new and legacy domain models | Azure | Domain boundary protection during migration |

### Multi-Cloud & Cloud-Agnostic Patterns

| Pattern | Description | Trade-offs |
|---------|-------------|-----------|
| **Active-Active Multi-Region** | Traffic served from multiple regions simultaneously; global load balancing | Highest availability; complex data sync; conflict resolution required |
| **Active-Passive Multi-Region** | Primary region serves traffic; standby promotes on failure | Simpler; RTO minutes not seconds; wasted standby capacity |
| **Cell-Based Architecture** | Deploy independent "cells" (mini-stacks); blast radius containment | Used by Amazon, Stripe; requires cell-aware routing; higher ops complexity |
| **Federated Identity** | Single identity across services (OIDC/SAML); centralized IdP | Enables SSO; IdP is SPOF; token validation overhead |
| **Zero-Trust Network** | Never trust network location; verify every request | Eliminates VPN perimeter; higher latency; requires mTLS or token-based auth |

### AWS-Specific Deep-Dives

| Pattern | Resource | Key Decision |
|---------|---------|-------------|
| ⭐ [Lambda at Scale](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html) | AWS Docs | Cold starts; concurrency limits; 15-min max; prefer for < 900s tasks |
| [DynamoDB Single-Table Design](https://www.alexdebrie.com/posts/dynamodb-single-table/) | Alex DeBrie | Access pattern driven; GSI/LSI for secondary access; avoid hot partitions |
| [SQS + Lambda Patterns](https://docs.aws.amazon.com/lambda/latest/dg/with-sqs.html) | AWS Docs | Batch size, visibility timeout = 6× Lambda timeout; DLQ setup |
| [RDS Proxy for Connection Pooling](https://aws.amazon.com/rds/proxy/) | AWS | Lambda → RDS: connection exhaustion; RDS Proxy multiplexes connections |
| [ElastiCache Patterns](https://docs.aws.amazon.com/whitepapers/latest/database-caching-strategies-using-redis/welcome.html) | AWS Whitepaper | Lazy-loading vs write-through vs write-behind; Redis vs Memcached |
| [Kinesis vs SQS vs SNS vs EventBridge](https://aws.amazon.com/blogs/compute/choosing-the-right-event-routing-service-for-your-application/) | AWS Blog | Kinesis: ordered, replay, analytics; SQS: queue/dequeue; SNS: fan-out; EventBridge: routing |

### GCP Architecture Patterns

| Resource | What It Covers | Use Case |
|---------|----------------|---------|
| ⭐ [GCP Architecture Center](https://cloud.google.com/architecture) | Reference architectures across all GCP products | Canonical GCP design patterns |
| [GCP Best Practices for Microservices](https://cloud.google.com/architecture/microservices-architecture-introduction) | GKE + Anthos + Cloud Run + Pub/Sub | GCP microservices stack |
| [BigQuery Architecture](https://cloud.google.com/bigquery/docs/introduction) | Serverless data warehouse; columnar; separation of storage and compute | Analytical workloads; Dremel descendent |
| [Pub/Sub Patterns](https://cloud.google.com/pubsub/docs/overview) | At-least-once; push + pull; fan-out | GCP equivalent of Kinesis + SNS hybrid |

### Azure Architecture Patterns

| Resource | What It Covers | Use Case |
|---------|----------------|---------|
| ⭐ [Azure Architecture Center](https://learn.microsoft.com/en-us/azure/architecture/) | Reference architectures + cloud design patterns | Canonical Azure designs; best cloud pattern library |
| [Azure Application Architecture Guide](https://learn.microsoft.com/en-us/azure/architecture/guide/) | N-tier → microservices → event-driven → CQRS | Architecture style selection guide |
| [Azure Service Bus vs Event Hubs vs Event Grid](https://learn.microsoft.com/en-us/azure/service-bus-messaging/compare-messaging-services) | Queue vs streaming vs routing messaging | Choosing the right Azure messaging service |

---

## 4. Books

| Book | Author(s) | Why It Matters | Key Topics |
|------|----------|---------------|-----------|
| ⭐ [Designing Data-Intensive Applications (DDIA)](https://dataintensive.net/) | Martin Kleppmann | The definitive reference for distributed systems design; cited in every senior interview | Replication, partitioning, transactions, consensus, stream processing |
| ⭐ [System Design Interview Vol. 1](https://www.amazon.com/System-Design-Interview-insiders-Second/dp/B08CMF2CQF) | Alex Xu | Most interview-targeted reference; covers 16 common systems | URL shortener, rate limiter, news feed, chat, video streaming |
| ⭐ [System Design Interview Vol. 2](https://www.amazon.com/System-Design-Interview-Insiders-Guide/dp/1736049119) | Alex Xu & Sahn Lam | Harder and more nuanced designs than Vol. 1 | Proximity service, ad click aggregation, hotel reservation, payment |
| [Designing Distributed Systems](https://www.oreilly.com/library/view/designing-distributed-systems/9781491983638/) | Brendan Burns (Kubernetes co-creator) | Distributed system patterns with container/Kubernetes framing | Sidecar, ambassador, adapter patterns; multi-node patterns |
| [Building Microservices (2nd Ed.)](https://www.oreilly.com/library/view/building-microservices-2nd/9781492034018/) | Sam Newman | Service decomposition, communication, testing, deployment | Domain-driven decomposition, service mesh, saga, API gateway |
| [The Site Reliability Engineering Book](https://sre.google/sre-book/table-of-contents/) | Google SRE Team | Google's production operations philosophy; SLOs, error budgets, toil | SLI/SLO/SLA, incident management, eliminating toil, load testing |
| [Software Architecture: The Hard Parts](https://www.oreilly.com/library/view/software-architecture-the/9781492086888/) | Ford, Richards, Sadalage, Dehghani | Trade-off analysis for modern distributed architectures; anti-pattern coverage | Service granularity, coupling analysis, data decomposition, sagas |
| [Fundamentals of Software Architecture](https://www.oreilly.com/library/view/fundamentals-of-software/9781492043447/) | Ford & Richards | Architecture styles, characteristics, decision-making framework | Architecture kata, coupling, cohesion, architecture styles matrix |
| [Understanding Distributed Systems](https://www.oreilly.com/library/view/understanding-distributed/9781838430214/) | Roberto Vitillo | Modern distributed systems primer; readable and concise | Networking, coordination, replication, transactions, observability |
| [Database Internals](https://www.databass.dev/) | Alex Petrov | Storage engine internals; B-trees, LSM trees, WAL, consensus | For deep-dive on storage engine design; LLD complement to DDIA |

---

## 5. Courses & Practice Platforms

### System Design Courses

| Course | Provider | Format | What Makes It Unique |
|--------|---------|--------|---------------------|
| ⭐ [Grokking the System Design Interview](https://www.designgurus.io/course/grokking-the-system-design-interview) | DesignGurus (Educative) | Text + diagrams | The original SD interview prep course; 25 systems; breadth coverage |
| ⭐ [Grokking the Advanced System Design Interview](https://www.designgurus.io/course/grokking-the-advanced-system-design-interview) | DesignGurus | Text + diagrams | Deep-dives on distributed systems primitives; harder systems |
| ⭐ [System Design Fundamentals (ByteByteGo)](https://bytebytego.com/) | Alex Xu (ByteByteGo) | Video + PDF | Best visual explanations; Vol. 1 & 2 content in video form |
| [Hello Interview — System Design](https://www.hellointerview.com/learn/system-design/in-a-hurry/introduction) | Hello Interview | Interactive | Structured framework; feedback on designs; good for blind spots |
| [Exponent System Design](https://www.tryexponent.com/courses/system-design) | Exponent | Video + mock interviews | Real mock interviews from ex-FAANG; structured feedback |
| [System Design Masterclass (Codemia)](https://codemia.io/) | Codemia | Practice + AI feedback | AI-powered design feedback; large question bank |
| [Acing the System Design Interview (Manning)](https://www.manning.com/books/acing-the-system-design-interview) | Zhiyong Tan | Book + exercises | Strong on distributed primitives; explains why not just what |

### Practice Platforms

| Platform | What It Offers | Best For |
|---------|---------------|---------|
| ⭐ [ByteByteGo Newsletter](https://blog.bytebytego.com/) | Weekly HLD visuals + deep-dives; free newsletter | Visual learner; consistent weekly practice |
| [HighScalability.com](http://highscalability.com/) | Architecture deep-dives of real systems; long-running archive | Real-world architecture case studies; 200+ companies |
| [InfoQ Architecture](https://www.infoq.com/architecture-design/) | Conference talks + articles from practitioners | Current industry thinking; how companies solved specific problems |
| [The System Design Primer (GitHub)](https://github.com/donnemartin/system-design-primer) | Open-source SD study guide; 250k+ stars; covers all basics | Free; comprehensive starting point for junior → senior |
| [Arpit Bhayani's System Design](https://arpitbhayani.me/system-design) | Deep-dive blog + YouTube on specific components | Rate limiters, ID generators, caches — component-level mastery |

---

## 6. Engineering Blogs by Company

Subscribe to these. Engineers at these companies post production-grade architecture decisions. This is gold for interview prep — you get to cite real incidents.

### Tier 1 — Must Follow

| Blog | Company | Best Content Areas |
|------|---------|-------------------|
| ⭐ [Netflix Tech Blog](https://netflixtechblog.com/) | Netflix | Microservices, streaming, chaos engineering, recommendations |
| ⭐ [Uber Engineering Blog](https://www.uber.com/blog/engineering/) | Uber | Geospatial, real-time dispatch, data infrastructure, migrations |
| ⭐ [Meta Engineering Blog](https://engineering.fb.com/) | Meta | Social graph, caching, messaging, newsfeed, AI infra |
| ⭐ [Google Research Blog](https://research.google/) | Google | Spanner, TrueTime, ML infra, search, maps |
| ⭐ [AWS Architecture Blog](https://aws.amazon.com/blogs/architecture/) | Amazon | Reference architectures, Well-Architected reviews, service deep-dives |
| ⭐ [Stripe Engineering Blog](https://stripe.com/blog/engineering) | Stripe | Payments, idempotency, reliability, distributed systems |
| [LinkedIn Engineering Blog](https://engineering.linkedin.com/blog) | LinkedIn | Feed, search, Kafka origin, data infrastructure |
| [Airbnb Engineering Blog](https://medium.com/airbnb-engineering) | Airbnb | Search, payments, ML, monolith migration |
| [Discord Engineering Blog](https://discord.com/blog/engineering) | Discord | Message storage, WebSockets, Elixir at scale, ScyllaDB |
| [Dropbox Tech Blog](https://dropbox.tech/) | Dropbox | File sync, metadata storage, CRDT-based collaboration |

### Tier 2 — Follow for Specific Topics

| Blog | Company | Best Content Areas |
|------|---------|-------------------|
| [Pinterest Engineering](https://medium.com/pinterest-engineering) | Pinterest | Image search, recommendation, ad systems |
| [Twitter Engineering Blog](https://blog.twitter.com/engineering) | Twitter (X) | Timeline, snowflake IDs, distributed KV |
| [Slack Engineering](https://slack.engineering/) | Slack | Real-time messaging, channel history, presence |
| [DoorDash Engineering](https://doordash.engineering/blog/) | DoorDash | Logistics, real-time ETA, marketplace systems |
| [Shopify Engineering](https://shopify.engineering/) | Shopify | E-commerce at scale, flash sales, multi-tenant SaaS |
| [Cloudflare Blog](https://blog.cloudflare.com/) | Cloudflare | Edge computing, DNS, CDN, DDoS, eBPF |
| [GitHub Engineering](https://githubengineering.com/) | GitHub | Git at scale, CI/CD, code search, collaboration |
| [Figma Engineering](https://www.figma.com/blog/section/engineering/) | Figma | CRDTs for collaborative editing, WebAssembly, multiplayer |
| [Canva Engineering](https://www.canva.dev/blog/engineering/) | Canva | Document rendering, real-time collaboration, image processing |

### Curated Aggregators

| Resource | What It Does | Update Frequency |
|---------|-------------|-----------------|
| ⭐ [The Morning Paper](https://blog.acolyer.org/) | Academic paper summaries; Adrian Colyer; 5+ years of archive | Historical; invaluable archive |
| [HighScalability.com](http://highscalability.com/) | "This week in high scalability" + deep dives | Weekly |
| [Architecture Notes](https://architecturenotes.co/) | Deep-dive architecture breakdowns with diagrams | Monthly |
| [System Design Newsletter (Neo Kim)](https://newsletter.systemdesign.one/) | Weekly system design case studies with diagrams | Weekly |
| [ByteByteGo Newsletter](https://blog.bytebytego.com/) | Visual system design concepts + case studies | Weekly |

---

## 7. GitHub Repositories & Study Guides

| Repository | Stars | What It Covers | Best For |
|-----------|-------|----------------|---------|
| ⭐ [System Design Primer](https://github.com/donnemartin/system-design-primer) | 270k+ | Comprehensive SD study guide; scalability, databases, caching, CDN, queues | Starting point; covers all primitives with diagrams |
| ⭐ [Awesome System Design Resources](https://github.com/ashishps1/awesome-system-design-resources) | 15k+ | Curated list: books, blogs, videos, papers; updated actively | Discovery; finding new resources |
| [Awesome Scalability](https://github.com/binhnguyennus/awesome-scalability) | 58k+ | Patterns + case studies organized by scalability principle | Deep breadth of production case studies |
| [System Design 101 (ByteByteGo)](https://github.com/ByteByteGoHq/system-design-101) | 60k+ | Visual explainers for protocols, patterns, components | Quick visual review of fundamentals |
| [Awesome Distributed Systems](https://github.com/theanalyst/awesome-distributed-systems) | 10k+ | Papers, books, courses on distributed systems | Academic and production depth |
| [Distributed Systems Reading Group](https://dsrg.pdos.csail.mit.edu/) | — | MIT's curated distributed systems papers + discussion notes | Paper-by-paper deep understanding |
| [Papers We Love](https://github.com/papers-we-love/papers-we-love) | 90k+ | Classic CS and distributed systems papers organized by topic | Finding the original sources |
| [Awesome CTO](https://github.com/kuchin/awesome-cto) | 25k+ | Engineering leadership, architecture, team management | Principal/Staff eng scope beyond just technical |

---

## 8. Quick-Access by Topic

### "Design a URL shortener / unique ID generator" →
[Snowflake ID (Twitter)](https://blog.twitter.com/engineering/en_us/a/2010/announcing-snowflake) · [Alex Xu Vol. 1 Ch. 7](https://bytebytego.com/courses/system-design-interview/design-a-url-shortener) · [System Design Primer — ID generation](https://github.com/donnemartin/system-design-primer) · [Consistent Hashing paper](https://dl.acm.org/doi/10.1145/258533.258660)

### "Design a distributed cache" →
[Scaling Memcached at Facebook](https://www.usenix.org/system/files/conference/nsdi13/nsdi13-final170_update.pdf) · [DDIA Ch. 5 (Replication)](https://dataintensive.net/) · [ElastiCache Patterns (AWS)](https://docs.aws.amazon.com/whitepapers/latest/database-caching-strategies-using-redis/welcome.html) · [Redis Architecture](https://redis.io/docs/management/replication/)

### "Design a news feed / social timeline" →
[LinkedIn FollowFeed](https://engineering.linkedin.com/blog/2016/03/followfeed--linkedin-s-feed-made-faster-and-smarter) · [Facebook TAO paper](https://www.usenix.org/conference/atc13/technical-sessions/presentation/bronson) · [Twitter Timeline](https://www.infoq.com/presentations/Twitter-Timeline-Scalability/) · [Alex Xu Vol. 1 Ch. 11](https://bytebytego.com/)

### "Design a chat / messaging system" →
[Discord Billions of Messages](https://discord.com/blog/how-discord-stores-billions-of-messages) · [Slack Engineering Blog](https://slack.engineering/) · [Facebook Messenger Migration](https://engineering.fb.com/2018/06/26/core-infra/migrating-messenger-storage-to-optimize-performance/) · [Alex Xu Vol. 1 Ch. 12](https://bytebytego.com/)

### "Design a distributed message queue / event streaming" →
[Kafka paper (LinkedIn)](https://www.microsoft.com/en-us/research/wp-content/uploads/2017/09/Kafka.pdf) · [Jay Kreps — The Log](https://engineering.linkedin.com/distributed-systems/log-what-every-software-engineer-should-know-about-real-time-datas-unifying) · [Kinesis vs SQS vs SNS vs EventBridge](https://aws.amazon.com/blogs/compute/choosing-the-right-event-routing-service-for-your-application/) · [MillWheel paper](https://static.googleusercontent.com/media/research.google.com/en//pubs/archive/41378.pdf)

### "Design a ride-sharing / location-based system" →
[Uber H3](https://www.uber.com/blog/h3/) · [Uber Dispatch (Ringpop)](https://www.uber.com/blog/introducing-ringpop-consistent-hash-ring/) · [Uber Surge Pricing](https://www.uber.com/blog/engineering/) · [Alex Xu Vol. 2 — Proximity Service](https://bytebytego.com/)

### "Design a video streaming system" →
[Netflix CDN (Open Connect)](https://netflixtechblog.com/how-netflix-works-with-isps-around-the-globe-to-deliver-a-great-viewing-experience-56ccff8f61e) · [Netflix Keystone Streaming](https://netflixtechblog.com/keystone-real-time-stream-processing-platform-a3ee651812a) · [AWS CloudFront + MediaLive](https://aws.amazon.com/solutions/implementations/video-streaming-on-aws/) · [Alex Xu Vol. 1 Ch. 14](https://bytebytego.com/)

### "Design a distributed database / storage system" →
[Dynamo paper](https://www.allthingsdistributed.com/files/amazon-dynamo-sosp2007.pdf) · [Bigtable paper](https://static.googleusercontent.com/media/research.google.com/en//archive/bigtable-osdi06.pdf) · [Spanner paper](https://static.googleusercontent.com/media/research.google.com/en//archive/spanner-osdi2012.pdf) · [DDIA by Kleppmann](https://dataintensive.net/)

### "Design a search engine / full-text search" →
[LinkedIn Galene Search](https://engineering.linkedin.com/search/did-you-mean-galene) · [Airbnb Search Architecture](https://medium.com/airbnb-engineering/airbnb-search-architecture-4d0aa73fea8c) · [Elasticsearch Architecture](https://www.elastic.co/guide/en/elasticsearch/reference/current/scalability.html) · [Dremel paper](https://static.googleusercontent.com/media/research.google.com/en//pubs/archive/36632.pdf)

### "Design a payment system" →
[Stripe Idempotency Keys](https://stripe.com/blog/idempotency) · [Airbnb Payments](https://medium.com/airbnb-engineering/scaling-airbnbs-payment-platform-43ebfc99b324) · [Saga Pattern (Azure)](https://learn.microsoft.com/en-us/azure/architecture/reference-architectures/saga/saga) · [Alex Xu Vol. 2 — Payment System](https://bytebytego.com/)

### "Design a rate limiter" →
[Stripe Rate Limiters](https://stripe.com/blog/rate-limiters) · [Cloudflare Rate Limiting](https://blog.cloudflare.com/counting-things-a-lot-of-different-things/) · [Alex Xu Vol. 1 Ch. 4](https://bytebytego.com/) · [Token bucket vs leaky bucket vs sliding window](https://arpitbhayani.me/blogs/rate-limiting)

### "Discuss CAP / consistency trade-offs" →
[Brewer's CAP Theorem](https://www.cs.berkeley.edu/~brewer/cs262b-2004/PODC-keynote.pdf) · [PACELC](https://dl.acm.org/doi/10.1109/MC.2012.33) · [DDIA Ch. 9 (Consistency and Consensus)](https://dataintensive.net/) · [Dynamo paper §4 (eventual consistency)](https://www.allthingsdistributed.com/files/amazon-dynamo-sosp2007.pdf)

### "Design observability / distributed tracing" →
[Dapper paper (Google)](https://static.googleusercontent.com/media/research.google.com/en//pubs/archive/36356.pdf) · [Stripe Distributed Tracing](https://stripe.com/blog/distributed-tracing) · [OpenTelemetry docs](https://opentelemetry.io/docs/) · [Monarch (Google metrics)](https://www.vldb.org/pvldb/vol13/p3181-adams.pdf)
