# Spring Cloud — Interview Questions

---

## Fundamentals (L3–L4)

**Q1. What problem does Spring Cloud Config solve?**
In microservices, each service has its own config file — updating a shared property (DB URL, feature flag) requires redeploying every service. Config Server centralizes config in a Git repo; services fetch config at startup. Update config in Git → refresh services via `/actuator/refresh` (with `@RefreshScope`) or Spring Cloud Bus (broadcast refresh to all instances).

**Q2. What is Eureka and what does it do?**
Eureka is a service registry (Netflix OSS). Services register themselves on startup with their host/port/health URL. Other services query Eureka to discover where to send requests instead of hardcoding IPs. Supports client-side load balancing: the calling service fetches all instances and picks one.

**Q3. What is a Feign Client?**
A declarative HTTP client. You define an interface annotated with `@FeignClient`; Spring generates the HTTP implementation at startup. Instead of manually building `RestTemplate` calls, you write: `@GetMapping("/inventory/{id}") InventoryResponse getInventory(@PathVariable String id)` — Feign handles serialization, error handling, and load balancing.

**Q4. What is a Circuit Breaker and why does it matter?**
When a downstream service is failing, calling it repeatedly wastes threads and propagates failure. A circuit breaker monitors failure rate; when it exceeds a threshold, the circuit "opens" — all calls are rejected immediately (or use a fallback) without contacting the downstream. After a configured wait, it allows a few "test" calls through (half-open). If they succeed, it closes. Prevents cascading failures.

**Q5. What is Spring Cloud Gateway?**
A reactive API gateway built on WebFlux/Netty. Handles: routing (which upstream to call), load balancing, rate limiting, auth, CORS, retry, and circuit breaking — all via configuration or custom filters. Single entry point for all external traffic.

---

## Advanced (L5 Senior)

**Q6. How does Resilience4j's circuit breaker work in Spring Cloud?**
State machine with three states:
- **CLOSED**: normal operation; failure rate tracked in a sliding window (count or time-based)
- **OPEN**: circuit broken; calls rejected immediately (fast fail); fallback method invoked
- **HALF-OPEN**: after wait duration; N test calls permitted; success → CLOSED; failure → OPEN

Key parameters: `failureRateThreshold` (50% = open after half fail), `slidingWindowSize` (track last 10 calls), `waitDurationInOpenState` (30s before half-open), `permittedCallsInHalfOpenState` (3 test calls).

**Q7. What happens when Spring Cloud Config Server is unreachable at startup?**
With `spring.cloud.config.fail-fast=true` (recommended for production): the service fails to start with `IllegalStateException` — better to crash than to start with stale/wrong config. Without `fail-fast`: service starts with local `application.yml` defaults — may be running with outdated config silently.

Mitigation: Config Server HA (multiple instances), retry on startup (`spring.cloud.config.retry.max-attempts=6`), Kubernetes-native: use ConfigMaps as fallback.

**Q8. How does `@RefreshScope` work?**
Beans annotated with `@RefreshScope` are a special type of Scope. When `/actuator/refresh` is called: Spring destroys the current instance and creates a fresh one on the next access. This re-evaluates all `@Value` and `@ConfigurationProperties` with the latest config. Note: `@Autowired` dependencies of the refreshed bean are NOT refreshed — only the bean itself.

**Q9. How does client-side load balancing work with Spring Cloud LoadBalancer?**
`lb://service-name` in Gateway or `@FeignClient(name = "service-name")` triggers the load balancer. `SpringCloudLoadBalancer` fetches the service instance list from Eureka (or K8s discovery), applies a strategy (round-robin default), and picks an instance. The list is cached locally and refreshed periodically. No external load balancer hop — the caller makes the decision.

**Q10. How do you configure distributed tracing in Spring Cloud?**
```yaml
management.tracing.sampling.probability: 0.1  # 10% sampling — critical at FAANG scale
```
`Micrometer Tracing` auto-instruments: HTTP requests (adds trace/span IDs to headers), Kafka messages (propagates in headers), scheduled tasks. Exports to Zipkin/Tempo/Jaeger. `traceId` appears in MDC automatically — every log line carries it.

---

## Principal Engineer Level

**Q11. How would you design a zero-downtime deployment strategy using Spring Cloud Gateway?**

Canary deployment:
```yaml
routes:
  - id: orders-stable
    uri: lb://orders-service
    predicates:
      - Path=/api/v1/orders/**
      - Weight=group1, 95
  - id: orders-canary
    uri: lb://orders-service-v2
    predicates:
      - Path=/api/v1/orders/**
      - Weight=group1, 5
```
Start at 5% canary → monitor error rate, latency, and business metrics → increase to 20%, 50%, 100%. Automated rollback: if error rate rises, Route weights can be updated via Config Server refresh or Git push without deploying new Gateway version.

**Q12. How do you handle cascading failure across 20 microservices?**

Layered defense:
1. **Timeouts**: every Feign/WebClient call has a timeout (connect=2s, read=10s) — prevents thread exhaustion
2. **Bulkhead**: Resilience4j `ThreadPoolBulkhead` — isolate each downstream in its own thread pool; one failing service can't consume all threads
3. **Circuit breaker per downstream**: open independently; no global circuit
4. **Fallback**: graceful degradation — return cached response, partial response, or empty list
5. **Retry with jitter**: `Retry.backoff(3, 500ms).jitter(0.5)` — prevents synchronized retry storms

Design rule: if a service has 5 downstream dependencies and each has 99% availability, the service has `0.99^5 = 95%` availability without circuit breakers. With circuit breakers + fallbacks: achieve 99.9% effective availability.

**Q13. When would you NOT use Spring Cloud and use Kubernetes-native solutions instead?**

Spring Cloud was designed for VM-era microservices where service discovery and config were application-layer concerns. In Kubernetes:
- Service discovery → Kubernetes Services + CoreDNS (no Eureka needed)
- Load balancing → kube-proxy / Envoy sidecar (no client-side LB needed)
- Circuit breaking → Istio / Linkerd service mesh (infrastructure, not application)
- Config → ConfigMaps + Secrets (no Config Server needed)
- Distributed tracing → OpenTelemetry sidecar (no Sleuth needed)

Keep Spring Cloud when: non-K8s environments, need client-side LB fine-tuning, team has existing Spring Cloud expertise, or infrastructure team doesn't support a service mesh.

---

## Code Walkthroughs

**Q14. Why is this circuit breaker not opening?**
```yaml
resilience4j:
  circuitbreaker:
    instances:
      paymentService:
        slidingWindowSize: 100
        failureRateThreshold: 50
```
```java
// Only 3 calls made in the last hour; 2 failed
// Circuit is still CLOSED
```
**Answer**: Sliding window is 100 calls — the failure rate is calculated only after 100 calls complete. With only 3 calls, the minimum call count hasn't been reached. Fix: lower `minimumNumberOfCalls` (default = `slidingWindowSize`):
```yaml
minimumNumberOfCalls: 5  # calculate after 5 calls
```

**Q15. What is wrong with this retry configuration?**
```java
@Retry(name = "inventoryService")
@CircuitBreaker(name = "inventoryService", fallbackMethod = "fallback")
public InventoryResponse check(String productId) { ... }
```
```yaml
resilience4j:
  retry:
    instances:
      inventoryService:
        maxAttempts: 5
  circuitbreaker:
    instances:
      inventoryService:
        slidingWindowSize: 10
        failureRateThreshold: 50
```
**Answer**: Retry (5 attempts) is nested inside CircuitBreaker. A single failing call triggers 5 retries — the circuit breaker sees 5 failures from 1 logical call. The circuit will open after just 2 logical calls (10 total failures / 50% threshold). Intent: usually, either retry OR circuit breaker — not both on the same method for the same failure type. If you need both: apply retry inside circuit breaker scope, and tune sliding window to match retry * logical calls.

---

## Common Mistakes

| Mistake | Problem | Fix |
|---------|---------|-----|
| No `fail-fast` on Config Server client | Starts with wrong config silently | `spring.cloud.config.fail-fast=true` |
| Circuit breaker with no fallback | `CallNotPermittedException` crashes caller | Always define `fallbackMethod` |
| Retry on non-idempotent operations | Double-posting orders, double-charging | Only retry GET; for POST, use idempotency keys |
| No timeout on Feign client | Thread hangs indefinitely | Always set connect and read timeouts |
| High sampling rate in tracing | Zipkin overwhelmed at FAANG scale | `sampling.probability: 0.05` (5%) in production |
