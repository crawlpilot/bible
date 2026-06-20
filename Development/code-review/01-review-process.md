# Code Review Process

## PR Lifecycle

```
Author                          Reviewer(s)                    CI / Automation
  │                                  │                               │
  │── write code ────────────────────│                               │
  │── self-review (pre-flight) ──────│                               │
  │── open PR ─────────────────────────────────────────────────────▶│
  │                                  │◀─── CI: lint, test, build ────│
  │◀─ assign reviewer(s) ────────────│                               │
  │                                  │── read description ───────────│
  │                                  │── review code ────────────────│
  │                                  │── leave comments ─────────────│
  │◀─ review comments ───────────────│                               │
  │── respond to comments ───────────│                               │
  │── push fixes ────────────────────│──────────────────────────────▶│
  │◀─ re-review (changed areas) ─────│                               │
  │◀─ LGTM ──────────────────────────│                               │
  │── merge (squash/rebase) ─────────│                               │
  │── delete branch ─────────────────│                               │
```

---

## Author Responsibilities

### Before Opening the PR

Run this checklist yourself before requesting review. Every item you miss costs a reviewer round-trip.

```
Pre-flight — Author Checklist
─────────────────────────────────────────────────────────────
Code
  ☐ I have re-read my own diff as if I were a stranger
  ☐ All new behaviour is covered by tests
  ☐ I have not introduced dead code, commented-out code, or TODOs without a ticket
  ☐ No print statements, console.log, System.out.println left in
  ☐ No secrets, passwords, or API keys in the diff
  ☐ No PII in logs, error messages, or responses
  ☐ Public API / event schema changes are backwards compatible
  ☐ Database migrations are additive (no column drops, renames, or NOT NULL without default)

Tests
  ☐ Happy path is tested
  ☐ Error/edge cases are tested (null input, empty list, boundary values, concurrent access)
  ☐ I have not deleted or commented out existing tests to make the build green
  ☐ Test names describe what is being tested, not how

PR Description
  ☐ Title: imperative verb, present tense ("Add order retry logic", not "Added" or "Adds")
  ☐ What: one paragraph on what changed
  ☐ Why: one paragraph on why (link to ticket/issue)
  ☐ How to test: steps for reviewer to verify the change manually if applicable
  ☐ Breaking changes called out explicitly
  ☐ Screenshots for UI changes
  ☐ Rollback plan for risky changes
```

### PR Size

| PR size | Lines changed | Review quality |
|---|---|---|
| **Ideal** | < 400 lines | Thorough review possible |
| **Acceptable** | 400–800 lines | Reviewer needs more time; split if possible |
| **Too large** | > 800 lines | Review quality degrades; split required |

**Rule**: if a PR cannot be split without losing coherence (e.g., a large refactor), add a PR walkthrough comment explaining the structure of the change — which files to read first and why.

---

## Reviewer Responsibilities

### SLA (Default — Adjust to Team Cadence)

| Priority | First response | Complete review |
|---|---|---|
| **P0 (unblocks a team member)** | 1 hour | Same day |
| **P1 (sprint work)** | Same business day | Within 1 business day |
| **P2 (non-blocking)** | 2 business days | 2 business days |

If you cannot complete a review within SLA, comment on the PR so the author knows and can find another reviewer.

### How to Review

**Read the PR description first.** If there is no description or the description doesn't explain why the change exists, request one before reviewing the code.

**Review in passes** — don't comment as you read the first time. First pass: understand the change as a whole. Second pass: detailed comments.

```
Reviewer Checklist
─────────────────────────────────────────────────────────────
First pass — Design
  ☐ Do I understand what this change does and why?
  ☐ Is this the right approach, or is there a simpler/safer design?
  ☐ Does it introduce unnecessary complexity?
  ☐ Are new abstractions (classes, interfaces, modules) justified?
  ☐ Does it create tight coupling between components?

Second pass — Correctness
  ☐ Does the code match what the PR description says it does?
  ☐ Are edge cases handled (null, empty, boundary values)?
  ☐ Are errors handled appropriately (not swallowed, not over-caught)?
  ☐ Is concurrent/shared state accessed safely?
  ☐ Are there race conditions or TOCTOU bugs?

Third pass — Tests
  ☐ Do tests test behaviour, not implementation?
  ☐ Are tests readable? Would someone understand what failed just from the test name?
  ☐ Is there meaningful coverage of error cases?
  ☐ Are there any test smells (assertions on mocks, no assertions, testing private methods)?

Fourth pass — Standards
  ☐ Logging (see 03-logging-checklist.md)
  ☐ Security (see 04-security-checklist.md)
  ☐ Language-specific issues (see 05/06/07)
  ☐ Naming: are names clear without reading the implementation?
  ☐ Comments: do comments explain WHY (not WHAT)?
  ☐ Dependencies: is each new dependency justified?
```

---

## Feedback Etiquette

### How to Write Good Review Comments

Code review comments are communication. Tone matters.

**Principles:**
- Comment on the code, not the person
- Explain the problem, not just point at it
- Offer an alternative when you block
- Distinguish blocking issues from preferences
- Ask questions rather than stating fault when uncertain

```
POOR:  "This is wrong."
GOOD:  "[BLOCK] If `user` is null here (e.g., unauthenticated request), 
        this throws NPE. Add a null check or use Optional."

POOR:  "Why did you do it this way?"
GOOD:  "[QUESTION] I'd have used a Map here for O(1) lookup — 
        is there a reason to keep the List? Happy to discuss if there's context I'm missing."

POOR:  "I would have done this differently."
GOOD:  "[SUGGESTION] Could simplify with streams: 
        `list.stream().filter(x -> x.active()).collect(toList())` — 
        no functional change, just shorter. Author's call."
```

### How to Respond to Review Comments

- **Acknowledge** every comment — don't silently fix without replying
- **Push back** when you disagree — "Done" is acceptable only if you made the change; explain if you didn't
- **Resolve** comments only after the fix is pushed and the reviewer has seen it (or you've agreed to defer)
- **Don't argue style** — if a reviewer has a style preference, default to theirs; it's not worth the round-trip. Automate style instead.

---

## Roles and Approval Rules

### Who Should Review

| Change type | Minimum reviewers |
|---|---|
| Bug fix, small feature | 1 from the owning team |
| New feature, significant refactor | 2: 1 domain expert + 1 broader reviewer |
| Public API change | 2 + team lead sign-off |
| Security-sensitive change | 2 + security team review |
| Database migration | 1 dev + DBA review |
| Infrastructure / CI change | 2: 1 dev + 1 ops/infra |
| Configuration change in production | 2 + change management ticket |

### Escalation Path

1. Author and reviewer cannot agree → involve a third reviewer
2. Three reviewers cannot agree → team lead decides; documents the reason
3. Cross-team impact → RFC or design doc required before merge
4. Security dispute → always defer to security team; no merge without their sign-off

---

## Merge Strategy

| Strategy | When to use | Pros | Cons |
|---|---|---|---|
| **Squash and merge** | Feature branches; one logical change | Clean linear history; bisect-friendly | Loses individual commit messages |
| **Rebase and merge** | Sequential independent commits that tell a story | Preserves commit detail; linear | Requires clean commit history from author |
| **Merge commit** | Long-lived branches (release, hotfix) | Preserves branch context | Cluttered history on main |

**Default recommendation**: squash and merge for feature PRs. Rebase for changelog-documented changes. Never use merge commit on main.

---

## Post-Merge

- **Delete the branch** immediately after merge
- If the change introduced a known risk: **monitor alerts for 24 hours** after merge to production
- If the PR contained a bug or incident: **add a retrospective comment** on the PR for future reference
- **Update documentation** in the same PR, not in a follow-up (follow-ups don't happen)

---

## Google's Code Review Principles (Reference)

Google's eng guide (publicly available) codifies these rules:

> "The primary purpose of code review is to ensure that the overall code health of Google's code base is improving over time."

Key principles applied at Google:
1. **Reviewers should approve a CL (changelist) if it definitely improves overall code health**, even if it isn't perfect
2. **Authors should not be blocked on reviews** — reviewers must respond within 1 business day
3. **There is no such thing as "perfect" code** — there is only better code
4. **In a conflict, the reviewer's preference wins on style; the author's wins on implementation**
5. **If a CL is too large to review well, the reviewer can ask for it to be split**
