# 15. Iterator
**Category**: Behavioral  
**GoF**: Yes  
**Complexity**: Low  
**Frequency in FAANG interviews**: Occasional

> Provide a way to access the elements of an aggregate object sequentially without exposing its underlying representation.

---

## Problem It Solves

A product search API returns results in pages of 20 (cursor-based pagination). The client code needs to iterate over all matching products without knowing about API pages, cursors, or rate limits. Without Iterator, the client handles `hasMorePages()`, `nextCursor`, and retry logic everywhere it needs to iterate. With Iterator, `ProductCatalogIterator` abstracts the pagination — client calls `hasNext()`/`next()` and gets individual products regardless of how many API calls were made.

## Structure (Participants)

```
    «interface»              «interface»
    Iterator<T>          IterableCollection<T>
┌────────────────┐       ┌────────────────────┐
│ + hasNext()    │       │ + createIterator()  │
│ + next(): T    │       └────────────────────┘
│ + peek(): T    │                 △
└────────────────┘                 │
        △              ProductCatalogCollection
        │              ┌───────────────────────┐
ProductCatalogIterator │ + createIterator()    │
                       └───────────────────────┘
```

Key participants:
- **Iterator** (`ProductCatalogIterator`): manages traversal state (current page, cursor, buffered items)
- **Iterable Collection** (`ProductCatalog`): creates and returns an iterator
- **Client**: calls `hasNext()`/`next()` — never imports the API client or sees cursors

---

## Real-World Use Case: Cursor-Based Paginated Product Catalog

A recommendation engine needs to score all 2M products in the catalog. The catalog service returns at most 100 products per API call. The scoring engine just needs to iterate product-by-product. The iterator fetches pages lazily — it doesn't preload all 2M products into memory.

### Implementation

```java
// Generic iterator interface
public interface CatalogIterator<T> {
    boolean hasNext();
    T next();
    int totalFetched();
}

// DTO from API
public record ProductPage(List<Product> products, String nextCursor, int totalCount) {
    boolean hasMore() { return nextCursor != null && !nextCursor.isEmpty(); }
}

// Concrete iterator — manages pagination transparently
public class ProductCatalogIterator implements CatalogIterator<Product> {
    private final ProductSearchClient client;
    private final ProductSearchQuery query;
    private final int pageSize;

    private Queue<Product> buffer = new ArrayDeque<>();
    private String cursor = null;
    private boolean exhausted = false;
    private int totalFetched = 0;

    public ProductCatalogIterator(ProductSearchClient client, ProductSearchQuery query, int pageSize) {
        this.client = client;
        this.query = query;
        this.pageSize = pageSize;
    }

    @Override
    public boolean hasNext() {
        if (!buffer.isEmpty()) return true;
        if (exhausted) return false;
        fetchNextPage();
        return !buffer.isEmpty();
    }

    @Override
    public Product next() {
        if (!hasNext()) throw new NoSuchElementException("No more products");
        return buffer.poll();
    }

    private void fetchNextPage() {
        try {
            ProductPage page = client.search(query, cursor, pageSize);
            buffer.addAll(page.products());
            totalFetched += page.products().size();
            cursor = page.nextCursor();
            if (!page.hasMore() && page.products().isEmpty()) {
                exhausted = true;
            } else if (!page.hasMore()) {
                exhausted = true;  // last page fetched
            }
        } catch (RateLimitException e) {
            // Retry after backoff
            sleep(e.retryAfterMs());
            fetchNextPage();
        }
    }

    @Override public int totalFetched() { return totalFetched; }
}

// Category-filtered iterator — wraps base iterator with a filter
public class FilteredProductIterator implements CatalogIterator<Product> {
    private final CatalogIterator<Product> source;
    private final Predicate<Product> filter;
    private Product peeked;

    public FilteredProductIterator(CatalogIterator<Product> source, Predicate<Product> filter) {
        this.source = source;
        this.filter = filter;
    }

    @Override
    public boolean hasNext() {
        while (peeked == null && source.hasNext()) {
            Product candidate = source.next();
            if (filter.test(candidate)) {
                peeked = candidate;
            }
        }
        return peeked != null;
    }

    @Override
    public Product next() {
        if (!hasNext()) throw new NoSuchElementException();
        Product result = peeked;
        peeked = null;
        return result;
    }

    @Override public int totalFetched() { return source.totalFetched(); }
}

// Client — recommendation engine
public class RecommendationScorer {
    private final ProductCatalogClient catalogClient;
    private final ScoringModel model;

    public void scoreAllProducts(ProductSearchQuery query) {
        CatalogIterator<Product> iterator = new ProductCatalogIterator(catalogClient, query, 100);

        // Client is completely unaware of pages or cursors
        while (iterator.hasNext()) {
            Product product = iterator.next();
            double score = model.score(product);
            scoreRepository.save(product.id(), score);
        }

        log.info("Scored {} products", iterator.totalFetched());
    }

    public void scoreInStockElectronics() {
        CatalogIterator<Product> base = new ProductCatalogIterator(catalogClient, allElectronicsQuery, 100);
        CatalogIterator<Product> inStock = new FilteredProductIterator(base, Product::isInStock);

        while (inStock.hasNext()) {
            Product p = inStock.next();
            model.score(p);
        }
    }
}
```

### How It Works (walkthrough)

1. `scorer.scoreAllProducts(query)` — creates iterator, calls `hasNext()`
2. Buffer is empty → `fetchNextPage()` → API call with `cursor=null` → first 100 products buffered
3. Client calls `next()` 100 times → buffer drains
4. Client calls `hasNext()` again → buffer empty, not exhausted → `fetchNextPage()` → next 100 buffered
5. Repeat until API returns no `nextCursor` → `exhausted = true` → `hasNext()` returns `false`
6. Client never saw a cursor, a page, or an API call — just a stream of `Product` objects

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | Iterator handles traversal; client handles business logic |
| Open/Closed | ✅ | Add `SortedProductIterator` or `CachedIterator` without changing client |
| Liskov Substitution | ✅ | `FilteredProductIterator` is substitutable for `CatalogIterator<Product>` |
| Interface Segregation | ✅ | `hasNext()`, `next()` — minimal interface |
| Dependency Inversion | ✅ | Client depends on `CatalogIterator` interface |

---

## When to Use

- Collection has a complex underlying structure (paginated API, B-Tree, graph) client shouldn't know about
- You want multiple traversal algorithms (sorted, filtered, random) over the same collection
- Collection is too large to load into memory — lazy fetching per `next()` call

## When NOT to Use

- The collection is a simple in-memory list — use Java's built-in `Iterator` or streams
- Traversal is always full-scan — a simple `forEach()` is cleaner

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Client code decoupled from pagination/structure | Iterator must be thread-safe if used concurrently |
| Lazy loading — don't fetch page 50 until page 49 is consumed | Stateful — iterator is not reusable without resetting |
| Multiple iterator types over same collection | Error handling (network failures mid-iteration) is complex |

---

**FAANG interview application**: "Iterator is the pattern for abstracting cursor-based pagination behind `hasNext()`/`next()`. The caller — a batch job, a reporting query, a recommendation scorer — shouldn't know that results come in 100-item pages from an API. The iterator handles the cursor, the retry on rate limit, and the lazy fetching. This is the pattern behind Java's `Stream.iterator()`, Spark's `Partition`, and DynamoDB's `ScanResult.getLastEvaluatedKey()` pattern."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Composite](../structural/08-composite.md) | Iterator can traverse Composite trees; the iterator hides whether it's visiting leaves or composites |
| [Visitor](22-visitor.md) | Visitor + Iterator together: iterator traverses, visitor operates on each element |
