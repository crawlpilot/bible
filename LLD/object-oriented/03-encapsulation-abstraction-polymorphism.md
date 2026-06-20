# Encapsulation, Abstraction, Polymorphism, and Inheritance

These are the four pillars of object-oriented design. They are often listed together, but they each solve a different problem. Understanding the distinction is essential for FAANG interviews because interviewers frequently ask candidates to differentiate between them.

---

## Encapsulation

Encapsulation means bundling data and behavior together and preventing outside code from depending on internal details.

### Why it matters

- Protects invariants — the object enforces its own rules
- Reduces accidental misuse — callers cannot put the object into invalid states
- Makes refactoring safer — internal implementation can change without affecting callers

### Shallow vs. deep encapsulation

**Shallow encapsulation** (common but insufficient): making fields private and adding getters and setters. This is syntactic encapsulation only. A setter `setStatus(OrderStatus.CANCELLED)` allows any caller to cancel an order at any time with no validation.

**Deep encapsulation** (the correct form): the object exposes behavior, not state. Callers tell the object what to do; the object decides whether and how to do it.

```java
// Shallow encapsulation — setter exposes internal state transitions
class Order {
    private OrderStatus status;
    public void setStatus(OrderStatus status) { this.status = status; }  // no protection
}

// Deep encapsulation — Order owns and enforces its state machine
class Order {
    private OrderStatus status = OrderStatus.DRAFT;
    private final List<OrderLine> lines;

    public void confirm() {
        if (status != OrderStatus.DRAFT) {
            throw new InvalidOrderStateException("Cannot confirm order in state " + status);
        }
        this.status = OrderStatus.CONFIRMED;
        // trigger domain event, apply side effects...
    }

    public void cancel(CancellationReason reason) {
        if (status == OrderStatus.SHIPPED || status == OrderStatus.DELIVERED) {
            throw new InvalidOrderStateException("Cannot cancel after shipment");
        }
        this.status = OrderStatus.CANCELLED;
    }

    public Money calculateTotal() {
        return lines.stream().map(OrderLine::total).reduce(Money.ZERO, Money::add);
    }
}
```

### Invariant protection — the most important consequence of encapsulation

An **invariant** is a condition that must always be true for the object to be in a valid state. Examples:
- An `Order` in `CONFIRMED` state must have at least one `OrderLine`
- An `Account` balance cannot be negative (if overdrafts are not allowed)
- A `DateRange` must always have `start <= end`

Encapsulation is the mechanism that enforces invariants. If fields are public or freely settable, invariants cannot be guaranteed.

### Encapsulation in practice

```java
// Invariant: a Money value cannot have a negative amount
class Money {
    private final BigDecimal amount;
    private final Currency currency;

    public Money(BigDecimal amount, Currency currency) {
        if (amount.compareTo(BigDecimal.ZERO) < 0) {
            throw new IllegalArgumentException("Money amount cannot be negative");
        }
        this.amount = amount;
        this.currency = currency;
    }

    public Money add(Money other) {
        if (!this.currency.equals(other.currency)) {
            throw new CurrencyMismatchException();
        }
        return new Money(this.amount.add(other.amount), this.currency);  // immutable
    }
}
```

---

## Abstraction

Abstraction means exposing only the important details and hiding implementation complexity behind a simpler interface.

### Why it matters

- Helps callers focus on *what* the object does, not *how* it does it
- Makes systems easier to understand at a higher level
- Lets you replace implementation details without changing callers

### Levels of abstraction

Every well-designed system has multiple levels:

| Level | Example |
|-------|---------|
| Domain abstraction | `PaymentGateway.charge(Money)` |
| Service abstraction | `OrderRepository.findById(OrderId)` |
| Infrastructure abstraction | `HttpClient.post(url, body)` |

Each level hides the complexity of the level below. The domain model does not know whether `PaymentGateway` calls Stripe or PayPal; `OrderRepository` does not expose SQL.

### Abstraction example — payment processing

```java
// Without abstraction — business logic coupled to Stripe SDK
class CheckoutService {
    public void processPayment(Order order) {
        StripeCharge charge = StripeCharge.create(
            "tok_visa",
            order.totalCents(),
            "usd"
        );
        if (charge.getStatus().equals("succeeded")) { ... }
    }
}

// With abstraction — business logic is infrastructure-agnostic
interface PaymentGateway {
    PaymentResult charge(PaymentRequest request);
}

class StripePaymentGateway implements PaymentGateway { ... }
class PayPalPaymentGateway implements PaymentGateway { ... }
class MockPaymentGateway implements PaymentGateway { ... }  // for tests

class CheckoutService {
    private final PaymentGateway paymentGateway;

    public void processPayment(Order order) {
        PaymentResult result = paymentGateway.charge(PaymentRequest.from(order));
        if (result.isSuccessful()) { ... }
    }
}
```

### Abstraction vs. encapsulation — the precise distinction

| Concept | Question it answers | Mechanism |
|---------|--------------------|-----------| 
| **Encapsulation** | What does the object protect? | Access control (private fields, controlled mutations) |
| **Abstraction** | What does the object expose? | Interface design (method signatures, return types) |

A class can encapsulate well but abstract poorly (it hides its internals but exposes too much surface area). A class can abstract well but encapsulate poorly (clean interface, but callers can bypass it and reach internal fields).

---

## Polymorphism

Polymorphism means different objects can respond to the same message in different ways.

### Why it matters

- Replaces large conditional branches — no `if/else` on type
- Makes extension easier — add a new type without changing existing call sites
- Supports runtime behaviour selection

### Runtime polymorphism (subtype / dynamic dispatch)

The most common form. The method called is determined at runtime based on the actual object type, not the declared type.

```java
interface NotificationChannel {
    void send(Notification notification);
}

class EmailChannel implements NotificationChannel {
    public void send(Notification notification) { /* SMTP */ }
}

class SmsChannel implements NotificationChannel {
    public void send(Notification notification) { /* Twilio */ }
}

class PushChannel implements NotificationChannel {
    public void send(Notification notification) { /* FCM */ }
}

// Polymorphic dispatch — no if/else needed
class NotificationService {
    public void notify(List<NotificationChannel> channels, Notification notification) {
        channels.forEach(channel -> channel.send(notification));  // each responds differently
    }
}
```

**Before polymorphism** (the code it replaces):
```java
for (String channelType : channelTypes) {
    if (channelType.equals("EMAIL")) { sendEmail(notification); }
    else if (channelType.equals("SMS")) { sendSms(notification); }
    else if (channelType.equals("PUSH")) { sendPush(notification); }
    // every new channel type = edit this file
}
```

### Compile-time polymorphism (method overloading)

The method to call is determined at compile time based on parameter types.

```java
class Calculator {
    public int add(int a, int b) { return a + b; }
    public double add(double a, double b) { return a + b; }
    public Money add(Money a, Money b) { return a.add(b); }
}
```

Overloading is less powerful than runtime polymorphism and should be used carefully — it can create confusion when argument types are implicitly convertible.

### Parametric polymorphism (generics)

A class or method that works for any type satisfying a constraint.

```java
class Repository<T extends Entity> {
    public Optional<T> findById(UUID id) { ... }
    public List<T> findAll() { ... }
    public void save(T entity) { ... }
}
```

Generics allow the same algorithm to work with different types without code duplication, preserving type safety.

---

## Inheritance

Inheritance allows a subclass to acquire the fields and methods of a superclass.

### When inheritance is appropriate

- The is-a relationship is genuinely true and semantically stable
- The subtype must be substitutable for the base type (LSP holds)
- There is substantial shared behavior that doesn't diverge across subtypes
- The hierarchy is shallow (one or two levels max in most cases)

### When inheritance is inappropriate

- The relationship is has-a or uses-a, not is-a
- You want code reuse but not the is-a contract
- The subtype must override most of the base class behavior
- You anticipate the hierarchy growing in multiple dimensions

```java
// Inappropriate inheritance — using it for code reuse, not an is-a relationship
class Stack extends ArrayList<Integer> {  // a Stack IS NOT an ArrayList
    // ArrayList exposes add(index, element), remove(index)... that violate stack semantics
}

// Correct: composition for code reuse without inheriting a broken contract
class Stack<T> {
    private final Deque<T> storage = new ArrayDeque<>();
    public void push(T item) { storage.push(item); }
    public T pop() { return storage.pop(); }
    public T peek() { return storage.peek(); }
    public boolean isEmpty() { return storage.isEmpty(); }
}
```

### Abstract classes vs. interfaces

| | Abstract Class | Interface |
|--|---------------|-----------|
| **Purpose** | Partial implementation + contract | Pure contract (behaviour only) |
| **State** | Can have instance fields | No instance state (Java 8+: default methods) |
| **Multiple inheritance** | Not allowed (Java) | Allowed |
| **Use when** | Shared implementation with a stable template | Multiple unrelated types need the same role |

**Rule of thumb**: prefer interfaces for contracts between modules. Use abstract classes when multiple related classes share non-trivial implementation and a template method pattern is appropriate.

```java
// Abstract class: shared template
abstract class DataExporter {
    public final void export(Dataset data) {  // template method
        Dataset validated = validate(data);
        String formatted = format(validated);  // abstract — subclass decides format
        write(formatted);                       // abstract — subclass decides destination
    }

    private Dataset validate(Dataset data) { /* shared validation logic */ return data; }
    protected abstract String format(Dataset data);
    protected abstract void write(String content);
}

class CsvFileExporter extends DataExporter {
    protected String format(Dataset data) { /* CSV serialization */ return ""; }
    protected void write(String content) { /* write to disk */ }
}
```

---

## The Difference Summarised

| Pillar | Core question | Main mechanism |
|--------|--------------|----------------|
| **Encapsulation** | What does this object protect? | Private state + behavioral methods |
| **Abstraction** | What does this object expose? | Interfaces + limited surface area |
| **Polymorphism** | How can different types respond the same way? | Interface implementation / method override |
| **Inheritance** | How can one type extend another's contract? | `extends` / `implements` |

---

## FAANG Interview Framing

**"What's the difference between abstraction and encapsulation?"**

> Encapsulation is about protecting the internal state — making sure external code cannot violate the object's invariants. Abstraction is about the interface you expose — hiding complexity so callers work with a simpler mental model. A class can be well-encapsulated (all fields private, all mutations guarded) but poorly abstracted (it leaks too many implementation-specific methods). And it can have a clean abstract interface but still be poorly encapsulated if callers can bypass the interface.

**"When would you use an interface vs. an abstract class?"**

> Interface when I'm defining a contract between components that don't share implementation — `PaymentGateway`, `NotificationChannel`, `Repository`. Abstract class when I have a group of closely related classes that share a substantial implementation and I want to enforce a template structure — like a `DataExporter` that always validates, formats, then writes, but lets subclasses decide the format and destination. In Java, I also use interfaces when a class needs to play multiple roles, since single-class inheritance limits what abstract classes can do.

**"How does polymorphism help you write better code?"**

> It eliminates type-checking conditionals. Every time I see `if (type == X) ... else if (type == Y) ...` in a loop or a dispatcher, I ask: should this be polymorphic dispatch instead? The payoff is that adding a new type no longer requires editing existing code — just implementing the interface. That's the open/closed principle in practice.

## Practical Interview Example

If asked to design a notification system, you can explain it like this:

- Encapsulation keeps the delivery details inside each notifier
- Abstraction exposes a common `send()` method
- Polymorphism allows email, SMS, and push implementations to behave differently behind the same interface
