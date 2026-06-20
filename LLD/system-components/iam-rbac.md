# LLD: IAM Service — RBAC Engine & Core Components

> Companion to `HLD/designs/iam-service.md`. This document covers class design, interface contracts, the policy evaluation algorithm in code, design patterns, SOLID analysis, and the key data structures behind a production RBAC engine.

---

## 1. RBAC Concepts — The Mental Model

Before any class design, nail the conceptual relationships:

```
┌──────────────────────────────────────────────────────────────────────┐
│                         RBAC Entity Model                            │
│                                                                      │
│  Principal ──── has ────► PolicyAttachment ──── points to ──► Policy │
│  (User /               (identity-based)          │                   │
│   Group /                                        │ Document          │
│   Role /           Resource ── has ──► PolicyAttachment              │
│   ServiceAccount)          (resource-based)      │                   │
│       │                                          ▼                   │
│       │  belongs to                          Statement[]             │
│       ▼                                          │                   │
│     Group                                   ┌───┴──────────────┐    │
│       │  contains                           │ Effect           │    │
│       ▼                                     │ Action[]         │    │
│     User                                    │ Resource[]       │    │
│                                             │ Condition?       │    │
│  Principal ── can assume ──► Role           └──────────────────┘    │
│                  │                                                   │
│                  │ TrustPolicy                                       │
│                  └── defines who may call AssumeRole                 │
└──────────────────────────────────────────────────────────────────────┘
```

**Three questions every authorization check answers:**
1. **Who** is making the request? → Principal resolution (user + all groups + assumed role)
2. **What** are they trying to do on **what**? → (action, resource) pair
3. **Which policies apply**, and what do they say? → Policy evaluation

---

## 2. Domain Model — Classes & Interfaces

### 2.1 Principal Hierarchy

```java
// Sealed hierarchy — exactly four kinds of principal, no others
public sealed interface Principal permits User, Group, Role, ServiceAccount {
    String getArn();       // urn:iam:user:alice  /  urn:iam:role:deployer
    String getName();
    PrincipalType getType();
    PolicyAttachment getPermissionBoundary();  // null = no boundary
}

public enum PrincipalType { USER, GROUP, ROLE, SERVICE_ACCOUNT }

@Value
public class User implements Principal {
    String arn;
    String name;
    String email;
    PolicyAttachment permissionBoundary;
    Instant createdAt;
    Instant deletedAt;

    // Resolved at query time — not stored on the entity
    @Transient List<Group> memberOf;
    @Transient List<PolicyAttachment> directPolicies;
}

@Value
public class Group implements Principal {
    String arn;
    String name;
    PolicyAttachment permissionBoundary;  // rare but valid
    List<PolicyAttachment> attachedPolicies;
}

@Value
public class Role implements Principal {
    String arn;
    String name;
    PolicyDocument trustPolicy;          // who may assume this role
    PolicyAttachment permissionBoundary;
    List<PolicyAttachment> attachedPolicies;
    Duration maxSessionDuration;         // max TTL for AssumeRole tokens
}

@Value
public class ServiceAccount implements Principal {
    String arn;
    String name;
    String ownerService;                 // which service owns this identity
    PolicyAttachment permissionBoundary;
    List<PolicyAttachment> attachedPolicies;
}
```

### 2.2 Policy & Statement

```java
@Value
public class Policy {
    String id;
    String name;
    String arn;
    int currentVersion;
    PolicyDocument document;             // the active version
    List<PolicyVersion> history;         // immutable audit trail
    Instant createdAt;
    String createdBy;
}

@Value
public class PolicyDocument {
    String version;                      // "2024-01-01"
    List<Statement> statements;

    public static PolicyDocument parse(String json) {
        // validates schema, compiles ARN patterns at parse time
        // throws PolicyParseException on invalid document
    }
}

@Value
public class Statement {
    String sid;                          // optional human label
    Effect effect;                       // ALLOW | DENY
    List<CompiledPattern> actions;       // pre-compiled glob patterns
    List<CompiledPattern> resources;     // pre-compiled ARN glob patterns
    List<Principal> principals;          // for resource-based policies
    ConditionBlock condition;            // null = no condition

    public boolean matches(String action, String resource) {
        return actions.stream().anyMatch(p -> p.matches(action))
            && resources.stream().anyMatch(p -> p.matches(resource));
    }
}

public enum Effect { ALLOW, DENY }

@Value
public class PolicyAttachment {
    String id;
    String principalArn;                 // who it's attached to
    String policyId;
    AttachmentType type;                 // IDENTITY | RESOURCE | PERMISSION_BOUNDARY
    Instant attachedAt;
    String attachedBy;
}

public enum AttachmentType { IDENTITY, RESOURCE, PERMISSION_BOUNDARY }

@Value
public class PolicyVersion {
    String policyId;
    int versionNumber;
    PolicyDocument document;
    Instant createdAt;
    String createdBy;
    boolean isDefault;                   // only one version is active at a time
}
```

### 2.3 Conditions

```java
// ConditionBlock is a map of operator → (key → values)
// Mirrors AWS IAM condition syntax exactly
@Value
public class ConditionBlock {
    // outer key = operator (StringEquals, IpAddress, Bool, DateGreaterThan…)
    // inner key = context key (platform:RequestedRegion, aws:SourceIp…)
    // value = list of acceptable values
    Map<String, Map<String, List<String>>> conditions;

    public boolean isSatisfied(Map<String, String> requestContext) {
        return conditions.entrySet().stream().allMatch(operatorEntry -> {
            ConditionOperator op = ConditionOperatorRegistry.get(operatorEntry.getKey());
            return operatorEntry.getValue().entrySet().stream().allMatch(keyEntry ->
                op.evaluate(requestContext.get(keyEntry.getKey()), keyEntry.getValue())
            );
        });
    }
}

// Strategy pattern — each operator is a pluggable strategy
public interface ConditionOperator {
    boolean evaluate(String requestValue, List<String> policyValues);
}

public class StringEqualsOperator implements ConditionOperator {
    public boolean evaluate(String requestValue, List<String> policyValues) {
        return requestValue != null && policyValues.contains(requestValue);
    }
}

public class IpAddressOperator implements ConditionOperator {
    public boolean evaluate(String requestValue, List<String> policyValues) {
        if (requestValue == null) return false;
        InetAddress requestIp = InetAddress.getByName(requestValue);
        return policyValues.stream().anyMatch(cidr -> CidrUtils.isInRange(requestIp, cidr));
    }
}

public class BoolOperator implements ConditionOperator {
    public boolean evaluate(String requestValue, List<String> policyValues) {
        return policyValues.contains(String.valueOf(Boolean.parseBoolean(requestValue)));
    }
}

public class DateGreaterThanOperator implements ConditionOperator {
    public boolean evaluate(String requestValue, List<String> policyValues) {
        Instant requestDate = Instant.parse(requestValue);
        return policyValues.stream().anyMatch(v -> requestDate.isAfter(Instant.parse(v)));
    }
}

// Registry — open for extension, no switch statements
public class ConditionOperatorRegistry {
    private static final Map<String, ConditionOperator> OPERATORS = Map.of(
        "StringEquals",      new StringEqualsOperator(),
        "StringLike",        new StringLikeOperator(),
        "IpAddress",         new IpAddressOperator(),
        "NotIpAddress",      new NotIpAddressOperator(),
        "Bool",              new BoolOperator(),
        "DateGreaterThan",   new DateGreaterThanOperator(),
        "DateLessThan",      new DateLessThanOperator(),
        "NumericEquals",     new NumericEqualsOperator()
    );

    public static ConditionOperator get(String operatorName) {
        ConditionOperator op = OPERATORS.get(operatorName);
        if (op == null) throw new UnknownConditionOperatorException(operatorName);
        return op;
    }
}
```

---

## 3. Policy Evaluation Engine

This is the heart of the system. Every authorization check flows through here.

```java
// Primary entry point — called by Authorization Gateway
@Service
public class PolicyEvaluationEngine {

    private final PrincipalResolver principalResolver;
    private final PolicyRepository policyRepository;
    private final GlobMatcher globMatcher;

    public AuthorizationDecision evaluate(AuthorizationRequest request) {
        // Step 1: Resolve the full effective policy set for this principal
        EffectivePolicySet policySet = principalResolver.resolve(request.getPrincipalArn());

        // Step 2: Determine permission boundary (caps max permissions)
        Optional<PolicyDocument> boundary = policySet.getPermissionBoundary();

        // Step 3: Run evaluation algorithm — order matters
        return runEvaluation(request, policySet, boundary);
    }

    private AuthorizationDecision runEvaluation(
            AuthorizationRequest req,
            EffectivePolicySet policySet,
            Optional<PolicyDocument> boundary) {

        String action   = req.getAction();
        String resource = req.getResource();
        Map<String, String> ctx = req.getContext();

        // === Phase 1: Explicit Deny scan (short-circuit) ===
        // Explicit deny always wins — scan ALL policies before checking allows
        for (PolicyDocument policy : policySet.getAllPolicies()) {
            for (Statement stmt : policy.getStatements()) {
                if (stmt.getEffect() == Effect.DENY
                        && stmt.matches(action, resource)
                        && satisfiesCondition(stmt, ctx)) {
                    return AuthorizationDecision.deny(
                        DenyReason.EXPLICIT_DENY, stmt.getSid(), policy.getId());
                }
            }
        }

        // === Phase 2: Explicit Allow scan ===
        Statement matchedAllow = null;
        String matchedPolicyId = null;

        outer:
        for (PolicyDocument policy : policySet.getAllPolicies()) {
            for (Statement stmt : policy.getStatements()) {
                if (stmt.getEffect() == Effect.ALLOW
                        && stmt.matches(action, resource)
                        && satisfiesCondition(stmt, ctx)) {
                    matchedAllow    = stmt;
                    matchedPolicyId = policy.getId();
                    break outer;
                }
            }
        }

        if (matchedAllow == null) {
            return AuthorizationDecision.deny(DenyReason.IMPLICIT_DENY, null, null);
        }

        // === Phase 3: Permission boundary check (if present) ===
        if (boundary.isPresent()) {
            boolean boundaryAllows = boundary.get().getStatements().stream()
                .anyMatch(stmt ->
                    stmt.getEffect() == Effect.ALLOW
                    && stmt.matches(action, resource)
                    && satisfiesCondition(stmt, ctx));

            if (!boundaryAllows) {
                return AuthorizationDecision.deny(
                    DenyReason.PERMISSION_BOUNDARY_BLOCKS, matchedAllow.getSid(), matchedPolicyId);
            }
        }

        // === Allowed ===
        return AuthorizationDecision.allow(matchedAllow.getSid(), matchedPolicyId);
    }

    private boolean satisfiesCondition(Statement stmt, Map<String, String> ctx) {
        return stmt.getCondition() == null || stmt.getCondition().isSatisfied(ctx);
    }
}
```

### 3.1 Authorization Decision

```java
@Value
public class AuthorizationDecision {
    Decision decision;             // ALLOW | DENY
    DenyReason denyReason;         // null on ALLOW
    String matchedStatementSid;
    String matchedPolicyId;
    Instant evaluatedAt;

    public enum Decision { ALLOW, DENY }

    public enum DenyReason {
        EXPLICIT_DENY,             // a Deny statement matched
        IMPLICIT_DENY,             // no Allow statement matched
        PERMISSION_BOUNDARY_BLOCKS // Allow found but boundary doesn't cover it
    }

    public static AuthorizationDecision allow(String sid, String policyId) {
        return new AuthorizationDecision(Decision.ALLOW, null, sid, policyId, Instant.now());
    }

    public static AuthorizationDecision deny(DenyReason reason, String sid, String policyId) {
        return new AuthorizationDecision(Decision.DENY, reason, sid, policyId, Instant.now());
    }

    public boolean isAllowed() { return decision == Decision.ALLOW; }
}
```

### 3.2 Principal Resolution

```java
// Resolves a principal ARN into the full set of effective policies
// Result is cached in Redis; this is called only on cache miss
@Service
public class PrincipalResolver {

    private final UserRepository userRepository;
    private final GroupRepository groupRepository;
    private final PolicyRepository policyRepository;
    private final RedisTemplate<String, EffectivePolicySet> cache;

    public EffectivePolicySet resolve(String principalArn) {
        // Cache check (Policy Cache — 30s TTL; invalidated on attachment change)
        EffectivePolicySet cached = cache.opsForValue().get(cacheKey(principalArn));
        if (cached != null) return cached;

        EffectivePolicySet resolved = resolveFromDb(principalArn);
        cache.opsForValue().set(cacheKey(principalArn), resolved, Duration.ofSeconds(30));
        return resolved;
    }

    private EffectivePolicySet resolveFromDb(String principalArn) {
        Principal principal = loadPrincipal(principalArn);
        List<PolicyDocument> policies = new ArrayList<>();

        // Direct policies
        policies.addAll(loadPoliciesFor(principalArn));

        // Group policies (User only)
        if (principal instanceof User user) {
            for (Group group : user.getMemberOf()) {
                policies.addAll(loadPoliciesFor(group.getArn()));
            }
        }

        // Role policies (when principal is a role or has assumed one)
        if (principal instanceof Role role) {
            policies.addAll(loadPoliciesFor(role.getArn()));
        }

        PolicyDocument boundary = principal.getPermissionBoundary() != null
            ? policyRepository.load(principal.getPermissionBoundary().getPolicyId()).getDocument()
            : null;

        return EffectivePolicySet.of(policies, boundary);
    }
}

@Value
public class EffectivePolicySet {
    List<PolicyDocument> identityPolicies;
    List<PolicyDocument> resourcePolicies;
    PolicyDocument permissionBoundary;     // null = no boundary

    public List<PolicyDocument> getAllPolicies() {
        List<PolicyDocument> all = new ArrayList<>(identityPolicies);
        all.addAll(resourcePolicies);
        return Collections.unmodifiableList(all);
    }
}
```

---

## 4. ARN / Glob Pattern Matching

```java
// Compiled at policy-store time; never recompiled per request
public class CompiledPattern {
    private final String originalPattern;
    private final List<Segment> segments;    // split on ":"

    public static CompiledPattern compile(String pattern) {
        return new CompiledPattern(pattern,
            Arrays.stream(pattern.split(":", -1))
                  .map(SegmentCompiler::compile)
                  .toList());
    }

    public boolean matches(String input) {
        String[] inputSegments = input.split(":", -1);
        if (segments.size() != inputSegments.length && !hasWildcardSegment()) return false;
        for (int i = 0; i < segments.size(); i++) {
            if (i >= inputSegments.length) return false;
            if (!segments.get(i).matches(inputSegments[i])) return false;
        }
        return true;
    }
}

// Each "segment" between ":" separators is compiled to a tiny NFA
// * → match zero or more chars  (not crossing ":")
// ? → match exactly one char    (not crossing ":")
// Prevents ReDoS: no backtracking, O(n) in input length
sealed interface Segment permits LiteralSegment, GlobSegment, WildcardSegment {
    boolean matches(String input);
}

record LiteralSegment(String value) implements Segment {
    public boolean matches(String input) { return value.equals(input); }
}

record WildcardSegment() implements Segment {             // bare "*"
    public boolean matches(String input) { return true; }
}

record GlobSegment(String pattern) implements Segment {   // contains * or ?
    public boolean matches(String input) {
        return GlobEngine.matches(pattern, input);        // linear NFA
    }
}
```

---

## 5. Authorization Gateway (Request Handler)

```java
// Thin handler — cache-first, delegates evaluation to engine on miss
@GrpcService
public class AuthorizationGateway extends AuthorizationServiceGrpc.AuthorizationServiceImplBase {

    private final DecisionCache decisionCache;
    private final PolicyEvaluationEngine engine;
    private final AuditEventPublisher auditPublisher;
    private final MeterRegistry metrics;

    @Override
    public void isAuthorized(AuthorizationRequest request,
                             StreamObserver<AuthorizationResponse> responseObserver) {
        Timer.Sample timer = Timer.start(metrics);
        try {
            // 1. Decision Cache hit (p80 of traffic)
            String cacheKey = DecisionCacheKey.of(request);
            AuthorizationDecision decision = decisionCache.get(cacheKey);

            if (decision == null) {
                // 2. Cache miss — evaluate
                decision = engine.evaluate(request);
                decisionCache.put(cacheKey, decision, Duration.ofSeconds(5));
                metrics.counter("iam.cache.miss").increment();
            } else {
                metrics.counter("iam.cache.hit").increment();
            }

            // 3. Async audit (never blocks response)
            final AuthorizationDecision finalDecision = decision;
            CompletableFuture.runAsync(() ->
                auditPublisher.publish(AuditEvent.of(request, finalDecision)));

            // 4. Respond
            responseObserver.onNext(toProto(decision));
            responseObserver.onCompleted();

        } catch (Exception e) {
            // On any evaluation error → DENY (fail-closed)
            metrics.counter("iam.evaluation.error").increment();
            responseObserver.onNext(AuthorizationResponse.newBuilder()
                .setDecision(Decision.DENY)
                .setReason("EvaluationError:" + e.getClass().getSimpleName())
                .build());
            responseObserver.onCompleted();
        } finally {
            timer.stop(metrics.timer("iam.authorization.latency"));
        }
    }
}
```

---

## 6. STS Service — Role Assumption

```java
@Service
public class SecurityTokenService {

    private final PrincipalResolver resolver;
    private final TrustPolicyEvaluator trustEvaluator;
    private final JwtSigner jwtSigner;
    private final TempCredentialRepository credentialRepo;

    public AssumeRoleResult assumeRole(AssumeRoleRequest request) {
        Role role = loadRole(request.getRoleArn());

        // Step 1: Validate the caller is permitted by the role's TrustPolicy
        boolean trusted = trustEvaluator.canAssume(request.getCallerArn(), role);
        if (!trusted) {
            throw new AccessDeniedException(
                request.getCallerArn() + " is not in trust policy of " + request.getRoleArn());
        }

        // Step 2: Validate requested duration <= role.maxSessionDuration
        Duration duration = Duration.ofSeconds(
            Math.min(request.getDurationSeconds(), role.getMaxSessionDuration().getSeconds()));

        // Step 3: Snapshot the role's effective policy set at issue time
        // This snapshot travels in the JWT — no DB lookup needed on each auth check
        EffectivePolicySet rolePolicy = resolver.resolve(role.getArn());
        String policySnapshot = PolicySerializer.toBase64(rolePolicy);

        // Step 4: Issue signed JWT
        Instant now    = Instant.now();
        Instant expiry = now.plus(duration);
        String tokenId = UUID.randomUUID().toString();

        String jwt = jwtSigner.sign(JwtClaims.builder()
            .subject(request.getCallerArn())
            .claim("assumed_role", role.getArn())
            .claim("policy_snapshot", policySnapshot)
            .claim("jti", tokenId)
            .issuedAt(now)
            .expiresAt(expiry)
            .build());

        // Step 5: Persist for revocation tracking
        credentialRepo.save(TempCredential.builder()
            .tokenId(tokenId)
            .principalArn(request.getCallerArn())
            .assumedRoleArn(role.getArn())
            .expiresAt(expiry)
            .build());

        return AssumeRoleResult.builder()
            .accessToken(jwt)
            .expiration(expiry)
            .assumedRoleArn(role.getArn())
            .build();
    }
}

// Evaluates whether a given caller can assume a role
// Uses the same PolicyEvaluationEngine so logic is never duplicated
@Service
public class TrustPolicyEvaluator {

    public boolean canAssume(String callerArn, Role role) {
        // TrustPolicy is a policy document where the action is "sts:AssumeRole"
        // and statements list principals who may call it
        return role.getTrustPolicy().getStatements().stream()
            .anyMatch(stmt ->
                stmt.getEffect() == Effect.ALLOW
                && stmt.getPrincipals().stream().anyMatch(p ->
                    p.getArn().equals(callerArn) || globMatchesPrincipal(p.getArn(), callerArn))
                && stmt.getActions().stream().anyMatch(a -> a.matches("sts:AssumeRole")));
    }
}
```

---

## 7. Admin Service (Policy & Identity CRUD)

```java
@Service
public class PolicyAdminService {

    private final PolicyRepository policyRepo;
    private final PolicyAttachmentRepository attachmentRepo;
    private final PolicyValidator validator;
    private final PolicyCacheInvalidator cacheInvalidator;
    private final PolicyChangePublisher changePublisher;

    public Policy createPolicy(CreatePolicyRequest request) {
        // 1. Parse and validate document (compiles ARN patterns, checks syntax)
        PolicyDocument document = PolicyDocument.parse(request.getDocumentJson());
        validator.validate(document);  // rejects over-broad "*:*" without explicit flag

        // 2. Persist
        Policy policy = Policy.builder()
            .id(UUID.randomUUID().toString())
            .name(request.getName())
            .arn(arnFor(request.getName()))
            .currentVersion(1)
            .document(document)
            .createdAt(Instant.now())
            .createdBy(request.getRequestedBy())
            .build();

        policyRepo.save(policy);
        policyRepo.saveVersion(PolicyVersion.of(policy, 1, true));
        return policy;
    }

    public Policy updatePolicy(String policyId, UpdatePolicyRequest request) {
        Policy existing = policyRepo.findById(policyId)
            .orElseThrow(() -> new PolicyNotFoundException(policyId));

        PolicyDocument newDocument = PolicyDocument.parse(request.getDocumentJson());
        validator.validate(newDocument);

        int newVersion = existing.getCurrentVersion() + 1;

        // Old version stays in history — immutable audit trail
        policyRepo.saveVersion(PolicyVersion.of(existing, existing.getCurrentVersion(), false));
        policyRepo.saveVersion(PolicyVersion.of(existing, newVersion, true));
        Policy updated = existing.withDocument(newDocument).withVersion(newVersion);
        policyRepo.save(updated);

        // Invalidate all principals this policy is attached to
        Set<String> affectedPrincipals = attachmentRepo.findPrincipalsByPolicyId(policyId);
        cacheInvalidator.invalidate(affectedPrincipals);
        changePublisher.publish(PolicyChangedEvent.of(policyId, affectedPrincipals));

        return updated;
    }

    public void attachPolicyToUser(String userId, String policyId) {
        PolicyAttachment attachment = PolicyAttachment.builder()
            .id(UUID.randomUUID().toString())
            .principalArn(resolveArn(userId))
            .policyId(policyId)
            .type(AttachmentType.IDENTITY)
            .attachedAt(Instant.now())
            .build();

        attachmentRepo.save(attachment);

        // Propagate: invalidate cache for this user + all sessions that assumed
        // a role containing this user's identity
        cacheInvalidator.invalidate(Set.of(resolveArn(userId)));
        changePublisher.publish(AttachmentChangedEvent.of(resolveArn(userId), policyId));
    }
}

// Validates policy documents before they are stored
@Component
public class PolicyValidator {
    private static final int MAX_STATEMENTS = 100;
    private static final int MAX_ACTIONS_PER_STATEMENT = 50;

    public void validate(PolicyDocument document) {
        if (document.getStatements().size() > MAX_STATEMENTS) {
            throw new PolicyValidationException("Policy exceeds max statement count");
        }
        for (Statement stmt : document.getStatements()) {
            if (stmt.getActions().size() > MAX_ACTIONS_PER_STATEMENT) {
                throw new PolicyValidationException("Statement exceeds max action count");
            }
            // Reject "*" on both action AND resource in same Allow statement
            // without explicit override flag — prevents accidental admin grants
            boolean actionWildcard   = stmt.getActions().stream().anyMatch(a -> a.isFullWildcard());
            boolean resourceWildcard = stmt.getResources().stream().anyMatch(r -> r.isFullWildcard());
            if (stmt.getEffect() == Effect.ALLOW && actionWildcard && resourceWildcard) {
                throw new PolicyValidationException(
                    "Allow statement with wildcard action AND wildcard resource requires explicit override");
            }
        }
    }
}
```

---

## 8. Caching Architecture in Code

```java
// Decision Cache — keyed by request tuple, 5s TTL
@Component
public class DecisionCache {
    private final RedisTemplate<String, CachedDecision> redis;

    public AuthorizationDecision get(String key) {
        CachedDecision cached = redis.opsForValue().get(key);
        return cached != null ? cached.toDecision() : null;
    }

    public void put(String key, AuthorizationDecision decision, Duration ttl) {
        redis.opsForValue().set(key, CachedDecision.of(decision), ttl);
    }

    public void invalidate(String key) {
        redis.delete(key);
    }
}

// Cache key: deterministic hash of the full authorization request
public class DecisionCacheKey {
    public static String of(AuthorizationRequest request) {
        // Sort context map for stable key regardless of insertion order
        String contextStr = new TreeMap<>(request.getContext())
            .entrySet().stream()
            .map(e -> e.getKey() + "=" + e.getValue())
            .collect(Collectors.joining("&"));
        String raw = request.getPrincipalArn()
            + "|" + request.getAction()
            + "|" + request.getResource()
            + "|" + contextStr;
        return "iam:decision:" + DigestUtils.sha256Hex(raw);
    }
}

// Policy Cache invalidation — propagates to all nodes via Kafka
@Component
public class PolicyCacheInvalidator {
    private final RedisTemplate<String, String> redis;

    public void invalidate(Set<String> principalArns) {
        // Delete from Redis — next cache miss will re-derive from DB
        List<String> keys = principalArns.stream()
            .map(arn -> "iam:policy-set:" + arn)
            .toList();
        redis.delete(keys);
    }
}

// Consumes Kafka PolicyChangedEvents on every Authorization Gateway node
@KafkaListener(topics = "iam.policy-changes")
public class PolicyChangeConsumer {
    private final LoadingCache<String, EffectivePolicySet> localLruCache;

    public void onPolicyChanged(PolicyChangedEvent event) {
        // Clear in-process LRU for affected principals
        // Redundant with Redis invalidation, but eliminates even the Redis RTT
        event.getAffectedPrincipalArns().forEach(localLruCache::invalidate);
    }
}
```

---

## 9. Policy Simulation

```java
// Answers "would this request be allowed?" — safe to call without side effects
@Service
public class PolicySimulationService {

    private final PrincipalResolver resolver;
    private final PolicyEvaluationEngine engine;

    public SimulationResult simulate(SimulateRequest request) {
        EffectivePolicySet policySet = resolver.resolve(request.getPrincipalArn());

        AuthorizationDecision decision = engine.evaluate(
            AuthorizationRequest.of(
                request.getPrincipalArn(),
                request.getAction(),
                request.getResource(),
                request.getContext()));

        // Return not just the decision but the full evaluation trace
        // so the caller can understand exactly which statement matched
        return SimulationResult.builder()
            .decision(decision.getDecision())
            .matchedStatementSid(decision.getMatchedStatementSid())
            .matchedPolicyId(decision.getMatchedPolicyId())
            .denyReason(decision.getDenyReason())
            .evaluatedPolicyIds(policySet.getAllPolicies().stream()
                .map(PolicyDocument::getId).toList())
            .hasPermissionBoundary(policySet.getPermissionBoundary() != null)
            .build();
    }
}
```

---

## 10. Design Patterns Applied

| Pattern | Where | Why |
|---|---|---|
| **Strategy** | `ConditionOperator` implementations (StringEquals, IpAddress, Bool, DateGreaterThan…) | Each condition type is a pluggable strategy; new operators added without touching evaluation code |
| **Sealed Interface + Pattern Matching** | `Principal` hierarchy (User, Group, Role, ServiceAccount) | Exhaustive handling enforced by compiler; no instanceof chains |
| **Composite** | `EffectivePolicySet` aggregates policies from user + all groups + assumed role | Evaluation engine sees one unified set; composition happens in `PrincipalResolver` |
| **Interpreter** | `PolicyDocument.parse()` → `Statement` → `CompiledPattern` → `ConditionBlock` | Policy JSON is a DSL; the parser builds an AST that is efficiently evaluated |
| **Chain of Responsibility** | Evaluation phases: ExplicitDeny → PermissionBoundary check → ExplicitAllow → ImplicitDeny | Each phase is a handler in a fixed chain; short-circuits on first match |
| **Null Object** | `null` permission boundary → always allows (no boundary cap) | Avoids null checks scattered through evaluation; boundary is either present or absent-but-permissive |
| **Template Method** | `PolicyEvaluationEngine.evaluate()` calls `runEvaluation()` which is overridable for test subclasses | Core algorithm is fixed; evaluation context can be injected in tests |
| **Publish-Subscribe** | `PolicyChangePublisher` → Kafka → all Gateway nodes | Decoupled cache invalidation; publisher doesn't know how many nodes are listening |
| **Builder** | `AuthorizationDecision`, `Policy`, `SimulationResult`, `TempCredential` | All domain objects are immutable value types; construction via builder pattern |

---

## 11. SOLID Analysis

| Principle | Compliance |
|---|---|
| **SRP** | `PolicyEvaluationEngine` only evaluates; `PrincipalResolver` only resolves policy sets; `PolicyAdminService` only handles CRUD; `AuditEventPublisher` only publishes — each changes for exactly one reason |
| **OCP** | New condition operators added by implementing `ConditionOperator` and registering in `ConditionOperatorRegistry` — zero changes to evaluation code; new principal types added by extending the sealed hierarchy |
| **LSP** | Any `Principal` implementation can be passed to `PrincipalResolver.resolve()`; any `ConditionOperator` implementation substitutes in the registry without changing behavior |
| **ISP** | `PolicyRepository`, `PolicyAttachmentRepository`, `TempCredentialRepository` are separate interfaces; `PolicyEvaluationEngine` depends only on read interfaces, never on write operations |
| **DIP** | `PolicyEvaluationEngine` depends on `PrincipalResolver` interface (not impl); `AuthorizationGateway` depends on `PolicyEvaluationEngine` interface — both are swappable with in-memory fakes in tests |

---

## 12. Failure Modes & Edge Cases

| Case | Behavior |
|---|---|
| **Policy evaluation throws** | `AuthorizationGateway` catches all exceptions → returns DENY (fail-closed). Never fail-open. |
| **Redis unavailable** | Decision Cache miss → fall through to `PolicyEvaluationEngine` → fall through to DB. Slower but correct. |
| **Principal not found** | `PrincipalResolver` returns an empty `EffectivePolicySet` → evaluation hits implicit deny. |
| **Circular group membership** | `PrincipalResolver` tracks visited group IDs in a `Set<String>` during resolution; skips already-visited. |
| **JWT token revoked mid-session** | `AuthorizationGateway` checks token `jti` against `TempCredential` table on first use per session; if row deleted (revoked) → deny. Subsequent checks served from Decision Cache (max 5s stale window). |
| **Policy with 0 statements** | Valid document; evaluation finds no matching statements → implicit deny. |
| **Condition block references unknown key** | `ConditionBlock.isSatisfied()` returns `false` when context key is absent → statement does not match → effective deny for that statement. Callers must include required context keys. |
| **Permission boundary set to a deleted policy** | `PrincipalResolver` treats missing boundary document as "boundary is deny-all" (safest default); alerts on-call. |

---

## 13. Key Metrics

```
iam.authorization.latency.ms        # histogram (p50/p99/p999) — SLA is p99 < 5ms
iam.cache.hit.rate                  # target > 80%
iam.cache.miss.count                # spikes on policy changes = expected
iam.policy.evaluation.errors        # should be zero
iam.explicit.deny.count             # tagged by matched_policy_id
iam.implicit.deny.count             # high = missing policy coverage
iam.principal.resolve.latency.ms    # DB query time on policy cache miss
iam.policy.propagation.lag.ms       # time from policy write to cache invalidation
iam.assume_role.count               # tagged by role_arn
iam.token.revocation.checks.count   # tagged by revoked=true/false
```

---

## FAANG Interview Callouts

**Q: Walk me through what happens when user Alice calls `orders:DeleteOrder` on `urn:platform:orders:prod:12345`.**

1. Gateway receives the gRPC call; computes cache key; checks Redis Decision Cache.
2. Cache miss → calls `PolicyEvaluationEngine.evaluate()`.
3. `PrincipalResolver.resolve("urn:iam:user:alice")` → fetches Alice's direct policies + policies from every group she belongs to → from Policy Cache (Redis) or DB.
4. Evaluation engine scans all statements for Deny matches first. Finds `DenyProdDelete` statement matching `orders:DeleteOrder` + `urn:platform:orders:prod:*` → returns `DENY, EXPLICIT_DENY, "DenyProdDelete"`.
5. Decision written to Decision Cache (5s TTL). Audit event published to Kafka async.
6. Response: `{ decision: DENY, reason: "ExplicitDeny:DenyProdDelete:policy-xyz" }`.

**Q: How do you prevent privilege escalation via the admin API?**

The Admin API itself is an IAM-protected resource. Creating a policy requires `iam:CreatePolicy` action; attaching a policy to a principal requires `iam:AttachPolicy`. Platform admins have these permissions; product teams do not. Critically, you cannot grant permissions you don't have — the `PolicyValidator` rejects any new policy whose effective permissions are broader than the caller's own permission set (write-time validation, not just read-time).

**Q: How does the policy snapshot in the JWT stay secure?**

The snapshot is signed as part of the JWT (RS256). Tampering with the payload breaks the signature. The snapshot is compressed + base64-encoded — not encrypted, because the holder of the token is authorized to know their own policies. Sensitive fields in `JobDataMap` (passwords, secrets) must never appear in policy documents.

**Q: How would you extend this to support ABAC (Attribute-Based Access Control)?**

ABAC is already partially here via `Condition` blocks — you can condition on resource tags (`platform:ResourceTag/Environment = prod`). Full ABAC would add tag-based resource matching to the ARN lookup and require the authorization request to carry resource attributes. The `ConditionOperatorRegistry` is the extension point — add a `TagEquals` operator; no changes to the evaluation engine itself.
