# Cell-Based Architecture

## TL;DR

Cell-based architecture partitions your infrastructure into independent, self-contained "cells" — each serving a subset of users. A failure in one cell is **contained** and cannot cascade to others. Amazon uses this pattern at massive scale (each AWS Availability Zone is partly a cell). It is the answer to "how do you achieve 99.99% availability without global blast radius."

---

## 1. The Core Problem It Solves

In a traditional horizontally-scaled system, all users share the same infrastructure. A bug in the payment service, a bad deployment, or a noisy-neighbor customer can degrade the experience for **all** users simultaneously.

**Cell-based architecture** limits the blast radius: a failure in Cell 3 affects only the users assigned to Cell 3 (e.g., 1/N of all users), not the entire user base.

```
Without cells:
  Bug in payment service → ALL users see failures

With cells:
  Bug in Cell 3's payment service → Only Cell 3 users affected (1/N impact)
```

---

## 2. Anatomy of a Cell

Each cell is a complete, independent stack:
- Load balancer
- API servers
- Database (primary + replicas)
- Cache
- Message queue
- All supporting services

No shared mutable state between cells. Cells share only:
- Read-only configuration (feature flags, rate limits)
- The global routing layer (which maps a user to a cell)

```mermaid
graph TB
    Router[Global Router / Cell Mapping Service]

    Router -->|user_id in [0, 25M)| Cell1
    Router -->|user_id in [25M, 50M)| Cell2
    Router -->|user_id in [50M, 75M)| Cell3
    Router -->|user_id in [75M, 100M)| Cell4

    subgraph Cell1 [Cell 1]
        LB1[LB] --> API1[API Servers]
        API1 --> DB1[(DB)]
        API1 --> Cache1[Cache]
        API1 --> Queue1[Queue]
    end

    subgraph Cell2 [Cell 2]
        LB2[LB] --> API2[API Servers]
        API2 --> DB2[(DB)]
        API2 --> Cache2[Cache]
        API2 --> Queue2[Queue]
    end
```

---

## 3. Cell Assignment Strategies

### Static hash-based assignment
```
cell_id = hash(user_id) % num_cells
```
- Simple, deterministic, no lookup required
- Problem: redistributing users when you add a cell requires rehashing

### Range-based assignment
```
user_id [0, 25M) → Cell 1
user_id [25M, 50M) → Cell 2
```
- Easy to add a new cell (add a new range)
- Problem: uneven user activity by range (older users more active)

### Lookup table
```
Global routing service maintains: user_id → cell_id mapping
```
- Full flexibility: move any user to any cell
- Cost: adds a lookup hop on every request (mitigated by caching)
- Enables: graceful cell draining, blue/green cell upgrades, cell rebalancing
- Used by: Stripe (shards users across cells), Salesforce (multi-tenant isolation)

---

## 4. Cell Sizing

The right cell size is determined by blast radius tolerance:

| Cell Count | Users per Cell | Blast Radius if 1 Cell Fails | Infra Overhead |
|-----------|---------------|------------------------------|----------------|
| 1 | 100% | 100% | None |
| 4 | 25% | 25% | Low |
| 10 | 10% | 10% | Medium |
| 100 | 1% | 1% | High |

**Amazon's rule of thumb**: each cell should serve a blast radius that is acceptable as a business outcome. For a consumer product, < 5% impact per cell is reasonable. For enterprise SaaS with large customers, consider one cell per tier (gold/silver/bronze) or one cell per large customer.

A single cell must be large enough to be **operationally efficient** — not so small that you have 1,000 cells and managing them becomes the problem.

---

## 5. Deployment Strategy with Cells

Cells enable **staged rollouts** without feature flags:

```
Day 1: Deploy new version to Cell 1 (1% of users)
       → Monitor error rate, latency, business metrics for 1 hour
Day 2: Expand to Cells 1-4 (4%)
       → Monitor for 24 hours
Day 3: Full rollout to all cells
```

If Cell 1 shows regressions, you rollback only Cell 1. Other cells are unaffected and continue running the stable version.

**This is how Amazon deploys AWS services**: a new version of S3's PUT handler is deployed to one cell (region + shard combination), validated, then expanded.

---

## 6. Inter-Cell Communication

The rule is: cells do not call each other for user data. Cross-cell calls reintroduce blast radius coupling.

**Exceptions**:
- **Cross-cell reads for global data** (product catalog, pricing): replicated to all cells from a global source; cells read locally
- **Cross-cell analytics**: async export to a separate analytics pipeline — not in the request path
- **Global aggregations** (trending content, leaderboards): computed by a separate global service that reads from all cells asynchronously

---

## 7. Cell-Based vs Availability Zone

These are related but different:

| | AZ | Cell |
|-|----|------|
| Defined by | Cloud provider (physical data center) | You (logical partition of users) |
| Granularity | 3–4 per region typically | Dozens to hundreds per region |
| Failure independence | Physical power/network independence | Logical blast radius isolation |
| Shared infrastructure | VPC, subnets, AMIs | Nothing shared except routing |
| Deployment unit | All AZs together | Each cell independently |

A cell can span multiple AZs (for HA within a cell). A mature architecture has both: cells for blast radius + multi-AZ within each cell for availability.

---

## 8. Noisy Neighbor Problem

In a multi-tenant SaaS without cell isolation:
- Enterprise customer with 10M API calls/day exhausts shared rate limits
- Their heavy writes cause replication lag for other tenants
- Their slow queries block other tenants' connection pool

Cell-based fix: assign large customers to dedicated cells (or even single-tenant cells). This is what Salesforce's "Performance Instances" and Stripe's tier-based sharding do.

---

## 9. Failure Modes

| Failure | Impact | Mitigation |
|---------|--------|------------|
| Cell router failure | All traffic fails | Multi-region router; heavy caching of cell mappings at API layer |
| One cell's DB fails | ~(1/N) users affected | Standard HA within the cell (multi-AZ RDS, replica promotion) |
| Code bug in new deployment | At most 1 cell's users affected if staged | Staged rollout; automated rollback on error rate spike |
| Cell assignment hotspot | One cell overloaded | Rebalance users; detect via per-cell load metrics |
| Cross-cell data dependency | Cascading failure | Prohibit cross-cell user-data reads in the request path |

---

## 10. Real-World Adoption

**Amazon AWS**: S3, DynamoDB, and most AWS services use cell-based design. Each "storage node group" is a cell. The Shuffle Sharding technique further isolates customers within shared infrastructure.

**Stripe**: Radar (fraud detection) is cell-based. Large merchants are assigned to dedicated cells to prevent a complex fraud decision for one merchant from starving others. Stripe engineering blog has detailed coverage.

**Salesforce**: Multi-tenant architecture uses "instances" (cells) to isolate customers. You can see which instance you're on (NA1, EU3, etc.).

**AWS Shuffle Sharding**: Assigns each customer a random subset of cells rather than one. If one cell is impacted, the customer has N-1 fallback cells. The blast radius for a single customer is dramatically reduced.

---

## 11. Capacity Estimation Example

**System**: 100M users, 4 cells

Per cell:
- Users: 25M
- Assume 10% DAU = 2.5M active/day
- Peak RPS: 2.5M × 10 requests/user / 86400s × 10 (peak factor) ≈ 2,900 RPS per cell

Each cell needs to be sized for ~3,000 RPS at peak. With a 2× headroom target, provision for 6,000 RPS per cell.

Each cell = ~20 API servers (at 300 RPS/server) + appropriate DB tier.

---

## 12. FAANG Interview Callout

**When does this topic come up**:
- "How do you achieve 99.99% availability?" → Cell-based + multi-region active-active
- "How do you limit the blast radius of a bad deployment?" → Staged rollout using cells
- "How do you handle noisy neighbors in a multi-tenant SaaS?" → Cell-based isolation with tenant assignment

**Common follow-ups**:
1. "How do you assign users to cells?" → Hash-based (simple), range-based (flexible), lookup table (full flexibility with routing service)
2. "What if two users in different cells need to interact?" → They don't for their own data; cross-cell interactions are handled by global services that operate asynchronously
3. "How do you add a new cell?" → Provision new cell; update routing service; migrate a range of users (lookup table makes this smooth)
4. "How do you handle a hotspot cell?" → Detect via per-cell metrics; rebalance users via the routing table; emergency: temporarily redirect users from the hot cell

**Distinguishing answer**: Most candidates answer availability questions with "add more replicas" or "multi-region." Bringing up cell-based architecture with its blast radius framing — and connecting it to Amazon's real deployment strategy — signals a principal engineer's systems thinking.
