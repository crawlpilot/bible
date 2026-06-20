# Pull Request Review Standards

## Why This Matters at Principal Engineer Level

Code review is the primary mechanism for knowledge transfer, quality enforcement, and architectural consistency across teams. A principal engineer defines the review culture — what reviewers look for, how feedback is communicated, how fast PRs turn around, and when to block vs. approve-with-comments. Getting this wrong causes either rubber-stamp approvals (quality degrades) or review bottlenecks (velocity collapses).

---

## PR Review Goals (in priority order)

1. **Correctness** — Does the code do what it claims? Does it handle edge cases and failures?
2. **Security** — Does it introduce vulnerabilities (OWASP top 10, secret leakage, privilege escalation)?
3. **Design** — Is it consistent with existing patterns? Does it create tech debt?
4. **Readability** — Will the next engineer understand this in 6 months?
5. **Tests** — Are the critical paths covered?
6. **Performance** — Are there obvious bottlenecks or N+1 queries?

Style is **last** and largely automated (linters, formatters). A reviewer should almost never block a PR for a style issue that a tool could catch.

---

## PR Size Standards

| Size | Lines changed | Review SLA | Recommended strategy |
|------|--------------|------------|---------------------|
| XS | < 50 | 2 hours | Any reviewer |
| S | 50–200 | 4 hours | 1 approver |
| M | 200–500 | 1 day | 2 approvers |
| L | 500–1000 | 2 days | 2 approvers + design check |
| XL | > 1000 | Reject as-is | Must be split |

**Principal engineer rule:** PRs over 1000 lines are a process smell. If a feature needs 3000 lines, it should ship in 3–5 PRs. Large PRs get rubber-stamped, hide bugs, and block others.

**How to split a large PR:**
- Vertical slice (feature layer by layer): DB schema → repo → service → API → UI
- Infrastructure first: add the hook, then fill in the implementation
- Strangler fig: add new path in parallel, shift traffic, delete old path

---

## The Author's Checklist (before requesting review)

```markdown
## PR Checklist

### Correctness
- [ ] Handles null / empty inputs
- [ ] Handles downstream service failure (timeout, 5xx)
- [ ] Idempotent if called twice (especially mutations)
- [ ] Thread-safe if accessed concurrently

### Tests
- [ ] Unit tests for all business logic branches
- [ ] Integration test for the happy path
- [ ] Edge case: empty list, max value, concurrent access

### Security
- [ ] No secrets in code or logs
- [ ] Input validated and sanitized at boundaries
- [ ] Authorization checked (not just authentication)
- [ ] No SQL/command injection vectors

### Observability
- [ ] New code path emits a metric or structured log
- [ ] Errors are logged with enough context to debug
- [ ] Latency-sensitive paths have tracing

### Documentation
- [ ] Public API contracts updated
- [ ] CHANGELOG entry if user-facing
- [ ] Linked to ticket (JIRA/Linear)
```

---

## The Reviewer's Mental Model

### First pass: intent (2 min)
- Read the PR description. What problem does this solve?
- If the description is missing, ask for it before reviewing code.
- Check the linked ticket for context.

### Second pass: design (10 min)
- Does this belong here? Wrong abstraction level?
- Does it introduce a new pattern that conflicts with existing patterns?
- Does it have the right boundaries (service, module, class)?

### Third pass: correctness (remainder)
- Read every line that changes business logic
- Check error paths explicitly — most bugs are in error handling
- Look for race conditions in concurrent code
- Verify the test covers the scenario it claims to

---

## Feedback Language Standards

Distinguish the **severity** of feedback clearly. Never make reviewers guess if a comment is blocking.

| Prefix | Meaning | Example |
|--------|---------|---------|
| `nit:` | Style, optional — don't block | `nit: variable name could be more descriptive` |
| `suggestion:` | Better approach, but not critical | `suggestion: this could use a builder pattern` |
| `question:` | Seeking understanding, not blocking | `question: why was this approach chosen over X?` |
| `issue:` | Bug or correctness problem — must fix | `issue: this will NPE if list is empty` |
| `blocking:` | Design flaw — needs discussion before merge | `blocking: this couples the payment service to the user service` |

**Tone rules:**
- Comment on the **code**, not the author: "This method does X" not "You did X"
- Lead with what you'd expect: "I'd expect this to return early if..." — not a judgment
- Provide a suggested alternative when blocking: don't just say "wrong", say "here's what I'd do"

---

## Reviewer Assignment Strategy

**CODEOWNERS** handles automatic assignment. Beyond that:

- **Domain expert** — always include the team that owns the code being modified
- **Consumer of the API** — if the PR changes a contract, include a team that depends on it
- **Security-sensitive code** — include security team on auth, payment, PII paths
- **Architectural change** — principal engineer review required

**Avoid:**
- Assigning > 3 reviewers (diffusion of responsibility)
- Assigning the same 2 senior engineers to every PR (bottleneck)
- Self-approving (even principals shouldn't)

---

## Review SLA and Escalation

```
Author opens PR
    │
    ├─ Reviewers assign within 30 min (business hours)
    │
    ├─ First review comment within SLA (see size table)
    │
    ├─ Author responds / revises within 4 hours
    │
    ├─ Reviewer re-reviews within 2 hours of revision
    │
    └─ Merge within 2 business days or escalate to EM
```

**Escalation triggers:**
- No reviewer response after 2× SLA → ping in team Slack channel
- Disagreement on design → tech lead / principal mediates (time-boxed to 30 min)
- Blocking comment unresolved > 2 days → synchronous meeting, time-boxed to 30 min

---

## Draft PRs and Early Feedback

Use draft PRs for:
- **RFC-style design validation** — get architecture feedback before writing all the code
- **WIP that unblocks others** — share early even if not complete
- **Cross-team changes** — start the conversation before the work is done

Convention: prefix the title with `[RFC]` for design-only reviews, `[WIP]` for in-progress code.

---

## Measuring Review Health (Metrics for a Team)

| Metric | Target | Action if exceeded |
|--------|--------|--------------------|
| PR cycle time (open → merge) | < 2 days | Investigate bottleneck reviewer |
| PR size (median lines changed) | < 300 | Process review on PR splitting |
| Review coverage (% PRs with ≥ 1 human review) | 100% | Fix CODEOWNERS |
| Review turnaround time | < 4 hours | SLA reminder, rotate reviewers |
| PR rejection rate (sent back for redesign) | < 10% | Invest in design docs / pre-review |

Track in your eng metrics dashboard (GitHub Insights, LinearB, Swarmia, or custom BigQuery pipeline).

---

## Interview Framing

**Q: How do you scale code review without creating bottlenecks?**

> The bottleneck is almost always a small set of senior engineers as the sole trusted reviewers. I fix this by making review expectations explicit and distributing ownership: CODEOWNERS assigns domain experts automatically, I establish a severity taxonomy so reviewers don't feel they need to catch everything, and I cap mandatory approvers at two. For high-stakes areas — auth, payments, schema migrations — I keep a short list of required approvers, but for everything else I push ownership to the team. I also use PR size limits; reviews over 500 lines almost always get rubber-stamped, so I mandate splitting. Finally I measure cycle time and flag bottleneck reviewers to the EM — if one person is on 80% of PRs, that's a structural problem.

**Q: How do you handle a disagreement between two senior engineers in a PR review?**

> I time-box it. If the PR thread has more than 5 back-and-forth comments with no convergence, I call a 30-minute synchronous meeting. The goal is a decision, not consensus. I'll ask both engineers to state their position and their concerns explicitly, then I'll make the call — or defer to whoever owns that code area. The key is that the code isn't blocked: either we merge the current approach with a documented follow-up to address the concern, or we hold and fix it now. I document the decision in the PR thread so future readers have context.
