# Penetration Testing: Process, Methodologies & Best Practices

> Principal engineer reference for security architecture, threat modeling, and leading pentest engagements. Covers the full lifecycle from scoping through reporting, across all major methodologies.

---

## Table of Contents

1. [What Is Penetration Testing](#1-what-is-penetration-testing)
2. [Engagement Types](#2-engagement-types)
3. [Methodologies](#3-methodologies)
4. [The 7-Phase Pentest Process](#4-the-7-phase-pentest-process)
5. [Testing Domains](#5-testing-domains)
6. [Tools by Phase and Domain](#6-tools-by-phase-and-domain)
7. [Vulnerability Scoring: CVSS](#7-vulnerability-scoring-cvss)
8. [Rules of Engagement](#8-rules-of-engagement)
9. [Reporting Standards](#9-reporting-standards)
10. [Legal and Compliance Considerations](#10-legal-and-compliance-considerations)
11. [Best Practices for Engineering Teams](#11-best-practices-for-engineering-teams)

---

## 1. What Is Penetration Testing

A **penetration test** is an authorized, simulated cyberattack against a system to identify vulnerabilities before malicious actors do. It differs from a vulnerability scan:

| Dimension | Vulnerability Scan | Penetration Test |
|-----------|-------------------|-----------------|
| Automation | Fully automated | Manual + automated |
| Exploitation | Identifies, does not exploit | Actively exploits to demonstrate impact |
| False positive rate | High | Low (exploits confirm findings) |
| Depth | Breadth over depth | Deep on specific attack chains |
| Output | List of CVEs and misconfigurations | Narrative: attack path, business impact, remediation |
| Frequency | Weekly/monthly | Annually or post-major change |

**Principal engineer relevance**: you will be asked to scope, review, and act on pentest findings. You need to understand the methodology to interpret severity correctly, prioritize remediations, and design systems that minimize attack surface.

---

## 2. Engagement Types

### By Knowledge Level

| Type | Tester's Prior Knowledge | Simulates |
|------|------------------------|-----------|
| **Black Box** | None — only public information | External attacker with no insider access |
| **White Box** | Full: source code, architecture diagrams, credentials | Comprehensive audit; maximum coverage |
| **Gray Box** | Partial: credentials, API docs, network diagrams | Insider threat; breached third-party; compromised credential scenario |

**When to use which**:
- Black box: compliance check, simulating external adversary, validating perimeter defenses
- White box: pre-launch security audit, code-level review, finding logic flaws in complex workflows
- Gray box: most realistic for post-breach "assume compromise" modeling; covers both external and insider threat

### By Scope

| Scope | What Is Tested |
|-------|---------------|
| **Network Pentest** | External perimeter, internal network, segmentation |
| **Web Application Pentest** | OWASP Top 10, authentication, business logic |
| **API Pentest** | REST/GraphQL/gRPC endpoints, authorization, injection |
| **Mobile Application Pentest** | iOS/Android binary, data storage, network traffic |
| **Cloud Pentest** | AWS/GCP/Azure misconfigurations, IAM, data exposure |
| **Social Engineering** | Phishing, vishing, physical access |
| **Red Team** | Full adversary simulation: all vectors, persistence, lateral movement, data exfiltration |

---

## 3. Methodologies

### PTES — Penetration Testing Execution Standard

The de facto standard for how a pentest engagement is structured. Seven phases (see Section 4). Covers intelligence gathering, threat modeling, exploitation, and reporting.  
[ptes.org](http://www.pentest-standard.org/)

### OWASP Testing Guide (OTG)

Purpose-built for web application and API testing. OTG v4.2 covers 91 test cases across 11 categories:
- OTG-INFO: Information gathering
- OTG-CONF: Configuration and deployment management
- OTG-IDENT: Identity management
- OTG-AUTHN: Authentication
- OTG-AUTHZ: Authorization
- OTG-SESS: Session management
- OTG-INPVAL: Input validation (injections, XSS, XXE)
- OTG-ERR: Error handling
- OTG-CRYPST: Cryptography
- OTG-BUSLOGIC: Business logic
- OTG-CLIENT: Client-side (DOM XSS, clickjacking, CORS)

### OSSTMM — Open Source Security Testing Methodology Manual

Focuses on operational security: tests are measured and scored. Produces a **RAV (Risk Assessment Value)** — a quantified security posture score. More rigorous for compliance-heavy environments (finance, healthcare).

### NIST SP 800-115 — Technical Guide to Information Security Testing

US government standard. Four phases: Planning → Discovery → Attack → Reporting. Preferred for federal systems and contractors. Maps directly to FISMA and FedRAMP requirements.

### MITRE ATT&CK Framework

Not a testing methodology but a **threat actor behavior catalog**. 14 tactics (Reconnaissance, Initial Access, Execution, Persistence, Privilege Escalation, Defense Evasion, Credential Access, Discovery, Lateral Movement, Collection, Command & Control, Exfiltration, Impact). Red teams map their activities to ATT&CK techniques — "we simulated T1078 (Valid Accounts) via T1110.003 (Password Spraying)."

Use ATT&CK to:
- Scope red team exercises to specific threat actor TTPs
- Map pentest findings to a common taxonomy
- Measure detection coverage: which ATT&CK techniques does your SIEM detect?

---

## 4. The 7-Phase Pentest Process

### Phase 1: Pre-Engagement (Scoping)

**Goal**: Define what will be tested, how, and within what constraints.

**Deliverables**:
- **Statement of Work (SOW)**: scope, exclusions, timeline, cost
- **Rules of Engagement (RoE)**: start/stop criteria, escalation contacts, prohibited actions
- **Authorization letter**: signed document permitting testing (critical for legal protection)

**Scoping decisions**:
```
In-scope:
  - IP ranges: 10.0.0.0/16, 203.0.113.0/24
  - Domains: *.example.com (excluding partner-owned subdomains)
  - Applications: /api/v2/*, /admin/* (excluding /billing)
  - Test accounts: pentest@example.com (not production user data)

Out-of-scope:
  - Third-party SaaS integrations (Salesforce, Stripe)
  - DoS/DDoS testing
  - Social engineering of employees (separate engagement)
  - Production database writes
```

**Key questions to answer in scoping**:
- Can testers write/delete data or only read?
- Are DoS attacks permitted? Against which endpoints?
- What happens if testers discover a critical vuln? Immediate escalation or include in final report?
- Is production in scope or only staging?
- What is the notification process if testing causes an outage?

---

### Phase 2: Intelligence Gathering (Reconnaissance)

**Goal**: Build a map of the target's attack surface without touching in-scope systems.

#### Passive Reconnaissance (OSINT — no direct contact)

| Source | What It Reveals | Tools |
|--------|----------------|-------|
| DNS records | Subdomains, mail servers, IP ranges | `dig`, `dnsrecon`, `amass`, `subfinder` |
| WHOIS | Registrant contact, registration dates | `whois`, `domaintools` |
| Certificate Transparency logs | All TLS certs ever issued for domain (reveals subdomains) | `crt.sh`, `certspotter` |
| Shodan / Censys | Open ports, banners, services exposed to the internet | `shodan.io`, `censys.io` |
| Google dorks | Exposed files, admin panels, error pages indexed by Google | `site:`, `inurl:`, `filetype:` operators |
| GitHub / GitLab | Leaked credentials, API keys, internal tooling, architecture docs | `truffleHog`, `gitleaks`, `git-secrets` |
| LinkedIn / Job postings | Technology stack, team structure, vendor relationships | Manual |
| Wayback Machine | Old pages, removed endpoints, legacy APIs | `waybackurls` |
| Cloud metadata | Public S3 buckets, Azure blobs, GCP storage | `S3Scanner`, `GrayhatWarfare` |

#### Active Reconnaissance (direct contact, limited interaction)

- **DNS brute-force**: enumerate subdomains beyond what OSINT reveals — `gobuster dns`, `ffuf`
- **Port scanning**: identify open ports across IP ranges — `nmap -sS -T4 -p-`
- **Service fingerprinting**: identify software and versions from banners — `nmap -sV`
- **Web crawling**: discover pages, forms, API endpoints — `gospider`, `katana`

---

### Phase 3: Threat Modeling

**Goal**: Given what you know about the target, determine the most likely and most impactful attack paths. Prioritizes Phase 4 exploitation planning.

**Frameworks**:
- **STRIDE**: Spoofing, Tampering, Repudiation, Information Disclosure, Denial of Service, Elevation of Privilege — per-component threat enumeration
- **PASTA**: Process for Attack Simulation and Threat Analysis — risk-centric, aligns threats to business impact
- **LINDDUN**: Privacy-focused threat model (Linkability, Identifiability, Non-repudiation, Detectability, Disclosure of information, Unawareness, Non-compliance)

**Threat modeling output**:
```
Asset: Customer payment data in PostgreSQL
Threat: SQL injection via /api/v2/search?q= → unauthorized data access
Likelihood: Medium (input sanitized in middleware but raw query used in one endpoint)
Impact: Critical (PCI DSS violation, financial and reputational)
Priority: P0 — test this first
```

---

### Phase 4: Vulnerability Analysis

**Goal**: Systematically identify security weaknesses using automated scanners + manual inspection.

#### Automated Scanning

| Category | Tool | What It Finds |
|----------|------|--------------|
| Web app | `Burp Suite Pro`, `OWASP ZAP` | OWASP Top 10, injection, broken auth |
| Network | `Nessus`, `OpenVAS`, `Qualys` | CVEs, misconfigurations, outdated software |
| API | `Burp Suite`, `Postman + OWASP checks` | OWASP API Top 10, broken object-level auth |
| Infrastructure | `Lynis`, `OpenSCAP` | OS hardening gaps |
| Container | `Trivy`, `Clair`, `Anchore` | CVEs in base images, secret leaks |
| IaC | `Checkov`, `tfsec`, `Terrascan` | Terraform/CloudFormation misconfigurations |
| Cloud | `Scout Suite`, `Prowler`, `Pacu` | AWS/GCP/Azure misconfigs, IAM issues |

#### Manual Testing

Automated scanners miss:
- **Business logic flaws** (e.g., changing `price=10` to `price=-1` in a checkout API)
- **Authorization bypasses** that require understanding the application's access model
- **Second-order SQL injection** (stored payloads that execute later)
- **Race conditions** (concurrent requests that bypass stock checks or account limits)
- **Insecure direct object references** (IDOR) where IDs are predictable or poorly validated

---

### Phase 5: Exploitation

**Goal**: Confirm vulnerabilities by exploiting them to demonstrate real-world impact. This is the phase that distinguishes a pentest from a scan.

**Principles**:
1. **Minimum footprint**: gain only the access needed to demonstrate the finding. Don't pivot further than necessary to prove the point.
2. **No destructive actions** unless explicitly scoped: no deleting data, no modifying production records, no crashing services.
3. **Document everything**: screenshot the exploit, record the exact request/response, note timestamps.
4. **Pause and escalate** if you discover a critical finding that the client would want to know immediately (active breach, critical data exposure).

**Common exploit categories**:

| Vulnerability | Exploit Technique | Typical Impact |
|---------------|------------------|---------------|
| SQL Injection | `sqlmap`, manual UNION/blind injection | DB dump, auth bypass |
| XSS (stored) | Steal session cookies, redirect to phishing | Account takeover |
| XXE | SSRF via XML entity → internal service access | Internal network exposure |
| SSRF | HTTP to internal metadata endpoint (AWS IMDS) | Cloud credential theft |
| Broken Auth | JWT none algorithm, weak secret brute-force | Account takeover |
| IDOR | Enumerate user IDs, access other users' data | Data breach |
| Command Injection | `; id`, `` `whoami` ``, `| cat /etc/passwd` | Remote code execution |
| Deserialization | Java gadget chains, Pickle in Python | RCE |
| Path Traversal | `../../etc/passwd` in file uploads/includes | File read/LFI → RCE |
| Open Redirect | `?redirect=https://evil.com` | Phishing, credential harvesting |

---

### Phase 6: Post-Exploitation

**Goal**: Simulate what a real attacker would do after initial compromise. Demonstrates the true blast radius.

**Activities** (within scoped permissions):
- **Privilege escalation**: from low-privileged user → root/admin. Linux: SUID binaries, sudo misconfigs, kernel exploits. Windows: token impersonation, unquoted service paths, DLL injection.
- **Lateral movement**: from the compromised host, reach other systems on the same network segment. Pass-the-hash, Kerberoasting, SSH key reuse.
- **Credential dumping**: extract passwords/hashes from memory (Mimikatz), config files, environment variables.
- **Persistence**: demonstrate how an attacker would maintain access: cron jobs, backdoored services, SSH authorized keys, scheduled tasks.
- **Data exfiltration**: demonstrate that target data (PII, credentials, IP) can leave the environment. DNS exfiltration, HTTPS to attacker-controlled server.
- **Covering tracks**: demonstrate whether the attack is detectable by reviewing logs, clearing audit trails (within scope).

**C2 frameworks used by red teams**:
- **Cobalt Strike**: industry standard for red team C2; stages, beacons, malleable profiles for traffic shaping
- **Metasploit Framework**: open-source exploit framework; `msfconsole`, Meterpreter shells
- **Sliver**: open-source C2 by BishopFox; gRPC-based; increasingly common alternative to Cobalt Strike
- **Brute Ratel C4**: modern C2; designed to evade EDR tools

---

### Phase 7: Reporting

**Goal**: Communicate findings in a way that drives action from both technical teams and executive stakeholders.

**Report structure**:

```
1. Executive Summary (1-2 pages)
   - Engagement scope and timeline
   - Risk posture: overall rating (Critical/High/Medium/Low)
   - Top 3 findings in plain language
   - Business impact summary
   - Recommended immediate actions

2. Technical Summary
   - Methodology used
   - Tools and techniques
   - Attack narrative: how the tester moved through the environment

3. Findings (one section per finding)
   - Title
   - Severity: CVSS score + qualitative
   - Affected systems/components
   - Description: what the vulnerability is
   - Evidence: screenshots, request/response, proof-of-concept
   - Risk: what an attacker could do with this
   - Remediation: specific steps to fix, not just "patch the system"
   - References: CVE, CWE, OWASP link

4. Appendix
   - Full list of in-scope/out-of-scope assets
   - All raw scanner output
   - Tools and versions used
   - Testing timeline log
```

---

## 5. Testing Domains

### Web Application — OWASP Top 10 (2021)

| Rank | Category | Key Tests |
|------|---------|-----------|
| A01 | Broken Access Control | IDOR, forced browsing, CORS misconfiguration |
| A02 | Cryptographic Failures | Cleartext credentials, weak ciphers, hardcoded keys |
| A03 | Injection (SQL, NoSQL, LDAP, OS) | Input fields, headers, JSON bodies, GraphQL |
| A04 | Insecure Design | Business logic flaws, missing rate limits on auth |
| A05 | Security Misconfiguration | Default creds, verbose errors, debug mode in prod |
| A06 | Vulnerable & Outdated Components | CVE scan on npm/pip/maven deps |
| A07 | Identification & Authentication Failures | Weak passwords, no MFA, session fixation |
| A08 | Software & Data Integrity Failures | Insecure deserialization, unsigned updates |
| A09 | Security Logging & Monitoring Failures | No audit log, logs deletable by app user |
| A10 | Server-Side Request Forgery (SSRF) | URL parameters, webhook URLs, PDF generators |

### API Security — OWASP API Top 10 (2023)

| # | Category | Example |
|---|---------|---------|
| API1 | Broken Object Level Authorization | GET /api/invoices/12345 without owning invoice 12345 |
| API2 | Broken Authentication | No rate limit on POST /login; JWT none algorithm |
| API3 | Broken Object Property Level Authorization | User can see `admin: true` field in their own profile response |
| API4 | Unrestricted Resource Consumption | Upload 10GB file; no request size limit; no rate limiting |
| API5 | Broken Function Level Authorization | Regular user calls DELETE /admin/users/1 |
| API6 | Unrestricted Access to Sensitive Business Flows | Unlimited discount code redemptions |
| API7 | Server Side Request Forgery | POST /fetch-url with url=http://169.254.169.254/latest/meta-data/ |
| API8 | Security Misconfiguration | CORS: Access-Control-Allow-Origin: * with credentials |
| API9 | Improper Inventory Management | Undocumented v1 API still accessible and unpatched |
| API10 | Unsafe Consumption of APIs | Trusting third-party API responses without sanitization |

### Network Penetration Testing

**External perimeter**:
- Port scanning: `nmap -sS -sV -sC --open -p- <target>`
- Service exploitation: outdated OpenSSH, exposed RDP, unpatched VPN appliances
- SSL/TLS: weak ciphers (RC4, 3DES), expired certs, POODLE/BEAST/BEAST — `testssl.sh`
- Email: SPF/DKIM/DMARC misconfiguration enabling spoofing

**Internal network** (post-initial compromise):
- Network segmentation validation: can you reach DB servers from DMZ?
- Lateral movement: SMB relay (Responder + ntlmrelayx), ARP spoofing
- AD attacks: Kerberoasting, AS-REP roasting, DCSync, BloodHound path analysis
- Credential reuse: HashiCat, Hydra against internal services

---

## 6. Tools by Phase and Domain

### Reconnaissance
```
amass         - comprehensive subdomain enumeration (active + passive)
subfinder     - fast passive subdomain discovery
httpx         - probe discovered hosts for HTTP/S services
shodan CLI    - query Shodan for exposed services
truffleHog    - scan git history for secrets
gau           - get all URLs from Wayback, CommonCrawl, OTX
```

### Scanning & Enumeration
```
nmap          - port scanning, service fingerprinting, NSE scripts
masscan       - fast port scanning (millions of IPs/second)
nikto         - web server scanner (outdated software, dangerous headers)
gobuster      - directory/file brute force, DNS brute force
feroxbuster   - recursive content discovery
wfuzz         - web fuzzer for parameters, headers
```

### Web Application Testing
```
Burp Suite Pro   - intercepting proxy, scanner, intruder, repeater
OWASP ZAP        - open-source alternative to Burp
sqlmap           - automated SQL injection detection and exploitation
XSStrike         - XSS detection and exploitation
dalfox           - fast XSS scanner
jwt_tool         - JWT analysis, alg:none, key confusion attacks
```

### Exploitation
```
Metasploit       - exploit framework, payloads, post-exploitation
searchsploit     - offline ExploitDB search
pwncat           - advanced reverse/bind shell handler
impacket         - Python library for Windows protocols (SMB, Kerberos, LDAP)
CrackMapExec     - Swiss army knife for Windows/AD post-exploitation
BloodHound       - AD attack path visualization
```

### Cloud-Specific
```
Pacu             - AWS exploitation framework (IAM, EC2, S3, Lambda)
Scout Suite      - multi-cloud security auditing tool
Prowler          - AWS/GCP/Azure security best practice checks (CIS)
CloudMapper      - AWS environment visualization
aws_consoler     - convert AWS credentials to console session
enumerate-iam    - brute-force IAM permissions
```

### Password Attacks
```
Hashcat          - GPU-accelerated hash cracking
John the Ripper  - CPU-based password cracker
Hydra            - online brute-force (SSH, FTP, HTTP, RDP)
CrackMapExec     - spray credentials across AD environments
Kerbrute         - Kerberos user enumeration and password spraying
```

---

## 7. Vulnerability Scoring: CVSS

**CVSS v3.1** (Common Vulnerability Scoring System) — the industry standard for severity scoring.

### Base Score Components

| Metric | Options |
|--------|---------|
| **Attack Vector** | Network (N) / Adjacent (A) / Local (L) / Physical (P) |
| **Attack Complexity** | Low (L) / High (H) |
| **Privileges Required** | None (N) / Low (L) / High (H) |
| **User Interaction** | None (N) / Required (R) |
| **Scope** | Unchanged (U) / Changed (C) |
| **Confidentiality Impact** | None (N) / Low (L) / High (H) |
| **Integrity Impact** | None (N) / Low (L) / High (H) |
| **Availability Impact** | None (N) / Low (L) / High (H) |

### Score Ranges

| CVSS Score | Severity | Example |
|------------|---------|---------|
| 9.0 – 10.0 | **Critical** | Unauthenticated RCE via network (Log4Shell: 10.0) |
| 7.0 – 8.9 | **High** | Auth bypass leading to admin access |
| 4.0 – 6.9 | **Medium** | Stored XSS requiring user interaction |
| 0.1 – 3.9 | **Low** | Information disclosure (version banner) |
| 0.0 | **None** | Informational / best practice gap |

**CVSS is necessary but not sufficient**: a CVSS 9.8 RCE on an internal development server with no external access may be lower business priority than a CVSS 5.3 IDOR that exposes customer PII. Always contextualize with **environmental score** (compensating controls) and **business impact**.

---

## 8. Rules of Engagement

The RoE document is the legal and operational contract for the engagement. Must be signed before any testing begins.

**Essential clauses**:

```
1. Testing window: Mon–Fri 09:00–17:00 PST (no weekends, no US holidays)
   Exception: for DoS testing only if explicitly approved — separate window

2. Authorized IP ranges for testers:
   203.0.113.10/32 (pentest firm egress IP)
   
3. Escalation contacts:
   Primary: Jane Smith (CISO) — jane@company.com — +1-555-0100
   Secondary: Bob Lee (Security Eng Lead) — bob@company.com
   Emergency (critical finding): 24/7 security@company.com
   
4. Prohibited actions:
   - No physical access testing
   - No social engineering of employees  
   - No modification or deletion of production data
   - No DoS against production endpoints (/api/checkout)
   - No testing of third-party systems (Stripe, Salesforce, AWS infrastructure)
   
5. Stop criteria:
   - Immediately stop and call primary contact if:
     a. Evidence of prior/active compromise is found
     b. Any production system becomes unavailable due to testing
     c. PII or financial data is accessed beyond what is needed to prove the finding
     
6. Data handling:
   - All finding evidence encrypted at rest (AES-256)
   - No evidence stored in cloud storage
   - All materials destroyed 30 days after final report delivery
```

---

## 9. Reporting Standards

### Finding Severity: Beyond CVSS

Report each finding with:

```markdown
## Finding: Unauthenticated SQL Injection in /api/v2/products

**Severity**: Critical (CVSS 9.8 — AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H)
**Affected Component**: GET /api/v2/products?category={INJECTION}
**CWE**: CWE-89 (SQL Injection)

### Description
The `category` parameter in the product search API is passed directly 
to a SQL query without parameterization...

### Evidence
Request:
  GET /api/v2/products?category=electronics' OR 1=1--
Response:
  [all products from all categories returned]

Proof-of-concept (database version extraction):
  category=electronics' UNION SELECT version(),null,null--
  PostgreSQL 14.2 on x86_64-pc-linux-gnu

### Business Impact
An unauthenticated attacker can dump the entire products table, 
extract user credentials, or modify product prices.

### Remediation
1. Use parameterized queries (prepared statements) for all database interactions
2. Apply principle of least privilege: the products API user should 
   only have SELECT on the products table, not on users or orders
3. Implement WAF rule to block SQL metacharacters in query parameters

### References
- OWASP SQL Injection: https://owasp.org/www-community/attacks/SQL_Injection
- CWE-89: https://cwe.mitre.org/data/definitions/89.html
```

### Remediation SLA Guidance

Provide clients with a suggested timeline tied to severity:

| Severity | Recommended Remediation Window |
|----------|-------------------------------|
| Critical | 24–48 hours (patch or mitigate immediately) |
| High | 7–14 days |
| Medium | 30 days |
| Low | 90 days or next sprint |
| Informational | Best effort |

---

## 10. Legal and Compliance Considerations

### Authorization is Everything

**Without written authorization, penetration testing is illegal** under:
- US: Computer Fraud and Abuse Act (CFAA) — unauthorized access, even to find vulns, is a federal crime
- EU: Computer Misuse Act equivalents in each member state
- UK: Computer Misuse Act 1990

Required documentation:
1. **Authorization letter** signed by system owner (not just IT)
2. **Scope agreement** with IP ranges, systems, and test types
3. **Third-party notifications**: if the target uses AWS, Azure, or GCP, check the cloud provider's penetration testing policy

### Cloud Provider Policies

| Cloud | Policy |
|-------|--------|
| AWS | No prior approval needed for most testing against your own resources. [Prohibited: DNS zone walking, DoS, port/protocol/request flooding of AWS infrastructure itself](https://aws.amazon.com/security/penetration-testing/) |
| GCP | Submit [Cloud Vulnerability Disclosure form](https://cloud.google.com/support/docs/security-disclosure) before testing. No approval needed for your GCP resources. |
| Azure | No prior approval needed for your Azure resources. Must follow [Microsoft Cloud Penetration Testing Rules of Engagement](https://www.microsoft.com/en-us/msrc/pentest-rules-of-engagement) |

### Bug Bounty vs. Pentest

| Dimension | Bug Bounty | Penetration Test |
|-----------|-----------|-----------------|
| Who | Public researchers (crowd) | Contracted firm |
| Scope | Defined by program | Defined by SOW |
| Timeline | Ongoing | Time-boxed (2–4 weeks) |
| Output | Individual findings | Comprehensive report |
| Coverage | Breadth (many eyes) | Depth (systematic) |
| Cost | Per valid finding | Fixed or T&M |

**Best practice**: run both. Bug bounty for continuous coverage; structured pentest annually and after major releases.

---

## 11. Best Practices for Engineering Teams

### Shift-Left Security

Don't wait for the annual pentest. Embed security earlier:

| Practice | Tool | When |
|---------|------|------|
| **SAST** (static analysis) | Semgrep, SonarQube, CodeQL | Every PR |
| **SCA** (dependency scan) | Snyk, Dependabot, OWASP Dependency-Check | Every build |
| **Secret scanning** | GitGuardian, truffleHog, gitleaks | Every commit |
| **IaC scanning** | Checkov, tfsec, Terrascan | Every Terraform PR |
| **DAST** (dynamic analysis) | OWASP ZAP, Burp Suite automation | Pre-deploy |
| **Container scanning** | Trivy, Snyk Container | Every image build |

### Threat Modeling as a Design Activity

Before writing code for a new feature:
1. Draw the data flow diagram
2. For each component and data flow: apply STRIDE
3. Identify trust boundaries (where does unauthenticated data enter?)
4. Document threat → control mapping
5. Include in design doc / RFC

### Security Champions Model

Embed a **security champion** in each engineering team:
- 10–20% of time dedicated to security work
- Attends AppSec office hours with security team
- Reviews PRs for security anti-patterns
- Communicates security requirements back to their team

This scales security expertise without requiring every team to have a dedicated AppSec engineer.

### Penetration Test Lifecycle Integration

```
Quarter 1: Scope and authorize pentest with external firm
Week 1–2:  Reconnaissance and scanning
Week 3–4:  Exploitation and post-exploitation
Week 5:    Report delivered
Week 6–8:  Remediation sprint (P0/P1 findings)
Week 9:    Retest: confirm critical/high findings are fixed
Week 10:   Final report with remediation evidence
Quarter 4: Begin scoping next year's engagement
```

**Retest is not optional**: a finding that is "fixed" without a retest has a non-trivial chance of being incompletely remediated. Budget retest time explicitly.
