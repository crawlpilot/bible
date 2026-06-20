# SOLID Principles

SOLID is a compact way to explain what makes an object-oriented design maintainable. It does not guarantee good architecture, but it gives you a useful checklist for identifying weak designs and improving them.

SOLID was popularised by Robert C. Martin. Each letter addresses a distinct failure mode that appears when responsibilities blur or dependencies point the wrong way.

---

## S: Single Responsibility Principle

> "A class should have one, and only one, reason to change."

A **reason to change** is a stakeholder or actor that can drive a change request. If the finance team and the devops team can both force a change to the same class, that class has two reasons to change.

### Good signal

- `InvoiceCalculator` — computes invoice totals (owned by finance logic)
- `InvoiceRepository` — persists invoices (owned by data layer)
- `InvoicePdfRenderer` — renders to PDF (owned by document format)
- `InvoiceEmailSender` — sends notifications (owned by comms team)

### Bad signal

- `InvoiceService` — computes totals, saves to DB, sends emails, and generates PDFs

When a class owns too many unrelated concerns, every change becomes risky: a change to email formatting can accidentally break the PDF rendering.

### Violation example and fix

```java
// Violation: one class, four reasons to change
class UserManager {
    public void createUser(User user) { /* DB insert */ }
    public void sendWelcomeEmail(User user) { /* SMTP */ }
    public void generateUserReport(User user) { /* PDF */ }
    public boolean authenticateUser(String user, String pass) { /* JWT */ }
}

// Compliant: each class has one reason to change
class UserRepository {
    public void save(User user) { /* DB insert */ }
}

class UserNotificationService {
    public void sendWelcomeEmail(User user) { /* SMTP */ }
}

class UserReportGenerator {
    public Report generate(User user) { /* PDF */ }
}

class AuthenticationService {
    public boolean authenticate(String username, String password) { /* JWT */ }
}
```

### Interview framing

> "SRP isn't just about having one method. It's about having one *actor* — one team, one feature domain, one business capability — that can drive a change to this class. If two different parts of the business can force me to open this file, that's a cohesion problem waiting to become a bug."

---

## O: Open/Closed Principle

> "Software entities should be open for extension, but closed for modification."

Stable, tested code should not need to be rewritten every time a new behaviour is added. Instead, design extension points so that new behaviour is added by writing new code, not by editing existing code.

### Example: discount strategy

```java
// Violation: adding a new discount type requires editing this class
class PriceCalculator {
    public double calculatePrice(Order order, String discountType) {
        if (discountType.equals("PERCENT")) {
            return order.getTotal() * 0.9;
        } else if (discountType.equals("FIXED")) {
            return order.getTotal() - 10;
        }
        // Every new discount type = edit this file
        return order.getTotal();
    }
}

// Compliant: new discount types are added by writing a new class
interface DiscountStrategy {
    double apply(double total);
}

class PercentageDiscount implements DiscountStrategy {
    private final double percent;
    public double apply(double total) { return total * (1 - percent / 100); }
}

class FixedDiscount implements DiscountStrategy {
    private final double amount;
    public double apply(double total) { return total - amount; }
}

class LoyaltyDiscount implements DiscountStrategy {  // added without touching existing code
    public double apply(double total) { return total * 0.85; }
}

class PriceCalculator {
    public double calculatePrice(Order order, DiscountStrategy discount) {
        return discount.apply(order.getTotal());
    }
}
```

### When to apply OCP

OCP does not mean "never edit any class". It means: identify the **variation points** in your system — the places most likely to change — and design abstraction around them. Stability around the core, openness at the edges.

### Interview framing

> "OCP guides me to identify where my system will need to grow. If I'm writing an `if/else` chain that I know will grow — different payment types, different notification channels, different export formats — that's the signal to introduce an interface. I don't pre-emptively abstract everything; I abstract where I can see variation coming."

---

## L: Liskov Substitution Principle

> "Subtypes must be substitutable for their base types without altering the correctness of the program."

This principle formalises what it means for an inheritance relationship to be correct. If you have to check `instanceof` or override a method to throw `UnsupportedOperationException`, you have violated LSP.

### The classic violation: Square extends Rectangle

```java
// Rectangle contract: width and height are independently settable
class Rectangle {
    protected int width, height;
    public void setWidth(int w) { this.width = w; }
    public void setHeight(int h) { this.height = h; }
    public int area() { return width * height; }
}

// Square violates the contract: setting width also changes height
class Square extends Rectangle {
    @Override
    public void setWidth(int w) { this.width = this.height = w; }
    @Override
    public void setHeight(int h) { this.width = this.height = h; }
}

// Code that worked with Rectangle breaks silently with Square
Rectangle r = new Square();
r.setWidth(5);
r.setHeight(3);
assert r.area() == 15;  // FAILS — actual result: 9
```

**Fix**: `Square` and `Rectangle` should be separate classes. If they share behaviour, use a common interface (e.g., `Shape`) without assuming independent dimension mutability.

### LSP contract rules

A subclass must:
- Accept **at least as broad** a set of inputs as the base class (contravariance on parameters)
- Return **at most as specific** a set of outputs (covariance on return types)
- Throw **no new exceptions** beyond what the base class declared
- Not **strengthen preconditions** (subclass cannot require more from callers)
- Not **weaken postconditions** (subclass cannot guarantee less to callers)

### Interview framing

> "LSP tells me whether an inheritance relationship is semantically honest. The test I use is: can I substitute every subtype in code that was written for the base type without knowing anything about the subtype? If the answer is no — because the subtype throws an exception the base didn't, or changes what a method means — then the hierarchy is wrong. I'd use composition or a different interface split instead."

---

## I: Interface Segregation Principle

> "Clients should not be forced to depend on methods they do not use."

Large interfaces create unnecessary coupling. When a client implements an interface it doesn't fully use, it must provide stub implementations, and changes to the large interface ripple to all clients — even those that don't care about the changed method.

### Violation and fix

```java
// Violation: one fat interface
interface Worker {
    void work();
    void eat();
    void sleep();
}

// A robot implements Worker but cannot eat or sleep
class Robot implements Worker {
    public void work() { /* actual work */ }
    public void eat() { throw new UnsupportedOperationException(); }  // forced stub
    public void sleep() { throw new UnsupportedOperationException(); } // forced stub
}

// Compliant: split by role
interface Workable { void work(); }
interface Feedable { void eat(); }
interface Restable { void sleep(); }

class HumanWorker implements Workable, Feedable, Restable { ... }
class Robot implements Workable { ... }  // honest; only what it can do
```

### ISP in the context of microservices and APIs

ISP also applies to REST APIs and service contracts. A client consuming a large aggregated API endpoint should not receive fields it never uses. Prefer purpose-specific endpoints or GraphQL-style field selection over one massive response type.

### Interview framing

> "ISP keeps my interfaces cohesive and my clients honest. When I see an interface with 15 methods, I ask: is every client using all 15? If not, the interface is doing too many things. I'll split by role or capability. The test: every implementation of this interface should be able to implement every method without throwing UnsupportedOperationException."

---

## D: Dependency Inversion Principle

> "High-level modules should not depend on low-level modules. Both should depend on abstractions. Abstractions should not depend on details. Details should depend on abstractions."

DIP reverses the intuitive direction of dependencies. Instead of business logic depending directly on a database or messaging library, both the business logic and the infrastructure implement and depend on an abstraction.

### Violation and fix

```java
// Violation: high-level business logic directly depends on low-level MySQL implementation
class OrderService {
    private final MySQLOrderRepository repo = new MySQLOrderRepository();  // concrete

    public void placeOrder(Order order) {
        repo.save(order);
    }
}

// Compliant: business logic depends on an abstraction; infrastructure depends on it too
interface OrderRepository {
    void save(Order order);
}

class MySQLOrderRepository implements OrderRepository {
    public void save(Order order) { /* MySQL-specific JDBC */ }
}

class InMemoryOrderRepository implements OrderRepository {  // for tests
    public void save(Order order) { /* in-memory store */ }
}

class OrderService {
    private final OrderRepository repo;  // depends on abstraction

    public OrderService(OrderRepository repo) {  // injected
        this.repo = repo;
    }

    public void placeOrder(Order order) {
        repo.save(order);
    }
}
```

### DIP enables testability

The primary practical benefit of DIP is that business logic can be unit-tested without standing up a real database, real message broker, or real HTTP service. The test injects a fake or mock implementation.

### DIP vs. Dependency Injection

DIP is the *principle* — the rule about which way dependencies should point. Dependency Injection (DI) is the *mechanism* used to satisfy DIP at runtime. DI frameworks (Spring, Guice, .NET DI) automate the wiring, but they don't create DIP compliance by themselves; the interfaces must still be designed correctly.

### Interview framing

> "DIP is the architectural consequence of all the other SOLID principles. When I apply SRP, OCP, and ISP, I end up with focused interfaces. DIP says: wire them together through those interfaces, not through concrete types. The result is that my business logic has no compile-time dependency on any infrastructure concern — database, queue, cache. I can swap the infrastructure, test in isolation, and evolve the two halves independently."

---

## SOLID as a System

The five principles reinforce each other:

| If you violate... | You create... | Which prevents... |
|------------------|--------------|--------------------|
| SRP | God class | OCP (can't extend one part without risking another) |
| OCP | Rigid if/else chains | Extensibility |
| LSP | Surprise behaviour in subtypes | Correct polymorphism |
| ISP | Fat interfaces | Cohesive, honest contracts |
| DIP | Tight coupling to infrastructure | Testability and swappability |

Applying all five together produces classes that are: focused (SRP), extensible (OCP), safely inheritable (LSP), contract-clean (ISP), and loosely coupled (DIP).

---

## SOLID Quick-Reference Card

```
S — Single Responsibility: one class = one reason to change (one actor)
O — Open/Closed:           extend by adding new code, not editing stable code
L — Liskov Substitution:   a subtype is always safely usable as its base type
I — Interface Segregation: interfaces are narrow and role-specific
D — Dependency Inversion:  business logic depends on abstractions, not concretions
```

---

## FAANG Interview Points

**"How do you apply SOLID in practice — not just define the letters?"**

> I don't apply SOLID as a checklist before writing code. I apply it as a diagnostic when I feel design pain. When I find myself writing the same conditional in multiple places, that's OCP telling me to introduce a strategy. When I find a class that needs a large test setup to test one method, that's SRP telling me the class has too many responsibilities. When I write `throw new UnsupportedOperationException()` in a subclass, that's LSP telling me the inheritance is wrong. The principles are most useful as a vocabulary for diagnosing pain, not a rulebook for upfront design.

**"Can SOLID principles ever be over-applied?"**

> Yes. SOLID applied too early leads to over-abstraction. SRP can create too many small classes that are hard to follow. OCP can lead to unnecessary interfaces before any variation exists. The right time to apply each principle is when you feel the pain that principle solves: duplication that signals DRY/OCP, test difficulty that signals DIP/SRP, or a hierarchy that's breaking that signals LSP/ISP. YAGNI is always in tension with OCP — I don't abstract for extension until I have two concrete cases of the variation.

## How SOLID Works Together

| Principle | Problem it reduces |
|-----------|-------------------|
| SRP | Unclear responsibilities |
| OCP | Fragile code when adding features |
| LSP | Broken inheritance hierarchies |
| ISP | Bloated interfaces |
| DIP | Tight coupling to low-level details |

## How to Use SOLID in an Interview

Do not recite the letters. Use them to explain design choices:

- Why did you split this class?
- Why did you use an interface here?
- Why is composition safer than inheritance in this case?

That is the level interviewers care about.
