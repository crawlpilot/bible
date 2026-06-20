# 36. Strangler Fig
**Category**: Modern / Enterprise  
**GoF**: No (Fowler 2004, "Strangler Fig Application")  
**Complexity**: High  
**Frequency in FAANG interviews**: Common

> Incrementally replace a legacy monolith by routing new functionality to new services while the monolith handles remaining traffic — until it can be safely retired — mirroring the way a strangler fig tree grows around an existing tree until the original tree is gone.

---

## Problem It Solves

A 10-year-old e-commerce monolith handles all operations: catalog, search, checkout, order management, payments, and notifications. It's written in PHP, deployed on bare metal, and takes 45 minutes to deploy. The team wants to migrate to microservices. A "big bang" rewrite is catastrophic — years of development, high risk, and the monolith serves 50M users today.

Strangler Fig lets you carve out one capability at a time. A proxy/façade sits in front of both systems. Traffic for `/api/catalog` goes to the new Catalog Service; everything else still goes to the monolith. Once each capability is migrated and proven, its traffic is cut over. Eventually the monolith handles nothing and can be decommissioned.

## Structure (Participants)

```
                       Users
                         │
                         ▼
              ┌───────────────────────┐
              │      API Façade       │  ← routing proxy (Nginx / API Gateway / Envoy)
              │  (Strangler Proxy)    │
              └───────────────────────┘
                  │              │
        new routes│              │legacy routes
                  ▼              ▼
          ┌─────────────┐  ┌────────────────────────────────┐
          │  Catalog     │  │        Legacy Monolith          │
          │  Service     │  │  [checkout, payments, orders,  │
          │  (new)       │  │   notifications, catalog OLD]  │
          └─────────────┘  └────────────────────────────────┘
          ┌─────────────┐
          │  Checkout    │  ← carved out next
          │  Service     │
          │  (new)       │
          └─────────────┘
```

**Migration phases**:
```
Phase 0:   [Monolith] handles 100% of traffic
Phase 1:   [Façade] added, routes 100% to monolith — zero change in behavior
Phase 2:   Catalog Service built; /api/catalog → new; rest → monolith
Phase 3:   Checkout Service built; /api/checkout → new; rest → monolith
Phase N:   Monolith handles 0% → decommission
```

Key participants:
- **Façade / Proxy**: the routing layer — the single entry point that knows which service handles which path
- **New Services**: microservices carved out of the monolith, one capability at a time
- **Legacy Monolith**: continues running and handling traffic for un-migrated capabilities
- **ACL (Anti-Corruption Layer)**: translates between the monolith's data model and new services' domain models
- **Data Sync**: mechanism to keep data consistent during the transition (dual-write, event sync, or DB read replica)

---

## Real-World Use Case: E-Commerce Monolith Migration

### Implementation

```java
// --- PHASE 1: Façade (API Gateway routing rules) ---

// Nginx routing config (simplified)
/*
server {
    listen 443;

    # Phase 2: Catalog migrated
    location /api/catalog {
        proxy_pass http://catalog-service;
    }

    # Phase 3: Checkout migrated
    location /api/checkout {
        proxy_pass http://checkout-service;
    }

    # Everything else still goes to the monolith
    location / {
        proxy_pass http://legacy-monolith;
    }
}
*/

// Programmatic façade for feature-flag-driven traffic splitting
@RestController
@RequestMapping("/api")
public class StranglerFacade {
    private final CatalogServiceClient catalogService;
    private final LegacyMonolithClient legacyMonolith;
    private final FeatureFlags featureFlags;
    private final MeterRegistry metrics;

    @GetMapping("/catalog/items/{itemId}")
    public ResponseEntity<ItemResponse> getItem(@PathVariable String itemId, HttpServletRequest req) {
        String backend = featureFlags.isEnabled("catalog-microservice", itemId) ? "new" : "legacy";
        metrics.counter("strangler.request", "path", "catalog.getItem", "backend", backend).increment();

        return switch (backend) {
            case "new" -> catalogService.getItem(itemId);
            case "legacy" -> legacyMonolith.forward(req);
            default -> throw new IllegalStateException();
        };
    }
}

// --- PHASE 2: New Catalog Service (clean domain model) ---

@Entity
public class CatalogItem {
    @Id private String id;                    // clean UUID
    private String title;
    private Money price;
    private String description;
    private InventoryStatus availability;
    private List<String> imageUrls;
    private Category category;
    // ... no PHP-era legacy fields
}

@Service
public class CatalogService {
    private final CatalogRepository catalog;
    private final SearchIndex searchIndex;  // Elasticsearch

    public CatalogItem getItem(String itemId) {
        return catalog.findById(itemId)
            .orElseThrow(() -> new ItemNotFoundException(itemId));
    }

    public SearchResult search(SearchQuery query) {
        return searchIndex.search(query);
    }
}

// --- DATA MIGRATION: dual-write during transition ---

// Strategy: write to both monolith DB and new service DB; read from new service
// (prevents data divergence during cutover)
@Service
public class CatalogDualWriteService {
    private final CatalogService newCatalog;
    private final LegacyCatalogClient legacyCatalog;

    // Called when a product is updated — writes to both systems
    public void updateItem(UpdateItemRequest request) {
        // Write to new service first (source of truth going forward)
        newCatalog.update(toDomainRequest(request));

        // Write to legacy (maintains consistency until monolith fully decommissioned)
        try {
            legacyCatalog.updateItem(toLegacyRequest(request));
        } catch (LegacyWriteException e) {
            // Log discrepancy — reconciliation job will catch it
            log.error("Dual-write divergence for item {}: {}", request.itemId(), e.getMessage());
            discrepancyQueue.publish(new DualWriteDiscrepancy(request.itemId(), "UPDATE"));
        }
    }
}

// --- PHASE 3: Strangling checkout ---

// Checkout migration is more complex — it writes to the order DB
// Strategy: sync the orders DB via CDC (Change Data Capture) until old orders fully migrated

@Service
public class OrderMigrationService {
    private final LegacyOrderRepository legacyOrders;
    private final OrderRepository newOrders;

    // Scheduled job: pull legacy orders not yet in new DB
    @Scheduled(fixedDelay = 60_000)
    public void reconcileLegacyOrders() {
        List<LegacyOrder> unmigrated = legacyOrders.findNotMigratedAfter(lastMigrationMark);
        for (LegacyOrder legacyOrder : unmigrated) {
            Order domainOrder = orderTranslator.toDomainOrder(legacyOrder);
            newOrders.save(domainOrder);
            lastMigrationMark = legacyOrder.createdAt();
        }
    }
}

// --- TRAFFIC MIGRATION: gradual canary rollout ---

// Feature flag controls percentage of traffic routed to new service
// LaunchDarkly / custom flag:
//   Day 1: 1% of users → catalog-microservice
//   Day 3: 10% of users
//   Day 7: 50% of users
//   Day 14: 100% — monolith catalog code still running but receives 0%
//   Day 21: Remove catalog routes from monolith; delete dead code

@Component
public class CatalogFeatureFlag {
    private final LaunchDarkly ld;

    public boolean isEnabled(String userId) {
        // Consistent assignment per user — same user always goes to same backend
        return ld.variation("catalog-microservice-rollout", userId, false);
    }
}
```

### Migration Sequence (walkthrough)

1. **Install façade** (Day 0): Nginx/API Gateway added in front of monolith. Behavior unchanged, 100% to monolith. Validate with load test.
2. **Build Catalog Service** (Weeks 1–4): New service built, tested. New DB seeded from monolith DB snapshot. Dual-write enabled.
3. **Canary** (Day 1): 1% of catalog traffic to new service. Monitor error rates, latency, data correctness. Compare responses to monolith responses (shadow mode first).
4. **Ramp** (Days 2–14): 1% → 10% → 50% → 100% over two weeks. Feature flag controls rollout.
5. **Decommission monolith's catalog** (Week 6): Remove catalog routes from monolith. Delete dead PHP code. Turn off dual-write.
6. **Repeat for checkout, payments, etc.**

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | Façade routes; new services own their capability; ACL translates |
| Open/Closed | ✅ | Adding a new carved-out service adds a routing rule — no changes to existing services |
| Liskov Substitution | ✅ | New service must return the same API contract as the monolith endpoint it replaces |
| Interface Segregation | ✅ | Each new service exposes only the API it owns |
| Dependency Inversion | ✅ | Façade depends on service abstractions, not implementations |

---

## When to Use

- Migrating a legacy monolith to microservices or a modern architecture
- The monolith cannot be taken offline for a big-bang rewrite
- Team wants incremental, reversible migration with the ability to roll back any step
- Different parts of the system have different urgency or complexity for migration

## When NOT to Use

- The monolith is small and can be fully rewritten in a few sprints
- The legacy system's data model is deeply entangled across all capabilities (shared tables, no clear seams)
- Cross-capability transactions are everywhere — microservices will require Saga, adding complexity
- You don't have a façade/proxy available (e.g., gRPC streaming, bidirectional WebSocket without routing support)

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Incremental and reversible — each phase can be rolled back by flipping a feature flag | Long transition period — running two systems simultaneously doubles operational cost and complexity |
| Zero downtime migration — users never experience a cutover event | Data consistency during dual-write phase — divergence requires reconciliation jobs |
| Each carved-out service can use modern tech stack, CI/CD, independent deploys | The façade becomes a new critical path — it must be highly available and low-latency |

---

**FAANG interview application**: "Strangler Fig is the industry-standard answer to 'how do you migrate a monolith without a big-bang rewrite?' The critical enabler is the façade — which at FAANG scale is typically an API Gateway (Kong, AWS API GW, Envoy) that does path-based routing. The two hardest problems in practice: (1) data ownership — when you carve out a service, which DB does it own? dual-write or CDC? (2) cross-cutting concerns — auth, rate limiting, tracing must work across both the monolith and new services from day one. Amazon migrated from their original monolith to microservices using exactly this pattern — the teams called it 'extracting seams.'"

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Anti-Corruption Layer](35-anti-corruption-layer.md) | ACL handles translation between the monolith's data model and new services during migration |
| [Proxy](../structural/12-proxy.md) | The Strangler Façade is implemented as a reverse Proxy |
| [Saga](26-saga.md) | After carving out transactional capabilities, Saga manages cross-service transactions that the monolith handled locally |
| [CQRS](25-cqrs.md) | Often adopted alongside Strangler Fig — reads go to new read-optimized services while writes still flow through the monolith |
