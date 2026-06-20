# AWS Gateways: API Gateway, ALB, NLB, NAT Gateway, Internet Gateway, Transit Gateway

## Overview
AWS has multiple types of "gateways," each solving a different connectivity problem. Principal engineers must be precise about which gateway to use and why — interviewers regularly probe these distinctions.

---

## API Gateway

### What it is
A fully managed API front door. Accepts HTTP(S)/WebSocket/REST requests, handles auth, throttling, transformation, and routing to Lambda, HTTP integrations, AWS services, or VPC resources.

### API Types

| Type | Protocol | Use case |
|---|---|---|
| **REST API** | HTTP/1.1 | Full-featured: stages, authorisers, usage plans, caching, request/response transformation |
| **HTTP API** | HTTP/1.1 + 2 | Lightweight, lower cost (~70% cheaper than REST), JWT auth, Lambda/HTTP integration |
| **WebSocket API** | WebSocket | Real-time bidirectional: chat, notifications, live dashboards |

**REST API vs HTTP API**:
| Feature | REST API | HTTP API |
|---|---|---|
| Latency | ~6ms overhead | ~1ms overhead |
| Cost | $3.50/million | $1.00/million |
| Response caching | Yes | No |
| Usage plans & API keys | Yes | No |
| Request transformation | Yes (Velocity templates) | Limited |
| Resource policy | Yes | Yes |
| Private API (VPC) | Yes | Yes |
| Custom domain | Yes | Yes |
| **Use when** | Need caching, usage plans, full WAF integration, complex transformation | Simple Lambda/HTTP proxy; JWT auth; cost-sensitive |

### API Gateway Authorisers

| Type | Mechanism | Use case |
|---|---|---|
| **Lambda authoriser (request type)** | Custom Lambda validates token, returns IAM policy | Proprietary tokens, API keys in header, IP filtering |
| **Lambda authoriser (token type)** | Lambda validates Bearer token | OAuth opaque tokens, custom JWT libraries |
| **Cognito authoriser** | API Gateway validates Cognito JWT natively | Cognito user pool authentication |
| **IAM authoriser** | AWS Signature V4 on requests | Service-to-service within AWS, internal APIs |
| **JWT authoriser (HTTP API only)** | Native JWT validation against JWKS | Standard OAuth/OIDC providers (Auth0, Cognito, Okta) |

### API Gateway Throttling
| Level | Limit | Override |
|---|---|---|
| Account-level (default) | 10,000 RPS, 5,000 burst | Request increase via support |
| Stage-level | Per method or stage | Configure in deployment |
| Usage plan | Per API key | Control third-party consumers |

429 Too Many Requests = throttled. Implement exponential backoff with jitter in clients.

### Private API (VPC Integration)
API Gateway private API accessible only from within a VPC via an Interface VPC Endpoint (`com.amazonaws.region.execute-api`). No internet exposure. Resource policy restricts access to specific VPC endpoint IDs.

### VPC Link (Private Integration)
Route API Gateway traffic to resources in a VPC (ALB, NLB, ECS, EC2) without exposing them to the internet:
- **REST API**: VPC Link → NLB → private resources
- **HTTP API**: VPC Link → ALB or NLB or Cloud Map → private resources

### API Gateway + Lambda patterns

**Lambda Proxy integration**: API Gateway passes the full HTTP request (method, path, headers, body) as a JSON event to Lambda. Lambda returns the full HTTP response (statusCode, headers, body). Most common pattern for serverless APIs.

**Direct integration (non-proxy)**: API Gateway transforms request → calls Lambda/AWS service → transforms response. Uses Velocity Template Language (VTL). Complex but zero Lambda invocation for simple CRUD proxies.

---

## Application Load Balancer (ALB)

### What it is
L7 (HTTP/HTTPS) load balancer. Understands HTTP headers, paths, hostnames, query strings. Routes to Target Groups (EC2, ECS, Lambda, IP, ALB).

### Key features
- **Path-based routing**: `/api/*` → API service; `/static/*` → S3 origin
- **Host-based routing**: `api.example.com` → API TG; `admin.example.com` → Admin TG
- **Header/query-string routing**: route based on any HTTP header or query parameter
- **Weighted routing**: blue/green deployment — 90% to stable, 10% to canary
- **gRPC support**: native gRPC health checks and routing
- **WebSocket and HTTP/2**: native support
- **Lambda targets**: up to 10MB request/response (larger than API Gateway REST API)
- **Sticky sessions**: cookie-based or application-based stickiness
- **WAF integration**: attach AWS WAF to block SQL injection, XSS, bad bots

### ALB vs API Gateway

| | ALB | API Gateway |
|---|---|---|
| **Protocol** | HTTP/HTTPS/gRPC/WebSocket | HTTP/WebSocket |
| **Target types** | EC2, ECS, Lambda, IP, ALB | Lambda, HTTP, AWS services |
| **Auth** | Cognito OIDC (limited), header passthrough | Full authoriser support |
| **Throttling** | None (rate limiting must be done at app layer) | Built-in throttling and usage plans |
| **Cost** | ~$16/month + $0.008/LCU-hour | $1–3.50/million requests |
| **Max request size** | No limit | 10MB (REST), 350KB (HTTP) |
| **Use when** | Container/EC2 services, gRPC, large payloads, complex routing | Serverless APIs, auth, usage plans, developer portal |

### Target Groups
Configure health checks per target group:
```
Protocol: HTTP
Path: /health
Healthy threshold: 2
Unhealthy threshold: 3
Timeout: 5s
Interval: 10s
Success codes: 200
```
ALB removes unhealthy targets; new registrations go through health check before receiving traffic.

---

## Network Load Balancer (NLB)

### What it is
L4 (TCP/UDP/TLS) load balancer. Passes bytes through to targets without HTTP awareness. Extremely high performance, static IP per AZ, preserves source IP.

### When to use NLB over ALB

| Requirement | Use NLB |
|---|---|
| TCP/UDP (not HTTP) | Database connections, MQTT, custom protocols |
| Static IP for whitelisting | NLB provides one Elastic IP per AZ |
| Ultra-low latency | ~100 microseconds vs ALB's ~1ms |
| Preserve client source IP | NLB passes source IP natively; ALB uses X-Forwarded-For |
| PrivateLink (expose VPC service) | NLB is required as PrivateLink endpoint |
| Very high throughput (millions RPS) | NLB scales to extreme throughput |

**NLB does NOT terminate HTTP**: it passes TCP bytes to targets. Cannot do path routing, header manipulation, or WAF integration.

---

## Internet Gateway (IGW)

A horizontally-scaled, redundant, highly available VPC component that allows internet traffic in and out of a VPC.

- Attach one IGW per VPC
- Route table entry: `0.0.0.0/0 → igw-xxxxx` makes a subnet "public"
- Translates private IP ↔ public IP for instances with public IP / Elastic IP
- No bandwidth limit, no single point of failure
- Free (pay only for data transfer)

**Public subnet = subnet with a route to IGW + instances with public IPs**. A subnet with an IGW route but no instances having public IPs is still effectively private.

---

## NAT Gateway

Provides outbound internet for private subnets — instances get outbound internet without being reachable inbound.

See [vpc-networking.md](vpc-networking.md) for full NAT Gateway coverage.

**Key points**:
- $0.045/hr + $0.045/GB processed
- One per AZ for HA
- Scales to 100 Gbps automatically
- Use VPC endpoints to eliminate NAT Gateway from AWS service calls

---

## Transit Gateway (TGW)

See [vpc-networking.md](vpc-networking.md) for full TGW coverage.

**Key points**:
- Hub-and-spoke for N VPCs + on-prem Direct Connect / VPN
- TGW route tables for segmentation (prod ≠ dev routing)
- $0.05/hr/attachment + $0.02/GB

---

## Gateway Load Balancer (GWLB)

Deploys third-party virtual appliances (firewalls, IDS/IPS, deep packet inspection) in a transparent, scalable way:

```
Internet → IGW → GWLB endpoint → GWLB → Appliance fleet (Palo Alto, Fortinet, Checkpoint)
                                      → Original destination (back to GWLB → application)
```

Uses GENEVE protocol to preserve original traffic while routing through appliances. Traffic is symmetric (same appliance sees both directions of a flow). Used in "centralized inspection" architectures where all traffic passes through a security VPC.

---

## VPC Endpoints (Gateway & Interface)

**Gateway Endpoints** (S3 and DynamoDB): route table entries; free; traffic stays on AWS backbone.
**Interface Endpoints (PrivateLink)**: ENI in your subnet; supports 100+ AWS services; ~$7.50/AZ/month.

**Key use cases**:
- ECR private endpoint → EKS/ECS pulls Docker images without NAT Gateway ($0.01/GB data transfer saving)
- Secrets Manager endpoint → Lambda reads secrets without NAT Gateway
- SQS/SNS endpoints → application processes messages without internet

---

## API Gateway Patterns

### Serverless REST API
```
Client → Route53 → CloudFront (optional WAF + CDN) → API Gateway → Lambda → DynamoDB
```

### Private Microservice Gateway
```
Client → API Gateway (private VPC endpoint) → VPC Link → NLB → ECS service (private subnet)
```

### Multi-Account API with Centralised Auth
```
External client → API Gateway (account A) → Lambda Authoriser (validate JWT)
               → VPC Link → NLB → ECS services (accounts B, C, D via PrivateLink)
```

---

## Gateway Decision Matrix

| Requirement | Use |
|---|---|
| HTTP/HTTPS API with auth, throttling, usage plans | API Gateway REST or HTTP API |
| Container/EC2 load balancing with routing rules | ALB |
| TCP/UDP load balancing, static IP, PrivateLink | NLB |
| Public internet access for VPC | Internet Gateway |
| Outbound internet from private subnet | NAT Gateway |
| Connect 10+ VPCs + on-prem | Transit Gateway |
| Network security appliance at scale | Gateway Load Balancer |
| Private AWS service access from VPC | VPC Endpoint (Gateway or Interface) |

---

## Monitoring

| Gateway | Key metric | Alert condition |
|---|---|---|
| API Gateway | `5XXError`, `Latency` P99, `Count` | Error rate > 1%; P99 > SLA |
| ALB | `HTTPCode_Target_5XX_Count`, `TargetResponseTime`, `UnHealthyHostCount` | Any unhealthy host; 5xx spike |
| NLB | `UnHealthyHostCount`, `ActiveFlowCount` | Any unhealthy; flow exhaustion |
| NAT Gateway | `ErrorPortAllocation`, `BytesOutToDestination` | Port exhaustion; data exfiltration |
| TGW | `BytesIn/Out`, `PacketsIn/Out`, `PacketDropCountBlackhole` | Blackhole drops → route table misconfiguration |

---

## Best Practices

1. **API Gateway**: use HTTP API (not REST) when you don't need caching, usage plans, or complex transformation — 70% cheaper
2. **ALB**: always configure health checks with realistic thresholds; use weighted target groups for canary deployments
3. **NLB**: use when clients need to whitelist static IPs; use PrivateLink with NLB as the endpoint service
4. **IGW**: one per VPC; routes only in public subnet route tables; do not route private subnets to IGW
5. **NAT Gateway**: one per AZ; VPC endpoints eliminate NAT for all AWS service calls
6. **TGW**: use TGW route table segmentation to prevent prod/dev cross-routing; enable CloudWatch flow logs on TGW
7. **WAF on ALB/API Gateway**: block OWASP top 10; use Managed Rule Groups (AWS or Marketplace)
8. **Enable access logging** on all ALBs and API Gateways — required for security forensics

---

## FAANG Interview Points

**"API Gateway vs ALB for a microservices API"**: ALB for services running in ECS/EC2 (container load balancing, path routing, no per-request cost at scale). API Gateway for serverless (Lambda) or when you need auth, throttling, API keys, usage plans, or a developer portal.

**"How do you expose an internal service to partners without exposing your VPC?"**: PrivateLink: NLB in front of your service → expose as PrivateLink Endpoint Service → partners create Interface Endpoint in their VPC to connect. No VPC peering, no CIDR conflicts, no internet exposure.

**"Design global API routing"**: Route53 Latency routing → CloudFront (TLS termination, WAF, CDN) → API Gateway (per-region) → Lambda/ALB. CloudFront reduces API Gateway costs (fewer requests hit origin) and improves latency via edge caching.
