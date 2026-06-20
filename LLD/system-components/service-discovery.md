# System Component: Service Discovery

**Category**: LLD · System Components · Microservices Infrastructure  
**Models**: Client-Side Discovery, Server-Side Discovery  
**Implementations**: Consul, Eureka (Netflix), Kubernetes DNS/kube-proxy, Envoy xDS, ZooKeeper, etcd

---

## Problem Statement

In a microservices architecture, services need to find each other at runtime. Hardcoding IP addresses fails because:
- Service instances scale up/down dynamically
- Instances crash and are replaced on different IP addresses
- Multiple environments (staging, prod) need different routing

Service discovery provides a registry of live service instances, allowing callers to resolve a logical service name to a live IP:port at request time.

---

## Two Models

### Client-Side Discovery

The client queries a **service registry** directly to get available instances, then applies its own **load balancing logic** to select one.

```
Client → Registry (get instances for "user-service")
       → [{"ip": "10.0.1.5", "port": 8080}, {"ip": "10.0.1.6", "port": 8080}]
Client → select instance (round-robin, random, consistent hash)
Client → call 10.0.1.5:8080
```

**Implementations**: Netflix Eureka + Ribbon, Consul + custom client library.

**Pros**: client has full control over load balancing algorithm; no extra network hop; can implement sophisticated routing (affinity, canary).  
**Cons**: client must implement discovery and load balancing logic in every language; tight coupling to the registry.

### Server-Side Discovery

The client sends requests to a **load balancer or proxy** that consults the registry and routes to an available instance. The client is unaware of instance selection.

```
Client → Load Balancer (send to "user-service")
       → Load Balancer queries Registry → gets instance list
       → Load Balancer selects 10.0.1.5:8080
       → proxies request
```

**Implementations**: AWS ALB + Route 53, Kubernetes `Service` + kube-proxy, Envoy proxy + xDS.

**Pros**: client is simple — just calls the service name; load balancing logic is centralized; works with any language.  
**Cons**: extra network hop; load balancer is a potential bottleneck and single point of failure (mitigated by multi-instance LB).

---

## Registry Design

### Interface

```python
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Optional
import time

@dataclass
class ServiceInstance:
    service_name: str
    instance_id: str
    host: str
    port: int
    metadata: dict = field(default_factory=dict)
    registered_at: float = field(default_factory=time.monotonic)
    last_heartbeat: float = field(default_factory=time.monotonic)

    @property
    def address(self) -> str:
        return f"{self.host}:{self.port}"

class ServiceRegistry(ABC):
    @abstractmethod
    def register(self, instance: ServiceInstance) -> bool:
        """Register a service instance. Returns True on success."""
        pass

    @abstractmethod
    def deregister(self, service_name: str, instance_id: str) -> bool:
        """Remove a service instance from the registry."""
        pass

    @abstractmethod
    def get_instances(self, service_name: str) -> list[ServiceInstance]:
        """Return all healthy instances of the named service."""
        pass

    @abstractmethod
    def heartbeat(self, service_name: str, instance_id: str) -> bool:
        """Update the last-seen timestamp for a service instance."""
        pass
```

### In-Memory Registry (single-node, for local use / testing)

```python
import threading

class InMemoryRegistry(ServiceRegistry):
    def __init__(self, heartbeat_timeout_s: float = 30.0):
        self._instances: dict[str, dict[str, ServiceInstance]] = {}
        self._lock = threading.Lock()
        self._timeout = heartbeat_timeout_s
        # Start background reaper
        threading.Thread(target=self._reap_expired, daemon=True).start()

    def register(self, instance: ServiceInstance) -> bool:
        with self._lock:
            if instance.service_name not in self._instances:
                self._instances[instance.service_name] = {}
            self._instances[instance.service_name][instance.instance_id] = instance
        return True

    def deregister(self, service_name: str, instance_id: str) -> bool:
        with self._lock:
            svc = self._instances.get(service_name, {})
            removed = svc.pop(instance_id, None)
            return removed is not None

    def get_instances(self, service_name: str) -> list[ServiceInstance]:
        now = time.monotonic()
        with self._lock:
            instances = self._instances.get(service_name, {}).values()
            # Return only instances with recent heartbeats
            return [i for i in instances
                    if now - i.last_heartbeat < self._timeout]

    def heartbeat(self, service_name: str, instance_id: str) -> bool:
        with self._lock:
            svc = self._instances.get(service_name, {})
            if instance_id in svc:
                svc[instance_id].last_heartbeat = time.monotonic()
                return True
        return False

    def _reap_expired(self):
        while True:
            time.sleep(self._timeout / 2)
            now = time.monotonic()
            with self._lock:
                for service_name, instances in list(self._instances.items()):
                    expired = [iid for iid, inst in instances.items()
                               if now - inst.last_heartbeat >= self._timeout]
                    for iid in expired:
                        del instances[iid]
```

---

## Health Checking Patterns

### Self-Registration with Heartbeat (Eureka Model)
Service instances register themselves on startup and send periodic heartbeats. If the registry doesn't receive a heartbeat within the timeout window, it marks the instance as expired.

```python
class ServiceClient:
    def __init__(self, registry: ServiceRegistry, instance: ServiceInstance,
                 heartbeat_interval_s: float = 10.0):
        self._registry = registry
        self._instance = instance
        self._interval = heartbeat_interval_s

    def start(self):
        self._registry.register(self._instance)
        threading.Thread(target=self._heartbeat_loop, daemon=True).start()

    def stop(self):
        self._registry.deregister(
            self._instance.service_name,
            self._instance.instance_id
        )

    def _heartbeat_loop(self):
        while True:
            time.sleep(self._interval)
            ok = self._registry.heartbeat(
                self._instance.service_name,
                self._instance.instance_id
            )
            if not ok:
                # Re-register if heartbeat failed (registry may have restarted)
                self._registry.register(self._instance)
```

### Third-Party Registration (Sidecar / Platform Model)
The platform (Kubernetes, Consul agent) monitors service health and manages registration. The service does not need to know about the registry.

In Kubernetes: the `kubelet` monitors pod health via liveness probes. Kubernetes `Endpoints` controller updates the `Service` endpoint list when pods become ready/unready. The service itself has zero registry awareness.

---

## Client-Side Discovery with Load Balancing

```python
import random

class ServiceDiscoveryClient:
    def __init__(self, registry: ServiceRegistry, 
                 lb_strategy: str = "round_robin",
                 refresh_interval_s: float = 30.0):
        self._registry = registry
        self._strategy = lb_strategy
        self._cache: dict[str, list[ServiceInstance]] = {}
        self._rr_counters: dict[str, int] = {}
        self._lock = threading.Lock()
        threading.Thread(target=self._refresh_loop,
                         args=(refresh_interval_s,), daemon=True).start()

    def resolve(self, service_name: str) -> Optional[ServiceInstance]:
        with self._lock:
            instances = self._cache.get(service_name)
        if not instances:
            instances = self._registry.get_instances(service_name)
            with self._lock:
                self._cache[service_name] = instances
        if not instances:
            return None
        return self._select(service_name, instances)

    def _select(self, name: str, instances: list[ServiceInstance]) -> ServiceInstance:
        if self._strategy == "random":
            return random.choice(instances)
        elif self._strategy == "round_robin":
            with self._lock:
                idx = self._rr_counters.get(name, 0)
                self._rr_counters[name] = (idx + 1) % len(instances)
            return instances[idx % len(instances)]
        return instances[0]

    def _refresh_loop(self, interval: float):
        while True:
            time.sleep(interval)
            with self._lock:
                for name in list(self._cache.keys()):
                    self._cache[name] = self._registry.get_instances(name)
```

---

## Comparison: Client-Side vs Server-Side

| Aspect | Client-Side (Eureka/Consul) | Server-Side (K8s/ALB/Envoy) |
|--------|---------------------------|------------------------------|
| **Client complexity** | High — must implement discovery + LB | Low — just use the service DNS name |
| **Language support** | Needs library per language | Universal — DNS/TCP level |
| **Load balancing** | Per-client, flexible algorithm | Centralized, standardized |
| **Network hops** | 0 extra hops | 1 extra hop (via proxy/kube-proxy) |
| **Failure isolation** | Registry failure → client falls back to cached list | Proxy failure → requests fail |
| **Advanced routing** | Full control (affinity, weighted, canary) | Depends on LB/proxy capability |
| **Best for** | JVM-heavy microservices, Netflix-style | Kubernetes-native, polyglot services |

---

## Production Considerations

### Registry Consistency vs Availability
The service registry is itself a distributed system. If it uses strong consistency (etcd/Zookeeper/Consul with Raft), it may be unavailable during leader elections. If it uses eventual consistency (Eureka), it may show stale instances.

**Eureka's self-preservation mode**: if Eureka stops receiving heartbeats from a large portion of instances (network partition), it assumes the problem is with itself, not the instances, and stops evicting entries. This prioritizes availability over accuracy.

**Consul**: uses Raft consensus — strong consistency, but unavailable during leader election (~150ms with 3-node cluster).

**Kubernetes**: uses etcd (Raft) for the service registry. The `Endpoints` list is updated synchronously but only after health probe failures propagate through the kubelet, which can take 30–60 seconds.

### DNS-Based Discovery (Kubernetes)
```
# In Kubernetes, every Service gets a DNS name:
# {service-name}.{namespace}.svc.cluster.local

# A Pod calling user-service:
http://user-service.default.svc.cluster.local:8080/users/123

# kube-proxy watches Endpoints; iptables rules route to healthy pods
# Round-robin load balancing at the iptables level (L4 only)
# For L7 load balancing: use a Service Mesh (Istio/Linkerd)
```

---

## FAANG Interview Callouts

**Where service discovery comes up:**
- "How do services find each other in your microservices design?" → service registry + client-side or server-side discovery
- "What happens when you add more instances of a service?" → dynamic registration via heartbeat; load balancer/proxy automatically routes to new instances
- "How does Kubernetes handle service-to-service communication?" → kube-proxy + CoreDNS + Endpoints controller

**Key trade-off to articulate:**
Client-side discovery gives you maximum control and zero extra hops but requires per-language library integration. Server-side discovery (Kubernetes Services, Envoy, AWS ALB) is language-agnostic and operationally simpler but adds a network hop and constrains load-balancing flexibility to what the proxy supports.

**For most FAANG-scale services today, the answer is**: Kubernetes Service for basic discovery + Envoy sidecar (Istio) for advanced L7 routing — server-side discovery, no client-side library required.
