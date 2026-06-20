# Branching Strategies — Principal Engineer Depth

> The right branching strategy depends on team size, release cadence, and deployment model. There is no universal answer — but there are clear failure modes for each choice.

---

## 1. The Four Strategies

### 1.1 Trunk-Based Development (TBD)

**Core idea:** Everyone commits to `main` (the trunk) directly, or via very short-lived branches (< 2 days). No long-lived feature branches.

```
main:  A--B--C--D--E--F--G  (always deployable)
            |         |
            branch    branch (< 2 days, then merged)
```

**How it works:**
- Developers either commit directly to main or open a PR that merges within 24–48 hours
- Incomplete features are hidden behind **feature flags**, not branches
- CI runs on every commit to main; main is always releasable
- Releases are tags on main, not branches

**When it works:**
- Teams shipping multiple times per day (FAANG deployment cadence: Google deploys thousands of times/day)
- Strong CI with fast feedback (< 10 min)
- Feature flag infrastructure exists
- High trust, experienced engineers who write small commits

**When it fails:**
- Teams without feature flag infrastructure (risky half-finished features land in prod)
- Slow CI (> 30 min) — the trunk isn't green long enough to be useful
- Inexperienced teams who write large, tangled changes
- Compliance requirements that mandate long-lived release branches

**FAANG adoption:** Google (all teams), Facebook/Meta, Netflix, Uber. The default at companies that deploy continuously.

---

### 1.2 GitHub Flow

**Core idea:** Main is always deployable. Work in feature branches, PR to main, merge = deploy.

```
main:          A--------D--------G
                \      / \      /
feature-login:   B----C   E----F
```

**How it works:**
1. Branch from main with a descriptive name (`feature/oauth-login`, `fix/memory-leak`)
2. Commit, push frequently
3. Open PR when ready for review (or as Draft PR earlier for feedback)
4. CI runs on the PR branch
5. Merge to main triggers deploy to production

**When it works:**
- SaaS products where you deploy on every merge
- Small-to-medium teams (5–50 engineers)
- No hard release schedules (deploy when ready)

**When it fails:**
- When you need to ship version X while version X+1 is in development — you need separate release branches
- Multiple environments with different promotion gates (staging → canary → prod) — GitHub Flow doesn't model this well without extra conventions
- Enterprise products with regulated release cycles

**Compared to TBD:** More permissive branch lifetime, but similar philosophy. The difference is TBD discourages branches > 2 days; GitHub Flow allows longer-lived PRs. In practice, GitHub Flow with squash merge and < 3 day branches approaches TBD.

---

### 1.3 Gitflow

**Core idea:** Named long-lived branches for each lifecycle phase.

```
main (production):     ----1.0----1.1----2.0----
                           /          /
hotfix:                ---h1---      /
release/1.1:          /--------\   /
develop:      A-B-C-D----------E-F-G-H----
               \     / \       /
feature/x:      X---X   feature/y: Y-Y-Y
```

**Branches:**

| Branch | Purpose | Lifetime |
|--------|---------|---------|
| `main` | Production-ready code | Permanent |
| `develop` | Integration branch | Permanent |
| `feature/*` | One feature | Days to weeks |
| `release/*` | Release stabilization | Days to weeks |
| `hotfix/*` | Emergency production fix | Hours to days |

**Workflow:**
1. Feature branches branch from `develop`, merge back to `develop`
2. When ready to release, cut a `release/x.y` branch from `develop`
3. Bug fixes on `release/x.y` branch
4. Merge `release/x.y` to both `main` and `develop`
5. Tag `main` with the version
6. Hotfixes branch from `main`, merge to both `main` and `develop`

**When it works:**
- Mobile apps, desktop software, or APIs with versioned releases (v1.2.3)
- Long QA/UAT cycles (release branch stabilizes while develop moves forward)
- Multiple supported versions in prod simultaneously (v1.x and v2.x)
- Enterprise software with regulated release windows

**When it fails:**
- Teams trying to deploy continuously — Gitflow's ceremony slows everything down
- Small teams (< 5) — cognitive overhead isn't worth it
- Teams without CI — the integration problems that Gitflow tries to solve (via develop) still compound without automation

**Why FAANG avoids it:** Google, Meta, Netflix ship too fast for Gitflow's ceremony. They achieve stability through feature flags, automated testing, and canary releases — not branch isolation.

---

### 1.4 Release Branches (Simplified Gitflow)

**Core idea:** Trunk-Based + release branches for stabilization. No separate `develop` branch.

```
main:       A--B--C--D--E--F--G
                  |
release/1.2:      C--fix1--fix2--[tag v1.2.0]
                              |
release/1.2.1:               fix3--[tag v1.2.1]
```

**How it works:**
- Engineers commit to main (TBD style)
- When a release is ready, cut a `release/x.y` branch from main
- Only critical bug fixes are cherry-picked from main onto the release branch
- The release branch is tagged for deployment

**When it works:**
- Mobile apps (Apple/Google review cycles force a stabilization period)
- Kubernetes operators and infrastructure tooling (users run specific versions)
- Open-source projects with community release expectations

**FAANG adoption:** Used by teams that ship binaries or container images that customers manage (not SaaS). Google Kubernetes Engine, AWS CLI, etc.

---

## 2. Strategy Comparison

| Dimension | TBD | GitHub Flow | Gitflow | Release Branches |
|-----------|-----|-------------|---------|-----------------|
| Branch lifetime | Hours | Days | Weeks | Branch lives until EOL |
| Merge conflicts | Minimal | Low | High (long-lived branches) | Low (cherry-picks only) |
| CI complexity | Low | Low | High (multiple branch types) | Medium |
| Feature flag need | **Required** | Helpful | Not needed | Helpful |
| Deploy cadence | Multiple/day | Merge = deploy | Scheduled releases | Scheduled releases |
| Rollback | Feature flag off | Revert commit + redeploy | Version rollback | Checkout old tag |
| Team size sweet spot | Any (with flags) | 5–50 | 10–100 | Any |
| Industry fit | FAANG SaaS | Startups, SaaS | Enterprise, mobile | Open-source, infra |

---

## 3. Choosing a Strategy — Decision Framework

```
Are you deploying continuously (multiple times/day)?
  YES → Do you have feature flag infrastructure?
          YES → Trunk-Based Development
          NO  → GitHub Flow (while you build flag infra)
  NO  → Do you ship versioned releases (semver, app stores, enterprise)?
          YES → Do you need to support multiple versions simultaneously?
                  YES → Gitflow
                  NO  → Release Branches
          NO  → GitHub Flow
```

---

## 4. Naming Conventions (FAANG Standard)

```bash
# Features
feature/<ticket-id>-short-description
feature/PLAT-1234-add-rate-limiting

# Bug fixes
fix/<ticket-id>-short-description
fix/AUTH-567-token-expiry-race

# Hotfixes (emergency, goes to prod fast)
hotfix/<ticket-id>-short-description
hotfix/PAY-999-double-charge-bug

# Release branches
release/<major>.<minor>
release/2.4

# Chore / non-feature work
chore/upgrade-spring-boot-3.2
refactor/extract-payment-service
docs/update-api-spec
```

---

## 5. Merge Strategies

| Strategy | What it does | When to use |
|----------|-------------|-------------|
| **Merge commit** | Creates a merge commit with two parents | Preserving branch topology; long-lived feature branches |
| **Squash and merge** | All PR commits → one commit on main | Clean main history; standard at most FAANG teams |
| **Rebase and merge** | Replays commits linearly, no merge commit | Preserving individual commits; authors who write clean atomic commits |

**Recommendation for most teams:** Squash and merge. Main history becomes `[ticket-id]: description` — one line per PR. Easy to bisect, easy to revert.

---

## 6. Branch Protection Rules (GitHub/GitLab)

These are not optional at scale. Required settings for `main`:

```yaml
# GitHub branch protection (via API or Terraform)
required_status_checks:
  strict: true                    # branch must be up to date before merging
  contexts:
    - "ci/build"
    - "ci/unit-tests"
    - "ci/integration-tests"
    - "security/snyk"

required_pull_request_reviews:
  required_approving_review_count: 1
  dismiss_stale_reviews: true
  require_code_owner_reviews: true  # CODEOWNERS file

restrictions:
  push: []                        # nobody pushes directly to main
  
allow_force_pushes: false
allow_deletions: false
require_signed_commits: true      # GPG-signed commits for audit trails
```

**CODEOWNERS:**
```
# Global fallback
*                          @platform-team

# Payments — any change requires payments team approval
/src/payments/             @payments-team @security-team

# Infrastructure as code
/terraform/                @infra-team
/.github/workflows/        @platform-team
```

---

## 7. Monorepo Branching

At companies with monorepos (Google, Meta, Twitter/X, Uber), branching strategy shifts:

- **One trunk** — all services live on main, always deployable
- **Build system knows what changed** — Bazel/Buck/Pants build only affected targets
- **Per-service deployments** — CI runs per-service tests on changed paths; each service deploys independently
- **No feature branches** — impossible to have a "feature branch" when 2000 engineers are on the same repo; everything is behind flags

**The hidden constraint:** Monorepo + feature branches = merge hell. A branch that touches shared libraries will have conflicts with every other branch that also touched them. This is why Google enforces TBD so strictly.

---

## 8. Common Failure Modes

| Problem | Symptom | Fix |
|---------|---------|-----|
| Long-lived feature branches | "This PR has 150 conflicts" | Switch to TBD + feature flags |
| Broken main | CI is always red | Add required status checks, require CI to pass before merge |
| Force-push to main | History rewritten, teammates' local branches diverge | Branch protection: disable force push |
| Cherry-pick drift | Release branch diverges from main | Limit cherry-picks; prefer forward-fix then backport tooling |
| Too many stale branches | `git branch -r` returns 800 branches | Auto-delete branches after merge; add branch staleness policy (30 days) |
| Gitflow overhead on a fast team | Release manager becomes a bottleneck | Switch to TBD; release managers become feature-flag owners |

---

## FAANG Interview Callouts

**"What branching strategy would you recommend for a team of 20 engineers shipping a SaaS product?"**
→ GitHub Flow with squash-and-merge. Enforce branch protection (1 approval + CI green). If you're shipping > 5x/day, push toward TBD and invest in feature flags. The decision matrix: deployment cadence × release versioning needs × team maturity.

**"How do you handle a hotfix when your team uses TBD?"**
→ Fix forward on main behind a flag. If main is too broken or the fix is time-sensitive: create a `hotfix/` branch from the last good tag on main, apply fix, merge to main (creating a tag), then cherry-pick to any release branches. The key: main is always releasable, so hotfix branches are short-lived (< 4 hours).

**"We have 5 microservices in separate repos and branching is inconsistent. What do you do?"**
→ Establish org-wide branching standards via an RFC. Automate enforcement via shared GitHub Actions workflow templates (`.github/workflows/`) stored in a `.github` org-level repo. Migrate teams one at a time — don't try to do it all at once. Measure with DORA metrics: deployment frequency and change failure rate tell you if the strategy is working.
