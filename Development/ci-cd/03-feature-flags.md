# Feature Flags (Feature Toggles)

## The Core Problem

Feature flags decouple **deployment** from **release**. Without them, every deployment is also a release — the new code is live the moment it's deployed. With flags, you can:

- Ship incomplete features to production (dark) while they're still in development
- Release features to 1% of users before 100%
- Kill a feature instantly without a redeploy (kill switch)
- Run A/B experiments independently of deployment cadence

**At Meta**: every significant feature ships behind a flag. The binary containing the code is deployed weeks before users ever see it. This is how they maintain >1 deploy/day velocity with 3B users.

---

## Flag Taxonomy

### By Lifecycle

| Type | Lifespan | Purpose | Example |
|------|----------|---------|---------|
| Release Toggle | Days–weeks | Hide incomplete feature until ready | New checkout flow |
| Experiment Toggle | Days–months | A/B test two implementations | Algorithm variant |
| Ops Toggle | Weeks–permanent | Performance or ops control | "disable expensive aggregation" |
| Permission Toggle | Permanent | Feature access by user tier | Premium feature gate |
| Kill Switch | Emergency use | Instant feature disable | "disable video encoding if infra is down" |

**Principal insight**: flags accumulate. Without governance, you end up with 2,000 flags after 3 years, half of which nobody knows the purpose of. Define flag lifecycle at creation time and enforce it.

---

## Architecture of a Feature Flag System

```
                    ┌───────────────────────────────┐
                    │        Flag Control Plane      │
                    │  (UI, API, targeting rules,    │
                    │   rollout %, user segments)    │
                    └───────────────┬───────────────┘
                                    │ flag config (JSON/Protobuf)
                                    ▼
                    ┌───────────────────────────────┐
                    │      Config Distribution       │
                    │  (push via SSE/WebSocket or    │
                    │   pull with short TTL cache)   │
                    └───────────────┬───────────────┘
                                    │ sub-100ms propagation
                                    ▼
          ┌─────────────────────────────────────────────────┐
          │                   SDK (in-process)              │
          │  evaluate(flagKey, context) → boolean/variant   │
          │  local cache + background refresh               │
          └─────────────────────────────────────────────────┘
                    │
          ┌─────────▼─────────┐
          │   Application      │
          │  if (ff.enabled(   │
          │   "new-checkout")) │
          └───────────────────┘
```

### Evaluation happens in the SDK (in-process)

Never make an HTTP call per flag evaluation. That adds latency to every request and creates a single point of failure.

The SDK:
1. Downloads flag config on startup
2. Refreshes via push (SSE) or poll (30s–2min TTL)
3. Evaluates locally using targeting rules
4. Falls back to default if config is unavailable

---

## Flag Evaluation: Targeting Rules

```
evaluate(flagKey="new-checkout", context={userId, email, country, plan}) → variant

Rules (evaluated in order, first match wins):
  1. if userId IN [override_list] → ON          (internal dogfooding)
  2. if email ENDS_WITH "@company.com" → ON     (employee test)
  3. if country == "US" AND rollout_% < 10 → ON (geo-based rollout)
  4. default → OFF
```

### Deterministic rollout with consistent hashing

For percentage-based rollout, you need consistent assignment — the same user should always get the same variant.

```python
def assign_variant(user_id: str, flag_key: str, rollout_pct: float) -> bool:
    # Hash the user+flag combination to get a stable bucket
    hash_val = int(hashlib.md5(f"{flag_key}:{user_id}".encode()).hexdigest(), 16)
    bucket = hash_val % 10000  # 0–9999
    return bucket < (rollout_pct * 100)  # rollout_pct=0.05 → bucket < 500
```

**Why include the flag key in the hash?** Without it, the same 5% of users gets every feature — they become unwitting guinea pigs. Including the flag key distributes different users for different flags.

---

## Flag Lifecycle Management

### Problem: Flag Debt

Flags accumulate. Stale flags create:
- Dead code paths that confuse readers
- Testing matrix explosion (2^n flag combinations)
- Operational risk (what does this flag do again?)

### Solution: Lifecycle-enforced flags

At creation time, define:

```yaml
flag:
  key: "new-checkout-v2"
  type: release
  owner: "checkout-team"
  created: "2026-01-15"
  expires: "2026-03-01"   # mandatory for release/experiment flags
  default_off: true
  jira: "CART-1234"
```

Automated enforcement:
- CI check: fail build if expired flag is evaluated anywhere in code
- Weekly report: flags expiring in 14 days, owners notified
- Flag removal: automated PR to remove flag + dead code branch when expired

**Platform teams at FAANG** track flag debt as a metric. > 30% stale flags = team health issue.

---

## Kill Switches

A kill switch is a flag designed for emergency use — to disable a feature that's causing incidents.

Design requirements:
1. **Sub-5-second propagation**: SDK must receive flag change within 5 seconds
2. **No service restart required**: update must take effect in running process
3. **Granular targeting**: kill per region, not globally if possible
4. **Audit log**: who toggled it, when, why
5. **Works when the flag service is down**: default to safe state (feature off)

```java
// Kill switch pattern
if (!featureFlags.isEnabled("video-encoding")) {
    // Return cached result or degrade gracefully
    return FallbackResponse.degraded("video encoding temporarily disabled");
}
// Normal path
return videoEncoder.encode(request);
```

**Common mistake**: kill switch that requires a deployment to activate. That's just a conditional — not a kill switch.

---

## Ops Flags: Circuit Breaker via Flag

Use ops flags as manual circuit breakers for expensive operations:

```java
// Flag: "enable-expensive-recommendations"
// Default: true (on)
// Toggle: off during traffic spikes to protect DB
if (featureFlags.isEnabled("enable-expensive-recommendations")) {
    return recommendationService.getPersonalized(userId);  // expensive ML call
} else {
    return recommendationService.getPopular();  // cheap cached result
}
```

At Netflix and Twitter, ops engineers have dashboards to toggle these during incidents without waiting for an on-call engineer to find and flip a config.

---

## Testing with Feature Flags

### The combinatorial explosion problem

With N binary flags, you have 2^N possible states. Testing all combinations is impossible.

**Mitigation**:
1. Test each flag in isolation (flag ON, flag OFF)
2. Only test combinations for flags known to interact
3. Integration tests always run with both states: `@ParameterizedTest`

```java
@ParameterizedTest
@ValueSource(booleans = {true, false})
void testCheckout_withNewCheckoutFlag(boolean flagEnabled) {
    featureFlags.override("new-checkout", flagEnabled);
    // test both paths
}
```

### Always clean up overrides after test

```java
@AfterEach
void cleanup() {
    featureFlags.resetOverrides();
}
```

---

## Feature Flag Vendors vs. Build vs. Config

| Approach | Pros | Cons | When |
|----------|------|------|------|
| Build in-house | Full control, no vendor dependency | Expensive to build well | > 1000 eng, flag volume justifies it |
| LaunchDarkly / Statsig | Battle-tested, fast | Cost, vendor dependency, data leaves your infra | < 500 eng, moving fast |
| ConfigMap / env vars | Simple, no infra | No targeting rules, slow propagation, requires restart | Not recommended for feature flags |
| Open-source (Unleash, Flagsmith) | No vendor lock, free | Self-hosted, ops burden | Mid-size, privacy requirements |

**FAANG uses in-house**: Meta has GateKeeper, Google has various internal systems. At that scale, the flag system is itself a mission-critical service with its own SRE team.

---

## FAANG Interview Callouts

**Q: How would you design a feature flag system that can evaluate 10M flags/sec with < 1ms latency?**

- Evaluation must be in-process (no network hop)
- SDK holds flag config in memory, refreshed via event stream (SSE/gRPC streaming)
- Config size: 10K flags × 1KB each = ~10MB in memory (acceptable)
- Evaluation: hash lookup + targeting rule evaluation = microseconds
- Propagation: SSE push from control plane → all SDK instances → < 5 seconds

**Q: A flag is stuck ON and can't be toggled because the flag service is down. What do you do?**

This is a flag service reliability incident. Your SDK must handle it:
1. Cache last known good state in memory + local file
2. Use cached state when flag service is unreachable
3. Default to `false` (feature off) if no cache exists (fail-safe)
4. Flag service SLO must be at least as high as the services that depend on it

If the flag service is down and you can't toggle off a bad feature — that's a production incident. Mitigate with: flag service multi-region, independent of app deploy, own SLO of 99.99%.

**Q: How do you prevent flag debt?**

Enforce TTL at creation. Block PRs that introduce flags without an expiry. Generate weekly "flag health" reports. Make removing a flag the default outcome — not an optional cleanup task.
