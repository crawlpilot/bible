# 35. Anti-Corruption Layer (ACL)
**Category**: Modern / Enterprise (Domain-Driven Design)  
**GoF**: No (Evans 2003, "Domain-Driven Design")  
**Complexity**: Medium  
**Frequency in FAANG interviews**: Common

> Insert a translation layer between two bounded contexts (or a legacy system) to prevent alien domain concepts from bleeding into your domain model — preserving model integrity at the boundary.

---

## Problem It Solves

The new `OrderService` needs inventory data from a legacy `WarehouseSystem` built in 2005. The legacy system represents availability as `item_status_cd = 1` (in stock), `2` (low stock), `3` (out of stock), `4` (discontinued) using raw integer codes, with a SOAP API returning XML with 47 fields. If `OrderService` calls the legacy API directly, legacy concepts — `item_status_cd`, legacy item IDs, XML response parsing — leak throughout the ordering domain model. Engineers writing order logic must understand legacy terminology. Refactoring the legacy system later becomes impossible.

The Anti-Corruption Layer translates the legacy model into the ordering domain's clean model at the boundary — `OrderService` works with `InventoryStatus.AVAILABLE`, `ItemId`, and clean interfaces. The legacy complexity is contained entirely within the ACL.

## Structure (Participants)

```
  OrderService (new bounded context)
        │
        │  inventoryPort.checkAvailability(itemId, qty)
        ▼
  ┌─────────────────────────────────────────────────────────┐
  │             Anti-Corruption Layer (ACL)                  │
  │                                                         │
  │  InventoryAdapter                                       │
  │    ├── translates domain ItemId → legacy item_no        │
  │    ├── calls legacy SOAP endpoint                       │
  │    ├── parses XML response                              │
  │    └── maps item_status_cd → InventoryStatus (enum)    │
  └─────────────────────────────────────────────────────────┘
        │
        │  legacyClient.getItemAvailability(item_no)
        ▼
  WarehouseSystem (legacy bounded context)
  [item_status_cd, item_no, warehouse_loc_id, XML/SOAP]
```

Key participants:
- **Domain Port** (`InventoryPort`): interface defined in the ordering domain using ordering domain types
- **Adapter / ACL** (`InventoryAdapter`): implements the port; all translation logic lives here
- **Legacy Client** (`WarehouseClient`): thin wrapper for the legacy SOAP/REST/DB call
- **Translator** (`InventoryTranslator`): maps legacy model ↔ domain model (can be a separate class)
- **Domain Model** (`InventoryStatus`, `ItemId`): clean ordering domain types — no legacy concepts

---

## Real-World Use Case: Order Service ↔ Legacy Warehouse System

### Implementation

```java
// --- DOMAIN LAYER (ordering bounded context) ---

// Clean domain value objects — no legacy concepts
public record ItemId(String value) {
    public ItemId { Objects.requireNonNull(value, "ItemId cannot be null"); }
}

public enum InventoryStatus {
    AVAILABLE, LOW_STOCK, OUT_OF_STOCK, DISCONTINUED
}

public record InventoryCheck(ItemId itemId, int requestedQty, InventoryStatus status, int availableQty) {
    public boolean canFulfill() {
        return (status == InventoryStatus.AVAILABLE || status == InventoryStatus.LOW_STOCK)
            && availableQty >= requestedQty;
    }
}

// Port: defined in the domain, no knowledge of legacy
public interface InventoryPort {
    InventoryCheck checkAvailability(ItemId itemId, int quantity);
    Map<ItemId, InventoryStatus> bulkCheckAvailability(Set<ItemId> itemIds);
}

// Domain service uses only domain types
@Service
public class OrderFulfillmentService {
    private final InventoryPort inventoryPort;

    public OrderFulfillmentService(InventoryPort inventoryPort) {
        this.inventoryPort = inventoryPort;
    }

    public FulfillmentDecision canFulfill(Order order) {
        List<FulfillmentIssue> issues = new ArrayList<>();
        for (OrderLine line : order.lines()) {
            InventoryCheck check = inventoryPort.checkAvailability(line.itemId(), line.quantity());
            if (!check.canFulfill()) {
                issues.add(new FulfillmentIssue(line.itemId(), check.status(), check.availableQty()));
            }
        }
        return issues.isEmpty() ? FulfillmentDecision.approved() : FulfillmentDecision.rejected(issues);
    }
}

// --- ANTI-CORRUPTION LAYER (infrastructure layer) ---

// Legacy data model (mirrors the SOAP response XML)
@XmlRootElement(name = "ItemAvailabilityResponse")
public class LegacyItemAvailabilityResponse {
    @XmlElement public String item_no;
    @XmlElement public int item_status_cd;      // 1=in-stock, 2=low, 3=oos, 4=disc
    @XmlElement public int available_qty;
    @XmlElement public String warehouse_loc_id;
    @XmlElement public String last_updated_ts;
    // ... 42 more legacy fields we don't care about
}

// Translator: the heart of the ACL — pure translation logic, no business logic
public class InventoryTranslator {

    // Legacy item numbers use a different format than domain ItemIds
    public String tolegacyItemNo(ItemId itemId) {
        // Legacy uses format: "WH-" + zero-padded 8-digit number
        return "WH-" + String.format("%08d", Long.parseLong(itemId.value()));
    }

    public ItemId toDomainItemId(String legacyItemNo) {
        // Strip "WH-" prefix and leading zeros
        return new ItemId(String.valueOf(Long.parseLong(legacyItemNo.replace("WH-", ""))));
    }

    public InventoryStatus toDomainStatus(int itemStatusCd) {
        return switch (itemStatusCd) {
            case 1 -> InventoryStatus.AVAILABLE;
            case 2 -> InventoryStatus.LOW_STOCK;
            case 3 -> InventoryStatus.OUT_OF_STOCK;
            case 4 -> InventoryStatus.DISCONTINUED;
            default -> throw new UnknownLegacyStatusException("Unknown item_status_cd: " + itemStatusCd);
        };
    }

    public InventoryCheck toInventoryCheck(ItemId itemId, int requestedQty, LegacyItemAvailabilityResponse response) {
        return new InventoryCheck(
            itemId,
            requestedQty,
            toDomainStatus(response.item_status_cd),
            response.available_qty
        );
    }
}

// Adapter: implements the domain port, delegates to legacy client + translator
@Component
public class LegacyWarehouseInventoryAdapter implements InventoryPort {
    private final WarehouseSystemClient legacyClient;
    private final InventoryTranslator translator;
    private final MeterRegistry metrics;

    public LegacyWarehouseInventoryAdapter(WarehouseSystemClient legacyClient,
                                            InventoryTranslator translator,
                                            MeterRegistry metrics) {
        this.legacyClient = legacyClient;
        this.translator = translator;
        this.metrics = metrics;
    }

    @Override
    public InventoryCheck checkAvailability(ItemId itemId, int quantity) {
        String legacyItemNo = translator.tolegacyItemNo(itemId);
        try {
            LegacyItemAvailabilityResponse response = legacyClient.getItemAvailability(legacyItemNo);
            return translator.toInventoryCheck(itemId, quantity, response);
        } catch (LegacySoapFaultException e) {
            // Translate legacy SOAP faults to domain exceptions
            if (e.getFaultCode().equals("ITEM_NOT_FOUND")) {
                throw new ItemNotFoundException(itemId);
            }
            throw new InventoryServiceException("Legacy warehouse unavailable", e);
        }
    }

    @Override
    public Map<ItemId, InventoryStatus> bulkCheckAvailability(Set<ItemId> itemIds) {
        // Legacy system doesn't support bulk — N individual calls with retry
        return itemIds.parallelStream()
            .collect(Collectors.toMap(
                id -> id,
                id -> checkAvailability(id, 1).status()
            ));
    }
}

// Legacy client — only used inside the ACL
@Component
public class WarehouseSystemClient {
    private final WebServiceTemplate soapTemplate;

    public LegacyItemAvailabilityResponse getItemAvailability(String legacyItemNo) {
        GetItemAvailabilityRequest request = new GetItemAvailabilityRequest();
        request.setItemNo(legacyItemNo);
        return (LegacyItemAvailabilityResponse) soapTemplate.marshalSendAndReceive(request);
    }
}
```

### How It Works (walkthrough)

1. `OrderFulfillmentService.canFulfill(order)` calls `inventoryPort.checkAvailability(ItemId("42"), 3)`
2. `LegacyWarehouseInventoryAdapter` receives the call — translates `ItemId("42")` → `"WH-00000042"`
3. `WarehouseSystemClient.getItemAvailability("WH-00000042")` fires SOAP request
4. Legacy responds: XML with `item_status_cd=1`, `available_qty=150`
5. `InventoryTranslator` maps: `item_status_cd=1` → `AVAILABLE`; constructs `InventoryCheck(AVAILABLE, 150)`
6. `OrderFulfillmentService` receives clean domain object: `check.canFulfill()` → true
7. No legacy concept (`item_status_cd`, `WH-` prefix, SOAP, XML) ever crossed into the domain layer

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | `InventoryTranslator` translates; `WarehouseSystemClient` communicates; `Adapter` wires them |
| Open/Closed | ✅ | Adding a new `InventoryPort` implementation for a different backend doesn't change domain code |
| Liskov Substitution | ✅ | Any `InventoryPort` implementation is substitutable — domain doesn't care if it's legacy or new |
| Interface Segregation | ✅ | Domain defines the `InventoryPort` contract with only the methods it needs |
| Dependency Inversion | ✅ | Domain depends on `InventoryPort` (abstraction); ACL is in the infrastructure layer |

---

## When to Use

- Integrating a new service with a legacy system that has a poor domain model (procedural, raw codes, XML/SOAP)
- Two bounded contexts with different domain models that must exchange data
- Replacing a dependency over time — ACL lets you swap the underlying system without touching domain code
- Third-party SaaS integrations where their data model doesn't match your domain

## When NOT to Use

- Both sides share the same domain model — a shared kernel is simpler
- The legacy system will be decommissioned within one sprint — overhead not worth it
- The legacy model is actually better than yours — consider adopting their model instead (Conformist pattern)

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Domain model stays clean — legacy concepts never reach domain logic | Extra layer: translator, adapter, and port to maintain |
| Decoupled replacement — swap the legacy system by writing a new adapter, zero domain changes | Translation bugs: if the mapping is wrong, errors surface far from the source |
| Explicit contract: `InventoryPort` is a clear boundary — easy to mock in tests | N+1 problem: if legacy doesn't support bulk, ACL must implement it (potentially with parallel calls) |

---

**FAANG interview application**: "ACL is the DDD answer to 'how do you integrate with a legacy system without letting it corrupt your domain model?' The key principle is that the domain defines the port interface — the legacy system must conform to you, not the other way around. At Meta, this pattern appears whenever a new service needs data from an older monolith: the new service defines a clean port, an ACL adapter handles all the translation complexity, and a future monolith decomposition only requires writing a new adapter. The port interface never changes. This also makes the domain code 100% unit-testable — mock the port, no legacy system needed."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Repository](24-repository.md) | Repository is often the port that ACL implements — the persistence interface defined in the domain |
| [Strangler Fig](36-strangler-fig.md) | ACL enables Strangler Fig — the new service uses ACL to talk to the legacy system while incrementally replacing it |
| [Adapter (GoF)](../structural/09-adapter.md) | ACL is a Hexagonal Architecture application of the Adapter pattern at bounded context boundaries |
| [Domain Events](31-domain-events.md) | ACL translates legacy events into domain events, preventing legacy event schemas from entering the domain |
