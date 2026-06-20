# Common OOP Interview Mistakes

Many candidates know the definitions of OOP terms but struggle to apply them under design pressure. These are the mistakes that most often weaken an interview answer.

---

## 1. Reciting definitions without application

Saying "encapsulation hides data" is not enough. You need to explain how encapsulation affects a real design decision.

**Weak answer:**
> "Encapsulation means making fields private."

**Strong answer:**
> "Encapsulation means the object owns its own rules. For example, in this order system, I won't expose a `setStatus()` method — I'll expose `confirm()`, `cancel()`, and `ship()`, each of which validates the transition before applying it. That way an `Order` can never be put into an invalid state from outside."

---

## 2. Overusing inheritance

Inheritance is often treated as the default reuse mechanism. In practice, composition is safer and more flexible in most designs.

**Anti-pattern: using inheritance for code reuse without an is-a relationship**

```java
// Wrong: Stack IS NOT an ArrayList — it should not expose add(index, element)
class Stack<T> extends ArrayList<T> { ... }

// Correct: Stack HAS storage — composition is honest
class Stack<T> {
    private final Deque<T> storage = new ArrayDeque<>();
    public void push(T item) { storage.push(item); }
    public T pop() { return storage.pop(); }
}
```

**When interviewers hear you reach for inheritance first**, they are listening for whether you can articulate the trade-off. Default to composition and explain when you'd use inheritance (genuine is-a, LSP holds, shared behavior is substantial and stable).

---

## 3. Creating abstract classes and interfaces too early

If you don't yet know the variation points, an abstract base class is premature. Start with a concrete implementation and refactor toward abstraction only when you see the second or third case.

**Premature abstraction:**
```java
// There is only one type of payment in the system today
abstract class AbstractPaymentProcessor {
    protected abstract void validatePayment(Payment p);
    protected abstract void executeTransaction(Payment p);
    protected abstract void sendConfirmation(Payment p);
    public final void process(Payment p) {
        validatePayment(p); executeTransaction(p); sendConfirmation(p);
    }
}
```

If there is one payment type, there is nothing to abstract yet. The template method pattern here costs you flexibility — you've locked in the three-step structure before knowing whether it's the right structure for all payment types.

**Correct approach:**
```java
// Start concrete
class CardPaymentProcessor {
    public void process(Payment payment) {
        validate(payment);
        charge(payment);
        notify(payment.getUser());
    }
}
// Introduce the abstraction when a second processor arrives with different needs
```

---

## 4. Ignoring invariants

An object should protect its own rules. If outside code can put the object into an invalid state, the model is too weak.

**Broken invariant example:**

```java
// DateRange with no invariant protection
class DateRange {
    public LocalDate start;
    public LocalDate end;
}
// Nothing prevents end < start — the object cannot protect itself

// Correct: enforce the invariant at construction
class DateRange {
    private final LocalDate start;
    private final LocalDate end;

    public DateRange(LocalDate start, LocalDate end) {
        if (end.isBefore(start)) {
            throw new IllegalArgumentException("End date must be >= start date");
        }
        this.start = start;
        this.end = end;
    }
}
```

**Interview signal:** when you describe an object in an interview and an interviewer asks "what happens if X is set to Y?", the correct answer is never "the caller shouldn't do that" — the correct answer is "the object prevents that by throwing an exception / using a factory / enforcing the rule in the constructor."

---

## 5. Designing for every future scenario

Interviewers prefer a focused design that solves the current problem well over a generic framework that anticipates every possible future requirement.

**Over-designed answer:**
> "I'd build a plugin-based architecture where each step in the workflow is configurable via a DSL, and the engine supports branching, loops, compensation transactions, and distributed checkpointing..."

For an interview question about a checkout flow with three steps.

**Focused answer:**
> "I'd model three domain steps as methods on a `CheckoutService`: `reserveInventory()`, `chargePayment()`, `scheduleShipment()`. If we need to support different payment strategies, I'd add a `PaymentStrategy` interface at that point. I'm not pre-building the plugin system unless the requirements call for it."

---

## 6. Confusing interfaces with abstraction

An interface is a tool. Abstraction is the design idea. You can have abstraction without a formal interface, and you can create an interface that adds no useful abstraction.

**Interface without abstraction:**
```java
// This interface adds no value — it just wraps one class with no additional meaning
interface UserServiceInterface {
    User findById(UUID id);
    void save(User user);
    void delete(UUID id);
}
class UserServiceImpl implements UserServiceInterface { ... }
// The interface and the class have identical structure; there is only one implementation
// and no plan for a second one
```

**Abstraction without a formal interface:**
```java
// A well-named class with private implementation IS an abstraction
class MoneyCalculator {
    public Money calculateTotal(List<LineItem> items) { ... }  // caller doesn't know the algorithm
}
```

Interviewers want to see that you introduce interfaces where there is genuine variation, not as a reflexive convention.

---

## 7. Using design patterns as the answer instead of the tool

Patterns are useful when they solve a real problem. They are not a substitute for understanding the domain.

**Pattern-first mistake:**
> "I'd use a Facade, a Factory, and a Chain of Responsibility here..."
(stated before the problem is fully understood)

**Domain-first correct approach:**
1. Understand the problem and the entities
2. Identify the variation points
3. Apply the pattern that fits the variation — and name it if it helps communication

If you reach for Observer, Strategy, or Builder, be able to explain *what problem would occur without it* and *why that pattern is the right fit*.

---

## 8. Neglecting testability as a design goal

At FAANG level, interviewers expect you to design for testability as a first-class concern, not as an afterthought.

**Untestable design:**
```java
class ReportService {
    public Report generate(UUID userId) {
        User user = new UserRepository().findById(userId);  // direct instantiation
        List<Order> orders = new OrderRepository().findByUser(userId);  // not injectable
        return buildReport(user, orders);
    }
}
```

**Testable design:**
```java
class ReportService {
    private final UserRepository userRepository;
    private final OrderRepository orderRepository;

    public ReportService(UserRepository userRepository, OrderRepository orderRepository) {
        this.userRepository = userRepository;
        this.orderRepository = orderRepository;
    }

    public Report generate(UUID userId) {
        User user = userRepository.findById(userId).orElseThrow();
        List<Order> orders = orderRepository.findByUserId(userId);
        return buildReport(user, orders);
    }
}
// Can be tested with InMemoryUserRepository and InMemoryOrderRepository
```

**Interview signal:** after describing a design, proactively say: "This is injectable so I can test `ReportService` with in-memory fakes without needing a real database."

---

## 9. Not talking about trade-offs

A principal engineer answer always includes trade-offs. Describing only the upsides of your design choice suggests you haven't thought about the costs.

**Weak answer:**
> "I'd use an event-driven design for this."

**Strong answer:**
> "I'd use an event-driven design here because it decouples the order service from the inventory service and lets each team scale independently. The cost is eventual consistency — the inventory may be temporarily out of sync with the order count — which is acceptable here because we're already managing distributed state across these services. If we needed strict consistency, I'd use a saga with compensation instead."

---

## 10. Anemic domain model

The most common structural mistake in OOP interviews: creating classes that hold data but contain no behavior, and placing all logic in service classes.

```java
// Anti-pattern: Order is a passive data container
class Order {
    private OrderStatus status;
    private List<OrderLine> lines;
    public OrderStatus getStatus() { return status; }
    public void setStatus(OrderStatus status) { this.status = status; }
    // no business logic here — it's all in OrderService
}

// Where it ends up:
class OrderService {
    public void cancel(Order order) {
        if (order.getStatus() == OrderStatus.SHIPPED) {
            throw new IllegalStateException();
        }
        order.setStatus(OrderStatus.CANCELLED);  // caller manages state transitions
    }
}
```

The problem: `OrderService` now knows and enforces `Order`'s business rules. If there are multiple services that manipulate orders, those rules will be duplicated or forgotten.

```java
// Correct: Order owns its own behavior and invariants
class Order {
    private OrderStatus status;
    private final List<OrderLine> lines;

    public void cancel() {
        if (status == OrderStatus.SHIPPED || status == OrderStatus.DELIVERED) {
            throw new InvalidOrderStateException("Cannot cancel after dispatch");
        }
        this.status = OrderStatus.CANCELLED;
    }

    public Money calculateTotal() {
        return lines.stream().map(OrderLine::total).reduce(Money.ZERO, Money::add);
    }
}
```

---

## Interview Improvement Checklist

Before wrapping up an OOP design in an interview, verify:

- [ ] **Responsibilities are focused** — each class has one clear reason to change
- [ ] **Inheritance is justified** — you can state the is-a relationship and confirm LSP holds
- [ ] **Abstractions exist where variation exists** — not everywhere by default
- [ ] **Invariants are protected** — objects cannot be put into invalid states from outside
- [ ] **The design is testable** — dependencies are injected, not instantiated internally
- [ ] **Trade-offs are stated** — you've mentioned what your design trades off
- [ ] **Patterns are named only when used** — and you can explain the problem each solves
- [ ] **No over-engineering** — the design matches the requirements as stated, not hypothetical extensions

---

## FAANG Calibration

| Mistake | L5 (Senior) gets it wrong | L6+ (Staff/Principal) never makes it |
|---------|--------------------------|--------------------------------------|
| Definitions without application | Often | Never |
| Overusing inheritance | Sometimes | Defaults to composition with justification |
| Ignoring invariants | Sometimes | Explicitly calls out invariant protection |
| Anemic domain model | Frequently | Distinguishes rich vs. anemic; chooses consciously |
| No trade-offs stated | Sometimes | Always states trade-offs before being asked |
| Patterns as the answer | Occasionally | Domain-first, pattern-second |
| No testability discussion | Frequently | Design for testability is a default posture |
