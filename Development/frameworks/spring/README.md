# Spring Framework — Module Overview

12 files covering every major Spring module. Start with Core (01) — all other modules build on it.

## Files

| File | Module | Key Internal Mechanism |
|------|--------|----------------------|
| [01-spring-core.md](01-spring-core.md) | Spring Core | BeanFactory, ApplicationContext, AOP proxy, SpEL |
| [02-spring-boot.md](02-spring-boot.md) | Spring Boot | `@EnableAutoConfiguration`, `spring.factories`, Actuator |
| [03-spring-mvc.md](03-spring-mvc.md) | Spring MVC | DispatcherServlet, HandlerMapping, FilterChain |
| [04-spring-data.md](04-spring-data.md) | Spring Data | Repository proxy, query derivation, @Transactional |
| [05-spring-security.md](05-spring-security.md) | Spring Security | SecurityFilterChain, AuthenticationManager, OAuth2 |
| [06-spring-cloud.md](06-spring-cloud.md) | Spring Cloud | Config Server, Eureka, Gateway, Resilience4j |
| [07-spring-webflux.md](07-spring-webflux.md) | Spring WebFlux | Project Reactor, Mono/Flux, Netty, R2DBC |
| [08-spring-batch.md](08-spring-batch.md) | Spring Batch | Job, Step, Chunk, JobRepository, partitioning |
| [09-spring-messaging.md](09-spring-messaging.md) | Spring Messaging | Kafka, AMQP, JMS, Integration EIP patterns |
| [10-spring-cache.md](10-spring-cache.md) | Spring Cache | `@Cacheable` proxy, CacheManager, Redis, eviction |
| [11-spring-testing.md](11-spring-testing.md) | Spring Testing | Test slices, MockMvc, Testcontainers, @MockBean |
| [12-spring-design-patterns.md](12-spring-design-patterns.md) | Design Patterns | All GoF patterns used across Spring internals |

## Dependency Diagram

```
Spring Core
    ├── Spring Boot (layered on top)
    │       ├── Spring MVC          (web layer)
    │       ├── Spring WebFlux      (reactive web layer — mutually exclusive with MVC)
    │       ├── Spring Data         (data access)
    │       ├── Spring Security     (security layer)
    │       ├── Spring Cache        (caching abstraction)
    │       └── Spring Testing      (test utilities)
    │
    ├── Spring Cloud                (distributed systems)
    │       ├── Spring Cloud Config
    │       ├── Spring Cloud Netflix / Eureka
    │       ├── Spring Cloud Gateway
    │       └── Spring Cloud Circuit Breaker (Resilience4j)
    │
    ├── Spring Batch                (bulk processing)
    └── Spring Messaging            (async / event-driven)
            ├── Spring Kafka
            ├── Spring AMQP
            ├── Spring JMS
            └── Spring Integration
```
