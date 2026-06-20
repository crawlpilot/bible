# Spring Boot — Auto-Configuration, Starters, and Production Readiness

Spring Boot eliminates boilerplate Spring configuration. Its core value: **convention over configuration** — sensible defaults for 80% of use cases, full override capability for the remaining 20%.

---

## Origins & Motivation

Pre-Boot Spring required: XML or Java config, manual dependency version management, explicit bean wiring for every framework integration. A "Hello World" REST service required ~30 lines of config. Spring Boot (2014) reduced this to zero — a single `@SpringBootApplication` bootstraps a production-ready application.

---

## Core Architecture

```
  @SpringBootApplication
         │
         ├── @ComponentScan          ← scans current package + sub-packages
         ├── @EnableAutoConfiguration ← triggers auto-configuration magic
         └── @SpringBootConfiguration ← marks as @Configuration source

  @EnableAutoConfiguration
         │
         └── AutoConfigurationImportSelector
                    │
                    └── Reads: META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports
                               (Spring Boot 2.7+; previously spring.factories)
                               │
                               └── Loads 150+ AutoConfiguration classes
                                   Each filtered by @Conditional annotations:
                                   @ConditionalOnClass, @ConditionalOnMissingBean,
                                   @ConditionalOnProperty, @ConditionalOnWebApplication
```

---

## Auto-Configuration Deep Dive

```java
// Spring Boot ships this (you never write it):
@AutoConfiguration
@ConditionalOnClass(DataSource.class)           // only if JDBC on classpath
@ConditionalOnMissingBean(DataSource.class)     // only if no DataSource defined already
@EnableConfigurationProperties(DataSourceProperties.class)
public class DataSourceAutoConfiguration {

    @Bean
    @ConditionalOnMissingBean
    public DataSourceInitializer dataSourceInitializer(...) { ... }

    @Bean
    public DataSource dataSource(DataSourceProperties properties) {
        return DataSourceBuilder.create()
            .url(properties.getUrl())
            .username(properties.getUsername())
            .build();
    }
}
```

**How to override auto-config**: Define your own `@Bean` of the same type — `@ConditionalOnMissingBean` ensures the auto-config one is skipped.

**How to debug auto-config**: Run with `--debug` flag or call `/actuator/conditions`. Shows every auto-config class and whether it was applied or why it was skipped.

---

## Starters

Starters are **curated dependency POMs** — they pull in a compatible set of libraries with no version conflicts:

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-web</artifactId>
    <!-- Pulls in: spring-webmvc, jackson, tomcat-embed, spring-core, etc. -->
</dependency>
```

| Starter | What It Brings |
|---------|---------------|
| `spring-boot-starter-web` | Spring MVC, Tomcat, Jackson |
| `spring-boot-starter-webflux` | Spring WebFlux, Netty, Reactor |
| `spring-boot-starter-data-jpa` | Hibernate, Spring Data JPA, HikariCP |
| `spring-boot-starter-security` | Spring Security, filter chain |
| `spring-boot-starter-actuator` | Health, metrics, info endpoints |
| `spring-boot-starter-test` | JUnit 5, Mockito, AssertJ, MockMvc |
| `spring-boot-starter-cache` | Spring Cache abstraction |
| `spring-boot-starter-kafka` | Spring Kafka, Kafka client |

**Creating a custom starter**:
```
my-starter/
├── my-starter-autoconfigure/   ← AutoConfiguration class + META-INF entry
└── my-starter/                 ← just a POM that depends on autoconfigure + libs
```

---

## `@ConfigurationProperties`

Typesafe, structured configuration binding — preferred over `@Value` for anything non-trivial:

```java
@ConfigurationProperties(prefix = "payment")
@Validated
public class PaymentProperties {
    @NotBlank
    private String apiKey;
    private Duration timeout = Duration.ofSeconds(30);  // default value
    private Retry retry = new Retry();

    @Data
    public static class Retry {
        private int maxAttempts = 3;
        private Duration backoff = Duration.ofMillis(500);
    }
}
```

```yaml
# application.yml
payment:
  api-key: ${PAYMENT_API_KEY}
  timeout: 15s
  retry:
    max-attempts: 5
    backoff: 1s
```

**Benefits over `@Value`**: IDE completion, type conversion, validation, nested objects, no SpEL required.

---

## Configuration Hierarchy (Priority — highest wins)

```
1. Command-line arguments           --server.port=9090
2. SPRING_APPLICATION_JSON env var
3. OS environment variables         SERVER_PORT=9090
4. application-{profile}.yml        application-prod.yml
5. application.yml                  base config
6. @PropertySource annotations
7. Default property values          (in @ConfigurationProperties)
```

**Production pattern**: Ship `application.yml` with defaults → override with env-specific `application-prod.yml` → override secrets via OS environment variables injected by Kubernetes/Vault.

---

## Profiles

```java
@Configuration
@Profile("prod")
public class ProdConfig {
    @Bean
    public DataSource prodDataSource() { ... }
}

@Configuration
@Profile("!prod")  // all profiles except prod
public class LocalConfig {
    @Bean
    public DataSource h2DataSource() { ... }
}
```

```yaml
# application-prod.yml — activated by SPRING_PROFILES_ACTIVE=prod
spring:
  datasource:
    url: jdbc:postgresql://prod-db:5432/orders
```

**Multi-profile**: `SPRING_PROFILES_ACTIVE=prod,us-east-1` — both applied, last one wins for overlapping keys.

---

## Actuator

Production-grade management endpoints bundled with no extra code:

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,loggers,conditions,env
  endpoint:
    health:
      show-details: when-authorized   # never expose details publicly
  server:
    port: 8081  # separate management port — NEVER expose 8080 externally
```

| Endpoint | Purpose |
|----------|---------|
| `/actuator/health` | Kubernetes liveness/readiness probe target |
| `/actuator/metrics` | Micrometer metrics (request count, latency, JVM) |
| `/actuator/info` | Build version, git commit — useful for deploy verification |
| `/actuator/loggers` | Change log level at runtime without restart |
| `/actuator/conditions` | Debug auto-configuration decisions |
| `/actuator/env` | Inspect resolved configuration (mask secrets!) |
| `/actuator/httptrace` | Recent HTTP request/response history |

### Custom Health Indicator

```java
@Component
public class KafkaHealthIndicator implements HealthIndicator {
    @Override
    public Health health() {
        try {
            kafkaAdmin.describeTopics(List.of("orders"));
            return Health.up().withDetail("broker", "reachable").build();
        } catch (Exception e) {
            return Health.down().withDetail("error", e.getMessage()).build();
        }
    }
}
```

---

## Embedded Server Tuning

```yaml
server:
  port: 8080
  tomcat:
    max-threads: 200          # thread pool for blocking I/O
    min-spare-threads: 20
    connection-timeout: 20000
    max-connections: 10000
    accept-count: 100         # queue size when all threads busy
  compression:
    enabled: true
    mime-types: application/json,text/html
    min-response-size: 1024
```

**Tomcat vs Netty**: Use Tomcat for traditional blocking REST APIs. Switch to Netty (`spring-boot-starter-webflux`) for event-loop-based reactive applications. They are mutually exclusive.

---

## ApplicationRunner / CommandLineRunner

```java
@Component
@Order(1)
public class DataLoader implements ApplicationRunner {
    @Override
    public void run(ApplicationArguments args) {
        // Runs after ApplicationContext fully initialized
        // Use for: cache warmup, schema validation, initial data seeding
    }
}
```

---

## Spring Boot Test Optimizations

```java
// Slow: loads full ApplicationContext
@SpringBootTest

// Fast: loads only web layer (controllers, filters) — no service/repo
@WebMvcTest(OrderController.class)

// Fast: loads only JPA layer — no web layer
@DataJpaTest

// Fast: loads only Redis layer
@DataRedisTest

// Fastest: no Spring context at all — pure unit test
// Just use JUnit + Mockito directly
```

---

## Design Patterns Used

| Pattern | Where in Spring Boot |
|---------|---------------------|
| **Template Method** | `SpringApplication.run()` defines the startup sequence; hooks (runners, listeners) fill in steps |
| **Factory** | Auto-configuration creates beans on behalf of the application |
| **Decorator** | `@ConditionalOnMissingBean` — existing bean decorates/replaces auto-configured one |
| **Observer** | `SpringApplicationEvent` hierarchy — lifecycle hooks via `ApplicationListener` |
| **Strategy** | `BannerPrinter`, `SpringApplicationRunListener` — pluggable startup behaviors |
| **Composite** | `CompositeHealthContributor` — multiple health checks aggregated as one |

---

## Trade-offs

| Aspect | Benefit | Cost |
|--------|---------|------|
| Auto-configuration | Zero config for common cases | Hard to debug unexpected bean wiring |
| Fat JAR | Single deployable artifact | Large image size; not ideal for layered Docker |
| Opinionated defaults | Works out of the box | Fighting defaults when requirements differ |
| Actuator | Ops visibility with zero code | Security risk if exposed without auth |
| Classpath scanning | No explicit wiring | Ambiguous beans, slow startup on huge classpaths |

---

## FAANG Interview Callout

1. **"How does Spring Boot auto-configuration work?"**
   - `@EnableAutoConfiguration` triggers `AutoConfigurationImportSelector`
   - Reads `META-INF/spring/...AutoConfiguration.imports`
   - Each config class filtered by `@Conditional*` — only applied when conditions met
   - Debug with `--debug` or `/actuator/conditions`

2. **"How do you override an auto-configured bean?"**
   - Define your own `@Bean` of the same type — `@ConditionalOnMissingBean` skips the auto-config
   - Or `@AutoConfigureBefore`/`@AutoConfigureAfter` to control ordering

3. **"What's the difference between `@Value` and `@ConfigurationProperties`?"**
   - `@Value`: single property, SpEL, no IDE support, no validation
   - `@ConfigurationProperties`: structured binding, type-safe, validated, IDE-completed — use this

4. **"How does Spring Boot handle multiple environments?"**
   - Profile-specific files (`application-prod.yml`) override base `application.yml`
   - Env vars and command-line args override everything — 12-factor app pattern

5. **"How do you expose metrics from a Spring Boot service?"**
   - `spring-boot-starter-actuator` + Micrometer dependency
   - Auto-wires `MeterRegistry`; metrics exposed at `/actuator/prometheus`
   - Add custom metrics: `meterRegistry.counter("orders.created").increment()`
