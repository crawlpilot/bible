# Network Components Deep Dive

**Domain:** Distributed Systems · Networking · Infrastructure  
**Interview context:** "What's the difference between an L4 and L7 load balancer?" / "When would you use a reverse proxy vs a load balancer?" / "Design the ingress layer for a high-traffic system." / "How does Nginx differ from Envoy?"

---

## The OSI Model — Why It Matters Here

Every network component in this document operates at a specific layer. The layer determines what information the component can inspect and act on.

```
Layer 7  │  Application   │  HTTP, gRPC, WebSocket, DNS
Layer 6  │  Presentation  │  TLS/SSL encryption, encoding
Layer 5  │  Session       │  TLS session, connection state
Layer 4  │  Transport     │  TCP, UDP — ports, segments
Layer 3  │  Network       │  IP — packets, routing
Layer 2  │  Data Link     │  Ethernet — frames, MAC addresses
Layer 1  │  Physical      │  Cables, signals
```

**The rule:** A component operating at layer N can read and act on headers from layers 1 through N. A layer 4 load balancer sees IP addresses and TCP ports. A layer 7 load balancer sees HTTP headers, URL paths, cookies, and request bodies.

Higher layer = more routing intelligence + more CPU cost + more latency.

---

## Taxonomy: Every Component at a Glance

```
Client
  │
  ▼
┌─────────────────────────────────────────────────────────────────┐
│  Forward Proxy (client-side, optional)                          │
│  "Client tells proxy where to go"                               │
│  Use: corporate egress, anonymisation, caching outbound         │
└─────────────────────────────────────────────────────────────────┘
  │
  │  (internet)
  │
  ▼
┌─────────────────────────────────────────────────────────────────┐
│  DNS Load Balancer (GSLB / Route 53 / Cloudflare)              │
│  "Directs client to nearest/healthiest datacenter"              │
│  Layer: 3/4 (DNS resolution) — no packet inspection            │
└─────────────────────────────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────────────────────────────┐
│  L4 Load Balancer / NLB                                         │
│  "TCP/UDP routing by IP + port"                                 │
│  Layer: 4 — sees IP, port, protocol. Blind to HTTP content      │
│  Example: AWS NLB, HAProxy TCP mode, IPVS                       │
└─────────────────────────────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────────────────────────────┐
│  L7 Load Balancer / Reverse Proxy                               │
│  "HTTP routing by path, header, host, cookie"                   │
│  Layer: 7 — full HTTP inspection, TLS termination               │
│  Example: AWS ALB, Nginx, HAProxy HTTP mode, Envoy              │
└─────────────────────────────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────────────────────────────┐
│  Backend Services                                               │
└─────────────────────────────────────────────────────────────────┘
```

---

## Section 1: Forward Proxy

### What It Is

A forward proxy sits **in front of clients**. The client explicitly configures it. The proxy makes requests on behalf of the client — the destination server sees the proxy's IP, not the client's.

```
Client ──► Forward Proxy ──► Internet ──► Destination Server
           (knows client's            (sees proxy IP,
            destination)               not client IP)
```

### How It Works

1. Client sends request to proxy: `CONNECT api.example.com:443 HTTP/1.1`
2. Proxy connects to destination on client's behalf
3. For HTTPS: proxy establishes tunnel (CONNECT method) — cannot inspect encrypted payload unless doing SSL inspection
4. Proxy returns response to client

### Use Cases

| Use case | How forward proxy helps |
|----------|------------------------|
| **Corporate egress control** | Force all employee traffic through proxy; log, filter, block |
| **Anonymisation / VPN** | Client's real IP hidden from destination |
| **Outbound caching** | Cache popular responses (npm registry, Docker Hub) to save bandwidth |
| **Geo-restriction bypass** | Proxy in another region circumvents geo blocks |
| **Security scanning** | Inspect outbound traffic for data exfiltration, malware |

### Characteristics

- Client **must be configured** to use the proxy (explicit proxy awareness)
- Can cache, log, and filter outbound requests
- Cannot inspect HTTPS unless doing active SSL interception (MITM)
- Transparent forward proxy: can intercept without client config via iptables redirect

### Examples

- **Squid** — open source, widely deployed in corporate networks
- **Charles / mitmproxy** — developer tools for HTTPS inspection
- **Corporate SSE / Zscaler** — cloud-native forward proxy
- **Privoxy** — privacy-focused forward proxy

---

## Section 2: Reverse Proxy

### What It Is

A reverse proxy sits **in front of servers**. Clients talk to the proxy, not knowing which backend server will handle their request. The client sees one address; the proxy distributes to many backends.

```
Client ──► Reverse Proxy ──► Backend Server A
                    └──────► Backend Server B
                    └──────► Backend Server C
           (client sees proxy IP; backends see proxy IP, not client)
```

### What It Does

A reverse proxy can do any or all of:
- **Load balancing** — distribute requests across backend instances
- **TLS termination** — decrypt HTTPS at the proxy; backends receive plain HTTP
- **Caching** — cache backend responses (Nginx content caching)
- **Compression** — gzip response bodies before sending to client
- **Authentication** — validate JWTs/API keys before forwarding to backend
- **Rate limiting** — enforce per-client request limits
- **URL rewriting** — rewrite paths before forwarding (`/api/v1` → `/v1`)
- **Health checking** — detect unhealthy backends and remove from rotation

### The Critical Distinction: Forward vs Reverse

| Dimension | Forward Proxy | Reverse Proxy |
|-----------|--------------|---------------|
| Sits in front of | Clients | Servers |
| Client awareness | Client must be configured | Client unaware — calls proxy directly |
| Server awareness | Destination server sees proxy | Backend server sees proxy, not client |
| Who benefits | Client (privacy, filtering) | Server owner (LB, TLS offload, security) |
| Example | Corporate web filter | Nginx in front of your API |

---

## Section 3: L4 Load Balancer (NLB)

### What It Is

An L4 load balancer routes traffic based on **IP address, TCP/UDP port, and protocol**. It has no visibility into the application layer — it cannot read HTTP headers, URLs, or cookies.

```
Incoming packet:
  src: 203.0.113.5:45123
  dst: 10.0.0.1:443
  protocol: TCP

L4 LB decision: "forward to backend:443 based on consistent hash of src IP"
                ← that's all it knows
```

### How It Works: Two Models

**Model 1: NAT (Network Address Translation)**
- L4 LB rewrites destination IP/port on every packet
- Every packet passes through the LB (full traffic volume)
- AWS Classic Load Balancer, IPVS in NAT mode

**Model 2: DSR (Direct Server Return)**
- LB forwards packets to backend
- Backend sends response **directly to client**, bypassing the LB
- LB only handles inbound traffic
- Much higher throughput — LB isn't a bottleneck for response traffic
- AWS NLB uses DSR by default

```
DSR flow:
Client → NLB (forward packet, rewrite MAC) → Backend
                                              Backend → Client (direct)
```

### AWS NLB Specifics

- **Layer 4** — TCP, UDP, TLS pass-through
- **Preserves client IP** — backends see real client IP (no x-forwarded-for needed)
- **Ultra-low latency** — ~100μs, vs ALB's ~1ms
- **TLS pass-through** — can forward encrypted TCP without terminating (backend terminates)
- **TLS termination** — can also terminate TLS at NLB level
- **Static IP** — each AZ gets a dedicated Elastic IP (useful for IP whitelisting by clients)
- **Handles millions of req/s** — no connection limits

### When to Use L4

| Use case | Why L4 |
|----------|--------|
| Non-HTTP protocols (MQTT, gRPC, raw TCP) | L7 can't parse non-HTTP |
| When client IP preservation is critical | L4 preserves source IP natively |
| Extreme throughput (millions of req/s) | L4 is cheaper per-packet than L7 |
| TLS pass-through (backend decrypts) | L4 forwards without decrypting |
| In front of an L7 load balancer | L4 as first tier, L7 as second tier |
| Gaming / real-time UDP | L7 load balancers typically don't handle UDP |

### L4 Limitations

- Cannot route by HTTP path, method, or header
- Cannot insert x-forwarded-for (it doesn't know HTTP)
- Cannot do HTTP health checks (only TCP connect checks)
- Cannot do content-based routing or A/B testing
- Sessions are sticky by IP only (coarse-grained)

---

## Section 4: L7 Load Balancer

### What It Is

An L7 load balancer (also called application load balancer) operates at the HTTP layer. It **terminates the TCP+TLS connection**, reads the full HTTP request, makes a routing decision based on application-level content, and opens a new TCP connection to the backend.

```
Client ──TCP+TLS──► L7 LB ──HTTP──► Backend A
                   ↑
                   Reads: Host, URL path, headers, cookies
                   Decides: which backend, which version
```

### What L7 Can Do That L4 Cannot

| Capability | L4 | L7 |
|-----------|----|----|
| Route by URL path | ❌ | ✅ `/api` → service A, `/web` → service B |
| Route by HTTP method | ❌ | ✅ GET → read replicas, POST → primaries |
| Route by HTTP header | ❌ | ✅ `X-Version: v2` → canary cluster |
| Route by cookie | ❌ | ✅ session affinity by cookie value |
| Route by hostname | ❌ | ✅ `api.example.com` vs `web.example.com` |
| HTTP health checks | ❌ | ✅ GET /health → expect 200 |
| Retry on 5xx | ❌ | ✅ retry the request on 502/503 |
| Rate limiting by user | ❌ | ✅ rate limit by API key in header |
| WebSocket upgrade | Manual | ✅ |
| gRPC routing | ❌ | ✅ route by gRPC method |
| Insert x-forwarded-for | ❌ | ✅ |
| A/B testing / canary | ❌ | ✅ |

### AWS ALB Specifics

- **Layer 7** — HTTP/1.1, HTTP/2, gRPC, WebSocket
- **Terminates TLS** — certificate managed in ACM
- **Rule-based routing** — path, host, header, query string conditions
- **Target groups** — EC2 instances, ECS tasks, Lambda functions, IP addresses
- **Sticky sessions** — via ALB-generated cookie (AWSALB) or application cookie
- **WAF integration** — attach AWS WAF rules to filter malicious requests
- **Access logs** — every request logged to S3 with full HTTP details

### L7 Routing Rules Example (AWS ALB)

```
Priority 1: Host: api.example.com, Path: /v2/*   → target-group: api-v2-canary (10% weight)
Priority 2: Host: api.example.com, Path: /v2/*   → target-group: api-v2-stable (90% weight)
Priority 3: Host: api.example.com, Path: /admin* → target-group: admin-service
Priority 4: Host: api.example.com                → target-group: api-service-default
Priority 5: Host: web.example.com                → target-group: frontend-service
Default:                                         → 404 Fixed Response
```

---

## Section 5: L4 vs L7 — Decision Framework

```
Is the protocol HTTP/gRPC/WebSocket?
    │
    No ──► Use L4 (NLB). L7 can't parse it.
    │
    Yes
    │
    Do you need content-based routing (path/header/host)?
    │
    No ──► Do you need extreme throughput (>1M req/s) or sub-ms latency?
    │          │
    │          Yes ──► L4 (NLB)
    │          No  ──► Either works; L7 gives more observability
    │
    Yes ──► Use L7 (ALB / Nginx / Envoy)
```

**Classic two-tier architecture:**

```
Internet ──► NLB (L4) ──► ALB (L7) ──► Backend services
             Static IP     Content-based routing
             DDoS buffer   TLS termination, WAF
```

NLB provides the static Elastic IP that clients and firewalls use for whitelisting. ALB sits behind NLB and handles HTTP routing. This gives you both static IPs (L4) and content routing (L7).

---

## Section 6: Nginx

### What It Is

Nginx is a **high-performance HTTP server, reverse proxy, and L7 load balancer** — originally built to solve the C10K problem (10,000 concurrent connections on a single server, which Apache struggled with).

### Architecture: Event-Driven, Non-Blocking

```
Nginx worker process (one per CPU core):
  Single thread
  Event loop (epoll/kqueue)
  Handles thousands of connections concurrently
  No thread-per-connection overhead
```

Apache used one thread/process per connection — at 1000 concurrent connections, you had 1000 threads, each burning stack memory. Nginx uses one worker per CPU core, each running an event loop, handling thousands of connections with minimal memory.

### Core Capabilities

**1. Reverse proxy + load balancing**

```nginx
# nginx.conf
upstream backend_pool {
    least_conn;                           # LB algorithm: least connections
    server backend1.internal:8080 weight=5;
    server backend2.internal:8080 weight=3;
    server backend3.internal:8080 backup; # only if others fail

    keepalive 32;                         # connection pool to backends
}

server {
    listen 443 ssl;
    server_name api.example.com;

    ssl_certificate     /etc/ssl/api.crt;
    ssl_certificate_key /etc/ssl/api.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    location /api/ {
        proxy_pass http://backend_pool;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_connect_timeout 5s;
        proxy_read_timeout 60s;
    }

    location /static/ {
        root /var/www;
        expires 30d;                      # serve static files directly
        add_header Cache-Control "public";
    }
}
```

**2. Load balancing algorithms**

| Algorithm | Config | Best for |
|-----------|--------|----------|
| Round robin | (default) | Homogeneous backends, equal request cost |
| Least connections | `least_conn` | Variable request durations |
| IP hash | `ip_hash` | Session stickiness by client IP |
| Hash (custom key) | `hash $cookie_id` | Session stickiness by cookie/URI |
| Random with least conn | `random two least_conn` | Very large backend pools |

**3. Content caching**

```nginx
proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=api_cache:10m
                 max_size=1g inactive=60m use_temp_path=off;

location /api/products {
    proxy_cache api_cache;
    proxy_cache_valid 200 5m;            # cache 200 responses for 5 minutes
    proxy_cache_key "$scheme$host$uri$is_args$args";
    proxy_cache_bypass $http_cache_control;  # honour Cache-Control: no-cache
    add_header X-Cache-Status $upstream_cache_status;
}
```

**4. Rate limiting**

```nginx
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=100r/s;

location /api/ {
    limit_req zone=api_limit burst=200 nodelay;
    limit_req_status 429;
    # 100 req/s allowed; burst of 200 without queuing; 429 on overflow
}
```

### Nginx Strengths

- **Static file serving** — serves files directly from disk without proxying; 10× faster than proxying through an app
- **SSL termination** — mature, battle-tested TLS stack
- **Content caching** — powerful cache with TTL, bypass, and purge controls
- **Rate limiting** — built-in leaky bucket with burst support
- **HTTP/2 + gzip** — enabled with single config directives
- **Broad ecosystem** — Nginx Plus, OpenResty (Lua scripting), ModSecurity WAF
- **Very low resource usage** — runs on 512MB RAM for thousands of connections

### Nginx Limitations

- **Static configuration** — changes require reload (graceful, but still a process signal)
- **No dynamic service discovery** — upstreams must be defined in config; DNS-based discovery is approximate
- **No native distributed tracing** — observability requires third-party modules
- **No circuit breaker** — passive health checking (removes backends on errors) but no proactive circuit breaking
- **Limited gRPC routing** — gRPC over HTTP/2 is supported but routing is less mature than HTTP/1.1

---

## Section 7: HAProxy

### What It Is

HAProxy is a **high-availability proxy** designed specifically for load balancing TCP and HTTP traffic. It is arguably the most reliable, deterministic load balancer available — trusted by GitHub, Twitter, Reddit, Stack Overflow.

### Key Differentiator: Reliability and Predictability

HAProxy's design philosophy: do one thing (proxying) and do it perfectly. No web server, no scripting engine, no filesystem access. Every CPU cycle is for proxying.

```
HAProxy at GitHub: ~2 million connections, 100 Gbps throughput, single process
HAProxy at Stack Overflow: primary LB for all traffic for years
```

### Architecture

HAProxy has two modes:

**TCP mode (L4):**
```
frontend tcp_in
    bind *:9000
    mode tcp
    default_backend tcp_servers

backend tcp_servers
    mode tcp
    balance roundrobin
    server s1 10.0.0.1:9000 check
    server s2 10.0.0.2:9000 check
```

**HTTP mode (L7):**
```
frontend http_in
    bind *:80
    bind *:443 ssl crt /etc/haproxy/ssl/cert.pem
    mode http
    option httplog
    option forwardfor                    # inject X-Forwarded-For

    # ACL-based routing
    acl is_api path_beg /api
    acl is_websocket hdr(Upgrade) -i websocket

    use_backend api_servers   if is_api
    use_backend ws_servers    if is_websocket
    default_backend web_servers

backend api_servers
    mode http
    balance leastconn
    option httpchk GET /health HTTP/1.1\r\nHost:\ api
    server api1 10.0.1.1:8080 check
    server api2 10.0.1.2:8080 check
    server api3 10.0.1.3:8080 check backup

backend web_servers
    mode http
    balance roundrobin
    cookie SERVERID insert indirect nocache  # sticky sessions by cookie
    server web1 10.0.2.1:80 check cookie web1
    server web2 10.0.2.2:80 check cookie web2
```

### HAProxy Strengths

- **TCP + HTTP in one binary** — L4 and L7 in a single, well-tested tool
- **Extremely stable** — HAProxy 1.5 (2014) configs still run on HAProxy 2.8; no breaking changes
- **ACL system** — powerful rule engine for routing (path, header, source IP, SSL SNI, method)
- **Stats page** — built-in real-time web dashboard at `/haproxy_stats`
- **Runtime API** — drain/add servers without restart: `echo "disable server backend/s1" | nc /run/haproxy.sock`
- **Consistent hashing** — stateful session routing by cookie, source IP, or custom URI hash
- **Health checks** — TCP, HTTP, and custom script-based health checks

### HAProxy Runtime API (Zero-Downtime Operations)

```bash
# Drain a server (no new connections, existing ones complete)
echo "set server api_servers/api1 state drain" | nc -U /run/haproxy.sock

# Re-enable
echo "set server api_servers/api1 state ready" | nc -U /run/haproxy.sock

# Change backend weight live
echo "set server api_servers/api2 weight 50" | nc -U /run/haproxy.sock

# View current stats
echo "show stat" | nc -U /run/haproxy.sock | cut -d',' -f1,2,18,19
```

### HAProxy Limitations

- **No built-in service discovery** — upstreams are static config (or require Consul Template / Dataplane API)
- **No native distributed tracing** — no OTLP export; requires third-party
- **No WASM / Lua** — less extensible than Nginx (OpenResty) or Envoy
- **Configuration verbosity** — complex routing rules become very long config files
- **No circuit breaker** — removes failed backends but no half-open / recovery pattern

---

## Section 8: Envoy

### What It Is

Envoy is a **modern L7 proxy designed for cloud-native microservices** — built by Lyft, donated to CNCF, now the data plane for Istio and AWS App Mesh. Unlike Nginx and HAProxy which were designed as standalone proxies, Envoy was designed to be **programmatically controlled** via its xDS API.

### The Core Differentiator: Dynamic Configuration

```
Nginx/HAProxy:                      Envoy:
Config file → reload signal         xDS API (gRPC) → live config push
                                    Zero restart, zero dropped connections
```

This is why Envoy is the choice for service meshes: thousands of sidecar Envoy instances need to receive new routing rules simultaneously when services are deployed. You can't reload 1,000 processes every time a pod scales.

### Envoy Architecture

```
┌─────────────────────────────────────────────────────┐
│  Envoy Process                                      │
│                                                     │
│  Downstream                                         │
│  ┌─────────────────────────────────────────────┐   │
│  │  Listeners                                  │   │
│  │  (LDS: port, protocol, filter chain)        │   │
│  └───────────────────┬─────────────────────────┘   │
│                      │ matched by filter chain      │
│  ┌───────────────────▼─────────────────────────┐   │
│  │  Filters                                    │   │
│  │  - HTTP Connection Manager                  │   │
│  │  - TLS inspector                            │   │
│  │  - Rate limit filter                        │   │
│  │  - JWT auth filter                          │   │
│  │  - gRPC-JSON transcoding                    │   │
│  └───────────────────┬─────────────────────────┘   │
│                      │ routed by RDS rules          │
│  ┌───────────────────▼─────────────────────────┐   │
│  │  Clusters (CDS)                             │   │
│  │  (upstream service definitions)             │   │
│  │  - LB policy: round robin / least req / hash│   │
│  │  - Circuit breaker thresholds               │   │
│  │  - Outlier detection                        │   │
│  └───────────────────┬─────────────────────────┘   │
│                      │ resolved by EDS              │
│  ┌───────────────────▼─────────────────────────┐   │
│  │  Endpoints (EDS)                            │   │
│  │  (actual IP:port instances)                 │   │
│  └─────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

### Key Envoy Capabilities

**1. Traffic management**
```yaml
# Header-based routing (canary by version header)
routes:
  - match:
      prefix: "/api/"
      headers:
        - name: "x-version"
          string_match:
            exact: "v2"
    route:
      cluster: api-v2-canary
      
  - match:
      prefix: "/api/"
    route:
      weighted_clusters:
        clusters:
          - name: api-v2
            weight: 90
          - name: api-v1
            weight: 10
```

**2. Circuit breaking (built-in)**
```yaml
circuit_breakers:
  thresholds:
    - priority: DEFAULT
      max_connections: 100
      max_pending_requests: 50
      max_requests: 200
      max_retries: 3

outlier_detection:
  consecutive_gateway_failure: 5
  base_ejection_time: 30s
  max_ejection_percent: 50   # never eject more than 50% of instances
```

**3. Retry policy**
```yaml
retry_policy:
  retry_on: "5xx,connect-failure,retriable-4xx"
  num_retries: 3
  per_try_timeout: 5s
  retry_back_off:
    base_interval: 100ms
    max_interval: 2s
```

**4. Distributed tracing (native OTLP)**
```yaml
tracing:
  provider:
    name: envoy.tracers.opentelemetry
    typed_config:
      grpc_service:
        envoy_grpc:
          cluster_name: otel_collector
      service_name: my-service
```

**5. WASM extensions**
Custom filters written in any WASM-compatible language (Rust, Go, C++) loaded at runtime — no Envoy recompile needed.

### Envoy Strengths

- **Dynamic config (xDS)** — live updates without restart; essential for service mesh
- **Native observability** — OTLP traces, Prometheus metrics, structured access logs built in
- **Circuit breaking + outlier detection** — first-class, not a plugin
- **gRPC-first** — HTTP/2 and gRPC treated as first-class protocols
- **WASM extensibility** — custom filters without forking
- **First-class service mesh data plane** — Istio, AWS App Mesh, Consul Connect all use Envoy
- **mTLS** — first-class support for mutual TLS between services (via SDS)

### Envoy Limitations

- **Complexity** — xDS config is verbose; YAML/JSON bootstrap is intricate
- **Operational expertise** — debugging Envoy (filter chains, xDS rejections, cluster health) requires deep knowledge
- **Memory footprint** — ~30–60MB per sidecar at idle (more than Nginx/HAProxy)
- **Not a web server** — no static file serving, no content caching
- **Control plane required** — full dynamic operation requires a working xDS server (Consul, Istio, custom)

---

## Section 9: Nginx vs HAProxy vs Envoy — Decision Matrix

| Dimension | Nginx | HAProxy | Envoy |
|-----------|-------|---------|-------|
| **Primary use case** | Web server + reverse proxy | Pure load balancing | Service mesh sidecar + API gateway |
| **L4 (TCP)** | Limited | ✅ Excellent | ✅ Good |
| **L7 (HTTP)** | ✅ Excellent | ✅ Excellent | ✅ Excellent |
| **gRPC routing** | Limited | Limited | ✅ First-class |
| **Dynamic config (no reload)** | ❌ (NJS workaround) | ✅ Runtime API | ✅ xDS (full live reload) |
| **Service discovery integration** | DNS only | DNS / Consul Template | ✅ Native xDS (Consul, Istio) |
| **Distributed tracing** | Plugin required | Plugin required | ✅ Native OTLP |
| **Circuit breaker** | ❌ | ❌ | ✅ Native |
| **Circuit breaker + outlier detection** | ❌ | ❌ | ✅ Native |
| **Static file serving** | ✅ Best-in-class | ❌ | ❌ |
| **Content caching** | ✅ Excellent | ❌ | ❌ |
| **Rate limiting** | ✅ Built-in | Via Lua | ✅ Native filter |
| **WAF / security** | ModSecurity | Limited | Via WASM |
| **Memory per instance** | ~5MB | ~10MB | ~40MB |
| **Config complexity** | Low | Medium | High |
| **Ecosystem maturity** | Very mature (20yr) | Very mature (20yr) | Newer (8yr), rapidly growing |
| **Best in production for** | Edge proxy, web apps, API GW | Database LB, TCP LB, stable HTTP LB | Service mesh, dynamic microservices |

### When to Use Each

| Use Nginx when... | Use HAProxy when... | Use Envoy when... |
|-------------------|--------------------|--------------------|
| Serving static files + proxying | Need rock-solid L4 + L7 in one tool | Running a service mesh |
| Need content caching at the proxy | Database connection pooling / LB | Need dynamic config without restarts |
| API gateway for external traffic | Long-term stability is paramount | Building a sidecar proxy |
| OpenResty Lua scripting | Large number of backends (ACL routing) | gRPC-heavy microservices |
| Familiar team, low operational overhead | HAProxy's runtime API for zero-downtime ops | Need native circuit breaking + tracing |

---

## Section 10: DNS Load Balancing / GSLB

### What It Is

DNS load balancing distributes traffic before it even reaches your infrastructure, at the DNS resolution level. Clients get different IP addresses depending on geography, health, or weight.

```
Client in US-East  ──► DNS query ──► Route 53 ──► 1.2.3.4 (US-East AZ)
Client in EU-West  ──► DNS query ──► Route 53 ──► 5.6.7.8 (EU-West AZ)
```

### AWS Route 53 Routing Policies

| Policy | How it routes | Use case |
|--------|--------------|----------|
| **Simple** | Single IP or round-robin if multiple | Single endpoint |
| **Weighted** | 90% to v1, 10% to v2 | Canary deploys |
| **Latency-based** | Route to the region with lowest latency to the client | Global apps |
| **Geolocation** | Route by client's country/continent | Data sovereignty, content localisation |
| **Geoproximity** | Route by distance, with traffic bias knobs | Fine-grained geo routing |
| **Failover** | Active-passive: route to secondary if primary health check fails | DR |
| **Multi-value answer** | Return up to 8 healthy IPs; client picks one | Simple L3 LB without dedicated LB |

### DNS Load Balancing Limitations

- **TTL lag** — clients cache DNS responses. With TTL=60s, all clients take up to 60s to see a new IP after failover
- **No connection-level load balancing** — a client that resolved one IP keeps using it until TTL expires
- **No SSL termination** — DNS only resolves names to IPs
- **Sticky by design** — the client keeps the resolved IP for the TTL duration
- **Health check granularity** — Route 53 health checks are coarser than ALB target health checks

**Best use:** global traffic distribution between datacenters/regions, as the first tier before regional load balancers.

---

## Section 11: Service Mesh Load Balancing (East-West)

Everything above is about **North-South** traffic: client → your system. In microservices, **East-West** traffic (service → service) is often 10–100× larger in volume.

Service mesh load balancing happens at the sidecar (Envoy) level, inside the cluster:

```
Order Service                 Payment Service
  │                              │
  │ Envoy sidecar                │ Envoy sidecar
  │                              │
  └── HTTP/gRPC ──────────────── ┘
        (mTLS, L7 routing,
         circuit break, retry,
         tracing — all from Envoy)
```

The key difference from external load balancers:

| External LB (North-South) | Service Mesh LB (East-West) |
|--------------------------|----------------------------|
| Centralised (one LB) | Distributed (sidecar per service) |
| Operated by infra team | Controlled by platform team via control plane |
| Services call load balancer | Services call each other; sidecar intercepts |
| No app code change | No app code change |
| Coarser health checking | Per-instance health (outlier detection) |

---

## Architecture Patterns for FAANG Interviews

### Pattern 1: Classic Three-Tier with DNS + NLB + ALB

```
Client
  │ DNS resolution (Route 53 latency-based → nearest region)
  ▼
NLB (L4)
  - Static Elastic IP per AZ
  - TLS pass-through
  - Ultra-low latency first hop
  │
  ▼
ALB (L7)
  - TLS termination (ACM certificate)
  - Path/host routing
  - WAF rules
  - Target groups per service
  │
  ▼
ECS / EKS Services
```

### Pattern 2: Service Mesh (East-West) + Ingress (North-South)

```
Internet
  │
  ▼
Ingress Controller (Nginx/Envoy/AWS ALB Ingress)
  - North-South: external → cluster
  - TLS termination, auth, rate limit
  │
  ▼
Kubernetes Services (ClusterIP)
  - East-West: pod → pod
  - Envoy sidecars handle mTLS, retry, circuit break, tracing
  │
  ▼
Pods (app container + Envoy sidecar)
```

### Pattern 3: API Gateway + Internal Mesh

```
Client
  │
  ▼
API Gateway (Kong / AWS API GW / Nginx)
  - Auth (JWT validation)
  - Rate limiting (per API key)
  - Protocol translation (REST → gRPC)
  - Request/response transformation
  │
  ▼
Internal service mesh (Envoy sidecars)
  - mTLS between all services
  - Per-service circuit breakers
  - Distributed tracing
  │
  ▼
Microservices
```

---

## Interview Quick-Reference

**Q: An L4 vs L7 load balancer — when do you use each?**
> "L4 for non-HTTP protocols, extreme throughput, or when you need client IP preservation without x-forwarded-for — it's cheaper per packet and lower latency. L7 when you need content-based routing (path, header, cookie), HTTP health checks, TLS termination, or application-layer features like retries and rate limiting. In practice I often use both: NLB at the edge for static IPs, ALB behind it for HTTP routing."

**Q: What's the difference between Nginx and Envoy?**
> "Nginx is a mature, battle-tested web server and reverse proxy with excellent static file serving, content caching, and a simple config model. Envoy is designed for dynamic microservice environments — its xDS API allows live configuration updates without restarts, it has native circuit breaking and distributed tracing, and it's the data plane used in every major service mesh. Use Nginx for edge proxying, API gateways, and content serving. Use Envoy as a sidecar proxy in a service mesh or when you need dynamic configuration, native circuit breaking, and per-request observability without modifying application code."

**Q: Why does a service mesh use L7 load balancing instead of DNS or L4?**
> "DNS load balancing is coarse — the client caches the resolved IP and keeps hitting the same instance for the TTL duration, so you can't do fine-grained load distribution or quickly remove a bad instance. L4 is port-and-IP level — it can't route by gRPC method or do per-request retries. L7 service mesh load balancing in the sidecar operates at the request level: every gRPC call or HTTP request is an independent routing decision, with outlier detection that ejects instances after 5 consecutive failures, and retry policies that replay failed requests transparently. This is far more reliable for microservices than either DNS or L4."
