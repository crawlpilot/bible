# 09. Decorator
**Category**: Structural  
**GoF**: Yes  
**Complexity**: Medium  
**Frequency in FAANG interviews**: Common

> Attach additional responsibilities to an object dynamically. Decorators provide a flexible alternative to subclassing for extending functionality.

---

## Problem It Solves

A cart's final price must pass through a pipeline: base item price → apply member discount → apply promo code → add tax → add shipping. Each step is conditional (members get the discount, promo code may or may not be present, digital items have no shipping). Hardcoding all combinations in a single `PriceCalculator` class violates SRP and OCP. Subclassing produces a combinatorial explosion (`MemberWithPromoWithShipping`, etc.). Decorator wraps a `PriceCalculator` with another, stacking responsibilities at runtime.

## Structure (Participants)

```
         «interface»
       PriceCalculator
  ┌─────────────────────────┐
  │ + calculate(cart): Money │
  └─────────────────────────┘
              △
    ┌─────────┴──────────────────────────┐
    │                                    │
BasePriceCalculator          PriceCalculatorDecorator (abstract)
(Leaf — sums items)         ┌──────────────────────────────────┐
                            │ # wrapped: PriceCalculator       │
                            │ + calculate(cart): Money         │
                            └──────────────────────────────────┘
                                         △
                    ┌────────────────────┼─────────────────────┐
                    │                    │                      │
          MemberDiscountDecorator  PromoCodeDecorator   TaxDecorator
          ShippingCostDecorator    LoggingDecorator
```

Key participants:
- **Component** (`PriceCalculator`): interface for the core operation
- **Concrete Component** (`BasePriceCalculator`): the un-decorated base implementation
- **Decorator** (abstract): wraps a Component, delegates to it, then adds behaviour
- **Concrete Decorators**: each adds one specific responsibility (`MemberDiscountDecorator`, `TaxDecorator`, etc.)

---

## Real-World Use Case: Cart Pricing Pipeline

The cart pricing pipeline must be configurable per merchant and per user: some merchants disable loyalty discounts, some categories are tax-exempt, digital goods have no shipping, some users have no promo code. Decorator lets the pipeline be assembled at runtime from the user/merchant config.

### Implementation

```java
// Component interface
public interface PriceCalculator {
    PricingResult calculate(Cart cart, PricingContext ctx);
}

// Pricing result carries breakdown for invoice/display
public record PricingResult(
    Money subtotal,
    Money memberDiscount,
    Money promoDiscount,
    Money tax,
    Money shipping,
    Money total,
    List<String> appliedRules
) { }

// Base — sums line items at face value
public class BasePriceCalculator implements PriceCalculator {
    @Override
    public PricingResult calculate(Cart cart, PricingContext ctx) {
        Money subtotal = cart.getItems().stream()
            .map(item -> item.getUnitPrice().multiply(item.getQuantity()))
            .reduce(Money.ZERO, Money::add);
        return new PricingResult(subtotal, Money.ZERO, Money.ZERO, Money.ZERO, Money.ZERO,
            subtotal, List.of("Base price calculated"));
    }
}

// Abstract Decorator — delegates to wrapped calculator, then applies adjustment
public abstract class PriceCalculatorDecorator implements PriceCalculator {
    protected final PriceCalculator wrapped;

    protected PriceCalculatorDecorator(PriceCalculator wrapped) {
        this.wrapped = wrapped;
    }

    @Override
    public PricingResult calculate(Cart cart, PricingContext ctx) {
        PricingResult base = wrapped.calculate(cart, ctx);  // delegate first
        return applyAdjustment(base, cart, ctx);            // then adjust
    }

    protected abstract PricingResult applyAdjustment(PricingResult result, Cart cart, PricingContext ctx);
}

// Concrete Decorators
public class MemberDiscountDecorator extends PriceCalculatorDecorator {
    private final MembershipService membershipService;

    public MemberDiscountDecorator(PriceCalculator wrapped, MembershipService ms) {
        super(wrapped);
        this.membershipService = ms;
    }

    @Override
    protected PricingResult applyAdjustment(PricingResult result, Cart cart, PricingContext ctx) {
        if (!membershipService.isPrimeMember(ctx.userId())) return result;  // skip non-members

        int discountPct = membershipService.getMemberDiscountPct(ctx.userId());
        Money discount = result.subtotal().multiply(discountPct).divide(100);

        return new PricingResult(
            result.subtotal(),
            discount,                               // member discount filled in
            result.promoDiscount(),
            result.tax(),
            result.shipping(),
            result.total().subtract(discount),      // total reduced
            append(result.appliedRules(), "Member " + discountPct + "% discount: -" + discount)
        );
    }
}

public class PromoCodeDecorator extends PriceCalculatorDecorator {
    private final PromoService promoService;

    public PromoCodeDecorator(PriceCalculator wrapped, PromoService promoService) {
        super(wrapped);
        this.promoService = promoService;
    }

    @Override
    protected PricingResult applyAdjustment(PricingResult result, Cart cart, PricingContext ctx) {
        if (ctx.promoCode() == null) return result;

        PromoResult promo = promoService.evaluate(ctx.promoCode(), cart, ctx.userId());
        if (!promo.isValid()) return result;

        Money discount = promo.discountAmount();
        return new PricingResult(
            result.subtotal(), result.memberDiscount(),
            discount,                               // promo discount filled in
            result.tax(), result.shipping(),
            result.total().subtract(discount),
            append(result.appliedRules(), "Promo '" + ctx.promoCode() + "': -" + discount)
        );
    }
}

public class TaxDecorator extends PriceCalculatorDecorator {
    private final TaxService taxService;

    public TaxDecorator(PriceCalculator wrapped, TaxService taxService) {
        super(wrapped);
        this.taxService = taxService;
    }

    @Override
    protected PricingResult applyAdjustment(PricingResult result, Cart cart, PricingContext ctx) {
        Money taxableAmount = result.total();   // tax applied on discounted total
        Money tax = taxService.calculateTax(taxableAmount, cart, ctx.shippingAddress());
        return new PricingResult(
            result.subtotal(), result.memberDiscount(), result.promoDiscount(),
            tax,                                // tax filled in
            result.shipping(),
            result.total().add(tax),            // total increased
            append(result.appliedRules(), "Tax: +" + tax)
        );
    }
}

public class ShippingCostDecorator extends PriceCalculatorDecorator {
    private final ShippingCalculator shippingCalc;

    public ShippingCostDecorator(PriceCalculator wrapped, ShippingCalculator shippingCalc) {
        super(wrapped);
        this.shippingCalc = shippingCalc;
    }

    @Override
    protected PricingResult applyAdjustment(PricingResult result, Cart cart, PricingContext ctx) {
        if (cart.isDigitalOnly()) return result;   // no shipping for digital goods
        if (result.total().isGreaterThan(Money.of(35))) {
            return appendRule(result, "Free shipping (order > $35)");
        }
        Money shipping = shippingCalc.estimate(cart, ctx.shippingAddress(), ctx.deliverySpeed());
        return new PricingResult(
            result.subtotal(), result.memberDiscount(), result.promoDiscount(), result.tax(),
            shipping,                            // shipping filled in
            result.total().add(shipping),
            append(result.appliedRules(), "Shipping: +" + shipping)
        );
    }
}

// Pipeline factory — assembles the decorator chain based on config
public class PricingPipelineFactory {
    public static PriceCalculator build(PricingConfig config, ServiceLocator services) {
        PriceCalculator pipeline = new BasePriceCalculator();

        if (config.memberDiscountEnabled()) {
            pipeline = new MemberDiscountDecorator(pipeline, services.membershipService());
        }
        if (config.promoCodesEnabled()) {
            pipeline = new PromoCodeDecorator(pipeline, services.promoService());
        }
        if (config.taxEnabled()) {
            pipeline = new TaxDecorator(pipeline, services.taxService());
        }
        if (config.shippingEnabled()) {
            pipeline = new ShippingCostDecorator(pipeline, services.shippingCalc());
        }
        return pipeline;
    }
}

// Client
PriceCalculator pipeline = PricingPipelineFactory.build(merchantConfig, services);
PricingResult result = pipeline.calculate(cart, pricingCtx);
```

### How It Works (walkthrough)

Call stack for member with promo on taxable physical order:

```
ShippingCostDecorator.calculate()
  → TaxDecorator.calculate()
      → PromoCodeDecorator.calculate()
          → MemberDiscountDecorator.calculate()
              → BasePriceCalculator.calculate() → subtotal = $100
          → member 10% discount: -$10, total = $90
      → promo SAVE20: -$18, total = $72
  → tax (8.5%): +$6.12, total = $78.12
→ shipping: +$5.99, total = $84.11
```

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | Each decorator does exactly one thing: member discount, promo, tax, or shipping |
| Open/Closed | ✅ | Add `LoyaltyPointsDecorator` without touching any existing decorator |
| Liskov Substitution | ✅ | All decorators implement `PriceCalculator` and are fully substitutable |
| Interface Segregation | ✅ | `PriceCalculator` is a focused single-method interface |
| Dependency Inversion | ✅ | Each decorator depends on `PriceCalculator` abstraction — infinite nesting possible |

---

## When to Use

- Behaviour should be added to objects at runtime without changing their class
- Behaviours should be combinable in any order and any subset
- Subclassing leads to a combinatorial explosion (MemberWithPromoWithTax, MemberWithTax, etc.)
- Cross-cutting concerns: logging, caching, rate limiting, authentication wrapped around any service

## When NOT to Use

- The set of combinations is small and fixed — simple subclassing is cleaner and more discoverable
- Order of decoration matters but is hard to communicate — document and test the required order
- Performance is critical — each decorator adds a stack frame; deep chains have overhead

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Runtime composition — assemble pipeline from config | Order of decorators matters — hard to debug if wrong order applied |
| SRP: each decorator is one class, one concern | Many small classes — IDE navigation can be harder |
| OCP: add behaviours without touching existing code | Decorator identity — `instanceof` checks break through the chain |
| Testable independently — each decorator unit-testable in isolation | Complex chains are harder to reason about holistically |

---

**FAANG interview application**: "I'd use Decorator for the cart pricing pipeline because the pricing rules are combinable and configurable per merchant. Each rule is a decorator that wraps the chain and applies its adjustment to the result of the inner chain. The pipeline is assembled by the factory based on merchant config — no if-else inside the calculator. Adding a new rule (loyalty points, flash sale discount) means adding one class and registering it in the factory — zero changes to existing decorators."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Adapter](06-adapter.md) | Adapter changes an interface; Decorator keeps the same interface and adds behaviour |
| [Proxy](12-proxy.md) | Proxy controls access; Decorator adds behaviour. Both wrap an object with the same interface |
| [Composite](08-composite.md) | Both use recursive composition; Composite aggregates children, Decorator wraps a single object |
| [Strategy](../behavioral/20-strategy.md) | Strategy replaces an algorithm; Decorator adds layers around it |
| [Chain of Responsibility](../behavioral/13-chain-of-responsibility.md) | CoR passes a request along a chain; Decorator wraps — both are linear chains but CoR can short-circuit |
