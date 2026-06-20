# Architecture Review Process

## Why This Matters at Principal Engineer Level

Architecture decisions are the highest-leverage decisions in engineering. A wrong implementation can be fixed in a PR. A wrong architecture compounds for years. The architecture review process is the mechanism by which organizations catch wrong decisions before they're committed in code, build shared understanding, and create a durable record of *why* systems are designed the way they are.

At principal engineer level, you are expected to run this process — design the review framework, facilitate reviews for the highest-stakes decisions, and build the organizational habit of reviewing architecture before building.

---

## The Architecture Decision Spectrum

Not every technical decision needs a formal review. The right governance level scales with reversibility and blast radius.

```
                      Reversibility
                LOW ◄──────────────────────► HIGH
    HIGH │  Full RFC + cross-team │  Design Doc + team review
         │  review + exec sign-off│  (can revisit if wrong)
B        │  (Examples: database   │  (Examples: new service,
l        │  engine choice, public │  API design, caching layer)
a        │  API design, infra     │─────────────────────────────
s        │  migration)            │  PR + 1 reviewer
t        │────────────────────────│  (Examples: new endpoint,
         │  Architecture Spike    │  new library, DB index)
R        │  (explore; decide      │
a        │  later)                │  No review needed
d  LOW   │                        │  (Implementation details)
i        │                        │
u        │                        │
s        └────────────────────────┴─────────────────────────────
```

| Decision Type | Review Required | Format | Timeline |
|--------------|----------------|--------|----------|
| Implementation detail | None | PR comment | N/A |
| Technical approach (1 team) | Lightweight design doc | 1-page doc + team discussion | 1-3 days |
| New service or significant component | Design doc | Full design doc + team review | 1 week |
| Cross-team impact | RFC | RFC + stakeholder review | 2-4 weeks |
| Platform-level or irreversible | Full RFC + ADR | RFC + CAB review + ADR | 4-8 weeks |
| Public API or company-level | Executive-sponsored RFC | RFC + leadership sign-off | 6-12 weeks |

---

## Design Doc Process (Team-Level)

Use a design doc when the decision affects one team but is significant enough to warrant discussion before implementation.

### When to Write a Design Doc

```
Write a design doc when:
□ The implementation will take > 1 week
□ There are meaningful alternatives to evaluate
□ Other engineers on the team will need to understand this to maintain it
□ You are unsure about the right approach
□ You want early feedback before committing implementation time

Don't write a design doc for:
□ Bug fixes
□ Straightforward feature implementations following established patterns
□ Changes < 1 day of work
□ Refactors with no behavior change
```

### Design Doc Template

```markdown
# [Title: What Are You Building?]

**Author(s)**: @name
**Status**: Draft | In Review | Approved | Implemented | Abandoned
**Created**: YYYY-MM-DD
**Last Updated**: YYYY-MM-DD
**Reviewers**: @name1, @name2
**Approvers**: @tech-lead

---

## Problem Statement

[1-3 paragraphs. What problem are we solving? Why does it need to be solved now?
What is the cost of NOT solving it? What is the scope?]

## Requirements

### Functional Requirements
- [What the system must do. Numbered list. Each item is verifiable.]
- FR-1: The system must process X within Y ms at Z QPS
- FR-2: The system must support A, B, C operations

### Non-Functional Requirements
- [Quality attributes. Numbered list.]
- NFR-1: P99 latency < 200ms at 10,000 QPS
- NFR-2: 99.9% availability over 30 days
- NFR-3: Zero data loss (RPO = 0) for write operations

### Out of Scope
- [Explicitly state what this design does NOT cover. Prevents scope creep.]

---

## Proposed Solution

[Core description of the approach. Include:]
- Architecture diagram (ASCII or embedded image)
- Key components and their responsibilities
- Data flow for the primary use case
- Data model (key tables/structures, not complete schema)
- API contracts (key endpoints, not complete spec)

### Component Diagram
\`\`\`
[ASCII or Mermaid diagram]
\`\`\`

### Data Flow
1. Client sends request to X
2. X validates and forwards to Y
3. Y reads from Z and...

---

## Alternatives Considered

### Alternative A: [Name]
**Description**: [Brief]
**Why Not**: [Specific reasons this was rejected]

### Alternative B: [Name]
**Description**: [Brief]  
**Why Not**: [Specific reasons this was rejected]

---

## Trade-offs and Risks

| Trade-off | Accepted Cost | Justification |
|-----------|-------------|---------------|
| [What you're giving up] | [How much] | [Why it's worth it] |

### Risks
- **Risk 1**: [Description] — Mitigation: [How you'd handle it]
- **Risk 2**: [Description] — Mitigation: [How you'd handle it]

---

## Implementation Plan

Phase 1 (Week 1-2): [What gets built; acceptance criteria]
Phase 2 (Week 3-4): [What gets built; acceptance criteria]
Phase 3 (Week 5):   [What gets built; acceptance criteria]

### Open Questions
- [ ] [Question that needs resolution before or during implementation]

---

## Success Metrics

How will we know this worked?
- [Metric 1]: [Target value] (measured by [how])
- [Metric 2]: [Target value]

---

## References
- [Relevant prior art, related docs, external references]
```

### Design Doc Review Process

```
Day 0: Author shares doc in draft; requests specific reviewers
Day 1-3: Reviewers leave comments (async)
Day 3: Author addresses comments, marks resolved/unresolved
Day 4: Synchronous meeting only if unresolved disagreements remain (optional)
Day 5: Approver signs off (or requests changes)

Review comment norms:
  Use a prefix system:
    NIT: (nit) - Minor, author's discretion
    Q: (question) - Clarifying question, no change needed if answered
    SUG: (suggestion) - Optional improvement
    REQ: (required) - Must be addressed before approval
    BLK: (blocker) - Fundamental issue; design must change
```

---

## RFC Process (Cross-Team)

Use an RFC when the change affects multiple teams, is hard to reverse, or sets a platform-level direction.

### RFC vs. Design Doc

| Dimension | Design Doc | RFC |
|-----------|-----------|-----|
| Scope | 1 team | 2+ teams or platform-wide |
| Reversibility | Moderate | Low |
| Audience | Team peers | All engineers; leadership |
| Review period | 3-5 days | 2-4 weeks |
| Consensus required | Team lead | Stakeholders + tech lead group |
| Historical record | Team wiki | Permanent engineering record |

### RFC Template

```markdown
# RFC-[NUMBER]: [Title]

**Author(s)**: @name
**Status**: Draft | Comment Period | Accepted | Implemented | Withdrawn | Superseded
**Created**: YYYY-MM-DD
**Comment Period Ends**: YYYY-MM-DD (minimum 2 weeks for cross-team RFCs)
**Implemented**: YYYY-MM-DD

---

## Summary

[1 paragraph. A concise description of what is being proposed and why.
Write this as if the reader has 30 seconds.]

## Motivation

### Problem
[What specific problem is this solving? Include metrics showing the problem exists.]
[Example: "Our checkout service calls 7 downstream services synchronously. At current QPS,
a 200ms slowdown in any one of them causes checkout P99 to exceed our 2s SLO.
Over the past 90 days, this has caused 3 SLO breaches and burned 40% of our error budget."]

### Why Now
[Why address this now vs. later? What gets worse if we wait?]

### Goals
- [Specific, measurable outcome 1]
- [Specific, measurable outcome 2]

### Non-Goals
- [Explicitly out of scope]
- [What this RFC intentionally does NOT address]

---

## Detailed Design

[The core section. Include:]

### Architecture
[Diagram + prose. How does the new system work? What are the key components?]

### Key Design Decisions
[Each major decision with rationale. This is where reviewers focus.]

**Decision 1: [Name]**
- Options considered: A, B, C
- Chosen: A
- Rationale: [Why]
- Trade-off accepted: [What you give up]

### API Design
[If applicable: key interfaces, contracts, endpoints]

### Data Model
[If applicable: key data structures, storage layer decisions]

### Migration Strategy
[How do we get from current state to desired state?
What is the rollout plan? How do we validate each phase?]

### Failure Modes
[What happens when this fails? How does the system degrade?]

---

## Alternatives Considered

### Alternative 1: [Name]
**Full description**: [Enough detail to evaluate]
**Why not chosen**: [Specific, non-dismissive reasons]

### Alternative 2: [Name]
**Full description**:
**Why not chosen**:

### Status Quo (Do Nothing)
**Why not chosen**: [Always evaluate doing nothing — it has real costs]

---

## Trade-offs

### What We Gain
- [Concrete benefit 1 with expected magnitude]

### What We Give Up / Accept
- [Concrete cost 1 with expected magnitude]

### Open Questions
- [ ] [Question not yet resolved; note who owns answering it and by when]

---

## Impact Assessment

**Teams impacted**: [List each team and describe impact]
**Migration effort**: [Per-team estimate]
**Dependencies**: [What must happen before this can be implemented?]
**Breaking changes**: [Yes/No; describe if yes]
**Rollback**: [How to reverse if this doesn't work]

---

## Implementation Plan

### Phase 1: [Name] (Weeks 1-N)
- [Work item 1]
- [Work item 2]
- Success criteria: [How we know this phase is done]

### Phase 2: [Name] (Weeks N+1 to M)
...

### Rollout Plan
[Traffic shifting, feature flags, gradual migration steps]

---

## Success Metrics

| Metric | Current | Target | Measurement |
|--------|---------|--------|-------------|
| [SLO metric] | [X] | [Y] | [Dashboard link] |
| [Velocity metric] | [A] | [B] | [How measured] |

---

## Feedback Requested

[Guide reviewers: what are the hard questions? Where are you most uncertain?]

1. Does the migration strategy account for X?
2. Are there performance implications of Y that I haven't considered?
3. Is the proposed API backward-compatible with existing consumers?
```

### RFC Review Protocol

```
Comment Period (minimum 2 weeks for cross-team RFC):

  Week 1: Async comment period
    - Author sends RFC to: relevant team leads, SRE/Platform, Security (if applicable)
    - All stakeholders comment on the RFC doc (not a meeting)
    - Author responds to comments; clarifies; updates doc

  Week 2: Resolution period
    - Author addresses all REQ/BLK comments
    - Unresolved issues: escalate to tech lead group for decision
    - Final RFC updated to reflect discussions

  If controversial: RFC Review Meeting (60 min max)
    - Present: author + 5 min overview
    - Discuss: unresolved issues only (not re-reading the doc)
    - Decide: each unresolved question → explicit decision + rationale recorded

  Acceptance:
    - RFC author marks status: Accepted
    - Record: approvers, date, key decisions made during review
    - Archive: permanent link in engineering wiki
```

---

## ADR Process (Architecture Decision Record)

An ADR documents a specific architecture decision after it's been made — not before. It is the permanent record of why a decision was made, so that future engineers understand the context and don't inadvertently reverse it.

### When to Write an ADR

```
Write an ADR after:
□ Any decision that came from an RFC or design doc
□ Any decision that future engineers might question and want to reverse
□ Any decision that has meaningful alternatives that were rejected
□ Any decision driven by a specific constraint that may not be obvious from the code

Don't write an ADR for:
□ Implementation details (which library to use for logging is not an ADR)
□ Decisions that are obvious from the code
□ Decisions with zero meaningful alternatives
```

### ADR Template

```markdown
# ADR-[NUMBER]: [Short descriptive title]

**Date**: YYYY-MM-DD
**Status**: Proposed | Accepted | Deprecated | Superseded by ADR-NNN
**Deciders**: @name1, @name2
**Consulted**: @name3, @name4

---

## Context

[The situation that led to this decision. Include:]
- What problem were we solving?
- What constraints existed (technical, organizational, time)?
- What was the state of the system at the time?

[Write for a reader who will encounter this in 3 years. Assume they know the current system
but don't know what the system looked like at the time of this decision.]

## Decision

[What was decided. A single clear statement.]
"We will use [X] for [purpose] because [primary reason]."

## Consequences

### Positive
- [What gets better as a result]

### Negative / Accepted Trade-offs
- [What gets worse or what we give up]
- [These are important: they help future engineers understand what to watch out for]

### Risks
- [What might go wrong; what are the known limitations]

## Alternatives Considered

### [Alternative 1]
[Description and why not chosen]

### [Alternative 2]
[Description and why not chosen]

## Implementation Notes

[Any important notes about how this decision was implemented, if not obvious]

## Review Triggers

[Under what conditions should this decision be revisited?]
- "If [X] happens, this decision should be re-evaluated"
- "This decision should be reviewed in [time period] as [technology/context] matures"
```

### ADR Numbering and Storage

```
Storage: /Architecture/decisions/
Naming:  ADR-0001-use-postgres-for-user-data.md
         ADR-0002-adopt-event-sourcing-for-orders.md
         ADR-0003-deprecated-kafka-for-internal-rpc.md

Index:   /Architecture/decisions/README.md (links to all ADRs with 1-line summary)
Tooling: adr-tools (CLI for creating and managing ADRs)
         Architectural Decision Records VS Code extension
```

---

## Architecture Review Anti-Patterns

| Anti-Pattern | Impact | Fix |
|-------------|--------|-----|
| **Design by committee** | RFC comment period becomes bikeshedding; decision delayed indefinitely | Time-box; explicit decision-maker; comments ≠ veto rights |
| **RFC theater** | RFC written after decision already made; comments are performative | RFC must be written before implementation begins |
| **Missing alternatives** | Reviewers can't evaluate without knowing what was rejected | Always document at least 2 alternatives, including "do nothing" |
| **Tribal knowledge, no ADRs** | Future engineers reverse decisions without understanding the context | ADR for every significant decision; index must be findable |
| **Architecture by accident** | No reviews → architecture emerges from individual PRs | Review gate: any PR touching architectural components requires design doc |
| **Over-RFC-ing** | Every decision requires 4-week RFC; velocity collapses | Right-size: RFC only for cross-team or hard-to-reverse decisions |
| **Design doc written after implementation** | Just documentation; no longer a decision-making tool | Review before implementation — it's called a DESIGN doc, not an IMPLEMENTATION doc |

---

## FAANG Interview Framing

### "How do you get alignment on a major architectural change across 20 teams?"

> "I use the RFC process for major architectural decisions. The RFC is not a meeting — it's a written proposal that stakeholders can engage with asynchronously at their own pace. I write the RFC with a 2-week comment period, specifically identifying the teams who must agree and the teams who should be informed. The key is being explicit about what is a comment versus a veto: every team can comment; only teams whose systems are directly impacted have blocking power. I address all blocking concerns in writing, updating the RFC to reflect each resolution. For genuinely controversial decisions where async resolution isn't working, I schedule a 60-minute meeting focused only on unresolved issues — not re-explaining the proposal. After acceptance, I write an ADR so that the decision is permanently recorded. Two years later, when someone asks 'why did we design it this way?', the answer is findable. That institutional memory is as valuable as the decision itself."

### "How do you decide when to use a design doc vs. an RFC?"

> "The decision rests on two factors: blast radius and reversibility. A design doc is right when the decision is contained within one team and has a reasonable reversal path. An RFC is right when the change crosses team boundaries, sets platform-level direction, or would be difficult and expensive to undo. In practice, I also look at whether the technical decision creates a dependency that other teams will need to design around — if other teams need to know this decision to make their own decisions, an RFC ensures they're in the loop before we commit. The failure mode I avoid is writing an RFC for every decision, which creates a slow bureaucratic process that people route around. Right-sizing the process to the decision is itself an architectural skill."
