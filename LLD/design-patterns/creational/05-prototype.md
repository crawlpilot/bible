# 05. Prototype
**Category**: Creational  
**GoF**: Yes  
**Complexity**: Low  
**Frequency in FAANG interviews**: Occasional

> Specify the kinds of objects to create using a prototypical instance, and create new objects by copying this prototype.

---

## Problem It Solves

A marketplace has 50,000 sellers. Each seller can create product listings, but 80% of a listing's data is identical to an existing one (same category, attributes, shipping template, return policy, image schema). Creating each listing from scratch is expensive: schema validation, attribute population, template selection, policy inheritance. The Prototype pattern clones an existing listing as the base, then the seller modifies only the deltas.

## Structure (Participants)

```
           «interface»
         Cloneable / Prototype
       ┌─────────────────────┐
       │ + clone(): Prototype │
       └─────────────────────┘
                 △
         ┌───────┴───────┐
         │               │
  ProductListing    ProductTemplate
  (concrete clone)  (registered prototype)


        PrototypeRegistry
  ┌────────────────────────────────┐
  │ - prototypes: Map<String, T>  │
  │ + register(key, proto)        │
  │ + get(key): T  (returns clone)│
  └────────────────────────────────┘
```

Key participants:
- **Prototype** (`ProductListing`): defines `clone()` method; knows how to deep-copy itself
- **Concrete Prototype**: implements the cloning logic — shallow or deep copy depending on field types
- **Registry** (`ProductTemplateRegistry`): stores named prototypes; returns clones on demand
- **Client**: requests a clone from the registry; modifies only the delta fields

---

## Real-World Use Case: Marketplace Product Listing Template System

Amazon's Seller Central allows sellers to use "listing templates" — pre-configured listings for a category (e.g., "Consumer Electronics — Headphones"). The template contains 40+ attributes (category, compliance certifications, return window, fulfillment template, image slots, variation theme). A seller clicks "Create similar listing" → the system clones the template → seller fills in the unique fields (ASIN title, price, GTIN).

A second use: **A/B test variant creation** — a base `ExperimentConfig` is cloned, then one field is modified for each experiment arm, without manually constructing each variant from scratch.

### The Design

`ProductListingTemplate` is stored in `TemplateRegistry` keyed by category. Sellers call `TemplateRegistry.get("electronics/headphones")` which returns a deep clone. The seller modifies `title`, `price`, `barcode` and submits. The base template is never modified.

### Implementation

```java
// Prototype interface
public interface Cloneable<T> {
    T clone();
}

// Concrete Prototype — product listing
public class ProductListing implements Cloneable<ProductListing> {
    private String title;
    private String categoryPath;           // e.g., "Electronics/Audio/Headphones"
    private Map<String, String> attributes; // mutable map — must deep-copy
    private ShippingTemplate shippingTemplate;
    private ReturnPolicy returnPolicy;
    private List<ImageSlot> imageSlots;    // mutable list — must deep-copy
    private ComplianceCertifications certifications;
    private FulfillmentConfig fulfillmentConfig;

    // Deep copy — critical for mutable fields
    @Override
    public ProductListing clone() {
        ProductListing copy = new ProductListing();
        copy.title = this.title;                                   // String — immutable, safe to share
        copy.categoryPath = this.categoryPath;                     // String — immutable
        copy.attributes = new HashMap<>(this.attributes);         // deep copy — mutable map
        copy.shippingTemplate = this.shippingTemplate.clone();    // deep copy — mutable object
        copy.returnPolicy = this.returnPolicy;                    // immutable value object — safe to share
        copy.imageSlots = this.imageSlots.stream()
            .map(ImageSlot::clone).collect(toList());             // deep copy — list of mutable objects
        copy.certifications = this.certifications;                // immutable — safe to share
        copy.fulfillmentConfig = this.fulfillmentConfig.clone();  // deep copy
        return copy;
    }

    // Fluent setters for modification after cloning
    public ProductListing withTitle(String title)   { this.title = title; return this; }
    public ProductListing withPrice(Money price)    { this.attributes.put("price", price.toString()); return this; }
    public ProductListing withBarcode(String gtin)  { this.attributes.put("gtin", gtin); return this; }

    // Getters...
}

// Prototype Registry
public class TemplateRegistry {
    private static final Map<String, ProductListing> templates = new ConcurrentHashMap<>();

    // Pre-loaded at startup from DB or config
    public static void register(String categoryKey, ProductListing template) {
        templates.put(categoryKey, template);
    }

    // Always returns a CLONE — never the prototype itself
    public static ProductListing get(String categoryKey) {
        ProductListing proto = templates.get(categoryKey);
        if (proto == null) throw new IllegalArgumentException("Unknown template: " + categoryKey);
        return proto.clone();
    }

    public static Set<String> availableTemplates() {
        return Collections.unmodifiableSet(templates.keySet());
    }
}

// Template initialization at startup
public class TemplateLoader {
    public static void load(TemplateRepository repo) {
        repo.findAll().forEach(template ->
            TemplateRegistry.register(template.categoryKey(), template)
        );
    }
}

// Client — seller service
public class ListingCreationService {
    public ProductListing createFromTemplate(String categoryKey, SellerInput input) {
        // Clone the template — O(1) relative to constructing from scratch
        ProductListing listing = TemplateRegistry.get(categoryKey)
            .withTitle(input.title())
            .withPrice(input.price())
            .withBarcode(input.barcode());

        // Seller-specific overrides
        if (input.hasCustomShipping()) {
            listing.setShippingTemplate(input.shippingTemplate());
        }

        return listing;
    }
}

// A/B experiment use case
public class ExperimentVariantFactory {
    private final ExperimentConfig baseConfig;

    public ExperimentConfig createVariant(String variantName, Consumer<ExperimentConfig> modification) {
        ExperimentConfig variant = baseConfig.clone();  // Prototype pattern
        modification.accept(variant);
        variant.setName(variantName);
        return variant;
    }
}

// Usage
ExperimentVariantFactory factory = new ExperimentVariantFactory(baseConfig);
ExperimentConfig controlGroup = factory.createVariant("control", c -> {});
ExperimentConfig variantA = factory.createVariant("variant-a", c -> c.setRankingModel("neural-v2"));
ExperimentConfig variantB = factory.createVariant("variant-b", c -> c.setPersonalizationLevel("high"));
```

### How It Works (walkthrough)

1. Startup: `TemplateLoader` loads all category templates from DB into `TemplateRegistry`
2. Seller requests "create listing in Electronics/Headphones"
3. `TemplateRegistry.get("electronics/headphones")` → calls `proto.clone()` → returns deep copy
4. Seller fills in `title`, `price`, `barcode` — only delta fields
5. Original prototype in registry is unmodified — safe for all future sellers to clone

**Deep copy correctness**: `attributes` (HashMap) is deep-copied — if two sellers modify their listings' attributes, they don't interfere. `returnPolicy` is an immutable value object — safe to share.

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | `ProductListing` knows how to clone itself; `TemplateRegistry` manages prototype storage |
| Open/Closed | ✅ | Add new template types (new category keys) without changing existing classes |
| Liskov Substitution | ✅ | Any `Cloneable<ProductListing>` can be registered and cloned uniformly |
| Interface Segregation | ✅ | `clone()` is the only method required; separate from domain behaviour |
| Dependency Inversion | ⚠️ | `TemplateRegistry` is a static singleton — can be refactored to an injectable interface |

---

## When to Use

- Object initialization is expensive (complex schema, many fields, external validation) and cloning is cheaper
- Many objects need the same base configuration with small variations (templates, experiment configs, role-based default settings)
- You want to avoid a class hierarchy of constructors for each variant — clone + modify is simpler
- The exact class of an object isn't known at compile time but the prototype is known

## When NOT to Use

- Objects are simple to construct — `new Object()` is cheaper and clearer than registering a prototype
- Deep copy is itself expensive (large object graphs, cyclical references) — prototype's advantage disappears
- When each object is fundamentally different — no meaningful prototype to clone from

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Avoids costly initialization — clone is O(copy size) vs O(construction cost) | Deep copy implementation is error-prone — easy to accidentally shallow-copy a mutable field |
| Decouples client from concrete class — client asks registry for a clone | Clone must be kept in sync as the class adds fields |
| Dynamic registration — new templates added at runtime without code changes | Cyclical object references make deep copy complex (need cycle detection) |
| Reduces subclass explosion — variants = prototype + modification | Cloned objects carry all prototype state — unused fields waste memory |

---

**FAANG interview application**: "Prototype fits when object construction is expensive and most objects share the same base configuration. For a marketplace listing template system, storing 20 category prototypes in a registry and cloning on demand is far cheaper than re-validating 40 attributes per new listing. The critical implementation detail is the deep-copy contract — mutable fields (HashMap, ArrayList) must be copied, immutable fields (String, value objects) can be shared. I'd add a unit test for each field to enforce the copy contract as the class evolves."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Singleton](01-singleton.md) | The Prototype Registry is typically a Singleton |
| [Factory Method](02-factory-method.md) | Factory Method can return a clone of a prototype instead of calling `new` |
| [Abstract Factory](03-abstract-factory.md) | Factories can store prototypes and return clones as the creation mechanism |
| [Decorator](../structural/09-decorator.md) | Clone the base + wrap with Decorator to add variation without modifying the prototype |
