# 12. Proxy
**Category**: Structural  
**GoF**: Yes  
**Complexity**: Medium  
**Frequency in FAANG interviews**: Common

> Provide a surrogate or placeholder for another object to control access to it.

---

## Problem It Solves

A microservice calls the Service Registry 200 times/second to resolve service endpoints. Each call to the actual registry hits ZooKeeper (network round-trip ~5ms). At 200 calls/sec, that's 200 unnecessary network calls per second when service locations change at most once per minute. A `ServiceRegistryProxy` caches results locally with a 30-second TTL, falling back to the real registry only on cache miss or expiry — without the calling code knowing or caring.

## Structure (Participants)

```
        «interface»
       ServiceRegistry
  ┌────────────────────────────┐
  │ + resolve(serviceName):    │
  │     ServiceEndpoint        │
  │ + register(name, endpoint) │
  │ + deregister(name)         │
  └────────────────────────────┘
              △
    ┌─────────┴──────────────────┐
    │                            │
ZookeeperRegistry        ServiceRegistryProxy
(Real Subject)           ┌──────────────────────────────┐
                         │ - real: ServiceRegistry       │
                         │ - cache: Map<String,Entry>    │
                         │ - circuitBreaker: CB          │
                         │ + resolve(name): Endpoint     │
                         │   → check cache               │
                         │   → if miss: call real + cache│
                         │   → if real unavailable: CB   │
                         └──────────────────────────────┘
```

Key participants:
- **Subject** (`ServiceRegistry`): the interface both real and proxy implement
- **Real Subject** (`ZookeeperRegistry`): the actual service being proxied
- **Proxy** (`ServiceRegistryProxy`): controls access — adds caching, circuit breaking, lazy loading, auth
- **Client**: calls `ServiceRegistry` interface — unaware it's hitting a proxy

---

## Real-World Use Case: Service Registry Proxy (Caching + Circuit Breaker)

A platform's service mesh resolves ~50 downstream services. The Service Registry (ZooKeeper/Consul/Eureka) is the source of truth, but calling it on every HTTP request is wasteful. `ServiceRegistryProxy` adds a local TTL cache (30s) and a circuit breaker — if ZooKeeper is down, the proxy returns the last known endpoints rather than failing every request.

A second use: **Virtual Proxy / Lazy Loading** — `UserProfileProxy` defers loading a user's full profile from the database until a field is actually accessed.

### Implementation

```java
// Subject interface
public interface ServiceRegistry {
    ServiceEndpoint resolve(String serviceName);
    void register(String serviceName, ServiceEndpoint endpoint);
    void deregister(String serviceName);
    List<ServiceEndpoint> resolveAll(String serviceName);  // for load balancing
}

// Real Subject — talks to ZooKeeper
public class ZookeeperServiceRegistry implements ServiceRegistry {
    private final CuratorFramework curator;

    @Override
    public ServiceEndpoint resolve(String serviceName) {
        try {
            byte[] data = curator.getData().forPath("/services/" + serviceName);
            return ServiceEndpoint.deserialize(data);
        } catch (Exception e) {
            throw new ServiceRegistryException("Failed to resolve " + serviceName, e);
        }
    }

    @Override
    public void register(String serviceName, ServiceEndpoint endpoint) { /* ... */ }

    @Override
    public void deregister(String serviceName) { /* ... */ }

    @Override
    public List<ServiceEndpoint> resolveAll(String serviceName) { /* ... */ }
}

// Cache entry with TTL
private record CacheEntry(ServiceEndpoint endpoint, Instant expiresAt) {
    boolean isExpired() { return Instant.now().isAfter(expiresAt); }
}

// Proxy — caching + circuit breaker + stale-while-revalidate
public class ServiceRegistryProxy implements ServiceRegistry {
    private final ServiceRegistry real;
    private final Map<String, CacheEntry> cache = new ConcurrentHashMap<>();
    private final Duration ttl;
    private final CircuitBreaker circuitBreaker;

    public ServiceRegistryProxy(ServiceRegistry real, Duration ttl) {
        this.real = real;
        this.ttl = ttl;
        this.circuitBreaker = new CircuitBreaker(
            failureThreshold: 5,
            successThreshold: 2,
            openTimeout: Duration.ofSeconds(30)
        );
    }

    @Override
    public ServiceEndpoint resolve(String serviceName) {
        CacheEntry entry = cache.get(serviceName);

        // Cache hit — return immediately (even if slightly stale: stale-while-revalidate)
        if (entry != null && !entry.isExpired()) {
            return entry.endpoint();
        }

        // Cache miss or stale — try real registry
        if (circuitBreaker.isOpen()) {
            // Circuit open — use stale cache if available, otherwise fail
            if (entry != null) {
                log.warn("Circuit open; returning stale endpoint for {}", serviceName);
                return entry.endpoint();
            }
            throw new ServiceUnavailableException("Service registry circuit open, no cached entry for " + serviceName);
        }

        try {
            ServiceEndpoint endpoint = circuitBreaker.execute(() -> real.resolve(serviceName));
            cache.put(serviceName, new CacheEntry(endpoint, Instant.now().plus(ttl)));
            return endpoint;
        } catch (Exception e) {
            circuitBreaker.recordFailure();
            if (entry != null) {
                log.warn("Registry call failed; returning stale entry for {}", serviceName);
                return entry.endpoint();  // degrade gracefully with stale data
            }
            throw new ServiceRegistryException("Cannot resolve " + serviceName, e);
        }
    }

    @Override
    public void register(String serviceName, ServiceEndpoint endpoint) {
        // Write-through: update registry + invalidate cache
        real.register(serviceName, endpoint);
        cache.remove(serviceName);
    }

    @Override
    public void deregister(String serviceName) {
        real.deregister(serviceName);
        cache.remove(serviceName);
    }

    @Override
    public List<ServiceEndpoint> resolveAll(String serviceName) {
        return real.resolveAll(serviceName);  // not cached — always fresh for load balancing
    }
}

// Virtual Proxy — Lazy Loading example
public interface UserProfile {
    String getUserId();
    String getDisplayName();
    Address getShippingAddress();    // expensive — loads from DB
    List<PaymentMethod> getSavedPaymentMethods();  // expensive
    PurchaseHistory getPurchaseHistory();           // very expensive
}

public class LazyUserProfileProxy implements UserProfile {
    private final String userId;
    private final UserProfileRepository repo;
    private UserProfile realProfile;   // null until first access of expensive field

    public LazyUserProfileProxy(String userId, UserProfileRepository repo) {
        this.userId = userId;
        this.repo = repo;
    }

    @Override public String getUserId()      { return userId; }        // cheap — no DB
    @Override public String getDisplayName() { return userId; }        // cheap — cached

    @Override
    public Address getShippingAddress() {
        ensureLoaded();                                                // load on first access
        return realProfile.getShippingAddress();
    }

    @Override
    public List<PaymentMethod> getSavedPaymentMethods() {
        ensureLoaded();
        return realProfile.getSavedPaymentMethods();
    }

    @Override
    public PurchaseHistory getPurchaseHistory() {
        ensureLoaded();
        return realProfile.getPurchaseHistory();
    }

    private synchronized void ensureLoaded() {
        if (realProfile == null) {
            realProfile = repo.loadFullProfile(userId);
        }
    }
}

// Client — request routing service
public class RequestRouter {
    private final ServiceRegistry registry;   // injected — could be proxy or real

    public RequestRouter(ServiceRegistry registry) {
        this.registry = registry;
    }

    public HttpResponse route(String targetService, HttpRequest request) {
        ServiceEndpoint endpoint = registry.resolve(targetService);  // may hit cache
        return httpClient.send(request, endpoint.url());
    }
}

// Wiring — proxy transparent to client
ServiceRegistry real = new ZookeeperServiceRegistry(curator);
ServiceRegistry proxy = new ServiceRegistryProxy(real, Duration.ofSeconds(30));
RequestRouter router = new RequestRouter(proxy);   // client never knows it's a proxy
```

### How It Works (walkthrough)

1. `router.route("payment-service", request)` → calls `proxy.resolve("payment-service")`
2. First call: cache miss → circuit breaker closed → calls `real.resolve("payment-service")` → ZK → `10.0.1.5:8080`
3. Stores in cache with TTL 30s, returns endpoint
4. Next 200 calls in 30s: cache hit → returns `10.0.1.5:8080` immediately — no ZK calls
5. ZooKeeper goes down: circuit breaker opens after 5 failures → subsequent calls return stale cache entry
6. ZK recovers: circuit breaker half-opens, probe succeeds, circuit closes, cache refreshes

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ⚠️ | This proxy combines caching + circuit breaker — could split into two proxies |
| Open/Closed | ✅ | Add logging proxy by wrapping: `new LoggingProxy(new ServiceRegistryProxy(real))` |
| Liskov Substitution | ✅ | `ServiceRegistryProxy` is fully substitutable for `ZookeeperServiceRegistry` |
| Interface Segregation | ✅ | `ServiceRegistry` interface is focused |
| Dependency Inversion | ✅ | Client depends on `ServiceRegistry` interface |

---

## When to Use

- **Caching proxy**: expensive remote calls that can be served from cache most of the time
- **Virtual proxy**: lazy load expensive objects until first actual field access
- **Protection proxy**: add auth/authorization check before delegating to real object
- **Remote proxy**: represent a remote object locally (gRPC stub is a remote proxy)
- **Circuit breaker proxy**: prevent cascading failures to a downstream dependency

## When NOT to Use

- The real subject is cheap to access — proxy adds overhead for no benefit
- The proxy logic becomes more complex than the real subject — simplify the real subject instead
- If AOP (aspect-oriented programming) or middleware is available — caching/logging proxies are better implemented as aspects

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Transparent to client — no code changes needed to add caching | Extra indirection — one more call in the stack |
| Composable — stack proxies (caching proxy around circuit breaker proxy) | Stale cache risk — proxy may serve outdated data |
| Separates cross-cutting concerns (caching, auth) from business logic | More complex testing — must test proxy and real subject separately |

---

**FAANG interview application**: "Proxy is the right pattern when you need to add a cross-cutting concern (caching, auth, circuit breaking, rate limiting) to an existing interface without changing client code. In service mesh architectures, the sidecar proxy (Envoy, Linkerd) is literally this pattern at the infrastructure level — every service call goes through a proxy that handles retries, circuit breaking, observability, and mTLS. In application code, I'd wrap the service registry with a caching proxy that uses a 30-second TTL and falls back to stale entries when the registry is unavailable — implementing the stale-while-revalidate pattern."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Decorator](09-decorator.md) | Decorator adds behaviour; Proxy controls access. Both wrap with same interface. |
| [Adapter](06-adapter.md) | Adapter changes the interface; Proxy keeps it the same |
| [Facade](10-facade.md) | Facade simplifies many interfaces; Proxy controls access to one interface |
| [Circuit Breaker](../modern/29-circuit-breaker.md) | Circuit Breaker is often implemented as a Proxy pattern |
