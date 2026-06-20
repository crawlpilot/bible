# Strangler Fig Pattern (Migration Strategy)

## Overview
The Strangler Fig pattern is the standard technique for replacing a legacy system incrementally — without a big-bang rewrite. The new system grows around the old one, gradually handling more traffic, until the legacy system can be safely decommissioned. The name comes from the strangler fig plant, which grows around a host tree and eventually replaces it.

Coined by Martin Fowler, it is the most widely used architectural migration pattern at FAANG.

---

## The Core Approach

```
Phase 0: Monolith serves all traffic
Client → Monolith

Phase 1: Introduce a facade (proxy) in front
Client → Facade → Monolith (facade passes everything through)

Phase 2: Extract first capability to new service
Client → Facade → [if /orders]: Order Microservice (new)
              → [everything else]: Monolith

Phase 3: Extract more capabilities over time
Client → Facade → [/orders]: Order Service
              → [/payments]: Payment Service
              → [/search]: Search Service
              → [remaining]: Monolith (getting smaller)

Phase N: Monolith is empty, decommissioned
Client → Facade → New Services (complete)
```

The facade (often an API Gateway, ALB, or Nginx reverse proxy) is the routing control plane — it lets you shift traffic percentage-by-percentage without client changes.

---

## Why Not a Big-Bang Rewrite?

The classic failure mode of "let's rewrite the whole thing in 18 months":

| Risk | Consequence |
|---|---|
| Business requirements change during rewrite | New system already out of date at launch |
| Hidden complexity discovered too late | Delivery date slips; team burns out |
| No intermediate value delivered | 18 months of opportunity cost |
| Big-bang cutover has high failure risk | No rollback path if new system fails at launch |
| Knowledge loss | Tacit knowledge in legacy system not discovered until missed |

**Strangler Fig mitigates all of these**: you ship value continuously; you discover hidden complexity one module at a time; rollback is trivial (re-route through facade); the legacy system runs in parallel until the new service is proven.

---

## AWS Implementation

### Facade Options

| Facade | Best for | Trade-offs |
|---|---|---|
| **API Gateway** | REST APIs; auth + throttling at gateway | 29s timeout limit; cost at very high throughput |
| **ALB (path routing)** | Container/EC2 backends; L7 routing | No auth at gateway; higher throughput limit |
| **CloudFront (origin routing)** | CDN + migration; global edge routing | Cache complicates stateful APIs |
| **Nginx / Envoy (EC2)** | Maximum control; complex routing logic | Operational overhead; not managed |

### Routing Configuration Evolution (ALB example)
```
Phase 1: All traffic to monolith target group (weight 100)

Phase 2: /api/v1/orders* → orders-service target group (new)
         /* → monolith target group (everything else)

Phase 3: /api/v1/orders*, /api/v1/payments* → new services
         /* → monolith

Phase N: All rules → new services; monolith target group removed
```

### Database Migration (the hard part)

The hardest part of strangling a monolith is the database — typically everything shares one large relational database.

**Approach 1: Shared database (short-term)**
New service reads and writes the monolith's database during transition. Acceptable for Phase 1-2; not long-term (creates coupling between new service and legacy schema).

**Approach 2: Database-per-service with sync**
New service gets its own database. A sync mechanism keeps it in sync with the monolith DB:
```
Monolith writes → CDC (Debezium) → Kafka topic → New service's DB
                                                   (eventually consistent)
```
New service reads from its own DB; writes go to its own DB and (via dual-write or CDC) to the monolith.

**Approach 3: Expand-contract (preferred for SQL)**
1. **Expand**: add new column/table to the shared DB (backward compatible)
2. **Migrate**: backfill data to new schema; run both old and new in parallel
3. **Contract**: remove old schema after all services use the new one

---

## The Anti-Corruption Layer (ACL)

When new services interface with the legacy system, they must not be contaminated by the legacy data model. The ACL is a translation layer:

```
New Order Service ←→ ACL ←→ Legacy Monolith
   (clean DDD model)    (translates)  (legacy schema/model)
```

The ACL prevents the legacy system's design decisions (bad naming, denormalised data, implicit state machines) from leaking into the new system. The new system speaks its own domain language; the ACL translates to/from the legacy model.

```python
# ACL example: translate legacy order format to new domain model
class LegacyOrderAdapter:
    def to_domain(self, legacy_order: dict) -> Order:
        return Order(
            id=OrderId(legacy_order['ORDER_NUM']),      # legacy uses numeric string
            status=self._map_status(legacy_order['STAT_CD']),  # legacy uses cryptic codes
            total=Money(legacy_order['TOT_AMT'], legacy_order['CURR_CD'])
        )
    
    def _map_status(self, code: str) -> OrderStatus:
        mapping = {'P': OrderStatus.PENDING, 'A': OrderStatus.ACTIVE, 'X': OrderStatus.CANCELLED}
        return mapping.get(code, OrderStatus.UNKNOWN)
```

---

## Migration Patterns by Component Type

### API Endpoints
1. Route new endpoint version (`/v2/orders`) to new service
2. Keep `/v1/orders` on monolith until clients migrate
3. Sunset `/v1/orders` after migration window (6–12 months)

### Background Jobs / Batch Processes
1. Create new job in new service
2. Disable old job in monolith
3. Run both in parallel briefly (with deduplication) to verify
4. Delete old job

### Event/Message Consumers
1. New service subscribes to the same topic/queue as monolith consumer
2. Set monolith consumer to "dry run" mode (consumes but doesn't write)
3. Monitor new service for correctness
4. Delete monolith consumer

### Scheduled Cron Jobs
1. Deploy new Lambda/ECS-based scheduler with identical schedule
2. Add a feature flag: run new or old implementation
3. Enable new implementation with flag; monitor
4. Remove old implementation

---

## Traffic Shifting Strategies

### Shadow Mode (Safest)
Route all production traffic to the monolith. Mirror a copy to the new service. New service processes but discards its responses (used only for comparison).

```
Client → Monolith → returns response to client
              ↓ async copy
         New Service → processes, logs differences vs monolith, discards response
```

Use for: validating that new service produces correct results before it serves real traffic. Detect data divergence with no user impact.

### Canary Release (Recommended Path)
Route a small percentage to the new service; observe; increase progressively:

```
Day 1: 1% of traffic → new service
Day 2 (if healthy): 10%
Day 5: 25%
Day 7: 50%
Day 10: 100%
(monolith on standby for 2 weeks)
```

Weighted ALB target groups or feature flags at the facade control the percentages.

### Feature Flag Release
Gate the new code path behind a feature flag:
```python
if feature_flags.enabled("new-orders-service", tenant_id=ctx.tenant_id):
    return new_orders_service.get_orders(ctx)
else:
    return legacy_monolith.get_orders(ctx)
```
Allows rollout by tenant, by user segment, by geography. Instant rollback: flip the flag.

---

## Metrics for Migration Progress

Track these to know if the migration is succeeding:

| Metric | Target |
|---|---|
| % of API traffic handled by new services | Increasing toward 100% |
| Error rate on new service vs monolith | New ≤ monolith; alert if new > 1.5× monolith |
| P99 latency on new service | ≤ monolith or better |
| Database writes via monolith only | Decreasing toward 0 |
| Number of ACL calls | Decreasing (fewer legacy dependencies) |
| Test coverage of new service | > 80% for extracted domains |

---

## Trade-offs

| Dimension | Strangler Fig | Big-Bang Rewrite |
|---|---|---|
| Risk | Low — rollback at any step | Very high — full replacement in one cutover |
| Time to value | Continuous — each extracted service ships value | All-or-nothing at end of rewrite |
| Team disruption | Moderate — run two systems in parallel | Very high — large team for extended period |
| Legacy system cost | Pays for both systems during transition | Still pays during rewrite period |
| Hidden complexity discovery | Gradual — discovered domain by domain | Catastrophic — discovered at end |
| Knowledge transfer | Natural — code alongside legacy | Lost — "legacy" team and "rewrite" team diverge |

---

## Best Practices

1. **Start with the facade** — even before extracting anything, introduce the routing layer. This is the control surface for all future work.
2. **Extract leaves first** — start with capabilities that have the fewest dependencies on the monolith (reporting, search, notifications). Leave the core domain for last.
3. **Establish the ACL early** — contamination by the legacy model is irreversible if not prevented from the start.
4. **Run shadow mode before canary** — catch data divergence before users see it.
5. **Keep the rollback path clear at every step** — you must be able to revert any step within 5 minutes.
6. **Define "done" for each service** — what does 100% migration mean? When is the monolith code for that domain deleted?
7. **Delete the monolith code** once migrated — leaving dead code creates confusion and maintenance burden.
8. **Don't try to improve design during migration** — the goal of strangling is functional equivalence, not refactoring. Refactor after migration.
9. **Set a migration timeline with milestones** — open-ended migrations lose momentum after 12 months.
10. **Measure the monolith's share of traffic** as the primary KPI — it should trend to zero.

---

## FAANG Interview Points

**"How would you migrate a legacy monolith to microservices?"**: Strangler Fig pattern. Introduce API Gateway/ALB facade in front of the monolith. Extract services one domain at a time, starting with the leaves (fewest dependencies). Use shadow mode first, then canary traffic shifting. Database-per-service with CDC sync during transition. Anti-Corruption Layer to prevent legacy model pollution.

**"What's the hardest part of the strangler fig migration?"**: The database. Monolithic systems typically have a single shared relational database with implicit coupling through foreign keys and shared tables. Decomposing it requires: choosing the right extraction order, handling dual-writes during transition, and eventually accepting eventual consistency between what used to be a single transaction.

**"How do you know when to stop the migration?"**: 100% of traffic routes through new services, zero writes through the monolith, all tests pass, the monolith codebase for migrated domains is deleted, and the monolith runs only residual functionality. Set a target date — "monolith is 0% of traffic by Q4" — and measure against it weekly.
