# Service Mesh Pattern

## Overview
A service mesh is an infrastructure layer that handles service-to-service communication concerns — traffic management, security (mTLS), observability, and resilience — without requiring application code changes. These cross-cutting concerns are handled by sidecar proxies (or eBPF agents) that intercept all network traffic to and from each service.

Without a service mesh, every service must implement retry logic, timeouts, circuit breakers, TLS, and telemetry independently. At 100 services, this means 100 independent implementations — inconsistent, hard to audit, and impossible to change uniformly.

---

## Architecture

### Sidecar Proxy Model
```
Pod A                         Pod B
┌─────────────────────┐       ┌─────────────────────┐
│ ┌──────────────────┐│       │ ┌──────────────────┐ │
│ │  App Container   ││       │ │  App Container   │ │
│ │  (service A)     ││       │ │  (service B)     │ │
│ └────────┬─────────┘│       │ └────────┬─────────┘ │
│          │ localhost ││       │         │ localhost  │
│ ┌────────┴─────────┐│       │ ┌────────┴─────────┐ │
│ │  Sidecar Proxy   ││──────►│ │  Sidecar Proxy   │ │
│ │  (Envoy)         ││ mTLS  │ │  (Envoy)         │ │
│ └──────────────────┘│       │ └──────────────────┘ │
└─────────────────────┘       └─────────────────────┘
         ↑ config                       ↑ config
         └────────────────┬─────────────┘
                    Control Plane
                    (Istiod / Linkerd Controller)
```

The sidecar intercepts all inbound and outbound traffic. The application is unaware — it makes connections to localhost; the sidecar handles encryption, routing, and telemetry transparently.

### eBPF Model (Cilium, Ambient Mesh)
No sidecar — eBPF programs in the kernel intercept traffic at the OS level. Lower latency, lower resource overhead. Istio Ambient Mesh uses this model (ztunnel for L4, waypoint proxy for L7).

---

## Service Mesh Capabilities

### 1. Mutual TLS (mTLS)
Every service-to-service call is encrypted and authenticated. Both sides present a certificate; both verify the other.

```yaml
# Istio: enforce mTLS in the namespace
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata: {name: default, namespace: payments}
spec:
  mtls:
    mode: STRICT  # reject all non-mTLS traffic; no plaintext allowed
```

**Without service mesh**: mTLS requires each service to manage its own certificates, CA trust, and renewal. With mesh: Istiod (the CA) issues certificates to each pod automatically. Certificates rotate every 24 hours by default.

### 2. Authorization Policies
Define which services can call which services:

```yaml
# Allow only the api-gateway service to call payments-service
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata: {name: payments-authz, namespace: payments}
spec:
  selector: {matchLabels: {app: payments-service}}
  action: ALLOW
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/api-gateway/sa/api-gateway-service"]
    to:
    - operation:
        methods: ["POST"]
        paths: ["/api/v1/payments", "/api/v1/refunds"]
```

Any other service trying to call `payments-service` on any other endpoint gets a 403 RBAC_ACCESS_DENIED — enforced by the sidecar without any code change.

### 3. Traffic Management
Route traffic based on headers, weights, or other criteria:

```yaml
# Canary deployment: 90% to stable, 10% to canary
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata: {name: payments-routing}
spec:
  hosts: [payments-service]
  http:
  - match:
    - headers:
        x-canary: {exact: "true"}
    route:
    - destination: {host: payments-service, subset: canary}
  - route:
    - destination: {host: payments-service, subset: stable}
      weight: 90
    - destination: {host: payments-service, subset: canary}
      weight: 10
---
# Retry and timeout policy
spec:
  http:
  - route:
    - destination: {host: payments-service}
    timeout: 5s
    retries:
      attempts: 3
      perTryTimeout: 2s
      retryOn: "5xx,reset,connect-failure"
```

### 4. Circuit Breaking
```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata: {name: payments-circuit-breaker}
spec:
  host: payments-service
  trafficPolicy:
    outlierDetection:
      consecutiveErrors: 5          # 5 consecutive 5xx → eject
      interval: 30s                 # scan interval
      baseEjectionTime: 30s         # stay ejected for 30s (then probe)
      maxEjectionPercent: 50        # eject at most 50% of endpoints
    connectionPool:
      tcp:
        maxConnections: 100         # max connections to this service
      http:
        http1MaxPendingRequests: 50
        http2MaxRequests: 100
```

### 5. Observability (Golden Signals, Zero Code)
Every sidecar emits:
- **Metrics**: request rate, error rate, latency histogram (P50/P95/P99) — per service, per endpoint
- **Traces**: distributed traces propagated via B3/W3C headers; exported to Jaeger/Zipkin/Tempo
- **Access logs**: every request with timing, response code, upstream service

This happens for every service automatically — no instrumentation code required in the application.

---

## Istio vs Linkerd vs AWS App Mesh

| Dimension | Istio | Linkerd | AWS App Mesh |
|---|---|---|---|
| **Proxy** | Envoy (full-featured) | Linkerd proxy (Rust, lighter) | Envoy |
| **Complexity** | High | Low | Medium |
| **Features** | Richest (Wasm extensions, complex routing) | Essential (mTLS, retries, metrics) | AWS-native integration |
| **Performance overhead** | ~5ms p99 latency added | ~1ms p99 added | ~3ms |
| **Memory per sidecar** | ~50MB | ~10MB | ~30MB |
| **Multi-cluster** | Yes (Istio federation) | Yes (Linkerd multicluster) | AWS only |
| **Ambient mode** | Istio Ambient (no sidecar, eBPF) | N/A | N/A |
| **Learning curve** | Steep | Gentle | Medium (AWS docs-driven) |
| **Use when** | Full feature set needed; complex routing; Wasm plugins | Simplicity; Rust performance; low overhead | AWS ECS/EKS; AWS CloudMap integration |

**Recommendation**: Linkerd for teams new to service mesh (simplicity wins). Istio for teams needing advanced traffic management and Wasm extensibility. AWS App Mesh for AWS-native shops using ECS.

---

## Service Discovery (with and without mesh)

### Without mesh: AWS Cloud Map / DNS
```
Service A → DNS lookup: "payments.service.production" → Route53 private hosted zone
         → Returns IP:Port of running payments tasks/pods
         → Connects directly (no mTLS, no retry, no circuit breaker)
```

### With Istio: Service Registry + Virtual Services
```
Service A → Envoy intercepts → looks up VirtualService/DestinationRule for payments-service
         → Applies mTLS, retry, timeout, circuit breaker transparently
         → Routes to healthy endpoint (load balancing within Envoy)
```

---

## ECS with AWS App Mesh

AWS App Mesh integrates with ECS via Envoy as a sidecar container in the task definition:

```json
// Task definition with App Mesh Envoy sidecar
{
  "containerDefinitions": [
    {
      "name": "payments-app",
      "image": "...",
      "portMappings": [{"containerPort": 8080}]
    },
    {
      "name": "envoy",
      "image": "840364872350.dkr.ecr.us-east-1.amazonaws.com/aws-appmesh-envoy:v1.29.4",
      "environment": [
        {"name": "APPMESH_VIRTUAL_NODE_NAME", "value": "mesh/my-mesh/virtualNode/payments-vn"}
      ]
    }
  ],
  "proxyConfiguration": {
    "type": "APPMESH",
    "containerName": "envoy",
    "properties": [
      {"name": "IgnoredUID", "value": "1337"},
      {"name": "ProxyIngressPort", "value": "15000"},
      {"name": "AppPorts", "value": "8080"}
    ]
  }
}
```

---

## Observability Stack with Service Mesh

Standard stack for Kubernetes + Istio:

```
Sidecars emit metrics → Prometheus (scrapes Envoy metrics endpoint)
                      → Grafana (dashboards: service health, latency, error rate)

Sidecars emit traces  → OpenTelemetry Collector → Jaeger / Tempo
                      → Grafana (distributed trace UI)

Sidecars emit logs    → Fluent Bit → Loki / CloudWatch / OpenSearch

Kiali (Istio topology UI) → shows service graph with error rates, latency
```

**Kiali** is particularly powerful: visualises the service graph in real-time, shows which services are breaching SLOs, and lets you see the effect of traffic policies (which % of traffic is going to canary vs stable).

---

## Service Mesh Trade-offs

| Dimension | With Service Mesh | Without Service Mesh |
|---|---|---|
| **mTLS** | Automatic; uniform | Per-service; inconsistent |
| **Retries/timeouts** | Declarative YAML; no code | Implemented in each service |
| **Observability** | Automatic for all services | Instrumentation required per service |
| **Latency overhead** | +1–5ms per hop (sidecar) | None |
| **Memory overhead** | +10–50MB per pod (sidecar) | None |
| **Operational complexity** | High (mesh control plane, CRDs) | None |
| **Debugging** | Harder (traffic goes through proxy) | Simpler (direct connections) |
| **Language independence** | Yes — mesh works regardless of language | Must implement in each language |

**When NOT to use service mesh**:
- Small clusters (<50 services) — the operational overhead outweighs the benefit
- Teams without Kubernetes expertise — don't add mesh complexity before mastering Kubernetes basics
- Performance-critical workloads where 1–5ms sidecar overhead is unacceptable (use eBPF/ambient mode instead)

---

## Best Practices

1. **Enable mTLS in STRICT mode** — permissive mode (allows both TLS and plaintext) is a transition state; move to strict as soon as all services are in the mesh
2. **Start with PERMISSIVE mTLS** for migration — allows gradual service onboarding without breaking non-mesh services during rollout
3. **Define AuthorizationPolicy for every service** — default-deny is the goal; allow only required service-to-service calls
4. **Use mesh-level retries + circuit breakers** instead of library-based — removes inconsistency across services; centrally configurable
5. **Export traces to a central backend** (Jaeger/Tempo) from day one — retro-enabling tracing after an incident is too late
6. **Version control all mesh config** (VirtualServices, DestinationRules, AuthorizationPolicies) in Git — treat as infrastructure
7. **Use Kiali** (or equivalent) for visual topology — humans cannot reason about 100-service graphs from text configs
8. **Consider Ambient Mesh** (Istio) for new deployments — no sidecar overhead; simpler rollout; lower resource cost
9. **Set resource requests/limits on Envoy sidecars** — sidecar containers compete with the application for CPU/memory; leave headroom
10. **Canary mesh config changes** — a bad VirtualService can route all traffic to a broken service; test in staging; use progressive rollout

---

## FAANG Interview Points

**"How do you enforce zero-trust between microservices in Kubernetes?"**: Service mesh (Istio) with STRICT mTLS PeerAuthentication. AuthorizationPolicy: deny all by default; explicit ALLOW for required service-to-service paths. Workload certificates issued by Istiod (backed by private CA). Policy changes go through PR review and are applied via GitOps.

**"How do you do a canary deployment with traffic splitting?"**: Istio VirtualService with weighted routing: 90% to stable DestinationRule subset, 10% to canary subset. Flagger automates the weight progression: checks metrics (error rate, P99 latency) after each step. If metrics degrade, Flagger automatically rolls back by shifting weight back to stable.

**"What's the overhead of a service mesh?"**: Latency: +1ms (Linkerd) to +5ms (Istio) P99 per hop. Memory: +10MB (Linkerd) to +50MB (Istio) per pod. CPU: < 0.1 vCPU per sidecar at moderate load. The overhead is acceptable for most workloads and the benefit (automatic mTLS, observability, traffic control) outweighs it. For sub-millisecond latency requirements, use eBPF (Istio Ambient or Cilium) — no sidecar, no proxy hop.
