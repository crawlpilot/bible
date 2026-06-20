# Code Ownership

## Why This Matters at Principal Engineer Level

Code ownership is the connective tissue between organizational structure and codebase health. Without it, PRs get merged without the right review, critical systems have no clear steward, and incidents have no obvious DRI (Directly Responsible Individual). A principal engineer designs the ownership model and ensures it evolves as the org changes. Conway's Law is real: your codebase structure will mirror your team structure — own that intentionally.

---

## Ownership Models

### 1. Strong Ownership (Collective Team)
A team owns a service end-to-end: on-call, roadmap, review, and incident response.

- **Best for:** Microservices architecture, clear service boundaries
- **Risk:** Knowledge silos — only one team can touch the service
- **FAANG usage:** Amazon's "you build it, you run it" model

### 2. Weak Ownership (Community of Practice)
Any team can contribute to any service; code area owners review but don't block.

- **Best for:** Shared libraries, platform tooling, cross-cutting concerns
- **Risk:** No one feels accountable for quality or incidents
- **FAANG usage:** Google's mono-repo approach — owners review but contributions are open

### 3. Stewardship Model (Hybrid)
A designated steward owns quality and review standards, but doesn't own feature delivery.

- **Best for:** Infrastructure, databases, security-critical paths
- **Risk:** Bottleneck if steward team is understaffed
- **FAANG usage:** Meta's platform teams for React Native, internal infra

---

## CODEOWNERS Implementation

CODEOWNERS is the enforcement layer. It lives in `.github/CODEOWNERS` (GitHub) or equivalent.

### Structure

```
# .github/CODEOWNERS
# Format: <pattern> <owner1> <owner2>

# === Global fallback ===
# If no rule matches, platform-eng reviews
*                               @org/platform-eng

# === Service ownership ===
/services/payments/             @org/payments-team
/services/auth/                 @org/auth-team @security-lead
/services/notifications/        @org/notifications-team

# === Shared libraries ===
/libs/common/                   @org/platform-eng
/libs/observability/            @org/sre-team

# === Infrastructure ===
/infra/                         @org/sre-team
/infra/terraform/               @org/sre-team @org/cloud-team
Dockerfile*                     @org/sre-team

# === CI/CD ===
/.github/workflows/             @org/sre-team
/.github/CODEOWNERS             @principal-eng @org/eng-leads

# === Architecture — principal sign-off ===
/ADRs/                          @principal-eng
/architecture/                  @principal-eng
/RFCs/                          @principal-eng @org/eng-leads

# === Security-sensitive paths ===
/services/auth/crypto/          @security-team @org/auth-team
**/migration/                   @dba-team @org/platform-eng
```

### Rules for writing CODEOWNERS
- More specific patterns override less specific ones (bottom rules win in GitHub)
- Keep team aliases up to date — stale CODEOWNERS is worse than none
- Never assign a single individual — always a team alias (handles vacations, departures)
- Review CODEOWNERS quarterly as org structure changes

---

## Ownership Registry (Beyond CODEOWNERS)

CODEOWNERS handles review routing. A separate ownership registry handles ops and incident routing.

```yaml
# service-catalog.yaml (input to internal developer portal)
services:
  - id: payment-service
    name: Payment Service
    team: payments-eng
    tier: P0          # production impact tier
    oncall: payments-oncall-rotation
    slack: "#payments-eng"
    runbook: https://wiki.internal/runbooks/payment-service
    slo:
      availability: 99.99%
      latency_p99: 200ms
    dependencies:
      - fraud-service
      - ledger-service
      - stripe-gateway
    repos:
      - org/payment-service
    owners:
      primary: alice@company.com
      secondary: bob@company.com
```

This feeds:
- **PagerDuty** — who gets paged for this service
- **Backstage / internal portal** — service discovery
- **Post-mortem tooling** — who is the DRI for an incident

---

## Ownership Transitions

When a team is disbanded, reorganized, or ownership needs to shift:

### Transfer Checklist
```
□ New team reads existing runbooks and architecture docs
□ 2-week shadow on-call period (new team observes)
□ 2-week reverse-shadow (new team leads, old team observes)
□ CODEOWNERS updated and reviewed by principal
□ service-catalog.yaml updated
□ PagerDuty rotation transferred
□ Slack channel ownership transferred
□ Runbook ownership transferred
□ Knowledge transfer sessions recorded (Loom/Confluence)
□ Old team available for 30 days as escalation path
```

**Principal engineer role:** Sponsor the transfer. No transfer is complete until new owners have been on-call through at least one incident independently.

---

## Preventing Ownership Rot

**Ownership rot** happens when CODEOWNERS is stale, service-catalog is out of date, and no one knows who to page.

Detection signals:
- PR review requested from a departed employee
- PagerDuty pages a team that doesn't own the service anymore
- Incident postmortem: "we didn't know who to contact"
- Code changes go unreviewed because no CODEOWNERS match

**Prevention mechanisms:**

1. **Quarterly ownership audit** — script that checks CODEOWNERS references against active GitHub teams
   ```bash
   # Check for teams in CODEOWNERS that don't exist in GitHub
   gh api /orgs/{org}/teams --paginate | jq '.[].slug' > active_teams.txt
   grep -oP '@\S+' .github/CODEOWNERS | sort -u > codeowners_teams.txt
   diff active_teams.txt codeowners_teams.txt
   ```

2. **Bot alerts on unreviewed PRs** — if a PR is open > 24h with no reviewer, ping the fallback owner

3. **Ownership page in engineering portal** — every service must have a team, a Slack channel, and a runbook URL. Missing = P1 task.

---

## Shared Code Ownership Patterns

### Platform Libraries (owned by platform team)
- Strict API stability — semver enforced
- Breaking changes require 6-week deprecation notice
- External contributions allowed via PR; platform team reviews

### Cross-cutting infrastructure code (SRE owns)
- `Dockerfile*`, CI pipeline definitions, Terraform modules
- No self-service changes — raise a ticket or pair with SRE
- Rationale: infrastructure changes have blast radius across all services

### Database schema (DBA + service team co-own)
- All migration PRs require DBA review
- Service team owns the migration file; DBA approves the change
- Rationale: a bad migration on a 500M-row table is irreversible in < 10 min

---

## Interview Framing

**Q: How do you design a code ownership model for a 200-engineer org?**

> I'd use a hybrid model: strong ownership at the service level, with stewardship for shared infrastructure. Each service has exactly one owning team — they're on-call, they review PRs, they own the roadmap. For cross-cutting code (CI/CD, Terraform, shared libraries), I'd designate steward teams (SRE for infra, platform for libraries) who set standards and review contributions from anyone. I'd enforce this via CODEOWNERS at the code level and a service catalog at the ops level — so both PR review routing and incident paging use the same source of truth. I'd run a quarterly audit to catch rot and make ownership status a health metric visible to EMs.

**Q: A critical service has no clear owner — no team claims it. What do you do?**

> This is a real scenario — "orphan services" happen after reorgs. First I establish a temporary DRI from the team closest to the service (based on git blame and incident history). Then I run a 2-week knowledge-transfer sprint: gather existing documentation, interview anyone who's touched it, write a runbook. After that, I formally assign ownership to a team with clear expectation-setting — this is an explicit ask from leadership, not a volunteer situation. Long-term, I'd use the incident to push for a mandatory service catalog where every service must have a named owner — no owner means it doesn't get deployed.
