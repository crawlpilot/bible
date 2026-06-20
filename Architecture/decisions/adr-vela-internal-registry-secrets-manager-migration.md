# ADR-005: Migration to Vela Build Pipeline, Internal Dependency Registry, and AWS Secrets Manager

**Title**: Replace Jenkins-on-AWS Build Pipeline and S3-Based Secret Injection with Vela Internal CI, Internal Dependency Registry, and AWS Secrets Manager Runtime Secret Resolution  
**Status**: Accepted  
**Date**: 2026-06-14  
**Authors**: [Principal Engineer — Platform], [Staff Engineer — DevSecOps], [SRE Lead]  
**Reviewers**: [VP Engineering], [Security Architect], [EM — Platform], [Cloud Infrastructure Lead]  
**Deciders**: [CTO], [VP Engineering], [CISO]

---

## Context

### Current State

The organisation's product is deployed to AWS (EC2 instances and Lambda functions). The build and deployment pipeline consists of three stages managed across two separate infrastructure planes:

**Stage 1 — Build (Jenkins in AWS):**
```
Developer pushes code to GitHub
        │
        ▼
Jenkins (self-hosted on EC2 in AWS)
  → Checks out source code
  → Resolves dependencies from public registries
    (npm registry, Maven Central, Docker Hub, PyPI)
  → Builds application artefacts (JARs, ZIPs, Docker images)
  → Pulls secrets/config from S3 env file at build time
    (environment variables baked into the build output)
  → Uploads built artefacts to S3 (s3://build-artefacts-prod/)
        │
        ▼
Stage 2 — Deploy (AWS CodePipeline + CodeDeploy)
  → CodePipeline detects new artefact in S3
  → CodeDeploy deploys artefact to EC2 fleet
  → Lambda function packages uploaded directly from S3
```

**Current pipeline topology diagram:**
```
┌──────────────────────────────────┐         ┌─────────────────────────────────────┐
│         AWS Account              │         │         Public Internet              │
│                                  │         │                                      │
│  ┌─────────────┐                 │  ───►   │  npm registry / Maven Central /      │
│  │   Jenkins   │  dependency     │         │  Docker Hub / PyPI                   │
│  │   (EC2)     │  resolution     │         │                                      │
│  └──────┬──────┘                 │         └─────────────────────────────────────┘
│         │                        │
│         │ reads secrets          │         ┌─────────────────────────────────────┐
│         ▼                        │         │              S3                      │
│  ┌─────────────┐                 │         │  s3://config-bucket/prod.env        │
│  │  S3 env     │  (build-time    │  ◄───   │  (plaintext env vars, DB passwords, │
│  │  injection  │   secret bake)  │         │   API keys stored as .env files)    │
│  └──────┬──────┘                 │         └─────────────────────────────────────┘
│         │                        │
│         │ uploads artefact       │
│         ▼                        │
│  ┌─────────────────────────┐     │
│  │  S3 Artefact Bucket     │     │
│  │  s3://build-artefacts/  │     │
│  └────────────┬────────────┘     │
│               │                  │
│               ▼                  │
│  ┌─────────────────────────┐     │
│  │   CodePipeline          │     │
│  │   + CodeDeploy          │     │
│  └──────┬──────────────────┘     │
│          │              │        │
│          ▼              ▼        │
│       EC2 Fleet     Lambda       │
└──────────────────────────────────┘
```

### Problems With the Current Architecture

**Problem 1: External dependency resolution from within AWS — supply chain and network exposure**

Jenkins resolves all build dependencies (Maven, npm, Docker base images) directly from public internet registries. This creates four concrete risks:

| Risk | Description | Severity |
|---|---|---|
| Dependency confusion attack | An attacker registers a public package with the same name as an internal package; if the resolver checks public first, the malicious version is pulled | Critical |
| Typosquatting | A mistyped dependency name resolves to a malicious public package | High |
| Package tampering / compromised upstream | A legitimate package is backdoored after being audited (event-stream incident, XZ Utils CVE-2024-3094) | High |
| Egress cost and latency | Each build pulls 100s of MB from the public internet through NAT Gateway; NAT Gateway egress cost at current build volume: ~$1,400/month | Medium |
| No audit trail | The organisation cannot prove which exact dependency versions were used in any given build (no reproducibility guarantee) | High |

The Security team has issued a formal requirement: **all build dependencies must be resolved from the internal registry by Q3 2026**. Direct outbound internet access from build agents for package resolution is prohibited under the revised third-party software supply chain policy.

**Problem 2: Secrets baked into artefacts at build time**

The current mechanism for injecting runtime configuration into services is a `.env` file stored in S3 (`s3://config-bucket/{env}/app.env`). During the Jenkins build step, this file is downloaded and its contents are embedded into the build artefact as environment variables bundled with the deployment package.

This pattern has the following security consequences:

| Issue | Description |
|---|---|
| Secrets in artefacts | Database passwords, API keys, and service credentials are baked into the JAR/ZIP at build time. Anyone with S3 read access to the artefact bucket can extract them. |
| No secret rotation without rebuild | Rotating a database password requires a full rebuild and redeploy of every service that uses it. At current deploy velocity (1.3 deploys/month), a rotation requires 3–4 days to propagate across all services. |
| No audit trail for secret access | S3 GetObject calls are logged but not per-application. It is impossible to determine which process read which secret at what time. |
| Blast radius of a compromised build agent | If Jenkins is compromised, an attacker has read access to all secrets across all environments via the S3 config bucket (single IAM role, broad read permissions). |
| Compliance violation | PCI DSS 3.4 and SOC 2 CC6.3 require that credentials at rest be encrypted and access be auditable per application. Flat `.env` files in S3 with a shared IAM role fail both criteria. A compliance audit finding was issued in Q1 2026. |

**Problem 3: Jenkins running in AWS is incompatible with the org-wide internal Vela platform adoption**

The organisation has standardised on **Vela** as the internal CI/CD platform for all services not deployed to AWS. Vela runs inside the corporate data centre (internal network), behind the corporate VPN, with direct access to the internal package registry. The product team's continued use of Jenkins-on-AWS creates:

- A bifurcated developer experience: engineers who work across internal and AWS-deployed services must learn two pipeline systems
- A maintenance burden: the platform team maintains a Jenkins installation exclusively for the product team (patching, plugin management, EC2 cost: ~$2,100/month)
- A network boundary problem: Vela (internal) cannot reach AWS resources directly; Jenkins (AWS) cannot reach internal registry directly without a VPN tunnel that does not currently exist

The organisation's platform team has mandated Vela adoption for all product teams by Q4 2026.

### Trigger for This ADR

Three converging mandates forced resolution in Q2 2026:

1. **Security policy enforcement**: The third-party software supply chain policy update (effective Q3 2026) prohibits direct public registry access from any build environment. Continued use of Jenkins pulling from Maven Central / npm / Docker Hub is a policy violation after the effective date.

2. **Compliance audit finding (Q1 2026)**: The SOC 2 audit found that S3-based secret injection does not satisfy CC6.3 (Logical Access Controls) and CC6.8 (Change Management for Credentials). Remediation is required before the Q4 2026 re-audit.

3. **Platform standardisation mandate**: The platform team's Q4 2026 Vela adoption deadline means the Jenkins-on-AWS setup will lose platform support in 6 months regardless.

---

## Decision

**Migrate the product's build and deploy pipeline to Vela (internal CI) with all dependencies resolved from the internal registry, and replace S3-based build-time secret injection with AWS Secrets Manager runtime resolution.**

The decision is composed of three interdependent changes that must be implemented together:

### Change 1: Build Pipeline — Jenkins (AWS) → Vela (Internal)

Vela builds will run inside the corporate data centre on the existing internal Vela cluster. The resulting artefacts are pushed to AWS S3 over a dedicated VPN tunnel (site-to-site VPN between corporate DC and the product's AWS VPC, provisioned as part of this migration).

**New pipeline topology:**

```
┌──────────────────────────────────────────────────┐     ┌──────────────────────────────────────┐
│        Corporate Data Centre (Internal)           │     │           AWS Account                │
│                                                   │     │                                      │
│  Developer pushes to GitHub                       │     │  ┌──────────────────────────────┐   │
│          │                                        │     │  │   S3 Artefact Bucket         │   │
│          ▼                                        │     │  │   s3://build-artefacts-prod/ │   │
│  ┌───────────────────────────────────────────┐   │     │  └───────────────┬──────────────┘   │
│  │               Vela Pipeline               │   │     │                  │                   │
│  │                                           │   │     │                  ▼                   │
│  │  stage: checkout                          │   │     │  ┌──────────────────────────────┐   │
│  │    clone from GitHub                      │   │     │  │       CodePipeline           │   │
│  │                                           │   │     │  │       + CodeDeploy           │   │
│  │  stage: dependencies                      │   │     │  └───────────┬────────────┬─────┘   │
│  │    resolve from internal registry ──────► │ ──┼──►  │             │            │          │
│  │    (Nexus / Artifactory)                  │   │ VPN │          EC2 Fleet    Lambda        │
│  │                                           │   │     │                                      │
│  │  stage: build + test                      │   │     │  ┌──────────────────────────────┐   │
│  │    compile, unit test, SAST, SCA          │   │     │  │    AWS Secrets Manager       │   │
│  │                                           │   │     │  │    (runtime secret fetch)    │   │
│  │  stage: publish                           │   │     │  └──────────────────────────────┘   │
│  │    push artefact to S3  ──────────────────│───┼──►  │                                      │
│  │    (over site-to-site VPN)                │   │     └──────────────────────────────────────┘
│  └───────────────────────────────────────────┘   │
│                                                   │
│  ┌──────────────────────────────────────────┐    │
│  │    Internal Registry (Nexus/Artifactory)  │    │
│  │    - npm proxy + hosted                   │    │
│  │    - Maven proxy + hosted                 │    │
│  │    - Docker proxy + hosted                │    │
│  │    - PyPI proxy                           │    │
│  └──────────────────────────────────────────┘    │
└──────────────────────────────────────────────────┘
```

**Vela pipeline definition (`.vela.yml` at repo root):**

```yaml
version: "1"

services:
  - name: nexus-proxy
    image: internal-registry.corp/infra/nexus-proxy:3.x

steps:
  - name: checkout
    image: internal-registry.corp/vela/git:latest
    pull: always
    commands:
      - git checkout $VELA_BUILD_COMMIT

  - name: restore-cache
    image: internal-registry.corp/vela/cache:latest
    pull: always
    parameters:
      action: restore
      key: deps-{{ checksum "pom.xml" }}
      path: ~/.m2/repository

  - name: build-and-test
    image: internal-registry.corp/build/jdk17:latest
    pull: always
    environment:
      MAVEN_OPTS: "-Dmaven.repo.local=~/.m2/repository"
      REGISTRY_URL: "https://nexus.corp.internal/repository/maven-proxy/"
    commands:
      - mvn -s .mvn/settings.xml clean verify -Dmaven.test.failure.ignore=false

  - name: save-cache
    image: internal-registry.corp/vela/cache:latest
    pull: always
    parameters:
      action: save
      key: deps-{{ checksum "pom.xml" }}
      path: ~/.m2/repository

  - name: sast-scan
    image: internal-registry.corp/security/semgrep:latest
    pull: always
    commands:
      - semgrep --config=auto --error --json > semgrep-results.json

  - name: sca-scan
    image: internal-registry.corp/security/dependency-check:latest
    pull: always
    commands:
      - dependency-check.sh --project "$VELA_REPO_NAME" --scan . --failOnCVSS 7

  - name: publish-artefact
    image: internal-registry.corp/vela/aws-cli:latest
    pull: always
    secrets:
      - AWS_ACCESS_KEY_ID       # scoped Vela secret; S3 write only
      - AWS_SECRET_ACCESS_KEY
    commands:
      - >
        aws s3 cp target/${APP_NAME}-${VELA_BUILD_NUMBER}.jar
        s3://build-artefacts-prod/${VELA_REPO_NAME}/${VELA_BUILD_NUMBER}/
        --region eu-west-1
    ruleset:
      branch: main
      event: push

  - name: trigger-codepipeline
    image: internal-registry.corp/vela/aws-cli:latest
    pull: always
    secrets:
      - AWS_ACCESS_KEY_ID
      - AWS_SECRET_ACCESS_KEY
    commands:
      - >
        aws codepipeline start-pipeline-execution
        --name ${APP_NAME}-deploy-prod
        --region eu-west-1
    ruleset:
      branch: main
      event: push
```

**Note**: All images referenced in `.vela.yml` are pulled from `internal-registry.corp` — never from Docker Hub or any public registry. The internal registry proxies public images after security scanning, approval, and caching.

---

### Change 2: Internal Registry — All Dependencies Must Resolve Internally

**Registry architecture (Nexus Repository Manager OSS, already running internally):**

| Repository | Type | Proxies | Used By |
|---|---|---|---|
| `maven-central-proxy` | Proxy | Maven Central | Java builds |
| `maven-hosted` | Hosted | — | Internal JARs / libraries |
| `maven-group` | Group | `maven-central-proxy` + `maven-hosted` | All Maven builds (single URL) |
| `npm-proxy` | Proxy | npmjs.com | Node.js builds |
| `npm-hosted` | Hosted | — | Internal npm packages |
| `npm-group` | Group | `npm-proxy` + `npm-hosted` | All npm builds |
| `docker-proxy` | Proxy | Docker Hub, ECR Public, GCR | Container base images |
| `docker-hosted` | Hosted | — | Internal images |
| `pypi-proxy` | Proxy | PyPI | Python builds |

**Proxy cache behaviour:** Nexus proxy repositories cache upstream artefacts after first resolution. The build agent never goes directly to the public internet — it always resolves from Nexus. Nexus fetches from upstream only if the artefact is not cached.

**Artefact security scanning gate (on proxy fetch):**
- Nexus IQ Server (or Sonatype Lifecycle) scans each artefact at first resolution
- Artefacts with CVSS ≥ 7.0 CVEs are quarantined: the artefact is downloaded to Nexus but not served to build agents; a Slack alert is sent to the security team
- Build agents receive a 403 for quarantined artefacts, failing the build explicitly

**Enforcing internal-only resolution in Maven (`settings.xml`):**

```xml
<settings>
  <mirrors>
    <mirror>
      <id>internal-nexus</id>
      <mirrorOf>*</mirrorOf>          <!-- redirect ALL repositories to Nexus -->
      <url>https://nexus.corp.internal/repository/maven-group/</url>
    </mirror>
  </mirrors>

  <servers>
    <server>
      <id>internal-nexus</id>
      <username>${env.NEXUS_USER}</username>
      <password>${env.NEXUS_PASSWORD}</password>
    </server>
  </servers>

  <!-- Explicit block: no direct internet resolution -->
  <profiles>
    <profile>
      <id>block-central</id>
      <repositories>
        <repository>
          <id>central</id>
          <url>https://nexus.corp.internal/repository/maven-group/</url>
        </repository>
      </repositories>
    </profile>
  </profiles>
  <activeProfiles>
    <activeProfile>block-central</activeProfile>
  </activeProfiles>
</settings>
```

**Docker base image policy:**
- All Dockerfiles must reference `FROM internal-registry.corp/...` — never `FROM ubuntu:22.04` or any public image directly
- The internal registry's `docker-proxy` repository serves the equivalent images after scanning
- PR linting (Dockerfile lint step in Vela pipeline) fails any `FROM` statement referencing a non-internal host

---

### Change 3: Secrets — S3 Build-Time Injection → AWS Secrets Manager Runtime Resolution

**Eliminated pattern (before):**

```
Build time (Vela/Jenkins):
  aws s3 cp s3://config-bucket/prod.env .env
  source .env           # DB_PASSWORD, API_KEY, etc. now in build env
  mvn package           # secrets baked into the JAR manifest / application.properties

Result: JAR at s3://build-artefacts/app-1.0.jar contains plaintext secrets
```

**New pattern (after):**

```
Build time (Vela):
  No secret access.
  Vela build agents have no IAM permissions to read Secrets Manager or any config bucket.
  The built JAR/ZIP contains no secrets — only application code and configuration schema.

Runtime (EC2 / Lambda startup):
  Application calls AWS Secrets Manager API on startup:
    aws secretsmanager get-secret-value --secret-id prod/app/database
  Returns: {"DB_HOST": "...", "DB_PASSWORD": "...", "DB_PORT": "5432"}
  Application caches the secret in-process for a configurable TTL (default: 1 hour)
  Application refreshes before TTL expiry
```

**AWS Secrets Manager structure:**

```
Secret naming convention: {env}/{service}/{component}

prod/payments-service/database
prod/payments-service/stripe-api
prod/order-service/database
prod/order-service/sqs-credentials
staging/payments-service/database
staging/payments-service/stripe-api
...
```

**IAM policy per service (least privilege):**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowReadOwnSecrets",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": [
        "arn:aws:secretsmanager:eu-west-1:123456789:secret:prod/payments-service/*"
      ]
    }
  ]
}
```

Each service's EC2 instance profile (or Lambda execution role) grants read access only to secrets prefixed with that service's namespace. No service can read another service's secrets.

**Application integration pattern (Java / Spring Boot):**

```java
// SecretManagerConfig.java
@Configuration
public class SecretsConfig {

    private final SecretsManagerClient client;

    public SecretsConfig(SecretsManagerClient client) {
        this.client = client;
    }

    @Bean
    public DatabaseCredentials databaseCredentials(
            @Value("${aws.secretsmanager.secret-id}") String secretId) {

        GetSecretValueRequest request = GetSecretValueRequest.builder()
                .secretId(secretId)
                .build();

        String secretJson = client.getSecretValue(request).secretString();
        return objectMapper.readValue(secretJson, DatabaseCredentials.class);
    }
}
```

```yaml
# application.yml — no secrets, only secret identifiers
aws:
  secretsmanager:
    secret-id: "prod/payments-service/database"
    region: "eu-west-1"
```

**Secret rotation:**
- AWS Secrets Manager automatic rotation enabled for all database credentials (30-day rotation cycle)
- Rotation uses Lambda rotation function (provided by AWS for RDS; custom for external services)
- Application's in-process TTL (1 hour) ensures rotation propagates within 1 hour without requiring a redeploy
- No rebuild, no redeploy, no pipeline run required for a secret rotation

**Migration from S3 env files:**

```
Phase 1 (parallel run):
  Secrets Manager populated from existing S3 env files (one-time import script)
  Application reads from BOTH S3 (fallback) and Secrets Manager (primary)
  Verify Secrets Manager reads are working via CloudTrail

Phase 2 (cutover):
  Remove S3 read permissions from EC2 instance profiles
  Remove S3 env file read step from pipeline
  S3 config bucket access restricted to security team only (for audit)

Phase 3 (cleanup):
  S3 config bucket versioned and archived
  Bucket policy set to DENY all GetObject except security team
  S3 env files retained for 90 days (compliance), then deleted
```

---

## Rollout Plan

### Phase 1 — Infrastructure Setup (Weeks 1–3)

- [ ] Provision site-to-site VPN: corporate DC ↔ product AWS VPC (Terraform-managed; IPsec)
- [ ] Configure Nexus proxy repositories for Maven, npm, Docker, PyPI
- [ ] Set up Nexus IQ Server scanning policy (CVSS ≥ 7.0 quarantine gate)
- [ ] Populate AWS Secrets Manager with all secrets currently in S3 env files
- [ ] Create per-service IAM policies for Secrets Manager access (least privilege)
- [ ] Validate Vela-to-S3 artefact push over VPN (latency and throughput acceptance test)

### Phase 2 — Pilot Migration (Weeks 4–6)

- [ ] Migrate 2 pilot services to Vela pipeline (lowest-risk services, selected with EM)
- [ ] Validate: all dependencies resolve from internal Nexus (no external DNS resolution from build agents)
- [ ] Validate: built artefacts contain no secrets (automated secret-scanning step in pipeline: `trufflesecurity/trufflehog` scan on output JAR/ZIP)
- [ ] Validate: EC2 instances fetch secrets from Secrets Manager on startup (CloudTrail verification)
- [ ] Run old (Jenkins) and new (Vela) pipelines in parallel for 2 weeks; compare artefact hashes

### Phase 3 — Full Migration (Weeks 7–14)

- [ ] Migrate remaining services to Vela pipeline (4 services/week; 2 teams/week)
- [ ] For each migrated service: disable S3 env file read permission from instance profile
- [ ] Decommission Jenkins EC2 instances progressively as services migrate
- [ ] Remove S3 config bucket write permissions from all build IAM roles

### Phase 4 — Hardening and Validation (Weeks 15–16)

- [ ] Security team penetration test: attempt to extract secrets from artefact bucket
- [ ] Compliance evidence package for SOC 2 CC6.3 and CC6.8: Secrets Manager access logs, IAM policies, no-plaintext-in-artefact scan results
- [ ] Jenkins EC2 instances fully decommissioned
- [ ] S3 config bucket locked to security-team-only access

---

## Consequences

### Positive

**Supply chain security:**
- No direct outbound internet access from any build agent for package resolution
- All dependencies pass through Nexus IQ vulnerability scanning gate before being served
- Dependency confusion attacks and typosquatting are mitigated: internal package names shadow public names in the group repository; external packages are pulled through a controlled proxy
- Full dependency audit trail: every artefact resolved from Nexus is logged with timestamp, build identity, and version

**Secret security:**
- Secrets are never embedded in build artefacts; artefacts are clean of credentials
- Per-service IAM least privilege: no service can read another service's secrets
- Automatic secret rotation without rebuild or redeploy
- Full CloudTrail audit of secret access: every `GetSecretValue` call is logged with service identity, timestamp, and secret name — satisfies SOC 2 CC6.3 and CC6.8
- Blast radius of a compromised build agent is eliminated: Vela agents have no Secrets Manager permissions

**Operational:**
- Developer experience unified: all product team engineers use the same Vela pipeline as the rest of the organisation
- Jenkins EC2 elimination: ~$2,100/month in EC2 costs removed; platform team Jenkins maintenance burden eliminated
- NAT Gateway egress cost reduced: dependency resolution moves from AWS NAT → internet to internal Nexus → VPN; estimated saving ~$1,400/month on NAT Gateway charges
- Secret rotation propagates within 1 hour (in-process TTL) vs. 3–4 day full-rebuild cycle previously

### Negative / Risks

**VPN dependency for artefact upload:**

Vela (internal) pushes artefacts to S3 (AWS) over the site-to-site VPN. VPN availability becomes a dependency in the build pipeline.

- Mitigation: site-to-site VPN provisioned with active-active redundancy (two tunnels in different availability zones per AWS VPN gateway documentation)
- Fallback: if VPN is unavailable, Vela pipeline fails cleanly at the `publish-artefact` step; no partial or corrupt artefact is uploaded. Engineers are alerted via Vela's built-in failure notification

**Build latency increase from Nexus proxy:**

First-time resolution of a dependency not yet cached in Nexus adds latency vs. direct resolution (Nexus fetches from upstream + scans before serving). Subsequent builds hit the Nexus cache and are faster than the old Jenkins setup (no NAT Gateway hop).

- Expected impact: first-build latency +30–90 seconds for cold cache
- At steady state: build time expected to decrease 10–20% (no NAT Gateway latency on cache hits; Nexus is on the internal network with sub-millisecond latency to build agents)

**Nexus as a new single point of failure:**

All builds now depend on Nexus availability. A Nexus outage stops all builds across all product and internal teams.

- Mitigation: Nexus is already a critical internal dependency for non-AWS services; it runs with HA configuration (active-passive with shared NFS storage). This migration adds load but does not change the HA architecture.
- SLA: Nexus platform team maintains 99.9% monthly availability SLA

**Application code changes required for Secrets Manager:**

Every service must be modified to call the Secrets Manager SDK instead of reading environment variables at startup. This is a code change, not just a pipeline change.

- Estimated scope: 8 services × 1–3 days per service = 16–24 engineer-days
- Mitigation: provide a shared library (`corp-secrets-spring-starter`) that wraps the Secrets Manager call, enabling one-line integration per service and standardising the caching and refresh logic. The library is maintained by the platform team.
- For Lambda: use the [AWS Parameters and Secrets Lambda Extension](https://docs.aws.amazon.com/secretsmanager/latest/userguide/retrieving-secrets_lambda.html) — no SDK integration code required; secrets are accessed via localhost HTTP endpoint injected by the extension layer

**Vela pipeline cold start for Docker image pulls:**

Vela agents pull pipeline step images from the internal Docker registry. First pull on a new agent node adds latency.

- Mitigation: pre-pull common build images on Vela agent nodes during provisioning (Ansible playbook maintained by platform team)

### Neutral

- S3 artefact storage and CodePipeline → CodeDeploy → EC2/Lambda deployment path are unchanged. Only the build and secret-injection stages change. This limits migration scope and preserves a tested deploy mechanism.
- CodePipeline now triggers on S3 artefact upload (unchanged), but the upload source changes from Jenkins to Vela. CodePipeline has no awareness of or dependency on the build tool.
- The Vela service account (used for S3 publish) requires a new IAM user with scoped S3 write permissions for the artefact bucket. This is narrower than the current Jenkins instance profile, which has broad S3 access.

---

## Alternatives Considered

### Option A: Keep Jenkins; Add Nexus Proxy as a Dependency Mirror; Migrate Secrets to Secrets Manager

**Description:** Retain Jenkins on EC2. Configure Jenkins to resolve dependencies from internal Nexus by setting mirror URLs in `.npmrc`, `settings.xml`, and Dockerfiles. Separately migrate secrets from S3 env files to Secrets Manager. Do not migrate to Vela.

| Dimension | Assessment |
|---|---|
| Supply chain security | ✅ Resolved — dependencies go through Nexus proxy |
| Secret security | ✅ Resolved — Secrets Manager at runtime |
| Developer experience | ❌ Two CI platforms continue (Jenkins for product, Vela for everyone else) |
| Jenkins maintenance | ❌ Continues; platform team maintains Jenkins for one team |
| Platform mandate compliance | ❌ Violates Q4 2026 Vela adoption mandate |
| Cost | ❌ $2,100/month Jenkins EC2 cost continues |
| Timeline to achieve security compliance | ✅ Faster than full Vela migration |

**Rejected because:** Satisfies the security requirements but does not satisfy the platform standardisation mandate. A second migration to Vela would still be required by Q4 2026, making this approach a two-step path that does not reduce total migration effort. Preferred to do one combined migration.

---

### Option B: Migrate to GitHub Actions; Use Internal Registry via Runner Configuration; Secrets via AWS Secrets Manager

**Description:** Replace Jenkins with GitHub Actions (GitHub Enterprise is already available). Self-hosted GitHub Actions runners configured to use internal Nexus proxy. Secrets via Secrets Manager at runtime.

| Dimension | Assessment |
|---|---|
| Supply chain security | ✅ Resolved via runner network policy |
| Secret security | ✅ Resolved via Secrets Manager |
| Developer experience | ⚠️ Better than Jenkins; but diverges from internal Vela standard |
| Self-hosted runner maintenance | ❌ Platform team must maintain GitHub Actions runner fleet (similar overhead to Jenkins) |
| Platform mandate compliance | ❌ Violates Q4 2026 Vela adoption mandate |
| GitHub Actions runner in AWS | ⚠️ Runners must be inside AWS VPC to access internal Nexus via VPN (same VPN dependency as chosen approach) OR runners are in corporate DC (same topology as chosen approach but with different tooling) |

**Rejected because:** GitHub Actions self-hosted runners require the same VPN topology as the chosen approach (Vela), while not satisfying the platform standardisation mandate and still requiring runner fleet maintenance. Vela is already running, supported, and compliant.

---

### Option C: Mirror Public Registries Directly Into AWS (ECR, CodeArtifact); No Internal Nexus Dependency

**Description:** Instead of routing through the internal Nexus proxy, use AWS-native equivalents: AWS CodeArtifact for npm/Maven/PyPI mirroring, Amazon ECR for Docker image mirroring. Jenkins or Vela build agents resolve from CodeArtifact/ECR within AWS.

| Dimension | Assessment |
|---|---|
| Supply chain security | ✅ Resolved — no direct public internet access from build agents |
| Secret security | Unchanged — separate initiative |
| Internal Nexus dependency | ✅ Eliminated — no VPN dependency for dependency resolution |
| AWS cost | ❌ CodeArtifact: $0.05/GB stored + $0.01/GB requested; at current build volume, ~$800/month |
| Org-wide governance | ❌ Registry split: internal services use Nexus; product team uses CodeArtifact. Two registries, two governance policies, two vulnerability scanning configurations. |
| Platform mandate compliance | ❌ Does not resolve Vela migration |
| SCA / vulnerability scanning | ❌ CodeArtifact has no built-in vulnerability scanning; would require CodeArtifact + Inspector or third-party integration |

**Rejected because:** Creates a second registry governance surface for the product team while the rest of the organisation uses Nexus. Violates the organisation's goal of a single internal registry with a single security scanning policy. The cost of $800/month is also higher than the NAT Gateway saving this approach would produce. The VPN (required for Vela migration) eliminates the "no VPN dependency" benefit of this option.

---

### Option D: Full GitOps — Vela Builds Image; Pushes to Internal Registry; ArgoCD Pulls to AWS (EKS-Only Path)

**Description:** As part of the migration, move EC2-based services to EKS (per ADR-003). Build Docker images via Vela; push to internal Docker registry; ArgoCD (running in AWS) pulls from internal registry and deploys to EKS. Eliminates CodePipeline/CodeDeploy entirely.

| Dimension | Assessment |
|---|---|
| Supply chain security | ✅ Excellent — image is built and scanned internally; ArgoCD pulls from internal registry |
| Secret security | ✅ Via Secrets Manager (same as chosen approach) |
| Architecture elegance | ✅ GitOps is the right long-term target; ADR-004 deferred this to Q1 2027 |
| EKS dependency | ❌ Requires ADR-003 (EKS migration) to be complete first |
| Timeline | ❌ ADR-003 completes Q4 2026; this option is not available by Q3 2026 security deadline |
| CodePipeline/CodeDeploy elimination | ✅ Long-term benefit; ❌ short-term risk of changing too many things simultaneously |

**Not rejected permanently — incorporated into the Q1 2027 roadmap.** The chosen approach (Vela → S3 → CodePipeline) is intentionally compatible with a future ArgoCD adoption: when ADR-003 completes, the Vela pipeline's `publish-artefact` step can be changed from S3 upload to internal registry push with minimal pipeline change. CodePipeline/CodeDeploy is replaced by ArgoCD at that point. This ADR's migration does not block that path.

---

## Decision Criteria Trade-off Summary

| Criterion | Chosen (Vela + Nexus + SecretsManager) | Option A (Keep Jenkins + Nexus + SM) | Option B (GitHub Actions + Nexus + SM) | Option C (CodeArtifact) | Option D (GitOps / EKS) |
|---|---|---|---|---|---|
| Resolves supply chain risk | ✅ | ✅ | ✅ | ✅ | ✅ |
| Resolves secrets compliance | ✅ | ✅ | ✅ | ❌ (separate) | ✅ |
| Satisfies platform Vela mandate | ✅ | ❌ | ❌ | ❌ | ✅ |
| Achievable by Q3 2026 security deadline | ✅ | ✅ | ✅ | ✅ | ❌ |
| Single migration (not two steps) | ✅ | ❌ | ❌ | ❌ | ✅ (but blocked) |
| No new AWS cost introduced | ✅ | ✅ | ✅ | ❌ (~$800/mo) | ✅ |
| Unified registry governance | ✅ | ✅ | ✅ | ❌ | ✅ |
| CodePipeline/CodeDeploy preserved | ✅ | ✅ | ✅ | ✅ | ❌ |
| Compatible with Q1 2027 GitOps roadmap | ✅ | ❌ | ❌ | ❌ | ✅ |

---

## Security Compliance Mapping

| Requirement | How This ADR Satisfies It |
|---|---|
| **SOC 2 CC6.3** — Logical access controls on credentials | Per-service IAM least-privilege policies on Secrets Manager; no shared credentials |
| **SOC 2 CC6.8** — Change management for credentials | Automatic rotation via Secrets Manager; rotation audit trail in CloudTrail |
| **Supply chain policy** — No direct public registry access from build agents | All dependency resolution through internal Nexus proxy; build agents have no outbound internet access |
| **PCI DSS 3.4** — Credentials encrypted at rest | Secrets Manager encrypts at rest with AWS KMS; no plaintext secrets in S3 env files |
| **PCI DSS 10.2** — Audit trails for credential access | CloudTrail logs every `GetSecretValue` call with service identity and timestamp |
| **Internal policy** — Vela adoption Q4 2026 | Build pipeline migrated to Vela; Jenkins decommissioned by end of Phase 4 |

---

## FAANG Interview Framing

> **"Tell me about a time you improved your organisation's security posture through a technical migration."**

Key beats:
- **Problem in concrete terms**: S3 env file injection meant secrets were baked into JAR artefacts — anyone with S3 read access could extract production database passwords. Not a theoretical risk: SOC 2 audit issued a formal finding.
- **Scope of the decision**: three interdependent changes (pipeline tool, registry, secrets mechanism) had to be coordinated — changing one without the others would leave security gaps
- **The non-obvious constraint**: the VPN (needed to push artefacts from internal Vela to AWS S3) was the critical path item. The rest of the migration couldn't start until the VPN was provisioned. Identified this in Week 1 and put it on the critical path in the rollout plan.
- **Alternatives considered and why rejected**: Option C (CodeArtifact) would have solved supply chain but split the organisation into two registry governance surfaces — traded one problem for a different one
- **Systemic outcome**: automatic secret rotation without rebuild propagates in < 1 hour; the old approach required 3–4 days per rotation. Post-migration, the team can rotate all production database passwords in a 1-hour window with zero deploys.

> **"How do you handle a migration that requires changes across multiple layers (pipeline, secrets, registry) simultaneously?"**

- Sequence the dependencies: registry must be running before pipelines can use it; secrets must be in Secrets Manager before S3 read permissions are removed; VPN must be up before artefact publish can work
- Parallel run period (Phase 2): old and new pipelines run simultaneously for 2 weeks; artefact hashes compared to verify equivalence before cutover
- Progressive cutover: 4 services per week rather than a big-bang switch; each cutover is independently reversible
- Don't change the deploy stage: CodePipeline/CodeDeploy is preserved exactly as-is; only the build and secret stages change. This scopes the blast radius of the migration.
