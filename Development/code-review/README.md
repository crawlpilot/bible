# Code Review Standards — Engineering Template

> A team-adoptable template for standardising code review practices. Fork this folder into your team wiki, remove sections that don't apply, and add your stack-specific rules. Calibrated to the bar used at Google, Meta, Amazon, and Stripe.

---

## Philosophy

Code review is not a gate — it is a collaboration. The goal is to ship correct, maintainable, secure code as a team, not to catch mistakes after the fact or demonstrate seniority through critique.

**What code review is for:**
- Correctness: does the code do what it claims?
- Shared ownership: every reviewer partially owns what they approve
- Knowledge transfer: the team learns the change, not just the author
- Design feedback: the right time to question an approach is before it ships
- Standards enforcement: naming, structure, security, observability

**What code review is NOT for:**
- Style wars (automate style with linters/formatters — never debate it in review)
- Proving expertise by finding fault
- Rewriting the author's solution in your preferred style
- Blocking on personal preference (distinguish preference from principle)

---

## Folder Structure

| File | Contents |
|---|---|
| [01-review-process.md](01-review-process.md) | PR lifecycle, author checklist, reviewer SLAs, feedback etiquette, escalation |
| [02-general-checklist.md](02-general-checklist.md) | Universal review checklist — correctness, tests, design, naming, error handling, concurrency |
| [03-logging-checklist.md](03-logging-checklist.md) | Logging anti-patterns, PII, log levels, structured logging, performance |
| [04-security-checklist.md](04-security-checklist.md) | OWASP Top 10, injection, auth/authz, secrets, input validation, crypto |
| [05-java-checklist.md](05-java-checklist.md) | Java-specific: null/Optional, streams, exceptions, concurrency, generics, immutability |
| [06-kotlin-checklist.md](06-kotlin-checklist.md) | Kotlin-specific: null safety, coroutines, data classes, sealed classes, extension functions |
| [07-python-checklist.md](07-python-checklist.md) | Python-specific: type hints, mutable defaults, comprehensions, context managers, dataclasses |

---

## How to Adopt This Template

1. **Copy this folder** into your team's internal wiki or repo (`docs/code-review/`)
2. **Delete language checklists** that don't apply to your stack
3. **Add your team's rules** — deployment constraints, DB migration rules, rate limit policies, etc.
4. **Set the SLA** in `01-review-process.md` to match your team's sprint cadence
5. **Add a pre-merge CI check** that enforces linting and test coverage so reviewers don't spend time on automatable issues
6. **Link from your PR template** — every PR description should reference the relevant checklist sections

---

## Severity Levels Used in Checklists

| Label | Meaning | PR can merge? |
|---|---|---|
| `[BLOCK]` | Must be fixed before merge. Correctness, security, data loss risk | No |
| `[WARN]` | Should be fixed; discuss with author. Technical debt, missing test coverage | Author decides with justification |
| `[NIT]` | Minor style or polish; low priority | Yes — address in follow-up or ignore |
| `[QUESTION]` | Reviewer needs clarification; not necessarily a problem | Merge after explanation |
| `[SUGGESTION]` | Optional improvement; reviewer's preference | Author's call |

**Rule**: never use `[BLOCK]` for personal style preference. Only block on objective issues: correctness, security, missing tests for changed behaviour, broken contracts.

---

## The LGTM Standard

An LGTM (Looks Good To Me) means the reviewer:
- Understands what the change does
- Believes it is correct
- Is comfortable co-owning it in production

Do not LGTM a change you don't understand. "I trust the author" is not a code review — it is a rubber stamp.

---

## Quick Reference: What to Always Check

```
☐ Does the change have tests that cover the new behaviour?
☐ Does it handle error cases?
☐ Is any PII or secret visible in logs, responses, or error messages?
☐ Does it change a public API or event schema? (backwards compatible?)
☐ Does it touch concurrency, caching, or distributed state?
☐ Does it add a new dependency? (licence, security, maintenance?)
☐ Does it have any DB migration? (non-additive change = BLOCK)
☐ Does it change configuration? (documented? feature-flagged?)
☐ Is the PR description accurate about what changed and why?
```
