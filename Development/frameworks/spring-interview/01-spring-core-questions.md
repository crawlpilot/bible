# Spring Core — Interview Questions

---

## Fundamentals (L3–L4)

**Q1. What is Inversion of Control (IoC)?**
IoC means the framework manages object creation and dependency wiring instead of the application code. Instead of `new Service()`, you declare dependencies and the container injects them. This inverts the traditional control flow: you don't call the framework, the framework calls you.

**Q2. What is the difference between `BeanFactory` and `ApplicationContext`?**
- `BeanFactory`: core container, lazy bean initialization, minimal features
- `ApplicationContext`: extends `BeanFactory`, adds eager singleton init, `@Autowired`, i18n messages, event publishing, AOP support
- Use `ApplicationContext` always; `BeanFactory` is for memory-constrained environments (embedded, now rarely relevant)

**Q3. What are the bean scopes in Spring?**
`singleton` (default), `prototype`, `request`, `session`, `application`, `websocket`. For web apps, `request` and `session` create new beans per HTTP request/session. `prototype` creates a new instance per `getBean()` call.

**Q4. What are the three types of dependency injection?**
1. Constructor injection (recommended — immutable, testable, non-null)
2. Setter injection (optional dependencies)
3. Field injection (avoid — hides dependencies, breaks testability)

**Q5. What is the bean lifecycle order?**
1. Instantiation (constructor)
2. Dependency injection (setter/field)
3. `BeanPostProcessor.postProcessBeforeInitialization()`
4. `@PostConstruct` method
5. `InitializingBean.afterPropertiesSet()`
6. Custom `init-method`
7. `BeanPostProcessor.postProcessAfterInitialization()` (AOP proxy created here)
8. Bean ready for use
9. `@PreDestroy` (on context close)
10. `DisposableBean.destroy()`

**Q6. What is `@Primary` and `@Qualifier`?**
When multiple beans of the same type exist, Spring doesn't know which to inject. `@Primary` marks the default; `@Qualifier("beanName")` at the injection point selects a specific one. Both used together: `@Qualifier` takes precedence.

---

## Advanced (L5 Senior)

**Q7. What is the self-invocation problem in AOP?**
When a Spring bean calls its own method (`this.method()`), the call bypasses the AOP proxy — any advice (e.g., `@Transactional`, `@Cacheable`) is NOT applied to the self-called method. The proxy is only entered from outside the bean.

Fix options:
1. Inject the bean into itself (`@Autowired private MyService self`)
2. Use `AopContext.currentProxy()`
3. Refactor the method into a separate bean

**Q8. What is the difference between JDK Dynamic Proxy and CGLIB proxy?**

| | JDK Dynamic Proxy | CGLIB |
|-|------------------|-------|
| Requirement | Target must implement an interface | Any class (subclasses the target) |
| How | `java.lang.reflect.Proxy` | Generates bytecode at runtime |
| Final class/method | N/A | Cannot proxy `final` classes or methods |
| Spring Boot default | `proxyTargetClass=true` defaults to CGLIB | — |

**Q9. When does Spring create a prototype-scoped bean, and what is the "prototype in singleton" trap?**
Prototype: created each time `getBean()` is called. Trap: if you inject a `@Scope("prototype")` bean into a `@Singleton` bean via `@Autowired`, the prototype is created once at injection time and never refreshed — it becomes effectively a singleton.

Fix: inject `ObjectFactory<PrototypeBean>` or use `ApplicationContext.getBean()` at each use, or `@Lookup` method injection.

**Q10. Explain the `@Configuration` vs `@Component` difference for `@Bean` methods.**
In `@Configuration`, the class is CGLIB-proxied. When one `@Bean` method calls another, Spring intercepts and returns the same singleton instance. In `@Component`, it's a plain Java call — each call creates a new object:

```java
@Configuration
public class ConfigClass {
    @Bean
    public A a() { return new A(b()); }  // b() calls Spring factory → same B instance

    @Bean
    public B b() { return new B(); }
}

@Component
public class ComponentClass {
    @Bean
    public A a() { return new A(b()); }  // b() is a plain Java method call → new B()!

    @Bean
    public B b() { return new B(); }
}
```

**Q11. What is `ApplicationEvent` and how does it enable decoupling?**
`ApplicationEventPublisher.publishEvent(event)` fires an event; `@EventListener` methods on any Spring bean receive it. Publishers don't know about subscribers. For transactional integrity, use `@TransactionalEventListener(phase = AFTER_COMMIT)` — fires only if transaction commits.

---

## Principal Engineer Level

**Q12. How do you design a Spring application that needs to support multiple data sources with different transaction managers?**
Configure multiple `DataSource` beans with `@Primary` for the default. Each needs its own `PlatformTransactionManager` bean. Use `@Transactional("specificTxManager")` to select the right one. For cross-database operations, consider JTA/XA (two-phase commit) or an eventual-consistency saga pattern.

```java
@Bean
@Primary
public DataSource primaryDataSource() { ... }

@Bean
public DataSource analyticsDataSource() { ... }

@Bean
@Primary
public PlatformTransactionManager primaryTxManager(DataSource primaryDataSource) {
    return new DataSourceTransactionManager(primaryDataSource);
}

@Bean
public PlatformTransactionManager analyticsTxManager(DataSource analyticsDataSource) {
    return new DataSourceTransactionManager(analyticsDataSource);
}
```

**Q13. How do you build a plugin architecture in Spring where new implementations can be added without modifying core code?**
Use the Strategy pattern via Spring's bean collection injection. Core code accepts `List<Plugin>` or `Map<String, Plugin>` — Spring injects all beans implementing that interface. New plugins are just new beans; no changes to the core.

```java
public interface PricingStrategy {
    String getName();
    BigDecimal calculate(Order order);
}

@Service
public class PricingEngine {
    private final Map<String, PricingStrategy> strategies;

    public PricingEngine(List<PricingStrategy> strategyList) {
        this.strategies = strategyList.stream()
            .collect(toMap(PricingStrategy::getName, identity()));
    }

    public BigDecimal price(String strategyName, Order order) {
        return strategies.get(strategyName).calculate(order);
    }
}
```

**Q14. How does Spring resolve circular dependencies?**
Spring resolves circular dependencies for singleton beans using a three-level cache:
1. `singletonObjects` — fully initialized beans
2. `earlySingletonObjects` — partially initialized, exposed before final init
3. `singletonFactories` — factory callbacks to create early references

For `@Autowired` field/setter injection, Spring can inject an early reference (partial bean) to break the cycle. Constructor injection cannot resolve circular dependencies — it will throw `BeanCurrentlyInCreationException`. The fix: redesign to remove the circular dependency (introduce a mediator/event).

---

## Code Walkthroughs

**Q15. What does this code print, and why?**
```java
@Service
public class OrderService {
    @Transactional
    public void createOrder() {
        this.sendNotification();  // Does @Transactional apply here?
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void sendNotification() {
        // What transaction is active here?
    }
}
```
**Answer**: `sendNotification()` runs within the SAME transaction as `createOrder()`, not a new one. Self-invocation bypasses the AOP proxy — `Propagation.REQUIRES_NEW` is ignored. To fix, inject `OrderService` into itself or move `sendNotification` to a separate bean.

**Q16. What's wrong with this prototype injection?**
```java
@Service  // singleton
public class RequestHandler {
    @Autowired
    private PrototypeBean prototypeBean;  // intended to be a new instance per request

    public void handle() {
        prototypeBean.process();  // always the same instance!
    }
}
```
**Answer**: The prototype bean is injected once at singleton creation — effectively becomes a singleton. Fix: use `@Autowired ObjectFactory<PrototypeBean> factory` and call `factory.getObject()` per request.

---

## Common Mistakes

| Mistake | Problem | Fix |
|---------|---------|-----|
| Field injection in production code | Hides dependencies, untestable without Spring | Constructor injection |
| Calling own `@Transactional` method | Proxy bypassed, no transaction | Inject self or restructure |
| Singleton bean with mutable state | Thread safety issues | Use `AtomicXxx`, `ThreadLocal`, or stateless design |
| Not understanding `@Configuration` vs `@Component` for `@Bean` | Multiple instances of beans | Use `@Configuration` for config classes with inter-bean dependencies |
| Ignoring circular dependency warning | `BeanCurrentlyInCreationException` | Redesign — introduce event or mediator |
