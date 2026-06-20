# Data Mesh Architecture Pattern

## Overview
Data Mesh is a decentralised, domain-oriented architecture for data at scale. It treats data as a product owned by domain teams, applies platform thinking to data infrastructure, and governs quality and access through federated standards rather than central control.

Coined by Zhamak Dehghani (ThoughtWorks, 2019). Addresses the failure mode of centralised data platforms: data lake/warehouse teams become bottlenecks; data quality degrades because the team owning the data is different from the team responsible for it; data pipelines are brittle and tightly coupled.

---

## The Four Principles

### 1. Domain-Oriented Ownership
Data is owned and served by the domain team that produces it — not a central data team.

```
Order domain team owns: orders data product, order events, order analytics
Payment domain team owns: payment data, transaction events, refund analytics
User domain team owns: user profiles, behaviour events, segmentation data
```

The team that knows the data best (because they build the system that produces it) is responsible for its quality, freshness, and access.

### 2. Data as a Product
Each domain's data offering is treated as a product with users (data consumers), SLAs, documentation, and a contract:

| Attribute | Specification |
|---|---|
| **Discoverability** | Listed in the data catalogue with description and owner |
| **Addressability** | Stable, well-known access endpoint (S3 path, API, Kafka topic) |
| **Self-describing** | Schema available in schema registry; README with semantics |
| **Trustworthy** | SLAs on freshness, completeness, accuracy |
| **Interoperable** | Standard formats (Parquet, Avro); standard protocols |
| **Secure** | Governed by federated policy; consumers request access |

### 3. Self-Serve Data Platform
A platform team builds and operates the infrastructure that allows domain teams to create data products without data engineering expertise:

- Automated pipeline scaffolding (create a new data product in hours, not weeks)
- Storage provisioning (S3, schema registry, Glue catalog)
- Quality monitoring tooling (Great Expectations, Deequ)
- Data lineage tracking (Apache Atlas, OpenLineage)
- Access control management (Lake Formation, attribute-based)
- Compute-on-demand (EMR Serverless, Athena, Redshift Serverless)

### 4. Federated Computational Governance
Standards for interoperability and compliance are defined centrally; enforcement is automated and decentralised:

- **Centrally defined**: data classification labels (PII, financial, internal), retention policies, encryption requirements, access audit logging
- **Locally enforced**: each data product team applies policies to their own products; platform validates compliance automatically
- **No manual approvals**: governance is code — if a data product passes automated checks, it's compliant

---

## Data Product Types

| Type | Description | AWS implementation |
|---|---|---|
| **Source-aligned** | Raw domain data, close to operational systems | CDC from RDS → Kafka → S3 (raw zone) |
| **Aggregate** | Summarised, joined, enriched | Glue ETL → S3 (curated zone) |
| **Consumer-aligned** | Optimised for specific consumer use case | Pre-computed Athena CTAS → S3 |
| **Stream** | Real-time data product | Kafka topic (consumer accesses directly) |

---

## Data Mesh on AWS

### Reference Architecture
```
Domain: Orders
  ├── Operational DB (Aurora PostgreSQL)
  ├── CDC pipeline (DMS or Debezium → MSK Kafka)
  ├── Raw data product (S3: s3://datalake/orders/raw/, Parquet, Hive partitioned)
  ├── Curated product (S3: s3://datalake/orders/curated/, enriched, cleaned)
  ├── Glue Catalog (table definitions for both)
  ├── Lake Formation permissions (who can query what)
  └── Data product registry entry (internal catalogue: DataHub or custom)

Domain: Payments
  ├── Same structure, independently owned
  └── ...

Platform team provides:
  ├── Account vending for new domains (one S3 prefix or account per domain)
  ├── Standard Glue Catalog conventions
  ├── Lake Formation policy templates
  ├── EMR Serverless / Athena for compute
  └── DataHub (or similar) for data discovery
```

### Data Access Control (Lake Formation)
AWS Lake Formation provides fine-grained access control over the Glue Catalog:

```
Lake Formation policy:
- Marketing team: can SELECT from orders/curated (view: columns {order_id, category, amount}, NO user_id)
- Finance team: can SELECT from payments/curated (all columns) WHERE NOT PII_FIELD
- Data science: can SELECT from orders/raw with row-level filter (no EU orders — GDPR scope)
```

Lake Formation column-level and row-level security applies across Athena, Redshift Spectrum, and EMR — consistent access control regardless of compute engine.

---

## Data Product Interface Contract

Each data product must publish a contract consumers can rely on:

```yaml
# data-product.yaml (committed to domain team's repo)
name: orders-curated
owner: orders-team@company.com
description: "Cleaned, enriched order data. One row per order. Excludes cancelled orders older than 90 days."
version: "2.1"
access: "https://internal.company.com/data-catalogue/orders-curated"

schema:
  format: parquet
  registry: "s3://schema-registry/orders-curated/v2/schema.avsc"
  glue_database: "orders"
  glue_table: "orders_curated"

sla:
  freshness_max_lag: "1 hour"          # data is never more than 1 hour old
  completeness: "99.9%"                # at most 0.1% missing records per day
  availability: "99.5%"                # Athena can query this data 99.5% of the time

partitioning:
  - column: "year"
  - column: "month"
  - column: "day"

pii_fields: []                         # PII has been removed; user_id replaced by hashed_user_id
data_classification: "internal"

access_request: "https://access.internal/request/orders-curated"
```

---

## Data Mesh vs Data Warehouse vs Data Lake

| Dimension | Data Warehouse | Data Lake | Data Mesh |
|---|---|---|---|
| **Organisation** | Centralised | Centralised | Decentralised by domain |
| **Ownership** | Central data team | Central data team | Domain teams |
| **Scalability** | Limited by central team capacity | Limited by data engineering capacity | Scales with org (domain teams grow independently) |
| **Data quality** | Central team responsible (far from source) | Often low ("data swamp") | Domain team responsible (close to source) |
| **Bottleneck** | Central data warehouse team | Central data lake/pipeline team | Platform team; resolved by self-serve |
| **Best for** | Structured reporting, BI | Large volume exploration, ML | Large orgs with many domains; federated governance |
| **Failure mode** | Warehouse team can't keep up | Data swamp — nobody trusts the data | Inconsistent standards across domains |

---

## Federated Governance: What's Centralised vs Decentralised

### Centralised (defined by governance council)
- Data classification taxonomy (PII, financial, public, internal, confidential)
- Retention policies (PII: 2 years max; audit logs: 7 years)
- Interoperability standards (must use Parquet or Avro; must use Glue Catalog; must use CloudEvents for streaming)
- Quality SLA minimums (every data product must have freshness ≤ 24h; completeness ≥ 99%)
- Access control protocol (Lake Formation; IAM; must request access for PII)

### Decentralised (enforced per domain)
- Schema design for their domain
- ETL/pipeline implementation (any tech, as long as output meets standards)
- Freshness target (can be better than minimum; not worse)
- Data enrichment and transformation logic
- Internal data product versioning and deprecation schedule

---

## Trade-offs

| Dimension | Data Mesh | Centralised Data Lake/Warehouse |
|---|---|---|
| **Scalability** | High — scales with domain teams | Limited by central team |
| **Data quality** | High — owner closest to source | Lower — central team doesn't know domain |
| **Consistency** | Risk of inconsistency across domains | Central team enforces consistency |
| **Operational complexity** | Very high — many data products to govern | Lower — central team manages everything |
| **Time to new data product** | Fast (domain teams self-serve) | Slow (central team backlog) |
| **Cross-domain joins** | Harder — must access multiple data products | Easy — all in one warehouse |
| **Organisation readiness** | Requires mature domain teams, platform | Works with less mature orgs |
| **Implementation cost** | High — platform investment + cultural change | Lower — familiar pattern |

**Data Mesh anti-pattern**: applying it to a small organisation (< 50 engineers or < 5 domains). The overhead of platform-building and domain ownership doesn't pay off until you have the bottleneck problem it solves.

---

## Best Practices

1. **Start with one domain as the pioneer** — don't try to mesh the whole organisation at once; one domain proves the model
2. **Platform before product** — the self-serve platform must exist before domain teams can own data products; don't make teams build their own pipelines from scratch
3. **Automate the contract validation** — data product SLAs must be monitored automatically; manual audits don't scale
4. **Data catalogue is the front door** — every data product in the catalogue with description, owner, schema, and SLA; without discovery, nobody can use the products
5. **Treat the data platform team as an internal product team** — they have domain teams as customers; build what the customers need, not what's technically interesting
6. **Define PII taxonomy before you start** — classification must be agreed before data products are published; retrofitting is painful
7. **Cross-domain joins require planning** — when consumer A needs data from domains B and C, there are options: a) consumer queries both products independently; b) one domain creates an aggregated product; c) platform provides a join layer (Athena federation)
8. **Data contracts are versioned** — schema evolution follows the same rules as API versioning; deprecation with a migration window

---

## FAANG Interview Points

**"Design a data platform for an org with 50 product teams"**: Data mesh. Each team owns their domain's data products. Platform team builds self-serve infrastructure (account vending, S3 + Glue + Lake Formation + Athena). Federated governance (data classification, retention, quality SLAs) defined by governance council. DataHub (or similar) for data discovery. One S3 prefix or account per domain for blast-radius isolation.

**"How do you ensure data quality in a decentralised data platform?"**: Domain team accountability (owners have SLA metrics visible on their dashboards). Automated quality checks in the pipeline (Great Expectations assertions run on every batch, fail the pipeline if violations exceed threshold). Central governance validates all data products meet minimum quality standards before being listed in the catalogue. Automated freshness monitoring (CloudWatch alarm if data product hasn't updated in > 2× expected interval).

**"Data warehouse vs data lake vs data mesh"**: Warehouse: structured, governed, SQL, good for BI but central team bottleneck. Lake: flexible, scalable, unstructured possible — but degrades to data swamp without strong governance. Mesh: solves the bottleneck and quality problem by pushing ownership to domain teams — but requires platform maturity and org discipline. Use mesh when you have many independent domains and the central team is visibly the bottleneck.
