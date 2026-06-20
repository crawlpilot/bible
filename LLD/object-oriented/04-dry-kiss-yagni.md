# DRY, KISS, and YAGNI

These are practical design heuristics, not rigid laws. They help you avoid unnecessary complexity while still building maintainable systems.

## DRY: Don’t Repeat Yourself

DRY means avoid duplication of knowledge, not just duplication of text.

### Good use

- A single pricing rule used by multiple checkout flows
- A shared validation rule used by both API and UI layers

### Bad use

- Creating a large abstraction just because two pieces of code look similar today

Sometimes repeated code is cheaper than a bad abstraction.

## KISS: Keep It Simple, Stupid

KISS means prefer the simplest solution that solves the problem correctly.

### What simple means

- Easy to understand
- Easy to test
- Easy to change

Simple does not mean naive. A simple design can still be robust.

## YAGNI: You Aren’t Gonna Need It

YAGNI reminds you not to build for speculative requirements.

### Good application

- Do not add plugin architecture until there are multiple real plugins
- Do not build generic workflow configuration if one workflow is all you need

### Why it matters

Premature generalization makes systems harder to understand and slower to ship.

## How the Three Work Together

| Heuristic | Main risk it prevents |
|-----------|------------------------|
| DRY | Repeated business logic drifting apart |
| KISS | Unnecessary complexity |
| YAGNI | Over-engineering for future uncertainty |

## The Main Trade-Off

Applying these heuristics too aggressively can also hurt design:

- DRY can create brittle abstractions
- KISS can become oversimplification
- YAGNI can prevent useful preparation for known requirements

---

## DRY: Deeper Detail

> "Every piece of knowledge must have a single, unambiguous, authoritative representation within a system."
> — *The Pragmatic Programmer*, Andy Hunt & Dave Thomas

DRY is about **knowledge** duplication, not **text** duplication. Two code blocks that look similar are not automatically a DRY violation. Two pieces of code that encode the *same business rule* in two separate places always are.

### Correct application of DRY

```java
// Violation: discount rule encoded in two places — they will diverge
class CartService {
    public Money applyMemberDiscount(Money price) {
        return price.multiply(0.90);  // 10% off for members
    }
}

class OrderService {
    public Money applyMemberDiscount(Money price) {
        return price.multiply(0.90);  // copied — will they stay in sync?
    }
}

// DRY: one authoritative source for the discount rule
class MemberPricingPolicy {
    private static final BigDecimal MEMBER_DISCOUNT = new BigDecimal("0.90");
    public Money apply(Money price) { return price.multiply(MEMBER_DISCOUNT); }
}
```

### When NOT to apply DRY — the Wrong Abstraction

Two code blocks that look similar may represent independent concepts that happen to look alike today. Extracting them creates **accidental coupling**.

> "Duplication is far cheaper than the wrong abstraction."
> — Sandi Metz

**Rule of thumb**: wait for the **third occurrence** before extracting a shared abstraction. By the third case, you have enough evidence to understand the real generalization.

```java
// These two validations look similar but represent independent business rules
// for different contexts — do not DRY them into one method
class UserRegistrationValidator {
    public boolean isValidEmail(String email) {
        return email.matches("^[^@]+@[^@]+\\.[^@]+$");
    }
}

class NewsletterSubscriptionValidator {
    public boolean isValidEmail(String email) {
        return email.matches("^[^@]+@[^@]+\\.[^@]+$");
    }
}
// If the newsletter team later needs stricter validation, having them separate
// means they can evolve independently without breaking the other.
```

---

## KISS: Deeper Detail

> "Simplicity is prerequisite for reliability."
> — Edsger W. Dijkstra

### What simple means in practice

| Dimension | Simple | Complex |
|-----------|--------|---------|
| **Reading** | Understandable without the author present | Requires explanation |
| **Testing** | One scenario = one test | Setup requires many stubs |
| **Debugging** | Failure is obvious from the stack trace | Requires tracing through many layers |
| **Changing** | Change one thing in one place | Change ripples to many files |

### Over-engineering example

```java
// KISS violation — solving a simple cache problem with excessive abstraction
public class CachedUserRetriever<T extends Identifiable<K>, K extends Serializable>
    implements AsyncRetrieverWithFallback<T, K> {
    private final GenericRepositoryStrategy<T, K> repositoryStrategy;
    private final CacheEvictionPolicy<K> evictionPolicy;
    private final FallbackChain<T, K> fallbackChain;
}

// KISS compliant — the simple version covering 95% of real needs
public class CachedUserService {
    private final UserRepository repository;
    private final Cache<UserId, User> cache;

    public Optional<User> findUser(UserId id) {
        return cache.get(id).or(() -> {
            Optional<User> user = repository.findById(id);
            user.ifPresent(u -> cache.put(id, u));
            return user;
        });
    }
}
```

### Cyclomatic complexity as a KISS metric

Cyclomatic complexity counts the number of independent paths through a method (roughly: `if` + `for` + `while` + `case` branches + 1). A method with complexity > 10 is a KISS violation.

| Cyclomatic Complexity | Risk Level |
|-----------------------|-----------|
| 1–5 | Simple, low risk |
| 6–10 | Moderate — acceptable with good tests |
| 11–20 | High — refactor candidate |
| > 20 | Untestable — must split |

```java
// Complex — cyclomatic complexity ≈ 8, hard to read
public boolean canProcessOrder(Order order, User user) {
    return order != null && !order.getLines().isEmpty() &&
           order.getStatus() == OrderStatus.DRAFT &&
           user != null && user.isActive() && !user.isBlocked() &&
           (user.hasRole(Role.ADMIN) || order.isOwnedBy(user));
}

// KISS — each rule is readable and independently testable
public boolean canProcessOrder(Order order, User user) {
    return isOrderProcessable(order) && isUserAuthorized(user, order);
}

private boolean isOrderProcessable(Order order) {
    return order != null
        && !order.getLines().isEmpty()
        && order.getStatus() == OrderStatus.DRAFT;
}

private boolean isUserAuthorized(User user, Order order) {
    if (user == null || !user.isActive() || user.isBlocked()) return false;
    return user.hasRole(Role.ADMIN) || order.isOwnedBy(user);
}
```

---

## YAGNI: Deeper Detail

> "Always implement things when you actually need them, never when you just foresee that you need them."
> — Ron Jeffries

### The cost of early generalization

- **Reading cost**: engineers who come after must understand abstractions with no obvious current use
- **Change cost**: the real requirement usually differs from the anticipated one — the pre-built abstraction must be reworked
- **Testing cost**: generalized code has more paths to cover, many hypothetical
- **Bug risk**: code exercised only by hypothetical paths is under-tested

### YAGNI violation examples

```java
// YAGNI violation — plugin system for one renderer
interface ReportRenderer { byte[] render(Report report); }
class PdfReportRenderer implements ReportRenderer { ... }
class HtmlReportRenderer implements ReportRenderer { ... }   // speculative
class ExcelReportRenderer implements ReportRenderer { ... }  // speculative

// YAGNI compliant — one implementation until a second is needed
class ReportService {
    public byte[] generatePdf(Report report) { /* direct implementation */ }
}
```

### When to override YAGNI

| Situation | Justification |
|-----------|--------------|
| Public API / SDK | External callers cannot be migrated; changes are breaking |
| Security boundaries | Retrofitting auth is error-prone; design it in from the start |
| Data schema | Migrations are costly; model the domain correctly upfront |
| Irreversible infrastructure choices | DB engine, event log retention, partitioning |
| Known second use case committed on roadmap | Abstract now to avoid immediate rework |

---

## DRY / KISS / YAGNI Tensions

| Tension | Resolution |
|---------|-----------|
| DRY vs. YAGNI | Wait for the third occurrence before extracting an abstraction |
| DRY vs. KISS | If the shared abstraction is harder to understand than two copies, keep the copies |
| KISS vs. YAGNI | Usually aligned — both resist complexity; no conflict in practice |

---

## FAANG Interview Framing

**"How do you decide when to abstract vs. inline something?"**

> I use the rule of three: once is inline, twice is suspicious, three times is abstract. Before the third case, I don't have enough signal to know what the abstraction really is. If I abstract from two cases, I often end up with something that's slightly wrong for a third and needs to be generalized again anyway.

**"How do you balance YAGNI with the need to build extensible systems?"**

> I distinguish reversible from irreversible decisions. Schema design, event contracts, public APIs, and security architecture are hard to change — I invest upfront. Everything else — internal class structure, service decomposition, specific algorithms — I design for current requirements and refactor when the next requirement makes the extension point obvious. Over-designed internal code is invisible tech debt; under-designed interfaces are breaking changes.

**"Can you give an example of KISS saving a project?"**

> On a data pipeline I inherited, the previous team had built a generic DAG execution engine with dynamic configuration and per-node retry strategies — supporting exactly one pipeline with four linear steps. 3,000 lines of configuration parsing, 40% test coverage. I replaced it with a 200-line sequential pipeline class — one method per step — with full coverage and transparent failure behaviour. The team shipped new features four times faster in the quarter after the replacement.

The right answer is judgment, not slogans.

## Interview Guidance

When explaining a design, show that you can balance reuse with simplicity. Interviewers want to hear that you know when to abstract and when to leave code duplicated for now.
