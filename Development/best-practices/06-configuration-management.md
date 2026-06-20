# Configuration Management Best Practices

## Overview
Configuration management is the discipline of separating code from configuration — environment-specific values, feature flags, secrets, and tuning parameters that change independently of deployments. Done poorly, configuration becomes a maintenance nightmare: hardcoded values scattered across code, secrets in git history, and production incidents caused by wrong configuration copied from staging. At FAANG scale, configuration management is also a safety mechanism: feature flags enable dark launches, canary rollouts, and instant rollback without redeployment.

---

## The Configuration Taxonomy

Not all configuration is equal. Different types require different storage, rotation, and access patterns:

| Type | Examples | Storage | Change frequency | Who changes it |
|---|---|---|---|---|
| **Secrets** | DB passwords, API keys, JWT signing keys, TLS certs | Secrets manager (AWS Secrets Manager, HashiCorp Vault) | Monthly rotation | Security team / automated rotation |
| **Environment config** | DB host/port, service endpoints, queue URLs | Environment variables / config server | Per deployment | Platform/DevOps team |
| **Feature flags** | Feature toggles, A/B experiment flags, kill switches | Feature flag system (LaunchDarkly, Unleash, internal) | Real-time (no deployment) | Product/engineering |
| **Application tuning** | Thread pool sizes, timeout values, batch sizes, cache TTLs | Config server / environment variables | Per deployment or runtime | Engineering |
| **Business rules** | Pricing tiers, rate limits, discount thresholds | Database / config service | Business-driven | Product team |

---

## The Twelve-Factor App: Config Principle

> **"An app's config is everything that is likely to vary between deploys (staging, production, developer environments). Apps should store config in the environment."**

```
Test: can you open-source the codebase right now, without compromising credentials?
  YES → config is correctly externalised
  NO  → secrets or environment-specific values are in the code
```

---

## Secrets Management

### Never Do This

```java
// WRONG: hardcoded secret in source code
private static final String DB_PASSWORD = "prod_p@ssw0rd_2025";
private static final String STRIPE_KEY = "sk_live_abc123";

// WRONG: secret in environment variable constructed at build time
// Dockerfile: ENV STRIPE_KEY=sk_live_abc123 ← in git history forever

// WRONG: secret in application.properties committed to git
spring.datasource.password=prod_password_here
stripe.secret.key=sk_live_abc123
```

### AWS Secrets Manager Pattern

```java
@Configuration
public class SecretsConfig {
    
    private final SecretsManagerClient secretsClient;
    
    @Bean
    public DatabaseCredentials databaseCredentials() {
        GetSecretValueResponse response = secretsClient.getSecretValue(
            GetSecretValueRequest.builder()
                .secretId("production/orders-service/db-credentials")
                .build()
        );
        
        Map<String, String> secrets = objectMapper.readValue(
            response.secretString(), new TypeReference<>() {}
        );
        
        return DatabaseCredentials.builder()
            .host(secrets.get("host"))
            .username(secrets.get("username"))
            .password(secrets.get("password"))
            .build();
    }
}
```

### Secret Rotation Pattern

```
1. AWS Secrets Manager triggers rotation Lambda (every 30/60/90 days)
2. Rotation Lambda:
   a. Creates new credentials in the database
   b. Stores new version in Secrets Manager (AWSPENDING stage)
   c. Tests new credentials
   d. Promotes AWSPENDING → AWSCURRENT
   e. Deletes old credentials after rotation window
3. Applications: use Secrets Manager SDK with caching;
   SDK refreshes automatically when secret version changes
```

```java
// CORRECT: cache secrets with automatic refresh
@Bean
public SecretsManagerCache secretsCache(SecretsManagerClient client) {
    return new SecretCache(client); // AWS SDK cache; refreshes on rotation
}
```

### HashiCorp Vault Pattern

```java
// Vault dynamic secrets: credentials generated per-service, short-lived
@Service
public class VaultDatabaseCredentialsProvider {
    
    private final VaultTemplate vaultTemplate;
    
    public DatabaseCredentials getCredentials() {
        // Vault generates a unique DB user with TTL for this service instance
        VaultResponse response = vaultTemplate.read(
            "database/creds/orders-service-role"
        );
        
        String username = (String) response.getData().get("username");
        String password = (String) response.getData().get("password");
        
        return DatabaseCredentials.of(username, password);
    }
}
```

---

## Environment-Specific Configuration

### Spring Boot Profile Pattern

```yaml
# application.yml — shared defaults
server:
  port: 8080

spring:
  application:
    name: orders-service

# application-production.yml — production overrides
spring:
  datasource:
    url: ${DB_URL}           # from environment variable
    username: ${DB_USER}     # from environment variable
    password: ${DB_PASSWORD} # from Secrets Manager via env var injection

aws:
  region: us-east-1
  sqs:
    order-events-queue: ${ORDER_EVENTS_QUEUE_URL}

# application-development.yml — local dev overrides
spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/orders_dev
    username: dev
    password: dev
  
  # H2 in-memory for tests
  h2:
    console:
      enabled: true
```

### Environment Variable Injection Pattern (Kubernetes)

```yaml
# Kubernetes deployment: inject config from ConfigMap and Secrets
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
        - name: orders-service
          image: orders-service:1.4.2
          
          env:
            # Plain config from ConfigMap
            - name: SERVER_PORT
              valueFrom:
                configMapKeyRef:
                  name: orders-config
                  key: SERVER_PORT
            
            - name: DB_URL
              valueFrom:
                configMapKeyRef:
                  name: orders-config
                  key: DB_URL
            
            # Secrets from Kubernetes Secret (or External Secrets Operator)
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: orders-db-secret
                  key: password
          
          # Health probes require correct config
          readinessProbe:
            httpGet:
              path: /health/ready
              port: 8080
            initialDelaySeconds: 30
```

### External Secrets Operator (Kubernetes + AWS Secrets Manager)

```yaml
# ExternalSecret syncs AWS Secrets Manager secrets to Kubernetes Secrets
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: orders-db-secret
spec:
  refreshInterval: 1h                           # Re-sync every hour for rotation
  secretStoreRef:
    name: aws-secrets-store
    kind: ClusterSecretStore
  target:
    name: orders-db-secret                      # Creates/updates this K8s secret
    creationPolicy: Owner
  data:
    - secretKey: password                       # K8s secret key
      remoteRef:
        key: production/orders-service/db       # AWS Secrets Manager path
        property: password                      # JSON field within the secret
```

---

## Feature Flags

### Why Feature Flags Are Critical at FAANG

- **Dark launch**: ship code to production that is not yet enabled for users
- **Canary rollout**: enable for 1% → 10% → 100% without redeployment
- **Instant kill switch**: disable a feature without redeployment or rollback
- **A/B experiments**: route user cohorts to different feature variants
- **Operational circuit breaker**: disable expensive features under load

### Feature Flag Categories

| Category | Purpose | Example | Who controls |
|---|---|---|---|
| **Release flag** | Dark launch; unfinished feature | `new_checkout_flow_enabled` | Engineering |
| **Ops flag** | Kill switch for stability | `payment_gateway_v2_enabled` | Engineering/On-call |
| **Experiment flag** | A/B test | `recommendation_algorithm_v2` | Data Science/Product |
| **Permission flag** | Premium features by tier | `bulk_export_enabled` | Product/Sales |

### LaunchDarkly Pattern (Java)

```java
@Service
public class OrderSubmissionService {
    
    private final LDClient ldClient;
    
    public OrderConfirmation submit(SubmitOrderCommand command, User user) {
        // Evaluate feature flag with user context for targeting
        LDContext context = LDContext.builder(user.id())
            .set("email", user.email())
            .set("plan", user.plan())
            .set("country", user.country())
            .build();
        
        boolean useNewPaymentFlow = ldClient.boolVariation(
            "new-payment-flow-enabled",
            context,
            false // default: off
        );
        
        if (useNewPaymentFlow) {
            return newPaymentFlow.process(command);
        } else {
            return legacyPaymentFlow.process(command);
        }
    }
}
```

### Internal Feature Flag Pattern (without LaunchDarkly)

```java
@Service
public class FeatureFlagService {
    
    private final FeatureFlagRepository flagRepository;
    private final LoadingCache<String, FeatureFlag> cache;
    
    public FeatureFlagService(FeatureFlagRepository flagRepository) {
        this.flagRepository = flagRepository;
        // Cache flags for 30 seconds; flag changes propagate within 30s
        this.cache = Caffeine.newBuilder()
            .expireAfterWrite(30, TimeUnit.SECONDS)
            .build(flagRepository::findByName);
    }
    
    public boolean isEnabled(String flagName, String userId) {
        FeatureFlag flag = cache.get(flagName);
        if (flag == null || !flag.isEnabled()) return false;
        
        // Percentage rollout: stable hash of userId → 0-100
        int bucket = Math.abs(userId.hashCode()) % 100;
        return bucket < flag.rolloutPercentage();
    }
}
```

### Flag Lifecycle Management

```
Flag states:
  OFF         → code deployed; feature not running
  CANARY      → enabled for internal users / 1-5% of production traffic
  GRADUAL     → ramping: 10% → 25% → 50% → 100%
  ON          → fully enabled for all users
  DEPRECATED  → scheduled for removal; code cleanup ticket created

Flag hygiene rules (flags are technical debt):
  - Create a JIRA/Linear ticket to remove the flag at 100% rollout
  - Remove flags within 2 sprints of reaching 100%
  - Never keep a flag for > 90 days without active use
  - Quarterly flag audit: any flag not changed in 60+ days reviewed for removal
```

---

## Configuration Validation

### Fail Fast on Misconfiguration

```java
@Configuration
@Validated
public class ApplicationConfig {
    
    @NotNull
    @Value("${payment.stripe.api-key}")
    private String stripeApiKey;
    
    @NotNull
    @Min(1) @Max(100)
    @Value("${order.processing.thread-pool-size:20}")
    private int threadPoolSize;
    
    @NotBlank
    @Pattern(regexp = "^(us-east-1|eu-west-1|ap-southeast-1)$")
    @Value("${aws.region}")
    private String awsRegion;
    
    @PostConstruct
    public void validate() {
        // Additional validation that bean validators can't express
        if (stripeApiKey.startsWith("sk_test_") && isProduction()) {
            throw new IllegalStateException(
                "Test Stripe key configured in production environment. Check configuration.");
        }
    }
}
```

**Rule**: applications should fail to start with a clear error message if configuration is invalid. A misconfigured application that starts and silently fails is worse than one that refuses to start.

---

## Configuration Drift Detection

```yaml
# Use Infrastructure as Code (Terraform/CDK) for all configuration
# Configuration defined in code = auditable, reviewable, versioned

# Terraform: AWS Secrets Manager secret
resource "aws_secretsmanager_secret" "orders_db" {
  name                    = "production/orders-service/db-credentials"
  description             = "Orders service database credentials"
  recovery_window_in_days = 7
  
  tags = {
    Service     = "orders-service"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

resource "aws_secretsmanager_secret_rotation" "orders_db" {
  secret_id           = aws_secretsmanager_secret.orders_db.id
  rotation_lambda_arn = aws_lambda_function.secret_rotation.arn
  
  rotation_rules {
    automatically_after_days = 30
  }
}
```

---

## Spring Cloud Config Server Pattern (Centralised Config)

```
Architecture:
  Git repo (config source) → Spring Cloud Config Server → services pull their config on startup

config-repo/
├── orders-service.yml           # service-specific config
├── orders-service-production.yml # service + environment
├── application.yml              # shared defaults for all services

Benefits:
  - Centralised; version-controlled
  - Environment-specific without duplication
  - Config refresh without restart (Spring Cloud Bus)
  
Drawbacks:
  - Config Server becomes a critical dependency (must be highly available)
  - Services can't start if Config Server is down
  - Secrets still need a separate secrets manager
```

---

## Trade-offs

| Decision | Option A | Option B | Recommendation |
|---|---|---|---|
| **Secrets storage** | AWS Secrets Manager | HashiCorp Vault | Secrets Manager on AWS: less operational overhead; Vault for multi-cloud or complex dynamic secrets |
| **Feature flags** | LaunchDarkly (managed) | Unleash (self-hosted) | LaunchDarkly for fast time-to-value and experimentation features; Unleash for cost control and data sovereignty |
| **Config distribution** | Environment variables | Spring Cloud Config Server | Env vars: simpler, twelve-factor compliant; Config Server: for teams needing runtime refresh without restart |
| **Feature flag evaluation** | Server-side | Client-side (SDK) | Server-side for security-sensitive flags; SDK for performance-critical evaluation (avoids network hop) |

---

## Configuration Anti-Patterns

| Anti-pattern | Problem | Fix |
|---|---|---|
| **Hardcoded config** | Requires redeployment for every value change; fails in different environments | Externalise all environment-specific values |
| **Secrets in git** | Permanent exposure — git history can never be fully purged | Secrets manager; git pre-commit hook scanning |
| **Configuration overload** | Operators must understand 300+ parameters to deploy correctly | Sensible defaults; document the 5 that actually need changing |
| **Silent misconfiguration** | App starts with wrong config; fails mysteriously later | Validate at startup; fail fast with descriptive error |
| **Flag accumulation** | 200 feature flags; nobody knows which are active | Flag lifecycle policy; quarterly audit; auto-expire old flags |
| **Environment variable sprawl** | 80 env vars; no documentation; wrong value causes prod incident | Document every variable; group into typed configuration classes |
| **Config in database with no audit trail** | Changed by hand; no record of who changed what | Config changes via pull request; database config changes trigger audit log |

---

## Best Practices Summary

1. **Separate code from configuration** — no hardcoded environment-specific values
2. **Never commit secrets to git** — use a secrets manager; install pre-commit hooks that scan for secret patterns
3. **Validate configuration at startup** — fail fast with clear error messages; don't silently start misconfigured
4. **Rotate secrets automatically** — use AWS Secrets Manager or Vault rotation; don't rely on manual rotation
5. **Use feature flags for all production changes** — dark launch, canary rollout, instant kill switch
6. **Define flag lifecycle policy** — every flag has a removal date; prune flags quarterly
7. **Infrastructure as Code for all config** — Terraform or CDK; configuration is code; it should be reviewed and versioned
8. **Sensible defaults for all optional config** — operators should only need to set the minimum
9. **Log configuration at startup (minus secrets)** — log which config source is used and the effective non-sensitive values
10. **Test configuration loading** — integration tests that verify the app starts correctly with each environment's config profile

---

## FAANG Interview Points

**"How do you manage 500 microservices' configuration across 3 environments without drift?"**: Three-part answer. First: infrastructure as code — all configuration is Terraform/CDK; changes go through pull request; no manual console changes; this is the source of truth and prevents drift by definition. Second: GitOps pipeline — Argo CD / Flux watches the config repo and applies changes; any manual deviation triggers a drift alert. Third: feature flags separate code deployment from feature activation — services deploy identical binary across environments; the feature flag system controls which features are active per environment. This means "staging config" is mostly feature flag state, not separate configuration files. The only truly environment-specific values are connection strings and secrets, which come from Secrets Manager keyed by environment.

**"What would you do if you discovered a production secret had been committed to git?"**: Treat it as an active security incident. First: rotate the secret immediately — assume it is compromised. Generate new credentials, deploy them via the secrets manager, verify services are using the new credentials. Second: revoke the old secret — once services are migrated, invalidate the old credentials at the source (AWS IAM, database, external API). Third: audit access — check access logs for the secret's resource for the window from the commit date to revocation. Fourth: purge from git history — `git filter-branch` or BFG Repo Cleaner to remove the commit from all branches; force-push; inform all contributors to re-clone. Fifth: prevent recurrence — install a pre-commit secret scanning hook (git-secrets, gitleaks, truffleHog) on all contributor machines and as a CI pipeline gate.

**"How do you do a zero-downtime rollout of a risky new feature to 100M users?"**: Feature flags with staged rollout. Deploy the code with the feature flag defaulting to OFF — this is a standard deployment, no user impact. Enable for internal users first (flag targets by email domain or user attribute) — detect issues without user impact. Enable for 1% of production users — real traffic, real scale, but minimal blast radius. Monitor error rate, latency, and business metrics for 30-60 minutes. If metrics are healthy, ramp to 10% → 25% → 50% → 100% with monitoring checkpoints. If any checkpoint shows degradation, the kill switch is one flag toggle — instant rollback, no redeployment, no downtime. This is how Google and Meta roll out changes to billions of users without maintenance windows.
