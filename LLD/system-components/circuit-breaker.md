# System Component: Circuit Breaker

**Category**: LLD · System Components · Resilience Patterns  
**Design Pattern**: State Machine (Finite Automaton)  
**Real-world implementations**: Netflix Hystrix, Resilience4j, Polly (.NET), Envoy proxy, Istio

---

## Problem Statement

When a downstream service is failing or overloaded, synchronous callers that continue sending requests:
1. Accumulate latency (waiting for timeouts)
2. Exhaust thread pools (threads blocked waiting for responses)
3. Cascade failures upstream — a slow dependency becomes a wide outage

The circuit breaker prevents this: once failures cross a threshold, the circuit "opens" and calls fail immediately (fast fail), giving the downstream service time to recover.

---

## State Machine

```
                 [failure rate ≥ threshold]
CLOSED ─────────────────────────────────────► OPEN
  ▲                                              │
  │ [probe succeeds]              [timeout elapses]
  │                                              │
HALF-OPEN ◄───────────────────────────────────────
  │
  │ [probe fails]
  └──────────────────────────────────────────► OPEN
```

**CLOSED**: Normal operation. Calls pass through. Failures are counted in a rolling window. If `failure_rate ≥ threshold`, transition to OPEN.

**OPEN**: Fast fail. All calls immediately throw `CircuitOpenException` (no network call made). After `wait_duration`, transition to HALF-OPEN.

**HALF-OPEN**: Probe state. Allow a limited number of calls through. If they succeed → CLOSED. If they fail → OPEN (reset wait timer).

---

## Interface Contract

```python
from abc import ABC, abstractmethod
from enum import Enum

class CircuitState(Enum):
    CLOSED = "CLOSED"
    OPEN = "OPEN"
    HALF_OPEN = "HALF_OPEN"

class CircuitBreaker(ABC):
    @abstractmethod
    def call(self, func, *args, **kwargs):
        """Execute func through the circuit breaker. Raises CircuitOpenError if open."""
        pass

    @abstractmethod
    def get_state(self) -> CircuitState:
        pass

    @abstractmethod
    def record_success(self):
        pass

    @abstractmethod
    def record_failure(self):
        pass

class CircuitOpenError(Exception):
    pass
```

---

## Implementation: Sliding Window Circuit Breaker

```python
import time
import threading
from collections import deque

class SlidingWindowCircuitBreaker(CircuitBreaker):
    def __init__(
        self,
        failure_rate_threshold: float = 0.5,   # 50% failure rate → open
        min_calls: int = 10,                    # need at least 10 calls before evaluating
        window_size: int = 20,                  # rolling window of last 20 calls
        wait_duration_s: float = 60.0,          # seconds in OPEN before trying HALF-OPEN
        half_open_max_calls: int = 5,           # probe calls in HALF-OPEN
    ):
        self._threshold = failure_rate_threshold
        self._min_calls = min_calls
        self._window_size = window_size
        self._wait_duration = wait_duration_s
        self._half_open_max = half_open_max_calls

        self._state = CircuitState.CLOSED
        self._window: deque[bool] = deque()     # True = success, False = failure
        self._open_time: float = 0.0
        self._half_open_calls = 0
        self._half_open_successes = 0
        self._lock = threading.Lock()

    def call(self, func, *args, **kwargs):
        with self._lock:
            self._maybe_transition()
            if self._state == CircuitState.OPEN:
                raise CircuitOpenError(
                    f"Circuit is OPEN. Retry after {self._wait_duration}s."
                )
            if self._state == CircuitState.HALF_OPEN:
                if self._half_open_calls >= self._half_open_max:
                    raise CircuitOpenError("Circuit is HALF-OPEN and probe limit reached.")
                self._half_open_calls += 1

        try:
            result = func(*args, **kwargs)
            self.record_success()
            return result
        except Exception as e:
            self.record_failure()
            raise

    def record_success(self):
        with self._lock:
            self._record(True)
            if self._state == CircuitState.HALF_OPEN:
                self._half_open_successes += 1
                if self._half_open_successes >= self._half_open_max:
                    self._transition_to_closed()

    def record_failure(self):
        with self._lock:
            self._record(False)
            if self._state == CircuitState.HALF_OPEN:
                self._transition_to_open()

    def _record(self, success: bool):
        self._window.append(success)
        if len(self._window) > self._window_size:
            self._window.popleft()
        if self._state == CircuitState.CLOSED:
            self._check_threshold()

    def _check_threshold(self):
        if len(self._window) < self._min_calls:
            return
        failure_rate = self._window.count(False) / len(self._window)
        if failure_rate >= self._threshold:
            self._transition_to_open()

    def _maybe_transition(self):
        if (self._state == CircuitState.OPEN and
                time.monotonic() - self._open_time >= self._wait_duration):
            self._transition_to_half_open()

    def _transition_to_open(self):
        self._state = CircuitState.OPEN
        self._open_time = time.monotonic()
        self._window.clear()

    def _transition_to_half_open(self):
        self._state = CircuitState.HALF_OPEN
        self._half_open_calls = 0
        self._half_open_successes = 0

    def _transition_to_closed(self):
        self._state = CircuitState.CLOSED
        self._window.clear()

    def get_state(self) -> CircuitState:
        with self._lock:
            self._maybe_transition()
            return self._state
```

---

## Usage Example

```python
import requests

cb = SlidingWindowCircuitBreaker(
    failure_rate_threshold=0.5,
    min_calls=5,
    window_size=10,
    wait_duration_s=30,
    half_open_max_calls=3,
)

def fetch_user(user_id: int) -> dict:
    def _do_request():
        resp = requests.get(f"https://user-service/users/{user_id}", timeout=2.0)
        resp.raise_for_status()
        return resp.json()

    try:
        return cb.call(_do_request)
    except CircuitOpenError:
        return {"user_id": user_id, "status": "unavailable"}   # fallback
    except Exception as e:
        raise
```

---

## Configuration Parameters

| Parameter | Typical Value | Trade-off |
|-----------|--------------|-----------|
| `failure_rate_threshold` | 0.5 (50%) | Lower → opens faster (more sensitive); Higher → tolerates more failures |
| `min_calls` | 5–20 | Too low → opens on random noise; Too high → slow to react |
| `window_size` | 10–100 | Larger → smoother signal, slower reaction; Smaller → noisier, faster reaction |
| `wait_duration_s` | 30–120s | Too short → hammers recovering service; Too long → unnecessary downtime |
| `half_open_max_calls` | 3–10 | More probes → more confident transition to CLOSED; fewer → faster recovery |

---

## Variants

### Count-Based Window
Uses a fixed count of last N calls (implemented above). Good for high-throughput services where time windows would be very dense.

### Time-Based Window
Uses a sliding time window (e.g., last 60 seconds). Better for services with variable call rates — a quiet period doesn't dilute recent failures.

```python
# Time-based window: events older than window_seconds are discarded
class TimedCircuitBreaker:
    def __init__(self, window_seconds=60, ...):
        self._events: deque[tuple[float, bool]] = deque()  # (timestamp, success)

    def _record(self, success: bool):
        now = time.monotonic()
        self._events.append((now, success))
        # Evict stale events
        while self._events and now - self._events[0][0] > self._window_seconds:
            self._events.popleft()
```

### Bulkhead + Circuit Breaker (Composite)
Combine with a thread pool bulkhead: if the bulkhead is saturated (all threads busy), treat it as a failure for the circuit breaker's window. This detects latency-based degradation (slow service, not error-returning service).

---

## Observability

A circuit breaker without metrics is invisible. Track:

```python
# Metrics to emit:
# circuit_breaker_state{service="user-service", state="OPEN"}   1 or 0
# circuit_breaker_calls_total{service="user-service", outcome="success|failure|rejected"}
# circuit_breaker_failure_rate{service="user-service"}   rolling_window failure rate
# circuit_breaker_state_transitions_total{service="user-service", from="CLOSED", to="OPEN"}
```

**Alert on**: circuit breaker transitioning to OPEN (immediate alert), circuit breaker stuck in OPEN for > 2× `wait_duration` (the downstream never recovered).

---

## FAANG Interview Callouts

**Where circuit breakers appear in system design:**
- API gateway protecting downstream microservices
- Service mesh sidecar (Envoy/Istio implements circuit breaking in the proxy layer — no application code changes)
- Database connection pool (stop trying to acquire connections if the DB is down)
- Payment processor calls (fast-fail rather than 30-second timeout during processor outage)

**Key trade-off to mention:**
- Library-based (Resilience4j, Hystrix): per-service configuration, code-level control, no infrastructure changes
- Sidecar-based (Envoy/Istio): language-agnostic, consistent policy across all services, but adds latency and operational complexity

**Hystrix is deprecated**: Netflix deprecated Hystrix in 2018. Resilience4j is the modern Java replacement. Polly is the .NET equivalent.

**The question that differentiates PE-level answers**: "What do you do when the circuit is open?" The answer is always a fallback: serve cached data, return a degraded response, queue the request for later, or return a clear error that the caller can handle. A circuit breaker without a fallback strategy is incomplete.
