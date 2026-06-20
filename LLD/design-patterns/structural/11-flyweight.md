# 11. Flyweight
**Category**: Structural  
**GoF**: Yes  
**Complexity**: High  
**Frequency in FAANG interviews**: Occasional

> Use sharing to support a large number of fine-grained objects efficiently.

---

## Problem It Solves

A marketplace has 5 million product SKUs. Each SKU is a `ProductVariant` object (color: red, size: L, stock: 42, price: $29.99). But 80% of the data is identical across variants of the same product: title, brand, category, description, bullet points, compliance certifications, return policy — 2KB per product, shared by potentially 50 variants. Storing these 2KB in each of 5M variant objects = 10GB in memory. Flyweight separates the **intrinsic state** (shared, immutable) from the **extrinsic state** (per-variant, mutable).

## Structure (Participants)

```
        FlyweightFactory (Registry)
  ┌──────────────────────────────────────┐
  │ - pool: Map<String, ProductMetadata> │
  │ + get(asin): ProductMetadata         │ ← returns shared instance
  └──────────────────────────────────────┘
                     │ manages
                     ▼
     «Flyweight (shared, immutable)»
           ProductMetadata
  ┌────────────────────────────────┐
  │ - asin: String                 │
  │ - title: String                │
  │ - brand: String                │
  │ - category: String             │
  │ - description: String (long)   │
  │ - bulletPoints: List<String>   │
  │ - returnPolicy: ReturnPolicy   │
  └────────────────────────────────┘
                 △ referenced by

   «Extrinsic state — not shared»
          ProductVariant
  ┌────────────────────────────────┐
  │ - sku: String                  │
  │ - color: String                │
  │ - size: String                 │
  │ - stockQuantity: int           │
  │ - price: Money                 │
  │ - metadata: ProductMetadata   ──┘ (shared reference)
  └────────────────────────────────┘
```

Key participants:
- **Flyweight** (`ProductMetadata`): immutable, shareable — the intrinsic state
- **Flyweight Factory** (`ProductMetadataRegistry`): creates and manages the pool; returns existing flyweights or creates new ones
- **Context** (`ProductVariant`): holds extrinsic (unique) state and a reference to the shared flyweight
- **Client**: obtains flyweights via the factory, never calls `new ProductMetadata()` directly

---

## Real-World Use Case: Product Variant Catalog

A fashion retailer has 200K products, each with 10–25 variants (size × color). That's 3–5M `ProductVariant` objects in the catalog service's in-memory index. Product metadata (title, description, category, brand, image schema) is 5KB per product, identical across all variants. Without Flyweight: 5M × 5KB = 25GB in heap. With Flyweight: 200K × 5KB (metadata pool) + 5M × 200B (variant extrinsic state) = ~1GB + 1GB = 2GB.

A second use: **character glyph rendering** — a rich text editor renders 100K characters; each glyph's font, size, and style data is shared via Flyweight, only position is per-character.

### Implementation

```java
// Flyweight — intrinsic state (immutable, thread-safe, shareable)
public final class ProductMetadata {
    private final String asin;           // Amazon Standard Item Number
    private final String title;
    private final String brand;
    private final String categoryPath;
    private final String longDescription;
    private final List<String> bulletPoints;
    private final ReturnPolicy returnPolicy;
    private final List<ComplianceCertification> certifications;
    private final Map<String, String> categoryAttributes;  // unmodifiable

    // Package-private constructor — only factory creates instances
    ProductMetadata(String asin, String title, String brand, /* ... */) {
        this.asin = asin;
        this.title = title;
        this.brand = brand;
        this.longDescription = longDescription;
        this.bulletPoints = List.copyOf(bulletPoints);          // immutable copy
        this.categoryAttributes = Map.copyOf(categoryAttributes); // immutable copy
        // ...
    }

    // Only getters — no setters (immutable)
    public String getAsin() { return asin; }
    public String getTitle() { return title; }
    // ...
}

// Flyweight Factory — manages the pool
public class ProductMetadataRegistry {
    private final Map<String, ProductMetadata> pool = new ConcurrentHashMap<>();
    private final ProductMetadataLoader loader;  // loads from DB/cache

    public ProductMetadataRegistry(ProductMetadataLoader loader) {
        this.loader = loader;
    }

    public ProductMetadata get(String asin) {
        return pool.computeIfAbsent(asin, this::loadFromSource);
    }

    private ProductMetadata loadFromSource(String asin) {
        return loader.load(asin);  // DB read — happens once per ASIN
    }

    public int poolSize() { return pool.size(); }
    public void invalidate(String asin) { pool.remove(asin); }  // for cache busting
}

// Context — extrinsic state (unique per variant)
public class ProductVariant {
    private final String sku;
    private final String color;
    private final String size;
    private volatile int stockQuantity;    // changes frequently
    private volatile Money price;          // changes with pricing engine
    private final ProductMetadata metadata; // shared reference — the flyweight

    public ProductVariant(String sku, String color, String size,
                          int stock, Money price, ProductMetadata metadata) {
        this.sku = sku;
        this.color = color;
        this.size = size;
        this.stockQuantity = stock;
        this.price = price;
        this.metadata = metadata;          // shared, not copied
    }

    // Extrinsic state accessed directly
    public String getSku()           { return sku; }
    public String getColor()         { return color; }
    public String getSize()          { return size; }
    public int getStockQuantity()    { return stockQuantity; }
    public Money getPrice()          { return price; }
    public void updateStock(int qty) { this.stockQuantity = qty; }
    public void updatePrice(Money p) { this.price = p; }

    // Intrinsic state accessed via flyweight
    public String getTitle()         { return metadata.getTitle(); }
    public String getBrand()         { return metadata.getBrand(); }
    public String getDescription()   { return metadata.getLongDescription(); }
    public String getCategoryPath()  { return metadata.getCategoryPath(); }
}

// Catalog service — assembles variants
public class ProductCatalogService {
    private final ProductMetadataRegistry metadataRegistry;
    private final VariantRepository variantRepo;

    public List<ProductVariant> getVariantsForProduct(String asin) {
        ProductMetadata metadata = metadataRegistry.get(asin); // from pool — shared

        return variantRepo.findByAsin(asin).stream()
            .map(variantRow -> new ProductVariant(
                variantRow.sku(),
                variantRow.color(),
                variantRow.size(),
                variantRow.stock(),
                variantRow.price(),
                metadata              // same metadata object for ALL variants of this ASIN
            ))
            .collect(toList());
    }
}

// Memory analysis
ProductMetadataRegistry registry = new ProductMetadataRegistry(loader);
// Load 200K products
// pool has 200K ProductMetadata objects (5KB each) = ~1GB
// Each of 5M variants holds one reference (8 bytes) to its metadata
// Extrinsic state per variant: sku + color + size + stock + price ≈ 200 bytes
// Total: 1GB (shared metadata) + 5M × 200B (variants) ≈ 2GB vs 25GB without Flyweight
```

### How It Works (walkthrough)

1. Request for ASIN `B08XYZ` (red/L, red/XL, blue/L, blue/XL, green/L — 5 variants)
2. `metadataRegistry.get("B08XYZ")` → first call: `computeIfAbsent` → DB read, create `ProductMetadata`, store in pool
3. Subsequent calls for same ASIN → pool hit → same `ProductMetadata` object returned
4. 5 `ProductVariant` objects created, each holding a reference to the *same* `ProductMetadata` object
5. Updating the description? Invalidate `"B08XYZ"` in registry → next request reloads → all variants see new description automatically via shared reference

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | `ProductMetadata` stores shared data; `ProductVariant` stores variant-specific state |
| Open/Closed | ✅ | Add new intrinsic fields to `ProductMetadata` without changing `ProductVariant` |
| Liskov Substitution | ✅ | N/A — no inheritance in this implementation |
| Interface Segregation | ✅ | `ProductMetadata` exposes only read methods (immutable) |
| Dependency Inversion | ⚠️ | `ProductVariant` directly references `ProductMetadata` class — could be an interface |

---

## When to Use

- Application uses a very large number of similar objects with significant shared state
- Memory profiling shows object heap is a bottleneck
- The shared (intrinsic) state can be clearly separated from the unique (extrinsic) state
- Intrinsic state is immutable (critical — shared objects must be thread-safe)

## When NOT to Use

- Object count is small — premature optimization
- Objects don't have meaningful shared state — Flyweight adds complexity without memory benefit
- Intrinsic and extrinsic states are hard to separate — the design becomes confusing
- Object creation cost is negligible — no need to reuse

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Dramatic memory reduction — 200K objects instead of 5M for metadata | Runtime trade-off: computing context (extrinsic state) instead of storing it |
| Shared objects are naturally thread-safe (immutable) | Adds complexity — intrinsic/extrinsic split is not always obvious |
| Cache invalidation is centralized in the registry | Shared objects mean all users see updates simultaneously — can cause subtle bugs |

---

**FAANG interview application**: "Flyweight is about separating intrinsic (shared, immutable) from extrinsic (unique, mutable) state. For a product catalog with 5M variant objects, the product metadata — title, description, category, return policy — is intrinsic: it's the same across all variants of an ASIN. The variant-specific fields — SKU, color, size, stock, price — are extrinsic. Storing metadata in a `ConcurrentHashMap` keyed by ASIN and pointing each variant to a shared reference reduces memory from 25GB to 2GB. This is the same principle used by the JVM's String interning pool."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Singleton](../creational/01-singleton.md) | Flyweight factory is often a Singleton; each unique flyweight is also effectively a singleton for its key |
| [Composite](08-composite.md) | Flyweights can be leaves in a Composite tree |
| [Factory Method](../creational/02-factory-method.md) | Flyweight factory uses factory-like creation logic (check pool → create if absent) |
