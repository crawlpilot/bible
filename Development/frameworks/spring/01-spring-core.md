# Spring Core — IoC, DI, AOP, and the Bean Lifecycle

Spring Core is the **foundation of the entire Spring ecosystem**. Every Spring module — MVC, Data, Security, Boot — is built on top of the IoC container defined here. Understanding Spring Core deeply is the prerequisite for understanding all other Spring questions.

---

## Origins & Motivation

Spring was created by Rod Johnson (2003) as a reaction to the complexity of J2EE (EJBs). The central insight: **the framework should manage object creation and wiring, not application code**. This is Inversion of Control (IoC).

---

## Core Architecture

```
                     ApplicationContext
                           │
              ┌────────────┴─────────────┐
              │        BeanFactory        │
              │   (core container)        │
              │                          │
              │  ┌─────────────────────┐ │
              │  │   BeanDefinition    │ │  ← metadata: class, scope, lazy, init/destroy
              │  │   Registry          │ │
              │  └─────────────────────┘ │
              │                          │
              │  ┌─────────────────────┐ │
              │  │   Singleton Pool    │ │  ← instantiated singletons live here
              │  └─────────────────────┘ │
              │                          │
              │  ┌─────────────────────┐ │
              │  │   BeanPostProcessor │ │  ← AOP proxies, @Autowired injection
              │  └─────────────────────┘ │
              └──────────────────────────┘
                           │
               ┌───────────┴──────────────┐
               │                          │
    AnnotationConfigApplicationContext  ClassPathXmlApplicationContext
         (annotation-driven)               (XML-driven, legacy)
```

---

## Dependency Injection

### Three DI Types

```java
// 1. Constructor Injection — PREFERRED (immutable, testable, no null risk)
@Service
public class OrderService {
    private final PaymentGateway paymentGateway;

    public OrderService(PaymentGateway paymentGateway) {
        this.paymentGateway = paymentGateway;
    }
}

// 2. Setter Injection — for optional dependencies
@Service
public class ReportService {
    private NotificationService notificationService;

    @Autowired(required = false)
    public void setNotificationService(NotificationService s) {
        this.notificationService = s;
    }
}

// 3. Field Injection — AVOID in production (breaks testability, hides deps)
@Service
public class BadService {
    @Autowired  // hard to test without Spring context; not recommended
    private PaymentGateway paymentGateway;
}
```

**Principal rule**: Always use constructor injection. Field injection hides dependencies and makes unit testing require reflection or a Spring context.

---

## Bean Lifecycle

```
  1. BeanDefinition loaded (classpath scan / XML / Java config)
  2. Constructor called
  3. Setter / field injection (@Autowired, @Value)
  4. BeanPostProcessor.postProcessBeforeInitialization()
     └─ @PostConstruct method called here
  5. InitializingBean.afterPropertiesSet()  (if implemented)
  6. Custom init-method (if configured)
  7. BeanPostProcessor.postProcessAfterInitialization()
     └─ AOP proxy created here if needed
  8. Bean ready for use (lives in Singleton pool)
  ...
  9. @PreDestroy method called (on context close)
 10. DisposableBean.destroy()  (if implemented)
 11. Custom destroy-method
```

```java
@Component
public class DatabasePool {

    @PostConstruct
    public void init() {
        // Opens connection pool — runs after injection
    }

    @PreDestroy
    public void cleanup() {
        // Closes connection pool — runs on context close
    }
}
```

---

## Bean Scopes

| Scope | One instance per | Use Case |
|-------|----------------|----------|
| `singleton` | ApplicationContext (default) | Stateless services, DAOs |
| `prototype` | `getBean()` call | Stateful beans (e.g., wizard step) |
| `request` | HTTP request | Per-request state in web apps |
| `session` | HTTP session | User session data |
| `application` | ServletContext | App-wide shared state |
| `websocket` | WebSocket session | WebSocket-scoped data |

**Common trap**: Injecting a `prototype`-scoped bean into a `singleton` — the prototype is created once at injection time and never refreshed. Fix: inject `ObjectFactory<T>` or `ApplicationContext.getBean()`.

---

## AOP (Aspect-Oriented Programming)

AOP allows **cross-cutting concerns** (logging, transactions, security) to be modularized separately from business logic.

### How Spring AOP Works

```
  Caller → Proxy → [Advice execution] → Target bean
```

Spring AOP creates a **proxy** around the target bean at startup:
- JDK Dynamic Proxy — if target implements an interface
- CGLIB Proxy — if target is a concrete class (subclasses it)

```java
@Aspect
@Component
public class AuditAspect {

    // Pointcut: intercept all methods in service package
    @Around("execution(* com.example.service.*.*(..))")
    public Object audit(ProceedingJoinPoint pjp) throws Throwable {
        log.info("Calling {}", pjp.getSignature());
        long start = System.currentTimeMillis();
        Object result = pjp.proceed();  // invoke the real method
        log.info("Completed in {}ms", System.currentTimeMillis() - start);
        return result;
    }

    @AfterThrowing(pointcut = "within(com.example.service.*)", throwing = "ex")
    public void logException(JoinPoint jp, Exception ex) {
        log.error("Exception in {} : {}", jp.getSignature(), ex.getMessage());
    }
}
```

### AOP Advice Types

| Advice | When It Runs |
|--------|-------------|
| `@Before` | Before method executes |
| `@After` | After method returns (any outcome) |
| `@AfterReturning` | After successful return |
| `@AfterThrowing` | After exception thrown |
| `@Around` | Wraps the method — most powerful, most dangerous |

### AOP Self-Invocation Trap

```java
@Service
public class OrderService {
    @Transactional
    public void placeOrder() {
        this.validateOrder(); // TRAP: self-invocation bypasses AOP proxy
    }

    @Transactional(propagation = REQUIRES_NEW)
    public void validateOrder() { ... } // @Transactional has NO EFFECT here
}
```

Fix: inject `OrderService` into itself (via `@Autowired` or `ApplicationContext.getBean()`), or restructure to avoid self-calls, or use `AopContext.currentProxy()` (fragile).

---

## Spring Expression Language (SpEL)

```java
@Value("#{systemProperties['user.home']}")
private String userHome;

@Value("#{T(java.lang.Math).PI * 2}")
private double twoPi;

@Value("#{orderService.getActiveOrders().size()}")
private int activeOrderCount;

// In @Cacheable
@Cacheable(key = "#user.id + '_' + #region")
public List<Product> getProducts(User user, String region) { ... }

// In @PreAuthorize
@PreAuthorize("hasRole('ADMIN') or #userId == authentication.name")
public void deleteUser(String userId) { ... }
```

---

## ApplicationContext Hierarchy

```java
// Parent context — shared infrastructure beans
AnnotationConfigApplicationContext parent = new AnnotationConfigApplicationContext();
parent.register(InfrastructureConfig.class);
parent.refresh();

// Child context — inherits parent beans, can override
AnnotationConfigApplicationContext child = new AnnotationConfigApplicationContext();
child.setParent(parent);
child.register(WebConfig.class);
child.refresh();
```

Child beans can access parent beans; parent beans cannot access child beans. Spring MVC creates a child context (WebApplicationContext) — this is why `@Service` beans defined in root context are accessible to `@Controller` beans in web context.

---

## @Configuration and Bean Definitions

```java
@Configuration
public class AppConfig {

    @Bean
    @Scope("prototype")
    public HttpClient httpClient() {
        return HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();
    }

    @Bean
    @Primary  // used when multiple beans of same type exist
    public DataSource primaryDataSource() { ... }

    @Bean
    @Qualifier("readReplica")
    public DataSource replicaDataSource() { ... }
}
```

**`@Configuration` vs `@Component`**: Classes annotated with `@Configuration` are CGLIB-subclassed. When you call `@Bean` method from another `@Bean` method inside `@Configuration`, Spring intercepts the call and returns the singleton. With `@Component` it's a plain Java call — creates a new instance every time.

---

## Conditional Beans

```java
@Bean
@ConditionalOnProperty(name = "feature.newpayment.enabled", havingValue = "true")
public PaymentService newPaymentService() { ... }

@Bean
@ConditionalOnMissingBean(PaymentService.class)
public PaymentService defaultPaymentService() { ... }

@Bean
@ConditionalOnClass(name = "com.stripe.Stripe")
public StripeGateway stripeGateway() { ... }
```

These are the same conditionals Spring Boot auto-configuration uses internally.

---

## Design Patterns Used

| Pattern | Where in Spring Core |
|---------|---------------------|
| **Factory** | `BeanFactory` — creates beans on demand |
| **Singleton** | Default bean scope — one instance per context |
| **Proxy** | AOP — JDK dynamic proxy or CGLIB subclass |
| **Observer / Event** | `ApplicationEventPublisher` / `@EventListener` |
| **Template Method** | `JdbcTemplate`, `RestTemplate` — define skeleton, subclass/lambda fills in steps |
| **Decorator** | `BeanPostProcessor` — wraps beans to add behavior |
| **Strategy** | `BeanNameGenerator`, `ScopeMetadataResolver` — pluggable algorithms |
| **Composite** | `CompositePropertySource` — multiple property sources as one |

---

## Trade-offs & When NOT to Use Spring Core

| Trade-off | Benefit | Cost |
|-----------|---------|------|
| IoC container | Loose coupling, testability | Startup time, "magic" debugging |
| AOP proxying | Centralize cross-cutting concerns | Self-invocation trap, proxy overhead |
| Classpath scanning | Zero config | Slow scan on huge classpaths; ambiguous bean errors |
| Singleton default | Memory efficient | Shared mutable state bugs |
| CGLIB proxy | Works on concrete classes | Can't proxy `final` classes/methods |

**Do not use Spring Core when**:
- Writing a utility library — don't force framework dependency on consumers
- Lambda / serverless functions where startup time is critical (prefer Quarkus/Micronaut with ahead-of-time compilation)
- Simple CLI tools with no dependency graph complexity

---

## FAANG Interview Callout

**Most-asked Spring Core questions at principal level**:

1. **"What's the difference between `BeanFactory` and `ApplicationContext`?"**
   - `BeanFactory`: lazy initialization, minimal features
   - `ApplicationContext`: eager singleton init, i18n, event publishing, AOP, `@Autowired`
   - In practice: always use `ApplicationContext`

2. **"How does `@Transactional` work internally?"**
   - AOP proxy intercepts the call → starts/commits/rolls back transaction → delegates to real method
   - Rollback only happens for unchecked exceptions by default
   - Self-invocation bypasses proxy → transaction doesn't apply

3. **"What is the bean lifecycle order?"**
   - Constructor → injection → `@PostConstruct` → `afterPropertiesSet` → ready → `@PreDestroy` → `destroy`

4. **"What happens when you inject a `prototype` bean into a `singleton`?"**
   - The prototype is instantiated once and cached — defeats the prototype purpose
   - Fix: `ObjectProvider<T>`, `@Lookup`, or `ApplicationContext.getBean()`

5. **"When does Spring create a JDK proxy vs a CGLIB proxy?"**
   - JDK: target implements at least one interface
   - CGLIB: concrete class with no interface; or when `proxyTargetClass=true`
   - Spring Boot defaults `proxyTargetClass=true` since Boot 2.x
