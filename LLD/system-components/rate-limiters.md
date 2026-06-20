# Rate Limiting — Complete Deep-Dive

> Calibrated to principal engineer interview bar: all algorithms, Java implementations, trade-off tables, FAANG interview callouts.

---

## What Is Rate Limiting?

Rate limiting controls the rate of requests a client or service can send over a time window. It protects systems from:
- Abuse / DoS attacks
- Cascading failures (backpressure)
- Cost overruns (metered APIs)
- SLA violations for downstream dependencies

---

## The Seven Rate Limiting Algorithms

| Algorithm | Memory | Burst Handling | Precision | Complexity |
|-----------|--------|---------------|-----------|------------|
| Token Bucket | O(1) | Yes (up to capacity) | Medium | Low |
| Leaky Bucket | O(1) | No (strict output rate) | High | Low |
| Fixed Window Counter | O(1) | Yes (boundary spike) | Low | Very Low |
| Sliding Window Log | O(N) per user | Exact | Highest | High |
| Sliding Window Counter | O(1) | Approximate | High | Medium |
| Concurrent Request Limiter | O(1) | No | N/A | Low |
| Adaptive Rate Limiter | Variable | Dynamic | Dynamic | High |

---

## 1. Token Bucket

### How It Works

A bucket holds tokens up to capacity `C`. Tokens are added at rate `R` tokens/second. Each request consumes one token. If no token is available, the request is rejected or queued.

```
Bucket: [●●●●●○○○○○]  capacity=10, tokens=5
Refill: +R tokens/sec
Request: consume 1 token → if tokens >= 1: allow, else: reject
```

### Java Implementation

```java
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.locks.ReentrantLock;

public class TokenBucket {
    private final long capacity;
    private final double refillRatePerMs;      // tokens per millisecond
    private double tokens;
    private long lastRefillTimestamp;
    private final ReentrantLock lock = new ReentrantLock();

    public TokenBucket(long capacity, long refillRatePerSecond) {
        this.capacity = capacity;
        this.refillRatePerMs = refillRatePerSecond / 1000.0;
        this.tokens = capacity;
        this.lastRefillTimestamp = System.currentTimeMillis();
    }

    public boolean tryConsume(int tokensRequested) {
        lock.lock();
        try {
            refill();
            if (tokens >= tokensRequested) {
                tokens -= tokensRequested;
                return true;
            }
            return false;
        } finally {
            lock.unlock();
        }
    }

    private void refill() {
        long now = System.currentTimeMillis();
        double tokensToAdd = (now - lastRefillTimestamp) * refillRatePerMs;
        tokens = Math.min(capacity, tokens + tokensToAdd);
        lastRefillTimestamp = now;
    }
}
```

**Distributed version with Redis:**

```java
// Lua script for atomic token bucket in Redis
// Ensures no race conditions across multiple instances
String luaScript = """
    local tokens_key = KEYS[1]
    local timestamp_key = KEYS[2]
    local rate = tonumber(ARGV[1])
    local capacity = tonumber(ARGV[2])
    local now = tonumber(ARGV[3])
    local requested = tonumber(ARGV[4])

    local last_tokens = tonumber(redis.call('get', tokens_key))
    if last_tokens == nil then last_tokens = capacity end

    local last_refreshed = tonumber(redis.call('get', timestamp_key))
    if last_refreshed == nil then last_refreshed = 0 end

    local delta = math.max(0, now - last_refreshed)
    local filled_tokens = math.min(capacity, last_tokens + (delta * rate))
    local allowed = filled_tokens >= requested

    local new_tokens = filled_tokens
    if allowed then
        new_tokens = filled_tokens - requested
    end

    redis.call('setex', tokens_key, math.ceil(capacity/rate) + 1, new_tokens)
    redis.call('setex', timestamp_key, math.ceil(capacity/rate) + 1, now)

    return { allowed and 1 or 0, new_tokens }
    """;
```

### Advantages
- **Burst-friendly**: burst up to `capacity` tokens, perfect for APIs that expect bursty traffic
- **Constant memory**: O(1) per user regardless of request history
- **Simple implementation**: two fields (tokens + timestamp)
- **Works well for throttling without strict smoothing**

### Disadvantages
- **Burst can overwhelm downstream**: if capacity is large, a burst of `C` requests hits downstream simultaneously
- **Clock skew issues**: in distributed systems, nodes with different clocks refill at different rates
- **Not perfectly smooth**: output rate is variable

### Trade-offs

| Decision | Token Bucket Behavior |
|----------|----------------------|
| High `capacity`, high `rate` | Allows heavy bursts, generous throttling |
| Low `capacity`, high `rate` | Smooth output with small burst allowance |
| Low `capacity`, low `rate` | Strict limiting, minimal burst |
| High `capacity`, low `rate` | Rarely accumulates, mostly rejects |

### FAANG Interview Callout
> Stripe uses Token Bucket for their API rate limiter. AWS API Gateway uses token bucket per key. The key insight: **token bucket shapes traffic without destroying burstiness**, which is important for real user interactions where a user might legitimately send 5 requests in a second.

---

## 2. Leaky Bucket

### How It Works

Requests enter a FIFO queue (the "bucket"). A processor drains the queue at a fixed rate `R`. If the queue is full (depth `D`), incoming requests are dropped. Output is always at a constant rate — it "leaks" at exactly `R` req/sec.

```
Incoming: →→→→→→→→→→  (variable rate)
Queue:    [req][req][req][req]  depth=D
Outgoing: → → → →             (fixed rate R)
```

### Java Implementation

```java
import java.util.concurrent.*;

public class LeakyBucket {
    private final BlockingQueue<Runnable> queue;
    private final ScheduledExecutorService scheduler;

    public LeakyBucket(int queueDepth, long leakRatePerSecond) {
        this.queue = new LinkedBlockingQueue<>(queueDepth);
        this.scheduler = Executors.newSingleThreadScheduledExecutor();
        long delayMs = 1000L / leakRatePerSecond;

        scheduler.scheduleAtFixedRate(() -> {
            Runnable request = queue.poll();
            if (request != null) {
                request.run();
            }
        }, 0, delayMs, TimeUnit.MILLISECONDS);
    }

    // Returns true if request was accepted into queue
    public boolean submit(Runnable request) {
        return queue.offer(request);
    }

    public void shutdown() {
        scheduler.shutdown();
    }
}

// Usage
LeakyBucket limiter = new LeakyBucket(100, 50); // queue=100, 50 req/s output
boolean accepted = limiter.submit(() -> handleRequest(req));
if (!accepted) {
    sendResponse(429, "Too Many Requests");
}
```

**Simple counter-based variant (no actual queue):**

```java
public class LeakyBucketCounter {
    private final long capacity;
    private final long leakRatePerMs;
    private long water;           // current "water" level
    private long lastLeakTime;

    public synchronized boolean tryConsume() {
        long now = System.currentTimeMillis();
        long leaked = (now - lastLeakTime) * leakRatePerMs;
        water = Math.max(0, water - leaked);
        lastLeakTime = now;

        if (water < capacity) {
            water++;
            return true;
        }
        return false;
    }
}
```

### Advantages
- **Perfectly smooth output**: downstream always receives exactly `R` req/sec — ideal for protecting fragile backends
- **Natural backpressure**: queue provides buffer; burst is absorbed, not rejected immediately
- **Simple mental model**: physical analogy is intuitive

### Disadvantages
- **Kills legitimate bursts**: a user who hasn't made requests for an hour can't burst — they still wait in queue
- **Queue adds latency**: queued requests incur artificial delay even when system is idle
- **Memory per user**: if you queue per-user, memory grows with active users × queue depth
- **Starvation possible**: in priority systems, low-priority requests may never drain

### Trade-offs

| Leaky Bucket | Token Bucket |
|-------------|--------------|
| Fixed output rate | Variable output rate |
| Absorbs bursts with latency | Absorbs bursts immediately (up to capacity) |
| Better for smooth downstream | Better for responsive user experience |
| Queue can stale | No stale requests |

### When to Use
Use Leaky Bucket when **downstream cannot absorb variable load** — e.g., a legacy payment processor that needs exactly 100 req/sec, or a printer queue. Rarely the right choice for public API rate limiting.

---

## 3. Fixed Window Counter

### How It Works

Time is divided into fixed windows (e.g., 1-minute slots). Each user has a counter per window. If counter exceeds limit `L`, reject. Counter resets at window boundary.

```
Window: [0s --- 60s] [60s --- 120s] [120s --- 180s]
Count:       47            1               0
Limit:       50
```

### Java Implementation

```java
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

public class FixedWindowCounter {
    private final int limit;
    private final long windowSizeMs;
    private final ConcurrentHashMap<String, AtomicInteger> counters = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<String, Long> windowStart = new ConcurrentHashMap<>();

    public FixedWindowCounter(int limit, long windowSizeMs) {
        this.limit = limit;
        this.windowSizeMs = windowSizeMs;
    }

    public boolean tryConsume(String userId) {
        long now = System.currentTimeMillis();
        long currentWindowStart = (now / windowSizeMs) * windowSizeMs;

        windowStart.compute(userId, (k, existingStart) -> {
            if (existingStart == null || existingStart != currentWindowStart) {
                counters.put(userId, new AtomicInteger(0));
                return currentWindowStart;
            }
            return existingStart;
        });

        AtomicInteger counter = counters.get(userId);
        return counter.incrementAndGet() <= limit;
    }
}
```

**Redis implementation (atomic):**

```java
// Redis INCR + EXPIRE is atomic per command but not together
// Use Lua for true atomicity:
String luaScript = """
    local current = redis.call('incr', KEYS[1])
    if current == 1 then
        redis.call('expire', KEYS[1], ARGV[1])
    end
    return current
    """;

// Key format: "ratelimit:{userId}:{windowTimestamp}"
String key = "ratelimit:" + userId + ":" + (System.currentTimeMillis() / windowMs);
long count = (Long) jedis.eval(luaScript, 1, key, String.valueOf(windowSizeSeconds));
return count <= limit;
```

### Advantages
- **Simplest possible implementation**: one counter per user per window
- **O(1) memory per user**: just a counter and timestamp
- **Predictable reset**: users know exactly when their quota resets
- **Easy to explain to product teams**: "100 requests per minute"

### Disadvantages
- **Boundary spike (the critical flaw)**: A user can make 100 requests at 11:59:59 and 100 more at 12:00:01 — 200 requests in 2 seconds while the limit is 100/min
- **Unfair within window**: all 100 can be used in the first second; the remaining 59 seconds are blocked

### The Boundary Spike Problem

```
          Window 1             Window 2
|-------- 60s ---------|-------- 60s ---------|
                  [100 req]  [100 req]
                    ^                ^
                  23:59:59        00:00:01
                  
= 200 requests in 2 seconds! Limit is 100/min.
```

### When to Use
Use only when:
- Exact precision is not required
- Boundary spikes are acceptable (e.g., internal batch jobs)
- Simplicity is the highest priority (e.g., billing counters, not traffic shaping)

---

## 4. Sliding Window Log

### How It Works

Store a log of timestamps for each request. When a new request arrives, remove timestamps older than the window, then count remaining — if count < limit, allow and add new timestamp.

```
Window: last 60 seconds
Log: [t-55s, t-40s, t-30s, t-10s, t-5s]  → count=5
New request at t: remove t-55s (>60s old), count=4 → allow, log t
```

### Java Implementation

```java
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

public class SlidingWindowLog {
    private final int limit;
    private final long windowMs;
    // TreeMap for O(log N) range deletions
    private final ConcurrentHashMap<String, TreeMap<Long, Integer>> logs = new ConcurrentHashMap<>();

    public SlidingWindowLog(int limit, long windowMs) {
        this.limit = limit;
        this.windowMs = windowMs;
    }

    public synchronized boolean tryConsume(String userId) {
        long now = System.currentTimeMillis();
        long windowStart = now - windowMs;

        TreeMap<Long, Integer> log = logs.computeIfAbsent(userId, k -> new TreeMap<>());

        // Remove all entries older than window
        log.headMap(windowStart).clear();

        // Count requests in current window
        int requestCount = log.values().stream().mapToInt(Integer::intValue).sum();

        if (requestCount < limit) {
            // Use merge to handle multiple requests at exact same millisecond
            log.merge(now, 1, Integer::sum);
            return true;
        }
        return false;
    }
}
```

**Redis implementation using Sorted Set:**

```java
// ZADD adds with score=timestamp, ZREMRANGEBYSCORE removes old entries
// ZCARD counts current entries — all atomic via pipeline or Lua

String luaScript = """
    local key = KEYS[1]
    local now = tonumber(ARGV[1])
    local window_start = tonumber(ARGV[2])
    local limit = tonumber(ARGV[3])
    local request_id = ARGV[4]

    redis.call('zremrangebyscore', key, 0, window_start)
    local count = redis.call('zcard', key)

    if count < limit then
        redis.call('zadd', key, now, request_id)
        redis.call('expire', key, math.ceil((now - window_start) / 1000) + 1)
        return 1
    end
    return 0
    """;

long now = System.currentTimeMillis();
long windowStart = now - windowMs;
String requestId = UUID.randomUUID().toString();
long allowed = (Long) jedis.eval(luaScript, 1, 
    "ratelimit:" + userId, 
    String.valueOf(now), String.valueOf(windowStart), 
    String.valueOf(limit), requestId);
```

### Advantages
- **Exact precision**: no boundary spike — truly counts requests in the last `W` milliseconds
- **No burst at boundaries**: fair at all times
- **Correct implementation of "100 requests per minute"**

### Disadvantages
- **O(N) memory per user**: stores every request timestamp in the window — if limit=10,000 req/min, log has up to 10,000 entries
- **O(N) computation**: count requires iterating or summing the log
- **Memory bomb**: high-limit APIs with many users = enormous Redis footprint
- **Not suitable for high limits**: 1M req/hour = 1M entries per user

### Memory Estimation
```
1M users × 1000 req/min limit × 8 bytes/timestamp = 8 GB just for timestamps
```

### FAANG Interview Callout
> Sliding Window Log is the **theoretically correct** solution interviewers want you to derive first. Then pivot to Sliding Window Counter as the practical production solution. Showing you understand the space complexity problem and how to resolve it demonstrates principal-level thinking.

---

## 5. Sliding Window Counter (Hybrid)

### How It Works

Combines Fixed Window's O(1) space with Sliding Window's accuracy. Uses two fixed windows (current + previous) and estimates the count in the sliding window by weighting the previous window's count by its overlap.

```
Previous window: [----------|    ] count=70  (30% overlaps with current window)
Current window:  [    |----------] count=40  (100% in current window)

Estimated sliding window count = 70 × 0.30 + 40 = 61
```

**Formula:**
```
estimate = prev_count × (window_size - elapsed_in_current) / window_size + curr_count
```

### Java Implementation

```java
public class SlidingWindowCounter {
    private final int limit;
    private final long windowMs;

    private final ConcurrentHashMap<String, long[]> data = new ConcurrentHashMap<>();
    // data[userId] = [prevWindowStart, prevCount, currWindowStart, currCount]

    public SlidingWindowCounter(int limit, long windowMs) {
        this.limit = limit;
        this.windowMs = windowMs;
    }

    public synchronized boolean tryConsume(String userId) {
        long now = System.currentTimeMillis();
        long currWindowStart = (now / windowMs) * windowMs;
        long prevWindowStart = currWindowStart - windowMs;

        long[] state = data.computeIfAbsent(userId, k -> new long[]{prevWindowStart, 0, currWindowStart, 0});

        // Shift windows if we've moved past current window
        if (state[2] != currWindowStart) {
            if (state[2] == prevWindowStart) {
                // Previous current becomes new previous
                state[0] = state[2];
                state[1] = state[3];
            } else {
                // Gap — reset previous
                state[0] = prevWindowStart;
                state[1] = 0;
            }
            state[2] = currWindowStart;
            state[3] = 0;
        }

        long elapsedInCurrent = now - currWindowStart;
        double prevWeight = (double)(windowMs - elapsedInCurrent) / windowMs;
        double estimate = state[1] * prevWeight + state[3];

        if (estimate < limit) {
            state[3]++;
            return true;
        }
        return false;
    }
}
```

**Redis implementation:**

```java
String luaScript = """
    local prev_key = KEYS[1]
    local curr_key = KEYS[2]
    local limit = tonumber(ARGV[1])
    local window_size = tonumber(ARGV[2])
    local elapsed_in_current = tonumber(ARGV[3])

    local prev_count = tonumber(redis.call('get', prev_key)) or 0
    local curr_count = tonumber(redis.call('get', curr_key)) or 0

    local prev_weight = (window_size - elapsed_in_current) / window_size
    local estimate = prev_count * prev_weight + curr_count

    if estimate < limit then
        redis.call('incr', curr_key)
        redis.call('expire', curr_key, window_size * 2 / 1000)
        return 1
    end
    return 0
    """;

long now = System.currentTimeMillis();
long windowSizeMs = 60_000L;
long currWindowStart = (now / windowSizeMs) * windowSizeMs;
long prevWindowStart = currWindowStart - windowSizeMs;
long elapsedInCurrent = now - currWindowStart;

String prevKey = "ratelimit:" + userId + ":" + prevWindowStart;
String currKey = "ratelimit:" + userId + ":" + currWindowStart;

long allowed = (Long) jedis.eval(luaScript, 2, prevKey, currKey,
    String.valueOf(limit), String.valueOf(windowSizeMs), String.valueOf(elapsedInCurrent));
```

### Advantages
- **O(1) memory**: only two counters per user regardless of limit
- **Near-exact accuracy**: error rate is at most ~0.003% under uniform distribution
- **No boundary spike**: the weighting smooths the transition between windows
- **Redis-friendly**: two GET + one INCR, all expressible in Lua
- **Production-grade**: Cloudflare, Nginx, and most API gateways use this approach

### Disadvantages
- **Approximate**: assumes uniform distribution within previous window — burst at end of previous window is under-counted
- **Not exactly fair**: a user who sent all prev window requests in the last millisecond gets the benefit of linear spread
- **Harder to explain**: product/support teams need more explanation than fixed window

### Error Bound Analysis
Under worst case (all previous window requests at the very end):
```
Max over-allowance ≈ prev_count × (fraction of prev window still in sliding range)
In practice: error < 1% under real-world traffic patterns
```

### FAANG Interview Callout
> This is the **production answer** for distributed rate limiting. Cloudflare wrote a blog post explaining this exact algorithm. When an interviewer asks "how does Cloudflare rate limit?", this is the answer. The key insight to articulate: **we trade exact accuracy for O(1) space and constant-time Redis operations**.

---

## 6. Concurrent Request Limiter (Semaphore-Based)

### How It Works

Instead of requests-per-time-window, limit **simultaneous in-flight requests**. A semaphore with `N` permits allows N concurrent requests. New requests wait or are rejected if all permits are held.

```
Max concurrency: 10
In-flight:  [req1][req2][req3][req4][req5][req6][req7][req8][req9][req10]
New request: → REJECT (or queue)
```

### Java Implementation

```java
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;

public class ConcurrentRequestLimiter {
    private final Semaphore semaphore;
    private final long timeoutMs;

    public ConcurrentRequestLimiter(int maxConcurrent, long timeoutMs) {
        this.semaphore = new Semaphore(maxConcurrent, true); // fair
        this.timeoutMs = timeoutMs;
    }

    public <T> T execute(Callable<T> task) throws Exception {
        boolean acquired = semaphore.tryAcquire(timeoutMs, TimeUnit.MILLISECONDS);
        if (!acquired) {
            throw new RateLimitException("Concurrent request limit exceeded");
        }
        try {
            return task.call();
        } finally {
            semaphore.release();
        }
    }

    // Decorator pattern for clean usage
    public static <T> T withLimit(Semaphore sem, Supplier<T> task) {
        sem.acquireUninterruptibly();
        try {
            return task.get();
        } finally {
            sem.release();
        }
    }
}
```

**Distributed semaphore with Redis:**

```java
public class DistributedConcurrentLimiter {
    private final JedisPool jedisPool;
    private final int maxConcurrent;
    private final String keyPrefix;

    public String acquire(String requestId, int ttlSeconds) {
        String luaScript = """
            local key = KEYS[1]
            local max = tonumber(ARGV[1])
            local request_id = ARGV[2]
            local ttl = tonumber(ARGV[3])
            local now = tonumber(ARGV[4])

            -- Remove expired entries
            redis.call('zremrangebyscore', key, 0, now - (ttl * 1000))

            local count = redis.call('zcard', key)
            if count < max then
                redis.call('zadd', key, now, request_id)
                redis.call('expire', key, ttl + 1)
                return 1
            end
            return 0
            """;

        try (Jedis jedis = jedisPool.getResource()) {
            long now = System.currentTimeMillis();
            long result = (Long) jedis.eval(luaScript, 1, keyPrefix,
                String.valueOf(maxConcurrent), requestId, 
                String.valueOf(ttlSeconds), String.valueOf(now));
            return result == 1 ? requestId : null;
        }
    }

    public void release(String requestId) {
        try (Jedis jedis = jedisPool.getResource()) {
            jedis.zrem(keyPrefix, requestId);
        }
    }
}
```

### Advantages
- **Prevents resource exhaustion**: caps DB connections, thread pool size, or downstream calls directly
- **Self-adjusting to latency**: if requests get slower (e.g., DB slowdown), fewer are in-flight, providing natural backpressure
- **Timeout-based**: slow requests eventually release permits (with TTL in distributed version)
- **Right tool for protecting shared resources** (connection pools, file handles)

### Disadvantages
- **Not rate-based**: doesn't prevent 1000 fast requests — just 1000 simultaneous ones
- **Permit leaks**: bugs that don't release permits cause gradual starvation (mitigated by TTL)
- **Not suitable as API quota**: users can't predict or plan around "concurrent" limits
- **Starvation risk**: long-running requests hold permits; fast requests starve

### Trade-offs vs Rate Limiting

| Dimension | Time-Window Rate Limit | Concurrency Limit |
|-----------|----------------------|-------------------|
| Protects against | Throughput overload | Resource exhaustion |
| User communication | "100 req/min" | "Try again shortly" |
| Self-adjusts to latency | No | Yes |
| Prevents bursts | Yes | No |
| Right for APIs | Yes | No |
| Right for DB connections | No | Yes |

---

## 7. Adaptive Rate Limiter

### How It Works

Rate limits adjust dynamically based on system health metrics (CPU, latency, error rate, queue depth). Rather than a fixed limit, the system measures headroom and allows more or fewer requests accordingly.

```
System healthy (CPU=30%, p99=20ms):  → allow 1000 req/s
System stressed (CPU=80%, p99=500ms): → allow 200 req/s
System degraded (CPU=95%, p99=2s):   → allow 50 req/s, shed load
```

### Java Implementation

```java
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;

public class AdaptiveRateLimiter {
    private final AtomicLong currentLimit = new AtomicLong(1000);
    private final AtomicReference<SystemHealth> lastHealth = new AtomicReference<>(SystemHealth.HEALTHY);

    private final TokenBucket bucket;
    private final MetricsCollector metrics;

    // Configurable thresholds
    private static final double CPU_WARN = 0.70;
    private static final double CPU_CRITICAL = 0.90;
    private static final long LATENCY_WARN_MS = 200;
    private static final long LATENCY_CRITICAL_MS = 1000;
    private static final double ERROR_RATE_WARN = 0.01;   // 1%
    private static final double ERROR_RATE_CRITICAL = 0.05; // 5%

    public AdaptiveRateLimiter(MetricsCollector metrics, long initialLimit) {
        this.metrics = metrics;
        this.bucket = new TokenBucket(initialLimit * 2, initialLimit);
        this.currentLimit.set(initialLimit);
        startAdaptationLoop();
    }

    private void startAdaptationLoop() {
        Executors.newSingleThreadScheduledExecutor().scheduleAtFixedRate(() -> {
            SystemMetrics m = metrics.current();
            long newLimit = calculateLimit(m);
            long oldLimit = currentLimit.getAndSet(newLimit);
            
            if (newLimit != oldLimit) {
                bucket.updateRate(newLimit);
                log.info("Rate limit adjusted: {} → {} (cpu={}, p99={}ms, errRate={})",
                    oldLimit, newLimit, m.cpuUsage, m.p99LatencyMs, m.errorRate);
            }
        }, 1, 5, TimeUnit.SECONDS);
    }

    private long calculateLimit(SystemMetrics m) {
        double multiplier = 1.0;

        // CPU factor
        if (m.cpuUsage > CPU_CRITICAL) multiplier = Math.min(multiplier, 0.2);
        else if (m.cpuUsage > CPU_WARN) multiplier = Math.min(multiplier, 0.6);

        // Latency factor
        if (m.p99LatencyMs > LATENCY_CRITICAL_MS) multiplier = Math.min(multiplier, 0.1);
        else if (m.p99LatencyMs > LATENCY_WARN_MS) multiplier = Math.min(multiplier, 0.5);

        // Error rate factor
        if (m.errorRate > ERROR_RATE_CRITICAL) multiplier = Math.min(multiplier, 0.05);
        else if (m.errorRate > ERROR_RATE_WARN) multiplier = Math.min(multiplier, 0.4);

        return (long)(currentLimit.get() * multiplier);
    }

    public boolean tryConsume(String userId) {
        return bucket.tryConsume(1);
    }
}

record SystemMetrics(double cpuUsage, long p99LatencyMs, double errorRate) {}
```

**AIMD (Additive Increase / Multiplicative Decrease) — Netflix approach:**

```java
// Additive increase when healthy: limit += 1 per interval
// Multiplicative decrease when degraded: limit *= 0.5
public class AIMDRateLimiter {
    private volatile double currentLimit;
    private final double minLimit;
    private final double maxLimit;
    private final double additiveFactor = 1.0;  // increase by 1/s when healthy
    private final double multiplicativeFactor = 0.5; // halve when degraded

    public void onSuccess() {
        currentLimit = Math.min(maxLimit, currentLimit + additiveFactor);
    }

    public void onFailure() {
        currentLimit = Math.max(minLimit, currentLimit * multiplicativeFactor);
    }
}
```

### Advantages
- **Self-regulating**: automatically backs off during incidents without human intervention
- **Maximizes throughput**: runs at maximum safe rate, not a conservative static limit
- **Graceful degradation**: shedding load before total failure
- **Observability-driven**: makes system health explicit

### Disadvantages
- **Complex to implement correctly**: wrong thresholds cause oscillation or false positives
- **Latency in response**: metric collection and adaptation loop adds delay
- **Hard to predict for clients**: clients can't plan around a limit that changes
- **False triggers**: a single slow query spikes p99, unnecessarily throttling good requests

### When to Use
- Internal service-to-service communication (not user-facing APIs)
- Circuit breaker integration
- Auto-scaling scenarios where you want to match traffic to capacity dynamically

---

## Comparison: All Algorithms Side-by-Side

| Criterion | Token Bucket | Leaky Bucket | Fixed Window | Sliding Log | Sliding Counter | Concurrency | Adaptive |
|-----------|-------------|--------------|--------------|-------------|-----------------|-------------|----------|
| Memory | O(1) | O(D) | O(1) | O(N) | O(1) | O(1) | O(1) |
| Burst allowed | Yes | No | Yes (boundary) | No | ~No | N/A | Dynamic |
| Boundary spike | No | No | **Yes** | No | ~No | N/A | N/A |
| Precision | Medium | High | Low | **Exact** | ~Exact | N/A | Dynamic |
| Redis-friendly | Yes | Partial | Yes | Yes (ZADD) | **Best** | Yes (ZADD) | Complex |
| Client predictable | Yes | Partial | Yes | Yes | Yes | No | No |
| Use for public APIs | **Yes** | Avoid | Avoid | Small limits | **Yes** | No | Internal |
| Complexity | Low | Low | **Lowest** | High | Medium | Low | **Highest** |

---

## Distributed Rate Limiting Architecture

### Single Node vs Distributed

**Single node** (in-memory): simple, no network, but fails with multiple instances.

**Centralized store (Redis)**: all instances share one Redis — consistent but adds ~1ms network hop per request.

**Local + sync**: each instance has a local counter, sync to Redis every N ms — approximate but fast.

```
                    ┌─────────────────────────────────────────┐
Client Requests     │           Load Balancer                 │
──────────────→     └──┬──────────────┬──────────────┬───────┘
                       │              │              │
                  ┌────▼────┐    ┌────▼────┐    ┌────▼────┐
                  │  App 1  │    │  App 2  │    │  App 3  │
                  │ local   │    │ local   │    │ local   │
                  │ counter │    │ counter │    │ counter │
                  └────┬────┘    └────┬────┘    └────┬────┘
                       └──────────────┴──────────────┘
                                      │
                               ┌──────▼──────┐
                               │    Redis    │
                               │  Cluster    │
                               │ (Lua atomic)│
                               └─────────────┘
```

### Race Condition Prevention

**Wrong (non-atomic):**
```java
// BUG: two threads can both pass the check before either increments
long count = jedis.get(key);        // read
if (count < limit) {
    jedis.incr(key);                // write — race between read and write
    return true;
}
```

**Correct (atomic Lua):**
```java
// All operations in one atomic Lua script — Redis is single-threaded
String lua = "local c = redis.call('incr', KEYS[1]); " +
             "if c == 1 then redis.call('expire', KEYS[1], ARGV[1]) end; " +
             "return c";
```

---

## Implementation Pattern: Rate Limiter as Filter/Interceptor

### Spring Boot Filter

```java
@Component
@Order(1)
public class RateLimitFilter implements Filter {
    private final SlidingWindowCounter rateLimiter;
    private final RateLimitConfig config;

    @Override
    public void doFilter(ServletRequest req, ServletResponse res, FilterChain chain)
            throws IOException, ServletException {
        HttpServletRequest request = (HttpServletRequest) req;
        String clientId = extractClientId(request);  // API key, user ID, IP

        if (!rateLimiter.tryConsume(clientId)) {
            HttpServletResponse response = (HttpServletResponse) res;
            response.setStatus(429);
            response.setHeader("X-RateLimit-Limit", String.valueOf(config.getLimit()));
            response.setHeader("X-RateLimit-Remaining", "0");
            response.setHeader("X-RateLimit-Reset", String.valueOf(nextWindowReset()));
            response.setHeader("Retry-After", String.valueOf(retryAfterSeconds()));
            response.getWriter().write("{\"error\":\"rate_limit_exceeded\"}");
            return;
        }

        chain.doFilter(req, res);
    }

    private String extractClientId(HttpServletRequest request) {
        // Priority: API key > authenticated user > IP
        String apiKey = request.getHeader("X-API-Key");
        if (apiKey != null) return "apikey:" + apiKey;
        
        Principal principal = request.getUserPrincipal();
        if (principal != null) return "user:" + principal.getName();
        
        return "ip:" + getClientIp(request);
    }
}
```

### Rate Limit Headers (RFC 6585 / IETF Draft)

```java
// Standard headers clients use to adapt their request rate
response.setHeader("X-RateLimit-Limit", "100");       // limit per window
response.setHeader("X-RateLimit-Remaining", "43");    // remaining in current window  
response.setHeader("X-RateLimit-Reset", "1686835200"); // UTC epoch of next reset
response.setHeader("Retry-After", "30");               // seconds until retry (on 429)
```

---

## Key Design Decisions for Interviews

### 1. What dimension to rate limit on?

| Dimension | Key | Use Case |
|-----------|-----|----------|
| Per IP | `ip:{ip}` | Anonymous, unauthenticated |
| Per user | `user:{userId}` | Authenticated APIs |
| Per API key | `key:{apiKey}` | B2B / developer APIs |
| Per endpoint | `endpoint:{path}:user:{id}` | Expensive endpoints stricter |
| Per tenant | `tenant:{tenantId}` | Multi-tenant SaaS |
| Global | `global:{service}` | Protect a specific downstream |

### 2. What to do when rate-limited?

| Strategy | When to use |
|----------|-------------|
| Reject (429) | Public APIs, unpredictable clients |
| Queue | Internal services, batch workloads |
| Shed to degraded response | Read-heavy APIs (return cached stale data) |
| Backpressure | Service mesh, gRPC |

### 3. Where to enforce?

| Layer | Tool | Trade-off |
|-------|------|-----------|
| API Gateway | Kong, AWS API GW | No code changes; limited flexibility |
| Service mesh | Istio, Envoy | Transparent; requires service mesh |
| Application code | Library | Full control; distributed sync needed |
| CDN | Cloudflare | DDoS protection; before origin |

---

## FAANG Interview Trade-off Summary

> "Which rate limiter would you use for a 100M-user public API?"

**Answer structure:**
1. Sliding Window Counter — production choice for distributed systems (O(1) Redis ops)
2. Token Bucket — if bursts must be allowed (user-facing APIs where UX matters)
3. Fixed Window — only if the team needs simplicity and boundary spikes are acceptable

> "How do you handle rate limiting across 50 API servers?"

**Answer:** Centralized Redis with Lua scripts for atomicity. Local counter with periodic sync (every 100ms) for ultra-low latency where ~10% overcount is acceptable. Sliding Window Counter in Redis is the production default.

> "What if Redis goes down?"

**Answer:** Circuit breaker around rate limit check. Options: fail-open (allow all — availability > correctness), fail-closed (block all — correctness > availability), or local fallback counter per node. Choice depends on SLA: payment APIs fail-closed, read APIs fail-open.
