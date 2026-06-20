# RFCs — Architecture Proposals and Rollout Plans

RFCs capture proposed changes that need cross-team alignment before implementation. At principal level, the value is not the document itself; it is the forcing function for clarifying the problem, the design space, and the rollout plan before the team commits.

## Contents

| File | Topic |
|------|-------|
| [rfc-template.md](rfc-template.md) | Reusable RFC structure for new proposals |
| [rfc-001-observability-standardization.md](rfc-001-observability-standardization.md) | Example RFC for standardizing telemetry collection and rollout |

## When to Write an RFC

- A change affects multiple services or teams
- The rollout has operational risk
- There are meaningful alternatives worth comparing
- The decision needs visible buy-in from reviewers and stakeholders
- The implementation will take more than one sprint or requires phased adoption

## RFC Bar

- Problem statement is concrete and measurable
- Motivation explains why the status quo is insufficient
- Design section is detailed enough to review implementation risk
- Trade-offs are explicit, not implied
- Rollout includes validation, fallback, and success metrics
