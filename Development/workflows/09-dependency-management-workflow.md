# Dependency Management Workflow

## Why This Matters at Principal Engineer Level

Dependencies are the primary vector for supply chain attacks, the primary source of security vulnerabilities in modern software, and a major driver of long-term maintenance burden. At principal engineer level, you set the dependency governance policy: what gets approved, how versions are managed, how vulnerabilities are tracked and patched, and how the organization avoids both dependency sprawl (too many libraries for the same purpose) and ossification (dependencies that never get updated).

The Log4Shell vulnerability in 2021 demonstrated that a single widely-used dependency can affect millions of systems simultaneously. Organizations with a mature dependency management workflow patched in hours; those without one took weeks or months.

---

## Dependency Risk Model

Every dependency you accept is a liability you accept. Before adding a dependency, understand what risk you're accepting.

### Risk Dimensions

| Risk Type | Questions to Ask |
|-----------|----------------|
| **Security** | How frequently does this library have CVEs? Is it actively maintained? |
| **Supply chain** | How many transitive dependencies does this add? Who owns the publish pipeline? |
| **Maintenance** | Is the project actively maintained? When was the last commit? |
| **License** | Is the license compatible with your product's license? (GPL vs. MIT vs. commercial) |
| **Stability** | Does the library have a stable public API or does it change frequently? |
| **Footprint** | What is the bundle/binary size impact? Does this matter for the platform? |
| **Redundancy** | Do you already have a library that does this? (Avoid two libraries for the same problem) |

### Dependency Evaluation Criteria (before adding)

```
□ Purpose: What does this library do that existing code or stdlib cannot?
□ Alternatives: Did you evaluate 3+ alternatives? What's the trade-off matrix?
□ Maintenance health:
  - Last commit: < 6 months ago
  - Open issues: reasonable volume; not hundreds of untriaged bugs
  - Active maintainers: 2+ maintainers (1 = bus factor = 1)
  - Stars/adoption: widely used = faster CVE discovery + patches
□ License: Compatible with product license (MIT/Apache 2.0 preferred)
□ CVE history: Zero critical/high CVEs in the last 12 months? Or were they patched quickly?
□ Transitive dependency count: How many new transitive deps does this add?
□ Version pinning: Can you pin to a specific version in a lockfile?
□ Update cadence: How often do breaking changes occur? Does the team maintain CHANGELOG?
```

### Dependency Categories

| Category | Governance Level | Examples |
|----------|-----------------|---------|
| **Foundational** | Strict: requires arch review | Web framework, ORM, messaging library, crypto library |
| **Utility** | Standard: team lead approval | Date handling, JSON parsing, HTTP client |
| **Development** | Lightweight: peer review | Test frameworks, linters, build tools |
| **Transitive** | Automated: dependency scanning | Added indirectly; governed by lockfile and scanner |

---

## Dependency Governance Process

### Adding a New Dependency (Decision Flow)

```
Engineer wants to add a new dependency
           │
           ▼
Does stdlib or an existing approved dependency solve this?
  Yes → Use existing; no new dependency
  No ↓
           ▼
Evaluate using criteria above (< 30 min research)
           │
           ▼
Is this a foundational dependency? (framework, security, infra)
  Yes → Architecture review required (design doc or RFC)
  No ↓
           ▼
Does it have a current critical/high CVE?
  Yes → Choose a different library
  No ↓
           ▼
PR with dependency added; peer reviewer approves
           │
           ▼
Automated dependency scan in CI (Snyk, Dependabot, OWASP)
           │
           ▼
Scan passes → Merge
Scan fails (CVE found) → Block; author must resolve
```

### Approved Dependency Registry

For large organizations, maintain an approved dependency list per language/ecosystem to avoid the "N libraries doing the same thing" problem:

```markdown
## Approved Dependencies — Java / Spring Boot

| Category | Approved Library | Version | Notes |
|----------|----------------|---------|-------|
| Web framework | spring-boot-starter-web | 3.2.x | |
| Database ORM | spring-data-jpa + hibernate | 6.x | |
| Database migrations | flyway | 10.x | |
| HTTP client | spring-webclient | bundled | Prefer over OkHttp for Spring apps |
| JSON serialization | jackson-databind | 2.15.x | |
| Testing | junit5 + mockito | 5.x | |
| Observability | micrometer + opentelemetry | latest stable | |
| Security | spring-security | bundled | |
| Cryptography | bcprov-jdk18on | latest | Never roll your own crypto |
| Caching | caffeine (local) / redisson (Redis) | latest | |

## Unapproved (do not add without arch review)
- Lombok (code generation; hides logic; onboarding friction)
- Guava (almost entirely superseded by stdlib and Apache Commons)
- Log4j 1.x (EOL; CVEs)
```

---

## Version Pinning Strategy

### Lockfiles — the Foundation

Every language ecosystem has a lockfile mechanism. Lockfiles are the single most important dependency management practice: they ensure that every environment (dev, CI, staging, production) runs the exact same dependency versions.

| Language | Lockfile |
|---------|---------|
| Java/Maven | `pom.xml` with explicit `<version>` + no SNAPSHOT in production |
| Java/Gradle | `gradle/wrapper/gradle-wrapper.properties` + dependency locking |
| Python | `requirements.txt` with pinned versions OR `poetry.lock` / `Pipfile.lock` |
| Node.js | `package-lock.json` or `yarn.lock` |
| Go | `go.sum` |
| Ruby | `Gemfile.lock` |
| Rust | `Cargo.lock` |

**Lockfile anti-patterns**:
```
BAD: requirements.txt
  django>=4.0        # can resolve to any version ≥ 4.0

GOOD: requirements.txt
  django==4.2.7     # exact version; reproducible builds

BAD: Gitignored lockfile
  # Some teams gitignore package-lock.json
  # This means each CI run may resolve different versions

GOOD: Lockfile checked into version control; never gitignored
```

### Version Update Strategy

**Semantic versioning** (how to interpret updates):

```
MAJOR.MINOR.PATCH (e.g., 2.4.1)

PATCH: 2.4.1 → 2.4.2  Bug fixes; safe to update immediately
MINOR: 2.4.x → 2.5.0  New features; backward-compatible; update within 1 sprint
MAJOR: 2.x.y → 3.0.0  Breaking changes; plan carefully; test thoroughly
```

**Update cadence policy**:

| Update Type | When to Apply |
|------------|--------------|
| Security patch (any severity) | Within 24 hours (critical/high); within 1 sprint (medium/low) |
| PATCH version | Monthly automated PR (Dependabot / Renovate) |
| MINOR version | Quarterly; include in a "dependency maintenance" sprint |
| MAJOR version | Planned; requires testing; schedule in roadmap |

---

## Vulnerability Management

### Automated Scanning Pipeline

Every repository must have automated dependency vulnerability scanning:

```
CI Pipeline Stage: Dependency Security Scan
    │
    ├── Run: Snyk / Dependabot / OWASP Dependency Check
    │
    ├── Output: list of CVEs with severity (Critical / High / Medium / Low)
    │
    └── Gate:
        Critical CVE → Block merge (fail CI)
        High CVE     → Block merge (fail CI)
        Medium CVE   → Warn; create ticket; don't block
        Low CVE      → Track; no immediate action required
```

**Tools**:
- **Dependabot** (GitHub-native): Automatic PRs for vulnerable dependency updates
- **Snyk**: Deep scanning including transitive dependencies; license compliance
- **OWASP Dependency Check**: Open source; integrates with Maven, Gradle, npm
- **Renovate**: Highly configurable auto-update bot; more control than Dependabot
- **Trivy**: Container image scanning (catches OS-level CVEs in your Docker base image)

### CVE Response SLA

| Severity | Discovery to Patch Target |
|----------|--------------------------|
| **Critical** (CVSS 9.0–10.0) | 24 hours (emergency change process) |
| **High** (CVSS 7.0–8.9) | 72 hours |
| **Medium** (CVSS 4.0–6.9) | 2 weeks (next sprint) |
| **Low** (CVSS 0.1–3.9) | Next quarterly dependency maintenance |

**Critical CVE response workflow**:
```
T+0: Vulnerability disclosed (NVD / GitHub Advisory / vendor notification)
T+0: Automated scanner flags affected repositories
T+1h: Owner notified (pagerduty if actively exploited; Slack otherwise)
T+2h: Assess exploitability: is the vulnerable code path reachable from our usage?
T+4h: If exploitable: initiate patch; follow emergency change process
T+24h: Patch deployed; incident retrospective if production exposure was possible
```

### Dealing with Slow-to-Patch Dependencies

When a dependency has a CVE and no patch is available yet:

```
Options in order of preference:
1. Replace the dependency (if alternative exists with no CVE)
2. Implement a compensating control:
   - WAF rule blocking the attack vector
   - Network policy restricting access to the vulnerable component
   - Application-level input validation that neutralizes the exploit vector
3. Accept the risk (only for low/medium severity; requires explicit sign-off):
   - Document the CVE, the reason for deferral, and a review date
   - Add to risk register
   - Monitor for patch availability
4. Pin to last safe version and do NOT update until patch is available
```

---

## Transitive Dependency Management

The dependency you add is the easy part. The hard part is the transitive dependency tree.

```
Your app adds: library-A (v1.0)
  library-A depends on: library-B (v2.0) → library-C (v3.0)
                        library-D (v1.5) → library-E (v0.9.1)  ← CVE!
                        
You now have 5 new dependencies, and you may not have reviewed library-E at all.
```

### Transitive Dependency Hygiene

```
□ Run dependency tree visualization regularly:
  Maven:  mvn dependency:tree
  Gradle: ./gradlew dependencies
  npm:    npm ls --all
  Python: pip show <package>; pipdeptree
  Go:     go mod graph

□ Review the transitive count when adding a new direct dependency:
  "This one library adds 47 transitive dependencies" → reconsider the choice

□ Use dependency exclusions for known-problematic transitive deps:
  Maven: <exclusion> blocks a specific transitive dep
  npm:   overrides in package.json (with care; may break the parent library)

□ Lock transitive dependencies in the lockfile (not just direct dependencies)

□ Quarterly: run a full dependency tree scan and review anything unexpected
```

### Duplicate Dependency Problem

Multiple libraries doing the same thing — common in large monorepos:

```
Example (Node.js): 3 different HTTP client libraries in one repo
  axios (added by team A in 2019)
  node-fetch (added by team B in 2020)
  got (added by team C in 2021)

Impact:
  - 3× the vulnerability surface
  - 3× the update burden
  - New engineers don't know which to use; add a 4th

Solution: Define a standard per-ecosystem; deprecate non-standard choices
  Step 1: Audit: find all HTTP client usages
  Step 2: Decide: pick one (e.g., axios); document the decision in ADR
  Step 3: Migrate: replace node-fetch and got usages over 1 quarter
  Step 4: Enforce: add lint rule blocking import of non-standard clients
```

---

## Dependency Lifecycle

### End-of-Life (EOL) Dependency Management

A dependency reaching end-of-life means:
- No more security patches
- No more bug fixes
- Gradual divergence from platform best practices

**Track EOL dates**:

```
EOL Tracking Table (update quarterly):
| Dependency | Current Version | EOL Date | Upgrade Target | Owner | Deadline |
|-----------|----------------|----------|----------------|-------|---------|
| Java 11 JDK | 11.0.20 | Sep 2026 | Java 21 LTS | @alice | Q2 2026 |
| Spring Boot 2.x | 2.7.14 | Nov 2023 | Spring Boot 3.x | @bob | Q1 2024 |
| Node.js 16 | 16.20.2 | Sep 2023 | Node.js 20 LTS | @carol | Done |
| PostgreSQL 13 | 13.12 | Nov 2025 | PostgreSQL 16 | @dave | Q4 2025 |

Source for EOL dates: https://endoflife.date
```

**EOL upgrade priority**:
- Already EOL with CVEs → Emergency upgrade
- EOL within 6 months → Schedule in next quarter's roadmap
- EOL within 12 months → Plan; no urgency yet

---

## License Compliance

Dependency licenses constrain how your product can be distributed. Get this wrong and you have a legal problem.

### License Compatibility Matrix

| License Type | Commercial Use | Modification Required | Share Alike | Use In SaaS |
|-------------|---------------|----------------------|-------------|------------|
| **MIT / Apache 2.0 / BSD** | ✓ Yes | Not required | No | ✓ Yes |
| **LGPL** | ✓ Yes (with care) | Must share LGPL portions | LGPL parts only | ✓ Yes (typically) |
| **GPL v2 / v3** | Depends on linking | Must open source your code | Yes (copyleft) | Complex — consult legal |
| **AGPL** | Requires open source | Must open source + network use | Yes | ✗ No (in most cases) |
| **Commercial** | ✓ If licensed | Per license terms | N/A | ✓ If licensed |
| **CC-BY-SA** | Not for software | — | — | Not for software |

**Policy for commercial SaaS products**:
```
Approved: MIT, Apache 2.0, BSD (2-clause, 3-clause), ISC, MPL 2.0 (with care)
Review required: LGPL, GPL (consult legal; depends on linking model)
Prohibited without legal approval: AGPL, GPL v3 (if modifying and distributing)
```

**Automated license scanning**:
```
Tools:
  - FOSSA: commercial; comprehensive license scanning + compliance reports
  - Licensee: open source; checks license compatibility
  - license-checker (npm): scans node_modules for licenses
  - go-licenses (Go): scans Go module licenses

CI gate:
  - Fail build if an AGPL or GPL (non-LGPL) license is detected in a new dependency
  - Warn on LGPL (requires legal review)
  - Pass on MIT/Apache/BSD
```

---

## FAANG Interview Framing

### "How do you manage dependency security at scale across 100+ services?"

> "At scale, manual dependency management is not possible — it has to be automated. My model has three layers. First, the prevention layer: an approved dependency registry and a pre-merge CI gate that blocks any dependency with a known critical or high CVE. Engineers can't accidentally ship a known-vulnerable dependency because the CI system won't let them merge. Second, the detection layer: automated scanning runs daily across all repositories, not just at merge time. New CVEs are discovered after merge, so you need continuous scanning to find vulnerabilities introduced in previously-safe dependencies. This generates a vulnerability backlog that's triaged by severity. Third, the response layer: a clear SLA — critical CVEs patched in 24 hours, high in 72 hours — with an escalation path that routes to the team's on-call engineer if the SLA is at risk. The thing most teams get wrong is relying entirely on developers to notice CVEs. At 100+ services, you need automation to surface them, automated PRs to simplify patching (Dependabot), and an SLA-backed process to drive them to closure."

### "Log4Shell just dropped. Walk me through your response."

> "The first question is exposure assessment — which of our services use log4j? I don't rely on engineers to self-report; I run an automated scan across all repositories using the dependency scanning toolchain we have in place. Within 2 hours, I have a list of every affected service with the version being used. The second question is exploitability — is the JNDI lookup vector reachable? In most web applications it is, because user-controlled input like HTTP headers (User-Agent, X-Forwarded-For) was logged using log4j. I assume exploitable unless proven otherwise. For each affected service, I initiate an emergency change: update log4j to the patched version (2.16+), run the CI pipeline, deploy through canary. For services where an immediate update is not possible (complex build dependencies), I implement a compensating control — a WAF rule blocking JNDI lookup patterns in incoming requests. I track resolution status in a war-room Slack channel with real-time updates, and I give engineering leadership a status update every 2 hours. The entire patching effort completes within 24 hours for all internet-facing services."
