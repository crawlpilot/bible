# 42. Rate Limiter / Throttle
**Category**: Infrastructure / Resource Management  
**GoF**: No  
**Complexity**: Medium  
**Frequency in FAANG interviews**: Very Common (often a standalone LLD problem)

> Control the rate at which requests are processed — protecting services from overload, enforcing API quotas per client, and preventing abuse — by rejecting or queuing requests that exceed a configurable threshold.

---

## Problem It Solves

Without rate limiting: a single misconfigured client fires 50,000 RPS at the payment API → DB connection pool exhaustion → payment latency spikes for all clients → cascading failure across checkout. With rate limiting: that client is throttled to 1,000 RPS (their quota); all other clients continue operating normally. Rate limiting solves: resource protection (infrastructure), fairness (multi-tenant), abuse prevention (security), and cost control (third-party API spend).

## Five Algorithms — Comparison

| Algorithm | Window Type | Memory per key | Burst Handling | Implementation |
|-----------|------------|---------------|----------------|----------------|
| Fixed Window Counter | Hard resets per period | O(1) | Allows 2× burst at window boundary | Simplest |
| Sliding Window Log | Exact per-request timestamps | O(requests in window) | No burst | Memory-intensive at high rate |
| Sliding Window Counter | Weighted blend of two windows | O(1) | Approximate — ±10% | Best balance |
| Token Bucket | Continuous refill | O(1) | Yes — up to bucket capacity | Industry standard |
| Leaky Bucket | Queue with fixed drain rate | O(queue depth) | Smooths to exact rate | Good for traffic shaping |

---

## Structure (Participants)

```
  Client Request
       │
       ▼
  RateLimiterMiddleware
  ┌──────────────────────────────────────────────┐
  │  1. Extract client key (API key / user ID)   │
  │  2. Check limiter for key                    │
  │       ├── ALLOWED → forward to service       │
  │       └── THROTTLED → 429 Too Many Requests  │
  │            + Retry-After header              │
  └──────────────────────────────────────────────┘
         │
         ▼
  RateLimiter (algorithm-specific)
         │
         ▼
  StateStore (Redis / in-memory)
```

---

## Real-World Use Case: API Gateway Rate Limiter

Payment API: 1,000 requests/minute per API key. Public search: 100 req/s per IP. Internal services: 10,000 req/s per service identity.

### Algorithm 1: Token Bucket

Classic algorithm. Tokens accumulate at a fixed rate (refill rate) up to a maximum (bucket capacity). Each request consumes one token. Allows bursting up to bucket capacity.

```java
// Token bucket — Redis-backed for distributed rate limiting
public class TokenBucketRateLimiter {
    private final RedisTemplate<String, String> redis;
    private final int      capacity;       // max tokens (burst size)
    private final double   refillRatePerMs; // tokens added per millisecond

    private static final String BUCKET_TOKENS    = ":tokens";
    private static final String BUCKET_LAST_REFILL = ":last_refill";

    public TokenBucketRateLimiter(RedisTemplate<String, String> redis,
                                   int capacity, int refillRatePerSecond) {
        this.redis            = redis;
        this.capacity         = capacity;
        this.refillRatePerMs  = refillRatePerSecond / 1000.0;
    }

    public RateLimitResult tryAcquire(String clientKey) {
        // Lua script for atomic check-and-consume (prevents TOCTOU race)
        String luaScript = """
            local tokens_key = KEYS[1]
            local timestamp_key = KEYS[2]
            local capacity = tonumber(ARGV[1])
            local refill_rate = tonumber(ARGV[2])
            local now = tonumber(ARGV[3])
            local requested = tonumber(ARGV[4])
            
            local last_refill = tonumber(redis.call('get', timestamp_key) or now)
            local current_tokens = tonumber(redis.call('get', tokens_key) or capacity)
            
            -- Calculate tokens to add since last refill
            local elapsed = math.max(0, now - last_refill)
            local new_tokens = math.min(capacity, current_tokens + elapsed * refill_rate)
            
            if new_tokens >= requested then
                -- Allow request
                redis.call('set', tokens_key, new_tokens - requested, 'EX', 3600)
                redis.call('set', timestamp_key, now, 'EX', 3600)
                return {1, math.floor(new_tokens - requested)}
            else
                -- Reject request
                local retry_after_ms = math.ceil((requested - new_tokens) / refill_rate)
                redis.call('set', timestamp_key, now, 'EX', 3600)
                return {0, retry_after_ms}
            end
            """;

        List<Object> result = redis.execute(
            new DefaultRedisScript<>(luaScript, List.class),
            List.of(clientKey + BUCKET_TOKENS, clientKey + BUCKET_LAST_REFILL),
            String.valueOf(capacity),
            String.valueOf(refillRatePerMs),
            String.valueOf(System.currentTimeMillis()),
            "1"
        );

        boolean allowed      = ((Number) result.get(0)).intValue() == 1;
        long    remaining    = ((Number) result.get(1)).longValue();

        return new RateLimitResult(allowed, remaining,
            allowed ? 0 : remaining);  // remaining = tokens if allowed; retry-after-ms if rejected
    }
}
```

### Algorithm 2: Sliding Window Counter

Most memory-efficient approximation of a true sliding window. Uses two fixed-window counters and a weighted blend.

```java
public class SlidingWindowRateLimiter {
    private final RedisTemplate<String, Long> redis;
    private final int  limit;           // requests per window
    private final long windowSizeMs;

    public SlidingWindowRateLimiter(RedisTemplate<String, Long> redis,
                                     int limit, Duration windowSize) {
        this.redis         = redis;
        this.limit         = limit;
        this.windowSizeMs  = windowSize.toMillis();
    }

    public RateLimitResult tryAcquire(String clientKey) {
        long now            = System.currentTimeMillis();
        long currentWindow  = now / windowSizeMs;
        long prevWindow     = currentWindow - 1;
        double elapsed      = (now % windowSizeMs) / (double) windowSizeMs;  // 0.0 → 1.0

        String currentKey   = clientKey + ":" + currentWindow;
        String prevKey      = clientKey + ":" + prevWindow;

        Long currentCount = redis.opsForValue().get(currentKey);
        Long prevCount    = redis.opsForValue().get(prevKey);

        long cur  = currentCount != null ? currentCount : 0L;
        long prev = prevCount    != null ? prevCount    : 0L;

        // Weighted blend: prev contributes remaining fraction of window
        double weightedCount = prev * (1.0 - elapsed) + cur;

        if (weightedCount + 1 > limit) {
            long retryAfterMs = (long) ((1 - elapsed) * windowSizeMs);
            return RateLimitResult.rejected(retryAfterMs);
        }

        // Increment current window counter
        Long newCount = redis.opsForValue().increment(currentKey);
        redis.expire(currentKey, Duration.ofMillis(windowSizeMs * 2));  // keep 2 windows
        return RateLimitResult.allowed(limit - newCount);
    }
}
```

### Algorithm 3: Fixed Window Counter (simplest)

```java
public class FixedWindowRateLimiter {
    private final RedisTemplate<String, Long> redis;
    private final int      limit;
    private final Duration window;

    public RateLimitResult tryAcquire(String clientKey) {
        long   windowStart = System.currentTimeMillis() / window.toMillis();
        String key         = clientKey + ":" + windowStart;

        Long count = redis.opsForValue().increment(key);
        if (count == 1) {
            redis.expire(key, window);  // set TTL on first increment
        }

        if (count > limit) {
            // Calculate time until window resets
            long retryAfterMs = window.toMillis() -
                (System.currentTimeMillis() % window.toMillis());
            return RateLimitResult.rejected(retryAfterMs);
        }
        return RateLimitResult.allowed(limit - count);
    }
}
```

### HTTP Middleware Integration

```java
// Spring / Jakarta servlet filter
@Component
@Order(1)
public class RateLimitFilter extends OncePerRequestFilter {
    private final RateLimiter rateLimiter;
    private final ApiKeyExtractor keyExtractor;

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain chain)
            throws ServletException, IOException {

        String clientKey = keyExtractor.extract(request);
        RateLimitResult result = rateLimiter.tryAcquire(clientKey);

        // Standard rate-limit response headers (IETF draft-ietf-httpapi-ratelimit-headers)
        response.setHeader("X-RateLimit-Limit",     String.valueOf(result.limit()));
        response.setHeader("X-RateLimit-Remaining", String.valueOf(result.remaining()));
        response.setHeader("X-RateLimit-Reset",     String.valueOf(result.resetEpochSeconds()));

        if (!result.allowed()) {
            response.setHeader("Retry-After",
                String.valueOf(result.retryAfterSeconds()));
            response.sendError(HttpStatus.TOO_MANY_REQUESTS.value(),
                "Rate limit exceeded. Retry after " + result.retryAfterSeconds() + "s.");
            return;
        }
        chain.doFilter(request, response);
    }
}
```

### Multi-Tier Rate Limiting Strategy

```
Global → Per-service → Per-endpoint → Per-client

Example:
  Global:         100,000 req/s  (protect infrastructure)
  Service:         10,000 req/s  (protect payment service)
  Endpoint POST /charge:  1,000 req/s  (protect DB write path)
  Client (API key):    100 req/min (API quota enforcement)
  Client (IP):          50 req/min (unauthenticated users)
```

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | `RateLimiter` only decides allow/reject; `RateLimitFilter` only handles HTTP; `RedisStore` handles persistence |
| Open/Closed | ✅ | Swap algorithm (TokenBucket ↔ SlidingWindow) without changing filter or client code |
| Liskov Substitution | ✅ | All algorithms implement `RateLimiter.tryAcquire(key)` — interchangeable |
| Interface Segregation | ✅ | `RateLimiter` exposes `tryAcquire()` only — callers don't need to know the algorithm |
| Dependency Inversion | ✅ | Filter depends on `RateLimiter` interface; Redis store is injected |

---

## When to Use

- Public-facing APIs with per-client quotas
- Protecting critical downstream resources (DB, payment providers, third-party APIs)
- Fairness in multi-tenant systems — prevent noisy neighbours
- Cost control on paid third-party APIs

## When NOT to Use

- Single-tenant internal services behind a trusted network — adds latency and complexity
- Load shedding at infrastructure level — use load balancer circuit breakers instead
- Flow control between producer and consumer — use backpressure (reactive streams) instead

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Protects downstream resources from overload | Redis dependency: rate limiter is useless if Redis is down — needs fallback (fail-open or fail-closed) |
| Fairness across clients — noisy neighbour cannot starve others | Distributed race: multiple instances incrementing the same key must use Lua scripts or INCR + NX for atomicity |
| Predictable resource consumption | Clients must handle 429 with exponential backoff — many clients implement this poorly |
| Token Bucket allows legitimate bursting | Fixed Window allows 2× burst at boundary — use Sliding Window if exact enforcement is required |

---

**FAANG interview application**: "The rate limiter is a very common LLD interview question — walk through at least Token Bucket and Sliding Window Counter. For distributed rate limiting, the key insight is: use Redis Lua scripts for atomic read-increment-check — a plain INCR followed by a GET is not atomic and causes races under high concurrency. For global rate limiting at scale (e.g. Google, Meta), use a distributed token bucket backed by a consistent store, but supplement with local in-memory token buckets (refreshed from Redis every 100ms) to avoid Redis becoming a single hot path. The typical quota hierarchy is: global → per-service → per-endpoint → per-API-key → per-IP."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Circuit Breaker](../modern/29-circuit-breaker.md) | Rate Limiter proactively throttles at the entry point; Circuit Breaker reactively detects downstream failure — both protect services but at different layers |
| [Bulkhead](../modern/33-bulkhead.md) | Bulkhead isolates resource pools; Rate Limiter controls request arrival rate — complementary |
| [Object Pool](../modern/38-object-pool.md) | Rate limiter protects the pool from being exhausted by bounding inbound request rate |
| [Proxy](../structural/12-proxy.md) | Rate limiter is typically implemented as a Proxy or middleware that intercepts every inbound request |
