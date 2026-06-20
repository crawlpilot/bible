# Stakeholder Alignment

## Why Alignment is a Principal Engineer Skill

At the senior engineer level, you align your team. At the principal level, you align *organizations*. You work across team boundaries where you have no authority — and where getting the wrong person onside at the wrong time can kill a multi-quarter initiative.

Alignment is not consensus. It is not getting everyone to agree. It is ensuring the right people have the right information, have been heard, and will not block forward progress.

---

## Stakeholder Mapping

Before any major initiative, map your stakeholders. Two dimensions matter:

```
                    HIGH INFLUENCE
                         │
         MANAGE CLOSELY  │  KEEP SATISFIED
         (Core partners) │  (Exec sponsors)
                         │
LOW INTEREST ────────────┼──────────────── HIGH INTEREST
                         │
         MONITOR         │  KEEP INFORMED
         (Peripheral)    │  (Affected teams)
                         │
                    LOW INFLUENCE
```

| Quadrant | Strategy | Cadence |
|----------|----------|---------|
| High influence + high interest | Manage closely; involve in decisions | Weekly sync |
| High influence + low interest | Satisfy their key concerns; don't over-communicate | Monthly update |
| Low influence + high interest | Keep informed; they're advocates | Async updates |
| Low influence + low interest | Monitor; don't invest time | Quarterly newsletter |

### Stakeholder Register Template

```
| Stakeholder | Role | Interest | Influence | Stance | Engagement Strategy |
|-------------|------|----------|-----------|--------|---------------------|
| [Name] | VP Eng | High | High | Supportive | Weekly 1:1, include in decisions |
| [Name] | Dir. Infra | Med | High | Neutral | Monthly briefing, ADR reviews |
| [Name] | PM Payments | High | Med | Skeptical | Bi-weekly sync, address concerns directly |
| [Name] | Legal | Low | High | Unknown | Engage at key milestones |
```

**Stances to watch:**
- **Supportive**: leverage as advocate; don't take for granted
- **Neutral**: convert with data; they'll go wherever the wind blows
- **Skeptical**: engage early and directly; understand their concern; don't avoid
- **Opposed**: escalate if they're high-influence and won't move; document attempts

---

## The Pre-Wiring Principle

**Rule:** No decision should be made at a meeting that hasn't been discussed before the meeting.

Pre-wiring is the practice of conducting 1:1 conversations with key decision-makers and influencers before the formal decision meeting. Goals:
1. Understand each person's perspective and concerns
2. Address objections privately (less defensiveness than in group)
3. Build individual buy-in that transfers to the group setting
4. Identify genuine blockers that would derail the meeting

### Pre-Wiring Sequence

```
T-5 days: Share proposal async (doc, design, ADR)
           Request async feedback by T-3

T-3 days: 1:1 with known skeptics or high-influence stakeholders
           Goal: understand concerns, not persuade

T-2 days: Adjust proposal based on valid concerns
           Explicitly note changes made (shows you listened)

T-1 day:  Confirm decision owners will attend
           Verify no remaining blockers

Day of:   Present — the meeting is confirmation, not deliberation
           If a new objection appears, offer to follow up rather than derail
```

---

## RACI for Decision-Making

RACI defines who does what for each decision. Without explicit RACI, decisions either stall (no clear owner) or are revisited (unclear who had authority).

| Role | Meaning | Count | Rule |
|------|---------|-------|------|
| **R** — Responsible | Does the work / makes the recommendation | 1-2 | Clear owner; too many means no owner |
| **A** — Accountable | Final decision authority; signs off | 1 only | Must be one person; if 2, escalate to identify true owner |
| **C** — Consulted | Input required before decision | ≤ 5 | More than 5 slows decisions to a crawl |
| **I** — Informed | Notified after decision | Unlimited | Async only; no meeting needed |

### RACI Anti-Patterns

| Anti-Pattern | Symptom | Fix |
|---|---|---|
| Too many R's | Nobody is making progress; everyone is waiting for everyone | Designate a single DRI |
| Multiple A's | Decision gets re-opened after it was made | One VP/Director must be the final word |
| C's ignored | Decisions made without consulting key stakeholders | Enforce C consultation as a gate before decision is made |
| I's invited to meetings | Status meetings become huge; no one is cut | Move I-stakeholders to async updates only |

---

## Handling Misalignment and Conflict

### Level 1: Disagreement on facts
**Root cause:** Different data, different interpretations  
**Fix:** Align on a single source of truth. Commission a joint analysis. Don't resolve with opinions.

### Level 2: Disagreement on approach
**Root cause:** Different mental models, expertise, risk tolerance  
**Fix:** Write an ADR (Architecture Decision Record). Force explicit trade-off comparison. Make the default clear. Let the opposing team make the case for their alternative in writing.

### Level 3: Disagreement on priorities
**Root cause:** Different team goals or OKRs  
**Fix:** Escalate to the shared manager with both teams' perspectives documented. Ask them to resolve at the org level. Don't try to win a priority argument in a peer meeting.

### Level 4: Political opposition
**Root cause:** Territorial, career-driven, or relationship-driven resistance  
**Fix:** Understand the underlying concern (job security? credit? control?). Address the real concern, not the stated one. If that fails, escalate with documentation of attempts.

---

## Decision Log

Maintain a decision log for every major initiative. Decisions that aren't documented get relitigated.

```markdown
# Decision Log — [Project Name]

## DEC-001: [Decision title]
**Date:** YYYY-MM-DD
**Decider:** [Name, role]
**Status:** Decided | Superseded by DEC-XXX

**Context:**
[1-2 sentences on why this decision was needed]

**Options considered:**
1. [Option A] — [key trade-off]
2. [Option B] — [key trade-off]

**Decision:**
[Option chosen] — [one-sentence rationale]

**Consequences:**
- [What becomes easier]
- [What becomes harder or is accepted as a constraint]

**Who was consulted:** [names]
**Who was informed:** [teams]
```

---

## Influence Without Authority: Techniques

### 1. Data-driven framing
Lead with numbers, not opinions. "Our checkout latency is 2x industry benchmark" lands differently than "our checkout is slow."

### 2. Aligned incentives
Find the overlap between your ask and their OKR. Don't ask teams to do work that doesn't serve their goals; find the framing where it serves both.

### 3. Narrate the cost of inaction
Teams often resist change because the current state is familiar. Make the cost of staying still concrete: "Every quarter we don't fix this, onboarding a new engineer takes 3 days instead of 3 hours."

### 4. Give credit publicly
Publicly credit the teams you depend on. People build things for people who appreciate them.

### 5. Offer reciprocity
"If you help us with X, we'll contribute back to your migration with Y." Creates cooperative norms.

### 6. Build relationships before you need them
Alignment is slow to build and fast to burn. Invest in peer relationships during normal times, not only when you need something.

### 7. Write it down
A well-written design doc or ADR is a tool of influence. It makes your thinking concrete, reviewable, and harder to dismiss than a verbal proposal.

---

## Stakeholder Communication Anti-Patterns

| Anti-Pattern | Why It Fails |
|---|---|
| Communicating only when things go wrong | Stakeholders distrust you; assume things are worse than they are |
| Over-communicating details to busy execs | They disengage; your signal gets lost in noise |
| Asking for alignment in a large group meeting | Groupthink; people won't voice objections publicly |
| Not acknowledging valid concerns | People disengage or work around you |
| Conflating "informed" with "aligned" | Informing doesn't create ownership or commitment |
| Bringing surprises to the steering committee | Destroys trust; execs need to be pre-wired |

---

## FAANG Interview Application

**When you'll be asked about this:**
- "Tell me about a time you drove alignment across multiple teams with competing priorities"
- "How do you get buy-in from teams that you don't manage?"
- "Describe a time you had to influence a decision at the executive level"

**What they're evaluating:**
- Organizational awareness: do you understand the power and interest dynamics?
- Influence mechanics: do you use data, alignment, and relationships — not title?
- Proactive communication: do you surface conflict early, or let it fester?

**Principal-level signal:**
Senior engineers resolve disagreements within their team. Principal engineers architect alignment across teams and functions, turning organizational resistance into cooperation through systematic engagement, not political maneuvering.
