# 07 — Metaprogramming: Annotations, Reflection, and Proxies

**Calibration:** Principal Engineer bar  
**Focus:** Annotation processors, reflection API with module system implications, dynamic proxies, bytecode manipulation, VarHandle replacing Unsafe.

---

## 1. Annotation Fundamentals

### Defining an Annotation

```java
// Custom annotation
@Retention(RetentionPolicy.RUNTIME)   // available at runtime via reflection
@Target({ElementType.FIELD, ElementType.PARAMETER})  // where it can be placed
@Inherited                            // subclasses inherit from superclass
@Documented                           // appears in Javadoc
public @interface MaxLength {
    int value();                      // single element — can use as @MaxLength(100)
    String message() default "too long";  // with default
}
```

### `@Retention` — When Does the Annotation Exist?

| Retention | Survives compilation? | Available at runtime? | Use case |
|-----------|----------------------|----------------------|----------|
| `SOURCE` | No | No | Compile-time markers (`@Override`, `@SuppressWarnings`) |
| `CLASS` (default) | Yes (in .class) | No | Bytecode tools (e.g., FindBugs probes) |
| `RUNTIME` | Yes | Yes | Spring `@Autowired`, Jackson `@JsonProperty`, JUnit `@Test` |

**Common mistake:** Defining a custom annotation without `@Retention(RUNTIME)`. All Spring annotations (like `@Transactional`) need `RUNTIME` — if you forget, the annotation is invisible to Spring at startup.

### `@Repeatable`

```java
@Repeatable(Roles.class)  // container annotation
@Retention(RUNTIME)
@Target(ElementType.TYPE)
@interface Role { String value(); }

@Retention(RUNTIME)
@Target(ElementType.TYPE)
@interface Roles { Role[] value(); }  // container

@Role("ADMIN")
@Role("USER")    // repeatable
class SecuredController { ... }

// Reading:
Role[] roles = SecuredController.class.getAnnotationsByType(Role.class);
```

---

## 2. Annotation Processors (APT)

Annotation processors run at **compile time** — they can:
- Validate usage (emit errors/warnings).
- Generate new source files.
- Generate resource files.

They **cannot** modify existing source files (this is a key limitation — Lombok works around it via internal compiler APIs, which is why it's controversial).

### Implementing an Annotation Processor

```java
@SupportedAnnotationTypes("com.example.MaxLength")
@SupportedSourceVersion(SourceVersion.RELEASE_21)
public class MaxLengthProcessor extends AbstractProcessor {

    @Override
    public boolean process(Set<? extends TypeElement> annotations, RoundEnvironment roundEnv) {
        for (Element element : roundEnv.getElementsAnnotatedWith(MaxLength.class)) {
            // Validate: @MaxLength only valid on String fields
            if (element.getKind() == ElementKind.FIELD) {
                TypeMirror type = ((VariableElement) element).asType();
                if (!type.toString().equals("java.lang.String")) {
                    processingEnv.getMessager().printMessage(
                        Diagnostic.Kind.ERROR,
                        "@MaxLength can only be applied to String fields",
                        element
                    );
                }
            }
        }
        return true;  // claim these annotations — no further processing
    }
}
```

### Real-World APT Examples

| Tool | What it generates/validates |
|------|-----------------------------|
| **Lombok** | `@Data`, `@Builder`, `@Value` — modifies AST (controversial, internal API) |
| **MapStruct** | Type-safe mapper implementations from `@Mapper` interfaces |
| **Dagger 2** | DI graph at compile time — no reflection at runtime, zero overhead |
| **AutoValue** | Immutable value class implementations from `@AutoValue` abstract classes |
| **Immutables** | Builder + immutable class from `@Value.Immutable` annotations |

### APT Registration

Processors are registered in `META-INF/services/javax.annotation.processing.Processor`:
```
com.example.MaxLengthProcessor
```

Or with `@AutoService(Processor.class)` from Google AutoService.

---

## 3. Reflection API

### `getFields()` vs. `getDeclaredFields()`

```java
class Parent { public int pub; protected int prot; private int priv; }
class Child extends Parent { public int childPub; private int childPriv; }

// getFields(): public fields from this class AND all superclasses
Child.class.getFields()
// → [childPub, pub]  (public fields only, including inherited)

// getDeclaredFields(): ALL fields from THIS class only (no inheritance)
Child.class.getDeclaredFields()
// → [childPub, childPriv]  (all visibility, only Child's own)

// To get ALL fields including private inherited ones:
Class<?> clazz = Child.class;
while (clazz != null) {
    for (Field f : clazz.getDeclaredFields()) {
        f.setAccessible(true);  // bypass private visibility
        // use f
    }
    clazz = clazz.getSuperclass();
}
```

### `setAccessible(true)` and JPMS

In Java 8 and earlier: `field.setAccessible(true)` always works.

In Java 9+ with modules: accessing non-exported packages requires the module to either:
- Have an `opens` directive in `module-info.java`, OR
- Be opened with `--add-opens` at JVM startup.

```java
// module-info.java in the library being reflected into
module com.example.domain {
    // Only allow reflection into this package (not exporting the API):
    opens com.example.domain.model to com.example.mapper;
}
```

Without `opens`, `setAccessible(true)` throws:
```
java.lang.reflect.InaccessibleObjectException:
  Unable to make field private com.example.domain.model.Order.id accessible:
  module com.example.domain does not "opens com.example.domain.model"
  to module com.example.mapper
```

**Common breakage:** Hibernate, Jackson, Spring, Lombok all use deep reflection. Migrating to Java 17+ often reveals these errors, requiring `--add-opens` flags:

```bash
--add-opens java.base/java.lang=ALL-UNNAMED
--add-opens java.base/java.util=ALL-UNNAMED
--add-opens java.base/java.nio=ALL-UNNAMED
```

### Generic Type Tokens via `ParameterizedType`

```java
// How Jackson's TypeReference works:
abstract class TypeReference<T> {
    private final Type type;

    protected TypeReference() {
        // getGenericSuperclass() returns the parameterized form of the supertype
        // e.g., "TypeReference<List<Order>>"
        Type superclass = getClass().getGenericSuperclass();
        if (superclass instanceof ParameterizedType pt) {
            this.type = pt.getActualTypeArguments()[0];
            // type = List<Order> — preserved as a ParameterizedType
        } else {
            throw new RuntimeException("missing type parameter");
        }
    }

    public Type getType() { return type; }
}

// Usage:
new TypeReference<List<Order>>() {}  // anonymous subclass preserves the type
// type = ParameterizedType(raw=List.class, args=[Order.class])
```

---

## 4. MethodHandles and VarHandle

### `MethodHandle` — Typed, JIT-Optimizable Invocable

`MethodHandle` is a typed reference to a method. After warmup, the JIT inlines `MethodHandle.invoke()` — same performance as a direct method call.

```java
// MethodHandle for String.valueOf(int)
MethodHandles.Lookup lookup = MethodHandles.lookup();
MethodHandle mh = lookup.findStatic(String.class, "valueOf",
    MethodType.methodType(String.class, int.class));

String result = (String) mh.invoke(42);  // "42"
// After JIT warmup: direct call, no reflection overhead
```

**Lookup access control:** The `Lookup` object captures the caller's access context. A `MethodHandles.lookup()` in class A creates a lookup with A's access rights — it can access everything A can access (including private members of A).

```java
// Accessing private field via MethodHandle (within the same class)
public class Counter {
    private int count = 0;

    private static final MethodHandle COUNT_HANDLE;
    static {
        try {
            COUNT_HANDLE = MethodHandles.lookup()
                .findGetter(Counter.class, "count", int.class);
        } catch (Exception e) { throw new ExceptionInInitializerError(e); }
    }

    int getCountViaHandle(Counter c) throws Throwable {
        return (int) COUNT_HANDLE.invoke(c);
    }
}
```

### `VarHandle` (Java 9) — Atomic Field Operations

`VarHandle` provides atomic operations on fields and array elements without `sun.misc.Unsafe`:

```java
class AtomicCounter {
    private volatile int value = 0;

    private static final VarHandle VALUE;
    static {
        try {
            VALUE = MethodHandles.lookup()
                .findVarHandle(AtomicCounter.class, "value", int.class);
        } catch (Exception e) { throw new ExceptionInInitializerError(e); }
    }

    // Atomic increment (CAS loop)
    void increment() {
        int prev, next;
        do {
            prev = (int) VALUE.getVolatile(this);
            next = prev + 1;
        } while (!VALUE.compareAndSet(this, prev, next));
    }

    // Atomic get
    int get() { return (int) VALUE.getVolatile(this); }

    // Atomic set with release semantics (weaker than volatile write, stronger than plain write)
    void set(int val) { VALUE.setRelease(this, val); }
}
```

**VarHandle access modes (ordered from weakest to strongest):**
- `get` / `set` — plain (no ordering guarantee, may be reordered)
- `getOpaque` / `setOpaque` — no cross-thread ordering, but coherent per-variable  
- `getAcquire` / `setRelease` — acquire/release semantics (used for lock implementations)
- `getVolatile` / `setVolatile` — full volatile semantics (sequentially consistent)
- `compareAndSet` — atomic CAS with full volatile semantics

---

## 5. Dynamic Proxies

### JDK Dynamic Proxy — Interface Only

```java
interface PaymentService {
    PaymentResult charge(CreditCard card, Money amount);
}

// Create a retry proxy
PaymentService retryProxy = (PaymentService) Proxy.newProxyInstance(
    PaymentService.class.getClassLoader(),
    new Class<?>[]{PaymentService.class},
    new RetryInvocationHandler(realPaymentService, 3)
);

class RetryInvocationHandler implements InvocationHandler {
    private final Object target;
    private final int maxRetries;

    @Override
    public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
        int attempts = 0;
        while (true) {
            try {
                return method.invoke(target, args);   // delegate to real implementation
            } catch (InvocationTargetException e) {
                if (++attempts >= maxRetries || !isRetryable(e.getCause())) throw e.getCause();
                Thread.sleep(100L * attempts);  // exponential backoff
            }
        }
    }
}
```

**Why JDK proxy only works with interfaces:**
- `Proxy.newProxyInstance` generates a class that `implements` the specified interfaces.
- All method calls are dispatched through `InvocationHandler.invoke`.
- To proxy a class, you'd need to subclass it — JDK proxy cannot subclass.

**CGLIB (class-based proxy):** Used by Spring AOP for concrete classes. Generates a subclass at runtime that overrides all non-final methods, inserting interceptor calls. Requires that the class is not `final` and methods are not `final`.

### The Self-Invocation Problem

```java
@Service
class OrderService {
    @Transactional
    public void placeOrder(Order order) {
        // ...
        sendConfirmation(order);   // calls this.sendConfirmation — NOT through proxy!
    }

    @Transactional(propagation = REQUIRES_NEW)
    public void sendConfirmation(Order order) {
        // @Transactional here is IGNORED when called from placeOrder
        // because the call goes to the raw OrderService object, not the proxy
    }
}
```

This affects all proxy-based AOP: `@Cacheable`, `@Async`, `@Transactional`, `@Retryable`.

**Fixes:**
1. Extract `sendConfirmation` to a separate Spring bean (cleanest).
2. Inject `self` via `@Lazy @Autowired OrderService self` (ugly but common).
3. Use `AopContext.currentProxy()` to get the proxy reference (tightly coupled to Spring).

---

## 6. Bytecode Manipulation

### When Libraries Use It

| Library | What it does with bytecode |
|---------|---------------------------|
| Hibernate | Generates entity proxy subclasses for lazy loading |
| Jackson | Generates `Serializer`/`Deserializer` classes for POJO types |
| Spring (CGLIB) | Generates proxy subclasses for `@Configuration` classes |
| Mockito | Generates mock classes that intercept all method calls |
| ByteBuddy | General-purpose class generation (used by the above) |

### Byte Buddy — Class Generation

```java
// Generate a subclass that overrides toString() to log field values
Class<? extends User> generatedClass = new ByteBuddy()
    .subclass(User.class)
    .method(ElementMatchers.named("toString"))
    .intercept(MethodDelegation.to(LoggingInterceptor.class))
    .make()
    .load(User.class.getClassLoader())
    .getLoaded();

User user = generatedClass.getDeclaredConstructor().newInstance();

class LoggingInterceptor {
    @RuntimeType
    public static Object intercept(@SuperCall Callable<?> superCall,
                                   @This Object self) throws Exception {
        String original = (String) superCall.call();
        log.info("toString called: {}", original);
        return original;
    }
}
```

### Java Agents and `ClassFileTransformer`

A Java Agent runs before the application and can transform class bytes as they are loaded:

```bash
java -javaagent:/path/to/agent.jar -jar myapp.jar
```

```java
// Agent premain
public class ProfilingAgent {
    public static void premain(String args, Instrumentation inst) {
        inst.addTransformer(new ProfilingTransformer());
    }
}

class ProfilingTransformer implements ClassFileTransformer {
    @Override
    public byte[] transform(ClassLoader loader, String className, Class<?> classBeingRedefined,
                            ProtectionDomain pd, byte[] classfileBuffer) {
        // Use ASM to add timing instrumentation to every method
        // Return modified bytecode, or null to leave unchanged
        return instrumentBytecode(className, classfileBuffer);
    }
}
```

**Java agents are how async-profiler, JFR, and JVM TI tools work.**

---

## 7. JPMS and the `--add-opens` Wall

### Java 9 Module System (JPMS)

Before Java 9: all classes in the JDK were accessible via reflection.  
After Java 9: strong encapsulation. Only `opens` packages can be reflected into.

```
module java.base {
    exports java.util;          // public API — accessible
    exports java.lang;          // public API — accessible
    // java.lang.reflect.Field internals: NOT exported, NOT opened
}
```

### Framework Breakage on Java 17

Java 17 made strong encapsulation the default. Many frameworks that relied on internal JDK reflection break:

```
WARNING: An illegal reflective access operation has occurred  (Java 9–15)
ERROR: InaccessibleObjectException (Java 16+)
```

**Migration options:**

1. `--add-opens` flag at JVM startup (short-term fix):
```bash
--add-opens java.base/java.lang=ALL-UNNAMED
--add-opens java.base/java.util=ALL-UNNAMED  
--add-opens java.base/sun.nio.ch=ALL-UNNAMED  # for Netty
```

2. `opens` in `module-info.java` (module-aware libraries):
```java
module com.example.app {
    // Allow framework to reflect into this package
    opens com.example.app.model to org.springframework.core;
}
```

3. Upgrade libraries that have fixed the underlying reflection usage (the proper fix).

### Deprecation Trajectory

- Java 9–15: warnings but allowed (`--illegal-access=warn`).
- Java 16: `--illegal-access=deny` default.
- Java 17: `--illegal-access` flag removed; strong encapsulation non-negotiable without explicit `--add-opens`.
- Java 23+: `sun.misc.Unsafe` non-critical methods being deprecated.

---

## Interview Q&A

### Q1 `[Principal]` Why can't a JDK dynamic proxy work with a class? What is the CGLIB alternative, and what is the self-invocation bypass problem?

**Answer:**

**Why JDK proxy cannot proxy classes:**

`Proxy.newProxyInstance` calls `ProxyGenerator.generateProxyClass()` which generates a class that `extends java.lang.reflect.Proxy implements [target interfaces]`. It dispatches all interface method calls to the `InvocationHandler`. To proxy a concrete class, the generated proxy would need to `extend` the class — but Java has single inheritance, and the generated proxy already extends `java.lang.reflect.Proxy`.

**CGLIB alternative:**

CGLIB uses ASM bytecode manipulation to generate a subclass of the target class at runtime. It overrides every non-final, non-private method to route calls through a `MethodInterceptor`. Spring uses CGLIB for `@Configuration` classes and concrete (non-interface) beans with `@Transactional`.

```java
// Spring does this internally when you annotate a class (not interface) with @Transactional
OrderService proxy = (OrderService) Enhancer.create(
    OrderService.class,
    new TransactionInterceptor(txManager, txAttributeSource)
);
```

**The self-invocation bypass:**

When `placeOrder()` calls `this.sendConfirmation()`, `this` refers to the raw `OrderService` object — not the CGLIB proxy. The CGLIB proxy wraps the object; it is not the object. The proxy's `TransactionInterceptor` is never invoked for the inner call.

This is not a Spring bug — it's a fundamental limitation of proxy-based AOP. The proxy sits outside the object. Once you're inside the object, all `this.method()` calls bypass the proxy.

**The cleanest fix:** Extract `sendConfirmation` into a `ConfirmationService` bean. `OrderService` injects `ConfirmationService`. The call goes through the proxy as a normal bean method call.

---

### Q2 `[Principal]` `getFields()` vs. `getDeclaredFields()`. In Java 17+, when does `setAccessible(true)` throw, and what is the fix?

**Answer:**

**`getFields()`:** Returns all `public` fields of the class AND all its superclasses. Inherited public fields are included.

**`getDeclaredFields()`:** Returns ALL fields (public, protected, package-private, private) of the class itself ONLY. No inherited fields. Requires `setAccessible(true)` for private fields.

**Java 17+ `InaccessibleObjectException`:**

Thrown by `setAccessible(true)` when:
1. The field is in a module that does NOT have an `opens` directive for the package.
2. The accessing module is not the same module as the field's class.

Example that works in Java 8, fails in Java 17:
```java
// Accessing java.lang internal field from unnamed module (your application)
Field field = String.class.getDeclaredField("value");
field.setAccessible(true);  // InaccessibleObjectException in Java 17
// java.base module does not "opens java.lang" to unnamed module
```

**Fixes:**

1. JVM flag (migration path):
```bash
--add-opens java.base/java.lang=ALL-UNNAMED
```

2. `module-info.java` in your library (if you're the library author):
```java
module com.example.reflector {
    requires java.base;  // must require the module
}
// Still won't work unless java.base opens java.lang — which it doesn't
```

3. Don't reflect into JDK internals — use public APIs or `MethodHandles.privateLookupIn()` for legitimate cases:
```java
// MethodHandles.privateLookupIn: requires the module to open the package
// Only works if the module has "opens" in module-info.java
MethodHandles.Lookup lookup = MethodHandles.privateLookupIn(TargetClass.class,
    MethodHandles.lookup());
```

4. Upgrade the framework that's doing the internal reflection. Most have fixed this by Java 17.

---

### Q3 `[Principal]` Why was `VarHandle` added in Java 9 instead of continuing to use `sun.misc.Unsafe`, and what operations does it provide?

**Answer:**

**Why `Unsafe` is problematic:**

`sun.misc.Unsafe` is a JDK-internal class with:
- No access control — any code can call `Unsafe.getUnsafe()` if it passes the caller check, or get an instance via reflection.
- No type safety — `getObject(Object, long)` takes raw offset values that can be computed incorrectly.
- No module system compatibility — it's in `sun.*` (not exported), breaking in Java 9+ strong encapsulation.
- No JIT optimization guarantee — the JIT treats Unsafe calls as opaque barriers in some cases.
- Stability is undefined — internal API can change without notice.

**VarHandle provides:**

```java
// Same operations as Unsafe, but typed and access-controlled:
VarHandle vh = MethodHandles.lookup()
    .findVarHandle(MyClass.class, "field", int.class);

vh.get(obj)                  // plain read
vh.set(obj, val)             // plain write
vh.getVolatile(obj)          // volatile read
vh.setVolatile(obj, val)     // volatile write
vh.getAcquire(obj)           // acquire read (for lock implementation)
vh.setRelease(obj, val)      // release write (for lock implementation)
vh.compareAndSet(obj, expected, update)  // CAS
vh.getAndAdd(obj, delta)     // atomic fetch-and-add
vh.getAndBitwiseOr(obj, mask)  // atomic bitwise OR
```

**Access control:** `MethodHandles.lookup()` captures the calling context. A `VarHandle` for a private field of class A can only be created by code in class A — the `Lookup` enforces this.

**JIT optimization:** The JIT understands `VarHandle` operations and can generate the same machine code as direct `volatile` accesses or hardware CAS instructions. `Unsafe` sometimes prevents JIT optimization.

**Who uses VarHandle:** `java.util.concurrent` internals (e.g., `AtomicInteger` switched from `Unsafe` to `VarHandle` in Java 9), Netty (slowly migrating), high-performance libraries.

---

*See also:* [03-concurrency-and-loom.md](03-concurrency-and-loom.md) §4 for VarHandle in the Treiber stack implementation | [06-design-patterns-java-idioms.md](06-design-patterns-java-idioms.md) for the self-invocation problem in AOP
