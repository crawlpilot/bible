# Code Review Best Practices & Standards

## Overview
Code review is the highest-leverage quality gate in software engineering. At FAANG scale, a code review is not just a bug check — it is a knowledge transfer mechanism, an architecture enforcement tool, and an onboarding accelerator. Principal engineers set the tone for review culture. Getting this right reduces defect escape rate, prevents architectural drift, and builds team capability faster than any other process.

---

## What Code Review Is (and Is Not)

| Code Review IS | Code Review IS NOT |
|---|---|
| A safety net for correctness and maintainability | A gatekeeping ritual that slows delivery |
| A knowledge transfer channel | A place to prove intellectual superiority |
| An architecture consistency check | A style debate (that's what linters are for) |
| A collaborative design session | A blame-assignment exercise |
| An asynchronous documentation artifact | A replacement for pair programming or design reviews |

**Principal engineer rule**: if you find yourself writing the same comment 3+ times per week across reviews, that is a signal for a team standard, a linter rule, or an ADR — not another review comment.

---

## The Review Pyramid

```
              ┌───────────────┐
              │ Style/Format  │  ← Automate with linters/formatters (don't spend human time here)
              ├───────────────┤
              │ Correctness   │  ← Unit tests + code logic
              ├───────────────┤
              │ Maintainability│ ← Naming, structure, complexity
              ├───────────────┤
              │ Design        │  ← SOLID, patterns, module boundaries
              ├───────────────┤
              │ Architecture  │  ← Service boundaries, data contracts, scalability
              └───────────────┘
              High-priority (bottom → top)
```

Reviewers should spend time on the bottom of the pyramid. Style issues should be caught by CI/CD before a human sees the diff.

---

## FAANG Code Review Standards

### Google (internal guidelines, publicly referenced)
- **LGTM (Looks Good To Me)** threshold: reviewer should approve only if they'd be comfortable being the on-call for this change at 3am
- **Readability** requirements: certain language-specific coding style certifications required before merging complex changes
- **Change size**: CLs (changelists) should be small — ideally < 200 lines of meaningful change
- **Response SLA**: reviewers expected to respond within 1 business day; acknowledge with "will review by EOD" if delayed
- **At least one approval** from an owner of the file being changed

### Meta (internal review culture)
- **Differential mindset**: Diffs are conversations, not submissions for judgment
- **Small, frequent commits**: "arc diff" culture; land changes in logical units, not "all of sprint 2 in one PR"
- **Graceful degradation expectation**: reviewer asks "what happens if this fails at 10× load?"
- **Configeek principle**: changes to configuration, feature flags, and database queries reviewed with extra scrutiny

### Amazon (Code Review within Leadership Principles)
- **Dive Deep**: reviewers expected to go beyond surface — understand WHY, not just what
- **Have Backbone; Disagree and Commit**: reviewer should push back on design concerns; author should push back on incorrect review feedback
- **Ownership**: the team that merges the code owns the production consequences

### Netflix
- **Freedom & Responsibility**: no mandatory approval count — engineers trusted; post-incident reviews are accountability mechanism
- **Surgical reviews**: reviewers focus on blast radius and rollback posture, not style
- **Chaos readiness**: "does this change handle partial failure?" is a standard question

---

## Review Checklist (Reviewer's View)

### Correctness
- [ ] Does the code do what the PR description claims?
- [ ] Are edge cases handled? (null, empty list, negative values, concurrent access)
- [ ] Are there tests? Do the tests actually cover the claimed behaviour?
- [ ] Are error paths handled correctly (not just happy path)?
- [ ] Is exception/error information preserved, not swallowed?

### Security (OWASP Top 10 lens)
- [ ] Is user input validated and sanitised before use?
- [ ] Are secrets hardcoded? (even in test files — they end up in git history)
- [ ] Are SQL queries parameterised? (SQL injection)
- [ ] Are authorisation checks present (not just authentication)?
- [ ] Are file paths, URLs, or redirects validated to prevent traversal or open redirect?
- [ ] Is sensitive data logged? (PII, tokens, passwords)

### Performance
- [ ] Are there N+1 query patterns? (loop calling DB on each iteration)
- [ ] Are there unbounded queries? (no LIMIT on SELECT)
- [ ] Is there unnecessary work in hot paths (per-request, per-event)?
- [ ] Are large in-memory collections a risk at production data volumes?
- [ ] Is caching used appropriately — and invalidated correctly?

### Design & Maintainability
- [ ] Does this change belong here? (correct service, correct module, correct layer)
- [ ] Is the naming clear without reading the implementation?
- [ ] Is there duplication that should be extracted?
- [ ] Is the change adding complexity that isn't required by the requirements?
- [ ] Will this be understandable to a new team member in 6 months?

### Observability
- [ ] Are new failure modes observable? (metrics, logs, alerts)
- [ ] Do error logs include enough context to diagnose? (trace ID, entity IDs, operation name)
- [ ] Are new SLIs/SLOs defined for significant new functionality?

### Operational
- [ ] Is this change backwards-compatible with the current deployed version? (rolling deploys)
- [ ] Is the change reversible? (feature flag, migration rollback)
- [ ] Are database migrations non-blocking? (no table locks on large tables)

---

## Review Checklist (Author's View)

Before requesting review:
- [ ] Self-review the full diff — catch trivial issues before a colleague's time is spent
- [ ] PR description answers: what, why, and how to test
- [ ] CI passes (tests, linters, security scans)
- [ ] Change is appropriately scoped — not "also cleaned up X, Y, Z" mixed with the main change
- [ ] Migration scripts included where needed
- [ ] Feature flag wrapping production-impacting changes in first rollout
- [ ] Linked to relevant tickets/requirements

---

## Effective Review Comments

### Comment Categories (use prefixes)
- `nit:` — minor style issue; reviewer won't block on this
- `suggestion:` — optional improvement; reviewer thinks it's better but won't block
- `question:` — genuinely unclear; reviewer needs explanation before approving
- `blocking:` — reviewer believes this must change before merge
- `praise:` — explicitly positive comment; normalise calling out good work

### Comment Quality Standards

**Bad comment**:
> "This is wrong."

**Better comment**:
> `blocking:` This will cause a NullPointerException if `user` is null (it can be null per the auth flow in `AuthService.java:142`). Suggest adding a null check or asserting non-null at the API boundary.

**Bad comment**:
> "Use streams here."

**Better comment**:
> `suggestion:` This for-loop with an accumulator variable could be a Stream reduce, which would make the intent clearer: `lines.stream().map(Line::total).reduce(Money.ZERO, Money::add)`. Up to you — keeping it imperative is also fine if the team finds it easier to read.

### Rules for Effective Comments
1. **Be specific**: quote the exact line; explain the exact issue
2. **Explain the why**: "this will fail under concurrent access because..." not just "this has a race condition"
3. **Offer a solution or direction**: not just a problem statement
4. **Separate blocking from non-blocking**: use prefixes; don't leave ambiguity about whether review is blocked
5. **Assume good intent**: "I think this might be clearer as..." not "this is poorly written"
6. **Acknowledge constraints**: "I know this is a quick fix — long-term we should X, but this unblocks the sprint"

---

## Handling Disagreements

### Author's responsibility when pushback is received
1. Read the comment assuming the reviewer is correct; re-examine the code
2. If you agree: acknowledge and fix
3. If you disagree: respond with evidence and reasoning (not defensiveness)
4. If unresolved after one exchange: escalate to a 10-minute sync call — async debates are inefficient

### Reviewer's responsibility when author disagrees
1. Be willing to re-examine your position with new information
2. Distinguish opinion from fact: "I prefer X" vs "X will cause Y under Z condition"
3. Escalate to team convention discussion if the disagreement reveals a missing standard

**Principal engineer principle**: disagree and commit. Once a decision is made (with reasons documented), the team moves forward. Revisit in retrospective, not in production.

---

## Review Size and Scope Standards

| Change Size | Guideline | Why |
|---|---|---|
| < 50 lines | Turnaround within hours | Small, low-risk; reviewer can context-switch quickly |
| 50–200 lines | Turnaround same day | Standard unit of work; holds context |
| 200–500 lines | Break up if possible; review as full context block | Hard to review well in fragmented time |
| > 500 lines | Require pre-review design alignment; split if possible | Review quality degrades; context loss likely |
| Database migration alone | Separate PR, separate approval | High blast radius; deserves focused review |
| Config changes alone | Separate PR; extra scrutiny | Low test coverage; high production impact |

---

## Automated Gates (What Should Never Reach Human Review)

Configure in CI/CD pipeline as mandatory checks before review can be requested:

```
┌─ Formatting ─────────────────────────────────────────────────────────┐
│  Java: Google Java Format / Checkstyle                               │
│  Python: Black + isort                                               │
│  JS/TS: Prettier + ESLint                                            │
└──────────────────────────────────────────────────────────────────────┘
┌─ Static Analysis ────────────────────────────────────────────────────┐
│  Java: SonarQube / SpotBugs / PMD / Checkstyle                      │
│  Python: pylint / mypy / bandit (security)                          │
│  SAST: Semgrep / Snyk / GitHub CodeQL                               │
└──────────────────────────────────────────────────────────────────────┘
┌─ Tests ──────────────────────────────────────────────────────────────┐
│  Unit tests: must pass; coverage gate (80%+ line coverage on new code)│
│  Integration tests: run against test environment                    │
└──────────────────────────────────────────────────────────────────────┘
┌─ Dependency Scanning ────────────────────────────────────────────────┐
│  Dependabot / Snyk: block on critical CVEs                          │
└──────────────────────────────────────────────────────────────────────┘
```

**Rule**: a linter or formatter flag that reaches human review is a CI/CD configuration failure — not a review comment opportunity.

---

## Review Metrics (Measuring Review Health)

| Metric | Target | Warning signal |
|---|---|---|
| Time to first review | < 4 hours (business hours) | > 1 day: reviewers overloaded or disengaged |
| Review cycle count | 1–2 rounds | > 3 rounds: design not aligned before coding; or reviewers nit-picking |
| PR merge rate after approval | > 95% same day | Blocked on downstream; merge train issues |
| Defects found post-merge vs in-review | < 10% post-merge | Review is rubber-stamping |
| Comment resolution rate | > 90% addressed | Author ignoring feedback |

---

## FAANG Principal Engineer Patterns

### The "Author owns the merge" principle
The author is responsible for ensuring their change is ready to merge. Reviewers provide input; the author integrates, responds, and merges. Reviewers should not merge on behalf of the author (except designated release engineers).

### Pre-review design alignment
For changes > 200 lines or architectural changes: 15-minute design sync before writing code saves 2+ review cycles. "No surprise PRs" for large changes.

### Review as documentation
Review comments and their resolutions are a permanent record. Future engineers will read the git log + PR description + resolved comments to understand why the code is the way it is. Write for the future reader, not just the current author.

---

## Trade-offs

| Approach | Benefit | Cost |
|---|---|---|
| **Require 2 approvals** | Higher correctness bar; knowledge spread | Slower cycle time; bottleneck on senior reviewers |
| **Require 1 approval** | Faster cycle time | Single reviewer can be wrong; less knowledge distribution |
| **Approve-then-merge without review on small changes** | Maximum velocity | Risk of defect escape; reviewer feedback is non-actionable |
| **Synchronous pair programming instead of async review** | Immediate feedback; higher design quality | Time-expensive; timezone constraints |
| **Automated review for style/security** | No human time wasted on automatable issues | Requires upfront tooling investment |

**Recommendation**: 1 required approval + mandatory CI gates + owner approval for changed files. Balance velocity with quality. Require 2 approvals only for critical paths (payment processing, auth, data deletion).

---

## Clean Code Principles in Code Review (Robert C. Martin)

The following principles are drawn directly from *Clean Code* by Robert C. Martin. They form the qualitative checklist a reviewer applies after the mechanical checklist passes. Each principle maps to a concrete review behaviour.

---

### 1. The Boy Scout Rule — "Always leave the code cleaner than you found it"

> *"The Boy Scouts of America have a simple rule that we can apply to our profession: Leave the campground cleaner than you found it."*
> — *Clean Code*, Chapter 1

**What it means in a code review context:**

The author is not required to refactor the entire file. But every PR should leave the touched code in a better state than before. The reviewer should actively look for opportunistic improvements that are in scope without scope-creeping the PR.

**How to apply it as a reviewer:**

- If you see a method the author touched that has an obviously bad name, it is in scope to rename it in the same PR.
- If the author added a helper next to a duplicated block, suggest extracting the duplicate in the same pass.
- If the author improved one half of a method but left the other half with inconsistent indentation or dead comments, ask them to clean those up.

**How to apply it as an author:**

- Your PR description should include a "housekeeping" section if you made improvements beyond the stated scope.
- Do not clean up unrelated areas in a way that bloats the diff — apply judgment. If the cleanup is > 20% of the PR's lines, consider a separate PR prefixed `[cleanup]`.

**Red flags to call out in review:**
```
// Bad: author touched this class but left it worse
public String processUserEvent(Object x, boolean flag, int mode, String data) {
    // TODO: figure out what mode 2 does
    if (mode == 2) { ... }
}
```

```
// Better: author leaves it cleaner
public String processUserRegistration(UserRegistrationEvent event) {
    if (event.requiresEmailVerification()) { ... }
}
```

**Boy Scout Rule as a culture signal:**
At Google and Meta, engineers are expected to include small, in-scope cleanup alongside functional changes. A PR that adds 50 lines of new logic but also removes 10 lines of dead code scores higher in review than one that introduces the same logic next to legacy noise. Over time, this is how large codebases stay maintainable without dedicated refactor sprints.

---

### 2. Meaningful Names — Names Should Reveal Intent

> *"The name of a variable, function, or class should answer all the big questions. It should tell you why it exists, what it does, and how it is used."*
> — *Clean Code*, Chapter 2

**Review checklist for naming:**

- [ ] **Intention-revealing names**: `d` → `elapsedTimeInDays`, `list` → `accountList`
- [ ] **No disinformation**: `accountList` should only be used if it is actually a `List<Account>` — not a `Set` or a `Map`
- [ ] **Pronounceable names**: `genymdhms` → `generationTimestamp`; if you can't say it in a design discussion, rename it
- [ ] **Searchable names**: magic numbers should be named constants; `WORK_DAYS_PER_WEEK = 5` not `5` scattered in code
- [ ] **No encoding in names**: avoid Hungarian notation (`strName`, `iCount`) — modern IDEs handle type information
- [ ] **Class names are nouns**: `Customer`, `WikiPage`, `AddressParser` — not `Manager`, `Processor`, `Data`, `Info` (these are noise words)
- [ ] **Method names are verbs**: `postPayment()`, `deletePage()`, `save()` — accessors/mutators prefixed with `get`/`set`/`is`
- [ ] **One word per concept**: don't use `fetch`, `retrieve`, and `get` for equivalent operations in the same codebase

**Review comment examples:**
```java
// Flagged: what does this do?
public List<int[]> getThem() {
    List<int[]> list1 = new ArrayList<>();
    for (int[] x : theList)
        if (x[0] == 4)
            list1.add(x);
    return list1;
}

// After Boy Scout cleanup:
public List<Cell> getFlaggedCells() {
    List<Cell> flaggedCells = new ArrayList<>();
    for (Cell cell : gameBoard)
        if (cell.isFlagged())
            flaggedCells.add(cell);
    return flaggedCells;
}
```

---

### 3. Functions — Small, One Thing, One Level of Abstraction

> *"The first rule of functions is that they should be small. The second rule of functions is that they should be smaller than that."*
> — *Clean Code*, Chapter 3

**Review checklist for functions:**

- [ ] **Single Responsibility**: can you describe what this function does without using the word "and"? If not, split it.
- [ ] **One level of abstraction per function**: a function that calls `repository.findById()` should not also contain a raw JDBC query in the same body
- [ ] **Flag arguments (boolean parameters) are a smell**: `render(true)` — what does `true` mean? Split into `renderForSuite()` and `renderForSingleTest()`
- [ ] **No side effects**: a function named `checkPassword(username, password)` should not secretly initialise a session — that is an unexpected side effect
- [ ] **Command-query separation**: a function either *does* something (command) or *answers* something (query) — not both. `set(attribute, value)` returning a boolean to indicate success violates this.
- [ ] **DRY — Don't Repeat Yourself**: duplicated logic is a review block. Even two methods with 80% overlap should be examined for extraction.
- [ ] **Prefer fewer function arguments**: 0 is ideal, 1 is fine, 2 is acceptable, 3 needs justification, > 3 use a parameter object.

**Smell patterns to flag in review:**
```java
// Smell: boolean argument = secret dual-purpose function
public Page renderHtml(boolean isSuite) { ... }

// Better: two honest, clearly-named functions
public Page renderHtmlForSuite() { ... }
public Page renderHtmlForSingleTest() { ... }
```

```java
// Smell: function does too many things
public void processOrder(Order order) {
    validate(order);
    applyDiscount(order);
    charge(order.getPaymentMethod());
    sendConfirmationEmail(order.getUser());
    updateInventory(order.getItems());
}

// Better: orchestrator + single-responsibility steps
public void processOrder(Order order) {
    validateOrder(order);
    applyPricingRules(order);
    fulfillOrder(order);
}
```

---

### 4. Comments — Code Should Explain Itself

> *"The proper use of comments is to compensate for our failure to express ourselves in code. Comments are always failures."*
> — *Clean Code*, Chapter 4

**This does NOT mean: no comments ever.** It means every comment is a cost — it can lie (code changes, comments don't), it can duplicate intent already expressed in the code, and it clutters the signal. A reviewer should flag bad comments as actively as bad code.

**Comments to flag as blockers in review:**

| Type | Example | Why bad |
|------|---------|---------|
| **Redundant comment** | `// increment i by one` on `i++` | Adds noise; restates the code |
| **Misleading comment** | Comment says "returns null on failure" but code throws | Actively harmful; causes bugs |
| **Mandated header comment** | Auto-generated file headers with date/author | Outdated the moment it's written; use `git blame` |
| **Journal/changelog comment** | `// 2024-01-10: added null check — Z` | That's what git history is for |
| **Commented-out code** | `// old version: return x * 1.2` left in the file | Delete it; it's in version control |
| **Noise comment** | `/** Default constructor */` on a no-arg constructor | Zero information content |

**Good comments (flag their absence when needed):**

| Type | Example | Why good |
|------|---------|---------|
| **Legal comment** | `// Copyright 2024 Acme Corp. (see LICENSE)` | Required; minimal |
| **Intent explanation** | `// Sorting descending to process highest-priority events first` | Explains WHY, not WHAT |
| **Warning of consequences** | `// This regex is intentionally greedy — do not change without load testing` | Prevents future mistakes |
| **TODO** | `// TODO: replace with feature-flag once platform supports it (TICKET-1234)` | Tracks known debt; has a ticket reference |
| **Clarification of algorithm** | Explaining the modulo wrapping in a ring buffer implementation | Code can't self-document non-obvious math |

**Review comment template for bad comments:**
> `nit:` This comment restates the method name and adds no information. If the implementation is non-obvious, consider renaming the method or adding an intent-comment that explains *why* this approach was chosen rather than *what* it does.

---

### 5. Formatting — Vertical and Horizontal Discipline

> *"Code formatting is about communication, and communication is the professional developer's first order of business."*
> — *Clean Code*, Chapter 5

Formatting is largely automated (see the CI/CD gates section), but some formatting concerns survive tooling.

**Vertical formatting rules reviewers should check:**

- **The Newspaper Metaphor**: a source file should read like a newspaper — top-level concept first (public API, class purpose), details further down. Methods should flow from high abstraction at the top to implementation detail at the bottom.
- **Vertical distance**: concepts that are closely related should be vertically close to each other in the file. If `validate()` is called inside `processOrder()`, it should be defined near it — not 200 lines below.
- **Blank lines as paragraph separators**: use blank lines to separate distinct concepts inside a method, not to pad code.

**Horizontal formatting rules:**

- Lines longer than 120 characters are usually trying to do too much on one line.
- Long boolean conditions should be extracted into a well-named variable:

```java
// Hard to review, easy to misread
if (employee.isFullTime() && employee.hasWorkedFor(MINIMUM_TENURE_MONTHS) && !employee.isOnLeave()) { ... }

// Reviewer-friendly
boolean isEligibleForVesting = employee.isFullTime()
    && employee.hasWorkedFor(MINIMUM_TENURE_MONTHS)
    && !employee.isOnLeave();
if (isEligibleForVesting) { ... }
```

---

### 6. Error Handling — Don't Obscure Logic

> *"Error handling is important, but if it obscures logic, it's wrong."*
> — *Clean Code*, Chapter 7

**Review checklist for error handling:**

- [ ] **Prefer exceptions to return codes**: returning `-1` or `null` to signal failure forces callers to check; exceptions enforce handling.
- [ ] **Provide context with exceptions**: exception messages should include the operation attempted and why it failed — not just a type name.
- [ ] **Don't return null**: returning null forces callers to null-check everywhere; return an empty collection, an `Optional`, or throw.
- [ ] **Don't pass null**: passing `null` as a parameter is asking for a `NullPointerException`; use overloads or a null object pattern.
- [ ] **Don't swallow exceptions silently**: `catch (Exception e) { }` is a review block — at minimum, log with context.
- [ ] **Don't use exceptions for flow control**: `try { return parseInt(s); } catch (NumberFormatException e) { return defaultValue; }` every call — use `isNumeric()` or `Optional.ofNullable()`.

```java
// Flagged: swallowed exception hides bugs
try {
    return userRepository.findById(id);
} catch (Exception e) {
    return null;  // blocking: caller has no idea why this failed
}

// Better: context preserved, caller can decide
try {
    return userRepository.findById(id);
} catch (DataAccessException e) {
    throw new UserLookupException("Failed to retrieve user id=" + id, e);
}
```

---

### 7. Unit Tests — FIRST Principles

> *"Test code is just as important as production code."*
> — *Clean Code*, Chapter 9

**FIRST acronym — review tests against each dimension:**

| Letter | Principle | What to check in review |
|--------|-----------|------------------------|
| **F** | **Fast** | Tests should run in milliseconds; mock external dependencies | Flag: hitting a real DB, real HTTP endpoint, `Thread.sleep()` in tests |
| **I** | **Independent** | Tests should not depend on each other; order should not matter | Flag: `@TestMethodOrder`, shared mutable static state between tests |
| **R** | **Repeatable** | Tests should produce the same result in any environment | Flag: tests that fail on CI but pass locally; reliance on system clock without injection |
| **S** | **Self-Validating** | Tests should produce a boolean pass/fail result, not require manual log inspection | Flag: test that prints "expected X" without an `assert` |
| **T** | **Timely** | Tests should be written just before the production code (TDD) or alongside it — not months later | Flag: PR with 300 lines of production logic and zero test additions |

**Additional test review rules from Clean Code:**

- **One assert per concept** (not literally one line, but one logical assertion per test method — avoid tests that verify 7 unrelated things)
- **Single concept per test**: each test should test exactly one behaviour; the test name should be a sentence describing the behaviour
- **Build-Operate-Check pattern**: every test has three sections — arrange (build the scenario), act (invoke the operation), assert (verify the result)

```java
// Good test structure: clear intent
@Test
void shouldReturnEmptyOptionalWhenUserDoesNotExist() {
    // Arrange
    when(userRepository.findById(999L)).thenReturn(Optional.empty());

    // Act
    Optional<User> result = userService.findUser(999L);

    // Assert
    assertThat(result).isEmpty();
}
```

---

### 8. The Four Rules of Simple Design (Kent Beck / Clean Code Chapter 12)

> *"A design is 'simple' if it follows these rules: runs all tests, contains no duplication, expresses the intent of the programmer, minimises the number of classes and methods."*
> — In priority order

**Apply this as a holistic review lens for any PR:**

| Rule | Review question | Flag when |
|------|----------------|-----------|
| **1. Passes all tests** | Do all unit and integration tests pass? | Any failing test is a hard block |
| **2. No duplication (DRY)** | Is there any logic that appears more than once? | Extract to a shared method or class |
| **3. Expresses intent** | Can a new team member understand this without explanation? | Variable/method names obscure meaning; missing abstraction |
| **4. Fewest elements** | Are there unnecessary classes, methods, or abstractions? | Over-engineering, premature abstraction, unused code paths |

These rules are ordered. Passing tests is non-negotiable. Eliminating duplication is next. Expression of intent follows. Minimising elements comes last — don't sacrifice clarity for brevity.

---

### Clean Code Review: Quick Reference Card

```
┌──────────────────────────────────────────────────────────────────────┐
│  CLEAN CODE CODE REVIEW CHECKLIST                                    │
│  (Apply after correctness, security, and design checks pass)         │
├──────────────────────────────────────────────────────────────────────┤
│  BOY SCOUT RULE                                                       │
│  □ Does the PR leave touched code cleaner than before?               │
│  □ Are trivial improvements in scope included?                       │
├──────────────────────────────────────────────────────────────────────┤
│  NAMING                                                               │
│  □ Do names reveal intent without reading the implementation?        │
│  □ No disinformation (List named X that isn't a List)                │
│  □ Class = noun, method = verb, boolean method = is/has/can          │
├──────────────────────────────────────────────────────────────────────┤
│  FUNCTIONS                                                            │
│  □ Small and do one thing (no "and" in the description)              │
│  □ No boolean flag arguments                                         │
│  □ No side effects                                                   │
│  □ Commands do things; queries return things — not both              │
├──────────────────────────────────────────────────────────────────────┤
│  COMMENTS                                                             │
│  □ No redundant or misleading comments                               │
│  □ No commented-out code (delete it — git has history)               │
│  □ Existing intent-explaining comments still accurate after change?  │
├──────────────────────────────────────────────────────────────────────┤
│  ERROR HANDLING                                                       │
│  □ No silent exception swallowing                                    │
│  □ No null returns (use Optional / empty collection)                 │
│  □ Exception messages include context (operation + reason)           │
├──────────────────────────────────────────────────────────────────────┤
│  TESTS                                                                │
│  □ FIRST: Fast, Independent, Repeatable, Self-Validating, Timely     │
│  □ One concept per test; Arrange-Act-Assert structure                │
│  □ Test names read as behaviour descriptions                         │
├──────────────────────────────────────────────────────────────────────┤
│  SIMPLE DESIGN (Kent Beck)                                           │
│  □ All tests pass                                                    │
│  □ No duplication                                                    │
│  □ Expresses intent clearly                                          │
│  □ Minimum necessary classes and methods                             │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Best Practices Summary

1. **Automate everything automatable** — linters, formatters, security scanners before human review
2. **Keep PRs small and focused** — one logical change per PR; database migrations in separate PRs
3. **Write PR descriptions that explain why** — not just what the code does
4. **Use prefixed comments** (nit/suggestion/blocking/question) to signal severity clearly
5. **Respond within one business day** — review delays are team velocity blockers
6. **Be specific in comments** — quote the line, explain the issue, offer a direction
7. **Distinguish opinion from correctness** — "I prefer X" is not blocking; "this will fail under Y" is
8. **Normalise praise** — explicitly acknowledge good design decisions
9. **Surface disagreements quickly** — one async exchange, then sync if still unresolved
10. **Treat patterns of comments as signals for standards** — if you write it 3 times, make it a rule

---

## FAANG Interview Points

**"How do you scale code review quality as a team grows from 5 to 50 engineers?"**: Three levers. First: automate everything automatable — style, formatting, and basic security scanning should never consume senior engineer time. Second: establish and write down team standards — a shared understanding of what "good" looks like eliminates 70% of review debates. Third: invest in reviewer capability — principal engineers mentor reviewers through comments, not just merges. As the team grows, the goal is that any two engineers reviewing the same diff reach the same conclusion, without needing a principal engineer to arbitrate.

**"How do you handle a situation where a reviewer and author are at a standstill disagreement?"**: Three-step escalation. One exchange async — author and reviewer each state their position with evidence. If unresolved: 10-minute sync call, because async debate is inefficient and emotionally costly. If still unresolved: the principal engineer or tech lead makes a decision with reasoning, and both parties commit. The decision and reasoning are documented in the PR or an ADR. The team agrees to revisit the decision at the next retrospective if either party still disagrees. The goal is always "disagree and commit" — not consensus at the cost of velocity.

**"What metrics do you use to evaluate code review health?"**: Four: time to first review (measures reviewer availability and prioritisation), review cycle count (measures design alignment before coding), post-merge defect rate attributed to reviewed changes (measures review effectiveness), and PR size distribution (measures author discipline). The most actionable single metric is review cycle count — more than 2 rounds consistently signals either a misalignment in design expectations before coding starts, or a reviewer who is catching things late that should have been discussed earlier.
