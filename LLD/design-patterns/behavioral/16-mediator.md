# 16. Mediator
**Category**: Behavioral  
**GoF**: Yes  
**Complexity**: Medium  
**Frequency in FAANG interviews**: Occasional

> Define an object that encapsulates how a set of objects interact. Mediator promotes loose coupling by keeping objects from referring to each other explicitly.

---

## Problem It Solves

A checkout form has 6 components that affect each other: entering a promo code recalculates the total; changing the delivery speed changes the shipping cost and delivery estimate; switching payment method may change whether a promo is valid; selecting an address may change tax. Without Mediator, each component holds references to every other — spaghetti coupling. With Mediator, each component talks only to the mediator, which coordinates the cascade.

## Structure (Participants)

```
         «interface»
        CheckoutMediator
  ┌─────────────────────────────┐
  │ + notify(sender, event)     │
  └─────────────────────────────┘
              △
  CheckoutCoordinator
  ┌─────────────────────────────────────────────┐
  │ - promoField: PromoInputComponent            │
  │ - deliverySelector: DeliverySpeedComponent   │
  │ - paymentPanel: PaymentMethodComponent       │
  │ - addressForm: AddressComponent              │
  │ - orderSummary: OrderSummaryComponent        │
  │ + notify(sender, event)                      │
  └─────────────────────────────────────────────┘

  Components (each has a mediator reference):
  PromoInput → mediator.notify(this, "PROMO_APPLIED")
  DeliverySpeed → mediator.notify(this, "SPEED_CHANGED")
  PaymentMethod → mediator.notify(this, "PAYMENT_CHANGED")
```

Key participants:
- **Mediator** (`CheckoutMediator`): interface for receiving component events and coordinating responses
- **Concrete Mediator** (`CheckoutCoordinator`): knows all components; implements cascade logic
- **Colleagues** (form components): each holds a `mediator` reference; calls `mediator.notify()` on state change; never directly references other components

---

## Real-World Use Case: Checkout Form Coordination

A checkout page has: `PromoInputComponent`, `DeliverySpeedComponent`, `PaymentMethodComponent`, `AddressComponent`, `OrderSummaryComponent`, and `PlaceOrderButton`. When any component changes, others must update consistently. The mediator captures all the cascade rules in one place.

### Implementation

```java
// Mediator interface
public interface CheckoutMediator {
    void notify(Object sender, String event, Object payload);
}

// Component base — holds mediator reference
public abstract class CheckoutComponent {
    protected CheckoutMediator mediator;

    public void setMediator(CheckoutMediator mediator) { this.mediator = mediator; }

    protected void emit(String event, Object payload) {
        mediator.notify(this, event, payload);
    }
}

// Components
public class PromoInputComponent extends CheckoutComponent {
    private String enteredCode;
    private PromoResult lastResult;

    public void applyPromo(String code) {
        this.enteredCode = code;
        emit("PROMO_ENTERED", code);
    }

    public void showValidPromo(PromoResult result) {
        this.lastResult = result;
        // update UI: show green checkmark + discount amount
    }

    public void showInvalidPromo(String reason) {
        // update UI: show error message
    }
}

public class DeliverySpeedComponent extends CheckoutComponent {
    private DeliverySpeed selected = DeliverySpeed.STANDARD;

    public void selectSpeed(DeliverySpeed speed) {
        this.selected = speed;
        emit("DELIVERY_SPEED_CHANGED", speed);
    }

    public DeliverySpeed getSelected() { return selected; }
}

public class AddressComponent extends CheckoutComponent {
    private Address shippingAddress;

    public void addressEntered(Address address) {
        this.shippingAddress = address;
        emit("ADDRESS_CHANGED", address);
    }

    public Address getShippingAddress() { return shippingAddress; }
}

public class OrderSummaryComponent extends CheckoutComponent {
    public void update(PricingResult pricing) {
        // Render: subtotal, discounts, tax, shipping, total
    }
    public void setPlaceOrderEnabled(boolean enabled) { /* enable/disable submit button */ }
}

// Concrete Mediator — all coordination logic in one place
public class CheckoutCoordinator implements CheckoutMediator {
    private final PromoInputComponent promoInput;
    private final DeliverySpeedComponent deliverySpeed;
    private final AddressComponent addressForm;
    private final OrderSummaryComponent orderSummary;

    // Services
    private final PromoService promoService;
    private final TaxService taxService;
    private final ShippingService shippingService;
    private final PricingEngine pricingEngine;

    // Current state
    private Cart cart;
    private User user;
    private PromoResult activePromo;

    public CheckoutCoordinator(Cart cart, User user, /* components + services */) {
        this.cart = cart;
        this.user = user;
        // Wire mediator into all components
        promoInput.setMediator(this);
        deliverySpeed.setMediator(this);
        addressForm.setMediator(this);
        orderSummary.setMediator(this);
    }

    @Override
    public void notify(Object sender, String event, Object payload) {
        switch (event) {
            case "PROMO_ENTERED" -> handlePromoEntered((String) payload);
            case "DELIVERY_SPEED_CHANGED" -> handleSpeedChanged((DeliverySpeed) payload);
            case "ADDRESS_CHANGED" -> handleAddressChanged((Address) payload);
        }
    }

    private void handlePromoEntered(String code) {
        PromoResult result = promoService.validate(code, cart, user);
        if (result.isValid()) {
            activePromo = result;
            promoInput.showValidPromo(result);
        } else {
            activePromo = null;
            promoInput.showInvalidPromo(result.invalidReason());
        }
        recalculateAndRender();
    }

    private void handleSpeedChanged(DeliverySpeed speed) {
        recalculateAndRender();  // shipping cost changes
    }

    private void handleAddressChanged(Address address) {
        // Validate address, recalculate tax, re-validate promo (geo-restricted promos)
        if (activePromo != null && !promoService.isValidForAddress(activePromo, address)) {
            activePromo = null;
            promoInput.showInvalidPromo("Promo not valid for this address");
        }
        recalculateAndRender();
    }

    private void recalculateAndRender() {
        PricingContext ctx = PricingContext.builder()
            .cart(cart).user(user)
            .promoResult(activePromo)
            .deliverySpeed(deliverySpeed.getSelected())
            .shippingAddress(addressForm.getShippingAddress())
            .build();

        PricingResult pricing = pricingEngine.calculate(ctx);
        orderSummary.update(pricing);

        boolean canPlaceOrder = addressForm.getShippingAddress() != null
            && pricing.total().isGreaterThan(Money.ZERO);
        orderSummary.setPlaceOrderEnabled(canPlaceOrder);
    }
}
```

### How It Works (walkthrough)

1. User enters promo code "SAVE15"
2. `promoInput.applyPromo("SAVE15")` → `mediator.notify(promoInput, "PROMO_ENTERED", "SAVE15")`
3. `CheckoutCoordinator.handlePromoEntered("SAVE15")`: validates promo → valid → sets `activePromo`
4. `promoInput.showValidPromo(result)` → UI shows green check
5. `recalculateAndRender()` → reprices cart with promo discount → `orderSummary.update(newPricing)`
6. User changes address → `mediator.notify(addressForm, "ADDRESS_CHANGED", newAddr)` → geo-validates promo → recalculates tax → rerenders summary
7. Components never reference each other — only the mediator does

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | Each component manages its own UI; mediator manages coordination |
| Open/Closed | ⚠️ | Adding new events requires mediator modification — trade-off of centralization |
| Liskov Substitution | ✅ | All components implement `CheckoutComponent` |
| Interface Segregation | ✅ | `notify()` is the only mediator-facing method |
| Dependency Inversion | ✅ | Components depend on `CheckoutMediator` interface |

---

## When to Use

- Multiple objects interact in complex, many-to-many ways
- You want to centralize coordination logic that would otherwise be scattered across components
- Components should be reusable independently (e.g., `AddressForm` used in profile settings too)

## When NOT to Use

- Components have simple, one-directional dependencies — use direct references
- The mediator grows too large (God class) — split into multiple smaller mediators by domain
- Components interact in simple, linear flows — use Chain of Responsibility instead

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Components are decoupled — testable in isolation | Mediator becomes a God class if not bounded |
| Coordination logic centralized — easy to understand and modify cascade rules | All cross-component interactions now require mediator involvement — indirection |
| Components can be reused without the mediator's coupling | Mediator has high coupling to all components |

---

**FAANG interview application**: "Mediator is the right pattern for a checkout form where 6 components must stay consistent — promo validity, tax, shipping, and payment method all affect each other. Without Mediator, adding a new component means updating N existing components. With Mediator, the new component emits events to the mediator, which handles the cascade. The trade-off is that the mediator can grow; I'd split by domain if it exceeds ~200 lines."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Facade](../structural/10-facade.md) | Facade is a one-way simplifier (client → subsystem); Mediator is two-way (colleagues ↔ mediator) |
| [Observer](18-observer.md) | Observer decouples via events; Mediator centralizes. Mediator can use Observer internally. |
