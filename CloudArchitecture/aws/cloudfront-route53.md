# AWS CloudFront & Route 53 — Deep Dive

## Overview

**CloudFront** is AWS's global CDN — a network of 600+ edge locations (Points of Presence) that cache content close to users, reducing origin load and latency.

**Route 53** is AWS's authoritative DNS service with health-checking, traffic routing policies, and private DNS for VPCs.

These two services almost always appear together in global system designs: Route 53 directs traffic, CloudFront delivers it fast.

---

## CloudFront Architecture

### Core Components

```
User → DNS lookup (Route 53) → nearest Edge Location
     → CloudFront Edge (cache hit?) → serve content
                                    → cache miss → Origin Shield → Origin (S3/ALB/API GW)
```

| Component | Role |
|-----------|------|
| **Distribution** | Configuration unit — one domain, N origins, N cache behaviors |
| **Edge Location** | 600+ globally; serves cached content |
| **Regional Edge Cache** | ~15 regions; sits between edges and origin; larger cache |
| **Origin Shield** | Optional: one central region collapses cache misses before hitting origin |
| **Origin** | S3 bucket, ALB, NLB, API Gateway, EC2, on-prem |

### Request Flow (Cache Miss with Origin Shield)

```
User in Tokyo
→ Tokyo Edge (miss)
→ Asia-Pacific Regional Edge Cache (miss)
→ Origin Shield: us-east-1 (miss)
→ Origin: ALB in us-east-1
→ Response cached at Origin Shield → Regional Edge Cache → Tokyo Edge
```

Next user in Seoul: Tokyo Edge miss → Regional Edge Cache hit. Tokyo user (same path): Edge cache hit.

**Origin Shield impact:** Reduces origin requests by 73% on average (AWS data) for global traffic.

---

## Cache Behaviors

A distribution can have multiple cache behaviors matched by path pattern:

```
/*.jpg        → Origin: S3 (long TTL: 1 year, immutable assets)
/api/*        → Origin: ALB (TTL: 0, no caching, pass-through)
/             → Origin: S3 (short TTL: 60s, HTML files)
```

### TTL Configuration
| Header | Behavior |
|--------|----------|
| `Cache-Control: max-age=86400` | CloudFront caches for 86,400s |
| `Cache-Control: no-store` | CloudFront does not cache |
| `Cache-Control: s-maxage=3600` | CDN-specific TTL (overrides max-age for CloudFront) |
| No header | CloudFront uses distribution default TTL (24h) |

**Invalidation:** `aws cloudfront create-invalidation --paths "/*"` — costs $0.005/path after 1,000/month. Better: use versioned file names (`main.v3.js`) to avoid invalidation entirely.

---

## Functions at the Edge

### CloudFront Functions vs Lambda@Edge

| Feature | CloudFront Functions | Lambda@Edge |
|---------|---------------------|-------------|
| Execution location | Edge (600+ PoPs) | Regional Edge Cache (~15 regions) |
| Max duration | 1ms | 5s (viewer) / 30s (origin) |
| Max memory | 2 MB | 128 MB – 10,240 MB |
| Access to network | No | Yes |
| Access to request body | No (viewer) | Yes (origin request/response) |
| Pricing | $0.10/million | $0.60/million |
| Use cases | URL rewrites, header manipulation, redirects, simple auth | A/B testing, auth with network calls, origin selection, image resizing |

**Decision:** CloudFront Functions for URL rewrites and header manipulation (<1ms, cheapest). Lambda@Edge when you need to call an external service (auth token validation via API, origin routing based on DB lookup).

### Lambda@Edge Execution Points

```
Viewer request:   Between user and CloudFront cache (before cache check)
Origin request:   Between CloudFront cache and origin (on cache miss only)
Origin response:  Between origin response and CloudFront cache (on cache miss)
Viewer response:  Between CloudFront cache and user (always executes)
```

**Best practices:** Deploy Lambda@Edge at the viewer-request stage only for auth (executed before cache check). Use origin-request for origin routing — executed only on cache miss, much cheaper.

---

## Security Features

### Signed URLs and Signed Cookies

| | Signed URL | Signed Cookie |
|--|-----------|---------------|
| Scope | Single resource | Multiple resources (wildcard) |
| Use case | One video file download | Authenticated media library access |
| Implementation | Generate URL with expiry + signature | Set cookie with policy + signature |

Signed URLs use a **CloudFront key pair** (not IAM keys). Rotate keys via key groups.

### Field-Level Encryption

- Encrypt specific form fields (e.g., credit card number) at the edge using a public key
- Travels encrypted through CloudFront, origin, microservices — only the service holding the private key can decrypt
- Satisfies PCI-DSS requirements for cardholder data

### Origin Access Control (OAC)

```
S3 bucket policy:
{
  "Principal": {"Service": "cloudfront.amazonaws.com"},
  "Condition": {"StringEquals": {"AWS:SourceArn": "arn:aws:cloudfront::ACCOUNT:distribution/DISTRO_ID"}}
}
```

Only CloudFront can reach the S3 bucket — no direct S3 URL access. OAC supports SigV4 signing, including for S3 server-side encryption with KMS.

---

## CloudFront Limits

| Parameter | Limit |
|-----------|-------|
| Max file size (cache) | 30 GB |
| Request body forwarded to origin | 5 GB for PUT/POST |
| Origins per distribution | 25 (soft) |
| Cache behaviors per distribution | 25 (soft) |
| Headers forwarded to origin | 10 whitelist (or all) |
| Geographic restrictions | Allowlist or blocklist (country level) |

---

## Route 53 — DNS Service

### Hosted Zones

| Type | Use case |
|------|----------|
| **Public** | Internet-facing DNS (yourdomain.com) |
| **Private** | Internal DNS within VPCs (internal.corp) |

**ALIAS record** (Route 53-specific): maps a zone apex (root domain, e.g., `example.com`) to an AWS resource (ALB, CloudFront, S3, API GW). Unlike CNAME, ALIAS is resolved server-side — zero latency for the DNS hop. **Always use ALIAS for apex domains pointing to AWS resources.**

---

## Routing Policies

| Policy | Behavior | Use case |
|--------|----------|----------|
| **Simple** | Single record → single resource | Basic DNS, no health checking |
| **Weighted** | Split traffic by weight (0–255) | Canary deployments, A/B testing |
| **Latency** | Route to region with lowest latency | Global active-active |
| **Failover** | Primary → secondary on health check failure | Active-passive DR |
| **Geolocation** | Route by user's country/continent | Compliance (GDPR data residency), localization |
| **Geoproximity** | Route by geographic distance, with bias | Fine-grained geographic routing |
| **Multivalue** | Return up to 8 healthy endpoints randomly | Poor man's load balancing for non-AWS targets |
| **IP-based** | Route by source IP CIDR | ISP-based routing, internal traffic |

### Combining Policies (Traffic Policies)

Route 53 Traffic Policies chain routing policies:
```
Geolocation (EU → EU ALB, US → US ALB)
  ↓ for each region
Weighted (90% stable → 10% canary)
  ↓
Failover (primary → secondary)
  ↓
Latency (pick lowest-latency AZ endpoint)
```

---

## Health Checks

| Type | How it works |
|------|-------------|
| **Endpoint** | Route 53 probes IP/domain at configurable interval (10s or 30s) from multiple regions |
| **Calculated** | Parent check passes if N of M child checks pass |
| **CloudWatch alarm** | Health based on a CloudWatch alarm (for internal resources) |

**Fast health checks:** 10-second interval + threshold of 1 failure = detect failure in 10s (vs 30s default × 3 = 90s). More expensive but critical for latency-sensitive failover.

**DNS TTL + health check interaction:**
```
DNS TTL: 60s
Health check frequency: 30s
Failover detection: 30s (1 failed check) to 90s (3 failed checks)
Failover propagation: up to 60s (TTL expiry)
Total worst-case failover: 90 + 60 = 150s
```
Reduce TTL to 10–30s before a planned failover to reduce client impact.

---

## Route 53 Resolver

### Inbound Resolver Endpoint
- Allows on-premises resolvers to query Route 53 private hosted zones
- Creates ENIs in VPC subnets — on-prem DNS forwards to these IPs

### Outbound Resolver Endpoint
- Allows VPC resources to resolve on-premises DNS names
- Route 53 Resolver forwards to on-prem DNS for specific domains

```
VPC resource → Route 53 Resolver → Outbound Endpoint → Direct Connect/VPN → On-prem DNS
On-prem host → VPN/Direct Connect → Inbound Endpoint → Route 53 Private Zone
```

---

## Global Multi-Region Pattern

```
Route 53 Latency-based routing:
  us-east-1: api.example.com → ALB (primary)
  eu-west-1: api.example.com → ALB (primary)
  ap-southeast-1: api.example.com → ALB (primary)

Each ALB backed by:
  ECS/EKS service → Aurora Global DB (reads: local replica, writes: primary region)
```

**Active-active with database write routing:**
- Reads: go to local Aurora Global DB replica (low latency)
- Writes: route to primary region via latency-based routing OR use write endpoint that always resolves to primary region

---

## CloudFront + API Gateway Pattern

```
CloudFront Distribution:
  /api/* → API Gateway (caching: TTL 0 for POST, short TTL for GET)
  /static/* → S3 (caching: 1 year for immutable, OAC)
  / → S3 SPA (caching: short TTL for index.html)
```

Benefits:
- Single domain for SPA + API (no CORS complexity)
- WAF at CloudFront layer protects both static and API
- DDoS protection (Shield Standard free at CloudFront edge)
- Reduce origin hits for cacheable API responses

---

## Trade-off: CloudFront vs Direct ALB

| Dimension | CloudFront + ALB | Direct ALB |
|-----------|-----------------|-----------|
| Global latency | Reduced (edge PoPs) | Higher for distant users |
| DDoS protection | Shield Standard (free) | Requires Shield Advanced or WAF |
| Static asset delivery | Excellent (cached at edge) | Origin for every request |
| WebSocket | Via ALB behavior (not cached) | Native |
| Cost | CloudFront data transfer + requests | ALB bandwidth |
| Complexity | Higher | Lower |

**Rule:** Add CloudFront when you have static assets, a global user base, or need DDoS protection. ALB alone is sufficient for internal or single-region APIs.

---

## FAANG Interview Callouts

**"Design a global content delivery system for Netflix-scale video"**
→ Route 53 latency routing → CloudFront distribution → Origin Shield → S3 (HLS segments). CloudFront Signed URLs for entitlement. Lambda@Edge for A/B testing of codec/resolution. Cache HLS manifests with short TTL (1–5 min), segments with long TTL (permanent). CDN cache hit rate target: 95%+.

**"How does Route 53 achieve sub-millisecond DNS resolution globally?"**
→ Anycast routing — the same IP is announced from 100+ global PoPs. Your DNS query goes to the nearest PoP by BGP routing. Route 53 answers from a distributed DNS cluster at that PoP. Typical resolution: <1ms from the nearest PoP.

**"How would you implement a canary deployment with Route 53?"**
→ Weighted routing: `stable.example.com` (weight 90) + `canary.example.com` (weight 10). Monitor error rates in canary. Shift weight incrementally (10 → 25 → 50 → 100). On rollback: set canary weight to 0 — DNS TTL propagation takes up to TTL seconds (set TTL to 30s before deployment).

**"How do you enforce GDPR data residency with Route 53?"**
→ Geolocation routing: EU users → EU ALB → EU RDS. All other users → global cluster. Route 53 geolocation routing is country/continent-level. Use geoproximity for finer control. Note: Route 53 uses IP-based geolocation — VPN users bypass this (accept as risk or layer with Cloudflare for stricter enforcement).

**"What's the difference between latency-based and geoproximity routing?"**
→ Latency-based: routes to the region with lowest measured network latency — most accurate for actual user experience. Geoproximity: routes based on geographic distance from the resource, with an optional bias (+/−) to shift traffic boundaries. Use latency for performance optimization, geoproximity when you need to explicitly control traffic boundaries regardless of actual latency.
