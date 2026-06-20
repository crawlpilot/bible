# 22. Visitor
**Category**: Behavioral  
**GoF**: Yes  
**Complexity**: High  
**Frequency in FAANG interviews**: Occasional

> Represent an operation to be performed on the elements of an object structure. Visitor lets you define a new operation without changing the classes of the elements on which it operates.

---

## Problem It Solves

A cart has `SingleItem`, `BundleItem`, and `SubscriptionItem` types. Calculating tax requires different rules per type (subscription items are tax-exempt in some regions). Estimating shipping requires per-item weight. Applying promo discounts requires category-specific logic. Without Visitor, all these operations would be methods on each cart item class — adding `calculateShipping()` means modifying 3 classes. Visitor adds new operations without modifying the item classes.

## Structure (Participants)

```
    «interface»              «interface»
   CartVisitor               CartItem
┌──────────────────┐      ┌────────────────────────────┐
│ visit(SingleItem)│      │ + accept(CartVisitor)       │
│ visit(BundleItem)│      └────────────────────────────┘
│ visit(SubItem)   │                   △
└──────────────────┘       ┌───────────┼───────────────┐
        △                  │           │               │
TaxCalculator  SingleItem  BundleItem  SubscriptionItem
Visitor        + accept()  + accept()  + accept()
DiscountVisitor
ShippingVisitor
```

Key participants:
- **Visitor** (`CartVisitor`): interface with one `visit()` overload per element type
- **Concrete Visitors** (`TaxCalculatorVisitor`, `DiscountApplierVisitor`, `ShippingEstimatorVisitor`): implement the operation for each element type
- **Element** (`CartItem`): interface with `accept(CartVisitor)` method
- **Concrete Elements** (`SingleItem`, `BundleItem`, `SubscriptionItem`): implement `accept()` by calling `visitor.visit(this)` — double dispatch
- **Object Structure** (`Cart`): iterates elements and calls `accept()` on each

---

## Real-World Use Case: Cart Tax + Discount + Shipping Calculation

The cart has 3 item types with different tax, discount, and shipping rules. Each operation (tax, discount, shipping) is a separate Visitor — adding a new operation (insurance estimate) requires one new visitor class, no changes to item classes.

### Implementation

```java
// Element interface
public interface CartItem {
    void accept(CartVisitor visitor);
    String sku();
    String name();
    int quantity();
    Money getUnitPrice();
}

// Concrete Elements
public class SingleItem implements CartItem {
    private final String sku;
    private final String name;
    private final int quantity;
    private final Money unitPrice;
    private final String category;
    private final double weightKg;

    // ... constructor ...

    @Override public void accept(CartVisitor visitor) { visitor.visit(this); }  // double dispatch
    @Override public String sku()        { return sku; }
    @Override public String name()       { return name; }
    @Override public int quantity()      { return quantity; }
    @Override public Money getUnitPrice() { return unitPrice; }
    public String getCategory()         { return category; }
    public double getWeightKg()         { return weightKg; }
}

public class BundleItem implements CartItem {
    private final String bundleId;
    private final List<CartItem> components;
    private final Money bundlePrice;

    @Override public void accept(CartVisitor visitor) { visitor.visit(this); }  // double dispatch
    @Override public String sku()        { return bundleId; }
    @Override public String name()       { return "Bundle " + bundleId; }
    @Override public int quantity()      { return 1; }
    @Override public Money getUnitPrice() { return bundlePrice; }
    public List<CartItem> getComponents() { return components; }
}

public class SubscriptionItem implements CartItem {
    private final String subscriptionId;
    private final SubscriptionPlan plan;

    @Override public void accept(CartVisitor visitor) { visitor.visit(this); }  // double dispatch
    @Override public String sku()         { return subscriptionId; }
    @Override public String name()        { return plan.name() + " Subscription"; }
    @Override public int quantity()       { return 1; }
    @Override public Money getUnitPrice() { return plan.monthlyPrice(); }
    public SubscriptionPlan getPlan()     { return plan; }
    public boolean isDigital()            { return true; }
}

// Visitor interface — one method per concrete element type
public interface CartVisitor {
    void visit(SingleItem item);
    void visit(BundleItem bundle);
    void visit(SubscriptionItem subscription);
}

// Visitor 1: Tax Calculator
public class TaxCalculatorVisitor implements CartVisitor {
    private final TaxService taxService;
    private final Address shippingAddress;
    private Money totalTax = Money.ZERO;
    private final List<TaxLineItem> taxBreakdown = new ArrayList<>();

    @Override
    public void visit(SingleItem item) {
        TaxRate rate = taxService.getRateForCategory(item.getCategory(), shippingAddress);
        Money itemTax = item.getUnitPrice().multiply(item.quantity()).multiply(rate.value()).divide(100);
        totalTax = totalTax.add(itemTax);
        taxBreakdown.add(new TaxLineItem(item.sku(), itemTax, rate));
    }

    @Override
    public void visit(BundleItem bundle) {
        // Bundle: visit each component for individual tax calculation
        bundle.getComponents().forEach(c -> c.accept(this));
    }

    @Override
    public void visit(SubscriptionItem subscription) {
        // Subscriptions are tax-exempt in most jurisdictions
        if (taxService.isSubscriptionTaxable(shippingAddress)) {
            Money tax = subscription.getUnitPrice().multiply(taxService.getSubscriptionRate(shippingAddress)).divide(100);
            totalTax = totalTax.add(tax);
        }
        // else: no tax added
    }

    public Money getTotalTax()                  { return totalTax; }
    public List<TaxLineItem> getTaxBreakdown()  { return taxBreakdown; }
}

// Visitor 2: Discount Applier
public class DiscountApplierVisitor implements CartVisitor {
    private final PromoConfig promo;
    private Money totalDiscount = Money.ZERO;

    @Override
    public void visit(SingleItem item) {
        if (promo.appliesToCategory(item.getCategory())) {
            Money discount = item.getUnitPrice().multiply(item.quantity())
                .multiply(promo.discountPct()).divide(100);
            totalDiscount = totalDiscount.add(discount);
        }
    }

    @Override
    public void visit(BundleItem bundle) {
        if (promo.appliesToBundles()) {
            Money discount = bundle.getUnitPrice().multiply(promo.discountPct()).divide(100);
            totalDiscount = totalDiscount.add(discount);
        }
    }

    @Override
    public void visit(SubscriptionItem subscription) {
        // Promos do not apply to subscriptions by default
        if (promo.appliesToSubscriptions()) {
            Money discount = subscription.getUnitPrice().multiply(promo.discountPct()).divide(100);
            totalDiscount = totalDiscount.add(discount);
        }
    }

    public Money getTotalDiscount() { return totalDiscount; }
}

// Visitor 3: Shipping Estimator
public class ShippingEstimatorVisitor implements CartVisitor {
    private final ShippingRateTable rateTable;
    private double totalWeightKg = 0;
    private final List<String> nonShippableItems = new ArrayList<>();

    @Override
    public void visit(SingleItem item) {
        totalWeightKg += item.getWeightKg() * item.quantity();
    }

    @Override
    public void visit(BundleItem bundle) {
        bundle.getComponents().forEach(c -> c.accept(this));  // accumulate weight of all components
    }

    @Override
    public void visit(SubscriptionItem subscription) {
        nonShippableItems.add(subscription.name());  // digital — no shipping
    }

    public Money estimateShipping(DeliverySpeed speed, Address destination) {
        if (totalWeightKg == 0) return Money.ZERO;
        return rateTable.lookup(totalWeightKg, speed, destination);
    }

    public double getTotalWeightKg() { return totalWeightKg; }
}

// Cart — the Object Structure
public class Cart {
    private final List<CartItem> items = new ArrayList<>();

    public void addItem(CartItem item) { items.add(item); }

    public <T extends CartVisitor> T accept(T visitor) {
        items.forEach(item -> item.accept(visitor));  // double dispatch on each item
        return visitor;
    }
}

// Client
Cart cart = new Cart();
cart.addItem(new SingleItem("SKU-100", "Laptop", 1, Money.of(1299), "electronics", 2.1));
cart.addItem(new BundleItem("BUNDLE-1", List.of(case_, cable_), Money.of(79)));
cart.addItem(new SubscriptionItem("SUB-001", SubscriptionPlan.PREMIUM));

TaxCalculatorVisitor taxCalc = cart.accept(new TaxCalculatorVisitor(taxService, shippingAddr));
DiscountApplierVisitor discountCalc = cart.accept(new DiscountApplierVisitor(activePromo));
ShippingEstimatorVisitor shippingCalc = cart.accept(new ShippingEstimatorVisitor(rateTable));
Money shipping = shippingCalc.estimateShipping(DeliverySpeed.STANDARD, shippingAddr);
```

### How It Works (walkthrough — double dispatch)

1. `cart.accept(taxCalc)` → iterates items → `singleItem.accept(taxCalc)`
2. `SingleItem.accept(v)` calls `v.visit(this)` → dispatches to `TaxCalculatorVisitor.visit(SingleItem)`
3. Tax calculated for the specific type — with its specific fields (`category`, `weight`)
4. `bundleItem.accept(taxCalc)` → `TaxCalculatorVisitor.visit(BundleItem)` → recursively visits components
5. `subscriptionItem.accept(taxCalc)` → `TaxCalculatorVisitor.visit(SubscriptionItem)` → may skip tax
6. Adding `InsuranceEstimatorVisitor` → zero changes to `SingleItem`, `BundleItem`, `SubscriptionItem`

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | TaxCalculator only calculates tax; each visitor has one concern |
| Open/Closed | ✅ | Add new visitor (InsuranceEstimator) without modifying element classes |
| Liskov Substitution | ✅ | All visitors substitutable; all elements substitutable |
| Interface Segregation | ⚠️ | Adding a new element type requires all visitors to add a new `visit()` method |
| Dependency Inversion | ✅ | Cart depends on `CartVisitor` and `CartItem` interfaces |

---

## When to Use

- Object structure is stable; operations on the structure change frequently
- Many unrelated operations on an object hierarchy without polluting them with those methods
- Add new operations to sealed class hierarchies (Java sealed, Kotlin sealed)

## When NOT to Use

- Element hierarchy changes frequently — adding a new element type requires updating all visitors
- Operations are few and stable — just add methods to the element classes
- The hierarchy is simple (one or two types) — direct dispatch is simpler

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Add operations without modifying element classes | Adding new element type requires modifying all visitors |
| Visitor accumulates state across the traversal | Breaks encapsulation slightly — visitor may need access to element internals |
| Double dispatch: correct behavior per type without instanceof | More complex pattern to explain and understand |

---

**FAANG interview application**: "Visitor is the right pattern when the object hierarchy is stable but operations change. For a cart with 3 item types, TaxCalculator, ShippingEstimator, and DiscountApplier are separate visitors — each implements the rules for each item type. Adding a new 'InsuranceEstimator' visitor requires one new class; the item classes are untouched. The double dispatch (`accept(v)` → `v.visit(this)`) is the key mechanism — it routes to the correct `visit()` overload based on the runtime type of the element."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Composite](../structural/08-composite.md) | Visitor often traverses a Composite tree — `BundleItem.accept()` recursively visits children |
| [Iterator](15-iterator.md) | Iterator traverses the collection; Visitor operates on each element during traversal |
| [Strategy](20-strategy.md) | Strategy replaces an algorithm; Visitor adds an algorithm to an existing hierarchy |
