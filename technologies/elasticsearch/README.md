# Elasticsearch — Overview & Decision Guide

**Type**: Distributed search and analytics engine  
**CAP Position**: AP (Availability + Partition Tolerance); near-real-time reads (NRT, ~1s lag)  
**Consistency Model**: Eventual — primary shard writes synchronously replicate to replicas; reads are NRT  
**Data Model**: JSON documents stored in inverted indexes, organised into shards (Lucene instances)  
**Write Model**: Append-to-translog → in-memory buffer → periodic Lucene segment refresh (default 1s)  
**Origin**: Shay Banon, 2010 (wrapper around Apache Lucene 2004); Elastic Inc. founded 2012

---

## What Is Elasticsearch?

Elasticsearch was born as a recipe search engine for Shay Banon's wife — a REST-friendly wrapper around Apache Lucene that hid Lucene's complexity and added distributed scaling. Today it is the dominant open-source search and analytics platform, used for full-text search, structured queries, log aggregation (ELK/EFK stack), security analytics (SIEM), and increasingly hybrid BM25 + dense-vector search for RAG pipelines.

The architectural bet: **invert Lucene's complexity behind a JSON HTTP API**, shard the index across nodes, and provide near-real-time indexing with a 1-second refresh window. This makes Elasticsearch fast to integrate, linearly scalable, and capable of sub-100ms search on billions of documents — at the cost of weak transactional guarantees and non-trivial operational overhead at scale.

---

## Quick-Reference Card

| Property | Value |
|----------|-------|
| CAP | AP — never blocks writes during partition; replicas may serve stale data |
| Consistency | NRT (near-real-time): writes visible within ~1s (refresh interval) |
| Data model | JSON documents → fields → inverted index terms |
| Write path | HTTP → coordinating node → primary shard → translog + memory buffer → periodic refresh |
| Read path | HTTP → coordinating node → scatter query to shards → gather + rank → fetch phase |
| Replication | Primary/replica shard pairs; replica count configurable per index |
| Query language | Query DSL (JSON); also SQL via X-Pack; EQL for event sequences |
| Horizontal scaling | Add data nodes; rebalance shards automatically |
| Multi-DC | Cross-Cluster Replication (CCR); Cross-Cluster Search (CCS) |
| Operational overhead | Medium-High — JVM heap tuning, shard sizing, index lifecycle management |
| Typical latency | < 10ms simple term queries; 50–200ms full-text multi-shard queries |
| Throughput | Clusters of 50+ nodes sustain millions of docs/min ingestion; petabyte-scale search |

---

## Decision Drivers: When to Choose Elasticsearch

**Choose Elasticsearch when ALL of the following are true:**

1. **Full-text search is required** — you need relevance ranking (BM25/TF-IDF), fuzzy matching, stemming, faceted navigation, or autocomplete over unstructured or semi-structured text
2. **Query patterns are ad-hoc and diverse** — you cannot pre-define every access pattern; users run arbitrary filters, aggregations, and text searches in combination
3. **Near-real-time visibility is acceptable** — you can tolerate ~1s indexing latency before data is searchable (not suited for banking ledgers or inventory that must read-your-own-writes)
4. **Read volume >> write volume** — Elasticsearch is read-optimised; inverted indexes are immutable segments; heavy update workloads cause write amplification
5. **Aggregation and analytics are part of the use case** — cardinality, histograms, geo-distance, percentiles across large document sets in sub-second latency

**The single most important question**: *Do you need relevance-ranked full-text search, or just filtering?* If yes, Elasticsearch. If no (you only need exact key lookups, range scans, or joins), choose a relational DB or Cassandra — you will pay Elasticsearch's operational overhead for no benefit.

---

## Use Cases

| Use Case | Why Elasticsearch Fits | Example Company |
|----------|----------------------|----------------|
| **Full-text search (e-commerce, docs)** | BM25 relevance scoring, faceted filters, autocomplete, multi-language analysis | GitHub (code search), Wikipedia, Shopify |
| **Log & metrics aggregation (ELK stack)** | Ingest millions of log lines/sec, full-text query on unstructured logs, Kibana dashboards | Netflix, Uber, LinkedIn, Cloudflare |
| **Security analytics / SIEM** | Sequence detection (EQL), anomaly detection, fast query over billions of events | Elastic SIEM, Crowdstrike, Palo Alto |
| **Geo-search** | Geo-point queries, geo-distance aggregation, polygon filters | Yelp, Foursquare, Uber (nearby driver search) |
| **Observability (APM / tracing)** | Correlate traces + logs + metrics in one store; Elastic APM | Elastic APM, many FAANG observability teams |
| **Hybrid search (BM25 + dense vector)** | Combined lexical + semantic ranking for RAG, semantic search | LinkedIn, Airbnb, modern LLM applications |

---

## Anti-Patterns: When NOT to Use Elasticsearch

| Anti-Pattern | Why It Fails | Better Alternative |
|-------------|-------------|-------------------|
| **Primary OLTP store** | No ACID transactions; NRT lag; no joins; update-heavy workloads cause segment fragmentation | PostgreSQL / MySQL |
| **Strong consistency reads** | Replica reads are stale until next refresh | PostgreSQL (synchronous replication) / Spanner |
| **Tiny datasets (< 1M docs)** | Operational overhead outweighs benefit; PostgreSQL full-text + `gin` index is sufficient | PostgreSQL with `tsvector` |
| **Very high write throughput without batching** | Document-level inverted index rebuild on every update; millions of singleton writes/sec kill performance | Cassandra (append-only) / Kafka → batch index |
| **Financial / inventory systems** | No serialisable isolation; no foreign keys | PostgreSQL / CockroachDB |
| **Frequent document updates (>50% of corpus/day)** | Each update = delete (tombstone) + re-insert; segment merge pressure is high | Purpose-built DB + periodic bulk re-index |

---

## Elasticsearch in the Broader Stack

Elasticsearch is almost always used **alongside** a primary database, not as a replacement:

```
Primary Store (Postgres / Cassandra / MongoDB)
         │
         │  Change Data Capture (Debezium / custom app events)
         ▼
  Elasticsearch Index  ──── Kibana / custom search UI
         │
         └─── Logstash / Fluentd (log ingestion) ──► Kibana
```

The canonical pattern: write to the source of truth → propagate to ES asynchronously for search and analytics.
