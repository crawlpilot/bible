# A Philosophy of Software Design
**Author:** John Ousterhout  
**Edition:** 2nd Edition (2021)  
**Relevance:** The most precise treatment of software complexity available — essential for principal engineers who design and critique systems at scale

---

## Why This Book Matters for Principal Engineers

Most software engineering books tell you *what* to do. Ousterhout tells you *why complexity accumulates* and gives you a precise vocabulary to identify it, name it, and fight it. For a principal engineer, this matters because:

1. **Code review and design review** require a vocabulary for articulating *why* a design is wrong, not just that it feels wrong.
2. **Architecture decisions** are ultimately decisions about where complexity lives, who owns it, and how it propagates.
3. **Mentoring** requires being able to teach design judgment, not just demonstrate it. Ousterhout's framework is teachable.

The central argument is simple and radical: **the fundamental goal of software design is to reduce complexity.** Everything else — modularity, abstraction, naming, comments, error handling — is a technique in service of that goal.

---

## The Central Thesis: Complexity Is the Enemy

### What Is Complexity?

Ousterhout defines complexity precisely:

> *"Complexity is anything related to the structure of a software system that makes it hard to understand and modify the system."*

Complexity is not the same as size. A large system can be low-complexity. A small system can be high-complexity. Complexity is a **property of the relationship between the parts**, not the sum of the parts.

### Why Complexity Matters

Complexity has two primary consequences:

1. **It slows development**: Engineers spend more time understanding, navigating, and verifying changes than actually writing new behavior.
2. **It causes bugs**: Engineers make incorrect changes because they don't understand all the implications of what they're modifying.

At principal engineer scale, complexity is the single greatest drag on engineering velocity. Not headcount. Not tooling. Not process. Complexity.

### The Three Symptoms of Complexity

Ousterhout identifies three observable symptoms that tell you complexity has accumulated:

| Symptom | Description | Example |
|---|---|---|
| **Change amplification** | A simple change requires modifications in many places | Adding a new field requires updating 12 files |
| **Cognitive load** | Requires significant background knowledge to make even small changes | Can't fix a bug without understanding 5 subsystems |
| **Unknown unknowns** | You don't know what you need to know to make a change safely | A change looks correct but breaks an unrelated feature |

**Unknown unknowns are the worst form.** Change amplification and cognitive load are visible and measurable. Unknown unknowns are invisible until they cause incidents.

### The Two Causes of Complexity

All complexity comes from exactly two sources:

1. **Dependencies**: When one piece of code cannot be understood or modified without understanding another.
2. **Obscurity**: When important information is not obvious from the code.

Every design technique in this book is a strategy to reduce dependencies, reduce obscurity, or both.

### How Complexity Accumulates

Complexity is insidious because it accumulates in small increments. No single decision makes a system unmaintainable. It's the accumulation of thousands of small compromises:
- "I'll just add a flag for this edge case."
- "I'll hardcode this for now."
- "I'll handle this special case at the call site."

Each decision adds a tiny amount of complexity. Over years, these accumulate into systems that are genuinely difficult to change. This is why code review for design quality (not just correctness) is essential.

---

## Chapter 2: The Nature of Complexity

### Tactical vs. Strategic Programming

This is the most important frame in the book. Ousterhout draws a hard line between two programming mindsets:

**Tactical Programming:**
- Goal: Make the current feature work as fast as possible.
- Approach: Shortest path to passing tests. Patches. Hacks. Special cases.
- Result: Works today. Harder to change tomorrow. Slightly harder every day after.

**Strategic Programming:**
- Goal: Make the system easy to change in the future, including today's change.
- Approach: Invest in design. Refactor before adding. Think about the abstraction first.
- Result: Slower today. Compound returns over months and years.

**The investment frame**: Strategic programming requires an upfront investment — perhaps 10–15% more time on any given task. That investment pays back with interest because future changes take less time. In a system with high strategic investment, a change that would take 3 days in a tactical system takes 3 hours.

> *"Facebook used to have the motto 'move fast and break things.' … Eventually they changed their motto to 'move fast with solid infrastructure.'"*

**The tactical tornado**: Some engineers are celebrated as heroes because they ship fast. They are tactical programmers. They ship fast by creating complexity. Other engineers spend their time cleaning up the mess. The tactical tornado looks productive; the system health metric tells a different story.

> *Principal engineer callout: Tactical programmers are promoted to individual contributor levels and plateau. Strategic programmers become staff and principal engineers because they compound. When you review code or coach engineers, the most important skill you can teach is the discipline of strategic programming.*

---

## Chapter 3: Working Code Isn't Enough (Strategic vs. Tactical)

The chapter reinforces the strategic/tactical dichotomy with concrete examples. The main point: **working code is the minimum bar, not the goal.** The goal is code that is correct, readable, and easy to change.

**Startups as a special case**: The book acknowledges that pure strategic programming is a luxury at early-stage startups where survival depends on shipping. The pragmatic approach: establish a minimum threshold of design quality (interfaces, module boundaries) even under speed pressure, so that the system doesn't become unmaintainable before the startup survives.

---

## Chapter 4: Modules Should Be Deep

This is the book's most original and actionable idea.

### The Interface vs. Implementation Distinction

Every module has:
- **Interface**: Everything a user of the module needs to know to use it. Parameters, return types, side effects, exceptions, ordering constraints.
- **Implementation**: Everything inside the module that makes it work.

**The goal of modularity**: Hide implementation behind a clean interface so that users don't need to understand the implementation to use the module.

### Deep vs. Shallow Modules

**Deep module**: A module with a **small interface** and a **large implementation**. The interface hides a lot of complexity.

**Shallow module**: A module with an **interface that is almost as complex as its implementation**. It provides little abstraction benefit.

```
Deep module:
┌──────────────────────────────────────┐
│         Interface (small)            │  ← thin line at top
├──────────────────────────────────────┤
│                                      │
│       Implementation (large)         │  ← big box below
│                                      │
│                                      │
└──────────────────────────────────────┘

Shallow module:
┌──────────────────────────────────────┐
│         Interface (large)            │  ← thick line at top
├──────────────────────────────────────┤
│       Implementation (small)         │  ← thin box below
└──────────────────────────────────────┘
```

**The ideal deep module** is Unix I/O:
- **Interface**: `open`, `read`, `write`, `close`, `lseek` — 5 system calls.
- **Implementation**: Hundreds of thousands of lines of kernel code handling file systems, device drivers, buffering, caching, permissions, network file systems, and more.

The entire complexity of the operating system's I/O stack is hidden behind 5 function calls.

**The archetypal shallow module** is a class with a getter and setter for every private field:

```java
// Shallow — the interface is as complex as the implementation
class UserRecord {
    private String firstName;
    private String lastName;
    
    public String getFirstName() { return firstName; }
    public void setFirstName(String firstName) { this.firstName = firstName; }
    public String getLastName() { return lastName; }
    public void setLastName(String lastName) { this.lastName = lastName; }
}
```

This class provides zero abstraction. The caller must know the exact internal representation. A module like this actually *increases* complexity by adding boilerplate without hiding anything.

### The Classitis Problem

Many modern software engineering cultures — particularly Java and OOP communities — have a bias toward many small classes. "Small classes are easier to understand!" This sounds reasonable but leads to classitis: a system with hundreds of tiny classes that each do almost nothing, requiring the caller to understand and coordinate all of them.

**The test for depth**: *How much implementation complexity does this interface hide?* If the answer is "not much," the module is shallow and should probably be merged into something else.

---

## Chapter 5: Information Hiding (and Leakage)

### Information Hiding

The most important technique for deep modules is **information hiding**: each module should know as little as possible about other modules. The implementation details of a module should be invisible to its callers.

**What to hide**:
- Data structures used internally
- Algorithms used to compute results
- Sequencing constraints and ordering dependencies
- Hardware-specific details
- Performance optimizations
- Error handling internals

**The benefit**: If you hide a detail, you can change it without affecting callers. If you expose it (through the interface), changing it breaks callers.

### Information Leakage

**Information leakage** occurs when design decisions are reflected in multiple modules. The moment that information about a module's internals is shared with other modules, you have created a dependency. Now both modules must be changed if that implementation detail changes.

**Example of temporal decomposition causing leakage**:

Consider a system that reads a file, parses it, and processes the results. An engineer decomposes this into three classes:
- `FileReader` — reads the file
- `FileParser` — parses it
- `FileProcessor` — processes results

Each class knows that the input is a file. If you change the input source to an API response, you must change all three classes. The file format has leaked across three module boundaries.

Better decomposition: one class that reads and parses (these are tightly coupled — the parser needs to know the format to parse it correctly), and one class that processes the semantic results (which doesn't care about the source).

### Temporal Decomposition

**Temporal decomposition** is the anti-pattern of organizing code by *when* things happen rather than *what* they do. It almost always causes information leakage.

> *"When designing modules, focus on the knowledge that's needed to perform each task, not on the order in which tasks occur."*

**Anti-pattern**: Decompose a system into phases (read → parse → validate → transform → store) and make each phase a module. The modules end up sharing knowledge about data formats, schemas, and intermediate representations.

**Better**: Decompose by **semantic ownership** — which module is responsible for which piece of domain knowledge? Let that module own the full lifecycle of that knowledge.

---

## Chapter 6: General-Purpose Modules Are Deeper

A persistent tension in software design: **should a module be general-purpose or special-purpose?**

Ousterhout's answer: **err toward general-purpose**, because:

1. General-purpose modules tend to be deeper (the interface hides more).
2. General-purpose modules are reused, which amortizes their design cost.
3. Special-purpose modules often reflect today's requirements; general-purpose modules survive requirement changes.

**The "somewhat general-purpose" sweet spot**: Don't over-engineer a truly generic framework. The goal is to identify the natural abstraction level of the domain and implement at that level — which is usually more general than the immediate use case but less general than a universal framework.

**Test for appropriate generality**: *"What is the simplest interface that covers all my current use cases?"* If the answer is more general than the current use case alone, you've found the right abstraction level.

**Example**: Designing a text editor's storage system for the first time. A special-purpose design might include operations like `backspace()`, `deleteSelection()`, `pasteText()`. A general-purpose design includes only `insert(position, text)` and `delete(start, end)`. The general-purpose version is simpler (fewer operations), covers all the same use cases, and adapts to future editing operations the designer hasn't thought of yet.

---

## Chapter 7: Different Layer, Different Abstraction

**Every layer in a system should provide a different abstraction from the layers above and below it.**

If two adjacent layers provide the same abstraction, one of them is probably unnecessary (or they should be merged).

### Pass-Through Methods

A **pass-through method** is a method that does little except invoke another method with the same (or nearly the same) signature:

```java
class UserService {
    private UserRepository repository;
    
    // Pass-through — adds no abstraction
    public User findById(Long id) {
        return repository.findById(id);
    }
}
```

This is a symptom of shallow layering. The `UserService` is not providing a different abstraction from the `UserRepository`. It exists because someone decided there should be a service layer, not because the service layer is doing something meaningful.

**Acceptable middle ground**: Methods that delegate *and* add real behavior (validation, authorization, caching, logging at a semantic level) are not pass-through methods. The key question is: *does this layer transform the abstraction, or just relay it?*

### Decorators

The Decorator pattern is frequently misused to create shallow wrappers:

```java
// Shallow decorator — adds almost no value
class LoggingFileReader extends FileReader {
    public String read(String path) {
        log.info("Reading file: " + path);
        return super.read(path);
    }
}
```

If this is the only behavior added by the decorator, it probably shouldn't be a separate class at all. The logging could be added to the underlying class, or the functionality could be composed differently.

**When decorators are justified**: When the added behavior is substantial, the decorator is a different team's responsibility, or the base class is in a library you don't control.

### Interface vs. Implementation Bloat

When an interface has the same number of methods as its implementation, and those methods map 1:1, the interface is providing no abstraction. It's documentation overhead with no design benefit.

---

## Chapter 8: Pull Complexity Downward

When designing a new module that will be used by many callers, you face a choice: **push complexity up to callers, or pull it down into the implementation.**

**Ousterhout's principle**: Pull complexity downward. Make life simple for callers at the cost of making the implementation more complex.

**Rationale**: If you push complexity upward, every caller must handle it. If there are 10 callers, the complexity is implemented 10 times (often inconsistently). If you pull it down, it's implemented once, correctly, in the module that owns the knowledge.

### Configuration Parameters as Complexity Pushback

Configuration parameters are a common form of complexity pushback. When a module exposes 15 tuning parameters, it's saying: *"I don't know the right value — you figure it out."*

Every configuration parameter represents knowledge the module is refusing to encapsulate. This pushes cognitive burden onto every caller.

**The alternative**: The module should try to determine the right value from context. If it truly cannot, expose the minimum configuration necessary. Default to sensible values and only require parameters when the caller genuinely knows something the module cannot.

> *"The downside of configuration parameters is that they create complexity for users of the module. Configuration parameters are fine if there's a sensible default and the user rarely changes them. But if users frequently have to set them, or if there are many of them, it's a sign that the module isn't deep enough."*

---

## Chapter 9: Better Together or Better Apart?

When should two pieces of functionality be merged into one module, and when should they be separated?

**Arguments for merging**:
- Information is shared between them (they need to know the same things)
- Merging eliminates pass-through interfaces
- The combined interface is simpler than two separate interfaces
- They form a natural conceptual unit

**Arguments for separating**:
- They serve different purposes or audiences
- Separating reduces cognitive load per module
- They have different rates of change

**The key test**: *Does combining them reduce the total complexity of the system (interfaces + implementations), or does it increase it?*

### Splitting Methods

Splitting a method into multiple smaller methods is only beneficial if:
1. Each sub-method is usable independently by callers (not just called by the parent)
2. The split creates a genuine abstraction that reduces cognitive load

Splitting a 200-line method into 10 private helper methods that are only ever called in sequence from the parent doesn't reduce complexity — it increases it by adding indirection without abstraction.

**Conjoined methods**: The opposite problem. Methods that are so tightly coupled that you cannot understand one without reading the other. They should probably be merged, or the shared logic extracted into a well-named helper.

---

## Chapter 10: Define Errors Out of Existence

Error handling is one of the greatest sources of complexity in software. The pragmatic programmer section on assertions touches this; Ousterhout goes deeper.

### The Problem with Exceptions

Exceptions are a mechanism for handling situations that the code doesn't know how to handle at the point where they occur. The problem: **exceptions are thrown in the deep module and handled in the shallow caller.** The caller must understand the internals well enough to handle the error correctly. This is a form of information leakage.

Furthermore, the number of exception handling paths in a system typically exceeds the number of happy-path flows. Each exception handler adds cognitive load and is rarely tested.

### The Strategy: Define Errors Out of Existence

The best error handling is error prevention — redesign the interface so the error cannot occur.

**Example**: Many older APIs have operations that can fail with "not found" or "already exists" errors. Modern API design eliminates these by making operations idempotent:

```
Old API:
- createUser(id, data) → throws UserAlreadyExistsException
- getUser(id) → throws UserNotFoundException

New API (define errors out of existence):
- upsertUser(id, data) → creates or updates, always succeeds
- findUser(id) → returns Optional<User>, caller handles empty case idiomatically
```

The `UserAlreadyExistsException` no longer exists. The cognitive load of handling it is gone for every caller.

**Another approach: Crash on programmer errors, recover on environmental errors**:
- If a method is called with invalid arguments (a programmer error), throw an unchecked exception or assert. The caller shouldn't be handling these — they indicate bugs.
- If an environmental condition fails (network timeout, disk full), use checked exceptions or Result types that force the caller to handle the possibility.

### Exception Masking

**Exception masking** is when a lower-level module catches an exception and handles it internally, preventing it from propagating to callers who don't need to know it happened.

Example: A TCP connection library retries automatically on transient network errors. The caller doesn't see the transient failures — they only see eventual success or eventual failure after all retries. The complexity of retry logic and transient error handling is pulled downward.

### Exception Aggregation

Instead of handling exceptions at the point they occur (which scatters handling code throughout the system), **aggregate exceptions** at a common handling point — often at the top of a request handler or a service boundary.

```java
// Scattered handling — complex
try {
    user = userService.get(userId);
} catch (UserNotFoundException e) {
    return Response.status(404).build();
}
try {
    order = orderService.create(user, items);
} catch (InsufficientInventoryException e) {
    return Response.status(409).build();
}

// Aggregated — cleaner
try {
    user = userService.get(userId);
    order = orderService.create(user, items);
    return Response.ok(order).build();
} catch (UserNotFoundException e) {
    return Response.status(404).build();
} catch (InsufficientInventoryException e) {
    return Response.status(409).build();
}
```

Even better: map all domain exceptions to HTTP status codes in a single exception mapper, and the business logic never thinks about HTTP at all.

---

## Chapter 11: Design it Twice

Before committing to a design, **design it twice** (or three times). Consider at least two different approaches to every non-trivial design problem:

- Different data structures
- Different module boundaries
- Different interface abstractions
- Different error handling strategies

Then compare them explicitly on the relevant dimensions: interface simplicity, depth (how much does it hide?), performance, testability, changeability.

**Why this works**: The first design is almost never the best design. It is the design that comes naturally from the most obvious framing of the problem. The second design forces you to escape that framing. Often the best solution is a hybrid of the two.

**At principal engineer scale**: Design it twice applies to architectural decisions, not just class design. Before committing to a microservices split, design the monolith version. Before committing to an event-driven architecture, design the synchronous version. The comparison will reveal which dimensions actually matter for your specific constraints.

> *"If you always take the first design that comes to mind, you will never see these alternatives, and you will develop an instinct for design that is limited to a narrow range of possibilities."*

---

## Chapter 12: Why Write Comments? The Four Excuses

Engineers who don't write comments typically give one of these excuses. Ousterhout refutes each:

| Excuse | Refutation |
|---|---|
| "Good code documents itself." | Code can only say *what*. It cannot say *why*. The reasoning behind design decisions — constraints, alternatives considered, non-obvious invariants — is not in the code. |
| "I don't have time to write comments." | The time you spend writing comments is repaid when the next engineer (including you, six months later) doesn't have to spend 3 hours reconstructing your reasoning. |
| "Comments get out of date." | Outdated comments are a discipline problem, not a commenting problem. Fix the root cause — treat comment updates as part of code changes. |
| "Comments are for bad code." | Comments are for knowledge that is not in the code. Even well-written code has invisible reasoning behind it. |

**The real purpose of comments**: Capture the knowledge that is not in the code — the *why*, the *what could have been*, the *what must not change*, the *invariants that aren't type-checked*.

---

## Chapter 13: Comments Should Describe Things That Aren't Obvious from the Code

The fundamental rule of commenting: **don't describe what the code does. Describe what the code doesn't say.**

### Levels of Comment Quality

**Useless (repeats the code)**:
```python
# Increment i
i += 1

# Check if user is active
if user.status == "active":
```

**Marginal (restates the interface)**:
```python
# Returns the user's email address
def get_email(user):
    return user.email
```

**Good (describes what the code can't)**:
```python
# Delay is capped at 30s to prevent thundering herd on reconnect.
# See incident post-mortem 2023-07-14 for why we chose 30s specifically.
RECONNECT_DELAY_MAX_MS = 30_000
```

```python
# We intentionally do NOT validate the token here — validation happens
# at the gateway layer. Validating twice would create a consistency risk
# if the gateway's validation logic changes.
def process_request(token, payload):
```

### The Four Types of Comments Worth Writing

1. **Interface comments**: Describe what the module provides and how to use it — not how it works.
2. **Data structure member comments**: Describe what the field represents, its units, valid ranges, and invariants.
3. **Implementation comments**: Describe *why* the code is doing something non-obvious — the constraint, the edge case, the historical reason.
4. **Cross-module comments**: Describe dependencies or contracts between modules that aren't captured in interfaces.

### What Abstract Comments Look Like

Abstract comments describe the **semantic level** of the code, not the implementation level:

```python
# BAD — mirrors the code
# Iterate over all users and find ones with the 'premium' flag set to true
premium_users = [u for u in users if u.premium]

# GOOD — describes intent and context
# Billing runs only against premium users; free users are excluded to avoid
# charging them for the base plan features they receive free of charge.
premium_users = [u for u in users if u.premium]
```

---

## Chapter 14: Choosing Names

Names are one of the highest-leverage tools for reducing complexity. A good name is a form of documentation that is automatically kept in sync with the code.

### Precision and Specificity

Names should be precise. Vague names create obscurity.

| Vague | Precise |
|---|---|
| `data` | `userProfileJson` |
| `process()` | `normalizePhoneNumber()` |
| `flag` | `isEmailVerified` |
| `result` | `paginatedOrders` |
| `temp` | `rawResponseBeforeParsing` |
| `manager` | `ConnectionPoolSupervisor` |
| `handler` | `PaymentWebhookProcessor` |

### Names Should Reveal the Abstraction Level

At the interface level, names should reveal *what*, not *how*:

```java
// Reveals implementation (how)
void writeToMySQLDatabase(Order order);

// Reveals abstraction (what)
void persist(Order order);
```

At the implementation level, names can and should reveal the mechanism:

```java
// Inside the implementation, specific names are fine
private Connection openMySQLConnection() { ... }
```

### Consistent Naming

**Consistency reduces cognitive load dramatically.** If you call it a `user` in one place, call it a `user` everywhere. If similar operations have similar names (`getUserById`, `getOrderById`, `getProductById`), the pattern is immediately recognizable.

Inconsistency creates cognitive load: *"Is `account` the same concept as `user`? When do we use `id` vs. `identifier`?"*

---

## Chapter 15: Write the Comments First

Ousterhout's most counterintuitive recommendation: **write interface comments before you write the implementation.**

### Why This Works

1. **Comments are a design tool.** Writing the comment forces you to articulate what the function does, its parameters, its return values, its exceptions. If you can't write a clear one-sentence comment describing the function, the function's design is probably wrong.

2. **The comment reveals the interface's quality.** If the comment is long, awkward, or requires many qualifications, the interface is complex. Simplify the interface until the comment is simple.

3. **Comments remain accurate.** Written alongside the code they describe (during development), not months later, comments are more likely to be correct.

### The Comment-Driven Development Workflow

1. Write the module interface comment (what does this module do?).
2. Write the interface for each method (parameters, return values, exceptions, side effects, ordering constraints).
3. Write the implementation.
4. Write implementation comments for non-obvious sections.

This workflow catches design problems before implementation begins, when they're cheapest to fix.

---

## Chapter 16: Modifying Existing Code

### The Strategic Mindset for Modifications

Every modification to existing code is an opportunity to improve the design, or to degrade it. The tactical approach: make the smallest change that makes the tests pass. The strategic approach: understand the existing design, make the change in the way that fits the design, and improve the design if the modification reveals a problem.

**The "change fits" test**: Before making a change, ask: *"Does this change feel natural in the existing design, or does it feel like a hack?"* If it feels like a hack, the design needs to change first, then the feature is added into the improved design.

### Maintaining Comments During Modification

The most important rule for code modification: **update the comments first, then the code.** This forces you to understand the existing design (by reading its documentation) before you change it, and ensures comments don't drift.

If you find comments that don't match the code, that's a bug in the comments or the code — investigate which one is wrong.

---

## Chapter 17: Consistency

Consistency is one of the highest-leverage complexity reducers available. When code is consistent:
- Patterns are recognizable
- New engineers learn faster
- Cognitive load decreases because "similar situations are handled similarly"

### What to Be Consistent About

| Domain | Consistency Rule |
|---|---|
| **Naming** | Same concept, same name everywhere |
| **Coding style** | Enforced by linter/formatter — not negotiable in code review |
| **Design patterns** | If the codebase uses the Repository pattern for data access, don't introduce DAOs |
| **Error handling** | If errors are returned as Result types, don't throw exceptions in some places |
| **Test structure** | Arrange/Act/Assert everywhere; same fixture patterns; same assertion style |
| **Logging** | Same log levels, same structured fields, same correlation ID placement |
| **API design** | Consistent URL patterns, consistent envelope format, consistent pagination |

### Documentation for Consistency

If a consistency pattern exists in your codebase that isn't obvious from reading any single file, **document it**. This is one of the highest-value uses of team documentation: capturing conventions that are invisible to a newcomer but load-bearing to the system.

---

## Chapter 18: Code Should Be Obvious

**Obviousness** is the property that lets a reader understand the code correctly without significant mental effort. Non-obvious code forces the reader to expend cognitive resources reconstructing the author's intent — and sometimes they reconstruct it incorrectly.

### What Makes Code Non-Obvious

**Event-driven code**: The flow of control is not visible by reading the code. You must know which events are fired, which handlers are registered, and in what order they execute.

**Generic containers with semantic meaning**: A `Map<String, Object>` that holds a specific set of keys with specific semantics. The caller must know what keys are valid and what types the values have — but the type system doesn't help.

**Code that violates expectations**: Code that does something surprising given its name or context. A method called `getUser()` that also creates the user if it doesn't exist.

**Code with side effects in unexpected places**: A getter that modifies state. A constructor that makes network calls. These violate the principle of least surprise.

### Techniques for Improving Obviousness

- Use types to encode constraints (a `NonEmptyList` instead of a `List` with a comment saying "don't pass empty lists")
- Keep methods short enough that the entire flow is visible at once
- Use consistent patterns (if the pattern is recognized, it requires no analysis)
- Name clearly — obvious code starts with precise names
- Write interface comments that set expectations before the reader reads the implementation

---

## Chapter 19: Software Trends

Ousterhout applies the complexity framework to evaluate several software trends:

### Object-Oriented Programming (OOP)

OOP's most valuable contribution: **information hiding**. Classes are a natural unit for hiding implementation details behind an interface.

OOP's greatest misuse: **excessive inheritance** and **shallow classes**. Inheritance creates tight coupling between superclass and subclass. Classitis (too many tiny classes) creates shallow modules everywhere.

**Verdict**: OOP is a good tool when used for information hiding. It's a source of complexity when used to create class hierarchies for their own sake.

### Agile Development

Agile development's core principle — short iterations with continuous feedback — is excellent for managing requirements uncertainty. The risk: agile cultures can create a bias toward tactical programming ("we need to ship this sprint") that accumulates complexity faster than teams can pay it down.

**Verdict**: Agile works well if teams maintain a strategic mindset within sprints. It works poorly if velocity theater overrides design quality.

### Unit Tests

Unit tests are excellent for catching regressions and enabling refactoring. The risk: **test-driven development can produce shallow, special-purpose designs** because the test drives toward the specific behavior needed, not toward the most general abstraction.

**Verdict**: Tests are essential. Design should drive tests, not the reverse. Write tests after you've found the right design, not to find the design.

### Design Patterns

Design patterns are a vocabulary for common design solutions. The risk: **patterns as cargo cult** — applying patterns because they're recognizable, not because they solve a real complexity problem.

**Verdict**: Use patterns when they reduce complexity. Every pattern has overhead (additional classes, additional indirection). That overhead is only worth paying when the pattern solves a real complexity problem that would otherwise exist.

### Getters and Setters

Getters and setters are an almost universal anti-pattern in Ousterhout's view:

1. They expose the internal data representation of a class, creating coupling to that representation.
2. They provide no abstraction — the caller must understand the internal field to use the getter.
3. They create shallow modules (many methods, no depth).

**The alternative**: Design an interface that expresses the operations the class supports, not the data it contains. Instead of `getBalance()` and `setBalance()`, provide `deposit(amount)`, `withdraw(amount)`, `getBalance()`. Now the class can change its internal representation (from a single decimal to a debit/credit ledger) without changing the interface.

### Microservices

Microservices decompose a monolith into separately deployable services. From a complexity standpoint, this is a tradeoff:

**Microservices reduce**:
- Module coupling (services communicate via versioned APIs, not shared memory)
- Deployment coupling (services can deploy independently)
- Team coupling (services have clear ownership)

**Microservices increase**:
- Interface complexity (network APIs are harder to change than method signatures)
- Operational complexity (distributed tracing, distributed transactions, service discovery)
- Testing complexity (integration testing across services is hard)

**Ousterhout's implicit verdict**: Microservices can be the right tool, but they are often adopted before the system is complex enough to justify them. Premature decomposition creates shallow services (lots of pass-through, no depth) and high coordination costs. Start with a well-modularized monolith; split when the benefits clearly outweigh the costs.

---

## Chapter 20: Designing for Performance

Performance optimization is a source of complexity. Ousterhout's approach: **measure first, optimize second, and optimize at the right level.**

### The Wrong Approach

Micro-optimizing without measurement. Adding low-level tricks (bit manipulation, loop unrolling) that complicate code for gains that may be immeasurable in the overall system.

### The Right Approach

1. **Design for performance from the start at the architectural level**: Choose the right data structures, the right algorithms, the right consistency model. These decisions matter 1000x more than micro-optimizations.

2. **Build and measure before optimizing**: You don't know where the bottleneck is until you measure. The bottleneck is almost never where intuition says it is.

3. **Optimize only the critical path**: After measurement, optimize the specific code that is actually slow. Keep the rest clean.

4. **Isolate performance-sensitive code**: Put it in a module with a clean interface. The complexity of the optimization is hidden behind the interface.

### Key Insight: Fundamental vs. Tactical Performance

**Fundamental performance decisions** (made at design time): 
- Cache results to avoid recomputation
- Reduce synchronization by designing for local state
- Choose data structures with the right access patterns
- Use bulk operations instead of row-by-row processing

These are built into the design. They don't add complexity because they change the fundamental structure.

**Tactical performance decisions** (made after measurement):
- Loop unrolling
- Inline hot functions
- SIMD intrinsics
- Lock-free data structures

These add complexity. They should be applied narrowly, documented extensively, and isolated in modules.

---

## Summary Framework: The Complexity Reduction Toolkit

| Problem | Symptom | Technique |
|---|---|---|
| **Change amplification** | Modifying one feature requires changes in 10 files | Deep modules, information hiding, eliminate pass-through |
| **Cognitive load** | Engineers can't make changes without understanding the whole system | Better abstraction, cleaner interfaces, obvious code |
| **Unknown unknowns** | Changes break things they shouldn't touch | Reduce coupling, eliminate global state, write interface comments |
| **Shallow modules** | Many small classes with trivial implementations | Merge modules, pull complexity down, generalize |
| **Information leakage** | Internal representations exposed across module boundaries | Redesign interfaces, hide data structures, use abstract types |
| **Temporal coupling** | Order of operations encoded in the caller | Pull sequencing into the module, use transactions |
| **Exception complexity** | Error handling overwhelms business logic | Define errors out of existence, mask, aggregate |
| **Naming obscurity** | Must read implementation to understand what a variable means | Precise, semantic names at the right abstraction level |
| **Comment deficit** | Reasoning behind design is invisible | Write interface comments, implementation rationale comments |

---

## Deep vs. Shallow: Application to Real Systems

### Deep Systems at FAANG Scale

| System | Deep Interface | Hidden Complexity |
|---|---|---|
| **Spanner** | SQL queries + ACID transactions | Two-phase commit, TrueTime, Paxos replication |
| **Dynamo/DynamoDB** | `Get(key)` / `Put(key, value)` | Consistent hashing, vector clocks, sloppy quorum, anti-entropy |
| **MapReduce** | `map(k,v)` / `reduce(k, [v])` | Distributed execution, fault tolerance, data locality, shuffle |
| **Kafka** | Produce / Consume with offsets | Log segmentation, ISR, leader election, replication, compaction |
| **Kubernetes** | Desired state declarations (YAML) | Reconciliation loops, scheduling, etcd, CRI, CNI |

These systems are the canonical examples of deep modules at infrastructure scale. Their interfaces are learnable in hours; their implementations are careers.

### Shallow Anti-Patterns at Scale

| Anti-Pattern | Symptom | Fix |
|---|---|---|
| Microservice per entity | 50 services, each wrapping a DB table with CRUD endpoints | Consolidate around bounded contexts |
| God object | One class that knows everything | Identify cohesive sub-domains, extract into deep modules |
| Anemic domain model | Domain objects with no behavior, all logic in services | Move behavior to domain objects |
| Leaky repository | Repository exposes query builder syntax to callers | Repository defines semantic query methods, hides query language |
| Config explosion | Module with 20 configuration parameters | Module introspects context; expose only essential params with good defaults |

---

## Applying This Book in Interviews

**"How do you think about abstraction?"**
→ Describe deep vs. shallow modules. A good abstraction hides complexity proportional to the simplicity of its interface. The goal is to minimize the knowledge a caller needs. Use Unix I/O as the canonical example.

**"How do you approach code review?"**
→ Complexity lens: Does this change amplify changes? Does it increase cognitive load? Does it create unknown unknowns? Review for interface quality (is it deep?), information hiding (what is it exposing?), and naming (is the abstraction level right?).

**"Tell me about a system you designed."**
→ Frame your design in terms of what complexity you were managing and how your module boundaries reduced it. What did each module hide? What dependencies did you eliminate?

**"How do you handle technical debt?"**
→ Distinguish between strategic investment (writing comments, improving interfaces, pulling complexity down) and tactical shortcuts (special-case flags, copy-paste, shallow wrappers). Frame tech debt as accumulated complexity that compounds — cite Ousterhout's point that even small increments of complexity are permanent.

**"How do you mentor junior engineers?"**
→ Teach the strategic vs. tactical distinction. Help engineers see that "working code" is not the goal. The goal is working code that is easy to change. Use the deep module framework to critique their designs in code review.

**"Walk me through your approach to a new design."**
→ Design it twice. Identify the natural abstraction level of the domain. Start with interface comments before implementation. Ask: "What is the simplest interface that covers all current use cases?" Evaluate depth: how much complexity does this interface hide?
