# Cell-Based Architecture Pattern

## Overview
Cell-based architecture partitions a system into independent, self-contained "cells" — each capable of serving a subset of customers or requests without any dependency on other cells. A failure in one cell does not propagate to others. It is the principal pattern for achieving *blast radius containment* at FAANG scale.

Originated at Amazon, Netflix, and Slack as the solution to a hard problem: at extreme scale, a single "multi-region" architecture is not enough — a bad deployment, a data corruption bug, or a cascading failure can still affect all users simultaneously. Cells prevent this.

---

## The Core Insight

**Traditional multi-region**:
```
All users → Global load balancer → Region A or Region B
A bug in the authentication service affects ALL users in both regions simultaneously.
```

**Cell-based**:
```
User A → Cell 1 (self-contained: compute + DB + cache)
User B → Cell 2 (independent: its own compute + DB + cache)
User C → Cell 3

A bug deployed to Cell 1 affects only users mapped to Cell 1.
Cell 2 and Cell 3 are unaffected. Roll back Cell 1 while 2/3 continue serving.
```

The blast radius of any failure — deploy, data corruption, configuration change, dependency outage — is bounded to a single cell and its user population.

---

## Cell Anatomy

Each cell is a fully functional, independent deployment unit:

```
Cell N
├── Compute (ECS cluster, EKS node group, Lambda functions)
├── Data store (RDS instance, DynamoDB table, ElastiCache cluster)
├── Messaging (SQS queues specific to this cell)
├── Configuration (SSM Parameter Store / Secrets Manager)
├── Observability (CloudWatch Log Group, metrics namespace scoped to cell-N)
└── Network (dedicated VPC or isolated subnets)
```

**Critical property**: a cell must be able to serve its assigned users with zero calls to any other cell. If cell 3 calls cell 1 for anything, they are not truly isolated.

---

## Cell Routing

How does a request get to the right cell?

### Static mapping (most common)
A routing tier maps user/tenant identifiers to cell IDs:

```
Request arrives with user_id = "u-12345"
  ↓
Cell Router Lambda / Service
  ↓ look up cell-id from DynamoDB routing table
  → cell_id = 3
  ↓
Route to cell-3 load balancer endpoint
```

The routing table is the most critical piece of infrastructure — it must be highly available, low-latency, and carefully managed.

### Consistent hashing
Hash the user ID to a cell ID. No routing table needed, but cell migration is harder (changing the hash ring moves users between cells).

### Geographic routing
Route by user geography: EU users → EU cells, US users → US cells. Combines cell-based blast radius with data residency compliance.

---

## Cell Sizing

| Organization scale | Cell size | Typical cell count | Strategy |
|---|---|---|---|
| Startup/growth | All users in 2-3 cells | 2–5 | Start with cells; migrate later is hard |
| Mid-size (1M users) | 100K–500K users/cell | 5–20 | Balance size vs management overhead |
| FAANG (100M+ users) | 1M–5M users/cell | 20–100 | Cells per region; regions add geo layer |

**Cell too large**: one cell's failure affects too many users — blast radius too wide
**Cell too small**: operational overhead explodes; too many deployments, too much infrastructure to manage

Rule of thumb: size cells so that a single cell failure is an acceptable incident (not a P0), not a company-wide outage.

---

## Cell-Based Deployment Strategy

The primary benefit of cells is **progressive deployment**:

```
Deploy v1.2.3 to Cell 1 (1-5% of users)
  ↓ Monitor: error rate, latency, business metrics (10-30 minutes)
  ↓ Healthy → Deploy to Cell 2 (5-10% of users)
  ↓ Monitor
  ↓ Healthy → Deploy to Cells 3-10 (50% of users)
  ↓ Monitor
  ↓ Healthy → Deploy to all remaining cells

If Cell 2 deployment triggers alerts:
  ↓ Rollback Cell 2 to v1.2.2 (seconds, only affects Cell 2's users)
  ↓ Cells 1, 3-N continue running v1.2.3 unaffected
```

This is the **canary deployment** pattern applied at the infrastructure level rather than just traffic splitting. The canary IS the cell — real production traffic on real infrastructure.

**Rollback speed**: because each cell is independent, rolling back is simply redeploying the previous version to one cell. No global coordination needed.

---

## AWS Implementation

### Option 1: One AWS Account Per Cell
Maximum isolation. Each cell is an AWS account:
```
Cell 1: AWS Account 111111111111
Cell 2: AWS Account 222222222222
...
Cell N: AWS Account NNNNNNNNNNNN

Management account: cell routing, IAM Identity Center, billing aggregation
```

**Benefits**: IAM blast radius confined to one account; accidental resource exhaustion in one cell can't affect others; separate CloudWatch quotas, Lambda concurrency limits, etc.

**Cost**: significant operational overhead; requires Account Factory + automated provisioning; hundreds of accounts need consistent infrastructure via IaC.

### Option 2: One EKS Namespace / ECS Cluster Per Cell (Same Account)
Lighter-weight isolation using Kubernetes namespaces or ECS clusters:
```
EKS Cluster (production)
├── Namespace: cell-1 (with Network Policy isolation + resource quotas)
├── Namespace: cell-2
└── Namespace: cell-N
```

Less isolated than separate accounts but much simpler operationally. Suitable when account-per-cell is too heavyweight.

### Option 3: DynamoDB Table Per Cell (Shared Compute, Isolated Data)
Shares compute cluster but isolates the most critical resource — the data store:
```
ECS Service: all cells handled by same service
  ↓ Request with tenant_id
  → Routes to DynamoDB table = "orders-cell-{cell_id}"
  or → RDS instance = "rds-orders-cell-{cell_id}"
```

Cheapest; easiest to operate. Data failures are cell-scoped; but a bad deployment affects all cells simultaneously.

---

## Cell Router: The Critical Path

The cell router is the one component that touches every request. It must be:
- **Ultra-low latency**: <1ms routing decision
- **Highly available**: if the router is down, all cells are unreachable
- **Independently deployable**: change routing logic without touching cells

```
Architecture: DNS (Route53) → CloudFront → Cell Router Lambda (provisioned concurrency)
                                                ↓ DynamoDB (routing table, DAX cached)
                                                → ALB of target cell
```

**Router DynamoDB schema**:
```
PK: user_id or tenant_id
SK: "cell"
cell_id: "cell-3"
cell_endpoint: "https://cell-3.internal.example.com"
migrating_to: null (or "cell-5" during migration)
```

**Cell migration**: moving a user from cell A to cell B requires:
1. Stop writes to cell A for that user (mark `migrating_to: cell-B`)
2. Sync data from cell A to cell B
3. Verify data consistency
4. Update routing table: `cell_id: cell-B`
5. Drain cell A

This is operationally complex — migrations should be rare events.

---

## Multi-Tenant Architecture with Cells

Cells are the standard pattern for SaaS multi-tenancy at scale:

| Tenancy model | Description | Cell usage |
|---|---|---|
| **Silo** | One cell per tenant | Maximum isolation; expensive; for premium/enterprise tiers |
| **Pool** | Many tenants per cell | Efficient; standard for free/growth tiers |
| **Bridge** | Critical tenants in silo; others in pool | Tiered offering |

**Noisy neighbour**: in pool cells, a single tenant consuming excessive resources affects others in the same cell. Solutions: per-tenant resource quotas, throttling at the routing tier, or automated cell eviction of high-consumption tenants.

---

## Trade-offs

| Dimension | Cell-Based | Traditional Multi-Region | Monolith |
|---|---|---|---|
| **Blast radius** | Single cell (e.g., 1% of users) | Entire region or global | Entire system |
| **Deployment risk** | Very low (canary per cell) | Region-at-a-time | All or nothing |
| **Operational complexity** | Very high (N× infrastructure) | High | Low |
| **Cross-cell queries** | Impossible by design | Easy | Easy |
| **Cost** | High (duplicated infra per cell) | Medium | Low |
| **Debugging** | Scoped to one cell | Cross-region correlation needed | Single system |
| **Data consistency** | No cross-cell transactions | Multi-region replication complexity | Trivial |

**When not to use cells**: small teams (<50 engineers), low user counts (<100K), early-stage product where operational complexity is not yet justified. Build the abstractions (routing tier, deployment pipeline) early, but materialise cells only when blast radius becomes a real problem.

---

## Real-World Implementations

**Amazon**: the origin. Amazon.com routes each user to a cell. Service teams own cells and can deploy independently. Internal name: "cell" (as described in the "Amazon Builder's Library").

**Netflix**: "zones" within a region. Each zone is independent. Chaos Engineering (Chaos Monkey) validates that cell failure doesn't cascade.

**Slack**: cells (called "shards") partition workspaces. A bug in the Slack deployment that affected shard-7 in 2023 affected only the workspaces in that shard — an incident, not a global outage.

**Stripe**: "stack" per region with further cell subdivision. Payment processing cells are sized to handle defined throughput thresholds; new cells added as load grows.

---

## Best Practices

1. **Design for cells from the beginning** — retrofitting cells onto a monolith is extremely hard
2. **Keep the cell router simple and stateless** — it's the critical path; complexity = fragility
3. **Cache the routing table aggressively** (DAX, ElastiCache) — the routing lookup must be <1ms
4. **Automate cell provisioning entirely** (Terraform modules, CDK constructs) — no cell should require manual setup
5. **Deploy progressively** — always start with 1-2 cells; monitor for 15+ minutes; then expand
6. **Define cell health metrics** that are business-meaningful (not just CPU) — error rate, conversion rate, p99 latency
7. **Cell migration tooling** must be tested and practiced — you will need it during incidents
8. **Define "cell failure" threshold** — what % of cell error rate triggers a rollback
9. **Never allow cross-cell calls** in the hot path — synchronous cross-cell coupling defeats the isolation purpose
10. **Regular game days** — simulate cell failures to validate isolation and test runbooks

---

## FAANG Interview Points

**"How would you design a system to serve 100M users with <0.1% blast radius per deployment?"**: Cell-based architecture. 20 cells × 5M users. Routing tier (DynamoDB + DAX, <1ms). Progressive deployments: 1 cell → monitor → expand. Cell failure = 5% of users. Automated cell provisioning via CDK. Cell health dashboards with business metrics.

**"How do you do zero-risk deployments at scale?"**: No such thing as zero risk, but cell-based deployments with progressive rollout get as close as possible. Deploy to 1 cell (5% users), monitor for 20 minutes, expand in stages. Automated rollback trigger: if error rate on new cells > 3× baseline, roll back that cell automatically. Remaining cells unaffected.

**"What's the hardest operational challenge with cells?"**: Cross-cell queries and global aggregations. "How many total active users right now?" requires querying all N cells and aggregating. Solutions: async aggregation into a global counter (approximate), event stream aggregation (each cell emits to global Kinesis stream), or accept that some metrics are eventually consistent.
