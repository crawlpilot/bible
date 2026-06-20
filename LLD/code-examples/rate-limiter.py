"""
Rate Limiter — Two Implementations
====================================
Implements Token Bucket and Sliding Window Counter algorithms.

Use case: limit API callers to N requests per time window.

Token Bucket:
  - Tokens accrue at a fixed rate up to a burst capacity
  - Each request consumes one token; rejected if no tokens available
  - Allows short bursts up to capacity while enforcing an average rate
  - Used by: AWS API Gateway, Stripe, most API rate limiters

Sliding Window Counter:
  - Approximation of exact sliding window log
  - Combines fixed-window counts from the current and previous window
  - Accurate to within 0.003% of exact count for uniform traffic
  - O(1) per request (no per-request log entry)
  - Used by: Redis CL.THROTTLE (GCRA variant), Cloudflare, Nginx

Both implementations are thread-safe for single-node use.
For distributed rate limiting, replace _store with Redis calls.
"""
import threading
import time
import math
from abc import ABC, abstractmethod


# ── Interface ─────────────────────────────────────────────────────────────

class RateLimiter(ABC):
    @abstractmethod
    def allow(self, key: str) -> bool:
        """Return True if the request for `key` is allowed."""
        pass

    @abstractmethod
    def allow_with_info(self, key: str) -> dict:
        """Return decision plus metadata (remaining, retry_after_s)."""
        pass


# ── Implementation 1: Token Bucket ────────────────────────────────────────

class TokenBucketRateLimiter(RateLimiter):
    """
    Token Bucket algorithm.

    Parameters:
        rate:     tokens replenished per second
        capacity: maximum tokens (burst allowance)

    Example: rate=100, capacity=200
      - Steady state: 100 req/s allowed
      - After 2 idle seconds: burst of 200 allowed, then back to 100/s
    """

    def __init__(self, rate: float, capacity: float):
        if rate <= 0 or capacity <= 0:
            raise ValueError("rate and capacity must be positive")
        self._rate = rate
        self._capacity = capacity
        # Per-key state: {key: (tokens, last_refill_time)}
        self._buckets: dict[str, tuple[float, float]] = {}
        self._lock = threading.Lock()

    def _get_tokens(self, key: str, now: float) -> tuple[float, float]:
        """Return current token count and last-refill time for key."""
        if key not in self._buckets:
            return self._capacity, now  # fresh key: full bucket
        tokens, last = self._buckets[key]
        # Refill tokens based on elapsed time
        elapsed = now - last
        tokens = min(self._capacity, tokens + elapsed * self._rate)
        return tokens, now

    def allow(self, key: str) -> bool:
        return self.allow_with_info(key)["allowed"]

    def allow_with_info(self, key: str) -> dict:
        now = time.monotonic()
        with self._lock:
            tokens, last = self._get_tokens(key, now)
            if tokens >= 1.0:
                tokens -= 1.0
                self._buckets[key] = (tokens, last)
                return {
                    "allowed": True,
                    "remaining": math.floor(tokens),
                    "retry_after_s": 0.0,
                }
            else:
                self._buckets[key] = (tokens, last)
                # Time until next token available
                deficit = 1.0 - tokens
                retry_after = deficit / self._rate
                return {
                    "allowed": False,
                    "remaining": 0,
                    "retry_after_s": round(retry_after, 3),
                }

    def refund(self, key: str, tokens: float = 1.0) -> None:
        """Return tokens to the bucket (e.g., for failed requests that shouldn't count)."""
        now = time.monotonic()
        with self._lock:
            current, last = self._get_tokens(key, now)
            self._buckets[key] = (min(self._capacity, current + tokens), last)


# ── Implementation 2: Sliding Window Counter ──────────────────────────────

class SlidingWindowCounterRateLimiter(RateLimiter):
    """
    Sliding Window Counter approximation.

    Divides time into fixed windows of `window_s` seconds.
    Estimates the count in the rolling window as:
        count = prev_count * (1 - elapsed_fraction) + current_count

    Error: at most (rate × 1 request / window_size) = negligible for most use cases.

    Parameters:
        limit:    maximum requests per window
        window_s: window size in seconds (default: 60s)
    """

    def __init__(self, limit: int, window_s: float = 60.0):
        if limit <= 0 or window_s <= 0:
            raise ValueError("limit and window_s must be positive")
        self._limit = limit
        self._window = window_s
        # {key: (window_start, current_count, prev_count)}
        self._counters: dict[str, tuple[float, int, int]] = {}
        self._lock = threading.Lock()

    def _current_window_start(self, now: float) -> float:
        return math.floor(now / self._window) * self._window

    def allow(self, key: str) -> bool:
        return self.allow_with_info(key)["allowed"]

    def allow_with_info(self, key: str) -> dict:
        now = time.monotonic()
        window_start = self._current_window_start(now)
        elapsed_in_window = now - window_start
        elapsed_fraction = elapsed_in_window / self._window

        with self._lock:
            if key not in self._counters:
                win_start, cur, prev = window_start, 0, 0
            else:
                win_start, cur, prev = self._counters[key]

            if win_start < window_start:
                # We've crossed into a new window
                if win_start + self._window < window_start:
                    # More than one window has elapsed — prev is zero
                    prev = 0
                else:
                    prev = cur
                cur = 0
                win_start = window_start

            # Approximate count in the rolling window
            estimated = prev * (1 - elapsed_fraction) + cur
            remaining = max(0, self._limit - math.floor(estimated) - 1)

            if estimated < self._limit:
                cur += 1
                self._counters[key] = (win_start, cur, prev)
                return {
                    "allowed": True,
                    "remaining": remaining,
                    "retry_after_s": 0.0,
                }
            else:
                self._counters[key] = (win_start, cur, prev)
                # Estimate when the window will have capacity
                time_to_next_slot = (
                    (estimated - self._limit + 1) / (prev / self._window)
                    if prev > 0 else self._window - elapsed_in_window
                )
                return {
                    "allowed": False,
                    "remaining": 0,
                    "retry_after_s": round(time_to_next_slot, 3),
                }


# ── Unit Tests ────────────────────────────────────────────────────────────

import unittest


class TestTokenBucketRateLimiter(unittest.TestCase):

    def test_allows_up_to_capacity(self):
        rl = TokenBucketRateLimiter(rate=10, capacity=5)
        # Fresh key has full bucket — 5 requests should succeed
        for _ in range(5):
            self.assertTrue(rl.allow("user:1"))
        # 6th should be rejected
        self.assertFalse(rl.allow("user:1"))

    def test_different_keys_independent(self):
        rl = TokenBucketRateLimiter(rate=10, capacity=3)
        for _ in range(3):
            rl.allow("user:1")
        self.assertFalse(rl.allow("user:1"))
        self.assertTrue(rl.allow("user:2"))  # user:2 bucket is full

    def test_refill_over_time(self):
        rl = TokenBucketRateLimiter(rate=10, capacity=10)
        for _ in range(10):
            rl.allow("user:1")
        self.assertFalse(rl.allow("user:1"))

        # Simulate 0.15 seconds passing → 10 * 0.15 = 1.5 tokens added
        bucket = rl._buckets["user:1"]
        rl._buckets["user:1"] = (bucket[0], bucket[1] - 0.15)  # rewind last_refill

        self.assertTrue(rl.allow("user:1"))   # 1.5 - 1 = 0.5 tokens remain
        self.assertFalse(rl.allow("user:1"))  # 0.5 < 1 → rejected

    def test_retry_after_populated(self):
        rl = TokenBucketRateLimiter(rate=2, capacity=2)
        rl.allow("user:1")
        rl.allow("user:1")
        result = rl.allow_with_info("user:1")
        self.assertFalse(result["allowed"])
        self.assertGreater(result["retry_after_s"], 0)

    def test_refund(self):
        rl = TokenBucketRateLimiter(rate=10, capacity=3)
        for _ in range(3):
            rl.allow("user:1")
        self.assertFalse(rl.allow("user:1"))
        rl.refund("user:1")  # return one token
        self.assertTrue(rl.allow("user:1"))


class TestSlidingWindowRateLimiter(unittest.TestCase):

    def test_allows_up_to_limit(self):
        rl = SlidingWindowCounterRateLimiter(limit=5, window_s=60)
        for _ in range(5):
            self.assertTrue(rl.allow("user:1"))
        self.assertFalse(rl.allow("user:1"))

    def test_different_keys_independent(self):
        rl = SlidingWindowCounterRateLimiter(limit=3, window_s=60)
        for _ in range(3):
            rl.allow("user:1")
        self.assertFalse(rl.allow("user:1"))
        self.assertTrue(rl.allow("user:2"))

    def test_remaining_count_decrements(self):
        rl = SlidingWindowCounterRateLimiter(limit=5, window_s=60)
        result = rl.allow_with_info("user:1")
        self.assertTrue(result["allowed"])
        self.assertEqual(result["remaining"], 4)

    def test_window_rollover(self):
        rl = SlidingWindowCounterRateLimiter(limit=3, window_s=60)
        for _ in range(3):
            rl.allow("user:1")
        self.assertFalse(rl.allow("user:1"))

        # Simulate rolling forward 2 full windows
        win_start, cur, prev = rl._counters["user:1"]
        rl._counters["user:1"] = (win_start - 120, cur, prev)

        # Should have full capacity again
        self.assertTrue(rl.allow("user:1"))


# ── Design Notes ──────────────────────────────────────────────────────────
"""
Algorithm Comparison:

                    Token Bucket        Sliding Window Counter
─────────────────────────────────────────────────────────────────
Burst handling      Yes (up to capacity)  Limited by window
Accuracy            Exact                 ~0.003% error at boundary
Memory per key      O(1): 2 floats        O(1): 3 values
Redis implementation SET + INCRBY + TTL   INCR on two keys
Complexity          O(1)                  O(1)
Smoothness          Allows burst spikes   More uniform
Best for            API rate limiting     Request-per-second limits

Distributed Rate Limiting with Redis:
─────────────────────────────────────
Token Bucket → Redis GETSET + EVAL (Lua script for atomicity):
    local tokens = tonumber(redis.call('GET', key)) or capacity
    local now = tonumber(ARGV[1])
    local last = tonumber(redis.call('GET', key..':ts')) or now
    tokens = math.min(capacity, tokens + (now - last) * rate)
    if tokens >= 1 then
        redis.call('SET', key, tokens - 1)
        redis.call('SET', key..':ts', now)
        return 1  -- allowed
    end
    return 0  -- rejected

Sliding Window → Two Redis INCR keys (current and previous window):
    INCR window:{window_start}:{key}
    EXPIRE window:{window_start}:{key} {2 * window_s}
    GET window:{prev_window_start}:{key}
    -- Apply formula: prev * (1 - elapsed_fraction) + cur

CL.THROTTLE (Redis module) implements GCRA (Generic Cell Rate Algorithm):
    CL.THROTTLE user:123 100 100 60   → [allowed, limit, remaining, retry_after, reset_after]
"""

if __name__ == "__main__":
    unittest.main(verbosity=2)
