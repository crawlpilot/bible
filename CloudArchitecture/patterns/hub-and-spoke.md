# Hub-and-Spoke Architecture Pattern

## Overview
Hub-and-Spoke is a topology pattern where a central hub provides shared services to multiple spoke environments. Spokes connect to the hub but do not connect directly to each other — all cross-spoke communication flows through the hub.

In cloud architecture, this pattern applies at two distinct levels:
1. **Network topology**: VPCs connected to a central Transit Gateway or shared VPC
2. **Account/organisational topology**: a central services account serving many product accounts

Both solve the same fundamental problem: how to share services (security tools, DNS, connectivity, CI/CD, logging) across many independent environments without creating N² connections or duplicating infrastructure.

---

## The Two Flavours

### Network Hub-and-Spoke (Transit Gateway)
```
                    ┌─────────────────┐
                    │  Hub VPC        │
                    │  ┌───────────┐  │
                    │  │ Shared    │  │
Spoke VPC A ───────►│  │ Services: │  │◄─────── Spoke VPC D
                    │  │ Egress    │  │
Spoke VPC B ───────►│  │ Firewall  │  │◄─────── Spoke VPC E
                    │  │ DNS       │  │
Spoke VPC C ───────►│  │ NTP/Time  │  │
                    │  └───────────┘  │
                    └────────┬────────┘
                             │
                     On-Premise / Internet
```
Transit Gateway is the hub. Each spoke VPC attaches to the TGW. The hub VPC contains shared inspection (AWS Network Firewall, third-party NGFW), centralised NAT, DNS resolution, and Direct Connect / VPN termination.

### Organisational Hub-and-Spoke (AWS Organizations)
```
                 ┌──────────────────────┐
                 │  Root OU             │
                 │  ┌────────────────┐  │
                 │  │ Management     │  │  (billing, org governance, SCPs)
                 │  │ Account        │  │
                 │  └────────────────┘  │
                 │  ┌────────────────┐  │
                 │  │ Shared Services│  │  (hub: security, logging, DNS, CI/CD, ECR)
                 │  │ Account        │  │
                 │  └────────────────┘  │
                 │  ┌────────────────┐  │
                 │  │ Prod OU        │  │
                 │  │  ├── Team A    │  │  (spokes: product accounts)
                 │  │  ├── Team B    │  │
                 │  │  └── Team C    │  │
                 │  └────────────────┘  │
                 │  ┌────────────────┐  │
                 │  │ Non-Prod OU    │  │
                 │  │  ├── Staging   │  │
                 │  │  └── Dev       │  │
                 │  └────────────────┘  │
                 └──────────────────────┘
```

---

## Spoke Isolation Levels

| Level | Blast radius | Autonomy | Cost | Use when |
|---|---|---|---|---|
| Per-service account | Single service | High | High (many accounts) | FAANG, regulated industries |
| Per-team account | One team's services | Medium | Medium | Mid-size orgs |
| Per-environment account | All prod or all non-prod | Low | Low | Small orgs |
| Single account (no isolation) | Everything | Very high | Minimal | Solo dev, prototypes only |

**FAANG standard**: one account per team per environment (e.g., `payments-prod`, `payments-staging`). Each account is a blast-radius boundary — a compromised or misconfigured account cannot affect other accounts' resources.

---

## Hub Services (What Lives in the Hub)

### Network Hub
| Service | Why centralised |
|---|---|
| **AWS Network Firewall / NGFW** | Inspect all egress in one place; update rules centrally; audit-friendly |
| **NAT Gateway (centralised)** | Reduces NAT Gateway proliferation; ~$32/month/per AZ saved per spoke |
| **AWS Direct Connect / VPN** | One physical connection shared across all spokes via TGW |
| **Route 53 Resolver** | Centralised DNS resolution for on-prem ↔ cloud hybrid DNS |
| **Transit Gateway** | Hub itself; connects all VPCs and on-prem |

### Account Hub (Shared Services Account)
| Service | Why centralised |
|---|---|
| **ECR (Container Registry)** | One registry; spokes pull images; cross-account pull-through cache |
| **AWS Security Hub** | Aggregates findings from all accounts into one view |
| **CloudTrail (aggregated)** | All accounts stream CloudTrail to central S3 bucket; tampering prevention |
| **GuardDuty (delegated admin)** | One GuardDuty admin account; findings from all member accounts |
| **CI/CD pipelines** | CodePipeline or GitHub Actions assume cross-account roles to deploy |
| **Secrets Manager (shared secrets)** | Shared TLS certificates, API keys, third-party tokens |
| **AWS Config (aggregator)** | Compliance posture across all accounts in one dashboard |

---

## Transit Gateway Route Table Segmentation

A critical security control: prevent prod spoke VPCs from routing to dev spoke VPCs through the hub.

```
TGW Route Table: "Production"
  - Associations: Prod-VPC-A, Prod-VPC-B, Hub-VPC
  - Propagations: routes to each prod spoke + hub

TGW Route Table: "Non-Production"
  - Associations: Dev-VPC, Staging-VPC
  - Propagations: routes to dev/staging spokes + hub (but NOT prod)

TGW Route Table: "Shared Services"
  - Associations: Hub-VPC
  - Propagations: routes to all spokes
```
Result: dev traffic can reach shared services but not prod VPCs. Prod traffic cannot reach dev at all.

---

## Centralised Egress Pattern

All spoke VPC outbound internet traffic routes through the hub:
```
Spoke VPC (private subnet)
  → Route: 0.0.0.0/0 to TGW
  → TGW routes to Hub VPC
  → Hub VPC: Network Firewall (inspect/block) → NAT Gateway → Internet
```

Benefits:
- Single egress IP range for external allowlisting
- Centralised URL/domain filtering (block malware C2, shadow IT)
- Centralised egress logging for compliance
- Cost: one NAT Gateway per AZ in the hub vs one per spoke AZ

Cost saving example: 10 spoke VPCs × 3 AZs × $32/NAT Gateway = $960/month saved by centralising in one hub.

---

## Centralised Ingress Pattern (With Egress Inspection)

```
Internet → Route53 → CloudFront → ALB (in Hub VPC)
                                    ↓ (via TGW VPC Link or PrivateLink)
                              Spoke VPC A (API service)
                              Spoke VPC B (web service)
```

Alternatively, each spoke has its own ALB but the WAF policy is centralised (shared AWS Managed Rule Groups, centralised WAF log analysis).

---

## Trade-offs

| Dimension | Hub-and-Spoke | Full Mesh (VPC Peering) | Flat (Single VPC) |
|---|---|---|---|
| **Connections** | N (spokes to hub) | N×(N-1)/2 | 0 (single network) |
| **Blast radius** | Account/VPC level | Account/VPC level | Entire network |
| **Latency** | +1 hop through hub | Direct peer-to-peer | None |
| **Cost** | TGW + centralised services | Peering free; data transfer cost | No extra networking |
| **Operational complexity** | Medium (central team manages hub) | High (N² peering agreements) | Low but dangerous |
| **Security control** | Centralised inspection | Per-VPC peering security | Flat trust |
| **Scalability** | Excellent — add spoke, attach to TGW | Poor — grows quadratically | Poor — single CIDR |

**When full mesh wins**: fewer than 5 VPCs with known, stable topology and no requirement for central inspection. VPC peering is free; TGW is not.

---

## Organisational Anti-Patterns

**The Big Shared VPC anti-pattern**: everything in one VPC. No account isolation. One misconfigured security group exposes every service. IAM blast radius is the entire account. Don't do this in production.

**The Peering Spaghetti anti-pattern**: every team peers their VPC to every other team's VPC they need. After 10 teams you have 45 peering connections. After 20 teams: 190 connections. Unmanageable; non-transitive (A can talk to B and C but B can't route to C through A).

**The Centralised Bottleneck anti-pattern**: every spoke routes all traffic (even spoke-to-spoke) through the hub for inspection. The hub becomes a throughput bottleneck and a single point of failure. Mitigation: route only internet egress through hub; allow approved spoke-to-spoke via direct TGW routing.

---

## AWS Landing Zone (Industrialising Hub-and-Spoke)

AWS Control Tower automates the hub-and-spoke org setup:
- Creates management, log archive, and security (audit) accounts automatically
- Applies guardrail SCPs to OUs
- Enrolls new accounts via Account Factory (or Terraform/CDK)
- Integrates with IAM Identity Center for SSO

**Account vending machine pattern**: engineers request a new AWS account via a self-service portal → Account Factory creates the account → applies baseline SCPs, CloudTrail, Config, GuardDuty, Security Hub → account is ready to use in minutes.

---

## Monitoring Hub-and-Spoke

| What to monitor | Metric / log | Alert |
|---|---|---|
| TGW attachment health | CloudWatch `PacketDropCountBlackhole` | > 0 → route table misconfiguration |
| Cross-account API calls | CloudTrail (aggregated in hub) | `AssumeRole` from unexpected account |
| Network Firewall blocked flows | Firewall logs to S3 + Athena | Spike in blocked → scanning or misconfiguration |
| Hub VPC NAT Gateway | `ErrorPortAllocation` | Port exhaustion → add NAT Gateways |
| Security Hub findings | Security Hub (aggregated) | Critical findings across any member account |

---

## Best Practices

1. **One AWS account per team per environment** — this is the blast radius unit; less than this is under-isolated
2. **Centralise security tooling** (GuardDuty, Security Hub, CloudTrail, Config) in a dedicated security account
3. **Use TGW route table segmentation** to prevent prod/non-prod cross-routing at the network layer
4. **Centralise egress** — one Network Firewall in the hub; centralise egress IP ranges for allowlisting
5. **Use Account Factory / Control Tower** for account vending — don't create accounts manually
6. **Apply SCPs from the root** to enforce baseline security (no root usage, no disabling CloudTrail, region restriction)
7. **PrivateLink over TGW peering** for exposing specific services across accounts — minimises network blast radius
8. **Tag everything** with `account-type`, `team`, `environment` — enables cost allocation and policy enforcement

---

## FAANG Interview Points

**"How would you design AWS networking for 200 teams?"**: Hub-and-spoke with Transit Gateway. One shared services account for centralised DNS, NAT, firewall, CI/CD, ECR. Each team gets an account per environment (dev/staging/prod). TGW route tables segment prod/non-prod. Control Tower + Account Factory for account vending.

**"How do you prevent a compromised dev account from reaching prod?"**: TGW route table segmentation — dev VPCs attach to the "Non-Production" route table which has no route to the "Production" route table. SCPs prevent dev accounts from creating TGW attachments to the production TGW. GuardDuty monitoring in both accounts.

**"Hub-and-spoke vs mesh for VPC connectivity?"**: Mesh for small stable topologies (<5 VPCs, known connectivity). Hub-and-spoke for growing orgs, centralised inspection, and hybrid (on-prem) connectivity. TGW adds ~$0.07/GB vs peering's pure data transfer cost — break-even is justified by operational simplicity beyond ~5 VPCs.
