# Azure Networking — VNet, Front Door, APIM, ExpressRoute

**AWS Equivalents**:  
- Azure Virtual Network (VNet) → Amazon VPC  
- Azure Front Door → Amazon CloudFront + ALB  
- Azure API Management (APIM) → Amazon API Gateway  
- Azure Application Gateway → AWS Application Load Balancer + WAF  
- Azure Load Balancer → AWS Network Load Balancer  
- Azure ExpressRoute → AWS Direct Connect  
- Azure Private Link / Private Endpoints → AWS PrivateLink  
- Azure DNS → Amazon Route 53  
- Azure Traffic Manager → Amazon Route 53 Traffic Policies  

**Mental model**: Azure networking mirrors AWS VPC concepts almost 1:1 but uses different names and has a few important differences: NSGs operate at both subnet and NIC level (AWS: NACLs at subnet, SGs at instance), and Azure Front Door is a single service combining CloudFront + ALB + WAF.

---

## 1. Azure Virtual Network (VNet)

### VNet vs VPC Comparison

| Concept | Azure VNet | AWS VPC |
|---------|-----------|---------|
| Private IP range | User-defined CIDR (RFC 1918) | Same |
| Subnet | Subdivision of VNet CIDR | Same |
| Internet gateway | Implicit (no explicit resource needed) | Explicit IGW resource required |
| NAT Gateway | Azure NAT Gateway | AWS NAT Gateway |
| Route table | User Defined Routes (UDR) | Route Tables |
| Firewall (stateful) | Network Security Group (NSG) | Security Group |
| Firewall (stateless) | NSG (also stateful — NSG is both) | Network ACL (NACL) |
| Peering | VNet Peering | VPC Peering |
| Hub-spoke | Azure Virtual WAN or manual hub VNet | AWS Transit Gateway |
| DNS | Azure Private DNS Zones | Route 53 Private Hosted Zones |

### Network Security Groups (NSG)

NSG = stateful packet filter. Applied at **subnet level** or **NIC level** (or both):
- Subnet NSG: applies to all resources in subnet
- NIC NSG: applies to specific VM/NIC

**vs AWS Security Groups**:
- Both: stateful (return traffic automatically allowed)
- NSG: can be applied to multiple subnets/NICs (SGs are attached to resource, not reused across subnets)
- NSG: has explicit DENY rules (AWS SGs: only ALLOW rules; NACLs handle deny)
- NSG: priority-based rule evaluation (lower number = higher priority, like NACLs)

**NSG rule structure**:
```
Priority: 100  (100–4096; lower = higher priority)
Name:     Allow-HTTPS
Protocol: TCP
Source:   Any (or specific IP/CIDR/ASG)
Dest:     VirtualNetwork
Port:     443
Action:   Allow

Priority: 65000  (default rules — cannot delete)
Name:     AllowVnetInBound (all VNet traffic in)
Name:     AllowAzureLoadBalancerInBound (ALB health probes)
Name:     DenyAllInBound (deny everything else)
```

### Application Security Groups (ASG)

Group VMs logically by function, then reference ASGs in NSG rules:
```
ASG: web-tier   → VMs: web01, web02, web03
ASG: db-tier    → VMs: db01, db02

NSG rule: Allow web-tier → db-tier on port 1433
(No IP addresses needed — ASG membership drives the rule)
```

**AWS equivalent**: Referencing Security Group IDs in other SG rules (same concept, different name).

### VNet Peering

- **Same region**: VNet Peering (low latency, no gateway needed)
- **Cross region**: Global VNet Peering (traffic over Azure backbone, not internet)
- **Non-transitive**: VNet A ↔ B, B ↔ C does NOT mean A ↔ C (same as VPC peering)

**Hub-Spoke topology** (vs AWS Transit Gateway):

```
Azure:
Hub VNet (shared services: firewall, DNS, AD)
  ├── Peer → Spoke VNet A (app team A)
  ├── Peer → Spoke VNet B (app team B)
  └── Peer → Spoke VNet C (app team C)

Traffic routing: Spoke → Hub → Spoke (forced via UDR + Azure Firewall)
```

**Azure Virtual WAN**: Managed hub-spoke at scale (Microsoft-managed hub). AWS Transit Gateway equivalent.

---

## 2. Azure Front Door

### What It Is

Global anycast CDN + Layer 7 load balancer + WAF in a single service. The most comprehensive comparison is to CloudFront + ALB combined.

```
Users worldwide
      │
      ▼ Anycast (routed to nearest POP — 118+ globally)
Azure Front Door POP
      │
      ├── WAF policy evaluation
      ├── TLS termination
      ├── Caching (CDN)
      └── Origin routing
           │
    ┌──────┼──────┐
    ▼      ▼      ▼
 Origin  Origin  Origin
(App Svc)(AKS)  (Storage)
```

### Front Door vs CloudFront + ALB

| Feature | Azure Front Door (Standard/Premium) | CloudFront | ALB |
|---------|------------------------------------|-----------|----|
| Global anycast | Yes | Yes | No (regional) |
| PoP locations | 118+ | 600+ (more PoPs) | N/A |
| WAF | Built-in | Separate WAF resource | Separate WAF resource |
| L7 routing | URL path, host, query string | Cache behaviors | Path/host routing |
| Health probes | HTTP/HTTPS probes to origins | Origin health checks | Target group health checks |
| SSL/TLS offload | Yes | Yes | Yes |
| Caching | Yes (CDN) | Yes | No |
| Static file hosting | Via Blob Storage origin | Via S3 origin | No |
| Custom domains + cert | Yes (Azure-managed cert) | Yes (ACM cert) | Yes (ACM cert) |
| Rate limiting | WAF rule (Premium) | WAF rule | WAF rule |
| DDoS protection | Standard (included) | AWS Shield Standard | AWS Shield Standard |

**Front Door tiers**:

| Tier | Use Case | Price |
|------|---------|-------|
| **Standard** | CDN + routing + basic WAF | Lower |
| **Premium** | Standard + advanced WAF + Private Link origins + Bot protection | Higher |

**Key Front Door capability**: Private Link origin — Front Door can route to private (non-internet-facing) backends via Azure Private Link. CloudFront requires public origin or OAI/OAC for S3.

### Routing Rules

```
Front Door profile
└── Endpoint: myapp.azurefd.net
    ├── Route: /api/* → Origin Group: api-backends (3 App Services, round-robin)
    ├── Route: /static/* → Origin: Azure Blob Storage (cache enabled)
    └── Route: /* → Origin Group: web-backends
```

**Origin group health probes**: If origin unhealthy (>4xx or timeout), Front Door removes it from rotation automatically.

---

## 3. Azure API Management (APIM)

### What It Is

Full-lifecycle API gateway with a developer portal, policy engine, and product/subscription model. More feature-rich than AWS API Gateway for enterprise use cases.

### Tiers

| Tier | Use Case | Scale | VNet |
|------|---------|-------|------|
| **Consumption** | Serverless, pay-per-call | Auto | External only |
| **Developer** | Non-production, dev/test | 1 unit | Supported |
| **Basic / Standard** | Production, low-medium traffic | Up to 4 units | Supported |
| **Premium** | Enterprise, multi-region, high SLA | Up to 31 units | Internal/External |
| **Isolated** | Highest compliance requirements | Dedicated infra | Full isolation |

### Policy Engine

APIM policies are XML-based transformations applied at four points:

```
Inbound (request from client → APIM)
Backend (request APIM → backend)
Outbound (response backend → APIM)
On-Error (error handler)
```

**Common policies**:

```xml
<policies>
  <inbound>
    <!-- Validate JWT from Entra ID -->
    <validate-jwt header-name="Authorization" failed-validation-httpcode="401">
      <openid-config url="https://login.microsoftonline.com/{tenant}/.well-known/openid-configuration" />
    </validate-jwt>

    <!-- Rate limit per subscription -->
    <rate-limit-by-key calls="100" renewal-period="60"
      counter-key="@(context.Subscription.Id)" />

    <!-- Transform request -->
    <set-header name="X-Internal-Caller" exists-action="override">
      <value>APIM</value>
    </set-header>
  </inbound>

  <backend>
    <!-- Circuit breaker -->
    <retry condition="@(context.Response.StatusCode >= 500)" count="3" interval="1" />
  </backend>

  <outbound>
    <!-- Remove internal headers from response -->
    <set-header name="X-Powered-By" exists-action="delete" />

    <!-- Cache response -->
    <cache-store duration="300" />
  </outbound>
</policies>
```

### APIM vs AWS API Gateway

| Feature | Azure APIM | AWS API Gateway (HTTP) | AWS API Gateway (REST) |
|---------|-----------|----------------------|----------------------|
| Policy engine | Rich XML policies | Request/response mapping | Request/response mapping |
| Rate limiting | Per subscription, per IP | Usage plans | Usage plans |
| Developer portal | **Built-in** (Cosmos-backed) | None (use 3rd party) | None |
| JWT validation | Native policy | Lambda authorizer | Lambda authorizer |
| Caching | Policy-based | Stage-level | Stage-level |
| Subscription/product model | Yes (multi-tier access) | API key only | API key / usage plans |
| Mock responses | Yes (mock-response policy) | Mock integration | Mock integration |
| WebSocket | Yes | Yes | No |
| gRPC | Yes (Premium) | No | No |
| Multi-region | Yes (Premium) | Regional only | Regional only |

**APIM subscription model**: Products → Subscriptions → APIs. A subscription key grants access to a product (bundle of APIs). Multiple access tiers (free, basic, enterprise) via product + rate-limit combinations.

---

## 4. Azure Application Gateway

Layer 7 load balancer with WAF. Closer to ALB than Front Door — regional (not global).

| Feature | Application Gateway | AWS ALB |
|---------|--------------------|---------| 
| Scope | Regional | Regional |
| Layer | 7 (HTTP/HTTPS) | 7 |
| WAF | WAF v2 built-in | Separate WAF resource |
| SSL offload | Yes | Yes |
| Path-based routing | Yes | Yes |
| Host-based routing | Yes | Yes |
| WebSocket | Yes | Yes |
| gRPC | Yes | Limited |
| Autoscaling | Yes (v2) | Yes |
| Zone redundancy | Yes (v2) | Yes |
| Private IP frontend | Yes | Yes |

**Application Gateway WAF v2** comes in two modes:
- **Detection**: Log without blocking (good for initial rollout)
- **Prevention**: Block matching requests

**OWASP rulesets**: CRS 3.2 (OWASP Core Rule Set) built-in.

---

## 5. Azure Load Balancer

Layer 4 (TCP/UDP) load balancer. The NLB equivalent.

| Feature | Azure Load Balancer | AWS NLB |
|---------|--------------------|---------| 
| Layer | 4 (TCP/UDP) | 4 |
| HA Ports | Yes (single rule for all ports) | No |
| Zonal redundancy | Zone-redundant SKU | Multi-AZ (built-in) |
| Static IP | Yes | Yes |
| Cross-region | Yes (Standard tier) | Global Accelerator required |
| Health probes | TCP, HTTP, HTTPS | TCP, HTTP, HTTPS, TLS |
| Session persistence | Source IP, Source IP+Port | Source IP (optional) |

**HA Ports rule**: Single load balancing rule for ALL TCP/UDP ports — useful for NVAs (Network Virtual Appliances / firewalls).

---

## 6. ExpressRoute vs AWS Direct Connect

### ExpressRoute

Dedicated private connectivity from on-premises to Azure over MPLS circuits (via providers like AT&T, Equinix).

| Feature | ExpressRoute | AWS Direct Connect |
|---------|-------------|-------------------|
| Max bandwidth | 100 Gbps | 100 Gbps |
| Redundancy | Active/Active circuits | LAG (Link Aggregation) |
| Connectivity model | Provider-based or Direct | Direct or via partner |
| BGP | Yes (mandatory) | Yes (mandatory) |
| On-prem ↔ On-prem routing | **Global Reach** (via Azure backbone) | AWS Direct Connect Gateway (VPC only) |
| SLA | 99.95% (redundant circuits) | 99.9% per connection |

**ExpressRoute Global Reach**: Connect two on-prem locations through Azure's backbone. Traffic flows on-prem A → ExpressRoute → Azure → ExpressRoute → on-prem B. AWS Direct Connect doesn't offer equivalent on-prem-to-on-prem routing through AWS backbone.

**ExpressRoute circuit types**:
- **Provider model**: Connect at co-location facility via partner
- **Direct (ExpressRoute Direct)**: Direct port into Microsoft network at 10/100 Gbps

---

## 7. Azure Private Link and Private Endpoints

Private access to Azure PaaS services (Storage, Cosmos DB, SQL, etc.) from within a VNet — traffic never leaves Microsoft network.

```
VNet
└── Subnet
    └── Private Endpoint (NIC with private IP 10.0.1.5)
              │
              └── Azure Private Link → Azure SQL Database
                                      (public endpoint can be disabled)
```

**DNS**: Private Endpoint registers `mysql.database.windows.net → 10.0.1.5` in a Private DNS Zone linked to the VNet.

**vs AWS PrivateLink**: Same concept. AWS PrivateLink creates an endpoint ENI; Azure creates a private endpoint NIC. Both support DNS resolution to private IPs.

---

## Key Numbers for Interviews

| Resource | Number | Notes |
|----------|--------|-------|
| Front Door POP locations | 118+ globally | vs CloudFront 600+ |
| Application Gateway max instances | 125 (v2) | Auto-scaling up to this |
| Azure Load Balancer backend pool | 1,000 VMs | Per load balancer |
| VNet max address space | /8 (1.6M IPs) | Multiple CIDR blocks supported |
| Subnets per VNet | 3,000 | Practical max |
| NSG rules per NSG | 1,000 (inbound + outbound) | Default; increase via support |
| VNet Peerings per VNet | 500 | Soft limit |
| ExpressRoute max bandwidth | 100 Gbps | Via Direct model |
| APIM request timeout | 240 seconds | Backend call timeout |
| APIM max request size | 102,400 bytes (100 KB) | Body size limit (configurable) |

---

> **FAANG Interview Callout**: "In Azure networking, the two most impactful differences from AWS are: (1) Azure Front Door unifies CDN + L7 load balancing + WAF — on AWS you'd need CloudFront + ALB + WAF ACL, three separate resources with separate pricing and configuration. (2) ExpressRoute Global Reach allows on-prem-to-on-prem routing through Azure's backbone, which is a key enterprise integration pattern for merger/acquisition scenarios — AWS Direct Connect doesn't offer an equivalent. For security, NSGs having explicit DENY rules (unlike SGs) means you can lock down traffic more precisely without relying on implicit deny-all, though NACLs cover this on AWS."
