# AWS Athena

## Overview
Athena is a serverless, interactive SQL query service for data stored in S3. It uses Presto (now Trino) as the query engine and Apache Hive metastore syntax for schema definitions. You pay $5 per TB of data scanned — no infrastructure to provision.

**Core value proposition**: run SQL against petabytes of data in S3 without loading it into a database. The data stays in S3; Athena reads it only when you query.

---

## Architecture

```
Client (Console / JDBC / API)
    ↓ SQL query
AWS Athena (Presto/Trino engine — serverless)
    ↓ Reads schema from
AWS Glue Data Catalog (table definitions, partitions, schema)
    ↓ Scans data from
S3 (Parquet/ORC/JSON/CSV files, partitioned by date/region/etc.)
    ↓ Results written to
S3 Results Bucket (query output, CSV or Parquet)
```

Athena is also integrated with:
- **AWS Lake Formation**: fine-grained column and row-level access control on top of Glue catalog
- **QuickSight**: BI dashboards directly on Athena queries
- **Glue ETL**: Glue transforms raw data into Parquet before Athena queries it

---

## Query Cost Optimisation (the most important topic)

Athena charges $5/TB scanned. The difference between a well-optimised query and a naive one can be **100–1000×** in cost.

### 1. Use Columnar Format (Parquet or ORC)
```
Query on CSV file (100 GB): scans 100 GB = $0.50
Query on Parquet (same data, 10 GB compressed, columnar): scans 1–3 GB = $0.005–0.015
Cost reduction: 30–100×
```

Parquet stores data column-by-column. `SELECT name, email FROM users WHERE status='active'` reads only the `name`, `email`, and `status` columns — not all columns. This is **column pruning**.

**ORC vs Parquet**:
| | Parquet | ORC |
|---|---|---|
| Columnar | Yes | Yes |
| Compression | Snappy/Zstd | Zlib/Snappy |
| Predicate pushdown | Yes | Yes |
| Best for | Spark, Athena, Presto | Hive, EMR |
| Athena preference | **Preferred** | Supported |

### 2. Partitioning
Partitions are directories in S3. Athena reads only partitions matching your WHERE clause.

```sql
-- Unpartitioned: scans 365 days of data = 3.65 TB = $18.25
SELECT * FROM events WHERE year = '2024' AND month = '01' AND day = '15';

-- Partitioned by year/month/day: scans 1 day = 10 GB = $0.05
-- Partition layout: s3://bucket/events/year=2024/month=01/day=15/
```

**Hive-style partitioning** (Athena auto-discovers): `year=2024/month=01/day=15/`
**Custom prefix partitioning**: `2024/01/15/` — requires manual `MSCK REPAIR TABLE` or Glue crawler.

**Partition projection**: for date-based partitions, define a projection in the table DDL so Athena generates partition paths mathematically instead of querying the Glue catalog:
```sql
TBLPROPERTIES (
  'projection.enabled'='true',
  'projection.dt.type'='date',
  'projection.dt.range'='2020-01-01,NOW',
  'projection.dt.format'='yyyy-MM-dd',
  'storage.location.template'='s3://bucket/events/${dt}/'
)
```
Eliminates Glue catalog calls per partition — significant speedup for queries over many days.

### 3. File Size
```
Too small (< 10 MB): thousands of files → high overhead listing S3, opening files
Too large (> 1 GB): can't parallelize well across query workers
Optimal: 64 MB – 512 MB per file after compression
```

Compact small files with Glue ETL job or S3 Batch Operations before querying.

### 4. Compression
Always compress. For Parquet: Snappy (fast, moderate compression) or Zstd (slower, better compression). For JSON/CSV: gzip (splits at 128MB boundaries for splittable reads) or Zstd.

**Splittable compression**: gzip files are NOT splittable in CSV/JSON. A 10 GB gzip CSV file is read by a single Athena worker. Use bzip2 (splittable) for large text files, or better: use Parquet.

### 5. Approximate Functions
For analytics on massive datasets, use approximate functions when exact counts aren't needed:
```sql
-- Exact count distinct (expensive — requires sort/hash of all values)
SELECT COUNT(DISTINCT user_id) FROM events; -- scans all data

-- Approximate (HyperLogLog — 2% error, 10-100× faster)
SELECT approx_distinct(user_id) FROM events;
```

---

## DDL & Table Management

### External Table (most common)
```sql
CREATE EXTERNAL TABLE IF NOT EXISTS events (
  event_id STRING,
  user_id STRING,
  event_type STRING,
  properties MAP<STRING, STRING>,
  timestamp BIGINT
)
PARTITIONED BY (year STRING, month STRING, day STRING)
STORED AS PARQUET
LOCATION 's3://my-datalake/events/'
TBLPROPERTIES ('parquet.compress'='SNAPPY');
```

### Add Partitions
```sql
-- Manual single partition:
ALTER TABLE events ADD PARTITION (year='2024', month='01', day='15')
LOCATION 's3://my-datalake/events/year=2024/month=01/day=15/';

-- Auto-discover all partitions (expensive on large tables):
MSCK REPAIR TABLE events;

-- Preferred: Glue crawler or Partition Projection (no catalog calls)
```

### CTAS (Create Table As Select)
Generate a new optimised table from a query:
```sql
CREATE TABLE events_parquet
WITH (
  format = 'PARQUET',
  parquet_compression = 'SNAPPY',
  partitioned_by = ARRAY['year', 'month'],
  bucketed_by = ARRAY['user_id'],
  bucket_count = 100,
  external_location = 's3://my-datalake/events_parquet/'
)
AS SELECT * FROM events_raw;
```
Use CTAS to convert CSV → Parquet, to repartition data, or to generate pre-computed aggregation tables.

---

## Athena Federated Query

Query data outside S3 using Lambda-based connectors:
- **DynamoDB**: query DynamoDB tables with SQL
- **RDS/Aurora**: query relational databases
- **Redshift**: cross-query Redshift + S3
- **CloudWatch Logs**: SQL over CloudWatch log groups
- **Custom**: any data source via custom Lambda connector (Kafka, MongoDB, etc.)

```sql
-- Query DynamoDB from Athena
SELECT * FROM "lambda:dynamodb".mydb.orders
WHERE order_date > '2024-01-01' AND total_amount > 100;
```

Federated queries run the Lambda connector for each data source, then join results in Athena's distributed engine. Performance is bounded by the Lambda connector's throughput.

---

## Athena for Cost Allocation / CloudTrail Analysis

Athena is the standard tool for querying CloudTrail and AWS Cost & Usage Report (CUR):

```sql
-- Find which IAM role made the most S3 PutObject calls
SELECT useridentity.arn, COUNT(*) as count
FROM cloudtrail_logs
WHERE eventname = 'PutObject' AND eventsource = 's3.amazonaws.com'
  AND year = '2024' AND month = '01'
GROUP BY 1 ORDER BY count DESC LIMIT 20;

-- Find top cost drivers by service last month
SELECT line_item_product_code, SUM(line_item_unblended_cost) as cost
FROM aws_cost_report
WHERE year = '2024' AND month = '01'
GROUP BY 1 ORDER BY cost DESC;
```

---

## Athena Workgroups

Workgroups segment query execution for cost control and access isolation:
- Enforce per-query data scan limits (prevent runaway queries)
- Separate result buckets per team/environment
- Cost allocation by workgroup tag
- Override result encryption settings

```json
// Workgroup with query scan limit:
{
  "EnforceWorkGroupConfiguration": true,
  "BytesScannedCutoffPerQuery": 10737418240  // 10 GB limit per query
}
```

---

## Athena vs Alternatives

| Dimension | Athena | Redshift Spectrum | BigQuery | Spark (EMR) |
|---|---|---|---|---|
| **Infrastructure** | Serverless | Redshift cluster required | Serverless | EMR cluster |
| **Pricing** | $5/TB scanned | $5/TB + Redshift cost | $5/TB (on-demand) | EC2 costs |
| **Startup time** | Seconds | Seconds (Redshift must be running) | Seconds | Minutes (cluster start) |
| **Concurrency** | 20 concurrent queries (default) | Bounded by Redshift cluster | Very high | Bounded by cluster |
| **Query performance** | Good with Parquet | Good; benefits from Redshift sortkeyss | Excellent | Excellent |
| **ML integration** | None native | Redshift ML | BigQuery ML | SageMaker + Spark |
| **Use when** | Ad-hoc S3 queries; AWS-native; serverless | S3 + Redshift mixed queries | GCP ecosystem | Complex ETL; ML; >1 hour queries |

---

## Monitoring & Alerting

| Metric | Alert condition |
|---|---|
| `DataScannedInBytes` | Spike → unexpected full-table scan; check for missing partition filter |
| `EngineExecutionTime` | P99 > SLA → optimise query or check file sizes |
| `QueryQueueTime` | High → approaching concurrent query limit |
| `QueryPlanningTime` | High → Glue catalog has too many partitions; use Partition Projection |
| Query failure rate | Via CloudTrail or Athena history | > 5% → schema mismatch or S3 access issue |

**Cost alert**: set a CloudWatch alarm on `DataScannedInBytes` per workgroup to detect unexpectedly expensive queries before the bill arrives.

---

## Best Practices

1. **Always use Parquet** for analytical data — 10–100× cost reduction vs CSV
2. **Partition by query patterns** — if you always filter by date, partition by date; if by region too, partition by date/region
3. **Use Partition Projection** for date partitions — eliminates Glue catalog overhead
4. **Compact small files** before querying — target 64MB–512MB per file
5. **Always include partition filter in WHERE clause** — never run a query without a partition predicate on large tables
6. **Use CTAS to materialise expensive queries** — compute once, query many times
7. **Set workgroup scan limits** for dev/staging — prevents accidental $500 full-table scans
8. **Use `approx_distinct`** for cardinality estimates — 100× faster than `COUNT(DISTINCT)`
9. **Compress with Snappy or Zstd** for Parquet; avoid gzip for CSV at scale (not splittable)
10. **Glue crawler on a schedule** to keep partition metadata updated for new data

---

## FAANG Interview Points

**"How do you query 10PB of S3 data affordably?"**: Parquet + Snappy + Hive partitioning + Partition Projection. A well-partitioned query scanning 10 GB instead of 10 TB = $0.05 instead of $50,000. CTAS for pre-aggregated views. Workgroup scan limits as cost guardrails.

**"Design a cost analytics platform on AWS"**: CloudTrail + Cost & Usage Report → S3 (Parquet, partitioned by account/date) → Glue Catalog → Athena for SQL analysis → QuickSight for dashboards. Automated daily Glue crawler. Partition Projection on date column.

**"Athena query is slow — how do you debug?"**: Check if partition filter is in WHERE clause. Check data format (CSV → Parquet). Check file sizes (small file problem). Check if statistics are up to date in Glue. Use `EXPLAIN` (Athena v3) to see query plan. Use `CTAS` to materialise intermediate results.
