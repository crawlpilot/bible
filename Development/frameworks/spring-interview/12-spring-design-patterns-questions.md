# Spring Design Patterns — Interview Questions

---

## Fundamentals (L3–L4)

**Q1. Which design pattern does Spring AOP use?**
**Proxy pattern**. Spring creates a proxy (either JDK Dynamic Proxy or CGLIB subclass) that wraps the target bean. When a caller invokes a method, they call the proxy, which applies advice (before, after, around), then delegates to the real method. The caller is unaware of the proxy — transparent interception.

**Q2. Which design pattern is `JdbcTemplate` an example of?**
**Template Method pattern**. `JdbcTemplate` defines the algorithm skeleton: obtain connection → prepare statement → execute → handle result → release connection → handle exceptions. The varying part (the query, the row mapper, the parameters) is provided by the caller as a lambda/callback. The template handles all the boilerplate.

```java
// Template handles: connection management, statement prep, exception translation
// You provide: only the query + row mapper (the varying part)
jdbc.query("SELECT * FROM orders WHERE status = ?",
    (rs, rowNum) -> new Order(rs.getInt("id")),  // ← your custom step
    "PENDING");
```

**Q3. What is the Singleton pattern in Spring?**
The default bean scope. The Spring container creates exactly one instance per `ApplicationContext` and returns the same instance for every injection point. This is managed Singleton — not the Gang of Four Singleton (no static instance, no private constructor). The container manages the instance lifecycle.

**Q4. Which pattern does `ApplicationEventPublisher` implement?**
**Observer pattern**. The `ApplicationEventPublisher` is the subject that maintains observers (`@EventListener` methods). When `publishEvent(event)` is called, all registered listeners that handle that event type are notified. Publishers don't know about subscribers — loose coupling.

**Q5. What is the Factory pattern in Spring?**
Three levels:
1. **Factory Method**: `@Bean` method — method creates and returns an object
2. **Factory**: `BeanFactory` — creates beans on demand; production-ready object graph assembly
3. **Abstract Factory**: `FactoryBean<T>` — a Spring-managed factory that produces beans of type T

---

## Advanced (L5 Senior)

**Q6. Explain the Chain of Responsibility in Spring Security's filter chain.**
`SecurityFilterChain` is a list of `Filter` objects. Each filter:
1. Processes the request (authenticate, check CSRF, etc.)
2. Either **stops the chain** (reject with 401/403) or **passes to next** (`chain.doFilter()`)

```
Request → SecurityContextPersistenceFilter
         → UsernamePasswordAuthenticationFilter
         → BearerTokenAuthenticationFilter
         → ExceptionTranslationFilter
         → FilterSecurityInterceptor → Controller
```
Each link handles what it can; passes the rest. Adding a filter inserts a new link.

**Q7. Where is the Strategy pattern used in Spring Security?**
Multiple places:
- `AuthenticationProvider`: `DaoAuthenticationProvider` vs `JwtAuthenticationProvider` vs `LdapAuthenticationProvider` — `ProviderManager` tries each strategy
- `PasswordEncoder`: `BCryptPasswordEncoder` vs `Argon2PasswordEncoder` vs `DelegatingPasswordEncoder`
- `AccessDecisionManager`: `AffirmativeBased`, `ConsensusBased`, `UnanimousBased` — different voting strategies for authorization decisions

**Q8. How is the Decorator pattern used in `BeanPostProcessor`?**
`BeanPostProcessor.postProcessAfterInitialization()` receives the bean and can return a different object. Spring uses this to wrap beans with AOP proxies — the original bean is decorated with proxy behavior:

```java
// Spring internally does something like this:
@Override
public Object postProcessAfterInitialization(Object bean, String beanName) {
    if (hasAopAdvice(bean)) {
        return createProxy(bean);  // return decorated version
    }
    return bean;  // no advice — return original
}
```
The caller gets the decorated proxy, not the original bean. Identical to the GoF Decorator.

**Q9. What is the Composite pattern in Spring, and where is it used?**
Composite allows treating a group of objects as a single object. In Spring:
- `CompositeHealthContributor`: combines multiple `HealthIndicator` beans; `/actuator/health` shows one aggregated result
- `CompositeItemProcessor` (Spring Batch): chains `ItemProcessor` objects; input flows through all of them in sequence
- `CompositePropertySource`: multiple `PropertySource` instances accessed as one

```java
// Composite health — single call, aggregated from 3 indicators
@Bean("infrastructure")
public CompositeHealthContributor infrastructureHealth(
        DatabaseHealthIndicator db,
        KafkaHealthIndicator kafka,
        RedisHealthIndicator redis) {
    return CompositeHealthContributor.fromMap(Map.of(
        "database", db, "kafka", kafka, "redis", redis
    ));
}
```

**Q10. How does the Adapter pattern appear in Spring MVC?**
`HandlerAdapter` adapts different handler types to the `DispatcherServlet`'s uniform interface:
- `RequestMappingHandlerAdapter`: adapts `@Controller` methods
- `SimpleControllerHandlerAdapter`: adapts `Controller` interface implementations
- `HandlerFunctionAdapter`: adapts WebFlux `HandlerFunction`

`DispatcherServlet` calls `handlerAdapter.handle()` — it doesn't know which type of handler is behind it. This is exactly the Adapter pattern: converts the incompatible interface of the handler into the interface the dispatcher expects.

---

## Principal Engineer Level

**Q11. If you were designing a Spring extension point for pluggable payment providers, which pattern(s) would you use and why?**

**Recommended**: Strategy + Factory Method + Observer

```java
// Strategy — each provider is interchangeable
public interface PaymentProvider {
    String getProvider();  // "stripe", "adyen", "braintree"
    PaymentResult charge(ChargeRequest req);
    boolean supports(Currency currency);
}

// Factory — Spring collects all providers; route by name
@Service
public class PaymentRouter {
    private final Map<String, PaymentProvider> providers;

    // Spring injects ALL PaymentProvider beans automatically
    public PaymentRouter(List<PaymentProvider> providerList) {
        this.providers = providerList.stream()
            .collect(toMap(PaymentProvider::getProvider, identity()));
    }

    public PaymentResult route(String providerName, ChargeRequest req) {
        return providers.get(providerName).charge(req);
    }
}

// Observer — decouple post-payment actions
@Component
public class StripeProvider implements PaymentProvider {
    private final ApplicationEventPublisher publisher;

    @Override
    public PaymentResult charge(ChargeRequest req) {
        PaymentResult result = stripeClient.charge(req);
        publisher.publishEvent(new PaymentCompletedEvent(result));  // decouple via event
        return result;
    }
}
```

**Why this design**: New providers are added with zero modification to existing code (Open/Closed Principle). The Strategy pattern makes providers interchangeable. Auto-collection via `List<PaymentProvider>` injection eliminates manual registration. Events decouple downstream actions (audit, notification, analytics).

**Q12. How does knowing design patterns help in a system design interview?**

Patterns provide vocabulary to communicate design intent quickly:
- "I'd use a circuit breaker" (pattern name) vs "I'd detect failures and stop calling the downstream for 30 seconds" (same thing, 15 more words)
- "Use a saga pattern" immediately signals distributed transaction handling to the interviewer
- Describing your design in pattern terms signals principal-level thinking — you're generalizing from a specific solution to a class of solutions

At principal level: don't just name patterns — explain WHY that pattern's trade-offs fit this problem. "I'd use the Facade here because the underlying subsystem has 6 APIs and callers only need 2 — the facade reduces coupling and simplifies the interface."

**Q13. Design a system where the logging behavior of a Spring service can be changed at runtime without redeployment.**

Use **Strategy + Observer + Spring's dynamic capability**:
```java
// Strategy — pluggable log formatting
public interface LogStrategy {
    void log(AuditEvent event);
}

@Component("json") public class JsonLogStrategy implements LogStrategy { ... }
@Component("csv")  public class CsvLogStrategy implements LogStrategy { ... }

// Context — holds current strategy
@Service
@RefreshScope  // reloads on /actuator/refresh → picks up new strategy property
public class AuditService {
    private final LogStrategy strategy;

    public AuditService(@Value("${logging.strategy:json}") String strategyName,
                        Map<String, LogStrategy> strategies) {
        this.strategy = strategies.get(strategyName);
    }
}
```
Update `logging.strategy` in Config Server → call `/actuator/refresh` → `@RefreshScope` recreates `AuditService` with new strategy. No deployment required.

---

## Code Walkthroughs

**Q14. Identify the design pattern in this code and explain a trade-off:**
```java
@Aspect
@Component
public class CachingAspect {
    @Around("@annotation(Cacheable)")
    public Object cache(ProceedingJoinPoint pjp) throws Throwable {
        String key = generateKey(pjp);
        Object cached = cacheStore.get(key);
        if (cached != null) return cached;
        Object result = pjp.proceed();
        cacheStore.put(key, result);
        return result;
    }
}
```
**Pattern**: Proxy (AOP) + Decorator (adds caching behavior transparently). The aspect wraps every method annotated with `@Cacheable`.

**Trade-off**: Self-invocation bypass (Proxy trade-off) — if the annotated method calls another `@Cacheable` method on the same class, the inner call bypasses the aspect. Also: the AOP advice runs for every call, adding overhead even on cache hits if the cache check itself is expensive.

**Q15. What pattern is missing from this code that would make it more maintainable?**
```java
@Service
public class NotificationService {
    public void notify(String type, Order order) {
        if (type.equals("email")) {
            emailClient.send(order.getEmail(), "Order confirmed");
        } else if (type.equals("sms")) {
            smsClient.send(order.getPhone(), "Order confirmed");
        } else if (type.equals("push")) {
            pushClient.notify(order.getDeviceToken(), "Order confirmed");
        }
        // Adding WhatsApp requires modifying this method ← Open/Closed violation
    }
}
```
**Answer**: Strategy pattern. The if/else chain violates Open/Closed Principle — adding a new channel requires modifying existing code. Refactor:
```java
public interface NotificationChannel {
    String getType();
    void send(Order order, String message);
}

@Service
public class NotificationService {
    private final Map<String, NotificationChannel> channels;

    public NotificationService(List<NotificationChannel> channelList) {
        this.channels = channelList.stream()
            .collect(toMap(NotificationChannel::getType, identity()));
    }

    public void notify(String type, Order order) {
        channels.get(type).send(order, "Order confirmed");
        // Adding WhatsApp = add a new @Component implementing NotificationChannel
    }
}
```

---

## Common Mistakes

| Mistake | Understanding Gap | Correct View |
|---------|------------------|-------------|
| Thinking Spring Singleton == GoF Singleton | GoF uses static + private constructor | Spring Singleton is container-managed; testable; multiple contexts = multiple instances |
| Confusing Decorator with Proxy | "They both wrap" | Proxy: same interface, transparent; Decorator: explicit, adds features the caller can see |
| Using Template Method for everything | Over-engineering | Only when the algorithm skeleton is stable and steps vary — don't force it |
| Not recognizing Chain of Responsibility | "It's just a list of filters" | Each handler independently decides to handle or pass — that's exactly CoR |
| Naming patterns without trade-offs | Pattern namedropping | Always state: what problem it solves + what it costs |
