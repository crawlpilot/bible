# Git Branching Strategies

## Why This Matters at Principal Engineer Level

A branching strategy is an organizational decision, not a developer preference. It determines your release cadence, merge risk, rollback capability, and CI/CD complexity. A principal engineer chooses a strategy that matches the team's deployment frequency and risk tolerance — and can articulate the trade-offs to engineering leadership.

---

## The Four Main Strategies

### 1. Trunk-Based Development (TBD)

**How it works:** All engineers commit directly to `main` (trunk) multiple times per day. Short-lived feature branches (< 1 day) are allowed. Releases cut from trunk.

```
main: ──A──B──C──D──E──F──G──► (deploy continuously)
          └─feat──┘
              (< 1 day)
```

**When to use:**
- High-deployment-frequency teams (10+ deploys/day)
- Strong CI/CD with fast test suites (< 10 min)
- Mature feature flag infrastructure
- Senior, disciplined teams

**Requirements:**
- Feature flags to decouple deploy from release
- Automated rollback (blue-green or canary)
- Comprehensive test coverage (unit + integration)
- PR/code review still happens — just merges fast

**FAANG usage:** Google, Meta, and Netflix all use TBD at scale. Google's mono-repo with 86,000+ engineers commits to a single trunk.

**Risks:**
- A broken commit breaks everyone → need fast CI gating
- "Not yet ready" code must be hidden behind flags, not branches

---

### 2. GitHub Flow

**How it works:** Feature branches off `main`, PR review, merge to `main`, deploy immediately.

```
main: ──A──────────D──────────G──►
          └─feat-1─┘  └─feat-2─┘
```

**Branch naming convention:**
```
feature/JIRA-123-add-payment-retry
fix/JIRA-456-null-pointer-checkout
chore/upgrade-spring-boot-3.2
```

**When to use:**
- Web apps that deploy frequently
- Small-to-medium teams (5–20 engineers)
- No complex release management required

**Risks:**
- `main` can become unstable if CI gates aren't enforced
- No staging environment concept built in

---

### 3. GitFlow

**How it works:** Two permanent branches (`main`, `develop`), plus `feature/*`, `release/*`, `hotfix/*` branches.

```
main:    ──────────────v1.0────────────v1.1──►
                        │               │
develop: ──A──B──C──D───┤──E──F──G──H──┤──►
              └─feat─┘  └─release/1.0─┘
```

**Branch lifecycle:**
| Branch | Branched from | Merges into | Purpose |
|--------|--------------|-------------|---------|
| `feature/*` | `develop` | `develop` | New features |
| `release/*` | `develop` | `main` + `develop` | Release stabilization |
| `hotfix/*` | `main` | `main` + `develop` | Production fixes |
| `develop` | — | `release/*` | Integration branch |
| `main` | — | — | Production-only |

**When to use:**
- Mobile apps / packaged software with versioned releases
- Long QA cycles before release
- Multi-version support required
- Regulatory environments requiring release gates

**Risks:**
- Merge hell — long-lived branches diverge
- Slow feedback loop — features isolated for days/weeks
- Not suited for continuous deployment

---

### 4. Release Branching (GitLab Flow variant)

**How it works:** Feature branches to `main` (like GitHub Flow), but release branches are cut from `main` for stable versions.

```
main:         ──A──B──C──D──E──F──►
                        │
release/1.0:            └──fix──►  (only hotfixes cherry-picked in)
```

**When to use:**
- SaaS products with multiple version tracks
- Enterprise software supporting N-1 releases
- Teams moving from GitFlow toward TBD

---

## Strategy Comparison

| Dimension | Trunk-Based | GitHub Flow | GitFlow | Release Branching |
|-----------|-------------|-------------|---------|-------------------|
| Deploy frequency | Continuous | On merge | On release | On release cut |
| Branch lifetime | < 1 day | Days | Weeks | Months |
| Merge complexity | Low | Low | High | Medium |
| Rollback mechanism | Feature flags | Revert PR | Hotfix branch | Cherry-pick |
| CI/CD complexity | High (gates critical) | Medium | Medium | Medium |
| Best for | High-freq SaaS | Web apps | Mobile/packaged | Enterprise SaaS |
| Risk of merge conflicts | Minimal | Low | High | Medium |

---

## Branch Protection Rules (Principal Engineer Standard)

For any strategy, `main` must be protected:

```yaml
# GitHub branch protection (via Terraform or UI)
branch_protection:
  pattern: main
  enforce_admins: true
  required_status_checks:
    strict: true  # must be up to date with main
    contexts:
      - build
      - unit-tests
      - integration-tests
      - security-scan
  required_pull_request_reviews:
    required_approving_review_count: 2
    dismiss_stale_reviews: true
    require_code_owner_reviews: true
  restrictions:
    push: []  # no direct pushes, ever
```

---

## CODEOWNERS Pattern

CODEOWNERS enforces that the right people review the right code — a principal engineer sets this up org-wide:

```
# .github/CODEOWNERS

# Global fallback — any file not matched below
*                   @team/platform-eng

# Service owners
/payments/          @team/payments-eng
/auth/              @security-lead @team/auth
/infra/             @team/sre

# Architecture decisions require principal review
/architecture/      @principal-eng-group
/ADRs/              @principal-eng-group

# CI/CD changes require SRE sign-off
/.github/           @team/sre
/Dockerfile*        @team/sre
```

---

## Commit Message Standards

**Conventional Commits** (enforce via git hooks or CI):

```
<type>(<scope>): <subject>

<body>

<footer>
```

Types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`, `ci`

```bash
feat(payments): add idempotency key support for charge API

Prevents duplicate charges on network retry. Key is generated
client-side and stored in Redis with 24h TTL.

Closes JIRA-1234
Breaking-change: no
```

Enforce with `commitlint`:
```bash
# package.json
{
  "commitlint": {
    "extends": ["@commitlint/config-conventional"]
  }
}
```

---

## Interview Framing

**Q: Which branching strategy would you use for a 50-team org?**

> I'd standardize on Trunk-Based Development with feature flags. At that scale, long-lived branches become coordination overhead — merge conflicts slow teams down and cause integration surprises. TBD forces teams to integrate continuously, keeps main always deployable, and shifts release control to flags rather than branches. The investment is in CI speed (sub-10-minute pipelines) and a mature flag service — that's table stakes at 50 teams anyway. I'd allow short-lived branches (< 1 day) to preserve code review workflows.

**Q: How do you handle a hotfix in trunk-based development?**

> If the bug is behind a flag, disable the flag — no code change needed. If not, the fix goes through the normal PR process directly to main and gets deployed within the hour via continuous deployment. The advantage over GitFlow hotfix branches is speed: no cherry-picks, no branch sync, no release manager coordination.
