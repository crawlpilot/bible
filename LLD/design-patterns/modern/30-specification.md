# 30. Specification
**Category**: Modern / Enterprise  
**GoF**: No (Evans & Fowler, DDD)  
**Complexity**: Medium  
**Frequency in FAANG interviews**: Occasional

> Encapsulate business rules as objects that can be combined using boolean logic, allowing complex queries and validation rules to be built from simple, composable predicates.

---

## Problem It Solves

A product search has 10 filter dimensions: category, price range, brand, in-stock, rating, shipping speed, seller tier, discount level, new arrivals, Prime-eligible. Building all combinations in SQL (12 query methods) or if-else blocks makes the code unmaintainable — adding "has video" filter requires modifying every query. Specification turns each filter into a composable object: `CategorySpec.and(PriceRangeSpec).and(InStockSpec).and(RatingSpec)`.

## Structure (Participants)

```
        «interface»
    ProductSpecification
┌─────────────────────────────┐
│ + isSatisfiedBy(p): bool    │
│ + and(other): Spec          │
│ + or(other): Spec           │
│ + not(): Spec               │
│ + toSqlPredicate(): Pred    │
└─────────────────────────────┘
              △
  ┌───────────┼───────────────────────────────────┐
  │           │              │                    │
CategorySpec PriceRangeSpec InStockSpec      CompositeSpec
                                             (AND/OR/NOT)
```

---

## Real-World Use Case: Product Search Filters

An e-commerce search page has 10 filters. Each filter is a `ProductSpecification`. The search service composes them dynamically from query parameters — no query builder branches, no if-else for every combination. New filters are new spec classes.

### Implementation

```java
// Specification interface
public interface ProductSpecification {
    boolean isSatisfiedBy(Product product);  // in-memory filtering
    Predicate<Product> toPredicate();        // for Java Stream filtering
    ProductSpecification and(ProductSpecification other);
    ProductSpecification or(ProductSpecification other);
    ProductSpecification not();
}

// Abstract base with default boolean combinators
public abstract class AbstractProductSpecification implements ProductSpecification {
    @Override public Predicate<Product> toPredicate() { return this::isSatisfiedBy; }

    @Override
    public ProductSpecification and(ProductSpecification other) {
        return new AndSpecification(this, other);
    }

    @Override
    public ProductSpecification or(ProductSpecification other) {
        return new OrSpecification(this, other);
    }

    @Override
    public ProductSpecification not() {
        return new NotSpecification(this);
    }
}

// Composite specifications (boolean logic)
public class AndSpecification extends AbstractProductSpecification {
    private final ProductSpecification left, right;

    public AndSpecification(ProductSpecification left, ProductSpecification right) {
        this.left = left; this.right = right;
    }

    @Override
    public boolean isSatisfiedBy(Product p) {
        return left.isSatisfiedBy(p) && right.isSatisfiedBy(p);
    }
}

public class OrSpecification extends AbstractProductSpecification {
    private final ProductSpecification left, right;

    @Override
    public boolean isSatisfiedBy(Product p) {
        return left.isSatisfiedBy(p) || right.isSatisfiedBy(p);
    }
}

public class NotSpecification extends AbstractProductSpecification {
    private final ProductSpecification inner;

    @Override
    public boolean isSatisfiedBy(Product p) {
        return !inner.isSatisfiedBy(p);
    }
}

// Concrete specifications — one per filter dimension
public class CategorySpecification extends AbstractProductSpecification {
    private final String categoryPath;
    private final boolean includeSubcategories;

    @Override
    public boolean isSatisfiedBy(Product p) {
        if (includeSubcategories) {
            return p.categoryPath().startsWith(categoryPath);
        }
        return p.categoryPath().equals(categoryPath);
    }
}

public class PriceRangeSpecification extends AbstractProductSpecification {
    private final Money minPrice;
    private final Money maxPrice;

    @Override
    public boolean isSatisfiedBy(Product p) {
        return p.price().isGreaterThanOrEqualTo(minPrice)
            && p.price().isLessThanOrEqualTo(maxPrice);
    }
}

public class InStockSpecification extends AbstractProductSpecification {
    @Override
    public boolean isSatisfiedBy(Product p) { return p.stockQuantity() > 0; }
}

public class MinRatingSpecification extends AbstractProductSpecification {
    private final double minRating;

    @Override
    public boolean isSatisfiedBy(Product p) { return p.averageRating() >= minRating; }
}

public class PrimeEligibleSpecification extends AbstractProductSpecification {
    @Override
    public boolean isSatisfiedBy(Product p) { return p.isPrimeEligible(); }
}

public class BrandSpecification extends AbstractProductSpecification {
    private final Set<String> brands;

    @Override
    public boolean isSatisfiedBy(Product p) { return brands.contains(p.brand()); }
}

public class NewArrivalSpecification extends AbstractProductSpecification {
    private final Duration window;

    @Override
    public boolean isSatisfiedBy(Product p) {
        return p.listedAt().isAfter(Instant.now().minus(window));
    }
}

// Spec builder — assembles from query parameters
public class ProductSpecificationBuilder {
    private final List<ProductSpecification> specs = new ArrayList<>();

    public ProductSpecificationBuilder category(String path) {
        if (path != null) specs.add(new CategorySpecification(path, true));
        return this;
    }

    public ProductSpecificationBuilder priceRange(Money min, Money max) {
        if (min != null || max != null) {
            specs.add(new PriceRangeSpecification(
                min != null ? min : Money.ZERO,
                max != null ? max : Money.of(Long.MAX_VALUE)
            ));
        }
        return this;
    }

    public ProductSpecificationBuilder inStockOnly(boolean inStock) {
        if (inStock) specs.add(new InStockSpecification());
        return this;
    }

    public ProductSpecificationBuilder minRating(Double rating) {
        if (rating != null) specs.add(new MinRatingSpecification(rating));
        return this;
    }

    public ProductSpecificationBuilder brands(List<String> brands) {
        if (brands != null && !brands.isEmpty()) specs.add(new BrandSpecification(Set.copyOf(brands)));
        return this;
    }

    public ProductSpecificationBuilder primeOnly(boolean prime) {
        if (prime) specs.add(new PrimeEligibleSpecification());
        return this;
    }

    public ProductSpecificationBuilder newArrivals(boolean newOnly) {
        if (newOnly) specs.add(new NewArrivalSpecification(Duration.ofDays(30)));
        return this;
    }

    public ProductSpecification build() {
        if (specs.isEmpty()) return new AllProductsSpecification();  // no filter = match all
        return specs.stream().reduce(ProductSpecification::and)
            .orElse(new AllProductsSpecification());
    }
}

// Product search service
public class ProductSearchService {
    private final ProductRepository productRepository;

    public List<Product> search(ProductSearchQuery query) {
        ProductSpecification spec = new ProductSpecificationBuilder()
            .category(query.getCategoryPath())
            .priceRange(query.getMinPrice(), query.getMaxPrice())
            .inStockOnly(query.isInStockOnly())
            .minRating(query.getMinRating())
            .brands(query.getBrands())
            .primeOnly(query.isPrimeOnly())
            .newArrivals(query.isNewArrivalsOnly())
            .build();

        // In-memory filtering (catalog loaded in memory for small catalogs)
        return productRepository.findAll().stream()
            .filter(spec::isSatisfiedBy)
            .sorted(query.getSortComparator())
            .skip((long) query.getPage() * query.getPageSize())
            .limit(query.getPageSize())
            .collect(toList());
    }
}

// Usage
ProductSpecification electronicsUnder500InStock =
    new CategorySpecification("electronics", true)
        .and(new PriceRangeSpecification(Money.ZERO, Money.of(500)))
        .and(new InStockSpecification())
        .and(new MinRatingSpecification(4.0));

// Validate a single product
boolean eligible = electronicsUnder500InStock.isSatisfiedBy(product);

// Filter a list
List<Product> results = catalog.stream()
    .filter(electronicsUnder500InStock::isSatisfiedBy)
    .collect(toList());
```

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | Each spec checks one criterion; composite specs combine them |
| Open/Closed | ✅ | Add `HasVideoSpecification` — new class; existing specs unchanged |
| Liskov Substitution | ✅ | All specifications substitutable through `ProductSpecification` |
| Interface Segregation | ✅ | Focused interface: `isSatisfiedBy()`, `and()`, `or()`, `not()` |
| Dependency Inversion | ✅ | Search service depends on `ProductSpecification` interface |

---

## When to Use

- Complex business rules must be combined in various ways
- Rules are specified at runtime (from user query, config, or UI selections)
- Rules must be independently unit-testable
- Validation rules and query rules share the same predicates

## When NOT to Use

- Specifications must translate to SQL — this requires a JPA Criteria API integration (more complex)
- Only 2–3 filters exist and they never change — a simple method is cleaner
- Performance is critical — composing many specs adds method call overhead vs. SQL WHERE clause

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Composable — any combination of N filters in one line | In-memory filtering doesn't scale to millions of products — needs SQL/ES translation |
| Each spec independently unit-testable | Translating to SQL (JPA Criteria, QueryDSL) doubles the implementation effort |
| Adding new filters = adding one class | Complex nested AND/OR/NOT trees can be hard to debug |

---

**FAANG interview application**: "Specification is the right pattern for multi-dimensional product filtering where filters are combinable and configurable at runtime. Each filter is a spec class: `CategorySpec.and(PriceRangeSpec).and(InStockSpec)`. The builder assembles the spec from query params — zero if-else for filter combinations. The trade-off is in-memory filtering doesn't scale to millions of products. For large catalogs, the spec must translate to SQL (JPA Criteria API) or an Elasticsearch query DSL — the spec object generates the query instead of evaluating it."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Composite](../structural/08-composite.md) | AND/OR/NOT specifications are Composite patterns |
| [Strategy](../behavioral/20-strategy.md) | Specification is a specialized Strategy for boolean predicates |
| [Repository](24-repository.md) | Repository accepts Specification objects to avoid query method explosion |
