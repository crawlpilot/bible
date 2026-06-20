# 02. Factory Method
**Category**: Creational  
**GoF**: Yes  
**Complexity**: Medium  
**Frequency in FAANG interviews**: Common

> Define an interface for creating an object, but let subclasses decide which class to instantiate.

---

## Problem It Solves

A checkout service must support Stripe, PayPal, and Braintree. Without a factory, the service is littered with `if (provider == "stripe") new StripeGateway() else if ...`. Every new provider requires modifying the checkout service — violating OCP. The Factory Method moves the creation decision to a dedicated creator, keeping the client code stable.

## Structure (Participants)

```
       «interface»
      PaymentGateway                   «abstract»
  ┌───────────────────┐           PaymentProcessor
  │ + charge()        │         ┌──────────────────────┐
  │ + refund()        │         │ + processPayment()   │
  │ + getStatus()     │         │ # createGateway() *  │  ← factory method
  └───────────────────┘         └──────────────────────┘
           △                            △
    ┌──────┴──────┐           ┌─────────┴──────────────┐
    │             │           │                        │
StripeGateway  PayPalGateway  StripeProcessor   PayPalProcessor
                               (creates Stripe)  (creates PayPal)
```

Key participants:
- **Product** (`PaymentGateway`): interface for the objects the factory creates
- **Concrete Product** (`StripeGateway`, `PayPalGateway`): implements Product
- **Creator** (`PaymentProcessor`): declares the factory method `createGateway()`; uses the product but doesn't know the concrete type
- **Concrete Creator** (`StripeProcessor`): overrides the factory method to return a specific Concrete Product

---

## Real-World Use Case: Payment Gateway Factory

A marketplace platform supports 5 payment providers. Each has a different SDK, authentication flow, and API shape. The checkout flow (`processPayment()`) is identical regardless of provider: validate → authorize → capture → return receipt.

### The Design

`PaymentProcessor` defines the template flow and declares `createGateway()` as the factory method. Each `ConcreteProcessor` subclass overrides `createGateway()` to return its specific gateway. The `PaymentProcessorFactory` maps a merchant's configured provider string to the correct `ConcreteProcessor`.

### Implementation

```java
// Product interface
public interface PaymentGateway {
    ChargeResult charge(Money amount, PaymentMethod method);
    RefundResult refund(String transactionId, Money amount);
    TransactionStatus getStatus(String transactionId);
}

// Concrete Products
public class StripeGateway implements PaymentGateway {
    private final StripeClient client;
    public StripeGateway(String apiKey) { this.client = new StripeClient(apiKey); }

    @Override
    public ChargeResult charge(Money amount, PaymentMethod method) {
        return client.paymentIntents().create(amount.cents(), method.stripeToken());
    }
    // ... refund, getStatus
}

public class PayPalGateway implements PaymentGateway {
    private final PayPalClient client;
    // PayPal-specific implementation
}

public class BraintreeGateway implements PaymentGateway {
    // Braintree-specific implementation
}

// Creator (abstract)
public abstract class PaymentProcessor {

    // Factory Method — subclasses override this
    protected abstract PaymentGateway createGateway();

    // Template — identical regardless of gateway
    public PaymentReceipt processPayment(Order order, PaymentMethod method) {
        PaymentGateway gateway = createGateway();         // uses factory method
        ChargeResult charge = gateway.charge(order.total(), method);
        if (!charge.isSuccessful()) {
            throw new PaymentFailedException(charge.errorMessage());
        }
        auditLog(order.id(), charge.transactionId());
        return new PaymentReceipt(charge.transactionId(), order.total());
    }

    private void auditLog(String orderId, String txId) { /* ... */ }
}

// Concrete Creators
public class StripePaymentProcessor extends PaymentProcessor {
    @Override
    protected PaymentGateway createGateway() {
        return new StripeGateway(Config.get("stripe.api_key"));
    }
}

public class PayPalPaymentProcessor extends PaymentProcessor {
    @Override
    protected PaymentGateway createGateway() {
        return new PayPalGateway(Config.get("paypal.client_id"), Config.get("paypal.secret"));
    }
}

public class BraintreePaymentProcessor extends PaymentProcessor {
    @Override
    protected PaymentGateway createGateway() {
        return new BraintreeGateway(Config.get("braintree.merchant_id"));
    }
}

// Registration factory — maps config string to processor
public class PaymentProcessorRegistry {
    private static final Map<String, Supplier<PaymentProcessor>> registry = Map.of(
        "stripe",     StripePaymentProcessor::new,
        "paypal",     PayPalPaymentProcessor::new,
        "braintree",  BraintreePaymentProcessor::new
    );

    public static PaymentProcessor forProvider(String provider) {
        Supplier<PaymentProcessor> supplier = registry.get(provider);
        if (supplier == null) throw new IllegalArgumentException("Unknown provider: " + provider);
        return supplier.get();
    }
}

// Client code — checkout service
public class CheckoutService {
    public Receipt checkout(Order order, Merchant merchant, PaymentMethod method) {
        String provider = merchant.preferredPaymentProvider();
        PaymentProcessor processor = PaymentProcessorRegistry.forProvider(provider);
        return processor.processPayment(order, method);
    }
    // Adding a new provider = new Gateway + new Processor subclass + one registry entry
    // CheckoutService never changes
}
```

### How It Works (walkthrough)

1. Merchant "Acme Corp" has `preferredPaymentProvider = "stripe"`
2. `CheckoutService` calls `PaymentProcessorRegistry.forProvider("stripe")` → returns `StripePaymentProcessor`
3. `processPayment()` calls `createGateway()` → `StripePaymentProcessor` returns `new StripeGateway(...)`
4. `charge()` called on `StripeGateway` → Stripe API called → receipt returned
5. **Adding Adyen**: create `AdyenGateway`, `AdyenPaymentProcessor`, register `"adyen"` → `CheckoutService` unchanged

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | Each class has one job: gateway creation OR payment processing |
| Open/Closed | ✅ | Add new provider by adding new classes, zero modification to existing code |
| Liskov Substitution | ✅ | All `PaymentProcessor` subclasses are substitutable; all gateways implement the same interface |
| Interface Segregation | ✅ | `PaymentGateway` interface is focused: charge, refund, status |
| Dependency Inversion | ✅ | `PaymentProcessor` depends on `PaymentGateway` interface, not on Stripe/PayPal concrete classes |

---

## When to Use

- The exact type of object to create isn't known until runtime (merchant config, user preference, feature flag)
- You want to add new product types without changing existing client code (OCP)
- A class delegates object creation to subclasses
- You need to encapsulate the construction logic (API key retrieval, SDK init) away from the client

## When NOT to Use

- If there's only one product type — a simple constructor call is cleaner
- If the creation logic is trivial — factory adds indirection for no benefit
- If the creator hierarchy becomes large — consider a registry/map approach instead of subclassing

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| OCP — new providers without modifying client | More classes — one `Processor` per provider |
| Encapsulates creation complexity (API keys, SDK init) | Requires subclassing the creator — can get deep |
| Testable — inject a mock gateway via a test `Processor` subclass | Slightly more indirection than a direct constructor call |
| Runtime polymorphism — provider selected from config | Registry + factory pair is two layers of indirection |

---

**FAANG interview application**: "I'd use Factory Method to isolate provider-specific payment gateway creation behind an interface. The `processPayment()` flow never changes — only `createGateway()` differs per subclass. Adding Adyen means a new `AdyenGateway` and `AdyenPaymentProcessor` — the checkout service and the `PaymentProcessor` base class are untouched. This is the Open/Closed Principle applied: open for extension (new subclass), closed for modification (existing code)."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Abstract Factory](03-abstract-factory.md) | Often implemented using Factory Methods; creates *families* of products |
| [Template Method](../behavioral/21-template-method.md) | Factory Method is a specialization of Template Method where the step being varied is object creation |
| [Singleton](01-singleton.md) | The concrete creator is often a Singleton |
| [Prototype](05-prototype.md) | Factory Method can return prototypes instead of `new` instances |
