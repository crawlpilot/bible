# 01 — Modern Java Language Features (Java 8–24)

**Calibration:** Principal Engineer interview bar — Google / Meta / Amazon  
**Cross-references:** [02-java-best-practices.md](../../Development/best-practices/02-java-best-practices.md) owns coding standards and Optional discipline. This file owns language semantics and internals.

---

## Java Version Feature Timeline

| Feature | JEP | Introduced | Finalized | Production-Safe Since |
|---------|-----|-----------|-----------|----------------------|
| Lambda + Streams | — | Java 8 | Java 8 | Java 8 |
| `var` (LVTI) | JEP 286 | Java 10 | Java 10 | Java 11 (LTS) |
| Text Blocks | JEP 378 | Java 13 preview | Java 15 | Java 17 (LTS) |
| Records | JEP 395 | Java 14 preview | Java 16 | Java 17 (LTS) |
| Sealed Classes | JEP 409 | Java 15 preview | Java 17 | Java 17 (LTS) |
| Switch Expressions | JEP 361 | Java 12 preview | Java 14 | Java 17 (LTS) |
| Pattern Matching `instanceof` | JEP 394 | Java 14 preview | Java 16 | Java 17 (LTS) |
| Pattern Matching Switch | JEP 441 | Java 17 preview | Java 21 | Java 21 (LTS) |
| Sequenced Collections | JEP 431 | — | Java 21 | Java 21 (LTS) |
| Virtual Threads | JEP 444 | Java 19 preview | Java 21 | Java 21 (LTS) |
| Structured Concurrency | JEP 480 | Java 21 preview | Java 23 preview | Not yet finalized |
| Scoped Values | JEP 481 | Java 21 preview | Java 23 preview | Not yet finalized |
| String Templates | JEP 430 | Java 21 preview | Java 23 preview | Not yet finalized |
| Unnamed Classes | JEP 463 | Java 21 preview | Java 23 preview | Not yet finalized |
| Value Types (Valhalla) | JEP 401 | Java 23 preview | TBD | Not yet finalized |

---

## 1. Text Blocks (Java 15 Final)

Text blocks eliminate the escaping ceremony of multi-line string literals. The critical interview topic is not the syntax — it's the **indentation-stripping algorithm**.

### Indentation Algorithm

```java
String json = """
        {
          "name": "Alice",
          "age": 30
        }
        """;
```

The algorithm:
1. Compute the **common whitespace prefix** across all non-blank content lines AND the closing `"""` line.
2. Strip that prefix from every line.
3. The closing `"""` position controls trailing whitespace. If `"""` is on its own line, the prefix is determined partly by its indentation.

```
Line content after prefix strip:
  "        {\n" → "{\n"         (8 spaces stripped)
  "          \"name\"..." → "  \"name\"..."  (8 spaces stripped, 2 remain)
```

**Escape sequences unique to text blocks:**

```java
String noNewline = """
        line one \
        line two
        """;
// Result: "line one line two\n"  — \<newline> joins lines

String preserveSpaces = """
        trailing   \s
        """;
// \s is an explicit space — prevents stripping of trailing whitespace
```

### Interview Gotcha

```java
// These produce DIFFERENT strings
String a = """
    hello
    """;          // "hello\n" — closing """ at 4-space indent, content at 4 spaces → stripped

String b = """
    hello
""";              // "    hello\n" — closing """ at 0 indent → 0 prefix stripped
```

---

## 2. Records (Java 16 Final)

Records are transparent data carriers. They auto-generate: canonical constructor, component accessors, `equals`, `hashCode`, `toString`. What interviewers actually ask about is what records *cannot* do and the semantics they enforce.

### What a Record Generates

```java
public record Point(int x, int y) {}

// Equivalent to:
public final class Point {
    private final int x;
    private final int y;

    public Point(int x, int y) {  // canonical constructor
        this.x = x;
        this.y = y;
    }

    public int x() { return x; }  // component accessors (NOT getX())
    public int y() { return y; }

    @Override public boolean equals(Object o) { ... }  // structural equality
    @Override public int hashCode() { ... }
    @Override public String toString() { ... }
}
```

### Compact Constructor — What It Cannot Do

The compact constructor does NOT receive parameters — it has access to the mutable component variables directly. Three hard restrictions:

```java
public record Range(int lo, int hi) {
    // Compact constructor — validates and normalizes
    Range {
        if (lo > hi) throw new IllegalArgumentException("lo > hi");
        // ✓ Can modify component variables before assignment:
        lo = Math.max(0, lo);   // normalize negative lo

        // ✗ Cannot explicitly assign this.lo = lo; (done automatically after body)
        // ✗ Cannot call this(other, args); (no delegation to another constructor)
        // ✗ Cannot add new parameters
    }
}
// After the body exits, the JVM does: this.lo = lo; this.hi = hi;
```

### Record Patterns (Java 21)

Records compose with pattern matching — the most powerful use case:

```java
sealed interface Shape permits Circle, Rectangle, Triangle {}
record Circle(double radius) implements Shape {}
record Rectangle(double width, double height) implements Shape {}
record Triangle(double base, double height) implements Shape {}

static double area(Shape s) {
    return switch (s) {
        case Circle(double r)               -> Math.PI * r * r;
        case Rectangle(double w, double h)  -> w * h;
        case Triangle(double b, double h)   -> 0.5 * b * h;
        // No default needed — sealed hierarchy is exhaustive
    };
}
```

Nested record patterns:

```java
record Point(double x, double y) {}
record Line(Point start, Point end) {}

static boolean isHorizontal(Line line) {
    return switch (line) {
        case Line(Point(_, double y1), Point(_, double y2)) -> y1 == y2;
    };
}
```

### Serialization Pitfall

Records use their canonical constructor during deserialization (unlike regular classes which bypass constructors via `Unsafe`). This means validation in the compact constructor runs on deserialization — a feature, but it means a serialized `Range(-5, 10)` that normalized `lo` to `0` will deserialize as `Range(0, 10)` with the original `-5` lost.

---

## 3. Sealed Classes and Interfaces (Java 17 Final)

Sealed types are a compile-time constraint: only the listed subtypes are permitted. The killer feature is **exhaustiveness** — the compiler knows the complete set of subtypes and can verify switch completeness.

```java
public sealed interface Expr
    permits Num, Add, Mul, Neg {}

public record Num(int value)         implements Expr {}
public record Add(Expr l, Expr r)    implements Expr {}
public record Mul(Expr l, Expr r)    implements Expr {}
public record Neg(Expr expr)         implements Expr {}
```

### Exhaustiveness Enforcement

```java
static int eval(Expr e) {
    return switch (e) {
        case Num(int v)       -> v;
        case Add(Expr l, Expr r) -> eval(l) + eval(r);
        case Mul(Expr l, Expr r) -> eval(l) * eval(r);
        case Neg(Expr inner)  -> -eval(inner);
        // No default — compiler verifies all 4 subtypes are covered
        // Adding a new subtype to Expr forces a compile error here
    };
}
```

Without sealed, adding a `Div` subtype would silently miss the switch. With sealed, you get a compile error, forcing you to handle it.

### Permitted Subtype Rules

- Permitted subtypes must be in the same package (or same module).
- Permitted subtypes must directly extend/implement the sealed type.
- Each permitted subtype must be `final`, `sealed`, or `non-sealed`.
  - `non-sealed`: reopens the hierarchy for that branch — useful for extension points.

```java
public sealed interface Notification permits PushNotification, EmailNotification {}
public record PushNotification(String token, String body) implements Notification {}
public non-sealed class EmailNotification implements Notification {}
// EmailNotification can be subclassed freely — it breaks the seal for that branch
```

---

## 4. Switch Expressions (Java 14) + Pattern Matching Switch (Java 21)

### Switch Expressions

Pre-Java 14 switch was a statement with fall-through semantics. Java 14 finalized switch as an **expression** that produces a value.

```java
// Old: statement, fall-through, verbose
String result;
switch (day) {
    case MONDAY: case TUESDAY: case WEDNESDAY: case THURSDAY: case FRIDAY:
        result = "Weekday"; break;
    case SATURDAY: case SUNDAY:
        result = "Weekend"; break;
    default: throw new IllegalArgumentException();
}

// New: expression, arrow syntax, no fall-through
String result = switch (day) {
    case MONDAY, TUESDAY, WEDNESDAY, THURSDAY, FRIDAY -> "Weekday";
    case SATURDAY, SUNDAY -> "Weekend";
};  // Compiler verifies exhaustiveness for enums
```

`yield` for multi-statement cases:

```java
int x = switch (code) {
    case 1 -> 100;
    case 2 -> {
        log("special case");
        yield 200;  // yield, not return
    }
    default -> 0;
};
```

### Pattern Matching Switch (Java 21)

Combines switch with type patterns and record patterns:

```java
static String format(Object obj) {
    return switch (obj) {
        case Integer i when i < 0    -> "negative int: " + i;
        case Integer i               -> "positive int: " + i;
        case String s when s.isEmpty() -> "empty string";
        case String s                -> "string: " + s;
        case null                    -> "null";  // explicit null handling
        default                      -> "other: " + obj;
    };
}
```

**Ordering rules:** More specific patterns must precede more general ones. Guarded patterns (`when`) come before the unguarded version of the same type pattern. The compiler enforces this.

**Null handling:** Classic switch throws NPE on null selector. Pattern matching switch can explicitly handle `null` with a `case null` arm.

---

## 5. Pattern Matching for `instanceof` (Java 16)

Eliminates the cast-after-check boilerplate:

```java
// Old
if (obj instanceof String) {
    String s = (String) obj;
    System.out.println(s.length());
}

// New
if (obj instanceof String s) {
    System.out.println(s.length());  // s is in scope here
}
```

### Scope Rules for Pattern Variables

The pattern variable's scope is the **intersection of definitely-assigned regions** — not a fixed syntactic scope.

```java
// Pattern variable flows into &&
if (obj instanceof String s && s.length() > 3) {
    // s is in scope — short-circuit && ensures instanceof succeeded
}

// Pattern variable does NOT flow into ||
if (obj instanceof String s || true) {
    // s is NOT in scope here — || could bypass the instanceof check
}

// Negation flips scope
if (!(obj instanceof String s)) {
    // s is NOT in scope in the true branch
} else {
    // s IS in scope in the else branch (instanceof must have succeeded)
}
```

---

## 6. `var` — Local Variable Type Inference (Java 10)

`var` instructs the compiler to infer the type from the right-hand side. It is **not** dynamic typing — the type is fixed at compile time.

### Prohibited Contexts

```java
// ✗ Field declarations
private var count = 0;          // compile error

// ✗ Method parameters
void process(var item) {}       // compile error

// ✗ Return types
var getCount() { return count; } // compile error

// ✗ Without initializer
var x;                          // compile error (can't infer)

// ✗ Null initializer
var x = null;                   // compile error (null has no type)
```

### Production Bug Pattern

```java
// Developer intends List<String>, gets ArrayList<String>
var list = new ArrayList<String>();
list.trimToSize();  // Compiles — ArrayList method, no IDE warning
                    // If list is passed to a method expecting List<String>,
                    // callers won't notice it's actually ArrayList

// More insidious: diamond operator loses type
var map = new HashMap<>();       // infers HashMap<Object, Object>
map.put("key", "value");        // OK
String v = map.get("key");      // ClassCastException at runtime — map is <Object, Object>
// Fix: var map = new HashMap<String, String>();
```

### When `var` Wins

```java
// Long generic types — readability improvement
var entries = Map.<String, List<Integer>>of("a", List.of(1, 2));

// Iteration — the inferred type is obvious from context
for (var entry : map.entrySet()) {
    // entry is Map.Entry<K,V> — inferred correctly
}

// try-with-resources — type is obvious from the factory method name
try (var conn = dataSource.getConnection();
     var stmt = conn.prepareStatement(sql)) { ... }
```

---

## 7. String Templates (Java 21 Preview / Java 23 Second Preview)

String templates provide interpolation with custom processing. Crucially, the language requires a **template processor** — you cannot just use `${}` directly, because raw string interpolation enables injection attacks.

### Template Processor Protocol

```java
// STR is the standard interpolation processor
String name = "Alice";
String greeting = STR."Hello, \{name}!";  // "Hello, Alice!"

// FMT is like printf-style formatting
double price = 9.99;
String formatted = FMT."Price: %.2f\{price}";  // "Price: 9.99"

// RAW returns a StringTemplate, not a String — for custom processing
StringTemplate template = RAW."SELECT * FROM users WHERE id = \{userId}";
```

### Custom Processor — The Real Power

The reason for requiring a processor: each processor decides how to handle the values. A SQL-safe processor can use parameterized queries:

```java
// A safe SQL processor
static final StringTemplate.Processor<PreparedStatement, SQLException> SQL =
    template -> {
        String query = template.interpolate();  // naive — DO NOT use for SQL
        // Better: use fragments + values separately
        var fragments = template.fragments();   // ["SELECT * FROM t WHERE id = ", ""]
        var values = template.values();         // [42]
        PreparedStatement ps = conn.prepareStatement(
            String.join("?", fragments));
        for (int i = 0; i < values.size(); i++) {
            ps.setObject(i + 1, values.get(i));
        }
        return ps;
    };

PreparedStatement ps = SQL."SELECT * FROM users WHERE id = \{userId}";
// userId is bound as a parameter, never interpolated into the SQL string
```

### Why Not Finalized Yet

After two preview rounds, the design questions blocking finalization:
1. Should `STR.` be in-language syntax (like `f""` in Python) or stay a library-based processor?
2. Security: if `STR.` becomes the default idiom, developers stop thinking about injection; the mandatory processor model forces the question.
3. Template processor API complexity — allowing i18n, SQL, HTML processors with correct behavior requires careful API design.
4. Performance: compile-time vs. runtime processing of templates.

---

## 8. Value Types — Project Valhalla (Java 23 Preview)

Project Valhalla addresses the **performance gap between primitives and objects**. In classic Java, `List<Integer>` boxes each `int` into a heap-allocated `Integer` object — cache-hostile pointer chasing.

### JEP 401 Status (Java 23)

Value classes (also called primitive classes) are declared with `value`:

```java
value class Point {
    private final double x;
    private final double y;

    Point(double x, double y) {
        this.x = x;
        this.y = y;
    }
}
```

**Semantics of value classes:**
- No identity — two `Point(1.0, 2.0)` instances are interchangeable.
- Cannot be `null` — null-restricted by default (an `int` is never null).
- Cannot synchronize — no monitor (no identity = no lock).
- Stored by value, not by reference — `Point[]` is a flat array of doubles, not a pointer array.

```java
// With Valhalla:
List<Point> points = new ArrayList<>();  // ArrayList<Point> stores Points inline
// No boxing! Each Point is stored as two adjacent doubles in the array.
// This eliminates the cache miss from pointer-chasing Integer[] to Integer objects.
```

### Why This Matters for FAANG Interviews

The GC pressure from boxed collections is a common performance bottleneck:
- A `Map<Long, Long>` with 10M entries: 10M `Long` objects × 16 bytes each = 160MB extra heap.
- Valhalla makes `Map<long, long>` viable — no boxing, no GC pressure.
- Java becomes competitive with C++ and Go for number-crunching workloads.

---

## 9. Sequenced Collections (Java 21)

A 27-year gap in the Java Collections API: no single type represented "a collection with a well-defined encounter order."

### The Gap

```java
// Before Java 21: No consistent API for first/last element
LinkedHashMap<K,V> map = ...;
K first = map.keySet().iterator().next();  // verbose, allocates Iterator
K last  = ...;  // no clean way without iterating to the end

List<E> list = ...;
E last = list.get(list.size() - 1);  // works for List, not for others
```

### The Solution

Three new interfaces inserted into the hierarchy:

```java
interface SequencedCollection<E> extends Collection<E> {
    SequencedCollection<E> reversed();
    void addFirst(E);
    void addLast(E);
    E getFirst();
    E getLast();
    E removeFirst();
    E removeLast();
}

interface SequencedSet<E> extends Set<E>, SequencedCollection<E> {
    SequencedSet<E> reversed();
}

interface SequencedMap<K,V> extends Map<K,V> {
    SequencedMap<K,V> reversed();
    Map.Entry<K,V> firstEntry();
    Map.Entry<K,V> lastEntry();
    // ...
}
```

Now `LinkedHashMap`, `LinkedHashSet`, `ArrayList`, `Deque`, `SortedSet`, `SortedMap` all implement the appropriate sequenced interface.

### Why It Was Hard to Add

- Retrofitting required `default` method implementations for all existing implementations without breaking them.
- Name conflicts: some collections already had methods with conflicting signatures (e.g., `Deque` has `addFirst`/`addLast` but with different generic types).
- The `reversed()` method must return a view (not a copy) — implementing this for every collection required careful default implementations.

---

## Interview Q&A

### Q1 `[Principal]` Records were finalized in Java 16, pattern matching switch in Java 21. How do sealed classes and record patterns compose together, and what does exhaustiveness checking give you that wasn't possible before?

**Answer:**

Sealed classes give the compiler a **closed, statically known** set of permitted subtypes. Record patterns give the compiler a way to **destructure** those subtypes in a switch case. Together, they form a type-safe discriminated union (sum type) with structural decomposition.

Before Java 21: you could use `instanceof` chains or visitor pattern, but neither was checked exhaustive. Adding a new subtype silently skipped existing switches.

After Java 21:
```java
sealed interface Result<T> permits Success, Failure {}
record Success<T>(T value) implements Result<T> {}
record Failure<T>(String error, Throwable cause) implements Result<T> {}

static <T> void handle(Result<T> r) {
    switch (r) {
        case Success<T>(T val)            -> process(val);
        case Failure<T>(String msg, _)    -> log(msg);
        // No default needed — compiler verifies all 2 subtypes covered
        // Adding Result.Pending requires updating this switch or compile error
    }
}
```

**What exhaustiveness gives you:**
- Adding `Pending` to the `permits` clause causes a compile error at every switch that doesn't handle it.
- The "shotgun surgery" problem (forgetting to update one of N switch statements) becomes a compile-time failure instead of a production bug.
- This is the Java equivalent of Haskell/Scala's exhaustive pattern matching.

---

### Q2 `[Principal]` What are the three things a compact constructor in a record cannot do that a canonical constructor can?

**Answer:**

1. **Cannot explicitly assign `this.field = value`** — in a compact constructor, the component variables (`x`, `y`, etc.) are mutable pre-assignment locals. After the compact constructor body exits, the JVM automatically assigns `this.x = x; this.y = y;`. You cannot write `this.x = x;` inside the body — it's already implied.

2. **Cannot call `this(...)` to delegate to another constructor** — canonical constructors can have overloads and delegate with `this(a, b)`. Compact constructors cannot: they *are* the canonical constructor and there is no "other" canonical constructor to delegate to.

3. **Cannot add constructor parameters** — a compact constructor inherits the same parameter list as the canonical constructor (the record components). You cannot add a `boolean validate` parameter to a compact constructor.

```java
record NonNegativeInt(int value) {
    NonNegativeInt {  // compact constructor
        if (value < 0) throw new IllegalArgumentException();
        value = Math.abs(value);  // ✓ normalize — assigned to this.value after body
        // this.value = value;    ✗ compile error
        // this(Math.abs(value)); ✗ no delegation
    }
}
```

---

### Q3 `[Principal]` When does `var` introduce a production bug, and give a concrete example?

**Answer:**

The bug class: `var` infers a **more concrete type** than the developer intended, exposing API surface that should be hidden, or inferring `Object` when a specific type is expected.

**Concrete example — diamond operator type erasure:**

```java
// Developer writes
var map = new HashMap<>();
map.put("userId", "alice");

// Compiler infers: HashMap<Object, Object>
// Not: HashMap<String, String>

// Later in code:
String userId = map.get("userId");  // ClassCastException at runtime
// map.get() returns Object, implicit downcast fails silently
```

Fix: `var map = new HashMap<String, String>();`

**Concrete example — ArrayList instead of List:**

```java
var cache = new ArrayList<String>();
cache.trimToSize();   // compiles — ArrayList method, fine locally
// But now the type is leaked in the method signature if cache is returned:
// The calling code now depends on ArrayList, not List
// If you later change to LinkedList, the call site breaks
```

**Rule of thumb:** Use `var` when the type is obvious from the right-hand side (constructor, cast, factory method name). Avoid with diamond operator alone.

---

### Q4 `[Principal]` Explain the text block indentation algorithm. What exactly determines how much whitespace is stripped, and what is the edge case with the closing `"""`?

**Answer:**

The algorithm is defined in JLS 3.10.6. Two concepts: **incidental whitespace** (leading whitespace that is an artifact of indentation) vs. **essential whitespace** (semantically meaningful).

**Stripping algorithm:**
1. Split the content into lines.
2. Find the **minimum indentation** among: all non-blank content lines + the closing `"""` line (if it's on its own line).
3. Strip exactly that many leading whitespace characters from every line.

**Closing `"""` edge case:**

```java
// Case 1: closing """ is indented (common)
String s = """
        Hello
        World
        """;
// Closing """ has 8 spaces, content lines have 8 spaces.
// Min indent = 8. Result: "Hello\nWorld\n"

// Case 2: closing """ is at column 0
String s = """
        Hello
        World
""";
// Closing """ has 0 spaces. Min indent = 0. Nothing stripped.
// Result: "        Hello\n        World\n"

// Case 3: closing """ is more indented than content
String s = """
    Hello
        """;   // 8 spaces, but content only has 4
// Min indent = 4 (content wins). Result: "Hello\n"
```

The key insight: the closing `"""` position is used to **contribute** to the minimum — it allows you to control stripping by moving the closing delimiter left or right.

---

### Q5 `[Principal]` String Templates are in their second preview round. What specific design questions have prevented finalization?

**Answer:**

Three open issues after two preview rounds:

**1. The `STR.` proliferation risk:**
If `STR."Hello \{name}"` becomes the everyday idiom, developers will use it for SQL, HTML, shell commands — creating injection vulnerabilities. The mandatory processor model forces you to think about the processing context, but `STR.` is still available as the default. There is debate about whether `STR.` should be harder to reach or renamed to signal "dumb interpolation."

**2. API surface of `StringTemplate`:**
The `StringTemplate` interface exposes `fragments()` (list of literal string parts) and `values()` (list of interpolated values). The question is whether this API is the right primitive for all processors, or whether some processors need richer compile-time information (e.g., type of each interpolated value for a type-safe SQL binder).

**3. Compile-time vs. runtime processing:**
Most template processors run at runtime. But `FMT.` style processors could theoretically be optimized at compile time if the format string is a constant. The current design doesn't allow compile-time processors. Some stakeholders want a path to constant-folding template expressions.

**4. Interaction with records and pattern matching:**
A template processor that produces a structured type (e.g., a `Query` record) rather than a `String` requires careful typing. The `Processor<R, E>` signature handles this but it creates a proliferation of processor types in library APIs.

---

### Q6 `[Principal]` What is the status of Project Valhalla as of Java 23, and how does it change the performance model for Java generics?

**Answer:**

**Current status:** JEP 401 (Value Classes) is in preview in Java 23. The full vision ("universal generics" allowing `List<int>`) requires additional JEPs that are not yet in preview.

**Current limitation:** Even with JEP 401, you cannot write `List<Point>` and have `Point` stored inline in the list's backing array. That requires generic specialization (separate JEP, later work).

**How it changes the performance model when complete:**

Classic Java:
```
List<Integer>: Object[] array → pointer → Integer object on heap
Cache behavior: each element access = 2 memory fetches (array slot + object)
GC cost: N Integer objects in Old Gen, each with header overhead
```

With Valhalla (full):
```
List<int>: int[] backing (specialized)
Cache behavior: 1 memory fetch (array slot contains the value inline)
GC cost: zero — primitives are not GC'd objects
```

**For interviews:** The key insight is that Java's generics use erasure + boxing, making `List<Integer>` 3–5× slower than `int[]` for bulk operations. Valhalla eliminates this by allowing the JIT to specialize the generic bytecode for each primitive type — similar to C++ templates or .NET's reified generics.

---

### Q7 `[Principal]` Sequenced Collections filled a 27-year API gap. What was missing, and why was it hard to retrofit?

**Answer:**

**What was missing:** No single type in `java.util` represented "a collection with a well-defined encounter order that you can efficiently access from both ends." Specifically:
- `List` has first/last by index but is not a `Set`.
- `Deque` has `peekFirst`/`peekLast` but extends `Queue`, not `Collection`.
- `LinkedHashSet` has insertion order but no accessor for first/last without iterator.
- `SortedSet` has `first()`/`last()` but is sorted, not insertion-ordered.

No interface unified these — you had to know the concrete type.

**Why hard to retrofit (3 reasons):**

1. **Name conflicts:** `Deque` already defined `addFirst(E)` and `addLast(E)`. The new `SequencedCollection` interface needed the same method names but with slightly different contract implications. Required careful coordination so `Deque` could implement `SequencedCollection` without conflict.

2. **`reversed()` return type covariance:** Each implementing class needs `reversed()` to return a view of its own type (e.g., `LinkedHashSet.reversed()` returns a `LinkedHashSet` view, not just a `SequencedSet`). This required `default` implementations in the interface plus overrides in each concrete class.

3. **Hierarchy diamond:** `LinkedHashMap` implements both `SequencedMap` and inherits from `HashMap` which implements `Map`. Inserting `SequencedMap` into the hierarchy without ambiguity required careful default method resolution — some methods needed to be explicitly defaulted to prevent multiple-inheritance conflicts.

---

*See also:* [02-type-system-and-generics.md](02-type-system-and-generics.md) for how sealed classes interact with the type system | [03-concurrency-and-loom.md](03-concurrency-and-loom.md) for Virtual Threads and Structured Concurrency deep-dive
