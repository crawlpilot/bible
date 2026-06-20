# Git — Principal Engineer Reference

This folder covers Git from first principles through the workflows, branching strategies, and deployment patterns used at FAANG scale. Everything here is calibrated to interview depth: you should be able to discuss _why_ a team chose a strategy, the failure modes they encountered, and how they evolved it.

## Files

| File | What it covers |
|------|----------------|
| [01-git-cheatsheet.md](01-git-cheatsheet.md) | Command reference with the _why_ behind each: plumbing vs porcelain, reflog, interactive rebase, bisect, worktrees |
| [02-branching-strategies.md](02-branching-strategies.md) | Gitflow vs Trunk-Based vs GitHub Flow vs Release branches — trade-offs, team size thresholds, FAANG preferences |
| [03-deployment-processes.md](03-deployment-processes.md) | How Git integrates with CI/CD: deployment rings, feature flags, rollback strategies, monorepo vs polyrepo |

## Interview Signals

A principal engineer question on Git is rarely about syntax. Expect:

- "How did you handle a merge conflict in a shared library used by 30 teams?" → see [02-branching-strategies.md](02-branching-strategies.md)
- "How do you roll back a bad deploy without downtime?" → see [03-deployment-processes.md](03-deployment-processes.md)
- "We're moving 40 repos into a monorepo — what breaks first?" → see [03-deployment-processes.md](03-deployment-processes.md)
- "Your team ships 50 times a day. How do you keep main green?" → see [02-branching-strategies.md](02-branching-strategies.md)

## Cross-Links

- [ci-cd/02-deployment-strategies.md](../ci-cd/02-deployment-strategies.md) — blue/green, canary, rolling at the infra level
- [workflows/01-git-branching-strategies.md](../workflows/01-git-branching-strategies.md) — original branching overview
- [workflows/04-release-management.md](../workflows/04-release-management.md) — release trains and freeze windows
- [best-practices/01-code-review-standards.md](../best-practices/01-code-review-standards.md) — PR standards that feed back into branching choices
