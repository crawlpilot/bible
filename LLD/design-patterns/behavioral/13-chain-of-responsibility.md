# 13. Chain of Responsibility
**Category**: Behavioral  
**GoF**: Yes  
**Complexity**: Medium  
**Frequency in FAANG interviews**: Common

> Avoid coupling the sender of a request to its receiver by giving more than one object a chance to handle the request. Chain the receiving objects and pass the request along the chain until an object handles it.

---

## Problem It Solves

A promo engine must evaluate whether a user's cart qualifies for a discount, checking in priority order: employee discount → active coupon code → loyalty tier discount → flash sale → bundle deal. Each check has its own eligibility rules. Without CoR, you write a deeply nested `if-else` tower. With CoR, each check is a handler class — new discount types are added by inserting a new handler, not by modifying the evaluation logic.

## Structure (Participants)

```
     «abstract»
   PromoHandler
┌─────────────────────────────┐
│ # next: PromoHandler        │
│ + setNext(handler)          │
│ + handle(ctx): PromoResult  │
└─────────────────────────────┘
            △
  ┌─────────┼──────────────────────┐
  │         │                      │
CouponH  LoyaltyH  FlashSaleH   BundleH
            ...
```

Key participants:
- **Handler** (`PromoHandler`): abstract class with `next` reference and `handle()` method
- **Concrete Handlers**: each implements eligibility check + either handles or passes to `next`
- **Client** (`PromoEngine`): builds the chain, submits `PromoContext` to the head

---

## Real-World Use Case: Promotion Eligibility Pipeline

An e-commerce platform has 5 discount types applied in priority order. Each handler decides if it applies; if yes, it enriches the context and may still pass to the next (stackable discounts) or short-circuit (exclusive discounts). The chain is built from merchant config — a flash sale merchant may not stack loyalty discounts.

### Implementation

```java
public record PromoContext(
    Cart cart, User user, String couponCode,
    List<AppliedDiscount> appliedDiscounts  // mutated by handlers
) {
    public void addDiscount(AppliedDiscount d) { appliedDiscounts.add(d); }
    public Money totalDiscount() {
        return appliedDiscounts.stream().map(AppliedDiscount::amount)
            .reduce(Money.ZERO, Money::add);
    }
}

// Abstract handler
public abstract class PromoHandler {
    protected PromoHandler next;

    public PromoHandler setNext(PromoHandler next) {
        this.next = next;
        return next;   // fluent for chaining
    }

    public abstract PromoContext handle(PromoContext ctx);

    protected PromoContext passToNext(PromoContext ctx) {
        return next != null ? next.handle(ctx) : ctx;
    }
}

// Handler 1: Employee discount — exclusive, highest priority
public class EmployeeDiscountHandler extends PromoHandler {
    private final EmployeeService employeeService;

    @Override
    public PromoContext handle(PromoContext ctx) {
        if (employeeService.isEmployee(ctx.user().id())) {
            ctx.addDiscount(new AppliedDiscount("EMPLOYEE", ctx.cart().subtotal().multiply(30).divide(100), "Employee 30% off"));
            return ctx;  // exclusive — stop chain
        }
        return passToNext(ctx);
    }
}

// Handler 2: Coupon code
public class CouponHandler extends PromoHandler {
    private final CouponService couponService;

    @Override
    public PromoContext handle(PromoContext ctx) {
        if (ctx.couponCode() != null) {
            CouponResult result = couponService.validate(ctx.couponCode(), ctx.cart(), ctx.user());
            if (result.isValid()) {
                ctx.addDiscount(new AppliedDiscount("COUPON_" + ctx.couponCode(), result.discountAmount(), result.description()));
                // Stackable — pass to next to check more discounts
            }
        }
        return passToNext(ctx);
    }
}

// Handler 3: Loyalty tier discount
public class LoyaltyDiscountHandler extends PromoHandler {
    private final LoyaltyService loyaltyService;

    @Override
    public PromoContext handle(PromoContext ctx) {
        LoyaltyTier tier = loyaltyService.getTier(ctx.user().id());
        if (tier != LoyaltyTier.NONE) {
            Money discount = ctx.cart().subtotal().multiply(tier.discountPct()).divide(100);
            ctx.addDiscount(new AppliedDiscount("LOYALTY_" + tier.name(), discount, tier.name() + " member discount"));
        }
        return passToNext(ctx);
    }
}

// Handler 4: Flash sale — time-based, per-category
public class FlashSaleHandler extends PromoHandler {
    private final FlashSaleService flashSaleService;

    @Override
    public PromoContext handle(PromoContext ctx) {
        List<FlashSale> activeSales = flashSaleService.getActiveSales();
        for (FlashSale sale : activeSales) {
            Money eligibleValue = ctx.cart().getItemsByCategory(sale.category())
                .stream().map(CartItem::getTotalPrice).reduce(Money.ZERO, Money::add);
            if (eligibleValue.isGreaterThan(Money.ZERO)) {
                Money discount = eligibleValue.multiply(sale.discountPct()).divide(100);
                ctx.addDiscount(new AppliedDiscount("FLASH_" + sale.id(), discount, sale.description()));
            }
        }
        return passToNext(ctx);
    }
}

// Handler 5: Bundle discount (buy 3+ items, 5% off)
public class BundleDiscountHandler extends PromoHandler {
    @Override
    public PromoContext handle(PromoContext ctx) {
        int itemCount = ctx.cart().totalItemCount();
        if (itemCount >= 5) {
            ctx.addDiscount(new AppliedDiscount("BUNDLE5", ctx.cart().subtotal().multiply(5).divide(100), "5+ items: 5% off"));
        } else if (itemCount >= 3) {
            ctx.addDiscount(new AppliedDiscount("BUNDLE3", ctx.cart().subtotal().multiply(2).divide(100), "3+ items: 2% off"));
        }
        return passToNext(ctx);
    }
}

// Chain builder
public class PromoEngine {
    public PromoContext evaluate(PromoContext ctx, PromoConfig config) {
        PromoHandler chain = buildChain(config);
        return chain.handle(ctx);
    }

    private PromoHandler buildChain(PromoConfig config) {
        EmployeeDiscountHandler employee = new EmployeeDiscountHandler(employeeService);
        CouponHandler coupon = new CouponHandler(couponService);
        LoyaltyDiscountHandler loyalty = new LoyaltyDiscountHandler(loyaltyService);
        FlashSaleHandler flash = new FlashSaleHandler(flashSaleService);
        BundleDiscountHandler bundle = new BundleDiscountHandler();

        // Fluent chain setup
        employee.setNext(coupon).setNext(loyalty).setNext(flash).setNext(bundle);
        return employee;
    }
}
```

### How It Works (walkthrough)

1. User (non-employee, coupon "SAVE10", loyalty GOLD) checks out cart of 4 items
2. `EmployeeDiscountHandler`: not employee → `passToNext()`
3. `CouponHandler`: SAVE10 valid → adds $15 discount → `passToNext()`
4. `LoyaltyDiscountHandler`: GOLD tier (8%) → adds $24 → `passToNext()`
5. `FlashSaleHandler`: no active flash sales → `passToNext()`
6. `BundleDiscountHandler`: 4 items < 5, ≥ 3 → adds 2% ($6) → `passToNext()` → null → return
7. Final: 3 discounts applied = $45 off

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | Each handler has one discount type to check |
| Open/Closed | ✅ | Add `SubscriberDiscountHandler` — insert it in the chain; existing handlers unchanged |
| Liskov Substitution | ✅ | All handlers are substitutable `PromoHandler` |
| Interface Segregation | ✅ | Single `handle()` method |
| Dependency Inversion | ✅ | `PromoEngine` depends on abstract `PromoHandler` |

---

## When to Use

- Multiple handlers may handle a request, and the set is known only at runtime
- You want to decouple the sender from the concrete handlers
- Handlers should be composable and orderable from config (not hardcoded)

## When NOT to Use

- There's only one handler — use a simple conditional
- Every request must be handled — guarantee handling in the last handler if needed
- Handler order is fixed at compile time — a simple list of handlers called sequentially is cleaner

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Add/remove handlers without changing client | No guarantee request is handled — need a default handler |
| Runtime composable chain from config | Debugging: must trace the full chain to find where request was handled or dropped |
| Each handler is independently unit-testable | Chain order bugs are subtle — wrong order = wrong discount priority |

---

**FAANG interview application**: "Chain of Responsibility is the right pattern for a promo eligibility pipeline where the set of discount rules is configurable, stackable, and may short-circuit. Each handler checks one rule and either applies it or passes to the next. The chain is built by the factory from merchant config — a flash-sale-only merchant disables the loyalty handler. Each handler is unit-tested with a mock `next` — you never need to set up the full chain to test one handler."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Decorator](../structural/09-decorator.md) | Both are linear chains; Decorator always delegates to next; CoR may short-circuit |
| [Command](14-command.md) | Commands often flow through a CoR pipeline for authorization/validation |
| [Composite](../structural/08-composite.md) | A composite of handlers is itself a CoR |
