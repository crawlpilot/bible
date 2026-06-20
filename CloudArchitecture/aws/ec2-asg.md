# AWS EC2 Auto Scaling Groups (ASG)

## Overview
An Auto Scaling Group (ASG) manages a fleet of EC2 instances, automatically scaling in and out based on demand, replacing unhealthy instances, and distributing capacity across Availability Zones. ASGs are the compute backbone for all traditional (non-serverless) web and application tiers on AWS.

---

## Core Concepts

```
Auto Scaling Group
├── Launch Template (instance type, AMI, SG, IAM role, user data)
├── Desired Capacity (current target instance count)
├── Min Capacity (floor — never scale below this)
├── Max Capacity (ceiling — never scale above this)
├── VPC Subnets (across multiple AZs)
└── Scaling Policies (when to add/remove instances)
```

**Desired = current target. Min ≤ Desired ≤ Max.**

---

## Launch Template vs Launch Configuration

Always use **Launch Templates** (Launch Configurations are deprecated):

| Feature | Launch Template | Launch Configuration |
|---|---|---|
| Versioning | Yes — v1, v2, v3 | No |
| Mixed instance types | Yes (Spot + On-Demand mix) | No |
| T2/T3 Unlimited mode | Yes | No |
| IMDSv2 enforcement | Yes | No |
| Nitro Enclaves | Yes | No |
| Status | **Current** | Deprecated |

Launch Template example (key fields):
```json
{
  "ImageId": "ami-xxxx",
  "InstanceType": "m7g.large",
  "IamInstanceProfile": {"Arn": "arn:aws:iam::...:instance-profile/my-role"},
  "SecurityGroupIds": ["sg-xxxx"],
  "MetadataOptions": {"HttpTokens": "required", "HttpEndpoint": "enabled"},
  "EbsOptimized": true,
  "Monitoring": {"Enabled": true},
  "UserData": "<base64-encoded startup script>"
}
```

---

## Scaling Policies

### 1. Target Tracking (recommended for most use cases)
Tell ASG what target to maintain; AWS manages the scaling automatically:
```json
{
  "TargetTrackingScalingPolicy": {
    "TargetValue": 60.0,
    "PredefinedMetricSpecification": {"PredefinedMetricType": "ASGAverageCPUUtilization"}
  }
}
```
Also works with: `ALBRequestCountPerTarget`, `ASGAverageNetworkIn/Out`, or custom CloudWatch metrics.

**How it works**: ASG continuously adjusts desired capacity to keep the metric at the target. It scales out fast (multiple steps), scales in conservatively (waits to avoid thrashing).

### 2. Step Scaling
Define scaling steps based on alarm breach magnitude:
```
If CPUUtilization > 70% (moderate breach): add 2 instances
If CPUUtilization > 85% (large breach): add 5 instances
If CPUUtilization < 30%: remove 1 instance
```
More granular than target tracking. Use when you need asymmetric scaling (scale out fast, scale in slow).

### 3. Scheduled Scaling
Pre-schedule capacity changes for known traffic patterns:
```
Every weekday 08:00 UTC: set desired=10 (morning traffic)
Every weekday 22:00 UTC: set desired=2 (night reduction)
```

### 4. Predictive Scaling
Uses ML to forecast traffic and pre-scale before peaks:
- Looks at the last 14 days of metric history
- Learns weekly patterns (Monday morning spike, Friday night drop)
- Launches instances ahead of the predicted spike
- Combine with Target Tracking for reactive correction of prediction errors

**Best practice**: use Predictive + Target Tracking together for production web tiers with regular traffic patterns.

---

## Cooldown Period

After a scaling action, the cooldown prevents another scaling action from firing immediately:
- Default cooldown: 300 seconds (5 minutes)
- Too short: thrashing (constant scale out/in)
- Too long: slow to react to genuine sustained load

**Instance warmup**: the time for a new instance to be "ready" to contribute to metrics. During warmup, the new instance's metrics are not counted in aggregate. This prevents the scaling alarm from firing again before the new instances are actually serving traffic.

---

## Health Checks

ASG replaces instances that fail health checks:

| Check type | What it checks | Use when |
|---|---|---|
| **EC2 health check** | EC2 status checks (hardware/hypervisor) | Always active |
| **ELB health check** | ALB/NLB target health check passes | **Always enable when behind a load balancer** |
| **Custom health check** | Application-defined via `SetInstanceHealth` API | Application-level health (DB connectivity, etc.) |

**Always enable ELB health check** on the ASG when behind an ALB. EC2 status checks won't catch an application that is running but returning 500s.

**Health check grace period**: don't mark an instance unhealthy for the first N seconds after launch (instance is still starting). Match to your application startup time + health check interval.

---

## Instance Refresh

Rolling update mechanism for updating instances to a new AMI or launch template version:

```json
{
  "AutoScalingGroupName": "my-app-asg",
  "Strategy": "Rolling",
  "Preferences": {
    "MinHealthyPercentage": 80,
    "InstanceWarmup": 300,
    "CheckpointPercentages": [20, 50, 100],
    "CheckpointDelay": 600
  }
}
```

**Zero-downtime AMI update flow**:
1. Update launch template to new AMI version
2. `StartInstanceRefresh` with `MinHealthyPercentage=80` — replaces 20% at a time
3. ASG launches new instances (new AMI), waits for them to pass health checks
4. Terminates old instances
5. Repeat until all instances are updated

**Rollback**: if the refresh detects a health check failure above threshold, it stops and rolls back automatically (if configured).

---

## Mixed Instances Policy (Spot + On-Demand)

The most cost-effective production pattern — run stable baseline on On-Demand, overflow on Spot:

```json
{
  "MixedInstancesPolicy": {
    "InstancesDistribution": {
      "OnDemandBaseCapacity": 2,
      "OnDemandPercentageAboveBaseCapacity": 20,
      "SpotAllocationStrategy": "price-capacity-optimized"
    },
    "LaunchTemplate": {
      "LaunchTemplateSpecification": {"LaunchTemplateId": "lt-xxxx", "Version": "$Latest"},
      "Overrides": [
        {"InstanceType": "m7g.large"},
        {"InstanceType": "m6g.large"},
        {"InstanceType": "m7i.large"},
        {"InstanceType": "c7g.xlarge"}
      ]
    }
  }
}
```

- `OnDemandBaseCapacity=2`: always keep 2 On-Demand instances running (baseline)
- `OnDemandPercentageAboveBaseCapacity=20`: for capacity above 2, 20% On-Demand, 80% Spot
- `SpotAllocationStrategy=price-capacity-optimized`: prioritise Spot pools with most available capacity (lowest interruption rate)
- Multiple instance types: if one Spot pool is exhausted, try others — increases availability

**Cost savings**: 60–80% reduction in compute cost for web/app tiers vs all On-Demand.

---

## Lifecycle Hooks

Pause instance launch or termination to run custom logic:

| Hook | Trigger | Use case |
|---|---|---|
| `autoscaling:EC2_INSTANCE_LAUNCHING` | Before instance enters InService | Register with service discovery, run bootstrap, warm up cache |
| `autoscaling:EC2_INSTANCE_TERMINATING` | Before instance is terminated | Drain connections, deregister from service registry, copy logs |

**Termination hook for graceful drain**:
1. ASG triggers termination
2. Lifecycle hook fires → instance enters `Terminating:Wait` state
3. Lambda receives EventBridge notification → calls application drain endpoint → waits
4. Lambda calls `CompleteLifecycleAction` → ASG proceeds to terminate
5. Total hook timeout: up to 2 hours (heartbeat extends it)

---

## Scaling for ECS and Kubernetes

ASG is used differently when running containers:

**ECS with EC2 launch type**: ASG manages EC2 instances (nodes). ECS Capacity Provider manages the desired count of the ASG based on ECS task scheduling demand. ECS Cluster Auto Scaling (CAS) integrates them — when ECS can't place tasks, CAS scales the ASG.

**EKS (Kubernetes)**: Cluster Autoscaler (CA) watches for unschedulable pods and scales the ASG backing the node group. Karpenter (newer, recommended) provisions nodes directly from EC2 APIs — faster and more instance-type flexible than CA.

---

## ASG with ALB: Full Pattern

```
Internet → Route53 → ALB (multi-AZ)
                   ├── Target Group (health check: /health, 200)
                   │         ├── Instance 1 (AZ-a) — registered by ASG
                   │         ├── Instance 2 (AZ-b)
                   │         └── Instance 3 (AZ-c)
                   └── (new instances automatically registered on launch)
                       (old instances deregistered before termination)
```

**Connection draining (deregistration delay)**: when ASG terminates an instance, ALB waits for in-flight requests to complete (default 300 seconds) before removing the target. Set this to match your max request processing time.

---

## Termination Policies

Controls which instances are terminated first on scale-in:
| Policy | Behaviour |
|---|---|
| `OldestLaunchTemplate` | Terminates instances with the oldest launch template version first |
| `OldestInstance` | Terminates the oldest instance (by launch time) |
| `NewestInstance` | Terminates the newest instance |
| `Default` | AZ balance first → oldest launch config → closest to billing hour |
| `AllocationStrategy` | Respects Spot/On-Demand balance in mixed fleet |

**Recommendation**: use `OldestLaunchTemplate` — ensures scale-in removes instances with outdated configurations, leaving the fleet on the latest AMI/template.

---

## Monitoring

| Metric | Alert condition |
|---|---|
| `GroupDesiredCapacity` | Equals `GroupMaxSize` → maxed out; consider raising max or capacity |
| `GroupInServiceInstances` | Below `GroupMinSize` → instances failing health checks |
| `GroupPendingInstances` | High + slow to decrease → slow startup (health check grace period too short) |
| `GroupTerminatingInstances` | Elevated → scale-in activity or health-check failures |
| `WarmPoolMinSize` → Warm pool size | Track warm pool readiness |
| ALB `UnHealthyHostCount` | > 0 → instances failing health checks |
| EC2 `StatusCheckFailed` | > 0 → hardware issues; ASG will replace |

**Scaling activity log**: every scaling event is logged in ASG Activity History — shows trigger, instance launched/terminated, and reason. Critical for post-incident analysis.

---

## Warm Pools

Pre-provision instances in a stopped/hibernated state so scaling out is nearly instant:

```
Warm Pool: 3 stopped instances (pre-launched, pre-configured)
Scale-out event: ASG starts a warm pool instance (seconds) instead of launching new (minutes)
```

Cost: stopped instances don't incur EC2 hourly charge (only EBS storage). Warmup time: ~30 seconds (start) vs ~3 minutes (launch+bootstrap).

Use warm pools for workloads that have slow bootstrap (JVM warmup, cache population, model loading) and need fast scale-out.

---

## Best Practices

1. **Always use Launch Templates** — versioned, feature-complete; Launch Configurations are deprecated
2. **Multi-AZ deployment** — spread across at least 3 AZs; set `AvailabilityZoneRebalancing=enabled`
3. **Mixed instances with Spot** — `price-capacity-optimized` allocation strategy; 3+ instance type overrides
4. **Target Tracking + Predictive Scaling** — reactive + proactive for stable web tiers
5. **Enable ELB health checks** — EC2 checks don't catch application failures
6. **Set health check grace period** to match startup time — prevent premature termination of starting instances
7. **Set connection draining on ALB** target group — don't terminate instances mid-request
8. **Use Instance Refresh** for AMI updates — zero-downtime rolling replacement
9. **Use lifecycle hooks** for graceful shutdown — drain connections and deregister from service discovery
10. **Monitor `GroupMaxSize` proximity** — maxing out the ceiling without alerting is a silent capacity crisis

---

## FAANG Interview Points

**"How do you achieve zero-downtime deployments with ASGs?"**: ALB + Target Group with connection draining. Instance Refresh with `MinHealthyPercentage=80`. New instances launched, pass health check, receive traffic before old instances are drained and terminated. AMI updated via Launch Template version bump.

**"How do you handle a traffic spike 2× normal for a product launch?"**: Scheduled scaling to pre-provision capacity 30 minutes before the launch. Predictive Scaling learns weekly patterns. Warm pool for instant scale-out. Target Tracking at 60% CPU for reactive corrections. Mixed Spot+On-Demand to cap cost.

**"Auto Scaling vs Kubernetes HPA"**: ASG scales EC2 nodes (infrastructure). Kubernetes HPA scales pods (application). In EKS: HPA scales pods first; when nodes are full, Karpenter/Cluster Autoscaler scales the ASG. The two layers work in concert. For ECS: ECS Cluster Auto Scaling sits between pod scheduling and ASG scaling.
