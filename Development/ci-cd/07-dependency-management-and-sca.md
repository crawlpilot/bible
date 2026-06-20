# Dependency Management, SCA, and Vulnerability Automation

## The Core Problem

At scale, dependencies are an attack surface you don't write but still own. In a 200-service org with 500 engineers:
- Each service has ~100–300 direct dependencies and 500–2,000 transitive ones
- A single CVE like Log4Shell forces you to audit **every** service simultaneously
- Manual patching across services takes weeks; the blast radius window stays open
- Without centralisation, version drift means Service A uses jackson 2.13, Service B uses 2.9 — same CVE, different patching status, no single pane of glass

**Principal engineer framing**: dependency hygiene is a platform-level problem, not a team-level one. The platform team owns the BOM, the automation, and the SLO. Individual teams consume, not curate.

---

## SCA (Software Composition Analysis) — Tool Landscape

SCA tools scan your dependency tree for known CVEs (from NVD, GitHub Advisory Database, OSS Index, Snyk Intel, etc.) and license violations.

### Tool Comparison

| Tool | Type | Language Support | CI Integration | Notable Strength | Limitation |
|------|------|-----------------|----------------|-----------------|------------|
| **Snyk** | Commercial (free tier) | Java, JS, Python, Go, .NET, Ruby, C/C++ | GitHub, GitLab, Jenkins, CircleCI | Dev-friendly UX, IDE plugin, autofix PRs | Expensive at scale; rate limits on free |
| **Mend (WhiteSource)** | Commercial | 200+ languages | All major CI | License compliance + CVE; policy engine | Heavy — best for regulated industries |
| **OWASP Dependency-Check** | OSS | Java, .NET, JS, Python, Ruby | Jenkins plugin, CLI, Maven/Gradle plugin | Free, works air-gapped | High false-positive rate; slow DB sync |
| **Grype** | OSS (Anchore) | Container + SBOM-based | Any CI (CLI) | Fast, pairs with Syft for SBOM scanning | No autofix; pull model only |
| **Trivy** | OSS (Aqua) | Container, IaC, SBOM, git repos | Any CI (CLI) | All-in-one (CVE + misconfig + secrets) | Fewer ecosystem integrations than Snyk |
| **Dependabot** | GitHub-native | ~20 ecosystems | GitHub Actions native | Zero-config to start; free | GitHub-only; limited grouping logic |
| **GitHub Advanced Security** | GitHub Enterprise | Java, JS, Python, Go, C#, C++ | GitHub Actions | CodeQL SAST + SCA in one platform | Cost; GitHub ecosystem lock-in |
| **Socket.dev** | Commercial | JS/TS (npm focus) | GitHub, CLI | Detects supply chain attacks (malware, typosquatting), not just CVEs | Limited to JS ecosystem |

### Recommended Stack (Pragmatic)

```
Development IDE:     Snyk IDE plugin (catches issues before commit)
CI commit stage:     Trivy or Grype on the built image (fast, fail-fast on CRITICAL/HIGH)
CI acceptance stage: Snyk or Mend (full dep tree scan, license check, policy enforcement)
Scheduled (nightly): OWASP Dependency-Check (comprehensive, NVD offline DB, no rate limits)
Runtime/Registry:    Trivy in the artifact registry (scan on push, block if policy violated)
```

**Key principle**: run a *fast, high-signal* scan on every commit (< 60s) and a *thorough* scan async/nightly. Don't block trunk on a 10-minute scan.

---

## Integrating SCA Into the Pipeline

### Fail Fast on CRITICAL

```yaml
# .github/workflows/security-scan.yml
- name: Scan image for vulnerabilities
  run: |
    trivy image \
      --exit-code 1 \
      --severity CRITICAL \
      --ignore-unfixed \
      registry.company.com/myservice:${{ github.sha }}
```

`--ignore-unfixed`: don't fail on CVEs that have no patch yet — actionable signal only.

### Vulnerability SLO (the missing piece in most orgs)

Without a SLO, vulnerability reports become noise. Define it as policy:

| Severity | Remediation SLO | Action if missed |
|----------|----------------|-----------------|
| CRITICAL | 72 hours | Pagerduty to service owner + skip-the-queue to platform team |
| HIGH | 7 days | Jira ticket auto-created, eng manager notified |
| MEDIUM | 30 days | Backlog item, reviewed in sprint planning |
| LOW | 90 days or suppress | Team discretion; suppressed with a justification comment |

Track this as an engineering health metric on the org dashboard.

### Suppressing False Positives Systematically

```yaml
# .trivyignore  (checked into repo, reviewed in PR)
CVE-2021-44228  # log4j - not applicable, we use logback, confirmed 2024-01-15
CVE-2022-42003  # jackson-databind - mitigated by WAF rule, expires 2024-06-01
```

Every suppression requires: CVE ID, reason, owner, expiry date. Expired suppressions fail the build — forces re-review.

---

## Automated Dependency Update Tools

Manual patching doesn't scale. Automating it removes toil but introduces risk — the design is in *how* you automate.

### Renovate vs. Dependabot

| Dimension | Renovate | Dependabot |
|-----------|----------|-----------|
| Hosting | Self-hosted (Mend Renovate) or Mend cloud | GitHub-managed only |
| Configuration | Highly configurable JSON (`renovate.json`) | Limited YAML config |
| Grouping updates | First-class: group by ecosystem, scope, regex | Basic grouping in newer versions |
| Automerge | Granular: patch only, minor, or regex-matched | Supported but less granular |
| Scheduling | Configurable windows, batch on specific days | Configurable but simpler |
| Monorepo support | Excellent | Decent (per-directory configs) |
| Custom registries | Yes (Artifactory, Nexus, private npm) | Yes |
| Cost | Free (self-hosted); paid cloud | Free on GitHub |
| Community | Large, active | GitHub-maintained |

**Recommendation**: Renovate for non-trivial orgs (monorepos, custom registries, fine-grained grouping). Dependabot is fine for small teams on GitHub with standard setups.

---

## Renovate — Configuration Deep Dive

### Core Configuration (`renovate.json`)

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "config:base",
    ":dependencyDashboard",
    ":semanticCommits",
    "group:monorepos"
  ],
  "timezone": "America/Los_Angeles",
  "schedule": ["before 6am on Monday"],
  "prConcurrentLimit": 5,
  "prCreationDelay": "24h",
  "labels": ["dependencies"],
  "assignees": ["platform-team"],
  "packageRules": [
    {
      "description": "Auto-merge patch updates (low risk)",
      "matchUpdateTypes": ["patch"],
      "matchCurrentVersion": "!/^0/",
      "automerge": true,
      "automergeType": "pr",
      "platformAutomerge": true
    },
    {
      "description": "Group all Spring Boot managed deps together",
      "matchPackagePatterns": ["^org.springframework", "^io.spring"],
      "groupName": "Spring Framework",
      "schedule": ["before 6am on the first day of the month"]
    },
    {
      "description": "Separate major bumps - always require manual review",
      "matchUpdateTypes": ["major"],
      "automerge": false,
      "labels": ["dependencies", "breaking-change"],
      "assignees": ["tech-lead"]
    },
    {
      "description": "Security updates - expedite regardless of schedule",
      "matchDepTypes": ["vulnerabilities"],
      "schedule": ["at any time"],
      "prPriority": 10,
      "labels": ["dependencies", "security"]
    }
  ]
}
```

### Key Grouping Strategies

**Group by ecosystem** — reduces PR noise when many packages update together:
```json
{
  "matchPackagePatterns": ["^@aws-sdk/"],
  "groupName": "AWS SDK",
  "groupSlug": "aws-sdk"
}
```

**Group patch + minor together, isolate major**:
```json
[
  {
    "matchUpdateTypes": ["patch", "minor"],
    "groupName": "non-breaking updates"
  },
  {
    "matchUpdateTypes": ["major"],
    "groupName": "major updates - requires review"
  }
]
```

**Internal packages — faster cadence**:
```json
{
  "matchRegistryUrls": ["https://artifactory.company.com"],
  "schedule": ["at any time"],
  "automerge": true
}
```

### Automerge Decision Framework

```
Patch update?
  └── No known CVE + green CI → automerge
  └── CVE fixed → automerge with expedited schedule

Minor update?
  └── Green CI + stable semver history → automerge (optional, risk-tolerance based)
  └── Ecosystem with poor semver hygiene (e.g., some JS libs) → require review

Major update?
  └── Always require review + explicit approval
  └── Create a tracking issue, coordinate with consumers

Internal library?
  └── If owns BOM → automerge only in non-prod first (staged rollout)
  └── If leaf package → automerge with green CI
```

---

## BOM Standardisation

A BOM (Bill of Materials) defines *which versions* of dependencies are used without requiring each project to repeat them. The goal: **one place to update, all consumers inherit**.

### Maven BOM Pattern

```xml
<!-- platform-bom/pom.xml — owned by platform team -->
<project>
  <groupId>com.company</groupId>
  <artifactId>platform-bom</artifactId>
  <version>2024.1.0</version>
  <packaging>pom</packaging>

  <dependencyManagement>
    <dependencies>
      <!-- Spring Boot manages its own transitive tree -->
      <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-dependencies</artifactId>
        <version>3.2.1</version>
        <type>pom</type>
        <scope>import</scope>
      </dependency>

      <!-- Override specific versions within Spring's tree -->
      <dependency>
        <groupId>com.fasterxml.jackson.core</groupId>
        <artifactId>jackson-databind</artifactId>
        <version>2.16.1</version>  <!-- pinned above Spring's default -->
      </dependency>

      <!-- Internal libraries — centrally versioned -->
      <dependency>
        <groupId>com.company.shared</groupId>
        <artifactId>observability-client</artifactId>
        <version>1.5.3</version>
      </dependency>
    </dependencies>
  </dependencyManagement>
</project>
```

```xml
<!-- service/pom.xml — consumes the BOM, declares NO versions -->
<dependencyManagement>
  <dependencies>
    <dependency>
      <groupId>com.company</groupId>
      <artifactId>platform-bom</artifactId>
      <version>2024.1.0</version>
      <type>pom</type>
      <scope>import</scope>
    </dependency>
  </dependencies>
</dependencyManagement>

<dependencies>
  <!-- No version declared — inherited from BOM -->
  <dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-web</artifactId>
  </dependency>
  <dependency>
    <groupId>com.company.shared</groupId>
    <artifactId>observability-client</artifactId>
  </dependency>
</dependencies>
```

### Gradle Version Catalog (`libs.versions.toml`)

Gradle's native solution — checked into the repo root, consumed across all subprojects:

```toml
# gradle/libs.versions.toml

[versions]
spring-boot     = "3.2.1"
jackson         = "2.16.1"
guava           = "32.1.3-jre"
junit           = "5.10.1"
observability   = "1.5.3"

[libraries]
spring-boot-web     = { module = "org.springframework.boot:spring-boot-starter-web",    version.ref = "spring-boot" }
spring-boot-test    = { module = "org.springframework.boot:spring-boot-starter-test",   version.ref = "spring-boot" }
jackson-databind    = { module = "com.fasterxml.jackson.core:jackson-databind",         version.ref = "jackson" }
guava               = { module = "com.google.guava:guava",                              version.ref = "guava" }
observability       = { module = "com.company.shared:observability-client",             version.ref = "observability" }

[bundles]
# Bundles: declare a set of libraries as a single alias
testing = ["spring-boot-test", "junit-jupiter-api", "junit-jupiter-engine"]

[plugins]
spring-boot         = { id = "org.springframework.boot",    version.ref = "spring-boot" }
spring-dep-mgmt     = { id = "io.spring.dependency-management", version = "1.1.4" }
```

```kotlin
// build.gradle.kts — type-safe, IDE-autocompleted
dependencies {
    implementation(libs.spring.boot.web)
    implementation(libs.jackson.databind)
    implementation(libs.observability)
    testImplementation(libs.bundles.testing)
}
```

### Gradle Platform Plugin (cross-project enforcement)

For monorepos, use a `platform` subproject to enforce versions across all subprojects:

```kotlin
// platform/build.gradle.kts
plugins { `java-platform` }

dependencies {
  constraints {
    api("com.fasterxml.jackson.core:jackson-databind:2.16.1")
    api("org.slf4j:slf4j-api:2.0.9")
  }
}
```

```kotlin
// service-a/build.gradle.kts
dependencies {
  implementation(platform(project(":platform")))
  implementation("com.fasterxml.jackson.core:jackson-databind")  // no version
}
```

---

## Managing Transitive Dependencies

Transitive dependencies are the majority of your attack surface — and the hardest to reason about.

### Visualise the Dependency Tree

```bash
# Maven
mvn dependency:tree -Dincludes=log4j

# Gradle
./gradlew :service-a:dependencies --configuration runtimeClasspath | grep log4j

# Show why a version was selected (conflict resolution)
./gradlew :service-a:dependencyInsight --dependency jackson-databind --configuration runtimeClasspath
```

### Dependency Locking (Reproducible Builds)

Without locking, `compile('guava:+')` resolves differently on Monday vs Friday:

```kotlin
// build.gradle.kts
dependencyLocking {
  lockAllConfigurations()
}
```

```bash
# Generate lock files (commit to repo)
./gradlew dependencies --write-locks

# Verify lock files are respected
./gradlew dependencies --no-daemon
```

Lock files (`gradle.lockfile`) are committed to git. PRs that change a dependency version show an explicit lock file diff — reviewers see exactly what transitive tree changed.

### Force-Override a Transitive Dependency (CVE Patching)

When a transitive dependency has a CVE but the direct dependency hasn't released a fix yet:

```kotlin
// Gradle — force the version across all configurations
configurations.all {
  resolutionStrategy {
    force("com.fasterxml.jackson.core:jackson-databind:2.16.1")
    // OR
    eachDependency {
      if (requested.group == "org.apache.logging.log4j") {
        useVersion("2.17.1")
        because("CVE-2021-44228 mitigation — upstream hasn't patched yet")
      }
    }
  }
}
```

```xml
<!-- Maven — use dependencyManagement to override transitive version -->
<dependencyManagement>
  <dependencies>
    <dependency>
      <groupId>org.apache.logging.log4j</groupId>
      <artifactId>log4j-core</artifactId>
      <version>2.17.1</version>  <!-- overrides whatever spring-boot brings in -->
    </dependency>
  </dependencies>
</dependencyManagement>
```

**Track force-overrides explicitly**: comment with CVE ID + expiry. Remove when the upstream library ships a fix — keeping stale overrides masks future CVEs.

---

## Centralising Dependency Governance at Scale

### The Platform BOM Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     PLATFORM TEAM                           │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              platform-bom (versioned)               │   │
│  │  ┌────────────────┐   ┌──────────────────────────┐  │   │
│  │  │  spring-boot   │   │  internal shared libs    │  │   │
│  │  │  bom (import)  │   │  (observability, auth...) │  │   │
│  │  └────────────────┘   └──────────────────────────┘  │   │
│  │  ┌────────────────┐   ┌──────────────────────────┐  │   │
│  │  │  CVE overrides │   │  approved 3rd-party vers │  │   │
│  │  │  (force-pins)  │   │  (jackson, guava, etc.)  │  │   │
│  │  └────────────────┘   └──────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
            │ published to internal Artifactory / Nexus
            ▼
┌──────────────────────────────────┐
│  Service A   Service B   ...     │
│  imports platform-bom            │
│  declares NO versions            │
└──────────────────────────────────┘
```

### BOM Release Cadence

| Trigger | BOM Release Type | Automation |
|---------|-----------------|------------|
| Critical CVE patched | Hotfix (e.g., 2024.1.1) | Renovate creates PR, platform team merges within SLO |
| Monthly Renovate batch | Minor (e.g., 2024.2.0) | Renovate PR auto-merges after green CI |
| Spring Boot major / Java major | Major (e.g., 2025.0.0) | Manual — coordinated migration wave |

### Multi-BOM Strategy (Blast Radius Segmentation)

Don't put everything in one BOM — partition by blast radius:

```
platform-bom-core       — spring-boot, jackson, slf4j, guava
platform-bom-data       — hibernate, flyway, postgres driver, redis client
platform-bom-messaging  — kafka-clients, avro, protobuf
platform-bom-security   — spring-security, jwt, vault client
```

Benefits:
- A CVE in `kafka-clients` triggers a `platform-bom-messaging` release only — services that don't use Kafka are unaffected
- Teams can opt into messaging BOM only when needed
- Smaller blast radius per BOM update

---

## Blast Radius Control

### Risk Tiering for Dependency Updates

```
TIER 1 — Patch version (e.g., 2.16.0 → 2.16.1)
  Risk: Low. Typically bug/CVE fixes, no API change.
  Automation: automerge after green CI (unit + integration tests pass)

TIER 2 — Minor version (e.g., 2.15.x → 2.16.x)
  Risk: Medium. New features, deprecated APIs, behaviour changes.
  Automation: Renovate creates PR, but requires human approval.
  Testing: Run full test suite + manual smoke test for key services.

TIER 3 — Major version (e.g., 2.x → 3.x)
  Risk: High. Breaking API changes, migration required.
  Process: RFC + migration guide + staged rollout by team/service tier.
  Testing: Pilot service migrates first, runs in prod for 2 weeks → org-wide.

TIER 4 — BOM major release (e.g., Java 17 → 21, Spring Boot 2 → 3)
  Risk: Org-wide. Requires coordinated migration wave.
  Process: Platform team publishes migration guide.
           Services migrate service-by-service with deadline.
           Old BOM reaches EOL 90 days after new BOM GA.
```

### Staged Rollout for BOM Updates

```
Week 1:  Platform team deploys to internal tooling services (lowest risk, fastest feedback)
Week 2:  Opt-in wave — teams with strong test coverage voluntarily upgrade
Week 3:  Default new services — new services start with new BOM
Week 4+: Mandatory wave — remaining services migrate; old BOM deprecated
```

Block CI for services still on deprecated BOM version after the deadline:

```yaml
# Enforce minimum BOM version in CI
- name: Check platform BOM version
  run: |
    BOM_VERSION=$(mvn help:evaluate -Dexpression=platform-bom.version -q -DforceStdout)
    MIN_VERSION="2024.1.0"
    if [ "$(printf '%s\n' "$MIN_VERSION" "$BOM_VERSION" | sort -V | head -n1)" != "$MIN_VERSION" ]; then
      echo "ERROR: platform-bom $BOM_VERSION is below minimum $MIN_VERSION"
      echo "Migration guide: https://wiki/platform-bom-migration"
      exit 1
    fi
```

### Private Artifact Proxy — Controlling the Supply Chain

Don't pull from Maven Central directly in production CI:

```
Developer / CI → Artifactory/Nexus (internal proxy) → Maven Central
                          │
                          ├── Caches artifacts (air-gap resilience)
                          ├── Blocks malicious/unlicensed packages (policy engine)
                          ├── Provides audit log (who pulled what, when)
                          └── Allows internal packages alongside public ones
```

Configuration:
```xml
<!-- settings.xml (for all engineers + CI agents) -->
<mirrors>
  <mirror>
    <id>central-proxy</id>
    <mirrorOf>*</mirrorOf>
    <url>https://artifactory.company.com/artifactory/maven-remote</url>
  </mirror>
</mirrors>
```

This ensures:
- Maven Central outage doesn't break your builds
- You can audit exactly which CVE-affected artifact versions were ever pulled
- A compromised package on Maven Central is blocked at the proxy before it reaches a build

---

## Operational Runbook: Responding to a Zero-Day

**Scenario**: Log4Shell drops at 6pm Friday. CVSS 10.0. How do you respond?

```
T+0h:  Alert fires from nightly Trivy scan (or Snyk security feed)
        → Query SBOM inventory: "which services contain log4j-core < 2.17.1?"
        SELECT service, version FROM sbom_inventory
        WHERE package = 'log4j-core' AND version < '2.17.1';

T+1h:  Platform team force-pins log4j-core 2.17.1 in platform-bom
        → Publishes platform-bom hotfix 2024.1.1

T+2h:  Renovate/Dependabot sees new BOM version
        → Creates PRs across all affected services
        → PRs marked `security` label → skip normal review queue

T+4h:  Services with high test coverage automerge (patch tier)
        → Green CI → auto-deploy to staging

T+8h:  Manual review for services with lower test confidence
        → Platform team triages, merges, deploys

T+24h: All services at or above patched version
        → Incident ticket closed, post-mortem scheduled
```

**What makes this possible**:
- Centralised BOM → single point of update, not 200 services patching independently
- SBOM inventory → instant blast radius assessment (no manual auditing)
- Automated PR generation → no manual dependency bumping across repos
- SLO-enforced timeline → teams can't ignore it

---

## FAANG Interview Callouts

**Q: A zero-day drops in a popular Java library. How do you assess and remediate across 300 microservices?**

Structure your answer around four capabilities:
1. **Inventory** — SBOM per service + central query layer. "Which services use log4j-core < 2.17.1?" should be a 10-second query.
2. **Blast radius segmentation** — BOM partitioning means only services importing the affected BOM slice are at risk.
3. **Automated remediation** — BOM hotfix → Renovate creates PRs → automerge for high-trust services → manual review for critical/low-coverage services.
4. **Enforcement** — CI blocks deploys for services still on vulnerable BOM past the SLO deadline.

**Q: How do you prevent dependency sprawl in a 50-team monorepo?**

- Gradle Version Catalog (single `libs.versions.toml`) as the sole source of truth for versions
- Platform plugin enforces constraints — services that violate emit a build warning, eventually an error
- PR bot checks: "this service is adding a new library not in the version catalog — requires platform team approval"
- `./gradlew dependencyInsight` is the standard debugging tool — it's fast and precise

**Q: How do you balance developer autonomy (teams pick their own libs) vs. security governance?**

- Approved library list in the internal Artifactory policy — pulls from unapproved packages fail with a link to the approval process
- Fast-track approval process for well-known, low-risk libraries (< 48 hours)
- Security team reviews: license (GPL vs Apache), CVE history, maintenance activity (last commit date, open CVE count)
- Teams can carry their own approved deviations; the platform team audits quarterly

**Q: Transitive dependency conflict — two libraries require incompatible versions of the same package. How do you resolve it?**

1. `./gradlew dependencyInsight` to see the full resolution tree and conflict origin
2. Check if the newer version of either direct dependency resolves the conflict (upgrade first, don't force)
3. If not, force-pin the version that doesn't break either consumer — validate with the test suite
4. Document the force override with reason + expiry
5. File an upstream issue — long-term, the fix lives in the library, not your build file
