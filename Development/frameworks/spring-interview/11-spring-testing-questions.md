# Spring Testing — Interview Questions

---

## Fundamentals (L3–L4)

**Q1. What is the difference between `@SpringBootTest` and `@WebMvcTest`?**
- `@SpringBootTest`: loads the full ApplicationContext — all beans, auto-configuration, all layers. Slow (seconds). Use for integration tests.
- `@WebMvcTest(Controller.class)`: loads only the web layer (controllers, filters, `@ControllerAdvice`, `WebMvcConfigurer`). No service, no repository beans. Fast. Requires `@MockBean` for any service dependency.

**Q2. What is `@MockBean`?**
Creates a Mockito mock of the specified type AND registers it as a Spring bean. The mock replaces any existing bean of that type in the ApplicationContext. Use in Spring slice tests (`@WebMvcTest`, `@DataJpaTest`) when you need to stub out a dependency.

**Q3. What is `MockMvc` and how do you use it?**
A test utility that simulates HTTP requests to Spring MVC controllers without starting an actual HTTP server. Allows asserting status codes, response body, headers:
```java
mockMvc.perform(get("/api/orders/123").header("Authorization", "Bearer token"))
    .andExpect(status().isOk())
    .andExpect(jsonPath("$.status").value("CONFIRMED"));
```

**Q4. What is `@DataJpaTest`?**
Loads only the JPA layer: repositories, entities, `DataSource`, `EntityManager`. Uses H2 in-memory DB by default. Each test method is transactional and rolled back automatically. Fast and isolated from the web layer.

**Q5. What is `@BeforeEach` vs `@BeforeAll` in JUnit 5?**
- `@BeforeEach`: runs before each test method — fresh state per test
- `@BeforeAll`: runs once before any test in the class (`static` method required) — use for expensive setup (start container)
- Spring testing: prefer `@BeforeEach` with `@Transactional` for DB state; use `@BeforeAll` for Testcontainers.

---

## Advanced (L5 Senior)

**Q6. How do you use Testcontainers with Spring Boot?**
```java
@SpringBootTest
@Testcontainers
class OrderIntegrationTest {
    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    @DynamicPropertySource
    static void overrideProps(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", postgres::getJdbcUrl);
        registry.add("spring.datasource.username", postgres::getUsername);
        registry.add("spring.datasource.password", postgres::getPassword);
    }

    @Test
    void shouldPersistOrder() {
        // Uses real PostgreSQL in Docker — not H2
    }
}
```
`@DynamicPropertySource` injects container URLs into Spring's environment before context starts.

**Q7. What is the difference between `@MockBean` and `@SpyBean`?**
- `@MockBean`: complete mock — all methods return null/default unless stubbed. No real implementation.
- `@SpyBean`: wraps the real bean — real methods called unless specifically stubbed (`doReturn(...).when(spy).method()`). Use when you need real behavior but want to verify or override one specific method.

```java
// MockBean — stub everything
@MockBean
private EmailService emailService;
when(emailService.send(any())).thenReturn(true);

// SpyBean — real behavior, verify specific call
@SpyBean
private AuditService auditService;
// real auditService.log() called; you just want to verify it was
verify(auditService).log(eq("ORDER_CREATED"), any());
```

**Q8. Why do you need `entityManager.flush()` and `entityManager.clear()` in JPA tests?**
- `flush()`: pushes pending changes (inserts, updates) from Hibernate's first-level cache to the DB
- `clear()`: evicts all entities from first-level cache

Without `clear()`: `findById()` after `save()` returns the cached entity from L1, not from the DB — you're testing the cache, not the query. With `clear()`: next query hits the DB — you're testing the actual persistence.

**Q9. How do you test `@Transactional` behavior — specifically, that a transaction COMMITS?**
Don't put `@Transactional` on the test method. A test-level `@Transactional` automatically rolls back after the test — you can't verify commit behavior. Instead:
```java
@Test
// NO @Transactional here
void shouldCommitTransaction() {
    orderService.createOrder(req);  // commits internally
    // Query from a fresh connection verifies the commit
    assertThat(orderRepository.findById(savedId)).isPresent();
    // Cleanup manually
    orderRepository.deleteById(savedId);
}
```

**Q10. What is the `@AutoConfigureTestDatabase` annotation?**
`@DataJpaTest` replaces the real DataSource with H2 by default. `@AutoConfigureTestDatabase(replace = NONE)` disables this replacement — uses the real configured datasource (or Testcontainers). Use when your queries use DB-specific features (PostgreSQL JSON, array types) that H2 doesn't support.

---

## Principal Engineer Level

**Q11. How do you design a test strategy for a Spring Boot microservice at FAANG scale?**

Three-tier strategy:
```
Layer               | Tool                          | Count  | Speed  | Purpose
--------------------|-------------------------------|--------|--------|--------
Unit                | JUnit 5 + Mockito             | 70%    | ★★★★★ | Business logic, edge cases
Slice               | @WebMvcTest, @DataJpaTest     | 20%    | ★★★★  | Layer contracts, validation
Integration         | @SpringBootTest + Testcontainers| 10%  | ★★     | Full request flow, migrations
```

CI strategy:
- Unit + slice tests: run on every commit (< 2 minutes)
- Integration tests: run on PR merge to main (< 15 minutes)
- Contract tests (Pact): run before any API change reaches consumers
- Performance baseline: run nightly; alert on > 10% regression

**Q12. How do you test event-driven behavior (Kafka consumers) in Spring?**
```java
@SpringBootTest
@EmbeddedKafka(partitions = 1, topics = {"orders.created"})
class OrderConsumerTest {

    @Autowired
    private KafkaTemplate<String, OrderEvent> kafkaTemplate;

    @Autowired
    private OrderRepository orderRepository;

    @Test
    void shouldProcessOrderEvent() throws Exception {
        OrderEvent event = new OrderEvent(UUID.randomUUID(), "CREATED");
        kafkaTemplate.send("orders.created", event.getOrderId().toString(), event);

        // Wait for consumer to process (async)
        await().atMost(Duration.ofSeconds(10))
               .until(() -> orderRepository.findById(event.getOrderId()).isPresent());

        assertThat(orderRepository.findById(event.getOrderId()))
            .isPresent()
            .get()
            .extracting(Order::getStatus)
            .isEqualTo(OrderStatus.PROCESSING);
    }
}
```
`@EmbeddedKafka` starts an in-process Kafka broker; `Awaitility` handles the async timing.

**Q13. How do you test Spring Security authorization rules without mocking the entire security chain?**
```java
@WebMvcTest(OrderController.class)
@Import(SecurityConfig.class)  // import real security config
class OrderSecurityTest {

    @MockBean
    private JwtDecoder jwtDecoder;  // mock the token decoder

    @Test
    @WithMockUser(roles = "USER")
    void userCanReadOrders() throws Exception {
        mockMvc.perform(get("/api/orders")).andExpect(status().isOk());
    }

    @Test
    @WithMockUser(roles = "USER")
    void userCannotDeleteOrders() throws Exception {
        mockMvc.perform(delete("/api/admin/orders/123")).andExpect(status().isForbidden());
    }

    @Test
    void unauthenticatedReturns401() throws Exception {
        mockMvc.perform(get("/api/orders")).andExpect(status().isUnauthorized());
    }
}
```

---

## Code Walkthroughs

**Q14. What is wrong with this test?**
```java
@DataJpaTest
class OrderRepositoryTest {
    @Autowired
    private OrderRepository orderRepository;

    @Test
    void shouldFindOrderByCustomerId() {
        orderRepository.save(new Order("customer-1", PENDING));

        List<Order> orders = orderRepository.findByCustomerId("customer-1");

        assertThat(orders).hasSize(1);
    }
}
```
**Answer**: This test will likely pass, but it's testing the first-level cache, not the database query. After `save()`, the entity is in Hibernate's L1 cache. `findByCustomerId()` may trigger a flush but the result may come from memory. Fix: add `entityManager.flush(); entityManager.clear();` between save and find to evict the entity and force a real DB query.

**Q15. Why does the mocked service method always return null?**
```java
@WebMvcTest(OrderController.class)
class OrderControllerTest {
    @Autowired MockMvc mockMvc;
    @Mock  // WRONG — should be @MockBean
    OrderService orderService;

    @Test
    void test() throws Exception {
        when(orderService.findById(any())).thenReturn(Optional.of(new Order()));
        mockMvc.perform(get("/orders/123")).andExpect(status().isOk());
    }
}
```
**Answer**: `@Mock` creates a Mockito mock in isolation — it's NOT registered in the Spring ApplicationContext. The controller gets the real (unregistered) `OrderService` injected by Spring, not the mock. Replace `@Mock` with `@MockBean` — this creates the mock AND registers it as the `OrderService` bean in the context.

---

## Common Mistakes

| Mistake | Problem | Fix |
|---------|---------|-----|
| `@SpringBootTest` for all tests | Slow suite (minutes vs seconds) | Use slices; `@SpringBootTest` sparingly |
| `@Mock` instead of `@MockBean` | Mock not registered in context; null or real bean injected | Use `@MockBean` in Spring test classes |
| No `entityManager.clear()` in JPA tests | Testing L1 cache, not DB | Always `flush()` + `clear()` before asserting |
| `@Transactional` on tests that verify commit | Rollback hides commit behavior | Remove `@Transactional` from test; cleanup manually |
| `H2` for PostgreSQL-specific features | Tests pass, prod fails | `@AutoConfigureTestDatabase(replace=NONE)` + Testcontainers |
| Not using `Awaitility` for async tests | Race condition; flaky tests | Use `await().atMost(10s).until(condition)` |
