# Role: Software Engineer (L3 / L4 — Junior to Mid-Level)

## Core Identity

The Software Engineer (L3 / L4, also called Junior or Mid-level Engineer) is responsible for **implementing well-defined tasks with increasing independence**. They are the foundation of engineering teams — writing most of the code that ships, building product features, fixing bugs, writing tests, and growing rapidly toward senior level.

Understanding this role deeply is critical for principal engineers: you will hire, mentor, unblock, and set the technical bar for engineers at this level.

---

## Level Breakdown

### L3 — Junior Software Engineer (0–3 years)
- Works on clearly scoped tickets with defined acceptance criteria
- Requires guidance on design, architecture, and non-obvious edge cases
- Pairs frequently with seniors and TL
- Primarily contributes at the implementation level
- Goal: Build foundations; ship features that work and are testable

### L4 — Mid-Level Software Engineer (3–6 years)
- Owns a component or feature end-to-end with light supervision
- Can write a basic design doc; needs review and feedback before finalizing
- Contributes meaningfully to code review
- Begins mentoring L3 engineers informally
- Goal: Reliable, autonomous delivery within well-scoped domain

---

## Primary Accountabilities

### L3 Accountabilities
1. Implement assigned tickets with quality: code works, tests written, PR ready for review
2. Ask good questions before getting stuck for too long (< 2 hours unblocked before asking)
3. Write readable, understandable code — others will maintain it
4. Run existing test suites; add unit tests for new code
5. Participate in code review: comment, ask questions, learn from feedback
6. Follow team conventions: naming, structure, PR templates, commit messages

### L4 Accountabilities
1. Own a feature from ticket → design → implementation → tests → review → deploy
2. Write clear design docs for features within their scope
3. Estimate work accurately at the feature level (days to 1-2 weeks)
4. Mentor L3 engineers: answer questions, review code, pair program
5. Identify and flag technical risks in assigned work
6. Participate in on-call rotation; resolve pages for familiar systems
7. Contribute to code review at team level, not just own PRs

---

## Growth Trajectory: L3 → L4 → L5

### From L3 to L4
| Signal | What It Looks Like |
|--------|------------------|
| Scope growth | Completes full features, not just subtasks |
| Independence | Doesn't need daily check-in; flags blockers proactively |
| Code quality | Feedback count per PR declining; catching own bugs |
| Design | Can break a feature into tasks; identifies edge cases |
| Collaboration | Reviews others' code with useful comments |

### From L4 to L5 (Senior)
| Signal | What It Looks Like |
|--------|------------------|
| Scope growth | Owns a service, not just a feature |
| Ambiguity | Resolves unclear requirements independently |
| Design | Leads the design doc for their domain |
| Cross-team | Navigates integrations with other teams without hand-holding |
| Multiplier | Others move faster because of them |

**Average FAANG timeline**:
- L3 → L4: 1.5–2.5 years
- L4 → L5: 2–4 years
- L5 → L6 (Staff): 3–6 years (fewer make this jump)

---

## Day-in-the-Life

### L3 Engineer (Sprint Week)
```
Monday:
  09:00  Sprint standup — share what you worked on, what's next, any blockers
  09:15  Pick up top ticket from sprint board
  09:30  Read existing code for context; ask TL if confused
  10:00  Start implementation; write tests first (TDD) if the team uses it
  13:00  PR open with draft label; request async feedback
  14:00  Code review — review 1-2 peers' PRs
  15:00  Address review comments; iterate

Friday:
  Retrospective contribution
  Sprint demo (if assigned feature is complete)
  Update ticket statuses, write any follow-up tickets
```

### L4 Engineer (Sprint Week)
```
Monday:
  Sprint planning contribution — estimate stories, flag dependencies
  Take ownership of a feature (multiple tickets)
  
Mid-sprint:
  Unblock L3 engineers on questions
  Write design doc for next sprint's feature
  Monitor own service health; address technical debt opportunistically
  
End of sprint:
  Demo complete feature
  Write follow-up tickets for known tech debt
  Review sprint metrics: velocity, bugs introduced, code coverage
```

---

## Technical Skills Progression

### Code Craft
| Skill | L3 | L4 |
|-------|----|----|
| Reads existing code | Yes, with help | Yes, independently |
| Writes readable code | Sometimes | Consistently |
| Refactors safely | Rarely | Yes, with test coverage |
| Identifies code smells | Rarely | Often |
| Writes idiomatic code | Not yet | Mostly |

### Testing
| Test Type | L3 | L4 |
|-----------|----|----|
| Unit tests | Writes basic ones | Writes thorough ones |
| Integration tests | Follows existing patterns | Creates new patterns |
| Test design | Needs guidance | Independent |
| TDD | Learning | Practiced |
| Contract tests | Not yet | Beginning |

### System Thinking
| Skill | L3 | L4 |
|-------|----|----|
| Understands own service | Yes | Yes |
| Understands upstream dependencies | Partially | Yes |
| Thinks about failure modes | Rarely | Sometimes |
| Estimates system impact | No | Partially |
| Considers DB schema impact | Rarely | Usually |

---

## Common L3/L4 Mistakes (That Principal Engineers Help Avoid)

| Mistake | Pattern | Coaching |
|---------|---------|---------|
| **Premature optimization** | Micro-optimizes before knowing the hot path | "Measure first. Profiler > intuition." |
| **Missing error handling** | Happy path only; exception swallowed | "What happens when the DB is down at line 42?" |
| **No tests** | "It works locally" | "How will you know it still works in 6 months?" |
| **Over-abstraction** | Builds framework for one use case | "YAGNI — you aren't gonna need it" |
| **Too many concerns per class** | God class, 2000 lines | "Single Responsibility Principle — what does this class do?" |
| **Committing too large** | 1000-line PR | "Smaller PRs get better reviews and merge faster" |
| **Not flagging blockers** | Stuck for 2 days silently | "Your job is to produce signal, not just output" |
| **Ignoring review feedback** | Marks conversations as resolved without addressing | "LGTM doesn't mean agree with everything; it means satisfied" |

---

## Engineer ↔ Tech Lead / Principal Engineer Interface

### What Engineers Need from the Principal
1. **Clear technical standards**: Not ambiguous "write good code" — specific, written, enforced
2. **Technical unblocking**: When they hit a wall on a hard design question
3. **Design feedback before implementation**: Review design doc before they write 3 weeks of code
4. **Context**: Why does this architecture decision matter? What's the bigger picture?
5. **Sponsorship**: Principal should name engineers by name in cross-team meetings when their work was key

### What Engineers Should Provide to the Principal
1. **Ground truth**: "The platform abstraction doesn't work for our use case because X"
2. **Early warning**: "I think this will be hard to test because of Y"
3. **Feedback on tooling**: Engineers are the daily users of the platform the Principal helped design

---

## Hiring Bar at L3/L4 (Principal Engineers Often Interview Candidates)

### What to Assess at L3
- **Coding fundamentals**: Can write a correct solution to a medium-difficulty DSA problem
- **Code quality**: Clean, readable, testable — not just "it works"
- **Communication**: Thinks out loud, asks clarifying questions, handles feedback gracefully
- **Learning velocity**: How fast do they pick up hints? Do they recognize feedback?
- **Curiosity**: Do they ask why, or just implement?

### What to Assess at L4
All of L3, plus:
- **System awareness**: Can they reason about their code in a larger system context?
- **Design thinking**: Given a vague requirement, can they break it down into a design?
- **Trade-off awareness**: Do they know there are alternatives, or do they only see one solution?
- **Ownership language**: Do they say "I shipped X and then Y broke" or "the deploy broke"?

### Red Flags at Any Level
- Never asked a clarifying question in the interview
- Can't explain why they chose their approach
- Gets defensive when interviewer suggests a correction
- Optimizes prematurely before getting to a working solution
- Can't articulate the time/space complexity of their solution

---

## FAANG L3/L4 Specifics

### Amazon
- L3 = SDE1, L4 = SDE2
- Behavioral bar is explicitly assessed at L3: Leadership Principles in behavioral interviews
- L4 is often expected to take on operational ownership of a service
- Writing is valued: L4 expected to write clear tickets and doc updates

### Google
- L3 = SWE III, L4 = SWE IV (note: Google's numbering starts at L3)
- Strong emphasis on CS fundamentals in coding interviews at all levels
- L4 expected to write design docs for projects they lead
- Peerness culture: L3 and L4 expected to contribute to discussions, not just execute

### Meta
- E3 = L3, E4 = L4
- Bootcamp (E3/E4 join a 6-week bootcamp and choose their team)
- "Move fast" culture: L4 expected to ship in first month
- Hackathons and internal open source contributions valued

### Netflix
- No formal L3/L4 distinction — Netflix hires primarily senior engineers
- Junior engineers exist but are rare; Netflix bets on "extraordinary people"
- High salary, high bar, low headcount model

---

## Interview Angles for Principal Engineers

**"How do you onboard a new L3 engineer to maximize their ramp time?"**
- Week 1: Environment setup, codebase tour, first tiny PR (documentation fix or test)
- Week 2: Pair-program on a small bug fix; they drive, I navigate
- Week 3-4: Own a small, well-scoped ticket end-to-end
- Week 5-8: First real feature with design doc reviewed before implementation
- Key: Set explicit 30/60/90-day goals with the engineer and EM jointly

**"How do you raise the technical bar for a team with many L3/L4 engineers?"**
- Define the bar explicitly in writing — review standards, testing requirements, observability checklist
- Don't just enforce, teach: run lunch-and-learns, post annotated examples, pair-program
- Design the system so the pit of success is easy to reach (golden templates, linters, CI gates)
- Recognize and amplify examples of excellent L3/L4 work — make quality visible

**"When do you escalate a performance issue for an L3 engineer?"**
- I give specific, documented feedback at least twice before escalating
- I define what "meeting expectations" looks like explicitly, not ambiguously
- I work with the EM jointly — this is their domain; I'm an input, not the decision-maker
- I check: is this a skill gap (coachable) or a will gap (different conversation)?
