# Spring Cloud — Distributed Systems Patterns for Microservices

Spring Cloud provides a toolkit for the common patterns that emerge in distributed microservice architectures: configuration management, service discovery, client-side load balancing, API gateway, circuit breaking, and distributed tracing. Each component addresses a specific failure mode of distributed systems.

---

## Spring Cloud Component Map

```
                    ┌─────────────────────────────┐
                    │     Spring Cloud Config      │  ← Centralized config
                    │   (01-config-server)         │
                    └──────────────┬──────────────┘
                                   │ config on startup
                    ┌──────────────▼──────────────┐
                    │  Service Registry (Eureka /  │  ← Service discovery
                    │  Consul / K8s)              │
                    └──────────────┬──────────────┘
                                   │ discover
          ┌────────────────────────▼────────────────────────┐
          │                Spring Cloud Gateway              │  ← API Gateway
          │    (routing, rate limiting, auth, tracing)       │
          └────────┬──────────────────────────┬─────────────┘
                   │ route                    │ route
       ┌───────────▼────────┐     ┌───────────▼────────┐
       │  Service A          │     │  Service B          │
       │  (Feign + LB)       │────▶│                    │
       │  (Resilience4j CB)  │     └────────────────────┘
       └────────────────────┘
                   │
       ┌───────────▼────────────────┐
       │  Distributed Tracing       │  ← Micrometer Tracing (Sleuth replacement)
       │  (Zipkin / Tempo / Jaeger) │
       └────────────────────────────┘
```

---

## 1. Spring Cloud Config

Centralize configuration across all services and environments.

```yaml
# Config Server — application.yml
spring:
  cloud:
    config:
      server:
        git:
          uri: https://github.com/myorg/config-repo
          search-paths: "{application}"  # folder per service
          default-label: main
          clone-on-start: true           # fail fast if git unreachable
```

```java
// Config Server — enable it
@SpringBootApplication
@EnableConfigServer
public class ConfigServerApplication { ... }
```

```yaml
# Client service — bootstrap.yml (loads before ApplicationContext)
spring:
  application:
    name: order-service          # maps to order-service.yml in config repo
  config:
    import: "configserver:http://config-server:8888"
  cloud:
    config:
      fail-fast: true            # crash if config server unreachable at startup
      retry:
        max-attempts: 6
        initial-interval: 1000
```

### Config Priority (highest first)
```
1. Profile-specific:  order-service-prod.yml
2. Service-specific:  order-service.yml
3. Global:            application.yml (in config repo)
4. Local:             application.yml (in service JAR)
```

### Dynamic Config Refresh
```java
@RestController
@RefreshScope  // bean is recreated when /actuator/refresh is called
public class FeatureController {
    @Value("${feature.new-checkout.enabled:false}")
    private boolean newCheckoutEnabled;
}
```

---

## 2. Service Discovery — Eureka

```java
// Eureka Server
@SpringBootApplication
@EnableEurekaServer
public class EurekaServerApplication { ... }

// Client service — registers on startup, queries for peers
// application.yml
eureka:
  client:
    service-url:
      defaultZone: http://eureka1:8761/eureka,http://eureka2:8761/eureka  # HA pair
  instance:
    prefer-ip-address: true
    lease-renewal-interval-in-seconds: 10  # heartbeat
    lease-expiration-duration-in-seconds: 30
```

**Eureka vs Kubernetes Service Discovery**:
| | Eureka | Kubernetes Services |
|-|--------|-------------------|
| Works in | Any environment | Kubernetes only |
| Client-side LB | Yes (Ribbon/LoadBalancer) | No (kube-proxy handles it) |
| Health checks | Self-reported heartbeat | Liveness/readiness probes |
| FAANG stance | Legacy; Kubernetes preferred | Standard in K8s-native deployments |

---

## 3. Feign Client — Declarative HTTP

```java
@FeignClient(
    name = "inventory-service",           // service name in registry
    fallback = InventoryClientFallback.class,
    configuration = FeignConfig.class
)
public interface InventoryClient {

    @GetMapping("/api/v1/inventory/{productId}")
    InventoryResponse getInventory(@PathVariable String productId);

    @PostMapping("/api/v1/inventory/reserve")
    ReservationResponse reserveItems(@RequestBody ReservationRequest req);
}

// Fallback — what to return when the call fails (circuit open or timeout)
@Component
public class InventoryClientFallback implements InventoryClient {
    @Override
    public InventoryResponse getInventory(String productId) {
        return InventoryResponse.unknown(productId);  // graceful degradation
    }

    @Override
    public ReservationResponse reserveItems(ReservationRequest req) {
        throw new ServiceUnavailableException("Inventory service unavailable");
    }
}

// Feign configuration — timeouts, logging, auth interceptor
@Configuration
public class FeignConfig {
    @Bean
    public Request.Options options() {
        return new Request.Options(2, TimeUnit.SECONDS,  // connect timeout
                                   10, TimeUnit.SECONDS,  // read timeout
                                   true);
    }

    @Bean
    public RequestInterceptor authInterceptor() {
        return template -> template.header("X-Service-Token", tokenProvider.getToken());
    }
}
```

---

## 4. Resilience4j — Circuit Breaker, Retry, Rate Limiter

```yaml
resilience4j:
  circuitbreaker:
    instances:
      inventoryService:
        sliding-window-size: 10
        failure-rate-threshold: 50          # open after 50% failures in window
        wait-duration-in-open-state: 30s    # wait before half-open
        permitted-calls-in-half-open-state: 3
        automatic-transition-from-open-to-half-open-enabled: true
  retry:
    instances:
      inventoryService:
        max-attempts: 3
        wait-duration: 500ms
        exponential-backoff-multiplier: 2   # 500ms → 1s → 2s
        retry-exceptions:
          - java.net.ConnectException
          - feign.RetryableException
        ignore-exceptions:
          - com.example.BusinessException   # don't retry business errors
  ratelimiter:
    instances:
      inventoryService:
        limit-for-period: 100
        limit-refresh-period: 1s
        timeout-duration: 0
  bulkhead:
    instances:
      inventoryService:
        max-concurrent-calls: 25
        max-wait-duration: 0ms
```

```java
@Service
public class OrderService {

    @CircuitBreaker(name = "inventoryService", fallbackMethod = "inventoryFallback")
    @Retry(name = "inventoryService")
    @Bulkhead(name = "inventoryService", type = Bulkhead.Type.THREADPOOL)
    public InventoryResponse checkInventory(String productId) {
        return inventoryClient.getInventory(productId);
    }

    private InventoryResponse inventoryFallback(String productId, Exception ex) {
        log.warn("Inventory circuit open for {}: {}", productId, ex.getMessage());
        return InventoryResponse.unknown(productId);
    }
}
```

### Circuit Breaker State Machine
```
         failure rate > threshold
  CLOSED ─────────────────────────► OPEN
    ▲                                  │
    │   success rate > threshold       │ wait-duration elapsed
    │                                  ▼
    └──────────────────────────── HALF-OPEN
                                  (test calls)
```

---

## 5. Spring Cloud Gateway

```java
@SpringBootApplication
public class GatewayApplication { ... }
```

```yaml
spring:
  cloud:
    gateway:
      routes:
        - id: order-service
          uri: lb://order-service        # lb:// = client-side load balancing via registry
          predicates:
            - Path=/api/v1/orders/**
            - Method=GET,POST,PUT
          filters:
            - StripPrefix=0
            - AddRequestHeader=X-Gateway-Source, api-gateway
            - CircuitBreaker=name=order-cb,fallbackUri=forward:/fallback
            - RequestRateLimiter=redis-rate-limiter,key-resolver=#{@ipKeyResolver}

        - id: static-public
          uri: lb://static-service
          predicates:
            - Path=/public/**
            - Weight=group1, 80          # canary: 80% to v1
        - id: static-canary
          uri: lb://static-service-v2
          predicates:
            - Path=/public/**
            - Weight=group1, 20          # canary: 20% to v2
      default-filters:
        - DedupeResponseHeader=Access-Control-Allow-Origin
```

```java
// Custom global filter — runs on every request
@Component
@Order(-1)  // before all other filters
public class AuthGatewayFilter implements GlobalFilter {
    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        String token = exchange.getRequest().getHeaders().getFirst("Authorization");
        if (!jwtValidator.isValid(token)) {
            exchange.getResponse().setStatusCode(HttpStatus.UNAUTHORIZED);
            return exchange.getResponse().setComplete();
        }
        return chain.filter(exchange);
    }
}
```

---

## 6. Distributed Tracing — Micrometer Tracing

```xml
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-tracing-bridge-brave</artifactId>  <!-- or bridge-otel -->
</dependency>
<dependency>
    <groupId>io.zipkin.reporter2</groupId>
    <artifactId>zipkin-reporter-brave</artifactId>
</dependency>
```

```yaml
management:
  tracing:
    sampling:
      probability: 0.1   # 10% sampling in prod — 100% is too expensive at FAANG scale
  zipkin:
    tracing:
      endpoint: http://zipkin:9411/api/v2/spans
```

Spring propagates `traceId` and `spanId` automatically across:
- HTTP headers (`X-B3-TraceId`, `X-B3-SpanId`, or `traceparent` in W3C format)
- Kafka message headers
- MDC (so logs contain trace IDs automatically)

---

## Design Patterns Used

| Pattern | Where in Spring Cloud |
|---------|----------------------|
| **Circuit Breaker** | Resilience4j — prevents cascading failures |
| **Gateway / Facade** | Spring Cloud Gateway — single entry point |
| **Service Locator** | Eureka — lookup services by name, not IP |
| **Retry** | Resilience4j Retry — transient failure recovery |
| **Bulkhead** | Resilience4j Bulkhead — isolate failure domains |
| **Sidecar** | Config Server client — externalizes config from service |
| **Ambassador** | Feign client — delegates inter-service communication |

---

## Trade-offs

| Component | Benefit | Cost |
|-----------|---------|------|
| Config Server | Centralized, environment-specific config | Single point of failure (mitigate with HA + cache) |
| Eureka | Self-registration, client-side LB | Consistency: AP model — stale registrations possible |
| Feign | Declarative HTTP clients | Hides complexity; harder to debug |
| Circuit Breaker | Prevents cascading failures | Tuning thresholds is hard; false positives cause outages |
| Gateway | Cross-cutting concerns centralized | Another network hop; single point of failure |

---

## FAANG Interview Callout

1. **"How do you handle service-to-service communication failures?"**
   - Timeouts + retries + circuit breaker (Resilience4j); exponential backoff with jitter; fallback responses; dead letter queues for async

2. **"What happens when the Config Server is down at startup?"**
   - `fail-fast: true` + retry configuration → service fails to start (safer than running with stale config)
   - Solution: Config Server HA, local cache of last-known config, or externalize via Kubernetes ConfigMaps

3. **"How does the Gateway apply rate limiting?"**
   - Redis-backed token bucket via `RequestRateLimiter` filter; key resolver determines the bucket key (IP, user ID, API key)

4. **"How do you do canary deployments with Spring Cloud Gateway?"**
   - Weight-based routing: `Weight=group, 80` → 80% traffic to stable, 20% to canary
   - Gradually increase canary weight as confidence builds

5. **"What's the difference between client-side and server-side load balancing?"**
   - Client-side (Ribbon/Spring Cloud LoadBalancer): client holds service list from registry, picks instance
   - Server-side (kube-proxy, Nginx, ALB): load balancer is a separate hop between clients
   - Client-side: lower latency, more control; but complex client logic
