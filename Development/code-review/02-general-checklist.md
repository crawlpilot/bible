# General Code Review Checklist

> Language-agnostic. Apply to every PR regardless of stack. Language-specific items are in separate checklists.

---

## 1. Correctness

```
☐ Does the code do what the PR description says?
☐ Are all edge cases handled? (null, empty, zero, max value, concurrent access)
☐ Are there off-by-one errors in loops or index access?
☐ Are comparisons correct? (== vs equals, floating-point comparison)
☐ Is mutable shared state accessed safely?
☐ Are there any race conditions or TOCTOU (time-of-check-time-of-use) issues?
☐ Are external inputs validated before use?
☐ Are return values checked? (ignoring an error return is a common bug)
```

### Common Correctness Anti-Patterns

```java
// [BLOCK] Return value ignored — method signals failure, caller ignores it
file.delete();           // returns false on failure; no check
list.remove(item);       // returns false if not found; no check

// CORRECT:
if (!file.delete()) {
    log.warn("Failed to delete temp file", kv("path", file.getPath()));
}

// [BLOCK] Null check after use
String name = user.getName().trim();   // NPE if getName() returns null
// CORRECT:
String name = user.getName() != null ? user.getName().trim() : "";

// [BLOCK] Mutation of a parameter — caller's collection modified unexpectedly
public List<Order> filterActive(List<Order> orders) {
    orders.removeIf(o -> !o.isActive());  // mutates caller's list
    return orders;
}
// CORRECT: return new list; never mutate input parameters

// [BLOCK] Integer overflow
int total = price * quantity;  // overflows if values are large
long total = (long) price * quantity;  // correct

// [WARN] Floating-point equality
if (price == 0.0) { ... }     // unreliable due to float precision
if (Math.abs(price) < 1e-9) { ... }  // correct
// Or better: use BigDecimal for money
```

---

## 2. Error Handling

```
☐ Are exceptions caught at the right layer? (not swallowed deep in business logic)
☐ Are catch blocks logging the exception object, not just the message?
☐ Are checked exceptions propagated or converted correctly?
☐ Are error responses meaningful? (not leaking stack traces to clients)
☐ Are resources closed in finally blocks or try-with-resources?
☐ Is the error handling proportionate? (don't wrap every line in try/catch)
```

### Error Handling Anti-Patterns

```java
// [BLOCK] Empty catch — silently swallows failure
try {
    processOrder(order);
} catch (Exception e) {
    // nothing — failure is invisible
}

// [BLOCK] Logging message only — stack trace lost
} catch (Exception e) {
    log.error("Order processing failed: " + e.getMessage());  // no stack trace
}
// CORRECT:
} catch (Exception e) {
    log.error("order.processing.failed", kv("order_id", orderId), e);  // pass exception object
}

// [BLOCK] Catching Exception to avoid declaring throws
try {
    riskyOperation();
} catch (Exception e) {   // too broad — catches NPE, OOM, everything
    return fallback;
}
// CORRECT: catch only the exception types you can handle

// [WARN] Catch-and-rethrow without adding context
} catch (DatabaseException e) {
    throw e;   // pointless; either handle it or don't catch it
}
// CORRECT:
} catch (DatabaseException e) {
    throw new OrderPersistenceException("Failed to persist order " + orderId, e);
}

// [BLOCK] Resource leak — no try-with-resources
Connection conn = dataSource.getConnection();
Statement stmt = conn.createStatement();
ResultSet rs = stmt.executeQuery(sql);
// process rs...
// MISSING: finally block to close rs, stmt, conn
// CORRECT: use try-with-resources
try (Connection conn = dataSource.getConnection();
     Statement stmt = conn.createStatement();
     ResultSet rs = stmt.executeQuery(sql)) {
    // process rs — auto-closed on exit
}
```

---

## 3. Tests

```
☐ New behaviour has tests
☐ Changed behaviour has updated tests
☐ Deleted behaviour has deleted tests (no dead test code)
☐ Tests test BEHAVIOUR, not implementation details
☐ Test names describe what is being tested (not "test1", "testMethod")
☐ No assertions on mock invocations as the primary test (mock-centric tests)
☐ No use of Thread.sleep() in tests (use awaitility or explicit signals)
☐ No magic numbers in test data without explanation
☐ Edge cases tested: null input, empty collection, max value, concurrent access
```

### Test Anti-Patterns

```java
// [BLOCK] No assertion — test always passes
@Test
public void testProcessOrder() {
    orderService.process(order);
    // no assertion — this test proves nothing
}

// [BLOCK] Asserting on mocks instead of behaviour
@Test
public void testSubmitOrder() {
    orderService.submit(order);
    verify(emailService, times(1)).sendConfirmation(order);  // tests implementation, not outcome
    // Better: assert the order is in CONFIRMED state; assert the confirmation email was sent
}

// [WARN] Magic numbers in test data
Order order = new Order("cust_123", 42, 19.99);
// What does 42 mean? What does 19.99 represent?
// CORRECT:
int quantity = 42;
BigDecimal unitPrice = new BigDecimal("19.99");
Order order = new Order("cust_123", quantity, unitPrice);

// [WARN] Thread.sleep for async operations
orderService.submitAsync(order);
Thread.sleep(1000);   // flaky — sometimes too fast, sometimes too slow
assertThat(order.getStatus()).isEqualTo(CONFIRMED);
// CORRECT: use Awaitility
await().atMost(5, SECONDS).until(() -> order.getStatus() == CONFIRMED);

// [BLOCK] Test that passes by coincidence
@Test
public void testSort() {
    List<Integer> input = List.of(3, 1, 2);
    sorter.sort(input);
    assertThat(input.get(0)).isEqualTo(1);  // only checks first element
    // What if sort is wrong but first element happens to be correct?
    assertThat(input).containsExactly(1, 2, 3);  // correct
}
```

---

## 4. Naming

```
☐ Names are self-explanatory without requiring a comment
☐ Abbreviations are only used for universally understood terms (id, url, dto, etc.)
☐ Boolean names read as questions: isActive, hasPermission, shouldRetry
☐ Method names are verb phrases: getOrder, submitOrder, calculateTotal
☐ Collection names are plural: orders, customers, lineItems
☐ Constants are SCREAMING_SNAKE_CASE (Java/Kotlin) or UPPER_CASE (Python)
☐ Temporary variables have meaningful names (not i, j, k unless in tight loops)
☐ No misleading names (list that's actually a map, manager that does nothing)
```

### Naming Anti-Patterns

```java
// [NIT] Single-letter variable with non-obvious meaning
int x = order.getLines().size();
// CORRECT:
int lineCount = order.getLines().size();

// [WARN] Hungarian notation or type suffixes
String nameStr;
List<Order> orderList;
Map<String, Order> orderMap;
// CORRECT: name for intent, not type
String customerName;
List<Order> pendingOrders;
Map<String, Order> ordersById;

// [WARN] Misleading boolean name
boolean status = order.isValid();  // status is ambiguous — status of what?
boolean isOrderValid = order.isValid();

// [WARN] Inconsistent naming for the same concept
// In one class: customerId, in another: customer_id, in another: cust_id
// Pick one and be consistent across the codebase — use a team glossary
```

---

## 5. Comments and Documentation

```
☐ Comments explain WHY, not WHAT (the code explains what)
☐ No commented-out code in the diff
☐ No TODO comments without a linked ticket/issue
☐ Public API methods have accurate Javadoc/docstring (not copy-pasted boilerplate)
☐ Complex algorithms or non-obvious decisions have an explanatory comment
☐ Comments are in English (if that's the team language) and grammatically correct
```

### Comment Anti-Patterns

```java
// [NIT] Comment that restates the code
// Increment the counter
counter++;

// [WARN] Commented-out code — use version control
// order.setStatus(LEGACY_SUBMITTED);
order.setStatus(SUBMITTED);

// [WARN] TODO without a ticket
// TODO: fix this properly later
if (order.getTotal() > 0) { ... }
// CORRECT: // TODO: handle zero-total orders (see JIRA-4521)

// [BLOCK] Outdated comment contradicting the code
// Returns the order if found, null otherwise
public Optional<Order> findOrder(String id) { ... }
// The code returns Optional but the comment says "null" — which is correct?
```

---

## 6. Design and Structure

```
☐ Is the change the simplest solution that meets the requirements?
☐ Does it introduce unnecessary abstraction (interfaces with one implementation, etc.)?
☐ Does it violate single responsibility? (class/method doing too many things)
☐ Does it create tight coupling? (concrete dependency instead of interface)
☐ Are new public APIs stable? (will this need to change again soon?)
☐ Does it duplicate logic that already exists in the codebase?
☐ Are new classes/modules placed in the correct layer (domain, service, infra)?
☐ Does it respect the existing architectural boundaries?
```

### Design Anti-Patterns

```java
// [WARN] Primitive obsession — pass a typed object, not raw primitives
public void createOrder(String customerId, String productId, int quantity, String currency, double amount) { ... }
// CORRECT:
public void createOrder(CustomerId customerId, OrderLine line, Money total) { ... }

// [WARN] Feature envy — method uses another class's data more than its own
public class OrderService {
    public BigDecimal calculateTax(Order order) {
        // Uses Order's internals directly — this belongs in Order or a TaxCalculator
        return order.getLines().stream()
            .mapToDouble(l -> l.getProduct().getPrice() * l.getQuantity() * order.getCustomer().getTaxRate())
            .sum();
    }
}

// [BLOCK] God method — one method doing everything
public OrderResult processOrder(Order order) {
    // validate order
    // check inventory
    // reserve inventory
    // calculate pricing
    // apply discounts
    // process payment
    // send confirmation email
    // update analytics
    // audit log
    // ...200 lines
}
// CORRECT: decompose into single-responsibility methods/services

// [WARN] Premature abstraction — interface before there's a second implementation
public interface OrderSubmitter { void submit(Order order); }
public class DefaultOrderSubmitter implements OrderSubmitter { ... }
// If there's only ever one implementation, the interface adds noise
// Create the interface when the second implementation appears
```

---

## 7. Performance

```
☐ Are database queries in loops? (N+1 problem)
☐ Are collections unnecessarily copied or traversed multiple times?
☐ Is there unbounded collection growth? (list grows without limit)
☐ Are large objects kept in memory longer than needed?
☐ Is there unnecessary synchronisation (lock on hot path)?
☐ Are there large payload responses where pagination would be appropriate?
☐ Are string concatenations in loops using StringBuilder?
☐ Are new threads created without a pool?
```

### Performance Anti-Patterns

```java
// [BLOCK] N+1 query in a loop
List<Order> orders = orderRepository.findAll();
for (Order order : orders) {
    // Fires one SQL query per order
    Customer customer = customerRepository.findById(order.getCustomerId());
    ...
}
// CORRECT: join or batch-fetch in a single query

// [WARN] Unbounded result set
List<Order> allOrders = orderRepository.findAll();  // returns all rows, no limit
// CORRECT: always paginate: findAll(Pageable pageable)

// [WARN] String concat in loop
String result = "";
for (String item : items) {
    result += item + ",";  // O(n²) due to string immutability
}
// CORRECT:
StringBuilder sb = new StringBuilder();
for (String item : items) sb.append(item).append(',');

// [WARN] Creating threads without a pool
for (Order order : orders) {
    new Thread(() -> processOrder(order)).start();  // unbounded thread creation
}
// CORRECT: use ExecutorService with a bounded thread pool

// [WARN] Re-computing inside a loop
for (Order order : orders) {
    double taxRate = configService.getTaxRate();  // DB call per iteration
    applyTax(order, taxRate);
}
// CORRECT: fetch taxRate once before the loop
```

---

## 8. Dependencies

```
☐ Is each new external dependency justified? (don't add a library for one utility method)
☐ Is the dependency licence compatible with the project? (GPL in an MIT project = BLOCK)
☐ Is the dependency actively maintained? (last commit > 1 year ago = question)
☐ Is the version pinned? (no open range like >=1.0.0 in production)
☐ Are transitive dependency conflicts introduced?
☐ Is a well-known library added when a simpler standard library solution exists?
```

---

## 9. Configuration and Feature Flags

```
☐ Is new configuration documented (name, type, default, effect)?
☐ Are risky changes behind a feature flag for staged rollout?
☐ Is the default value safe if the config is missing?
☐ Are secrets loaded from a secret store, not from config files?
☐ Is the configuration validated on startup, not lazily at runtime?
```

---

## 10. Database and Migrations

```
☐ Is the migration additive? (add column, add table — never drop, rename without transition period)
☐ Does the migration have a rollback plan?
☐ Does adding a NOT NULL column provide a DEFAULT value for existing rows?
☐ Are new indexes created CONCURRENTLY (PostgreSQL) to avoid locking?
☐ Are large table migrations batched to avoid lock timeouts?
☐ Is the migration tested against production-scale data in staging?
```

### Migration Anti-Patterns

```sql
-- [BLOCK] Drop column without deprecation period
ALTER TABLE orders DROP COLUMN legacy_status;
-- App code may still reference this column; coordinate removal separately

-- [BLOCK] NOT NULL column with no default — fails on existing rows
ALTER TABLE orders ADD COLUMN approved_at TIMESTAMP NOT NULL;
-- CORRECT:
ALTER TABLE orders ADD COLUMN approved_at TIMESTAMP;  -- nullable first
-- After app is deployed and backfill complete:
ALTER TABLE orders ALTER COLUMN approved_at SET NOT NULL;

-- [BLOCK] Non-concurrent index on large table (locks writes during creation)
CREATE INDEX idx_orders_customer_id ON orders(customer_id);
-- CORRECT (PostgreSQL):
CREATE INDEX CONCURRENTLY idx_orders_customer_id ON orders(customer_id);
```
