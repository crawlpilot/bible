# Spring Boot — Interview Questions

---

## Fundamentals (L3–L4)

**Q1. What does `@SpringBootApplication` do?**
It is a meta-annotation combining three annotations:
- `@ComponentScan`: scans the package and sub-packages for beans
- `@EnableAutoConfiguration`: triggers Spring Boot's auto-configuration mechanism
- `@SpringBootConfiguration`: marks as a configuration class (source of `@Bean` definitions)

**Q2. What is a Spring Boot Starter?**
A starter is a curated POM that pulls in a compatible set of dependencies for a specific concern. `spring-boot-starter-web` brings Spring MVC, Tomcat, Jackson, and Spring Core — all version-compatible. Eliminates manual dependency version management.

**Q3. What is the difference between `application.yml` and `application.properties`?**
Functionally equivalent — both configure the same properties. YAML supports nested structure and multi-document files (`---`); `.properties` is flatter and simpler. Team preference; Spring Boot supports both. Cannot mix them for the same key — YAML takes precedence if both exist.

**Q4. What is Spring Boot Actuator?**
A library that adds production management endpoints with zero code: `/actuator/health` (liveness/readiness), `/actuator/metrics` (Micrometer), `/actuator/loggers` (runtime log level), `/actuator/info` (build metadata), `/actuator/env` (config inspection).

**Q5. How do Spring profiles work?**
`@Profile("prod")` marks a bean that only loads when `prod` profile is active. Profile-specific config files (`application-prod.yml`) override base config. Activated via `SPRING_PROFILES_ACTIVE=prod` or `--spring.profiles.active=prod`. Multiple profiles can be active: `SPRING_PROFILES_ACTIVE=prod,us-east-1`.

---

## Advanced (L5 Senior)

**Q6. How does Spring Boot auto-configuration work internally?**
1. `@EnableAutoConfiguration` imports `AutoConfigurationImportSelector`
2. `AutoConfigurationImportSelector` reads all class names from `META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports` (Boot 2.7+; previously `spring.factories`)
3. Each listed class is annotated with `@AutoConfiguration` and filtered by `@Conditional*` annotations
4. Only auto-configs whose conditions are met become actual `@Configuration` classes
5. Debug with `--debug` flag or `/actuator/conditions`

**Q7. What are the `@Conditional` annotations in Spring Boot and when do you use each?**

| Annotation | Condition |
|------------|-----------|
| `@ConditionalOnClass` | Class present on classpath |
| `@ConditionalOnMissingClass` | Class absent from classpath |
| `@ConditionalOnBean` | A bean of given type exists |
| `@ConditionalOnMissingBean` | No bean of given type exists |
| `@ConditionalOnProperty` | A property has a specific value |
| `@ConditionalOnWebApplication` | Running as web app |
| `@ConditionalOnExpression` | SpEL expression evaluates to true |
| `@ConditionalOnCloudPlatform` | Running on specific cloud |

**Q8. What is the difference between `@Value` and `@ConfigurationProperties`?**

| | `@Value` | `@ConfigurationProperties` |
|-|---------|--------------------------|
| Binding | Single property | Structured group of properties |
| Type conversion | SpEL-based | Jackson-based, supports `Duration`, `DataSize` |
| IDE support | Limited | Full (auto-complete in YAML/properties) |
| Validation | None | `@Validated` + JSR-303 constraints |
| Nested objects | No | Yes |
| Use for | One-off properties, simple | Any group of 3+ related properties |

**Q9. What is the Spring Boot configuration property hierarchy?**
Highest priority wins (simplified):
1. Command-line args: `--server.port=9090`
2. `SPRING_APPLICATION_JSON` env var
3. OS environment variables: `SERVER_PORT=9090` (relaxed binding)
4. Profile-specific: `application-prod.yml`
5. Base: `application.yml`
6. `@PropertySource` annotations
7. Default values in `@ConfigurationProperties`

**Q10. How does Spring Boot handle graceful shutdown?**
```yaml
server:
  shutdown: graceful
spring:
  lifecycle:
    timeout-per-shutdown-phase: 30s  # wait up to 30s for in-flight requests
```
On `SIGTERM`: stops accepting new requests → waits for in-flight requests to complete → shuts down context → invokes `@PreDestroy` / `DisposableBean.destroy()`. Essential for Kubernetes pod rollouts.

---

## Principal Engineer Level

**Q11. How would you create a custom Spring Boot starter for a shared internal library (e.g., company-wide audit logging)?**

Structure:
```
audit-spring-boot-starter/
├── audit-spring-boot-autoconfigure/
│   ├── src/main/java/com/example/audit/AuditAutoConfiguration.java
│   ├── src/main/java/com/example/audit/AuditProperties.java
│   └── src/main/resources/META-INF/spring/
│       └── org.springframework.boot.autoconfigure.AutoConfiguration.imports
└── audit-spring-boot-starter/
    └── pom.xml  (depends on autoconfigure + audit library)
```

```java
@AutoConfiguration
@ConditionalOnClass(AuditService.class)      // only if library on classpath
@ConditionalOnMissingBean(AuditService.class) // don't replace user-defined bean
@EnableConfigurationProperties(AuditProperties.class)
public class AuditAutoConfiguration {
    @Bean
    public AuditService auditService(AuditProperties props) {
        return new AuditService(props.getLevel(), props.isAsync());
    }
}
```
Teams add `audit-spring-boot-starter` as dependency → get `AuditService` auto-configured with zero config.

**Q12. How do you tune Spring Boot for production performance?**
- Lazy initialization: `spring.main.lazy-initialization=true` — cuts startup time significantly; trade-off: first request is slower
- JVM settings: `-XX:+UseG1GC`, `-Xms512m`, `-Xmx2g`, `-XX:MaxGCPauseMillis=200`
- Tomcat thread pool: `server.tomcat.max-threads=400` — match to DB connection pool size
- Connection pool: `spring.datasource.hikari.maximum-pool-size=20` — HikariCP default 10 is often too small
- Compression: `server.compression.enabled=true` — reduces bandwidth significantly for JSON APIs
- Actuator: expose only required endpoints; separate management port to prevent external exposure

**Q13. How do you handle secrets in Spring Boot at FAANG scale?**
Never store secrets in `application.yml` or environment variables directly. Strategy:
1. **Vault**: `spring-cloud-vault` — Spring reads secrets from HashiCorp Vault at startup; supports dynamic secrets and rotation
2. **AWS Secrets Manager**: `spring-cloud-aws-secrets-manager` — `spring.config.import=aws-secretsmanager:/my/secret`
3. **Kubernetes Secrets + External Secrets Operator**: inject into pod env vars or volume mounts
4. **Spring Cloud Config Server with Vault backend**: centralized config + secret management

---

## Code Walkthroughs

**Q14. What happens when you add `spring-boot-starter-data-jpa` but don't configure a datasource?**
Spring Boot auto-configuration tries to create `DataSource` — fails with `DataSourceAutoConfiguration` error because no `spring.datasource.url` is configured. Exception: `Failed to configure a DataSource: 'url' attribute is not specified`. Fix: configure the datasource OR exclude auto-config: `@SpringBootApplication(exclude = DataSourceAutoConfiguration.class)`.

**Q15. Why does this custom bean get ignored?**
```java
@Bean
public DataSource myDataSource() {
    return DataSourceBuilder.create().url("jdbc:h2:mem:test").build();
}

// In application.yml:
spring:
  datasource:
    url: jdbc:postgresql://prod-db:5432/orders
```
**Answer**: It doesn't get ignored — it overrides auto-configuration. Spring Boot's `DataSourceAutoConfiguration` is annotated with `@ConditionalOnMissingBean(DataSource.class)` — since you defined `myDataSource`, the auto-config is skipped entirely. But the `application.yml` properties are NOT used because they feed `DataSourceProperties` which feeds the auto-configured bean. Your `myDataSource()` bean is the only `DataSource`.

---

## Common Mistakes

| Mistake | Problem | Fix |
|---------|---------|-----|
| Exposing actuator on public port | Security risk — exposes internal state | `management.server.port=8081`; firewall internally only |
| Using `@Value` for grouped config | Verbose, not validated, no IDE help | `@ConfigurationProperties(prefix="...")` |
| Not setting `server.shutdown=graceful` | In-flight requests killed on deploy | Always enable in production |
| Relying on application startup order | Brittle; order not guaranteed | Use `ApplicationRunner` / `@DependsOn` only when truly necessary |
| Logging secrets via `/actuator/env` | Credential leak | Use `spring.config.import` for secrets; mask in actuator |
