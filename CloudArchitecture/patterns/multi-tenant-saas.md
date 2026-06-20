# Multi-Tenant SaaS Architecture Pattern

## Overview
Multi-tenancy is the ability for a single system to serve multiple customers (tenants) from shared infrastructure while maintaining data isolation, performance isolation, and the illusion of a private deployment to each tenant.

Multi-tenancy is the foundational architectural decision in any SaaS product. It determines cost structure, compliance posture, scalability ceiling, and the operational model for the entire platform.

---

## Tenancy Models

### Silo (Dedicated per Tenant)
Each tenant has their own dedicated infrastructure stack:
```
Tenant A: own EC2, own RDS, own VPC, own S3 bucket
Tenant B: own EC2, own RDS, own VPC, own S3 bucket
Tenant N: own EC2, own RDS, own VPC, own S3 bucket
```

| Dimension | Value |
|---|---|
| Data isolation | Perfect — no shared infrastructure |
| Blast radius | Single tenant |
| Compliance | Strong (PCI, HIPAA, SOC2 per tenant) |
| Customisation | Per-tenant configuration, versions |
| Cost | Highest (N× infrastructure even at idle) |
| Operational overhead | Highest (N× deployments, N× monitoring) |
| Scale | Limited by infrastructure provisioning speed |
| **Use for** | Enterprise, regulated industries, strategic accounts, premium tier |

### Pool (Shared Infrastructure)
All tenants share the same infrastructure; data isolation via tenant ID:
```
Single ECS cluster → Single RDS (tenant_id column in every table)
Single DynamoDB tables (partition key includes tenant_id)
Single Lambda functions (request context carries tenant_id)
```

| Dimension | Value |
|---|---|
| Data isolation | Logical only (application-enforced via tenant_id) |
| Blast radius | All tenants (a bug in isolation logic exposes all data) |
| Compliance | Harder; must prove logical isolation suffices |
| Cost | Lowest (efficient bin-packing) |
| Operational overhead | Lowest (one deployment, one monitoring setup) |
| Noisy neighbour risk | High — one tenant can saturate shared resources |
| **Use for** | Free tier, SMB customers, high-volume low-value tenants |

### Bridge (Tiered Isolation)
Premium tenants get silo isolation; standard tenants share pool infrastructure:
```
Enterprise customers → dedicated stack per tenant (silo)
Growth customers → shared cluster, isolated DB per tenant (semi-silo)
Free/SMB customers → fully shared pool
```

This is the standard production model for mature SaaS platforms. Align isolation tier with business value:
- Free: pool
- Professional: pool with data isolation (separate schema or DB)
- Enterprise: full silo with dedicated infrastructure

---

## Data Isolation Patterns

### Row-Level Security (Shared DB, Shared Tables)
Every table has a `tenant_id` column. Every query must include `WHERE tenant_id = ?`. Enforced at:
- **ORM level**: custom base model that injects `tenant_id` into every query
- **PostgreSQL Row-Level Security**: database-enforced; even if application bug omits the filter, DB blocks access

```sql
-- PostgreSQL RLS
CREATE POLICY tenant_isolation ON orders
  FOR ALL TO app_user
  USING (tenant_id = current_setting('app.tenant_id')::uuid);

-- Application sets the setting per request
SET app.tenant_id = 'tenant-123';
SELECT * FROM orders;  -- automatically filtered to tenant-123
```

**Risk**: application must set the tenant context correctly on every request. A missing `SET` statement exposes all tenant data. Defense-in-depth: enable RLS as the backstop.

### Schema Per Tenant (Shared DB, Separate Schemas)
Each tenant gets their own PostgreSQL schema (`tenant_abc.orders`, `tenant_xyz.orders`).

```sql
SET search_path TO tenant_abc;
SELECT * FROM orders;  -- queries tenant_abc.orders, not tenant_xyz.orders
```

- Better isolation than row-level; schema migration per tenant is independent
- Harder to query across tenants (analytics, platform aggregations)
- PostgreSQL limit: thousands of schemas per DB is feasible; millions is not

### Database Per Tenant (Shared Instance, Separate Databases)
Each tenant has their own database within a shared RDS instance:

```
RDS instance → tenant_a_db, tenant_b_db, tenant_c_db
```

- Strong isolation; easy to export/delete one tenant's data (GDPR "right to erasure")
- RDS limit: 100 databases per instance
- Connection pooling complexity: each tenant DB needs its own connection pool

### Instance Per Tenant (Full Silo)
Separate RDS instance per tenant. Maximum isolation, highest cost.

---

## Noisy Neighbour Problem

The most critical operational challenge in pooled multi-tenancy.

**What it is**: Tenant A generates 10× normal load, consuming shared CPU/IO/connections, degrading performance for Tenants B, C, D sharing the same infrastructure.

**Detection**:
```
Metric: P95 latency per tenant_id
Alert: any tenant's P95 > 2× baseline for 5 consecutive minutes
Investigate: which tenant_id is responsible for the spike
```

**Mitigation strategies**:

| Strategy | Mechanism | Trade-off |
|---|---|---|
| **Request throttling** | Rate limit per tenant_id at API Gateway or application layer | Tenant experience degrades but others protected |
| **Queue per tenant** | Separate SQS queue per tenant; processing workers poll fair-share | More queues; complex routing |
| **Resource quota** | DynamoDB capacity units per tenant; Lambda reserved concurrency per tenant | Requires per-tenant provisioning |
| **Cell eviction** | Move high-consumption tenant to dedicated cell (silo) | Operational complexity |
| **Backpressure** | When tenant queue depth exceeds threshold, reject new requests with 429 | Requires good client retry behaviour |

---

## Tenant Context Propagation

Every layer of the stack must know the current tenant context. This is typically propagated as:

1. **JWT claim**: `{"sub": "user-123", "tenant_id": "tenant-abc", "plan": "enterprise"}`
2. **Request header**: `X-Tenant-ID: tenant-abc` (authenticated at API Gateway)
3. **Thread-local / request-scoped context**: extracted once at entry point, available throughout

```python
# FastAPI dependency injection (Python)
async def get_tenant_context(token: str = Depends(oauth2_scheme)) -> TenantContext:
    claims = verify_jwt(token)
    return TenantContext(
        tenant_id=claims['tenant_id'],
        plan=claims['plan'],
        feature_flags=get_feature_flags(claims['tenant_id'])
    )

@app.get("/orders")
async def list_orders(ctx: TenantContext = Depends(get_tenant_context), db: Session = Depends(get_db)):
    return db.query(Order).filter(Order.tenant_id == ctx.tenant_id).all()
```

**Critical**: validate tenant context at the boundary (API Gateway/Lambda authoriser). Never trust `tenant_id` from the request body — it must come from authenticated credentials.

---

## Tenant-Aware Observability

Metrics and logs must be tagged with `tenant_id` to enable per-tenant health monitoring:

```python
# CloudWatch EMF with tenant dimension
metrics.add_dimension(name="TenantId", value=ctx.tenant_id)
metrics.add_dimension(name="Plan", value=ctx.plan)
metrics.add_metric(name="APILatency", unit=MetricUnit.Milliseconds, value=latency_ms)
```

**Per-tenant dashboards**: QuickSight or Grafana dashboards showing each tenant's usage, error rate, and latency. Used for:
- Detecting noisy neighbours
- Capacity planning (when does a tenant need to be migrated to a larger cell?)
- Business reporting (usage-based billing)
- SLA compliance (enterprise tenants guaranteed P99 < 200ms)

---

## Tenant Onboarding / Offboarding

### Onboarding automation
```
New tenant registers → Account Vending Lambda:
  1. Create tenant record in control plane DB
  2. Provision data layer (schema or DB per tenant)
  3. Create default configuration in SSM Parameter Store
  4. Create feature flag overrides in LaunchDarkly
  5. Allocate to cell (routing table update)
  6. Send welcome email with credentials
```

All steps must be idempotent (onboarding can be retried safely on failure).

### Offboarding (GDPR compliance)
```
Tenant deletion request → Offboarding Lambda:
  1. Deactivate tenant (mark inactive, block new requests)
  2. Export tenant data to S3 (customer receives their data)
  3. Delete all tenant records from DB (schema drop or row deletion)
  4. Purge S3 objects with tenant prefix
  5. Revoke API keys and access tokens
  6. Remove routing table entry
  7. Audit log: "tenant-abc deleted at 2024-01-15 by admin on request of data subject"
```

GDPR right to erasure requires all PII to be purged. If using event sourcing, events containing PII must either be deleted (hard) or the PII field must be encrypted with a per-tenant key that is then deleted ("crypto-shredding").

---

## Control Plane vs Data Plane

SaaS systems typically have two planes:

**Control Plane** (manages tenants):
- Tenant registration and configuration
- Billing and subscription management
- Feature flag management
- Cell routing and tenant allocation
- Admin APIs

**Data Plane** (serves tenant requests):
- The actual product functionality
- Tenant-scoped data reads/writes
- Business logic
- Real-time APIs

These should be independently deployed and scaled. A control plane outage (can't create new tenants) should not affect existing tenants in the data plane.

---

## AWS SaaS Factory Patterns

AWS provides the SaaS Factory reference architecture:

| Component | AWS service |
|---|---|
| Identity and auth | Cognito user pools (per-tenant or shared + custom attributes) |
| Tenant onboarding | Lambda + DynamoDB (tenant registry) |
| Routing | API Gateway + Lambda authoriser (extracts tenant from JWT) |
| Per-tenant isolation | IAM (tenant-scoped roles), DynamoDB condition expressions |
| Observability | CloudWatch + tenant_id as dimension |
| Billing | AWS Marketplace or Stripe; usage metered via Lambda |

---

## Trade-offs Summary

| Model | Isolation | Cost | Complexity | Best for |
|---|---|---|---|---|
| **Full Silo** | Perfect | Very high | Very high | Enterprise, regulated |
| **Semi-Silo (DB per tenant)** | Strong | High | High | Professional tier |
| **Shared DB (schema per tenant)** | Medium | Medium | Medium | Growth tier |
| **Shared DB (row-level)** | Weakest | Lowest | Low (but highest risk) | Free/SMB tier |

---

## Best Practices

1. **Lead with identity** — tenant_id must be extracted from authenticated JWT, never from request body
2. **Row-Level Security as backstop** — database-enforced isolation prevents application-level isolation bugs from becoming data breaches
3. **Instrument everything with tenant_id** — metrics, logs, traces must all carry tenant context
4. **Throttle per tenant** — noisy neighbour is guaranteed at scale; build throttling infrastructure before you need it
5. **Automate onboarding entirely** — manual onboarding doesn't scale; API-driven from day one
6. **Crypto-shredding for GDPR** — encrypt PII fields with per-tenant keys; delete the key to "erase" the data
7. **Tiered isolation aligned with pricing** — free tier in pool; enterprise in silo; intermediate tiers in between
8. **Control plane and data plane independently deployable** — admin operations must not risk disrupting active tenants
9. **Test cross-tenant isolation explicitly** — unit test that tenant A cannot see tenant B's data; this test must never be skipped
10. **Measure per-tenant SLA compliance** — enterprise tier SLAs are legally binding; measure them proactively

---

## FAANG Interview Points

**"Design a multi-tenant SaaS analytics platform"**: Control plane (tenant registration, billing) separate from data plane. Free tier: shared DynamoDB tables with tenant_id partition key + RLS. Professional: dedicated DynamoDB tables per tenant. Enterprise: isolated AWS account per tenant (silo). Per-tenant throttling at API Gateway via usage plans. Tenant_id in every CloudWatch metric dimension for per-tenant alerting.

**"How do you handle GDPR deletion for an event-sourced system?"**: Crypto-shredding: encrypt PII fields in events with a per-tenant KMS data key. Store the key in Secrets Manager. On deletion request, delete the key — encrypted PII in old events becomes unrecoverable (treated as erased). Non-PII event data remains accessible for analytics.

**"Noisy neighbour — how do you detect and fix it?"**: Per-tenant P95 latency metrics with CloudWatch. Alert on >2× baseline for any tenant. Automated response: throttle the offending tenant's API rate (SQS queue depth cap). Long-term: migrate high-consumption tenants to a dedicated cell/silo before they impact others. SLA guarantee: enterprise tier tenants get resource quotas guaranteed by dedicated infrastructure.
