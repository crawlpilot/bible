# Sidecar Pattern — Envoy + OpenTelemetry + Consul

**Pattern:** Sidecar / Service Mesh  
**Components:** Envoy Proxy · OpenTelemetry Collector · Consul Service Discovery · Config Manager  
**Deployment targets:** Docker Compose (local/container) · Kubernetes  
**Interview context:** "How do you implement a service mesh?" / "How do you add observability without modifying application code?" / "Design the networking and observability layer for a microservices platform."

---

## What the Sidecar Pattern Solves

In a microservices architecture, every service needs the same cross-cutting capabilities:
- **mTLS** between services (auth + encryption)
- **Distributed tracing** (correlate a request across 10 hops)
- **Metrics collection** (latency, error rate, throughput)
- **Dynamic service discovery** (where is payment-service right now?)
- **Load balancing** (choose which instance to call)
- **Retry / circuit breaker** (handle downstream failures gracefully)
- **Config hot-reload** (change timeout values without redeploying)

The naive approach: implement all of these in every service. In Java, Go, and Python. Maintained by 12 teams. Updated whenever the standard changes.

**The sidecar approach:** Inject a proxy container alongside every service container. The proxy handles all of the above. The application talks only to `localhost`. All cross-cutting concerns live in the proxy — zero application code changes.

```
Without sidecar:                  With sidecar:
┌──────────────────────┐          ┌────────────────────────────────────┐
│ Service A            │          │ Pod / Task                         │
│ ┌──────────────────┐ │          │ ┌──────────────┐  ┌─────────────┐ │
│ │ App code         │ │          │ │ App code     │  │ Envoy       │ │
│ │ + mTLS library   │ │          │ │ (plain HTTP) │  │ sidecar     │ │
│ │ + tracing SDK    │ │          │ │              │  │ (mTLS,      │ │
│ │ + metrics SDK    │ │          │ │              │  │  tracing,   │ │
│ │ + retry logic    │ │          │ │              │  │  lb, retry) │ │
│ │ + circuit breaker│ │          │ └──────┬───────┘  └──────┬──────┘ │
│ └──────────────────┘ │          │        │ localhost        │        │
└──────────────────────┘          └────────┴─────────────────┴────────┘
                                           ↕ all network I/O goes
                                             through Envoy
```

---

## Component Roles

| Component | Role | Protocol |
|-----------|------|----------|
| **Envoy** | Sidecar proxy — handles all inbound/outbound traffic | HTTP/1.1, HTTP/2, gRPC, TCP |
| **OpenTelemetry Collector** | Receives telemetry from Envoy; processes; exports to backends | OTLP, Zipkin, Prometheus |
| **Consul** | Service registry + health checks + KV store | HTTP API, DNS |
| **Config Manager** | Serves Envoy dynamic config via xDS API | gRPC (xDS) |

---

## Full Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Control Plane                               │
│                                                                     │
│  ┌─────────────────┐   ┌─────────────────┐   ┌──────────────────┐  │
│  │ Consul           │   │ Config Manager  │   │ OTel Collector   │  │
│  │ (service         │   │ (xDS control    │   │ (telemetry       │  │
│  │  registry +      │◄──│  plane — serves │   │  pipeline)       │  │
│  │  health checks + │   │  Envoy dynamic  │   │                  │  │
│  │  KV config)      │   │  config)        │   │                  │  │
│  └────────┬─────────┘   └────────┬────────┘   └───────┬──────────┘  │
│           │ Service discovery    │ xDS (LDS/CDS/       │             │
│           │                      │ EDS/RDS)            │ OTLP        │
└───────────┼──────────────────────┼─────────────────────┼─────────────┘
            │                      │                      │
            ▼                      ▼                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Data Plane (each service + sidecar)                                │
│                                                                     │
│  ┌──────────────────────────────────────┐                          │
│  │  Pod / ECS Task                      │                          │
│  │                                      │                          │
│  │  ┌────────────┐     ┌─────────────┐  │                          │
│  │  │ Service A  │     │ Envoy       │  │                          │
│  │  │ :8080      │◄───►│ :15001 in   │◄─┼── inbound from mesh     │
│  │  │            │     │ :15001 out  │──┼── outbound to mesh      │
│  │  │            │     │ :9901 admin │  │                          │
│  │  └────────────┘     └──────┬──────┘  │                          │
│  │   localhost only           │ OTLP    │                          │
│  └────────────────────────────┼─────────┘                          │
│                               └──────────────────────────────────► │
│                                         OTel Collector             │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Component 1: Envoy as the Sidecar

Envoy is a high-performance L4/L7 proxy written in C++ by Lyft, now the de facto standard sidecar for service meshes (Istio, AWS App Mesh both use Envoy as the data plane).

### Why Envoy

| Feature | Envoy | Nginx | HAProxy |
|---------|-------|-------|---------|
| Dynamic config (no reload) | ✅ xDS API | ❌ Requires reload | ❌ Requires reload |
| Native gRPC support | ✅ | Partial | ❌ |
| L7 routing (by header, path, method) | ✅ | ✅ | Limited |
| Built-in tracing (Zipkin/OTel) | ✅ | ❌ | ❌ |
| Circuit breaker | ✅ | ❌ | ❌ |
| Outlier detection | ✅ | ❌ | ❌ |
| Admin API | ✅ | Limited | Limited |
| WASM extensibility | ✅ | ❌ | ❌ |

### Envoy Configuration: Static Bootstrap

Every Envoy instance starts with a bootstrap config. In sidecar mode this defines the admin port, xDS server address, and any static listeners/clusters.

```yaml
# envoy-bootstrap.yaml
admin:
  address:
    socket_address:
      address: 0.0.0.0
      port_value: 9901              # admin interface — metrics, config dump, drain

node:
  id: "${POD_NAME}"                  # unique per instance
  cluster: "${SERVICE_NAME}"
  metadata:
    service: "${SERVICE_NAME}"
    version: "${SERVICE_VERSION}"

dynamic_resources:
  lds_config:                        # Listener Discovery Service
    resource_api_version: V3
    api_config_source:
      api_type: GRPC
      transport_api_version: V3
      grpc_services:
        - envoy_grpc:
            cluster_name: xds_cluster
      refresh_delay: 5s

  cds_config:                        # Cluster Discovery Service
    resource_api_version: V3
    api_config_source:
      api_type: GRPC
      transport_api_version: V3
      grpc_services:
        - envoy_grpc:
            cluster_name: xds_cluster

static_resources:
  clusters:
    - name: xds_cluster               # Config Manager — control plane
      type: STRICT_DNS
      connect_timeout: 5s
      http2_protocol_options: {}
      load_assignment:
        cluster_name: xds_cluster
        endpoints:
          - lb_endpoints:
              - endpoint:
                  address:
                    socket_address:
                      address: config-manager
                      port_value: 18000

    - name: otel_collector            # OTel Collector — telemetry
      type: STRICT_DNS
      connect_timeout: 5s
      http2_protocol_options: {}
      load_assignment:
        cluster_name: otel_collector
        endpoints:
          - lb_endpoints:
              - endpoint:
                  address:
                    socket_address:
                      address: otel-collector
                      port_value: 4317
```

---

## Component 2: Service Discovery with Consul

Consul is HashiCorp's service mesh and service registry. In this architecture, Consul is the **source of truth for where services live**.

### How Consul Works

```
Service registers with Consul on startup
    │
    ├─ Service: "I am payment-service, running at 10.0.1.5:8080"
    │
Consul runs health checks (HTTP GET /health every 10s)
    │
    ├─ If check passes: service is healthy, in the registry
    ├─ If check fails 2× consecutive: service is deregistered
    │
Config Manager watches Consul for changes via watch API
    │
    └─ When service instances change → push updated EDS to Envoy via xDS
```

### Consul Service Registration

```hcl
# consul-service.hcl — deployed alongside each service
service {
  name    = "payment-service"
  id      = "payment-service-${INSTANCE_ID}"
  port    = 8080
  address = "${POD_IP}"

  tags = [
    "version=2.4.1",
    "env=prod",
    "region=us-east-1"
  ]

  meta = {
    protocol = "http"
    team     = "payments"
  }

  check {
    name     = "HTTP health check"
    http     = "http://${POD_IP}:8080/health"
    interval = "10s"
    timeout  = "3s"
    deregister_critical_service_after = "60s"
  }
}
```

Registration via API (programmatic, for containerised services):

```bash
# On startup, register with Consul
curl -X PUT http://consul:8500/v1/agent/service/register \
  -H "Content-Type: application/json" \
  -d '{
    "Name": "payment-service",
    "ID": "payment-service-abc123",
    "Port": 8080,
    "Address": "10.0.1.5",
    "Check": {
      "HTTP": "http://10.0.1.5:8080/health",
      "Interval": "10s",
      "Timeout": "3s",
      "DeregisterCriticalServiceAfter": "60s"
    }
  }'
```

### Consul KV for Config

Consul also provides a key-value store used for runtime config (timeouts, feature flags, retry policies):

```bash
# Write config values
consul kv put config/payment-service/upstream_timeout_ms 2000
consul kv put config/payment-service/retry_attempts 3
consul kv put config/payment-service/circuit_breaker_threshold 50

# Config Manager watches these keys and pushes to Envoy dynamically
```

---

## Component 3: Config Manager (xDS Control Plane)

The Config Manager is the control plane that translates service registry state (from Consul) into Envoy dynamic configuration (via xDS).

Envoy's xDS (discovery services) protocol is how Envoy learns its configuration dynamically — no process restart required.

### xDS API Surface

| API | Full Name | What it controls |
|-----|-----------|-----------------|
| LDS | Listener Discovery Service | What ports Envoy listens on and with what filters |
| RDS | Route Discovery Service | HTTP routing rules (path, header matching) |
| CDS | Cluster Discovery Service | Upstream service definitions (name, LB policy, circuit breaker) |
| EDS | Endpoint Discovery Service | Which IP:port instances belong to each cluster |
| SDS | Secret Discovery Service | TLS certificates for mTLS |

### Config Manager: Core Logic

```go
// config-manager/main.go (simplified)
package main

type ConfigManager struct {
    consulClient  *consul.Client
    snapshotCache cache.SnapshotCache
    nodeHash      cache.NodeHash
}

// Watch Consul for service changes
func (cm *ConfigManager) WatchConsul(ctx context.Context) {
    // Watch all services continuously
    services, _, err := cm.consulClient.Health().Services("", "", true, &consul.QueryOptions{
        WaitIndex: 0,
        WaitTime:  30 * time.Second,
    })

    for {
        // Build Envoy snapshot from current Consul state
        snapshot := cm.buildSnapshot(services)

        // Push to all registered Envoy instances
        cm.snapshotCache.SetSnapshot(ctx, "all", snapshot)
    }
}

func (cm *ConfigManager) buildSnapshot(services map[string][]*consul.ServiceEntry) *cache.Snapshot {
    var clusters []types.Resource
    var endpoints []types.Resource
    var listeners []types.Resource
    var routes []types.Resource

    for serviceName, instances := range services {
        // Build Cluster (upstream service definition)
        cluster := &cluster.Cluster{
            Name:                 serviceName,
            ConnectTimeout:       durationpb.New(5 * time.Second),
            ClusterDiscoveryType: &cluster.Cluster_Type{Type: cluster.Cluster_EDS},
            EdsClusterConfig: &cluster.Cluster_EdsClusterConfig{
                EdsConfig: &core.ConfigSource{
                    ConfigSourceSpecifier: &core.ConfigSource_Ads{},
                },
            },
            // Circuit breaker
            CircuitBreakers: &cluster.CircuitBreakers{
                Thresholds: []*cluster.CircuitBreakers_Thresholds{{
                    MaxConnections:     wrapperspb.UInt32(100),
                    MaxPendingRequests: wrapperspb.UInt32(50),
                    MaxRequests:        wrapperspb.UInt32(200),
                }},
            },
            // Outlier detection (auto-ejects unhealthy instances)
            OutlierDetection: &cluster.OutlierDetection{
                ConsecutiveGatewayFailure:          wrapperspb.UInt32(5),
                BaseEjectionTime:                   durationpb.New(30 * time.Second),
                MaxEjectionPercent:                 wrapperspb.UInt32(50),
            },
        }
        clusters = append(clusters, cluster)

        // Build Endpoints (one per healthy Consul instance)
        var lbEndpoints []*endpoint.LbEndpoint
        for _, svc := range instances {
            lbEndpoints = append(lbEndpoints, &endpoint.LbEndpoint{
                HostIdentifier: &endpoint.LbEndpoint_Endpoint{
                    Endpoint: &endpoint.Endpoint{
                        Address: &core.Address{
                            Address: &core.Address_SocketAddress{
                                SocketAddress: &core.SocketAddress{
                                    Address:       svc.Service.Address,
                                    PortSpecifier: &core.SocketAddress_PortValue{
                                        PortValue: uint32(svc.Service.Port),
                                    },
                                },
                            },
                        },
                    },
                },
            })
        }

        cla := &endpoint.ClusterLoadAssignment{
            ClusterName: serviceName,
            Endpoints: []*endpoint.LocalityLbEndpoints{{
                LbEndpoints: lbEndpoints,
            }},
        }
        endpoints = append(endpoints, cla)
    }

    // Build HTTP connection manager listener with tracing
    listener := buildHttpListener()
    listeners = append(listeners, listener)

    snapshot, _ := cache.NewSnapshot(
        time.Now().String(),
        map[resource.Type][]types.Resource{
            resource.ClusterType:  clusters,
            resource.EndpointType: endpoints,
            resource.ListenerType: listeners,
            resource.RouteType:    routes,
        },
    )
    return snapshot
}
```

---

## Component 4: OpenTelemetry Integration

Envoy has native support for exporting traces via Zipkin and OpenTelemetry. OTel Collector acts as the central processing hub.

### Envoy Tracing Configuration

Configured in the HTTP Connection Manager filter via the xDS LDS config:

```yaml
# Part of the Listener config pushed by Config Manager (xDS)
http_filters:
  - name: envoy.filters.http.router

# Tracing config on the HTTP connection manager
tracing:
  provider:
    name: envoy.tracers.opentelemetry
    typed_config:
      "@type": type.googleapis.com/envoy.config.trace.v3.OpenTelemetryConfig
      grpc_service:
        envoy_grpc:
          cluster_name: otel_collector
        timeout: 5s
      service_name: "${SERVICE_NAME}"

# Tracing decision: sample 10% of requests, 100% of errors
tracing:
  random_sampling:
    value: 10.0
```

### OTel Collector Pipeline

The OTel Collector receives Envoy's traces + metrics and routes them to backends:

```yaml
# otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317      # Envoy sends traces here
      http:
        endpoint: 0.0.0.0:4318

  prometheus:
    config:
      scrape_configs:
        - job_name: envoy-sidecars
          static_configs:
            - targets: ['envoy-sidecar:9901']   # Envoy admin metrics
          metrics_path: /stats/prometheus

processors:
  batch:
    timeout: 10s
    send_batch_size: 1000

  # Add service metadata from Consul to spans
  resource:
    attributes:
      - key: deployment.environment
        value: "${ENV}"
        action: upsert

  # Tail-based sampling: keep all errors + 5% of successes
  tail_sampling:
    decision_wait: 10s
    policies:
      - name: errors
        type: status_code
        status_code: {status_codes: [ERROR]}
      - name: slow-requests
        type: latency
        latency: {threshold_ms: 1000}
      - name: sample-rest
        type: probabilistic
        probabilistic: {sampling_percentage: 5}

exporters:
  # Traces → Grafana Tempo
  otlp/tempo:
    endpoint: http://tempo:4317
    tls:
      insecure: true

  # Metrics → Prometheus / AMP
  prometheusremotewrite:
    endpoint: http://prometheus:9090/api/v1/write

  # Debug
  debug:
    verbosity: normal

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [resource, tail_sampling, batch]
      exporters: [otlp/tempo]

    metrics:
      receivers: [otlp, prometheus]
      processors: [resource, batch]
      exporters: [prometheusremotewrite]
```

### Key Envoy Metrics Exposed

Envoy's `/stats/prometheus` endpoint exposes 1000+ metrics. The critical ones:

```
# Downstream (inbound to this service via sidecar)
envoy_http_downstream_rq_total                    — total requests received
envoy_http_downstream_rq_time_bucket              — latency histogram
envoy_http_downstream_rq_5xx                      — 5xx responses
envoy_http_downstream_cx_active                   — active connections

# Upstream (outbound from this service)
envoy_cluster_upstream_rq_total{cluster="payment-service"}
envoy_cluster_upstream_rq_time_bucket{cluster="payment-service"}
envoy_cluster_upstream_rq_pending_overflow{cluster="payment-service"}  ← circuit breaker
envoy_cluster_upstream_cx_overflow{cluster="payment-service"}

# Circuit breaker state
envoy_cluster_circuit_breakers_default_cx_open{cluster="payment-service"}
```

---

## Deployment: Docker Compose (Container Setup)

For local development and non-Kubernetes environments.

### File Structure

```
sidecar-demo/
├── docker-compose.yml
├── envoy/
│   ├── bootstrap.yaml
│   └── entrypoint.sh
├── consul/
│   └── config.hcl
├── otel-collector/
│   └── config.yaml
├── config-manager/
│   ├── Dockerfile
│   └── main.go
└── services/
    ├── order-service/
    │   └── ...
    └── payment-service/
        └── ...
```

### docker-compose.yml

```yaml
version: "3.9"

networks:
  mesh:
    driver: bridge

services:

  # ── Control Plane ──────────────────────────────────────────────────

  consul:
    image: hashicorp/consul:1.17
    command: consul agent -server -bootstrap-expect=1 -ui -client=0.0.0.0 -data-dir=/consul/data
    ports:
      - "8500:8500"    # HTTP API + UI
      - "8600:8600/udp" # DNS
    volumes:
      - ./consul/config.hcl:/consul/config/config.hcl
    networks: [mesh]

  config-manager:
    build: ./config-manager
    environment:
      CONSUL_ADDR: consul:8500
      XDS_PORT: "18000"
    ports:
      - "18000:18000"
    depends_on: [consul]
    networks: [mesh]

  otel-collector:
    image: otel/opentelemetry-collector-contrib:latest
    command: ["--config=/etc/otel/config.yaml"]
    volumes:
      - ./otel-collector/config.yaml:/etc/otel/config.yaml
    ports:
      - "4317:4317"    # OTLP gRPC
      - "4318:4318"    # OTLP HTTP
      - "8888:8888"    # Collector self-metrics
    networks: [mesh]

  # ── Services + Sidecars ────────────────────────────────────────────

  order-service:
    build: ./services/order-service
    environment:
      PORT: "8080"
      # Services talk to localhost — Envoy intercepts and routes
      PAYMENT_SERVICE_URL: "http://127.0.0.1:15001/payment-service"
    networks: [mesh]

  order-service-sidecar:
    image: envoyproxy/envoy:v1.29-latest
    environment:
      SERVICE_NAME: order-service
      POD_NAME: order-service-1
      POD_IP: ""
    volumes:
      - ./envoy/bootstrap.yaml:/etc/envoy/envoy.yaml
    entrypoint: ["/bin/sh", "/etc/envoy/entrypoint.sh"]
    depends_on: [order-service, config-manager, consul]
    network_mode: "service:order-service"   # Shares network namespace with app

  payment-service:
    build: ./services/payment-service
    environment:
      PORT: "8080"
    networks: [mesh]

  payment-service-sidecar:
    image: envoyproxy/envoy:v1.29-latest
    environment:
      SERVICE_NAME: payment-service
      POD_NAME: payment-service-1
    volumes:
      - ./envoy/bootstrap.yaml:/etc/envoy/envoy.yaml
    entrypoint: ["/bin/sh", "/etc/envoy/entrypoint.sh"]
    depends_on: [payment-service, config-manager, consul]
    network_mode: "service:payment-service"

```

**Key:** `network_mode: "service:order-service"` gives the Envoy sidecar the same network namespace as the app container — they share `localhost`. This is how the sidecar intercepts all traffic without iptables.

### Entrypoint: Consul Registration + Envoy Start

```bash
#!/bin/sh
# envoy/entrypoint.sh

# Register with Consul on startup
curl -sf -X PUT http://consul:8500/v1/agent/service/register \
  -H "Content-Type: application/json" \
  -d "{
    \"Name\": \"${SERVICE_NAME}\",
    \"ID\": \"${POD_NAME}\",
    \"Port\": 8080,
    \"Address\": \"$(hostname -i)\",
    \"Tags\": [\"env=local\"],
    \"Check\": {
      \"HTTP\": \"http://$(hostname -i):8080/health\",
      \"Interval\": \"10s\",
      \"Timeout\": \"3s\",
      \"DeregisterCriticalServiceAfter\": \"60s\"
    }
  }"

# Deregister on shutdown
trap "curl -sf -X PUT http://consul:8500/v1/agent/service/deregister/${POD_NAME}" EXIT

# Start Envoy
envoy -c /etc/envoy/envoy.yaml \
  --service-node "${POD_NAME}" \
  --service-cluster "${SERVICE_NAME}" \
  -l warning
```

---

## Deployment: Kubernetes

In Kubernetes, the sidecar is injected automatically into every Pod via a **Mutating Webhook Admission Controller** — no manual Deployment changes required.

### Architecture on Kubernetes

```
┌─────────────────────────────────────────────────────────────────────┐
│  Kubernetes Cluster                                                 │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────┐      │
│  │  kube-system namespace                                   │      │
│  │  - Sidecar injector (MutatingWebhookConfiguration)       │      │
│  └──────────────────────────────────────────────────────────┘      │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────┐      │
│  │  mesh-system namespace                                   │      │
│  │  - Consul (StatefulSet, 3 replicas)                      │      │
│  │  - Config Manager (Deployment)                           │      │
│  │  - OTel Collector (DaemonSet — one per node)             │      │
│  └──────────────────────────────────────────────────────────┘      │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────┐      │
│  │  app namespace                                           │      │
│  │                                                          │      │
│  │  ┌───────────────────────────────┐                       │      │
│  │  │  Pod: order-service           │                       │      │
│  │  │  ┌──────────────┐ ┌────────┐  │                       │      │
│  │  │  │ order-service│ │ envoy  │  │  ← injected by webhook│      │
│  │  │  │ container    │ │sidecar │  │                       │      │
│  │  │  └──────────────┘ └────────┘  │                       │      │
│  │  │  initContainer: iptables-init │  ← redirects traffic  │      │
│  │  └───────────────────────────────┘                       │      │
│  └──────────────────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────────────┘
```

### Service Deployment (No Sidecar Config Required by Developers)

```yaml
# order-service/deployment.yaml
# Developers write this — no sidecar config needed
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-service
  namespace: app
  annotations:
    sidecar.mesh/inject: "true"           # ← only annotation needed
    sidecar.mesh/service-name: "order-service"
spec:
  replicas: 3
  selector:
    matchLabels:
      app: order-service
  template:
    metadata:
      labels:
        app: order-service
    spec:
      containers:
        - name: order-service
          image: order-service:2.4.1
          ports:
            - containerPort: 8080
          env:
            - name: PAYMENT_SERVICE_URL
              value: "http://payment-service/api/v1"   # logical name — Envoy resolves
```

### Sidecar Injector Webhook

The webhook intercepts Pod creation and adds the Envoy container and iptables init container:

```yaml
# What the webhook adds to every annotated Pod:

initContainers:
  - name: mesh-init
    image: mesh/iptables-init:latest
    securityContext:
      capabilities:
        add: [NET_ADMIN]
    command:
      - /bin/sh
      - -c
      - |
        # Redirect all inbound traffic to Envoy port 15006
        iptables -t nat -A PREROUTING -p tcp -j REDIRECT --to-port 15006
        # Redirect all outbound traffic (except Envoy itself) to Envoy port 15001
        iptables -t nat -A OUTPUT -p tcp -m owner ! --uid-owner 1337 -j REDIRECT --to-port 15001

containers:
  # (existing app containers unchanged)
  - name: envoy
    image: envoyproxy/envoy:v1.29-latest
    securityContext:
      runAsUser: 1337   # UID exempt from iptables redirect
    env:
      - name: POD_NAME
        valueFrom:
          fieldRef:
            fieldPath: metadata.name
      - name: POD_NAMESPACE
        valueFrom:
          fieldRef:
            fieldPath: metadata.namespace
      - name: SERVICE_NAME
        valueFrom:
          fieldRef:
            fieldPath: metadata.annotations['sidecar.mesh/service-name']
    args:
      - -c /etc/envoy/bootstrap.yaml
      - --service-node $(POD_NAME)
      - --service-cluster $(SERVICE_NAME)
    ports:
      - containerPort: 15001  # outbound intercept
      - containerPort: 15006  # inbound intercept
      - containerPort: 9901   # admin
    resources:
      requests:
        cpu: 10m
        memory: 40Mi
      limits:
        cpu: 100m
        memory: 128Mi
```

**How iptables interception works:**
- `PREROUTING`: Any TCP packet arriving at the Pod is redirected to Envoy port 15006 before the app sees it
- `OUTPUT`: Any TCP packet the app sends out is redirected to Envoy port 15001
- Envoy itself runs as UID 1337, which is explicitly exempt from the OUTPUT redirect (prevents infinite loop)
- Result: all app traffic flows through Envoy transparently — the app only knows `localhost`

### Consul on Kubernetes

```yaml
# consul/statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: consul
  namespace: mesh-system
spec:
  serviceName: consul
  replicas: 3   # production minimum: 3 for fault tolerance
  selector:
    matchLabels:
      app: consul
  template:
    spec:
      containers:
        - name: consul
          image: hashicorp/consul:1.17
          command:
            - consul
            - agent
            - -server
            - -bootstrap-expect=3
            - -datacenter=us-east-1
            - -data-dir=/consul/data
            - -client=0.0.0.0
            - -ui
            - -retry-join=consul-0.consul.mesh-system.svc.cluster.local
            - -retry-join=consul-1.consul.mesh-system.svc.cluster.local
            - -retry-join=consul-2.consul.mesh-system.svc.cluster.local
          ports:
            - containerPort: 8500   # HTTP API
            - containerPort: 8600   # DNS
            - containerPort: 8301   # Serf LAN gossip
```

Consul on Kubernetes uses Kubernetes service accounts for auth — no separate secret management needed.

### OTel Collector as DaemonSet

```yaml
# otel-collector/daemonset.yaml
# One Collector per node — reduces network hops vs. per-pod
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: otel-collector
  namespace: mesh-system
spec:
  selector:
    matchLabels:
      app: otel-collector
  template:
    spec:
      containers:
        - name: otel-collector
          image: otel/opentelemetry-collector-contrib:latest
          args: ["--config=/etc/otel/config.yaml"]
          ports:
            - containerPort: 4317   # OTLP gRPC
            - containerPort: 4318   # OTLP HTTP
          resources:
            requests:
              cpu: 50m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
          volumeMounts:
            - name: config
              mountPath: /etc/otel
      volumes:
        - name: config
          configMap:
            name: otel-collector-config
```

---

## Trade-off Analysis

### Advantages

| Dimension | Benefit |
|-----------|---------|
| **Zero app code changes** | Observability, mTLS, retries, circuit breaking — all without a library import |
| **Language agnostic** | Java, Go, Python, Node services all get the same capabilities |
| **Centralised policy** | Change retry policy, sampling rate, or circuit breaker threshold in Config Manager — no service redeploy |
| **Consistent telemetry** | Every service emits the same trace format, metric names, log structure |
| **Gradual rollout** | Enable mTLS for one service at a time; dark-launch new routing rules via header matching |
| **Operational visibility** | Envoy admin at `:9901` shows live traffic, upstream health, circuit breaker state — no instrumentation needed |

### Disadvantages

| Dimension | Cost |
|-----------|------|
| **Resource overhead** | Each Envoy sidecar: ~10m CPU + 40MB memory at rest. At 100 pods = 1 CPU + 4GB memory just for proxies |
| **Latency addition** | Each hop through Envoy adds ~0.1–0.5ms. For a request that crosses 5 services = 1–2.5ms additional latency |
| **Operational complexity** | 3 new systems to operate: Consul, Config Manager, OTel Collector. Each needs HA, monitoring, upgrade procedures |
| **Debugging complexity** | Traffic now flows through a proxy layer — "why is this request failing?" now requires checking Envoy logs, not just app logs |
| **xDS expertise required** | Writing and debugging xDS configuration (LDS/RDS/CDS/EDS) requires deep Envoy knowledge |
| **Startup sequencing** | App containers must wait for Envoy to be ready; init containers add to pod startup time |

### Key Trade-offs

**Trade-off 1: Latency vs. Observability**  
Every request adds ~0.1–0.5ms per hop through Envoy. For real-time systems with < 10ms end-to-end SLOs, this is significant. For most SaaS systems with > 50ms SLOs, it is not. **Decision rule:** if p99 SLO < 20ms, measure carefully before adopting; if SLO > 50ms, accept the overhead.

**Trade-off 2: Operational simplicity vs. Platform capability**  
Without a service mesh: each team manages their own client-side load balancing, retries, and circuit breakers. Simpler overall, but inconsistent and hard to enforce standards. With a mesh: consistent behaviour across all services, but 3 new platform components to operate. **Decision rule:** if you have a platform/SRE team that can own the mesh, the trade-off is clearly positive at 10+ services.

**Trade-off 3: Control plane availability vs. Data plane availability**  
If the Config Manager goes down, Envoy continues serving traffic with the last known configuration — the data plane is resilient. But no new configuration can be pushed. **This is Envoy's most important resilience property:** the control plane can be unavailable without affecting service-to-service traffic.

**Trade-off 4: Consul vs. Kubernetes-native service discovery (kube-dns)**  
Consul provides richer metadata, multi-datacenter federation, and health checks beyond Kubernetes liveness probes. Kubernetes DNS is simpler (zero operational overhead) but has no dynamic topology signals for Envoy. **Decision rule:** Kubernetes-only deployments can use Kubernetes endpoints API as the xDS source; use Consul when you have multi-DC, hybrid-cloud, or non-Kubernetes workloads to register.

---

## When NOT to Use This Pattern

| Scenario | Reason |
|----------|--------|
| < 5 services, single team | Operational overhead exceeds the benefit |
| < 10ms latency SLO | Proxy hop latency may violate SLO |
| Serverless / AWS Lambda | No persistent container to attach a sidecar to |
| Team has no platform engineering capacity | 3 new systems to operate without dedicated ownership will rot |
| Batch processing workloads | Service-to-service networking is not the bottleneck; observability can be cheaper |

---

## Usage Patterns

The sidecar pattern is not a single deployment model — it appears in four distinct usage patterns, each with different scope and trade-offs.

---

### Pattern A: Observability-Only Sidecar (Entry Pattern)

**What:** Inject Envoy solely for metrics + tracing. No mTLS. No traffic routing. Minimal xDS configuration.

**When:** You have an existing service fleet and want to add observability without touching app code or introducing mTLS complexity.

```
App → Envoy (traces + metrics only) → OTel Collector → Backends
         ↓ still plain HTTP to upstreams
      (no routing, no TLS, no circuit breaker)
```

**Complexity:** Low. Single OTel Collector, simple Envoy bootstrap. No Config Manager required — static Envoy config suffices.

**Adoption path:** This is the first step. Prove the value of uniform observability before adding mTLS or dynamic routing.

---

### Pattern B: Full Service Mesh (Mature Pattern)

**What:** Full sidecar injection with mTLS, dynamic routing, circuit breaking, retries, and service discovery — exactly as described in this document.

**When:** 10+ services, multi-team, need platform-enforced standards for reliability and security.

**Complexity:** High. Requires: Config Manager (xDS), Consul, OTel Collector, certificate management (SDS), MutatingWebhook.

**The operational cost is real:** At 100 pods, you are running 100 Envoy sidecars + 3 Consul nodes + Config Manager + OTel DaemonSet. This is 4–6 additional components with their own on-call, upgrade, and scaling concerns. Assign a platform team before adopting.

---

### Pattern C: Sidecar as API Gateway (Ingress Pattern)

**What:** A standalone Envoy instance (not a sidecar — a dedicated pod/container) at the cluster edge, using xDS for dynamic routing to internal services.

**When:** You want a programmable API gateway (header routing, canary, auth filters) without adopting a commercial API gateway product.

```
Internet → Envoy (edge, standalone) → Internal services
           ↑
           xDS config from Config Manager
           (routing rules, rate limits, auth filters via WASM)
```

**Advantage over ALB/NGINX:** Same xDS API as internal sidecars — routing rules are defined consistently across edge and mesh.

**Disadvantage vs. ALB:** No managed TLS renewal, no built-in WAF, higher operational burden.

---

### Pattern D: Node-Level Proxy (Alternative to Sidecar)

**What:** A single Envoy proxy runs per node (DaemonSet), not per pod. All pods on the node share it.

**When:** Resource overhead of per-pod sidecars is unacceptable (very high pod density, constrained nodes).

```
Node:
  Pod A → node-proxy Envoy → external
  Pod B → node-proxy Envoy → external
  Pod C → node-proxy Envoy → external
```

**Trade-off:** Lower resource overhead (one proxy per node instead of one per pod). But per-pod traffic isolation is lost — the proxy cannot distinguish Pod A's traffic from Pod B's without L4 source port tracking. Circuit breaker and outlier detection are per-node, not per-pod.

**Istio Ambient Mesh** (ztunnel) uses this model as its L4 layer, adding per-pod L7 sidecars only for services that need advanced L7 features.

---

## Consul vs. Service Discovery Alternatives

Consul is one of several options for service discovery and health checking. The choice between them is one of the most common trade-off questions in system design interviews.

---

### Comparison Table

| Dimension | **Consul** | **Kubernetes Endpoints API** | **AWS Cloud Map** | **Eureka (Netflix OSS)** | **etcd / ZooKeeper** |
|-----------|-----------|-----------------------------|--------------------|--------------------------|----------------------|
| **Primary use** | Service registry + health + KV + mTLS | K8s-native service discovery | Cloud-native AWS service registry | JVM service registry (Spring Boot) | Distributed coordination (not service discovery primarily) |
| **Health checks** | Rich (HTTP, TCP, gRPC, script, TTL) | K8s liveness/readiness probes | HTTP, custom | Client heartbeat (TTL) | TTL via ephemeral nodes |
| **Multi-datacenter** | ✅ Native WAN federation | ❌ (requires external tools) | ✅ (per region, manual cross-region) | ❌ | ❌ (single cluster) |
| **Non-K8s workloads** | ✅ Works for VMs, ECS, bare metal | ❌ K8s pods only | ✅ Any IP:port | ✅ | ✅ |
| **KV store** | ✅ Built-in | ❌ (ConfigMap is separate) | ❌ | ❌ | ✅ (etcd) |
| **DNS interface** | ✅ Built-in DNS resolver | ✅ kube-dns / CoreDNS | ✅ Route 53 | ❌ | ❌ |
| **Service mesh / mTLS** | ✅ Consul Connect (built-in) | ✅ via Istio / Linkerd | ❌ | ❌ | ❌ |
| **ACL / RBAC** | ✅ Fine-grained ACL tokens | ✅ via K8s RBAC | ✅ via IAM | ❌ | ✅ (etcd RBAC) |
| **xDS support** | ✅ via Consul API (used by Envoy) | ✅ Native (K8s Endpoints → EDS) | ❌ | ❌ | ❌ |
| **Operational complexity** | Medium (cluster of 3–5 agents) | Zero (part of K8s control plane) | Zero (managed AWS) | Medium (Spring Cloud config) | Medium–High |
| **Open source** | ✅ (HashiCorp BSL 2.1+) | ✅ (Apache 2.0) | ❌ (AWS proprietary) | ✅ (Apache 2.0, maintained by Netflix/Pivotal) | ✅ |

---

### When to Choose Consul

Choose Consul when:
- You have **hybrid deployments**: VMs, ECS, Kubernetes, bare metal — Consul is the only mature option that registers all of them in one registry
- You need **multi-datacenter service discovery** with WAN federation — Consul's native multi-DC model is the easiest to operate at this scope
- You want **Consul Connect** (built-in service mesh using Envoy under the hood) — it gives you a supported, integrated service mesh without building your own xDS control plane
- You need **runtime KV config** that Envoy routing rules or app code can read without a separate config service
- You are already invested in **HashiCorp ecosystem** (Terraform, Vault, Nomad) — integration is first-class

**FAANG companies using Consul:** HashiCorp lists Cloudflare, Barclays, and various financial firms. Netflix uses Eureka (JVM) — they built it before Consul existed.

---

### When to Use Kubernetes Endpoints API Instead

The Kubernetes Endpoints API (and its newer replacement, EndpointSlices) is the zero-operational-overhead option for pure Kubernetes deployments:

```
How it works:
  - Every Kubernetes Service creates an Endpoints object
  - Endpoints contains the IP:port of all healthy (ready) pods
  - Envoy xDS can be served by any control plane that watches K8s API (e.g., Istiod, custom controller)
  - No Consul needed — the K8s control plane IS the service registry
```

**Advantage:** Zero additional infrastructure. No Consul agent to run, upgrade, or monitor. kube-proxy and CoreDNS handle basic service-to-service routing natively.

**Disadvantage vs. Consul:**
- Cannot register non-Kubernetes workloads (VMs, external services)
- Health checks are limited to pod readiness probes (Consul's HTTP/TCP/script checks are richer)
- No built-in multi-cluster federation — requires additional tooling (Submariner, Istio multi-cluster, Cilium Cluster Mesh)
- No native KV store for runtime config

**Decision rule:** Pure Kubernetes, single cluster, Kubernetes-only workloads → use K8s Endpoints. Multi-cloud, hybrid, or multi-DC → use Consul.

---

### When to Use AWS Cloud Map

AWS Cloud Map is fully managed — no servers to run. Integrates natively with ECS, EKS, EC2, and Route 53.

```
ECS task starts → ECS registers to Cloud Map automatically → Route 53 DNS resolves the service
```

**Advantage:** Zero operational overhead in AWS. If you are already all-in on AWS managed services (ECS, EKS, ALB, Route 53), Cloud Map is the natural choice.

**Disadvantage vs. Consul:**
- AWS-only — no multi-cloud or hybrid-cloud path
- No native KV config store
- No built-in service mesh / mTLS (must use App Mesh or Istio alongside)
- DNS-only service discovery — Envoy dynamic EDS requires a separate adapter

**When to choose:** Greenfield AWS deployment, no multi-cloud requirement, operational simplicity is paramount.

---

### Consul Connect vs. Istio vs. Linkerd vs. AWS App Mesh

If you are adopting a service mesh (not just service discovery), the choice is between building your own (this document) or adopting a managed mesh. Here is how the options compare:

| Dimension | **Custom (Envoy + Consul + Config Manager)** | **Consul Connect** | **Istio** | **Linkerd** | **AWS App Mesh** |
|-----------|----------------------------------------------|--------------------|-----------|-----------|--------------------|
| **Data plane** | Envoy (your config) | Envoy (managed by Consul) | Envoy (managed by Istiod) | Linkerd2-proxy (Rust, ultra-light) | Envoy (managed by AWS) |
| **Control plane** | Custom (you build it) | Consul server cluster | Istiod | Linkerd control plane | AWS managed |
| **Config interface** | xDS YAML / Go code | Consul service config + intentions | Kubernetes CRDs (VirtualService, DestinationRule) | Kubernetes CRDs (Server, ServiceProfile) | AWS console / CloudFormation |
| **mTLS** | Manual (SDS + cert manager) | ✅ Built-in Consul Connect | ✅ Built-in (strict mode) | ✅ Built-in, automatic | ✅ Built-in |
| **Observability** | Full control via OTel | ✅ Built-in | ✅ Built-in (Prometheus, Jaeger, Kiali) | ✅ Built-in (Prometheus, Grafana) | ✅ (X-Ray, CloudWatch) |
| **Circuit breaking** | Full Envoy config | Limited | Full Envoy config | Limited (L4 only) | Full Envoy config |
| **Traffic management** | Full xDS (LDS/RDS/CDS/EDS) | Consul intentions + config | VirtualService, DestinationRule | ServiceProfile | AWS console routing |
| **Resource overhead per pod** | ~40MB / 10m CPU | ~40MB / 10m CPU | ~50MB / 15m CPU | **~10MB / 5m CPU** | ~40MB / 10m CPU |
| **Operational complexity** | **Highest** (you own everything) | Medium | High (Istiod, certificates, CRDs) | Low | Lowest (fully managed) |
| **Multi-cluster** | Manual | ✅ WAN federation | ✅ Multi-primary / primary-remote | ✅ Multi-cluster | ❌ AWS-only |
| **Non-K8s support** | ✅ via Consul | ✅ via Consul | ✅ VM mode | ❌ | ✅ ECS + EKS |
| **Best for** | Maximum control, custom requirements | HashiCorp ecosystem | Large K8s footprint, full feature set | Simplicity + minimal overhead | AWS-native, managed operations |

---

### Deep Trade-off: Build vs. Buy on the Control Plane

The architecture in this document builds the xDS control plane (Config Manager). Istio and Consul Connect ship a production-ready control plane. The build-vs-buy trade-off is explicit:

**Build your own (this document):**
- You control exactly what gets pushed to Envoy
- You can integrate any source of truth (Consul, K8s, AWS SSM, your own CMDB)
- Maintenance cost: your team owns the xDS code, schema migrations, Envoy version upgrades
- **Right when:** Existing service registry is not Consul or K8s, or you have non-standard routing requirements that the off-the-shelf control planes don't support

**Use Consul Connect / Istiod:**
- Consul Connect: battle-tested, production-grade xDS server maintained by HashiCorp. If you are already using Consul for service registry, this is the zero-marginal-effort control plane.
- Istiod: the most feature-complete option; the dominant choice for large Kubernetes deployments. Supports multi-cluster, VM workloads, advanced traffic policies. Steep learning curve.
- **Right when:** Standard requirements, no custom xDS needs, K8s-native, platform team available to own Istio

**Decision rule for FAANG interviews:** "If I have a Consul-based service registry and need a service mesh, I'd use Consul Connect to avoid building the xDS control plane from scratch. If I'm Kubernetes-native and the team has service mesh experience, Istio. If I want minimal resource overhead and simpler operations for a K8s fleet, Linkerd. If I'm on AWS and want zero operational overhead, App Mesh."

---

## Comprehensive Advantages and Disadvantages

### Advantages — Full Detail

**1. Zero application code changes**  
Teams ship their services as plain HTTP servers. All networking capabilities (mTLS, retries, circuit breaking, tracing) are added by the platform team via the proxy layer. This is the most powerful argument for the sidecar pattern: you get uniform reliability and observability across a heterogeneous fleet (Java, Go, Python, Node) with no coordination with 12 feature teams.

**2. Centralised policy enforcement**  
Without a sidecar: if you want all services to use QUORUM consistency, or retry 3 times on 503, you have to change 40 services. With a sidecar: change the Config Manager or Consul config entry once, push to all Envoy instances via xDS in seconds. This is the same advantage Kubernetes NetworkPolicy has over per-service firewall rules.

**3. Uniform, consistent observability**  
All 40 services emit the same metric names (`envoy_cluster_upstream_rq_total`, `envoy_http_downstream_rq_time_bucket`), the same trace format (OTLP, W3C traceparent), and the same access log structure. Building dashboards, SLO alerts, and latency heatmaps is dramatically simpler when the data model is identical across all services. Without a sidecar, each service may use a different tracing library, different metric names, different sampling rates.

**4. Gradual, reversible adoption**  
You can enable the sidecar one service at a time. You can start with observability-only and add mTLS later. You can shadow-route traffic (send 1% to a new version) via xDS without deploying a new load balancer rule. The proxy layer is a control surface that lets you change traffic behaviour without touching application code or redeploying services.

**5. Circuit breaking and outlier detection across the fleet**  
Envoy's outlier detection ejects an upstream endpoint after N consecutive gateway errors. Without a sidecar, each client service must implement its own circuit breaker (Resilience4j, Hystrix, go-circuitbreaker). With Envoy, the platform enforces consistent circuit breaking semantics everywhere. An unhealthy payment-service instance is ejected from all callers' load balancing pool simultaneously — not just from callers that happen to have Resilience4j configured correctly.

**6. mTLS as a default, not an opt-in**  
Once the mesh is in place, mTLS between all services can be made the default. Every service-to-service call is mutually authenticated (not just encrypted) — you know both who is calling and who is being called. This makes lateral movement after a pod compromise significantly harder. Without a sidecar, mTLS requires every service to manage certificates, trust stores, and rotation — in practice, it is rarely implemented consistently.

---

### Disadvantages — Full Detail

**1. Resource overhead — cumulative and non-trivial**  
Each Envoy sidecar at rest consumes approximately:
- CPU: 10m (0.01 cores) at idle, up to 100m under load
- Memory: 40–80MB per instance

At 100 pods: 1–10 additional CPU cores, 4–8 GB additional memory just for proxies. At 1,000 pods (large microservices fleet): 10–100 additional CPU cores, 40–80 GB memory. This is significant cloud cost. Linkerd's Rust proxy reduces this to ~10MB/instance.

**2. Added latency — non-negotiable at high hop counts**  
Each Envoy proxy adds ~0.1–0.5ms per hop:
- Single service call: +0.2–1ms (inbound + outbound proxy)
- A request spanning 5 services: +1–5ms added latency

For services with P99 SLO of 100ms: 1–5ms overhead is acceptable. For real-time systems (P99 < 10ms SLO): the overhead is measurable and potentially SLO-breaking. Measure before adopting in latency-sensitive paths.

**3. New failure modes introduced by the proxy**  
The proxy itself can fail, misconfigure, or become a bottleneck:
- Envoy circuit breaker triggers too aggressively → cascades a healthy service as "down"
- xDS configuration pushed incorrectly → routing loops, 503 flood
- Envoy OOM → all traffic through that pod drops
- iptables misconfiguration → traffic bypass (security hole)

Each of these is a new category of incident that didn't exist before the sidecar. The platform team must own the oncall rotation for proxy failures — a commitment not to be underestimated.

**4. Debugging complexity increases at every layer**  
When a request fails, the debugging path now includes:
1. App logs (did the app receive the request?)
2. Envoy access logs (did Envoy route it correctly?)
3. Envoy admin (`/clusters` — is the upstream healthy? `/listeners` — is the listener configured?)
4. Config Manager logs (was the correct xDS config pushed?)
5. Consul health (are the upstream instances registered and healthy?)

Engineers unfamiliar with the mesh will struggle to locate the failure. This requires investment in: Envoy-specific runbooks, training, and tooling (e.g., `istioctl analyze`, `consul debug`).

**5. Control plane is a single point of coordination failure**  
If the Config Manager + Consul both become unreachable simultaneously (worst case), Envoy instances continue running with cached configuration but cannot be updated. A new deployment (new pod, new endpoint) will not be discovered by existing Envoy instances until the control plane recovers. This is "control plane degraded, data plane working" — a known and acceptable failure mode for Envoy, but it means your service discovery is frozen for the outage duration.

**6. Sidecar version management across a large fleet**  
Keeping Envoy versions consistent across 100+ pods requires a coordinated rollout strategy. Envoy has a rapid release cycle (~6 weeks). Each upgrade must be tested (API compatibility, configuration schema changes) and rolled out via a canary deployment of the sidecar DaemonSet or image update. This is a non-trivial operational burden.

---

## When NOT to Use This Pattern

| Scenario | Reason |
|----------|--------|
| < 5 services, single team | Operational overhead exceeds the benefit |
| < 10ms latency SLO (P99) | Proxy hop latency (~0.1–0.5ms per hop) may violate SLO |
| Serverless / AWS Lambda | No persistent container to attach a sidecar to |
| Team has no platform engineering capacity | 3 new systems to operate without dedicated ownership will rot |
| Batch processing workloads | Service-to-service networking is not the bottleneck; observability can be cheaper via OTel SDK |
| High pod density, resource-constrained nodes | 40MB × 500 pods = 20GB memory for proxies alone; consider Linkerd or node-level proxy instead |
| Already using a managed mesh (Istio, App Mesh) | Don't build a custom control plane when a supported one already exists |

---

## FAANG Interview Framing

**Q: How would you implement distributed tracing across 40 microservices without modifying each service?**

> "The sidecar pattern via Envoy. Every service gets an Envoy proxy injected as a sidecar — in Kubernetes via a MutatingWebhookAdmissionController, in ECS via task definition injection. Envoy generates trace spans for every inbound and outbound request using the W3C traceparent header for propagation. The spans are exported to an OTel Collector via OTLP. The Collector applies tail-based sampling — keeps 100% of error traces, 5% of success traces — and exports to Grafana Tempo. The application code changes: zero. The engineer adding a new service gets distributed tracing automatically, from day one, just by deploying their container with the `sidecar.mesh/inject: true` annotation."

**Q: How does service discovery work in a dynamic microservices environment?**

> "Consul as the service registry. Each service registers on startup with its IP, port, and health check endpoint. Consul runs the health check every 10 seconds; instances that fail are deregistered. A Config Manager watches Consul via the blocking query API — when instances change, it pushes updated EDS (Endpoint Discovery Service) config to all Envoy proxies via xDS gRPC. Envoy refreshes its upstream endpoints without restart. The application code doesn't do DNS lookups or maintain client-side registries — it just calls `http://payment-service/api` and Envoy resolves the current healthy instances, applies the configured load balancing policy, and routes accordingly."

**Q: What happens if the Config Manager (control plane) goes down?**

> "Envoy is deliberately designed so that the data plane survives control plane failures. Each Envoy instance caches the last configuration it received. If the Config Manager is unreachable, Envoy continues serving traffic with that cached config — no new endpoint changes, no new routing rules, but existing traffic continues. This is Envoy's most important resilience property. The consequence: you can't push new config until the control plane recovers — so a Consul service registration change (new instance deployed) won't reach Envoy until Config Manager is back. For short outages (minutes), the stale endpoint list is usually acceptable. For long outages, the load balancer's outlier detection will still eject unhealthy endpoints proactively based on response codes."
