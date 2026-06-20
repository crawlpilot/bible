# 02 — Type System and Generics

**Calibration:** Principal Engineer bar  
**Focus:** Generics semantics, variance, erasure implications, type inference evolution, reifiable types.

---

## 1. Generics Erasure

Java generics use **type erasure**: all generic type parameters are removed at compile time and replaced with their bounds (or `Object` if unbounded). The bytecode contains no generic type information.

### Why Erasure Was Chosen

Erasure was a deliberate migration-compatibility decision for Java 5 (2004). The goal: add generics without breaking existing compiled code. A `List` (raw type) and `List<String>` must be assignment-compatible for migration.

The alternative — reification (keeping type info at runtime, as .NET does) — would have required changes to the JVM itself and broken binary compatibility with all existing Java code.

### What Erasure Does

```java
// Source code
List<String> names = new ArrayList<>();
names.add("Alice");
String name = names.get(0);

// After erasure (approximate bytecode equivalent)
List names = new ArrayList();       // <String> erased → raw List
names.add("Alice");
String name = (String) names.get(0); // Compiler inserts cast
```

The cast is inserted by the compiler at the use site — this is why violations produce `ClassCastException` at the use site, not at the add site.

### Heap Pollution

When an unchecked operation causes a variable of a parameterized type to refer to an object that is not of that parameterized type:

```java
// This compiles with a warning, not an error
static <T> List<T> dangerousCast(List<?> raw) {
    return (List<T>) raw;   // @SuppressWarnings("unchecked") required
}

List<Integer> ints = List.of(1, 2, 3);
List<String> strings = dangerousCast(ints);  // No exception here
String s = strings.get(0);                   // ClassCastException HERE
// Stack trace points to this line, not to dangerousCast — confusing in production
```

**Production impact:** The `ClassCastException` appears at a location far from the source of the problem. The `@SuppressWarnings("unchecked")` annotation in a utility method conceals the bug's origin.

**Rule:** Every `@SuppressWarnings("unchecked")` must be accompanied by a proof comment explaining why the cast is safe.

---

## 2. Variance: PECS and Why It Matters

Java generics are **invariant**: `List<Dog>` is NOT a `List<Animal>`, even though `Dog` is an `Animal`.

### Why Invariance Is Correct

If `List<Dog>` were assignable to `List<Animal>` (covariance), this would compile:

```java
List<Dog> dogs = new ArrayList<>();
List<Animal> animals = dogs;    // If this were allowed...
animals.add(new Cat());         // ...this would compile and add a Cat to a Dog list
Dog d = dogs.get(0);            // ClassCastException — it's a Cat
```

Java arrays ARE covariant (`Dog[]` is-a `Animal[]`) and this exact bug is possible:

```java
Dog[] dogs = new Dog[3];
Animal[] animals = dogs;        // Compiles — arrays are covariant
animals[0] = new Cat();         // Throws ArrayStoreException at RUNTIME
```

Generics chose invariance to catch this at compile time.

### Bounded Wildcards for Flexibility: PECS

**PECS: Producer Extends, Consumer Super**

When a parameterized type is used as a **producer** (you read from it), use `? extends T` (upper bounded).  
When a parameterized type is used as a **consumer** (you write to it), use `? super T` (lower bounded).

```java
// Producer (reading from source): use extends
// "source is a List of some subtype of T"
static <T> void copy(List<? super T> dest, List<? extends T> src) {
    for (T t : src) {   // Reading from src — src must be a producer
        dest.add(t);    // Writing to dest — dest must be a consumer
    }
}

// Usage: copy integers from a List<Integer> into a List<Number>
List<Integer> ints = List.of(1, 2, 3);
List<Number>  nums = new ArrayList<>();
copy(nums, ints);   // Compiles: Number super Integer, Integer extends Number ✓
```

**Why `? extends` prevents writes:**

```java
List<? extends Number> numbers = new ArrayList<Integer>();
numbers.add(42);        // COMPILE ERROR
numbers.add(3.14);      // COMPILE ERROR
// The compiler does not know the actual type at runtime.
// It could be List<Integer> or List<Double> or List<BigDecimal>.
// Adding anything other than null is unsafe.
Number n = numbers.get(0);  // OK — reading always returns at least a Number
```

**Why `? super` prevents typed reads:**

```java
List<? super Integer> list = new ArrayList<Number>();
list.add(42);        // OK — Integer IS-A Number IS-A Object; safe to add Integer
list.add(100);       // OK
Integer i = list.get(0);   // COMPILE ERROR
// List could be List<Number>, List<Object>, etc.
// Reading only gives you Object (the common supertype of all ? super Integer)
Object o = list.get(0);    // OK — least specific type
```

---

## 3. Bounded Type Parameters

### Upper Bounded

```java
// T must be a Number or a subtype of Number
static <T extends Number> double sum(List<T> list) {
    double total = 0;
    for (T t : list) {
        total += t.doubleValue();  // doubleValue() available because T extends Number
    }
    return total;
}
```

### Multiple Bounds

```java
// T must extend Comparable AND Serializable
// First bound can be a class; subsequent bounds must be interfaces
static <T extends Comparable<T> & Serializable> T max(T a, T b) {
    return a.compareTo(b) >= 0 ? a : b;
}
```

### F-Bounded Polymorphism (Recursive Bounds)

For builder patterns that return `this` with the correct subtype:

```java
// Without F-bounds: builder returns base type, losing subtype info
interface Builder<T> {
    Builder<T> withName(String name);  // Returns Builder<T>, not ConcreteBuilder
    T build();
}

// With F-bounds: builder can return its own type
interface Builder<T, B extends Builder<T, B>> {
    B withName(String name);   // Returns B — the actual subtype
    T build();
}

class PersonBuilder implements Builder<Person, PersonBuilder> {
    private String name;
    public PersonBuilder withName(String name) { this.name = name; return this; }
    public Person build() { return new Person(name); }
}

// Enables fluent API without cast:
Person p = new PersonBuilder().withName("Alice").withAge(30).build();
//                              ^^^^^^^^^^^^^^^^^^^^^^^^^
//                              No cast needed — withName returns PersonBuilder
```

**When F-bounds break:** The bound `B extends Builder<T, B>` is not enforced transitively. A malicious subclass `EvilBuilder extends Builder<Person, PersonBuilder>` (using a different B) defeats the self-type guarantee. For true self-type safety, use an abstract `self()` method pattern.

---

## 4. Wildcard Capture

### The Problem

```java
static void swap(List<?> list, int i, int j) {
    Object temp = list.get(i);
    list.set(i, list.get(j));  // COMPILE ERROR: set requires ? type
    list.set(j, temp);         // COMPILE ERROR
}
// list.get(i) returns ?, list.set(i, ?) requires knowing ?
// The compiler tracks two separate capture variables for the two ?.
```

### The Wildcard Capture Helper Pattern

```java
// Public API uses ?
static void swap(List<?> list, int i, int j) {
    swapHelper(list, i, j);  // delegate to typed helper
}

// Private helper gives a name to the wildcard
private static <T> void swapHelper(List<T> list, int i, int j) {
    T temp = list.get(i);
    list.set(i, list.get(j));  // T is known — compiles
    list.set(j, temp);
}
```

The helper introduces a named type parameter `T` that unifies the two occurrences of `?`. The compiler captures `?` as `CAP#1` in `swapHelper`, and since both `get` and `set` use the same `T = CAP#1`, the operation is type-safe.

---

## 5. Intersection Types

A type parameter can be bounded by multiple types using `&`:

```java
// Intersection type: T must be both Runnable and Serializable
static <T extends Runnable & Serializable> void submit(T task) {
    executor.submit(task);   // uses Runnable aspect
    serialize(task);         // uses Serializable aspect
}
```

**With `var`:**
```java
var task = (Runnable & Serializable) () -> System.out.println("hello");
// task has the intersection type (Runnable & Serializable)
// Usable anywhere Runnable or Serializable is expected
```

**Limitation:** Intersection types cannot be written as local variable types without `var` (before Java 10). `Runnable & Serializable x = ...` is not valid syntax for a variable declaration — only for casts and type parameters.

---

## 6. Type Inference Evolution

### Java 7 — Diamond Operator

```java
// Before Java 7: must repeat type arguments
Map<String, List<Integer>> map = new HashMap<String, List<Integer>>();

// Java 7: diamond infers from left-hand side
Map<String, List<Integer>> map = new HashMap<>();
```

### Java 8 — Target Typing in Lambdas

```java
// The lambda's type is inferred from the expected functional interface
Comparator<String> c = (a, b) -> a.compareTo(b);
// Compiler knows Comparator<String> is expected, infers a,b are String

// Complex inference: method return type used as target type
List<String> sorted = list.stream()
    .sorted(Comparator.comparing(String::length))  // String::length inferred as Function<String,Integer>
    .collect(Collectors.toList());
```

### Java 10 — `var`

```java
var map = new HashMap<String, String>();  // infers HashMap<String, String>
```

See [01-modern-language-features.md](01-modern-language-features.md) §6 for `var` details.

### Current Inference Limits

```java
// Limit 1: var with diamond loses generics
var map = new HashMap<>();       // infers HashMap<Object, Object> — rarely intended

// Limit 2: Generic return types in chain — inference can fail
var result = Stream.of()         // Stream<Object> — empty stream
    .map(x -> x.toString());     // NPE at runtime when iterated

// Limit 3: Cannot infer type from overloaded method
var v = Collections.emptyList(); // returns List<Object>, not List<String>
// Even if v is later assigned to List<String>, the inference is already done
```

---

## 7. Reifiable vs. Non-Reifiable Types

A **reifiable type** is one whose complete type information is available at runtime. Only reifiable types can be used with `instanceof` and `new`.

| Reifiable | Non-Reifiable |
|-----------|--------------|
| `String` | `List<String>` |
| `int[]` | `List<?>` (even wildcard) |
| `List<?>` ... actually reifiable! | `List<String>` |
| `Object[]` | `T` (type parameter) |
| `Integer[]` | `T[]` (generic array) |
| raw `List` | `Map<String, Integer>` |

Wait — `List<?>` is reifiable. A wildcard `?` is a placeholder for an unknown type, but the type is "erased" to `List` at runtime in the same way — and `instanceof List<?>` is equivalent to `instanceof List` (raw). The key is unbounded wildcards lose no information vs. what's actually stored.

### Why `new T[10]` is Illegal (JLS §15.10.1)

```java
class Container<T> {
    T[] array = new T[10];  // COMPILE ERROR: generic array creation
}
```

Because:
1. Arrays are covariant and checked at runtime (via `ArrayStoreException`).
2. `T` is erased to `Object[]` at runtime.
3. `new T[10]` would create an `Object[]`, not a `T[]`.
4. If stored as `T[] array`, a caller expecting `String[]` would get an `Object[]` — heap pollution without a `ClassCastException`.

**Workaround with unchecked cast:**
```java
@SuppressWarnings("unchecked")
T[] array = (T[]) new Object[10];
// Safe only if the array never escapes the class where T is known at construction time
```

**Better workaround: use `Class<T>` token:**
```java
class Container<T> {
    private final T[] array;

    @SuppressWarnings("unchecked")
    Container(Class<T> elementType, int size) {
        array = (T[]) Array.newInstance(elementType, size);
        // Array.newInstance creates the correct runtime type: e.g., String[10]
    }
}
```

---

## 8. Raw Types and Migration Compatibility

**Raw type:** A generic type used without type parameters.

```java
List rawList = new ArrayList();   // raw type — legal but deprecated
rawList.add("hello");
rawList.add(42);                  // No type checking

String s = (String) rawList.get(1);  // ClassCastException at runtime
```

Raw types exist for backward compatibility — pre-Java 5 code that used `List` as a raw type continues to compile. All raw type operations produce "unchecked" warnings.

**The migration compatibility rule (JLS §4.8):**
- A raw type is assignment-compatible with its parameterized versions.
- But assigning a parameterized type to a raw type "infects" all operations on the raw type — you get unchecked warnings.

```java
List<String> strings = new ArrayList<>();
List raw = strings;       // legal (erases to same runtime type)
raw.add(42);              // unchecked warning — you've bypassed type safety
String s = strings.get(0);  // ClassCastException — raw.add() bypassed the check
```

**In code review:** Any raw type in non-legacy code is a red flag. The only legitimate use is `instanceof` checks (e.g., `x instanceof List`) since you can't write `x instanceof List<String>`.

---

## Interview Q&A

### Q1 `[Principal]` Why is `List<String>` not a subtype of `List<Object>`? What would go wrong if it were, and how does this contrast with arrays?

**Answer:**

If `List<String>` were a subtype of `List<Object>`, the following would be type-safe code that corrupts the list:

```java
List<String> strings = new ArrayList<>();
List<Object> objects = strings;    // if this were allowed
objects.add(42);                   // adds Integer to a List<String>
String s = strings.get(0);        // ClassCastException — it's an Integer
```

The compiler prevents this with invariance: `List<String>` and `List<Object>` are unrelated types.

**Contrast with arrays — they ARE covariant:**
```java
String[] strings = new String[3];
Object[] objects = strings;       // COMPILES — arrays are covariant
objects[0] = 42;                  // ArrayStoreException at RUNTIME
```

Arrays detect the violation at runtime via the `ArrayStoreException` mechanism — the JVM checks the component type on every array store. This is the "covariant arrays" hole from Java 1.0 that generics were designed to fix at compile time.

**The lesson:** Java has TWO different models. Arrays: covariant + runtime-checked. Generics: invariant + compile-time-checked. Generics are safer (fail earlier) but less flexible (require wildcards for covariant usage).

---

### Q2 `[Principal]` Explain the production problem with generics erasure and Jackson deserialization. What is `TypeReference` and how does it work?

**Answer:**

**The problem:**

```java
// This does NOT compile — can't take .class of a parameterized type
objectMapper.readValue(json, List<Order>.class);

// This compiles but gives you a List<LinkedHashMap>, not List<Order>
List<Order> orders = objectMapper.readValue(json, List.class);
// Each element is a LinkedHashMap because Jackson erased List<Order> → List
```

**Why:** `Class<T>` tokens are erased. `List<Order>.class` doesn't exist at runtime — only `List.class` does.

**The `TypeReference` workaround:**

```java
List<Order> orders = objectMapper.readValue(json,
    new TypeReference<List<Order>>() {});
```

`TypeReference<List<Order>>` is an anonymous subclass. Its **superclass** is `TypeReference<List<Order>>`. The JVM stores the generic superclass type in the class file metadata. The trick: `getClass().getGenericSuperclass()` returns a `ParameterizedType` that includes `List<Order>` — the type arguments are preserved because they're part of the *class definition*, not a local variable declaration.

```java
// TypeReference implementation (simplified)
abstract class TypeReference<T> {
    protected final Type type;
    TypeReference() {
        // getGenericSuperclass() returns "TypeReference<List<Order>>"
        this.type = ((ParameterizedType)
            getClass().getGenericSuperclass()).getActualTypeArguments()[0];
        // type = List<Order> — preserved because it's in the class's supertype definition
    }
}
```

This is a compile-time trick: the type argument `List<Order>` is hardcoded in the anonymous class's supertype, which is NOT erased (class metadata preserves supertype arguments for reflection).

---

### Q3 `[Principal]` What is wildcard capture conversion, and when do you need the wildcard capture helper pattern?

**Answer:**

**Capture conversion:** When the compiler encounters `List<?>`, it internally creates a fresh type variable `CAP#1` for the unknown element type. This is "capture conversion" (JLS §5.1.10).

Two separate `List<?>` expressions get **different** capture variables:

```java
void bad(List<?> list) {
    list.set(0, list.get(0));  // COMPILE ERROR
    // list.get(0) returns CAP#1
    // list.set(0, ?) requires CAP#2
    // CAP#1 ≠ CAP#2 — compiler can't prove they're the same type
}
```

**Why the helper pattern fixes it:**

```java
void good(List<?> list) {
    copyHelper(list);  // delegate
}

<T> void copyHelper(List<T> list) {
    T elem = list.get(0);   // T
    list.set(0, elem);      // T — same type variable, compiles!
}
```

In `copyHelper`, the type variable `T` is a single named capture. Both `get` and `set` use the same `T`, so the compiler can verify type safety.

**When you need it:**
- Any operation that requires reading from and writing to the same `List<?>`.
- "Collections.swap" is the canonical example.
- In practice: you need the helper when you call a method on `List<?>` that has the wildcard in both argument and return type positions.

---

### Q4 `[Principal]` Why is `new T[10]` illegal in Java? What are two safe workarounds with different trade-offs?

**Answer:**

**Why illegal (JLS §15.10.1):**

Arrays are reifiable — they carry their component type at runtime and verify stores via `ArrayStoreException`. `T` is erased to `Object` at runtime. If `new T[10]` were allowed:
1. The runtime would create an `Object[10]` (since `T` is erased).
2. If `T = String`, the code would store this as `String[]`.
3. A caller passing a `String[]` reference to a method that stores a `Dog` would not get an `ArrayStoreException` (the array thinks it's `Object[]`).
4. Heap pollution without any error — a `String[]` that contains `Dog` objects.

**Workaround 1: Unchecked cast**
```java
@SuppressWarnings("unchecked")
T[] array = (T[]) new Object[10];
```

Safe IF: the array never escapes the generic class. If returned as `T[]` from a public API, the caller might cast it to `String[]` — ClassCastException.

**Workaround 2: `Array.newInstance` with `Class<T>` token**
```java
@SuppressWarnings("unchecked")
T[] array = (T[]) Array.newInstance(elementType, 10);
// elementType: Class<T> passed to constructor
```

Creates a real `String[10]` (or whatever `T` is) at runtime. Safe to return as `T[]` from public API because the runtime type is correct. Trade-off: requires an extra `Class<T>` parameter threaded through the API.

**Modern alternative:** Use `ArrayList<T>` instead. The array-backed list holds `Object[]` internally and manages casts safely. Only use generic arrays when you absolutely need array semantics (e.g., implementing a collection type from scratch).

---

*See also:* [01-modern-language-features.md](01-modern-language-features.md) §3 for sealed classes as type-system feature | [04-data-structures-internals.md](04-data-structures-internals.md) for how erasure affects HashMap and Collection internals
