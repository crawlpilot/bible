# 20. Strategy
**Category**: Behavioral  
**GoF**: Yes  
**Complexity**: Low  
**Frequency in FAANG interviews**: Common

> Define a family of algorithms, encapsulate each one, and make them interchangeable. Strategy lets the algorithm vary independently from clients that use it.

---

## Problem It Solves

A promo engine must apply different discount types: percentage off, fixed amount off, buy-X-get-Y-free, bundle pricing (buy 3 for $49.99). Each merchant can configure which strategy to use. Hardcoding all algorithms in one `DiscountCalculator` class violates OCP — adding BOGO requires modifying the class. Strategy makes each algorithm a class, selected at runtime from merchant config.

## Structure (Participants)

```
     «interface»
  DiscountStrategy
┌─────────────────────────────────┐
│ + apply(cart, promo): Money     │
│ + describe(): String            │
│ + isEligible(cart, user): bool  │
└─────────────────────────────────┘
              △
  ┌───────────┼─────────────────────┐
  │           │                     │
Percentage  FixedAmount  BuyXGetY  Bundle
Strategy    Strategy     Strategy  Pricing
```

Key participants:
- **Strategy** (`DiscountStrategy`): interface for all discount algorithms
- **Concrete Strategies**: each implements one discount type
- **Context** (`PromoEngine`): holds a strategy reference; calls `strategy.apply(cart, promo)`
- **Client**: selects and injects the appropriate strategy from config

---

## Real-World Use Case: Promo Discount Engine

A marketplace lets merchants create promotions: "20% off electronics", "$15 off orders over $100", "Buy 2 get 1 free on headphones", "Any 3 t-shirts for $49.99". Each is a different strategy. The `PromoEngine` applies whichever strategy is configured for the active promo — no if-else.

### Implementation

```java
// Strategy interface
public interface DiscountStrategy {
    DiscountResult apply(Cart cart, PromoConfig promo, User user);
    boolean isEligible(Cart cart, PromoConfig promo, User user);
    String describe();
}

public record DiscountResult(Money discountAmount, String description, List<String> affectedSkus) {}

// Strategy 1: Percentage off
public class PercentageDiscountStrategy implements DiscountStrategy {
    @Override
    public boolean isEligible(Cart cart, PromoConfig promo, User user) {
        Money cartSubtotal = cart.subtotal();
        Money minimumOrder = promo.minimumOrderValue();
        return cartSubtotal.isGreaterThanOrEqualTo(minimumOrder);
    }

    @Override
    public DiscountResult apply(Cart cart, PromoConfig promo, User user) {
        int pct = promo.discountPercentage();
        List<CartItem> eligibleItems = promo.categoryFilter() != null
            ? cart.getItemsByCategory(promo.categoryFilter())
            : cart.getItems();

        Money discountBase = eligibleItems.stream()
            .map(CartItem::getTotalPrice).reduce(Money.ZERO, Money::add);
        Money discount = discountBase.multiply(pct).divide(100);

        List<String> affectedSkus = eligibleItems.stream().map(CartItem::sku).collect(toList());
        return new DiscountResult(discount, pct + "% off " + (promo.categoryFilter() != null ? promo.categoryFilter() : "all items"), affectedSkus);
    }

    @Override public String describe() { return "Percentage Discount"; }
}

// Strategy 2: Fixed amount off (with minimum order threshold)
public class FixedAmountDiscountStrategy implements DiscountStrategy {
    @Override
    public boolean isEligible(Cart cart, PromoConfig promo, User user) {
        return cart.subtotal().isGreaterThanOrEqualTo(promo.minimumOrderValue());
    }

    @Override
    public DiscountResult apply(Cart cart, PromoConfig promo, User user) {
        Money discount = promo.fixedDiscountAmount().min(cart.subtotal()); // can't discount more than cart total
        return new DiscountResult(discount, "$" + discount + " off your order", emptyList());
    }

    @Override public String describe() { return "Fixed Amount Discount"; }
}

// Strategy 3: Buy X Get Y Free (BOGO and variants)
public class BuyXGetYFreeStrategy implements DiscountStrategy {
    @Override
    public boolean isEligible(Cart cart, PromoConfig promo, User user) {
        int eligibleCount = cart.getItemsByCategory(promo.categoryFilter())
            .stream().mapToInt(CartItem::quantity).sum();
        return eligibleCount >= promo.buyQuantity();
    }

    @Override
    public DiscountResult apply(Cart cart, PromoConfig promo, User user) {
        List<CartItem> eligibleItems = cart.getItemsByCategory(promo.categoryFilter());
        // Sort cheapest first — give away the cheapest as the "free" item
        eligibleItems.sort(Comparator.comparing(item -> item.getUnitPrice()));

        int totalQty = eligibleItems.stream().mapToInt(CartItem::quantity).sum();
        int freeQty = (totalQty / (promo.buyQuantity() + promo.getQuantity())) * promo.getQuantity();

        // Sum of the cheapest items (the ones that are free)
        Money discount = Money.ZERO;
        int remaining = freeQty;
        for (CartItem item : eligibleItems) {
            if (remaining <= 0) break;
            int freeFromThis = Math.min(remaining, item.quantity());
            discount = discount.add(item.getUnitPrice().multiply(freeFromThis));
            remaining -= freeFromThis;
        }

        return new DiscountResult(discount, "Buy " + promo.buyQuantity() + " Get " + promo.getQuantity() + " Free", emptyList());
    }

    @Override public String describe() { return "Buy X Get Y Free"; }
}

// Strategy 4: Bundle pricing (any 3 for $49.99)
public class BundlePricingStrategy implements DiscountStrategy {
    @Override
    public boolean isEligible(Cart cart, PromoConfig promo, User user) {
        int eligibleCount = cart.getItemsByCategory(promo.categoryFilter())
            .stream().mapToInt(CartItem::quantity).sum();
        return eligibleCount >= promo.bundleSize();
    }

    @Override
    public DiscountResult apply(Cart cart, PromoConfig promo, User user) {
        List<CartItem> eligibleItems = cart.getItemsByCategory(promo.categoryFilter());
        int totalQty = eligibleItems.stream().mapToInt(CartItem::quantity).sum();
        int completeBundles = totalQty / promo.bundleSize();

        // Total actual price of bundle items
        Money actualPrice = eligibleItems.stream()
            .map(CartItem::getTotalPrice).reduce(Money.ZERO, Money::add);

        // Price at bundle rate
        Money bundlePrice = promo.bundlePrice().multiply(completeBundles);

        // Remaining items (not in a complete bundle) at regular price
        int remainingQty = totalQty % promo.bundleSize();
        // ... calculate remaining price ...

        Money discount = actualPrice.subtract(bundlePrice);
        return new DiscountResult(discount, completeBundles + " bundle(s) of " + promo.bundleSize() + " for $" + promo.bundlePrice(), emptyList());
    }

    @Override public String describe() { return "Bundle Pricing"; }
}

// Strategy registry — loaded from DB
public class DiscountStrategyRegistry {
    private final Map<String, DiscountStrategy> strategies = Map.of(
        "PERCENTAGE", new PercentageDiscountStrategy(),
        "FIXED_AMOUNT", new FixedAmountDiscountStrategy(),
        "BUY_X_GET_Y", new BuyXGetYFreeStrategy(),
        "BUNDLE_PRICE", new BundlePricingStrategy()
    );

    public DiscountStrategy get(String strategyType) {
        DiscountStrategy strategy = strategies.get(strategyType);
        if (strategy == null) throw new IllegalArgumentException("Unknown discount strategy: " + strategyType);
        return strategy;
    }
}

// Context — the PromoEngine
public class PromoEngine {
    private final DiscountStrategyRegistry registry;

    public PromoApplicationResult applyPromo(Cart cart, PromoConfig promo, User user) {
        DiscountStrategy strategy = registry.get(promo.strategyType());

        if (!strategy.isEligible(cart, promo, user)) {
            return PromoApplicationResult.notEligible(strategy.describe());
        }

        DiscountResult result = strategy.apply(cart, promo, user);
        return PromoApplicationResult.applied(result);
    }
}
```

### How It Works (walkthrough)

1. Merchant promo: `{strategyType: "BUY_X_GET_Y", buyQuantity: 2, getQuantity: 1, categoryFilter: "headphones"}`
2. Cart has 3 Sony headphones ($199 each)
3. `registry.get("BUY_X_GET_Y")` → `BuyXGetYFreeStrategy`
4. `isEligible()`: 3 ≥ 2 → true
5. `apply()`: buy 2 get 1 → 1 free item → cheapest = $199 → discount = $199
6. `PromoEngine` returns `DiscountResult($199, "Buy 2 Get 1 Free", ["SKU-HEADPHONE"])`

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | Each strategy implements one discount algorithm |
| Open/Closed | ✅ | Add `FlashSaleStrategy` — new class; `PromoEngine` and registry unchanged |
| Liskov Substitution | ✅ | All strategies substitutable through `DiscountStrategy` |
| Interface Segregation | ✅ | Focused interface: `apply()`, `isEligible()`, `describe()` |
| Dependency Inversion | ✅ | `PromoEngine` depends on `DiscountStrategy` interface |

---

## When to Use

- Multiple algorithms for the same operation; the algorithm is selected at runtime from config
- Algorithms must be independently testable and swappable
- Eliminate conditional branching that selects among algorithm variants

## When NOT to Use

- Only 1–2 algorithms exist and won't change — a simple function or method is cleaner
- Algorithm selection is static/compile-time — use inheritance
- Algorithms need to share a lot of state with the context — consider Template Method instead

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Add new algorithms without changing existing code (OCP) | Client must know which strategy to pick (resolved by factory/registry) |
| Each strategy is independently unit-testable | Number of classes grows with number of algorithms |
| Eliminates conditional branching from context | Communication overhead: context may need to pass data strategies don't need |

---

**FAANG interview application**: "Strategy is the canonical pattern for a promo discount engine. Each discount type is a strategy — percentage, fixed, BOGO, bundle pricing. The PromoEngine doesn't care which strategy it's running; it calls `strategy.apply()`. New discount types are configured in the merchant console, mapped to a strategy class in the registry. At FAANG scale, the strategy registry itself is loaded from a feature-flag system — A/B testing which BOGO variant performs better becomes a strategy swap."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [State](19-state.md) | Both delegate to an interchangeable object. Strategy swaps algorithms; State changes behavior based on lifecycle. |
| [Template Method](21-template-method.md) | Template Method uses inheritance to vary algorithm steps; Strategy uses composition. |
| [Decorator](../structural/09-decorator.md) | Decorator adds behavior layers; Strategy replaces the algorithm. Can be combined: decorator pipeline of strategies. |
| [Factory Method](../creational/02-factory-method.md) | Factory creates the appropriate strategy from config/type |
