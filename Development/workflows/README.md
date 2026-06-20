# Development Workflows

Engineering workflow knowledge expected at the principal engineer level — how software moves from idea to production safely and repeatedly at scale.

## Files in this Directory

| File | Topic | Key Concepts |
|------|-------|-------------|
| [01-git-branching-strategies.md](01-git-branching-strategies.md) | Git branching models | Trunk-Based Development, GitFlow, GitHub Flow, CODEOWNERS, commit standards |
| [02-pr-review-standards.md](02-pr-review-standards.md) | Pull request culture | Review goals, PR size limits, feedback language, SLA, review metrics |
| [03-code-ownership.md](03-code-ownership.md) | Code and service ownership | Ownership models, CODEOWNERS, service catalog, ownership rot, transitions |
| [04-release-management.md](04-release-management.md) | Release strategies | Canary, blue-green, feature flags, release trains, rollback, deploy freezes |
| [05-change-management.md](05-change-management.md) | Managing high-risk changes | RFC process, DB migrations, strangler fig, breaking change comms, audit trail |
| [06-api-lifecycle-management.md](06-api-lifecycle-management.md) | API versioning and deprecation | Versioning strategies, breaking vs. non-breaking changes, deprecation process, design governance |
| [07-architecture-review-process.md](07-architecture-review-process.md) | Design docs, RFCs, ADRs | When to write each, full templates, review protocols, ADR storage |
| [08-developer-productivity-metrics.md](08-developer-productivity-metrics.md) | Engineering productivity | DORA metrics (all 4), SPACE framework, what NOT to measure, dashboard template |
| [09-dependency-management-workflow.md](09-dependency-management-workflow.md) | Dependency governance | CVE response SLA, version pinning, approved registry, license compliance, EOL management |
| [10-developer-experience-inner-loop.md](10-developer-experience-inner-loop.md) | DevEx and local dev | Docker Compose dev env, hot reload, service virtualization, onboarding automation |
| [11-sprint-to-production-workflow.md](11-sprint-to-production-workflow.md) | End-to-end delivery lifecycle | INVEST criteria, DoD, CI stages, canary protocol, feature flag rollout, post-deploy monitoring |

## Key Trade-offs to Know

| Decision | Options | Principal Engineer Recommendation |
|----------|---------|----------------------------------|
| Branching strategy | Trunk vs GitFlow | Trunk-Based Development for high-frequency SaaS; GitFlow for mobile/packaged |
| PR size | Large vs small PRs | Enforce < 500 lines; large PRs get rubber-stamped and hide bugs |
| Release strategy | Continuous vs scheduled | Continuous with feature flags + canary gates; trains for cross-team coordination |
| Schema migrations | Big-bang vs phased | Always phased (3-phase pattern); never combine schema + data migration |
| Change communication | Ad-hoc vs structured | Structured: 6-week notice for breaking changes, dashboard for migration tracking |
| API versioning | URI vs header vs additive-only | URI versioning for public APIs; additive-only for internal with disciplined consumers |
| Design review scope | Design doc vs RFC | Design doc for 1-team, reversible decisions; RFC for cross-team or hard-to-reverse |
| Dependency updates | Manual vs automated | Automated (Dependabot/Renovate) for patch/minor; planned sprints for major versions |

## Interview Question Map

| Interview Question | File |
|-------------------|------|
| Which branching strategy for 50-team org? | [01-git-branching-strategies.md](01-git-branching-strategies.md) |
| How to scale code review without bottlenecks? | [02-pr-review-standards.md](02-pr-review-standards.md) |
| How to handle a disagreement in PR review? | [02-pr-review-standards.md](02-pr-review-standards.md) |
| Design ownership model for 200-engineer org | [03-code-ownership.md](03-code-ownership.md) |
| Zero-downtime database migration | [05-change-management.md](05-change-management.md) |
| Design release process for 50-team org | [04-release-management.md](04-release-management.md) |
| Communicate breaking API change at scale | [06-api-lifecycle-management.md](06-api-lifecycle-management.md) |
| How to deprecate an API with 200 consumers | [06-api-lifecycle-management.md](06-api-lifecycle-management.md) |
| Production incident — broken release | [04-release-management.md](04-release-management.md) |
| Get alignment on major architectural change | [07-architecture-review-process.md](07-architecture-review-process.md) |
| When to write RFC vs design doc | [07-architecture-review-process.md](07-architecture-review-process.md) |
| How do you measure engineering productivity? | [08-developer-productivity-metrics.md](08-developer-productivity-metrics.md) |
| Team velocity dropped 30% — how to diagnose? | [08-developer-productivity-metrics.md](08-developer-productivity-metrics.md) |
| Log4Shell just dropped — walk me through response | [09-dependency-management-workflow.md](09-dependency-management-workflow.md) |
| How to improve developer productivity for 50 engineers? | [10-developer-experience-inner-loop.md](10-developer-experience-inner-loop.md) |
| Design delivery workflow from 5 to 50 engineers | [11-sprint-to-production-workflow.md](11-sprint-to-production-workflow.md) |
| Roll out a high-risk change to production | [11-sprint-to-production-workflow.md](11-sprint-to-production-workflow.md) |
