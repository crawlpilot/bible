# Object-Oriented Foundations

Object-oriented design is a way of organizing software around objects that combine state and behavior. The value of this approach is not that it is fashionable or traditional. The value is that it gives you a structure for managing complexity through clear responsibilities and explicit boundaries.

## The Core Idea

An object represents a cohesive piece of the domain. It owns some data, exposes behavior that acts on that data, and hides the details that should not be visible to the rest of the system.

That combination matters because software systems fail when every part knows too much about every other part. OO gives you a practical way to reduce that coupling.

## Why Object-Oriented Design Exists

| Problem | OO response |
|---------|-------------|
| Code becomes hard to reason about | Put related data and behavior together |
| Functions need too many parameters | Move state into an object |
| Changes ripple across the codebase | Hide implementation behind stable interfaces |
| Testing is difficult | Replace dependencies with mocks or fakes |
| Behavior varies by type | Use polymorphism instead of large conditionals |

## The Main Benefits

- **Modularity**: each class owns a focused responsibility
- **Encapsulation**: implementation details stay private
- **Reusability**: behavior can be reused through composition or inheritance
- **Testability**: dependencies can be swapped in tests
- **Extensibility**: new behavior can be added with less disruption to existing code

## The Main Risks

- Too many small classes with no clear domain value
- Deep inheritance hierarchies that are difficult to follow
- Objects that expose internal state directly
- Anemic domain models where objects are just data containers
- Over-abstraction before requirements are stable

## Composition vs Inheritance

Inheritance is useful when a subtype truly is a specialized version of a base type and can safely honor the base contract. Composition is usually safer because it lets you reuse behavior without binding yourself to a rigid hierarchy.

### Prefer Composition When

- You want to combine behaviors dynamically
- The variation is algorithmic rather than structural
- You want to avoid fragile base classes
- You expect the implementation to change often

### Prefer Inheritance When

- The subtype relationship is real and stable
- Shared behavior is substantial and unlikely to diverge
- The base class defines a strong contract

## A Simple Mental Model

Think in terms of three questions:

1. What data does this object own?
2. What behavior should live with that data?
3. What should remain hidden so the rest of the system stays stable?

---

## Cohesion and Coupling

These two metrics define the quality of an object-oriented design more precisely than any other single concept.

**Cohesion** is the degree to which the elements inside a class belong together. High cohesion means every field and method is directly related to the class's central responsibility.

**Coupling** is the degree to which a class depends on other classes. Low coupling means a change in one class does not force changes elsewhere.

The target is always **high cohesion, low coupling**.

| Combination | Outcome |
|-------------|---------|
| High cohesion, low coupling | Maintainable, testable, evolvable |
| High cohesion, high coupling | Works within a bounded context but breaks at boundaries |
| Low cohesion, low coupling | Anemic, utility-bag classes with no design value |
| Low cohesion, high coupling | The "god class" — the most common and damaging pattern |

### Detecting Low Cohesion (Code Smells)
- A class has more than 10–15 public methods
- Methods in the class do not share fields — some use `fieldA`, others use `fieldB`, none use both
- The class name includes words like `Manager`, `Handler`, `Processor`, `Util`, or `Helper` — these are often responsibility dumping grounds
- You cannot describe what the class does in one short sentence

### Detecting High Coupling (Code Smells)
- A class imports or instantiates many other concrete classes directly
- Changing the signature of one method forces changes in 5+ other files
- Testing the class requires setting up a large dependency graph

---

## The Law of Demeter (Principle of Least Knowledge)

> A module should not know about the internal structure of the objects it manipulates.

In practical terms: a method should only call methods on:
1. Itself
2. Objects passed as parameters
3. Objects it directly creates
4. Objects stored as direct fields

```java
// Violation: the caller knows too much about the structure
String city = customer.getAddress().getCity().toUpperCase();

// Compliant: the object speaks for itself
String city = customer.getCity();
```

This is sometimes summarised as "don't talk to strangers". The practical consequence is that chains like `a.b().c().d()` are a design warning — each dot is a dependency on an internal structure.

**Why it matters at scale**: in a large codebase, violating the Law of Demeter creates invisible coupling across module boundaries. When `Address` changes its internal structure, every caller that chains through it breaks — even though none of them are in the `Address` package.

---

## Tell, Don't Ask

Related to the Law of Demeter: instead of *asking* an object for its data to make a decision, *tell* the object what to do and let it use its own data to decide.

```java
// Ask pattern (procedural thinking inside OO code)
if (order.getStatus() == OrderStatus.PLACED && order.getPayment().isConfirmed()) {
    order.setStatus(OrderStatus.PROCESSING);
}

// Tell pattern (OO thinking)
order.startProcessing();  // Order knows its own rules
```

The tell pattern keeps business rules inside the objects that own the relevant data, which is where they belong.

---

## Object Modeling Process

When you design an object model in an interview or at work, apply these steps in order:

1. **Identify the nouns in the domain** — these are candidates for classes (`Order`, `User`, `Payment`, `Shipment`)
2. **Identify the verbs that apply to each noun** — these become methods (`confirm()`, `cancel()`, `ship()`)
3. **Assign each responsibility to exactly one class** — if you are unsure, the class whose data is most relevant should own it
4. **Draw the relationships** — association, composition, aggregation, or inheritance
5. **Ask "what changes independently?"** — each independent axis of change should be a separate class or interface
6. **Verify with a scenario walkthrough** — trace a real use case through the model and check that no class needs to reach into another's internals

### Relationship Types

| Relationship | Meaning | Lifetime | Example |
|-------------|---------|----------|---------|
| **Association** | A uses B | Independent | `Order` references `Customer` |
| **Aggregation** | A has B, but B can exist without A | Independent | `Department` has `Employee`s |
| **Composition** | A owns B, B cannot exist without A | Same lifetime | `Order` owns `OrderLine`s |
| **Inheritance** | A is-a B | — | `SavingsAccount` is-a `Account` |
| **Dependency** | A uses B temporarily | Method scope | `OrderService` uses `PricingEngine` |

Use **composition** (owns) for strong part-whole relationships. Use **association** (references) for loose links. Avoid **inheritance** unless the is-a relationship is genuinely stable.

---

## Composition vs. Inheritance — Detailed Comparison

```java
// Inheritance approach — fragile when requirements change
class Bird {
    public void fly() { ... }
}
class Duck extends Bird { }
class Penguin extends Bird {
    @Override
    public void fly() { throw new UnsupportedOperationException(); } // Liskov violation
}

// Composition approach — flexible and honest
interface Flyable { void fly(); }
interface Swimmable { void swim(); }

class Duck implements Flyable, Swimmable {
    private final FlyBehavior flyBehavior = new StandardFlight();
    private final SwimBehavior swimBehavior = new DuckPaddling();
    public void fly() { flyBehavior.fly(); }
    public void swim() { swimBehavior.swim(); }
}

class Penguin implements Swimmable {
    private final SwimBehavior swimBehavior = new DivingSwim();
    public void swim() { swimBehavior.swim(); }
    // no fly method — Penguin is honest about what it can do
}
```

**Interview answer on composition vs. inheritance**: "I default to composition because it avoids the fragile base class problem and doesn't lock me into a single hierarchy. I use inheritance when the subtype relationship is semantically true and I need the subtype to be substitutable for the base — i.e., when Liskov Substitution holds naturally."

---

## Anemic Domain Model Anti-Pattern

An **anemic domain model** is a design where classes exist only to hold data, with no behavior attached. All logic is in separate service classes.

```java
// Anemic: Order is a data bag
class Order {
    private OrderStatus status;
    private List<OrderLine> lines;
    // only getters and setters
}

// All logic dumped into a service (procedural, not OO)
class OrderService {
    public void confirm(Order order) { ... }
    public void cancel(Order order) { ... }
    public Money calculateTotal(Order order) { ... }
}

// Rich domain model: Order owns its behavior
class Order {
    private OrderStatus status;
    private List<OrderLine> lines;

    public void confirm() {
        if (status != OrderStatus.DRAFT) throw new InvalidOrderStateException(...);
        this.status = OrderStatus.CONFIRMED;
    }

    public Money calculateTotal() {
        return lines.stream().map(OrderLine::total).reduce(Money.ZERO, Money::add);
    }
}
```

The anemic model is common but leads to logic scattered across service classes, poor cohesion, and objects that cannot protect their own invariants. It is a symptom of procedural thinking expressed through OO syntax.

---

## FAANG Interview Framing

**Q: "Walk me through how you would design the object model for X."**

Apply this structure:
1. Identify the core entities (nouns) in the problem
2. Describe their responsibilities in one sentence each
3. Explain the relationships between them (composition, association)
4. Identify where variation will come from and show how polymorphism handles it
5. Mention what you explicitly excluded and why (YAGNI)

**Q: "What's the difference between an object-oriented and a procedural approach here?"**

> In a procedural approach, the data and the functions that act on it are separate. The callers must understand the data structure to know what to do with it. In an OO approach, the object owns its data and exposes behavior — callers tell the object what to do without knowing how. The OO model is preferable when the rules that govern the data are likely to evolve, because the logic stays co-located with the data it governs.

**Q: "How do you decide when to create a new class?"**

> When I find that I'm describing two distinct responsibilities in one sentence connected by "and", it's a signal to separate them. When I find that methods in a class don't share fields with each other, cohesion is low and splitting is warranted. When I find that tests for one piece of logic require setting up state for an unrelated piece, that's also a clear indicator.

If you can answer those clearly, your design is usually on the right track.

## Interview Framing

In an interview, say that OO is a tool for managing change. Then explain that good design reduces coupling, makes responsibilities obvious, and keeps the model aligned with the domain.
