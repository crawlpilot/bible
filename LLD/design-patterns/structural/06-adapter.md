# 06. Adapter
**Category**: Structural  
**GoF**: Yes  
**Complexity**: Low  
**Frequency in FAANG interviews**: Common

> Convert the interface of a class into another interface clients expect. Adapter lets classes work together that couldn't otherwise because of incompatible interfaces.

---

## Problem It Solves

A platform has processed payments through an in-house `LegacyPaymentSystem` for 10 years. The new checkout service is built against a clean `PaymentGateway` interface. The legacy system has a completely different API — `makePayment(accountNo, dollars, cents, ref)` instead of `charge(Money, PaymentMethod)`. Rewriting the legacy system is too risky. The Adapter wraps the legacy system, translating calls without touching either side.

## Structure (Participants)

```
«interface»                        «class»
PaymentGateway       Adapter      LegacyPaymentSystem
┌────────────┐    ┌───────────────────────────────┐    ┌────────────────────────┐
│ + charge() │◄───│ LegacyPaymentAdapter           │───►│ + makePayment()        │
│ + refund() │    │ - legacy: LegacyPaymentSystem  │    │ + reverseTransaction() │
│ +getStatus()    │ + charge()   → makePayment()   │    │ + queryTransaction()   │
└────────────┘    │ + refund()   → reverseXaction()│    └────────────────────────┘
                  │ + getStatus()→ queryXaction()  │
                  └───────────────────────────────┘
```

Key participants:
- **Target** (`PaymentGateway`): the interface clients expect
- **Adaptee** (`LegacyPaymentSystem`): existing class with the incompatible interface
- **Adapter** (`LegacyPaymentAdapter`): wraps the Adaptee and implements the Target interface
- **Client** (`CheckoutService`): works only against the Target interface — never knows about the Adaptee

---

## Real-World Use Case: Legacy Payment Processor Integration

An e-commerce platform has a 10-year-old in-house payment processor (`LegacyPaymentSystem`). The new `CheckoutService` is built against `PaymentGateway`. The legacy system uses an RPC protocol with positional parameters and integer-cent amounts instead of `Money` objects. Rewriting the legacy system would take 6 months; the adapter takes 2 days.

A second real-world adapter: **shipping carrier unification** — FedEx, UPS, and DHL each have different APIs. `FedExAdapter`, `UPSAdapter`, `DHLAdapter` all implement `ShippingProvider`, and the fulfillment service uses only `ShippingProvider`.

### Implementation

```java
// Target interface — what the new system expects
public interface PaymentGateway {
    ChargeResult charge(Money amount, PaymentMethod paymentMethod);
    RefundResult refund(String transactionId, Money amount);
    TransactionStatus getStatus(String transactionId);
}

// Adaptee — legacy system with incompatible interface (cannot be modified)
public class LegacyPaymentSystem {
    // Old API: account number, dollars, cents, reference code
    public LegacyChargeResponse makePayment(
            String accountNumber, int dollars, int cents, String referenceCode) {
        // ... calls legacy RPC ...
        return new LegacyChargeResponse(/* ... */);
    }

    public LegacyRefundResponse reverseTransaction(String legacyTxRef, int dollars, int cents) {
        // ...
    }

    public LegacyStatusResponse queryTransaction(String legacyTxRef) {
        // ...
    }
}

// Adapter — bridges the two worlds
public class LegacyPaymentAdapter implements PaymentGateway {
    private final LegacyPaymentSystem legacy;

    public LegacyPaymentAdapter(LegacyPaymentSystem legacy) {
        this.legacy = legacy;
    }

    @Override
    public ChargeResult charge(Money amount, PaymentMethod paymentMethod) {
        // Translate Money → dollars + cents
        int dollars = amount.wholeDollars();
        int cents = amount.remainingCents();

        // Translate PaymentMethod → account number format legacy expects
        String accountNumber = paymentMethod.toAccountNumber();
        String referenceCode = UUID.randomUUID().toString().replace("-", "").substring(0, 12);

        LegacyChargeResponse legacyResponse = legacy.makePayment(accountNumber, dollars, cents, referenceCode);

        // Translate legacy response → new ChargeResult
        return legacyResponse.isApproved()
            ? ChargeResult.success(legacyResponse.getAuthCode(), amount)
            : ChargeResult.failure(legacyResponse.getDeclineReason());
    }

    @Override
    public RefundResult refund(String transactionId, Money amount) {
        LegacyRefundResponse response = legacy.reverseTransaction(
            transactionId, amount.wholeDollars(), amount.remainingCents()
        );
        return response.isReversed()
            ? RefundResult.success(response.getReversalCode())
            : RefundResult.failure(response.getErrorMessage());
    }

    @Override
    public TransactionStatus getStatus(String transactionId) {
        LegacyStatusResponse response = legacy.queryTransaction(transactionId);
        return switch (response.getLegacyStatus()) {
            case "APPROVED" -> TransactionStatus.CAPTURED;
            case "DECLINED" -> TransactionStatus.DECLINED;
            case "REVERSED" -> TransactionStatus.REFUNDED;
            case "PENDING"  -> TransactionStatus.PENDING;
            default         -> TransactionStatus.UNKNOWN;
        };
    }
}

// Shipping adapter example — same pattern
public interface ShippingProvider {
    ShipmentLabel createLabel(Package pkg, Address from, Address to);
    TrackingInfo track(String trackingNumber);
}

public class FedExAdapter implements ShippingProvider {
    private final FedExWebServiceClient fedEx;

    @Override
    public ShipmentLabel createLabel(Package pkg, Address from, Address to) {
        FedExShipRequest req = FedExShipRequest.builder()
            .shipper(toFedExAddress(from))
            .recipient(toFedExAddress(to))
            .weight(pkg.weightInOz())
            .dimensions(pkg.dimensions())
            .build();
        FedExShipResponse resp = fedEx.ship(req);
        return new ShipmentLabel(resp.getTrackingNumber(), resp.getLabelBytes());
    }

    @Override
    public TrackingInfo track(String trackingNumber) {
        FedExTrackResponse resp = fedEx.track(trackingNumber);
        return new TrackingInfo(resp.getStatus(), resp.getEstimatedDelivery(), resp.getEvents());
    }

    private FedExAddress toFedExAddress(Address addr) { /* ... */ }
}

// Client — only sees PaymentGateway
public class CheckoutService {
    private final PaymentGateway paymentGateway;

    public CheckoutService(PaymentGateway paymentGateway) {
        this.paymentGateway = paymentGateway;  // injected — could be Stripe, PayPal, or Legacy adapter
    }

    public Receipt processPayment(Order order, PaymentMethod method) {
        ChargeResult result = paymentGateway.charge(order.total(), method);
        if (!result.isSuccessful()) throw new PaymentFailedException(result.error());
        return new Receipt(result.transactionId(), order.total());
    }
}

// Wiring
LegacyPaymentSystem legacy = new LegacyPaymentSystem();
PaymentGateway adapter = new LegacyPaymentAdapter(legacy);
CheckoutService checkout = new CheckoutService(adapter);  // legacy system, new interface
```

### How It Works (walkthrough)

1. `CheckoutService.processPayment()` calls `paymentGateway.charge(Money.of(99.99), card)`
2. `LegacyPaymentAdapter.charge()` receives `Money.of(99.99)` → translates to `dollars=99, cents=99`
3. Calls `legacy.makePayment("4111111111111111", 99, 99, "REF20241124")` — legacy RPC call
4. `LegacyChargeResponse` → translated to `ChargeResult.success("AUTH-XYZ", Money.of(99.99))`
5. `CheckoutService` receives a modern `ChargeResult` — never aware of legacy system

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | Adapter's only job: translate between two interfaces |
| Open/Closed | ✅ | Add new adapters (FedEx, UPS, DHL) without touching `ShippingProvider` or fulfillment service |
| Liskov Substitution | ✅ | `LegacyPaymentAdapter` is fully substitutable for any `PaymentGateway` |
| Interface Segregation | ✅ | `PaymentGateway` is a focused interface — adapter implements only what's needed |
| Dependency Inversion | ✅ | `CheckoutService` depends on `PaymentGateway` abstraction, not on any concrete system |

---

## When to Use

- You need to use an existing class with an incompatible interface and cannot modify it (legacy, third-party, SDK)
- You want a unified interface over multiple external systems with different APIs (shipping carriers, payment providers)
- You are integrating third-party libraries that don't match your domain model

## When NOT to Use

- Both interfaces are similar and a simple wrapper is all that's needed — a plain wrapper without the pattern overhead
- The adaptee's API will change frequently — adapters become maintenance burden when both sides are unstable
- You can modify the adaptee's source — just make it implement the target interface directly

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Integrates incompatible interfaces without modifying either side | Extra layer — debugging requires tracing through the adapter |
| Client code stays clean and testable (depends on interface only) | Adapter can become complex if the translation is lossy or stateful |
| Easy to swap — replace one adapter with another, client unchanged | Does not solve fundamental API incompatibilities — some features may not map |

---

**FAANG interview application**: "Adapter is the right pattern when you need to integrate a legacy system or third-party SDK that you cannot modify. The key design decision is the translation layer: the adapter must correctly map data types (Money → dollars/cents), error codes (LegacyDeclineCode → DeclineReason), and lifecycle concepts (legacy transaction IDs → new transactionId format). I'd build the adapter with extensive unit tests using a mock legacy system — the translation logic is where bugs hide."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Decorator](09-decorator.md) | Decorator keeps the same interface and adds behaviour; Adapter changes the interface |
| [Proxy](12-proxy.md) | Proxy keeps the same interface and controls access; Adapter changes the interface |
| [Facade](10-facade.md) | Facade simplifies a complex subsystem; Adapter makes one interface compatible with another |
| [Factory Method](../creational/02-factory-method.md) | Factory often creates the appropriate adapter based on config |
