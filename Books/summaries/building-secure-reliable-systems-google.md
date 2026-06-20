# Building Secure & Reliable Systems
**Authors:** Heather Adkins, Betsy Beyer, Paul Blankinship, Ana Oprea, Piotr Lewandowski, Adam Stubblefield  
**Publisher:** O'Reilly / Google (2020)  
**Relevance:** Security + reliability engineering at FAANG scale — essential for principal engineers owning production systems

---

## Why This Book Matters for Principal Engineers

Security and reliability are not separate disciplines bolted on after the fact — they are **system properties that must be designed in from day one**. This book, written by the Google SRE and security teams who protect one of the world's largest infrastructures, makes a single foundational argument:

> **Reliability and security are two sides of the same coin.** A system that goes down under load and a system that goes down under attack have the same root cause: insufficient design discipline.

For principal engineer candidates, this book provides:

1. **The mental model** — Security is availability, integrity, and confidentiality. Reliability is availability and correctness. They overlap, and you should reason about them together.
2. **Organizational patterns** — How do you build and run teams that keep both properties? What processes scale from startup to millions of machines?
3. **Incident playbooks** — What does Google actually do when things go wrong (breach, outage, or both)?
4. **Design principles** — Concrete heuristics you can apply at architecture review time.

---

## Core Thesis

The book's central argument is **"Security and Reliability by Design"** — shifting both concerns left into architecture, APIs, libraries, and defaults rather than auditing and patching after the fact. Key corollaries:

- The cheapest security fix is the one you designed out of possibility
- The cheapest reliability fix is the one you designed out of possibility  
- Adversarial thinking (what would an attacker do?) and reliability thinking (what would a cascading failure do?) use the same cognitive toolkit
- Humans are the weakest link in both security and reliability — design systems that constrain human error surface

---

## Core Themes

| Theme | Central Idea |
|---|---|
| **Intersection of security and reliability** | They share failure modes: DoS = availability failure; data corruption = integrity failure |
| **Design for adversaries** | Assume breach; design for detection and containment, not just prevention |
| **Least privilege** | The minimum access needed is the only access granted — always |
| **Defense in depth** | No single control is sufficient; layer independent controls |
| **Blast radius reduction** | Contain failures so they don't cascade across the system |
| **Organizational culture** | Security and reliability require a blameless, learning culture — not fear |
| **Understandability** | A system you don't understand, you cannot secure or make reliable |

---

## Part I: Intersection of Security and Reliability

---

### Chapter 1: The Intersection of Security and Reliability

#### The Two Disciplines Compared

The authors establish that security teams and SRE teams historically operated in silos, yet their goals and failure modes overlap almost entirely:

| Dimension | Reliability | Security |
|---|---|---|
| **Adversary** | Physics, complexity, bugs | Malicious actors |
| **Availability threats** | Hardware failure, cascading overload | DDoS, ransomware |
| **Integrity threats** | Bit rot, data corruption, race conditions | Data tampering, injection attacks |
| **Confidentiality threats** | Accidental exposure via logging/cache | Data exfiltration |

**Key insight**: A DoS attack is a reliability event. A data exfiltration is a confidentiality event. Both can result from poor design. Thinking about your system from both lenses simultaneously is a principal engineer superpower.

#### Reliability Tenets That Also Apply to Security

- **Redundancy**: Redundant systems are harder to take down and harder to fully compromise
- **Monitoring and alerting**: You can't respond to a breach you can't detect — same as an outage
- **Graceful degradation**: A system that degrades safely under load also degrades more safely under attack

#### The CIA Triad Extended

The book expands the classic CIA triad (Confidentiality, Integrity, Availability) to include:
- **Safety**: Physical safety for hardware and humans
- **Accountability**: Audit trails that allow forensics after an incident
- **Understandability**: If an operator cannot reason about the system state, they cannot respond to incidents

> *Principal Engineer lens: When designing systems, explicitly call out where each CIA dimension is at risk. A data pipeline that processes PII risks confidentiality; a write path with eventual consistency risks integrity; a synchronous critical path risks availability.*

---

### Chapter 2: Understanding Adversaries

#### Adversary Taxonomy

Understanding who you're designing against determines what controls are proportionate. The book categorizes adversaries by:

| Tier | Who | Capability | Example |
|---|---|---|---|
| **Nation-state** | Government-backed APT | Highest: zero-days, supply chain, insider access | APT41, Lazarus Group |
| **Organized crime** | Criminal syndicates | High: ransomware, credential stuffing at scale | REvil, Conti |
| **Hacktivists** | Ideologically motivated | Medium: DDoS, defacement, data leaks | Anonymous |
| **Script kiddies** | Opportunistic | Low: automated scans, known CVE exploitation | Mass scanning botnets |
| **Insiders** | Current/former employees | Varies: high access, low detection | Disgruntled employees, accidental |

**Design implication**: The right threat model depends on who you realistically face. A fintech startup protecting payments faces organized crime more than APTs. A defense contractor faces nation-states. Your controls must be calibrated to the realistic adversary, not a fantasy worst case that results in unusable systems.

#### Attacker Goal vs. Defender Goal Asymmetry

One of the most important insights in the book:

> **Attackers need to find one path in. Defenders need to close all paths.**

This asymmetry is why defense-in-depth, assume-breach, and detection are critical. You will not achieve perfect prevention. Design for detection and containment as first-class objectives.

#### The Kill Chain Mental Model

The book references the cyber kill chain:
1. **Reconnaissance** — Gathering information
2. **Weaponization** — Developing the exploit
3. **Delivery** — Getting the payload to the target
4. **Exploitation** — Triggering the vulnerability
5. **Installation** — Establishing persistence
6. **Command & Control** — Communicating with the attacker
7. **Actions on Objective** — Data theft, destruction, pivoting

**Principal engineer application**: Each stage of the kill chain is an opportunity to detect or disrupt. A defense-in-depth design should have controls targeting multiple stages, so that breaking through one stage doesn't give the attacker a clear path to their objective.

---

## Part II: Designing for Security and Reliability

---

### Chapter 3: Case Study — Safe Proxies

#### What Is a Safe Proxy?

Google's approach to giving engineers and automated systems access to production: instead of granting direct access, all access goes through a **safe proxy** — a gateway that:
- Enforces authentication and authorization
- Logs all actions with full audit trail
- Rate-limits and throttles dangerous operations
- Can inject approval workflows for high-impact actions
- Can be revoked instantly

#### Why Proxies Over Direct Access

Direct production access is a reliability and security anti-pattern:
- **Blast radius**: One misconfigured command can affect every machine
- **Auditability**: SSH sessions are opaque; proxied commands are logged
- **Automation hygiene**: Scripts that SSH into production are effectively ungated

**Design pattern**: Build every internal tool as if it will someday be called by an attacker who has compromised a service account. Proxies enforce this by design.

#### Proxy Design Principles

1. **Idempotency checking** — Warn when a command would be non-idempotent
2. **Safety labels** — Commands are labeled safe/unsafe/destructive; rate limits differ by label
3. **Approval chains** — Destructive operations require a second human approval
4. **Dry-run mode** — All commands must support `--dry-run` that shows effect without applying
5. **Rollback support** — The proxy tracks state changes and can generate a rollback plan

> *Interview callout: Safe proxies are an architectural pattern for achieving "least privilege at the action level, not just the role level." Mention this when asked about access control in system design.*

---

### Chapter 4: Design Tradeoffs

#### Security vs. Usability

The most common anti-pattern in security: **make it so secure that people work around it**. A security control that is bypassed provides no protection; it provides false confidence. 

**The usability test**: Would a reasonable engineer, under time pressure, follow this control or route around it? If the answer is "route around it," the control will fail in production.

**Google's answer**: Build security into the **happy path**, not as friction on top of it. Example: requiring a certificate for all internal service communication (mTLS everywhere) removes the decision — you can't opt out, so there's nothing to bypass.

#### Reliability vs. Security Tensions

| Tension | Reliability Preference | Security Preference | Resolution |
|---|---|---|---|
| **Change velocity** | Deploy fast to fix outages | Slow down to audit changes | Automated security checks in CI/CD |
| **Logging verbosity** | Log everything for debugging | Don't log PII or credentials | Structured logging with redaction |
| **Access breadth** | Everyone can touch everything to fix incidents | Least privilege always | Break-glass accounts with mandatory review |
| **Encryption overhead** | Raw performance | Always encrypt in transit and at rest | Hardware acceleration (AES-NI), modern TLS |

#### Break-Glass Access

For operational emergencies where normal access paths are insufficient:

- A **break-glass account** provides elevated access but triggers:
  - Mandatory peer review of all actions taken
  - Automatic security alert to the security team
  - Post-incident review requirement
  - Time-bounded access (auto-expires after N hours)

**Design principle**: Don't eliminate emergency access — you will need it. Instead, make emergency access **auditable and reviewable**, so it deters misuse without blocking legitimate use.

---

### Chapter 5: Least Privilege

#### The Principle

> Grant only the minimum permissions required to complete the task, and revoke them as soon as the task completes.

Least privilege is the single highest-leverage security control because it limits blast radius. A compromised service can only do what that service was permitted to do.

#### Least Privilege in Practice

**For humans:**
- Role-based access control (RBAC) with well-defined roles, not ad-hoc permissions
- Time-bounded access: access grants expire and require renewal
- Just-in-time (JIT) access: request access for a specific task, access is granted, access expires
- No standing admin access in production

**For services:**
- Service accounts with minimum scopes
- Workload identity (service X gets credentials by proving it is service X, not by holding a secret)
- No sharing credentials between services
- Secrets management: secrets injected at runtime, never in code or config files

**For data:**
- Column-level access control for sensitive tables
- Data classification: PII, PCI, PHI get stricter controls than operational metrics
- Data masking in non-production environments

#### Privilege Escalation Attack Surface

Every permission grant is a potential escalation path. The book emphasizes **auditing permission grants** as a key security monitoring signal. Unexpected privilege escalation is often the earliest detectable signal of an active attack.

> *Principal Engineer lens: When reviewing a system design, ask "what is the blast radius if this service account is compromised?" If the answer is "everything," the design has a least-privilege failure.*

---

### Chapter 6: Understandability

#### Why Understandability Is a Security Property

A system that operators cannot understand:
- Cannot be correctly configured
- Cannot be correctly monitored
- Cannot be correctly debugged during an incident
- Cannot be correctly audited after a breach

**Understandability is not just a developer experience concern — it is a security control.** Complexity is an attacker's ally; simplicity is the defender's ally.

#### Complexity Anti-Patterns

| Anti-Pattern | Why It Harms Security and Reliability |
|---|---|
| **Security theater** | Controls that look secure but don't reduce risk (e.g., password complexity rules without rate limiting) |
| **Layered permissions** | Permission systems where the effective permission requires tracing through 5 inheritance levels |
| **Configuration sprawl** | Thousands of config flags, many with security implications, with no central understanding |
| **"Just SSH in"** | Unlogged, untracked access that leaves no audit trail |
| **Cargo-cult security** | Controls copied from another system without understanding why they exist |

#### Principles for Understandable Systems

1. **Invariants over complex logic** — "No user data ever leaves region X" is an invariant; check it in the architecture, not just in the code
2. **Policy as code** — Security policy encoded in code (OPA, Rego) is reviewable, testable, and auditable
3. **Declarative over imperative security** — Describe what is allowed (allowlist), not what is forbidden (denylist)
4. **Small, auditable surfaces** — Prefer narrow APIs over broad ones; every endpoint is attack surface
5. **Runbooks with "why"** — Operational runbooks should explain why each step matters, so operators don't blindly follow steps that may not apply

---

### Chapter 7: Designing Systems for Resiliency

#### Failure Domains

A **failure domain** is the blast radius of a single failure. Good reliability design constrains failure domains so that no single failure brings down the entire system.

| Level | Failure Domain | Design Technique |
|---|---|---|
| **Host** | Single machine | Redundant replicas |
| **Rack** | Rack power/network | Spread replicas across racks |
| **Datacenter** | DC power/network | Multi-DC deployment |
| **Region** | Region-level events | Multi-region with independent control planes |
| **Global** | Global BGP, DNS | Multi-cloud or active-active global |

**Security corollary**: Failure domains limit attack blast radius. If an attacker compromises one replica, they shouldn't automatically compromise all replicas. Achieve this through:
- Different credentials per replica
- Network segmentation between failure domains
- Blast radius limiting at the data layer (sharding, tenant isolation)

#### Defense-in-Depth for Reliability

Reliability defense-in-depth mirrors security defense-in-depth:

1. **Prevention**: Write correct code, test thoroughly, validate inputs
2. **Detection**: Monitoring, alerting, anomaly detection
3. **Mitigation**: Feature flags, circuit breakers, graceful degradation
4. **Recovery**: Rollback, backup restoration, disaster recovery

No single layer is sufficient. The principal engineer's job is to ensure all four layers exist and are tested.

#### Chaos Engineering as a Security Tool

Chaos engineering (deliberately injecting failures) is discussed as a **shared tool** between reliability and security teams:
- Reliability use: Does the system degrade gracefully under failure?
- Security use: Does the system behave correctly when a component is compromised?

Running regular "fire drills" — including security breach simulations — ensures the organization's response muscles are exercised before they're needed.

---

### Chapter 8: Designing Resilient APIs

#### APIs as Security Boundaries

Every API is a trust boundary: the caller is in a different trust context from the callee. The book establishes API design principles from this security-first perspective:

**Principle 1: Narrow surface area**
Every endpoint, parameter, and return value is attack surface. APIs should expose exactly what callers need and nothing more. Avoid "convenience" endpoints that return everything.

**Principle 2: Input validation at the boundary**
Validate all inputs at the API boundary before any processing. Never trust caller-supplied data, even from internal services. Trust levels:
- Internet callers: trust nothing, validate everything
- Internal service callers: trust identity (via mTLS), validate all data
- Privileged internal services: trust identity + role, validate destructive operations

**Principle 3: Idempotency**
Idempotent APIs are both more reliable (retries are safe) and more auditable (duplicate calls are detectable). Design every write operation with a client-generated idempotency key.

**Principle 4: Rate limiting and quotas**
Rate limiting protects both reliability (prevents overload) and security (limits automated attack impact). Apply limits at multiple levels: per IP, per user, per API key, per tenant.

**Principle 5: Auditability**
Every API call that modifies state should be logged with:
- Who called (authenticated identity)
- What was called (operation + parameters, redacted for PII)
- When (timestamp with nanosecond precision)
- From where (IP, service identity)
- Result (success/failure + error code)

---

## Part III: Implementing Security and Reliability

---

### Chapter 9: Designing for Recovery

#### Recovery as a First-Class Design Goal

Most systems are designed to work correctly. Fewer are designed to recover correctly. The book argues recovery design is as important as happy-path design:

- **Mean Time to Recovery (MTTR)** is the metric that actually matters during incidents, not MTBF
- **Recovery time objective (RTO)** and **recovery point objective (RPO)** should be explicit requirements, not afterthoughts
- A system that takes 4 hours to restore from backup has a different risk profile than one that auto-heals in 30 seconds

#### Recovery Patterns

| Pattern | Recovery Type | When to Use |
|---|---|---|
| **Hot standby** | Sub-second failover | Lowest RTO requirement, highest cost |
| **Warm standby** | Minutes to failover | Medium RTO, moderate cost |
| **Cold standby** | Hours to restore | High RTO acceptable, lowest cost |
| **Backup + restore** | Hours to days | Rarely used for primary services; archive use |
| **Active-active** | Zero failover (no failover needed) | Highest availability, complex consistency |

#### Backup Design Principles

Backups are useless unless tested. The book emphasizes:

1. **Regular restore drills** — Prove you can restore, not just that you're writing backups
2. **Immutable backups** — Backups must be write-protected; ransomware targets mutable backup stores
3. **Separate trust domain** — Backup infrastructure should be in a separate IAM domain; a compromised production account should not be able to delete backups
4. **Versioned backups** — Multiple backup generations protect against logical corruption (corruption may not be immediately detected)
5. **Off-site backups** — Protect against site-level failures and physical disasters

#### Incident Response Design

Systems should be designed to facilitate incident response:

- **Kill switches**: Every major feature should have an instant disable mechanism
- **Debug modes**: Safe, read-only debugging modes that expose internal state without modifying it
- **Traffic control**: The ability to drain, shift, or block traffic at multiple levels (DNS, load balancer, feature flag)
- **Rate of change control**: Canary deployments, progressive rollouts, and the ability to halt a rollout

---

### Chapter 10: Mitigating Denial-of-Service Attacks

#### DoS as a Reliability Problem

The book explicitly frames DoS attacks as a reliability problem with a malicious cause. The defenses are the same defenses used for organic traffic spikes:

**Layer 3/4 (Network) DDoS:**
- **Volume-based attacks**: UDP floods, ICMP floods — mitigated by upstream scrubbing (CDN, DDoS-mitigation services like Project Shield, Cloudflare)
- **Protocol attacks**: SYN floods — mitigated by SYN cookies, rate limiting at the network edge

**Layer 7 (Application) DoS:**
- **Request flooding**: Brute force requests — mitigated by application-level rate limiting, CAPTCHAs
- **Expensive query attacks**: Attacker sends requests that trigger expensive backend operations — mitigated by query cost budgets, timeouts, circuit breakers
- **Amplification attacks**: Small request triggers large response — mitigated by response size limits, pagination

#### Rate Limiting Architecture

The book describes Google's rate limiting stack:

1. **Edge rate limiting** (CDN / load balancer): Coarse limits, protect infrastructure
2. **API gateway rate limiting**: Per-user, per-tenant, per-API-key limits
3. **Service-level rate limiting**: Protects downstream dependencies
4. **Database-level rate limiting**: Query rate limits, connection pool limits

**Key design decision**: Where you rate limit determines the blast radius of a DoS attack. Rate limiting at the edge is cheapest (stops traffic before it hits your servers). Rate limiting at the database is most expensive (traffic traversed your entire stack before being rejected). You need both: edge limits for volumetric attacks, service limits for sophisticated application-level attacks.

#### Adaptive Rate Limiting

Static rate limits fail when:
- Organic traffic spikes look like DoS attacks
- DoS attacks stay just under static thresholds

**Adaptive limits** adjust based on current system load: when the system is healthy, limits are relaxed; when the system is stressed, limits are tightened. This is a feedback control loop — the same mechanism as an auto-scaling group, applied to access control.

---

### Chapter 11: Handling Sensitive Data

#### Data Classification

The book's framework for classifying data sensitivity:

| Classification | Example | Control Requirements |
|---|---|---|
| **Public** | Marketing copy, open-source code | No special controls |
| **Internal** | Internal docs, non-sensitive configs | Access requires authentication |
| **Confidential** | Customer data, internal financial data | Encryption at rest + in transit, access logging |
| **Restricted** | PII, PCI, PHI, credentials, keys | Encryption, strict access control, audit logging, data minimization |

**Data minimization** is the first and most effective control: don't collect data you don't need, and delete data you no longer need. You can't lose data you don't have.

#### Secrets Management

Secrets (API keys, database passwords, certificates, encryption keys) require special handling:

**Anti-patterns:**
- Secrets in source code (git blame finds them forever)
- Secrets in environment variables (visible in process list, logs)
- Secrets in config files checked into version control
- Shared secrets across services
- Secrets that never rotate

**Recommended pattern:**
1. **Secret management service** (Vault, AWS Secrets Manager, GCP Secret Manager)
2. **Dynamic secrets**: Secrets generated per-request with short TTLs
3. **Workload identity**: Service proves its identity via attestation (not a long-lived secret)
4. **Automatic rotation**: Rotation happens automatically on a schedule, with the application handling key rollover gracefully
5. **Audit logging**: Every secret access logged

#### Encryption

**At rest:**
- Encryption at the storage layer (disk encryption) is table stakes but protects only against physical media theft
- Application-level encryption (envelope encryption) protects against a compromised storage backend
- Key management is the hardest part: where do the keys live? (Cloud KMS, HSM)

**In transit:**
- TLS 1.3 everywhere, including internal service-to-service
- mTLS for service-to-service (mutual authentication — both sides prove identity)
- Certificate pinning where the threat model justifies it
- No plaintext protocols on internal networks (not even between "trusted" services)

**Key hierarchy (Google's model):**
```
Master Key (HSM-protected, rarely used)
  └── Data Encryption Key (DEK) — per-dataset or per-record
        └── Encrypted data
```
The DEK is encrypted with the master key (key-encrypting key). Rotation of the master key doesn't require re-encrypting all data — only the DEKs need to be re-encrypted.

---

### Chapter 12: Writing Code

#### Secure Coding Principles

The book translates security principles into code-level guidance:

**1. Prefer safe APIs over unsafe ones**
Languages and libraries often provide both a safe and an unsafe version of operations. Always use the safe version.
- `parameterized_query(sql, params)` over string concatenation SQL
- `os.path.join()` over string concatenation for paths
- Cryptographic libraries over rolling your own crypto

**2. Input validation**
Validate inputs at the earliest possible point, before any processing:
- Type checking
- Range checking (min/max values)
- Format validation (regex, schema)
- Allowlisting over denylisting (describe valid input, not invalid input)

**3. Error handling that doesn't leak information**
Error messages returned to callers should not reveal internal system state:
- Internal: `database error: column 'user_id' doesn't exist in table 'sessions'` (reveals schema)
- External: `Internal server error. Request ID: abc123` (allows correlation without revealing schema)
Log the detailed error internally for debugging; return a safe error externally.

**4. Output encoding**
Encode all output for the context in which it will appear:
- HTML context: HTML entity encoding
- SQL context: Parameterized queries
- Shell context: Shell escaping or subprocess arrays (never `shell=True`)
- URL context: URL encoding

**5. Dependency management**
Every dependency is a potential supply chain attack vector:
- Pin dependency versions (lockfiles)
- Use a private artifact mirror, don't pull from the internet at build time
- Review dependency changes during code review
- Scan for known vulnerabilities in dependencies (Dependabot, Snyk)
- Minimize transitive dependencies

#### Code Review as a Security Control

The book argues that code review is one of the highest-leverage security controls:
- The reviewer has fresh eyes and will catch assumptions the author missed
- Four-eyes principle: reduces insider threat risk for sensitive code paths
- Code review documentation: the rationale for security decisions is recorded

**What to look for in security-sensitive code review:**
- Input validation completeness
- Output encoding correctness
- Error handling that leaks information
- Missing authentication or authorization checks
- Race conditions in security-sensitive code paths
- Crypto misuse (wrong algorithm, wrong key size, ECB mode, hardcoded keys)

---

## Part IV: Maintaining Systems Over Time

---

### Chapter 13: Testing Code

#### Test Types and Security Relevance

| Test Type | Reliability Value | Security Value |
|---|---|---|
| **Unit tests** | Verify individual component logic | Verify individual security checks work |
| **Integration tests** | Verify components interact correctly | Verify security controls compose correctly |
| **End-to-end tests** | Verify user-facing flows work | Verify security controls aren't bypassed in real flows |
| **Fuzz testing** | Verify system handles unexpected input | Find input validation vulnerabilities |
| **Penetration testing** | Not typically applicable | External validation of security posture |
| **Property-based testing** | Verify invariants hold across many inputs | Verify security properties hold across all input classes |

#### Fuzzing

Fuzzing — generating random, malformed, or boundary-case inputs and verifying the system doesn't crash or behave incorrectly — is highlighted as particularly valuable for security:

- A crash is potential for a memory corruption exploit (in unsafe languages)
- An unexpected success response may indicate a bypass
- An unhandled exception may leak information

**Coverage-guided fuzzing** (libFuzzer, AFL++) tracks code coverage to guide input generation toward unexplored code paths. Google uses ClusterFuzz to run fuzz testing at scale across all C/C++ and Go code.

#### Test Environments Must Match Production

A common failure mode: security or reliability properties hold in test but not in production because:
- Test uses in-memory implementations instead of real dependencies
- Test doesn't simulate production load patterns
- Test uses permissive configs for developer convenience
- Test lacks production network topology

**Recommendation**: Use production-equivalent infrastructure for pre-production testing. Shadow traffic testing (replaying production traffic to staging) catches discrepancies that unit tests miss.

---

### Chapter 14: Deploying Code

#### Deployment as a Risk Event

Every deployment is an opportunity to introduce a regression — in functionality, reliability, or security. The book treats deployment design as a risk management problem.

**Deployment risk factors:**
- Size of the change (lines of code changed, number of services affected)
- Frequency of deployment (less frequent = larger batched changes = higher risk)
- Reversibility (can you roll back instantly?)
- Observability (can you detect a regression within minutes?)

#### Progressive Delivery

Minimize deployment blast radius by deploying gradually:

1. **Canary deployment**: 1% of traffic to new version, monitor for errors/latency regressions
2. **Staged rollout**: 1% → 5% → 20% → 50% → 100%, with automatic promotion/rollback based on metrics
3. **Feature flags**: Decouple deployment from release; code is deployed dark, feature is enabled separately
4. **Blue/green deployment**: Maintain two identical environments; switch traffic atomically

**Automatic rollback triggers:**
- Error rate exceeds baseline + N standard deviations
- P99 latency exceeds SLO threshold
- User-defined business metrics drop below threshold

#### Deployment and Security

Security properties of deployments:
- **Signed artifacts**: Build artifacts are signed; the deployment system verifies signatures before deploying
- **Provenance**: The deployment system records what code, what build machine, what configuration was deployed, and by whom
- **Reproducible builds**: Given the same source + inputs, the build produces the same binary (eliminates "works on my machine" security ambiguity)
- **Binary authorization**: Production only runs binaries that were built by the trusted CI system (Google's BeyondBuild model)

---

### Chapter 15: Investigating Systems

#### The Investigation Lifecycle

Whether investigating a reliability incident or a security incident, the process is similar:

1. **Triage**: Is this happening? How severe? Who is affected?
2. **Contain**: Limit ongoing damage (rate limit, block, roll back)
3. **Investigate**: What happened? When? Why?
4. **Remediate**: Fix the underlying cause
5. **Recover**: Restore normal operation
6. **Post-mortem**: Learn and prevent recurrence

**Key difference**: In a security incident, the investigation itself must be careful not to tip off the attacker, destroy evidence, or alert the attacker that they've been discovered before containment is ready.

#### Logging for Investigations

Effective investigation requires logs that were designed for investigation, not just for debugging. The book's logging requirements:

**What to log:**
- Authentication events (success and failure)
- Authorization decisions (especially denials)
- Data access to sensitive objects (reads, writes, deletes)
- Configuration changes
- Privilege escalations
- Network connections to/from sensitive services

**How to log it:**
- Structured JSON (machine-parseable)
- Immutable log storage (write-once, append-only)
- Tamper-evident logs (hash-chained or signed)
- Replicated off-system (attacker shouldn't be able to delete evidence from the compromised host)
- Long retention (some attack techniques have dwell times of months before detection)

#### Forensics Readiness

**Design for forensics**:
- Preserve disk images before wiping compromised hosts
- Capture in-memory state (process list, network connections, open files) before shutdown
- Maintain network flow logs (NetFlow/IPFIX) at the network level — these survive host compromise
- Time-synchronized logs across all systems (NTP is critical for correlation)

---

### Chapter 16: Disaster Planning

#### Disaster Categories

| Category | Example | Recovery Approach |
|---|---|---|
| **Component failure** | Single server, single database | Automatic failover within minutes |
| **Data corruption** | Logical bug corrupts data | Restore from backup at a recovery point |
| **Infrastructure failure** | Datacenter power loss | Failover to another datacenter |
| **Catastrophic failure** | Regional outage, cloud provider incident | Multi-region or multi-cloud failover |
| **Security incident** | Ransomware, mass credential compromise | Incident response + restore from clean backups |

#### The Disaster Recovery Plan (DRP)

A DRP is only as good as its last test. The book emphasizes:
- **Documented recovery procedures**: Step-by-step, not relying on tribal knowledge
- **Regular drills**: At least annually; at Google, surprise drills are run to test real-world readiness
- **Ownership**: Every service has a named owner responsible for its DRP
- **RTO and RPO commitments**: Explicit, signed off by business stakeholders, reflected in the architecture

#### "DiRT" — Disaster Recovery Testing

Google's DiRT (Disaster Recovery Testing) program:
- Deliberately causes failures in production systems on a scheduled basis
- Validates that failover mechanisms actually work
- Discovers gaps in runbooks and automation
- Exercises the human response, not just the automated recovery

**For principal engineers**: Be able to describe your organization's equivalent of DiRT. The absence of disaster recovery testing is a significant risk flag in any architecture review.

---

## Part V: Organization and Culture

---

### Chapter 17: Crisis Management

#### The OODA Loop for Incidents

The book frames incident response using the **OODA loop** (Observe, Orient, Decide, Act):

1. **Observe**: Collect data from monitoring, logs, user reports
2. **Orient**: Build a mental model of what's happening
3. **Decide**: Choose the next action (investigate deeper vs. mitigate now)
4. **Act**: Execute the decision and observe the results

Incident response quality is determined by the speed and accuracy of this loop. Good tooling (dashboards, log search, runbooks) accelerates it; poor tooling slows it.

#### Incident Command Structure

Google's incident command structure (adapted from FEMA Incident Command System):

- **Incident Commander (IC)**: Owns the incident, makes final decisions, communicates externally
- **Operations Lead**: Hands-on investigation and remediation
- **Communications Lead**: User communications, status page, executive updates
- **Planning Lead**: Tracks timeline, coordinates parallel workstreams

**Key principle**: The IC must not be hands-on. An IC who is also debugging is doing two jobs and will fail at one. Separation of concerns applies to incident response too.

#### Security Incident Response Specifics

Security incidents have additional considerations:
- **Evidence preservation**: Don't wipe systems before forensics are complete
- **Attacker awareness**: Assume the attacker can see your actions; don't tip your hand in Slack channels the attacker may have access to
- **Legal and compliance involvement**: Many security incidents have mandatory reporting requirements (GDPR 72-hour notification, PCI DSS breach notification)
- **Communication security**: Use out-of-band communication channels during suspected breaches (phone calls instead of Slack, if Slack may be compromised)

---

### Chapter 18: Recovery and Aftermath

#### Blameless Post-Mortems

The post-mortem is the primary learning mechanism for both reliability and security incidents. The book strongly advocates for blameless post-mortems:

**Blame is counterproductive because:**
- It discourages honest reporting (people hide near-misses)
- It focuses on individuals rather than systems
- It doesn't prevent recurrence (another person will make the same mistake in the same system)

**Effective post-mortems include:**
1. Timeline of events (what happened, when)
2. Root cause analysis (5 Whys, fault tree analysis)
3. Impact quantification (users affected, duration, data lost)
4. Immediate mitigations applied
5. Long-term action items with owners and due dates
6. What went well (don't only analyze failure; reinforce what worked)

#### Action Item Quality

Post-mortem action items are only valuable if they're:
- **Specific**: "Add alerting for X condition" not "improve monitoring"
- **Owned**: A named person is responsible, not a team
- **Dated**: Has a due date, not "sometime"
- **Tracked**: In a bug tracker, reviewed in weekly meetings
- **Completed**: Someone follows up; items don't languish

---

### Chapter 19: Organizational Considerations

#### Security and Reliability Team Models

| Model | Description | Pros | Cons |
|---|---|---|---|
| **Separate teams** | Dedicated SRE team, dedicated Security team | Deep specialization | Silos, slow coordination |
| **Embedded security** | Security engineers embedded in product teams | Fast feedback, context | May lack depth |
| **Shared responsibility** | Every engineer is responsible for security + reliability | Scale, ownership | Requires investment in tooling and training |
| **Google's model** | Shared responsibility + specialist teams for hardest problems | Scales to thousands of engineers | Requires years to build the culture |

**The principal engineer's role in security culture:**
- Set the example: every security issue you catch in code review signals that security matters
- Build shared vocabulary: use precise security terms in design reviews
- Make the right thing the easy thing: create libraries and tools that are secure by default
- Push back on "we'll add security later": this is a myth; the cost of adding security later is 10-100x

#### Hiring for Security and Reliability

The book discusses what to look for in engineers who will own security and reliability:
- **Comfort with ambiguity**: Incidents don't come with full information
- **Systems thinking**: The ability to see how a change in one place affects another
- **Adversarial mindset**: Ask "how would an attacker abuse this?" about everything
- **Learning from failure**: Treat mistakes as data, not as personal failures
- **Communication under pressure**: Incidents require clear, calm communication even when things are bad

---

## Key Frameworks Summary

### The Security-Reliability Design Checklist

For every system you design, ask:

**Confidentiality**
- [ ] What data is sensitive? Is it classified?
- [ ] Who can access it? Is access least-privilege?
- [ ] Is it encrypted at rest and in transit?
- [ ] Is access logged and auditable?

**Integrity**
- [ ] What happens if data is corrupted? How is corruption detected?
- [ ] Are writes idempotent? Is double-write safe?
- [ ] Are there consistency guarantees? What are the failure modes?
- [ ] Is there a way to verify data integrity after restore?

**Availability**
- [ ] What is the RTO? RPO? Is the architecture designed to meet them?
- [ ] What is the failure domain? What fails together?
- [ ] Are there single points of failure?
- [ ] What is the blast radius of a DoS attack on this system?

**Accountability**
- [ ] Is every sensitive action logged with who, what, when, and from where?
- [ ] Are logs immutable and off-system?
- [ ] Can you reconstruct a timeline of events for a security investigation?

**Understandability**
- [ ] Can a new operator understand the system state from the monitoring?
- [ ] Are all access decisions understandable and auditable?
- [ ] Is the permission model simple enough to reason about?

---

## FAANG Interview Applications

### When to Cite This Book

**System Design interviews:**
- Any time you discuss access control: cite least privilege, just-in-time access, break-glass accounts
- Any time you discuss data storage: cite encryption, key management, data classification
- Any time you discuss APIs: cite input validation, rate limiting, audit logging
- Any time you discuss deployment: cite progressive delivery, binary authorization, artifact signing

**Architecture Review questions:**
- "How would you handle a security breach?" → Incident response structure, forensics readiness, out-of-band communication
- "What's your disaster recovery plan?" → RTO/RPO, backup strategy, DiRT-style testing
- "How do you control access to production?" → Safe proxies, break-glass, JIT access

**Leadership/Behavioral questions:**
- "Describe a time you improved security/reliability" → Use SSTAR format, cite organizational scale impact
- "How do you build a culture of reliability?" → Blameless post-mortems, shared responsibility model, making the right thing the easy thing

### Key Numbers to Remember

| Metric | Typical Values |
|---|---|
| **TLS handshake overhead** | ~1ms for resumption, ~10ms for full handshake |
| **AES-256-GCM throughput** | 1-10 GB/s on modern hardware (AES-NI) |
| **mTLS overhead vs. TLS** | ~1-2ms additional per connection (certificate validation) |
| **Canary traffic percentage** | 1% initial, automated promotion after 15-30 minutes |
| **Secret rotation period** | API keys: 90 days; certificates: 1 year; root keys: 3-5 years |
| **Log retention (compliance)** | PCI DSS: 1 year; HIPAA: 6 years; GDPR: data minimization (shorter) |
| **DoS mitigation activation** | CDN scrubbing: seconds; BGP blackhole: minutes |

---

## One-Page Summary

**The core message**: Security and reliability are the same discipline, applied from two different threat models. Design both in from the start. The key principles:

1. **Assume breach** — Design for detection and containment, not just prevention
2. **Least privilege** — Minimum access, minimum duration, everywhere
3. **Defense in depth** — No single control is sufficient; layer independent controls
4. **Blast radius** — Every failure has a radius; design to limit it
5. **Understandability** — You cannot secure or make reliable what you cannot understand
6. **Blameless culture** — Blame prevents learning; systems thinking enables improvement
7. **Test your recovery** — An untested recovery plan is not a recovery plan
8. **Make the right thing easy** — Security controls that are circumvented provide false confidence

> **Interviewer signal**: Candidates who treat security as "someone else's job" don't pass at FAANG principal level. Demonstrating that you think about security and reliability together, from the first API design to the last incident post-mortem, signals principal engineer maturity.
