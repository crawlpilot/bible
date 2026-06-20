# 08. Composite
**Category**: Structural  
**GoF**: Yes  
**Complexity**: Medium  
**Frequency in FAANG interviews**: Common

> Compose objects into tree structures to represent part-whole hierarchies. Composite lets clients treat individual objects and compositions of objects uniformly.

---

## Problem It Solves

A shopping cart contains individual items, bundle deals (buy headphones + case + cable as a unit), and combo offers (bundle + extended warranty). Calculating the total, applying discounts, or rendering the cart requires the same operation across all levels of the tree. Without Composite, you write `if (item instanceof Bundle)` branching everywhere. With Composite, every item — leaf or composite — implements the same `CartItem` interface, and `calculateTotal()` is a recursive tree walk.

## Structure (Participants)

```
           «interface»
            CartItem
  ┌─────────────────────────┐
  │ + getPrice(): Money     │
  │ + applyDiscount(pct)    │
  │ + getDescription(): str │
  │ + getItems(): List      │
  └─────────────────────────┘
            △
    ┌───────┴────────────┐
    │                    │
SingleItem           CompositeItem
(Leaf)               (Composite)
┌──────────┐        ┌─────────────────────────────┐
│ - sku    │        │ - children: List<CartItem>   │
│ - price  │        │ - discountPct: int           │
│ - qty    │        │ + add(CartItem)              │
└──────────┘        │ + remove(CartItem)           │
                    │ + getPrice() → sum children  │
                    └─────────────────────────────┘
                              △
                    ┌─────────┴────────┐
                    │                  │
               BundleItem         ComboOffer
               (fixed items,      (bundle +
               bundle discount)    add-ons)
```

Key participants:
- **Component** (`CartItem`): interface for all elements — leaf and composite alike
- **Leaf** (`SingleItem`): a single product with no children; implements all Component methods directly
- **Composite** (`CompositeItem`, `BundleItem`, `ComboOffer`): contains children; delegates operations to children and aggregates results
- **Client** (`Cart`): operates on `CartItem` — never checks whether it's a leaf or composite

---

## Real-World Use Case: Shopping Cart with Nested Promotions

Amazon's cart supports: single items, bundle deals (phone + case + charger at a bundle price), combo offers (bundle + AppleCare), and gift sets (multiple items in a gift box). `calculateTotal()`, `applyBulkDiscount()`, `generateInvoiceLines()`, and `checkInventoryAvailability()` all walk the same tree recursively.

### Implementation

```java
// Component interface — uniform interface for leaf and composite
public interface CartItem {
    Money getUnitPrice();
    Money getTotalPrice();            // unit price × qty, or sum of children
    void applyDiscount(int pct);     // applied to self or propagated to children
    String getDescription();
    List<CartItem> getChildren();     // empty for leaves
    boolean isAvailable();           // inventory check
}

// Leaf — a single product SKU
public class SingleItem implements CartItem {
    private final String sku;
    private final String name;
    private final int quantity;
    private Money unitPrice;
    private boolean inStock;

    public SingleItem(String sku, String name, int quantity, Money unitPrice, boolean inStock) {
        this.sku = sku;
        this.name = name;
        this.quantity = quantity;
        this.unitPrice = unitPrice;
        this.inStock = inStock;
    }

    @Override public Money getUnitPrice()   { return unitPrice; }
    @Override public Money getTotalPrice()  { return unitPrice.multiply(quantity); }
    @Override public void applyDiscount(int pct) {
        this.unitPrice = unitPrice.multiply(100 - pct).divide(100);
    }
    @Override public String getDescription() { return quantity + "× " + name + " @ " + unitPrice; }
    @Override public List<CartItem> getChildren() { return Collections.emptyList(); }
    @Override public boolean isAvailable()  { return inStock && quantity > 0; }
}

// Composite — a bundle (phone + case + charger as a unit)
public class BundleItem implements CartItem {
    private final String bundleName;
    private final List<CartItem> components;
    private int bundleDiscountPct;        // extra discount for buying as a bundle

    public BundleItem(String bundleName, int bundleDiscountPct) {
        this.bundleName = bundleName;
        this.bundleDiscountPct = bundleDiscountPct;
        this.components = new ArrayList<>();
    }

    public void add(CartItem item)    { components.add(item); }
    public void remove(CartItem item) { components.remove(item); }

    @Override
    public Money getTotalPrice() {
        Money subtotal = components.stream()
            .map(CartItem::getTotalPrice)
            .reduce(Money.ZERO, Money::add);
        return subtotal.multiply(100 - bundleDiscountPct).divide(100);
    }

    @Override
    public void applyDiscount(int pct) {
        // Propagate discount to all children (additional to bundle discount)
        components.forEach(c -> c.applyDiscount(pct));
    }

    @Override
    public String getDescription() {
        String childDesc = components.stream()
            .map(CartItem::getDescription)
            .collect(Collectors.joining(", "));
        return bundleName + " [" + bundleDiscountPct + "% off] (" + childDesc + ")";
    }

    @Override public List<CartItem> getChildren() { return Collections.unmodifiableList(components); }
    @Override public Money getUnitPrice()         { return getTotalPrice(); }

    @Override
    public boolean isAvailable() {
        return components.stream().allMatch(CartItem::isAvailable);  // all components must be in stock
    }
}

// Composite — a combo offer (bundle + add-ons)
public class ComboOffer implements CartItem {
    private final String offerName;
    private final List<CartItem> items;
    private final Money fixedOfferPrice;   // combo has a fixed price, not sum of parts

    public ComboOffer(String offerName, Money fixedPrice) {
        this.offerName = offerName;
        this.fixedOfferPrice = fixedPrice;
        this.items = new ArrayList<>();
    }

    public void add(CartItem item)    { items.add(item); }

    @Override public Money getUnitPrice()         { return fixedOfferPrice; }
    @Override public Money getTotalPrice()         { return fixedOfferPrice; }
    @Override public void applyDiscount(int pct)  { /* fixed price — discount not propagated */ }
    @Override public String getDescription() {
        return offerName + " (fixed: " + fixedOfferPrice + ")";
    }
    @Override public List<CartItem> getChildren() { return Collections.unmodifiableList(items); }
    @Override public boolean isAvailable() {
        return items.stream().allMatch(CartItem::isAvailable);
    }
}

// Cart — client that operates on CartItem uniformly
public class Cart {
    private final List<CartItem> items = new ArrayList<>();

    public void addItem(CartItem item)    { items.add(item); }
    public void removeItem(CartItem item) { items.remove(item); }

    public Money calculateTotal() {
        return items.stream()
            .map(CartItem::getTotalPrice)  // works for both leaves and composites
            .reduce(Money.ZERO, Money::add);
    }

    public void applyBulkDiscount(int pct) {
        items.forEach(item -> item.applyDiscount(pct));  // propagates recursively
    }

    public boolean isFullyAvailable() {
        return items.stream().allMatch(CartItem::isAvailable);
    }

    public List<String> generateInvoiceLines() {
        return items.stream()
            .map(CartItem::getDescription)  // recursive for composites
            .collect(toList());
    }
}

// Usage — building a complex cart
Cart cart = new Cart();

// Single item
cart.addItem(new SingleItem("SKU-001", "Laptop Stand", 1, Money.of(39.99), true));

// Bundle deal
BundleItem phoneBundle = new BundleItem("Smartphone Bundle", 15); // 15% bundle discount
phoneBundle.add(new SingleItem("SKU-100", "Galaxy S25", 1, Money.of(999.99), true));
phoneBundle.add(new SingleItem("SKU-101", "Galaxy Case", 1, Money.of(49.99), true));
phoneBundle.add(new SingleItem("SKU-102", "Fast Charger", 1, Money.of(29.99), true));
cart.addItem(phoneBundle);

// Combo offer (bundle + AppleCare)
ComboOffer combo = new ComboOffer("Galaxy S25 + AppleCare Combo", Money.of(1099.00));
combo.add(phoneBundle);
combo.add(new SingleItem("SKU-200", "AppleCare+ 2yr", 1, Money.of(149.00), true));
cart.addItem(combo);

Money total = cart.calculateTotal();  // walks the tree recursively
```

### How It Works (walkthrough)

1. `cart.calculateTotal()` iterates over top-level items: `SingleItem`, `BundleItem`, `ComboOffer`
2. `SingleItem.getTotalPrice()` → `39.99 × 1 = 39.99`
3. `BundleItem.getTotalPrice()` → sums children (`999.99 + 49.99 + 29.99 = 1079.97`), applies 15% discount → `917.97`
4. `ComboOffer.getTotalPrice()` → returns fixed `1099.00`
5. Cart never checks `instanceof` — uniform treatment of leaves and composites

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | `SingleItem` handles leaf pricing; `BundleItem` handles aggregation |
| Open/Closed | ✅ | Add `GiftSetItem` composite without changing `Cart` or `SingleItem` |
| Liskov Substitution | ✅ | `BundleItem` is substitutable for `CartItem` in all contexts |
| Interface Segregation | ⚠️ | `getChildren()` is meaningless for `SingleItem` — common Composite trade-off |
| Dependency Inversion | ✅ | `Cart` depends on `CartItem` interface, not on concrete types |

---

## When to Use

- Data has a natural tree structure (cart items, file system, org hierarchy, UI component tree)
- Clients should treat single items and groups uniformly — no `instanceof` checks
- Operations (calculate, validate, render) must propagate recursively through the tree

## When NOT to Use

- The hierarchy is always flat — a simple list is cleaner
- Leaf and composite operations are fundamentally different — forcing a unified interface creates confusion
- The tree structure changes very rarely — a simple nested list may suffice

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Uniform interface — client code never branches on leaf vs composite | `getChildren()` on leaf is meaningless — minor interface pollution |
| Recursive operations work naturally on any depth of tree | Can be over-general — type safety is reduced when any CartItem can hold any CartItem |
| Easy to add new composite types without changing client | Designing the component interface requires anticipating all operations upfront |

---

**FAANG interview application**: "I'd model the cart as a Composite tree when the cart supports nested structures — individual items, bundles, and combo offers. The key insight is that `Cart.calculateTotal()` doesn't need to know the depth or type of the tree — it calls `getTotalPrice()` on each top-level item and the recursion handles the rest. Adding a new composite type (gift set, subscription box) means adding one new class that implements `CartItem` — the cart and checkout pipeline are untouched."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Decorator](09-decorator.md) | Both use recursive composition; Decorator adds behaviour to a single object, Composite aggregates children |
| [Iterator](../behavioral/15-iterator.md) | Iterator can traverse the Composite tree without the client knowing the tree structure |
| [Visitor](../behavioral/22-visitor.md) | Visitor adds operations to every node in a Composite tree without modifying the nodes |
| [Builder](../creational/04-builder.md) | Builder can be used to construct complex Composite trees step-by-step |
