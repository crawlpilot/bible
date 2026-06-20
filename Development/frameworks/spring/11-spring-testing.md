# Spring Testing — Test Slices, MockMvc, Testcontainers, and Test Strategy

Spring Testing provides a rich testing ecosystem built on JUnit 5. Understanding which testing tool to reach for — and why — is the difference between a fast, reliable test suite and a slow, flaky one that engineers learn to distrust.

---

## Testing Pyramid for Spring Applications

```
         /\
        /  \
       / E2E \         ← Few: Selenium, Playwright (full browser)
      /────────\
     / Integration \   ← Some: @SpringBootTest + Testcontainers
    /──────────────\
   / Slice Tests    \  ← Many: @WebMvcTest, @DataJpaTest, @DataRedisTest
  /──────────────────\
 / Unit Tests         \ ← Most: JUnit 5 + Mockito (no Spring context)
/──────────────────────\

Rule: Most tests should be at the bottom (fast). Fewer at top (slow).
```

---

## Test Types — Choosing the Right Tool

| Annotation | What It Loads | Speed | Use For |
|------------|--------------|-------|---------|
| None (plain JUnit) | Nothing | ★★★★★ | Business logic, pure functions, domain objects |
| `@WebMvcTest` | Web layer only (controllers, filters) | ★★★★ | REST endpoints, request/response mapping, validation |
| `@DataJpaTest` | JPA layer only (repos, entities) | ★★★★ | Repository queries, entity mappings, transactions |
| `@DataRedisTest` | Redis layer only | ★★★☆ | Redis repositories, RedisTemplate operations |
| `@RestClientTest` | HTTP client + JSON | ★★★★ | `RestTemplate`, `WebClient`, FeignClient |
| `@SpringBootTest` | Full context | ★★ | Integration tests, full request flow |
| `@SpringBootTest` + Testcontainers | Full context + real DB | ★ | End-to-end, migration tests |

---

## Unit Tests — No Spring Context

```java
class OrderServiceTest {

    // No @ExtendWith(SpringExtension.class) — pure JUnit 5 + Mockito
    @Mock
    private OrderRepository orderRepository;

    @Mock
    private PaymentGateway paymentGateway;

    @InjectMocks
    private OrderService orderService;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
    }

    @Test
    void shouldCreateOrderWhenPaymentSucceeds() {
        // Given
        CreateOrderRequest req = new CreateOrderRequest("product-1", 2, "user-1");
        Order savedOrder = new Order(UUID.randomUUID(), "user-1", OrderStatus.PENDING);
        when(orderRepository.save(any(Order.class))).thenReturn(savedOrder);
        when(paymentGateway.authorize(any())).thenReturn(new PaymentResult(true, "auth-123"));

        // When
        Order result = orderService.createOrder(req);

        // Then
        assertThat(result.getStatus()).isEqualTo(OrderStatus.CONFIRMED);
        verify(orderRepository).save(argThat(order ->
            order.getCustomerId().equals("user-1") &&
            order.getStatus() == OrderStatus.PENDING));
    }

    @Test
    void shouldThrowWhenPaymentFails() {
        when(paymentGateway.authorize(any())).thenThrow(new PaymentDeclinedException("Insufficient funds"));

        assertThatThrownBy(() -> orderService.createOrder(req))
            .isInstanceOf(PaymentDeclinedException.class)
            .hasMessageContaining("Insufficient funds");

        verify(orderRepository, never()).save(any());
    }
}
```

---

## @WebMvcTest — Controller Slice

```java
@WebMvcTest(OrderController.class)  // only loads web layer — no service/repo beans
class OrderControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean  // creates a Mockito mock and registers it as Spring bean
    private OrderService orderService;

    @Autowired
    private ObjectMapper objectMapper;

    @Test
    void shouldReturn201WhenOrderCreated() throws Exception {
        // Given
        CreateOrderRequest req = new CreateOrderRequest("product-1", 2);
        Order order = new Order(UUID.randomUUID(), OrderStatus.CONFIRMED);
        when(orderService.createOrder(any())).thenReturn(order);

        // When / Then
        mockMvc.perform(post("/api/v1/orders")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(req))
                .header("Authorization", "Bearer test-token"))
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.status").value("CONFIRMED"))
            .andExpect(jsonPath("$.id").isNotEmpty())
            .andDo(print());  // prints request/response for debugging
    }

    @Test
    void shouldReturn400WhenRequestInvalid() throws Exception {
        mockMvc.perform(post("/api/v1/orders")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"productId": "", "quantity": 0}
                    """))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.errors").isArray())
            .andExpect(jsonPath("$.errors[*].field",
                containsInAnyOrder("productId", "quantity")));
    }

    @Test
    @WithMockUser(roles = "USER")  // simulates authenticated user
    void shouldReturn403ForAdminEndpoint() throws Exception {
        mockMvc.perform(delete("/api/v1/admin/orders/some-id"))
            .andExpect(status().isForbidden());
    }
}
```

---

## @DataJpaTest — Repository Slice

```java
@DataJpaTest  // loads JPA layer + H2 in-memory by default
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)  // use real DB
@Import(JpaAuditingConfig.class)  // import if @CreatedDate etc. needed
class OrderRepositoryTest {

    @Autowired
    private OrderRepository orderRepository;

    @Autowired
    private TestEntityManager entityManager;

    @Test
    void shouldFindPendingOrdersForCustomer() {
        // Given — persist test data
        entityManager.persist(new Order("customer-1", OrderStatus.PENDING));
        entityManager.persist(new Order("customer-1", OrderStatus.COMPLETED));
        entityManager.persist(new Order("customer-2", OrderStatus.PENDING));
        entityManager.flush();
        entityManager.clear();  // evict from L1 cache — next query hits DB

        // When
        List<Order> orders = orderRepository.findByCustomerIdAndStatus("customer-1", OrderStatus.PENDING);

        // Then
        assertThat(orders).hasSize(1);
        assertThat(orders.get(0).getStatus()).isEqualTo(OrderStatus.PENDING);
    }

    @Test
    void shouldReturnEmptyWhenNoOrders() {
        assertThat(orderRepository.findByCustomerId("non-existent")).isEmpty();
    }
}
```

---

## Testcontainers — Real Dependencies in Tests

```java
@SpringBootTest
@Testcontainers
class OrderIntegrationTest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine")
        .withDatabaseName("orders_test")
        .withUsername("test")
        .withPassword("test");

    @Container
    static KafkaContainer kafka = new KafkaContainer(DockerImageName.parse("confluentinc/cp-kafka:7.5.0"));

    @Container
    static GenericContainer<?> redis = new GenericContainer<>("redis:7-alpine")
        .withExposedPorts(6379);

    @DynamicPropertySource  // inject container URLs into Spring context
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", postgres::getJdbcUrl);
        registry.add("spring.datasource.username", postgres::getUsername);
        registry.add("spring.datasource.password", postgres::getPassword);
        registry.add("spring.kafka.bootstrap-servers", kafka::getBootstrapServers);
        registry.add("spring.redis.host", redis::getHost);
        registry.add("spring.redis.port", () -> redis.getMappedPort(6379));
    }

    @Autowired
    private OrderService orderService;

    @Autowired
    private OrderRepository orderRepository;

    @Test
    void shouldPersistOrderAndPublishEvent() {
        CreateOrderRequest req = new CreateOrderRequest("product-1", 1, "customer-1");

        Order order = orderService.createOrder(req);

        assertThat(order.getId()).isNotNull();
        assertThat(orderRepository.findById(order.getId())).isPresent();
        // verify Kafka event published...
    }
}
```

### Shared Testcontainers (Reuse Across Tests)

```java
// Shared base class — containers started once for all test classes
@SpringBootTest
@Testcontainers
public abstract class IntegrationTestBase {

    @Container
    static PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:16-alpine")
        .withReuse(true);  // reuse across runs (needs ~/.testcontainers.properties)

    @DynamicPropertySource
    static void props(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
    }
}

class OrderRepositoryIntegrationTest extends IntegrationTestBase { ... }
class PaymentRepositoryIntegrationTest extends IntegrationTestBase { ... }
```

---

## @MockBean vs @SpyBean

```java
// @MockBean — full mock, all methods return default/null unless stubbed
@MockBean
private PaymentGateway paymentGateway;
// paymentGateway.authorize(any()) returns null by default

// @SpyBean — real implementation, but can stub specific methods
@SpyBean
private EmailService emailService;
// emailService.sendEmail() calls real implementation
// doReturn("OK").when(emailService).sendEmail(any()); // stub just this one
```

**Rule**: Use `@MockBean` for external dependencies (HTTP clients, payment gateways). Use `@SpyBean` when you need the real implementation but want to verify or stub one specific interaction.

---

## Test Slices for Other Technologies

```java
// WebFlux controller testing
@WebFluxTest(OrderReactiveController.class)
class OrderReactiveControllerTest {
    @Autowired
    private WebTestClient webTestClient;

    @Test
    void shouldStreamOrders() {
        webTestClient.get().uri("/api/v1/orders/stream")
            .accept(MediaType.TEXT_EVENT_STREAM)
            .exchange()
            .expectStatus().isOk()
            .expectBodyList(Order.class).hasSize(3);
    }
}

// JSON serialization testing
@JsonTest
class OrderDtoJsonTest {
    @Autowired
    private JacksonTester<OrderDto> json;

    @Test
    void shouldSerializeOrderDto() throws Exception {
        OrderDto dto = new OrderDto(UUID.randomUUID(), OrderStatus.CONFIRMED);
        assertThat(json.write(dto)).hasJsonPathStringValue("$.status", "CONFIRMED");
    }
}
```

---

## Testing @Transactional

```java
@DataJpaTest
class TransactionalBehaviorTest {

    @Test
    @Transactional  // rolled back after test — no DB cleanup needed
    void shouldRollbackOnException() {
        // ...
    }

    @Test
    // No @Transactional on test — commits are permanent
    // Must clean up manually; needed when testing transaction commit behavior
    void shouldCommitWhenTransactionCompletes() {
        orderService.createOrder(req);
        // data is committed — can verify from another session
    }
}
```

---

## Design Patterns Used

| Pattern | Where in Spring Testing |
|---------|------------------------|
| **Stub** | `@MockBean` — returns controlled values |
| **Spy** | `@SpyBean` — wraps real object, records calls |
| **Test Double** | `MockMvc` — simulates HTTP without real server |
| **Builder** | `MockMvcRequestBuilders` — fluent request construction |
| **Fixture** | `@BeforeEach` / `@BeforeAll` — shared test state |
| **Container** | Testcontainers — standardize external dependencies |

---

## Testing Best Practices

| Practice | Why |
|----------|-----|
| Test behavior, not implementation | Tests survive refactoring |
| One assertion per logical unit | Clear failure messages |
| `@DataJpaTest` over `@SpringBootTest` for repo tests | 10x faster |
| `TestEntityManager.flush()` + `clear()` before asserting | Ensures query hits DB, not L1 cache |
| Use `@DynamicPropertySource` for container URLs | Clean, supports parallel test execution |
| Avoid `@Transactional` on integration tests that test commit behavior | Hides real behavior |
| Separate unit and integration tests in CI | Unit tests in every commit; integration tests in PR/merge |

---

## FAANG Interview Callout

1. **"What test slices does Spring Boot provide and when do you use each?"**
   - `@WebMvcTest`: controller, validation, exception handling
   - `@DataJpaTest`: repository queries, entity mapping, transactions
   - `@SpringBootTest`: full context, use sparingly — slow

2. **"What's the difference between `@MockBean` and `@Mock`?"**
   - `@Mock` (Mockito): mock without Spring context — use in pure unit tests
   - `@MockBean` (Spring): creates mock AND registers it as a Spring bean — use in slice tests

3. **"How do you test that a transaction actually rolled back?"**
   - `@Transactional` on the test method auto-rolls back — test environment only
   - To test real commit/rollback: use Testcontainers with real DB, no `@Transactional` on test

4. **"How do you test a Kafka consumer?"**
   - Testcontainers Kafka: `KafkaContainer`, produce a test message, verify the consumer processed it
   - Or `EmbeddedKafka` for faster in-process testing (less realistic)

5. **"How do you ensure test isolation when tests share a database?"**
   - `@Transactional` + rollback per test (default in `@DataJpaTest`)
   - Or Testcontainers with `withReuse(false)` — fresh container per test class
   - Or manual cleanup in `@AfterEach` using `deleteAll()` on repository
