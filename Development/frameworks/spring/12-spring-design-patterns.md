# Design Patterns in Spring — GoF Patterns Across the Ecosystem

The Spring Framework is one of the best real-world examples of GoF (Gang of Four) design patterns applied at scale. Every interview that touches Spring is also implicitly a design patterns interview. This file maps every major pattern to its concrete Spring implementation, with code examples showing the pattern in action.

---

## Pattern Landscape in Spring

```
CREATIONAL                    STRUCTURAL                  BEHAVIORAL
──────────────────────────   ──────────────────────────  ──────────────────────────
Factory Method    ● BeanFactory  Proxy       ● AOP Proxy    Chain of Resp. ● FilterChain
Abstract Factory  ● FactoryBean  Decorator   ● PostProc.    Strategy       ● AuthProvider
Singleton         ● Bean Scope   Adapter     ● HandlerAdapt Template Meth. ● JdbcTemplate
Builder           ● *Builder     Composite   ● PropertySrc  Observer       ● AppEvent
Prototype         ● @Prototype   Facade      ● JdbcTemplate Command        ● @Scheduled
                                             Bridge     ● LoggingSystem    Iterator  ● Pageable
```

---

## 1. Factory Method

**Where**: `BeanFactory`, `FactoryBean`, auto-configuration beans.

```java
// BeanFactory — creates beans on demand (Factory Method)
ApplicationContext ctx = new AnnotationConfigApplicationContext(AppConfig.class);
OrderService service = ctx.getBean(OrderService.class);  // factory creates instance

// FactoryBean — Spring-managed factory for complex object creation
@Component
public class RedisConnectionFactoryBean implements FactoryBean<RedisConnectionFactory> {

    @Override
    public RedisConnectionFactory getObject() {
        LettuceConnectionFactory factory = new LettuceConnectionFactory(
            new RedisStandaloneConfiguration("redis-host", 6379));
        factory.afterPropertiesSet();
        return factory;
    }

    @Override
    public Class<?> getObjectType() {
        return RedisConnectionFactory.class;
    }

    @Override
    public boolean isSingleton() {
        return true;
    }
}

// @Bean methods — Factory Method in @Configuration
@Configuration
public class AppConfig {
    @Bean  // this IS the factory method
    public PaymentGateway paymentGateway(PaymentProperties props) {
        return PaymentGateway.builder()
            .apiKey(props.getApiKey())
            .timeout(props.getTimeout())
            .build();
    }
}
```

**Interview trigger**: "What is a `FactoryBean`?" — It's a Spring factory that produces beans, not a bean itself. `getBean("myFactory")` returns what `getObject()` returns, not the `FactoryBean` instance. Use `&myFactory` to get the factory itself.

---

## 2. Singleton

**Where**: Default bean scope — one instance per ApplicationContext.

```java
@Service  // Singleton by default
public class OrderService { ... }

// The container guarantees: same instance for every injection
@RestController
public class OrderController {
    private final OrderService service;  // always the same instance
}

// CRITICAL: Singleton beans must be stateless or thread-safe
// BAD — shared mutable state:
@Service
public class BadCounterService {
    private int requestCount = 0;  // SHARED across all threads — race condition!
    public void increment() { requestCount++; }
}

// GOOD — use AtomicInteger or delegate to thread-safe store:
@Service
public class GoodCounterService {
    private final AtomicLong count = new AtomicLong(0);
    public void increment() { count.incrementAndGet(); }
}
```

**Multiton variant**: `@Scope("prototype")` — new instance per `getBean()` call. Rarely needed; use when beans carry per-request state.

---

## 3. Proxy

**Where**: AOP — the most pervasive pattern in Spring internals.

```java
// What you write:
@Service
public class OrderService {
    @Transactional  // instructs Spring to create a proxy
    public Order createOrder(CreateOrderRequest req) { ... }
}

// What Spring creates at startup (conceptually):
public class OrderService$$SpringCGLIBProxy extends OrderService {
    @Override
    public Order createOrder(CreateOrderRequest req) {
        TransactionStatus tx = txManager.getTransaction(new DefaultTransactionDefinition());
        try {
            Order result = super.createOrder(req);  // calls real method
            txManager.commit(tx);
            return result;
        } catch (RuntimeException ex) {
            txManager.rollback(tx);
            throw ex;
        }
    }
}

// JDK Dynamic Proxy (when interface exists):
Object proxy = Proxy.newProxyInstance(
    classLoader,
    new Class[]{ OrderService.class },
    (proxyInstance, method, args) -> {
        // advice logic before
        Object result = method.invoke(target, args);
        // advice logic after
        return result;
    }
);
```

**Why it matters**: Every `@Transactional`, `@Cacheable`, `@Secured`, `@Async`, `@Retryable` annotation creates a proxy. Self-invocation bypasses the proxy — the most common Spring bug.

---

## 4. Decorator

**Where**: `BeanPostProcessor`, `HandlerInterceptor`, `ExchangeFilterFunction`.

```java
// BeanPostProcessor — decorates beans after creation
@Component
public class AuditBeanPostProcessor implements BeanPostProcessor {

    @Override
    public Object postProcessAfterInitialization(Object bean, String beanName) {
        if (bean instanceof Repository) {
            // Wrap repository with auditing decorator
            return Proxy.newProxyInstance(
                bean.getClass().getClassLoader(),
                bean.getClass().getInterfaces(),
                (proxy, method, args) -> {
                    audit(beanName, method.getName());
                    return method.invoke(bean, args);
                });
        }
        return bean;
    }
}

// WebClient filter — decorates HTTP requests
WebClient client = WebClient.builder()
    .filter(ExchangeFilterFunction.ofRequestProcessor(request -> {
        // Decorates each request with auth header
        return Mono.just(ClientRequest.from(request)
            .header("Authorization", "Bearer " + tokenProvider.getToken())
            .build());
    }))
    .build();
```

---

## 5. Chain of Responsibility

**Where**: Filter chain (Servlet), `SecurityFilterChain`, `HandlerInterceptor` chain.

```java
// Each filter either handles the request or passes it to the next
@Component
public class RateLimitFilter extends OncePerRequestFilter {

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res,
                                     FilterChain chain) throws IOException, ServletException {
        if (!rateLimiter.tryAcquire(req.getRemoteAddr())) {
            res.setStatus(HttpStatus.TOO_MANY_REQUESTS.value());
            return;  // STOP the chain — request is rejected
        }
        chain.doFilter(req, res);  // PASS to next filter in chain
    }
}

// Spring Security's filter chain is the same pattern:
// SecurityContextPersistenceFilter → UsernamePasswordFilter → BasicAuthFilter
//   → ExceptionTranslationFilter → FilterSecurityInterceptor
// Each can stop the chain (reject) or pass (allow)
```

---

## 6. Observer / Event

**Where**: `ApplicationEventPublisher`, `@EventListener`, `@TransactionalEventListener`.

```java
// Event — plain POJO
public record OrderCreatedEvent(UUID orderId, String customerId, Instant occurredAt) {}

// Publisher — fires event (decoupled from listeners)
@Service
public class OrderService {
    private final ApplicationEventPublisher publisher;

    public Order createOrder(CreateOrderRequest req) {
        Order order = orderRepository.save(new Order(req));
        publisher.publishEvent(new OrderCreatedEvent(order.getId(), req.customerId(), Instant.now()));
        return order;
    }
}

// Observer 1 — sends email
@Component
public class OrderEmailListener {
    @EventListener
    public void onOrderCreated(OrderCreatedEvent event) {
        emailService.sendOrderConfirmation(event.customerId(), event.orderId());
    }
}

// Observer 2 — publishes to Kafka ONLY after transaction commits
@Component
public class OrderKafkaPublisher {
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onOrderCreated(OrderCreatedEvent event) {
        kafkaTemplate.send("orders.created", event.orderId().toString(), event);
    }
}
```

**`@TransactionalEventListener`** is critical: events fired in `BEFORE_COMMIT` (default) or `AFTER_COMMIT`. Use `AFTER_COMMIT` for Kafka/external calls — prevents publishing when transaction rolls back.

---

## 7. Template Method

**Where**: `JdbcTemplate`, `RestTemplate`, `TransactionTemplate`, `AbstractItemReader`.

```java
// JdbcTemplate defines the skeleton (open connection → execute → close → handle exceptions)
// You provide only the varying part (the query + row mapper)
@Repository
public class OrderDao {
    private final JdbcTemplate jdbc;

    public List<Order> findByCustomer(String customerId) {
        return jdbc.query(
            "SELECT * FROM orders WHERE customer_id = ?",
            (rs, rowNum) -> new Order(  // ← this is your custom step
                UUID.fromString(rs.getString("id")),
                rs.getString("customer_id"),
                OrderStatus.valueOf(rs.getString("status"))
            ),
            customerId
        );
    }
}

// TransactionTemplate — template for programmatic transactions
@Service
public class OrderService {
    private final TransactionTemplate txTemplate;

    public Order createWithRetry(CreateOrderRequest req) {
        return txTemplate.execute(status -> {  // ← your custom step inside the template
            try {
                return orderRepository.save(new Order(req));
            } catch (OptimisticLockingFailureException e) {
                status.setRollbackOnly();
                throw e;
            }
        });
    }
}
```

---

## 8. Strategy

**Where**: `AuthenticationProvider`, `PasswordEncoder`, `KeyGenerator`, `CacheResolver`, `HandlerMapping`.

```java
// Spring picks the right AuthenticationProvider strategy at runtime
@Configuration
public class SecurityConfig {
    @Bean
    public AuthenticationManager authenticationManager(
            UserDetailsService userDetailsService,
            PasswordEncoder encoder) {

        DaoAuthenticationProvider dbStrategy = new DaoAuthenticationProvider();
        dbStrategy.setUserDetailsService(userDetailsService);
        dbStrategy.setPasswordEncoder(encoder);

        JwtAuthenticationProvider jwtStrategy = new JwtAuthenticationProvider(jwtDecoder());

        // ProviderManager tries each strategy in order
        return new ProviderManager(List.of(dbStrategy, jwtStrategy));
    }
}

// Custom cache key strategy
@Bean
public KeyGenerator tenantAwareKeyGenerator() {
    return (target, method, params) -> {
        String tenantId = TenantContext.getCurrentTenantId();
        return tenantId + ":" + method.getName() + ":" + Arrays.toString(params);
    };
}

@Cacheable(value = "products", keyGenerator = "tenantAwareKeyGenerator")
public List<Product> getProducts() { ... }
```

---

## 9. Adapter

**Where**: `HandlerAdapter`, `MessageConverter`, `TaskExecutorAdapter`.

```java
// HandlerAdapter adapts diverse handler types to a uniform interface
// DispatcherServlet calls handlerAdapter.handle() — doesn't care which type of handler
public interface HandlerAdapter {
    boolean supports(Object handler);
    ModelAndView handle(HttpServletRequest req, HttpServletResponse res, Object handler);
}

// Spring provides adapters for:
// - @Controller methods (RequestMappingHandlerAdapter)
// - HttpRequestHandler (SimpleControllerHandlerAdapter)
// - HandlerFunction (HandlerFunctionAdapter — functional endpoints)

// MessageConverter adapts between Java objects and HTTP body
@Bean
public MappingJackson2HttpMessageConverter jsonConverter() {
    MappingJackson2HttpMessageConverter converter = new MappingJackson2HttpMessageConverter();
    converter.setObjectMapper(customObjectMapper());
    return converter;
}
```

---

## 10. Composite

**Where**: `CompositeHealthContributor`, `CompositePropertySource`, `CompositeItemProcessor`.

```java
// CompositeHealthContributor — aggregate multiple health checks as one
@Component("dependencies")
public class DependenciesHealthIndicator implements CompositeHealthContributor {
    private final Map<String, HealthContributor> contributors;

    public DependenciesHealthIndicator(
            DatabaseHealthIndicator dbHealth,
            KafkaHealthIndicator kafkaHealth,
            RedisHealthIndicator redisHealth) {
        this.contributors = Map.of(
            "database", dbHealth,
            "kafka", kafkaHealth,
            "redis", redisHealth
        );
    }

    @Override
    public HealthContributor getContributor(String name) { return contributors.get(name); }

    @Override
    public Iterator<NamedContributor<HealthContributor>> iterator() {
        return NamedContributor.of(contributors).iterator();
    }
}
// /actuator/health/dependencies shows aggregated status of all three

// CompositeItemProcessor — chain processors in Spring Batch
@Bean
public CompositeItemProcessor<Order, ProcessedOrder> compositeProcessor() {
    CompositeItemProcessor<Order, ProcessedOrder> processor = new CompositeItemProcessor<>();
    processor.setDelegates(List.of(
        new ValidationProcessor(),
        new EnrichmentProcessor(),
        new TransformationProcessor()
    ));
    return processor;
}
```

---

## 11. Builder

**Where**: `UriComponentsBuilder`, `MockMvcRequestBuilders`, `JobBuilder`, `SecurityFilterChain` config.

```java
// Spring Security — fluent builder for filter chain configuration
http
    .authorizeHttpRequests(auth -> auth
        .requestMatchers("/public/**").permitAll()
        .anyRequest().authenticated())
    .sessionManagement(sm -> sm.sessionCreationPolicy(STATELESS))
    .csrf(AbstractHttpConfigurer::disable);

// UriComponentsBuilder — builds complex URLs safely
URI uri = UriComponentsBuilder.fromHttpUrl("https://api.example.com")
    .path("/v1/products")
    .queryParam("category", category)
    .queryParam("page", page)
    .queryParam("size", 20)
    .build()
    .toUri();
```

---

## 12. Command

**Where**: `@Scheduled`, `CommandLineRunner`, Spring Batch `Tasklet`.

```java
// @Scheduled — encapsulates the command to run at a time
@Component
public class ScheduledCommands {

    @Scheduled(cron = "0 0 2 * * *")  // 2AM daily
    public void archiveOldOrders() {
        orderService.archiveOrdersOlderThan(Duration.ofDays(90));
    }

    @Scheduled(fixedRate = 60_000)  // every minute
    public void refreshExchangeRates() {
        exchangeRateService.refresh();
    }
}

// CommandLineRunner — run once at startup
@Component
@Order(1)
public class CacheWarmupRunner implements CommandLineRunner {
    @Override
    public void run(String... args) {
        productService.warmupCache();  // execute the command
    }
}
```

---

## Pattern Quick-Reference Card

| GoF Pattern | Spring Implementation | Key Class/Annotation |
|-------------|----------------------|---------------------|
| Factory Method | Bean creation | `BeanFactory`, `@Bean`, `FactoryBean` |
| Singleton | Default scope | `@Component`, `@Service`, `@Repository` |
| Prototype | Per-request beans | `@Scope("prototype")` |
| Builder | Fluent configuration | `HttpSecurity`, `JobBuilder`, `UriComponentsBuilder` |
| Proxy | AOP weaving | `@Transactional`, `@Cacheable`, `@Secured`, `@Async` |
| Decorator | Bean post-processing | `BeanPostProcessor`, `ExchangeFilterFunction` |
| Adapter | Handler/Converter bridging | `HandlerAdapter`, `MessageConverter` |
| Composite | Aggregated components | `CompositeHealthContributor`, `CompositeItemProcessor` |
| Facade | Simplified API | `JdbcTemplate`, `RestTemplate`, `KafkaTemplate` |
| Chain of Responsibility | Request processing | Filter chain, `SecurityFilterChain`, Interceptors |
| Observer / Event | Loose coupling | `ApplicationEventPublisher`, `@EventListener` |
| Template Method | Algorithmic skeleton | `JdbcTemplate`, `TransactionTemplate`, `AbstractItemReader` |
| Strategy | Pluggable algorithms | `AuthenticationProvider`, `PasswordEncoder`, `KeyGenerator` |
| Command | Encapsulate operation | `@Scheduled`, `CommandLineRunner`, Batch `Tasklet` |
| Iterator | Sequential access | `Pageable`, `ItemReader` |

---

## FAANG Interview Callout

1. **"Which design pattern does Spring AOP use?"**
   - Proxy pattern — creates a proxy (JDK dynamic proxy or CGLIB subclass) that intercepts method calls and applies advice

2. **"Which pattern is `JdbcTemplate` an example of?"**
   - Template Method — defines the skeleton algorithm (connect → execute → close → handle exceptions); you provide just the query + row mapper

3. **"How does `ApplicationEventPublisher` implement the Observer pattern?"**
   - Subject (`ApplicationEventPublisher`) maintains a list of observers (`@EventListener`); when an event is published, all registered listeners are notified

4. **"Where is Chain of Responsibility used in Spring Security?"**
   - `SecurityFilterChain` — each filter either handles the request (rejects with 401/403) or calls `chain.doFilter()` to pass to the next filter

5. **"What's the difference between Decorator and Proxy in Spring?"**
   - Proxy: same interface, wraps to add behavior (AOP) — caller unaware of proxy
   - Decorator: adds behavior by wrapping — typically explicit, extends functionality rather than intercepting
   - In practice: AOP proxies are transparent (caller doesn't know); `BeanPostProcessor` decorators explicitly wrap beans
