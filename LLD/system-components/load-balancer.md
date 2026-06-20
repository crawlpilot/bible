# System Component: Load Balancer

**Category**: LLD · System Components · Traffic Distribution  
**Algorithms**: Round Robin, Weighted Round Robin, Least Connections, Consistent Hash, Random, IP Hash  
**Real-world implementations**: NGINX, HAProxy, AWS ALB/NLB, Envoy, Caddy, Traefik

---

## Problem Statement

A load balancer distributes incoming requests across a pool of backend servers to:
1. Maximize throughput by using all available capacity
2. Minimize latency by avoiding overloaded servers
3. Ensure high availability by routing around unhealthy backends
4. Provide session stickiness when required (stateful services)

The choice of algorithm matters significantly at scale: the wrong algorithm leads to hot spots, uneven load, or cache thrashing.

---

## L4 vs L7 Load Balancing

| Property | L4 (Transport Layer) | L7 (Application Layer) |
|----------|---------------------|----------------------|
| Operates on | TCP/UDP packets | HTTP/gRPC/WebSocket content |
| Routing criteria | IP + port | URL path, headers, cookies, body |
| Performance | ~1M conn/s per core | ~100K req/s per core |
| SSL termination | Pass-through or terminate | Always terminates |
| Session affinity | IP-hash or TCP session | Cookie or header |
| Use case | High-throughput TCP, UDP (DNS, gaming) | HTTP APIs, microservices |

**AWS equivalents**: NLB = L4, ALB = L7.

---

## Interface

```python
from abc import ABC, abstractmethod

class Backend:
    def __init__(self, host: str, port: int, weight: int = 1):
        self.host = host
        self.port = port
        self.weight = weight
        self.active_connections = 0
        self.healthy = True
        self.total_requests = 0

    def __repr__(self):
        return f"{self.host}:{self.port}"

class LoadBalancer(ABC):
    def __init__(self, backends: list[Backend]):
        self.backends = backends

    @abstractmethod
    def select(self, request=None) -> Backend | None:
        """Select a backend for the given request. Returns None if no healthy backend."""
        pass

    def healthy_backends(self) -> list[Backend]:
        return [b for b in self.backends if b.healthy]
```

---

## Algorithm 1: Round Robin

```python
import threading

class RoundRobinLB(LoadBalancer):
    def __init__(self, backends):
        super().__init__(backends)
        self._index = 0
        self._lock = threading.Lock()

    def select(self, request=None) -> Backend | None:
        healthy = self.healthy_backends()
        if not healthy:
            return None
        with self._lock:
            backend = healthy[self._index % len(healthy)]
            self._index += 1
        return backend
```

**Pros**: Simple, even distribution across equal-capacity servers.  
**Cons**: Ignores server capacity differences, ignores current load.  
**Use when**: servers are homogeneous, requests are similar in cost, stateless workloads.

---

## Algorithm 2: Weighted Round Robin

```python
class WeightedRoundRobinLB(LoadBalancer):
    """
    Smooth weighted round robin (Nginx-style).
    Avoids burst sending to high-weight servers.
    """
    def __init__(self, backends):
        super().__init__(backends)
        self._current_weights = {b: 0 for b in backends}
        self._lock = threading.Lock()

    def select(self, request=None) -> Backend | None:
        healthy = self.healthy_backends()
        if not healthy:
            return None
        with self._lock:
            total = sum(b.weight for b in healthy)
            # Increase each backend's current weight by its effective weight
            for b in healthy:
                self._current_weights[b] += b.weight
            # Select the backend with the highest current weight
            best = max(healthy, key=lambda b: self._current_weights[b])
            # Decrease the selected backend's current weight by total
            self._current_weights[best] -= total
        return best
```

**Example**: backends A(weight=5), B(weight=1), C(weight=1) → A gets 5/7 of requests, B and C get 1/7 each, spread smoothly (not in bursts of 5).

**Use when**: servers have different hardware capacity, traffic should be proportional to capacity.

---

## Algorithm 3: Least Connections

```python
class LeastConnectionsLB(LoadBalancer):
    def select(self, request=None) -> Backend | None:
        healthy = self.healthy_backends()
        if not healthy:
            return None
        # Select backend with fewest active connections
        return min(healthy, key=lambda b: b.active_connections)
```

For weighted least connections: `min(healthy, key=lambda b: b.active_connections / b.weight)`

**Pros**: Adapts to long-lived connections, routes away from slow/overloaded servers naturally.  
**Cons**: Requires tracking connection counts; `active_connections` must be decremented accurately on request completion.  
**Use when**: long-running requests (WebSocket, file uploads, gRPC streaming), heterogeneous request cost.

---

## Algorithm 4: Consistent Hashing

Routes requests to the same backend based on a hash of a key (user ID, session ID, URL). Minimizes remapping when backends are added/removed.

```python
import hashlib
import bisect

class ConsistentHashLB(LoadBalancer):
    def __init__(self, backends, virtual_nodes=150):
        super().__init__(backends)
        self._ring: list[int] = []
        self._hash_to_backend: dict[int, Backend] = {}
        self._virtual_nodes = virtual_nodes
        self._lock = threading.Lock()
        for backend in backends:
            self._add_to_ring(backend)

    def _hash(self, key: str) -> int:
        return int(hashlib.md5(key.encode()).hexdigest(), 16)

    def _add_to_ring(self, backend: Backend):
        for i in range(self._virtual_nodes):
            h = self._hash(f"{backend.host}:{backend.port}#{i}")
            self._ring.append(h)
            self._hash_to_backend[h] = backend
        self._ring.sort()

    def _remove_from_ring(self, backend: Backend):
        for i in range(self._virtual_nodes):
            h = self._hash(f"{backend.host}:{backend.port}#{i}")
            self._ring.remove(h)
            del self._hash_to_backend[h]

    def select(self, request) -> Backend | None:
        """request must have a hashable key attribute (e.g., request.session_id)."""
        healthy = set(self.healthy_backends())
        if not healthy:
            return None
        key_hash = self._hash(str(request))
        with self._lock:
            idx = bisect.bisect_right(self._ring, key_hash) % len(self._ring)
            # Walk clockwise until we find a healthy backend
            for _ in range(len(self._ring)):
                backend = self._hash_to_backend[self._ring[idx]]
                if backend in healthy:
                    return backend
                idx = (idx + 1) % len(self._ring)
        return None

    def add_backend(self, backend: Backend):
        with self._lock:
            self.backends.append(backend)
            self._add_to_ring(backend)

    def remove_backend(self, backend: Backend):
        with self._lock:
            self.backends.remove(backend)
            self._remove_from_ring(backend)
```

**Virtual nodes**: without virtual nodes, backends cluster on one region of the ring, causing uneven distribution. 150 virtual nodes per backend gives ~±5% load variation.

**Key property**: when a backend is added/removed, only `1/N` of keys are remapped (vs. O(all) for modulo hashing).

**Use when**: stateful services (caches — minimize cache misses on scaling), session affinity, sharded databases.

---

## Algorithm 5: Random with Health Check

Simpler than consistent hash for stateless services. Random selection among healthy backends:

```python
import random

class RandomLB(LoadBalancer):
    def select(self, request=None) -> Backend | None:
        healthy = self.healthy_backends()
        return random.choice(healthy) if healthy else None
```

**Power of Two Choices**: instead of pure random, pick two backends at random and choose the one with fewer connections — approaches Least Connections performance with O(1) overhead:

```python
class PowerOfTwoChoicesLB(LoadBalancer):
    def select(self, request=None) -> Backend | None:
        healthy = self.healthy_backends()
        if not healthy:
            return None
        if len(healthy) == 1:
            return healthy[0]
        a, b = random.sample(healthy, 2)
        return a if a.active_connections <= b.active_connections else b
```

---

## Health Checking

```python
import time
import threading
import requests as http_requests

class HealthChecker:
    def __init__(self, backends: list[Backend], interval_s=10, timeout_s=2):
        self._backends = backends
        self._interval = interval_s
        self._timeout = timeout_s

    def start(self):
        t = threading.Thread(target=self._run, daemon=True)
        t.start()

    def _run(self):
        while True:
            for backend in self._backends:
                self._check(backend)
            time.sleep(self._interval)

    def _check(self, backend: Backend):
        url = f"http://{backend.host}:{backend.port}/health"
        try:
            resp = http_requests.get(url, timeout=self._timeout)
            backend.healthy = resp.status_code == 200
        except Exception:
            backend.healthy = False
```

**Health check types**:
- **Passive**: observe real traffic — if a backend returns 5xx consistently, mark unhealthy. No extra requests.
- **Active**: dedicated health check endpoint (`/health`, `/ping`). Detects failures before real traffic is affected.
- **Hybrid (AWS ALB)**: active checks with passive observability — most robust.

---

## Algorithm Comparison

| Algorithm | Best For | Weakness |
|-----------|---------|----------|
| Round Robin | Homogeneous servers, uniform requests | Ignores server load |
| Weighted RR | Different server capacities | Static weights, doesn't adapt |
| Least Connections | Long-lived or variable-cost requests | Requires accurate connection tracking |
| Consistent Hash | Caches, session affinity | Uneven distribution without virtual nodes |
| Random / P2C | Stateless, high throughput | No session affinity |

---

## FAANG Interview Callouts

**Where load balancer algorithms come up:**
- "How do you distribute traffic across your 50 API servers?" → Round Robin or P2C
- "How do you ensure requests for the same user hit the same Redis shard?" → Consistent Hash
- "How do you handle the case where one of your servers is slower than the others?" → Least Connections or P2C
- "What happens when you add a new server?" → Consistent Hash: only 1/N remapping; Round Robin: immediate inclusion

**Key decisions to call out in an interview:**
1. L4 vs L7 (throughput vs routing flexibility)
2. Session affinity requirements (stateful = consistent hash; stateless = round robin/P2C)
3. Health checking strategy (active vs passive vs hybrid)
4. Failure behavior: what happens when all backends are unhealthy? (fail open vs fail closed)
