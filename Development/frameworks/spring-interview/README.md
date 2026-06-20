# Spring Interview Questions — Usage Guide

Interview questions leveled by engineering grade. Each file follows the same structure: Fundamentals (L3-L4) → Advanced (L5) → Principal (L7) → Code Walkthroughs → Common Mistakes.

## Files

| File | Module | Top Questions Asked |
|------|--------|-------------------|
| [01-spring-core-questions.md](01-spring-core-questions.md) | Core | IoC, AOP proxy, bean lifecycle, self-invocation |
| [02-spring-boot-questions.md](02-spring-boot-questions.md) | Boot | Auto-config internals, @Conditional, starters |
| [03-spring-mvc-questions.md](03-spring-mvc-questions.md) | MVC | DispatcherServlet flow, Filter vs Interceptor |
| [04-spring-data-questions.md](04-spring-data-questions.md) | Data | N+1, @Transactional propagation, JPQL vs native |
| [05-spring-security-questions.md](05-spring-security-questions.md) | Security | Filter chain, OAuth2, JWT, method security |
| [06-spring-cloud-questions.md](06-spring-cloud-questions.md) | Cloud | Circuit breaker, service discovery, Gateway |
| [07-spring-webflux-questions.md](07-spring-webflux-questions.md) | WebFlux | Mono/Flux, backpressure, flatMap vs concatMap |
| [08-spring-batch-questions.md](08-spring-batch-questions.md) | Batch | Chunk, partitioning, restart, skip/retry |
| [09-spring-messaging-questions.md](09-spring-messaging-questions.md) | Messaging | Kafka consumer, exactly-once, DLT |
| [10-spring-cache-questions.md](10-spring-cache-questions.md) | Cache | @Cacheable internals, cache stampede, eviction |
| [11-spring-testing-questions.md](11-spring-testing-questions.md) | Testing | Slices, Testcontainers, @MockBean |
| [12-spring-design-patterns-questions.md](12-spring-design-patterns-questions.md) | Patterns | Which pattern where, AOP=Proxy, JdbcTemplate=Template Method |

## Interview Priority by Role

| Role | Must Know | Should Know |
|------|----------|-------------|
| L3-L4 | Core, Boot, MVC basics | Data (CRUD), Security basics |
| L5 Senior | Core internals, AOP, Transactions, Security filter chain | WebFlux intro, Testing, Design Patterns |
| L6 Staff | All above + Cloud, WebFlux depth, Patterns deep | Batch, Messaging architecture |
| L7 Principal | All modules — architect-level trade-offs, not just mechanics | Cross-module architectural questions |
