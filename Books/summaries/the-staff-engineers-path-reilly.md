# The Staff Engineer's Path: A Guide for Individual Contributors Navigating Growth and Change
**Author**: Tanya Reilly  
**Edition**: O'Reilly Media, 2022  
**Category**: Technical Leadership · Staff/Principal Engineering · Influence Without Authority · Technical Strategy

> "Being a staff engineer means solving the hard problems your team can't — not because they aren't smart enough, but because nobody has the time, the context, or the mandate to work on them."

---

## Why This Book Matters for FAANG PE Interviews

This is the most directly applicable book to the Staff/Principal Engineer role that exists. Most engineering books are either deep technical references or people-management guides. Reilly occupies the exact middle ground: the experienced IC who has moved from "writes excellent code" to "shapes the technical direction of an organisation."

FAANG interviewers evaluating at the principal level are looking for three things above all else: **big-picture thinking**, **execution on ambiguous hard problems**, and **scaled influence without authority**. Reilly structures her entire book around exactly these three pillars.

**Direct interview mapping**:
- "How do you decide what to work on at your level?" → Chapter 4 (Finite Time) + Chapter 2 (Three Maps)
- "Tell me about a time you drove a large cross-team technical initiative" → Chapter 5 (Leading Big Projects)
- "How do you influence teams that don't report to you?" → Chapter 8 (Good Influence at Scale)
- "How do you think about technical strategy?" → Chapter 3 (Creating the Big Picture)
- "Tell me about a time you course-corrected a project that was going wrong" → Chapter 5 (Leading Big Projects)
- "How do you develop junior engineers?" → Chapter 7 (You're a Role Model Now)
- "How do you form and defend technical opinions?" → Chapter 6 (Why Have Opinions?)
- "Describe how you navigated org politics to get a technical decision through" → Chapter 2 (Three Maps)

---

## TL;DR — 5 Ideas to Internalize

1. **Your job title changed; your compass needs to change too** — the work of a staff engineer is not more of the same excellent technical work. It is qualitatively different: setting direction, removing ambiguity, and making the organisation more capable. Engineers who keep optimising for individual output at this level stall.
2. **You need three maps, not one** — you must simultaneously understand your immediate team's context (locator map), the political and social terrain of your organisation (topographical map), and where the organisation is trying to go (treasure map). Most engineers only carry the first.
3. **Time is your most finite resource — protect it ruthlessly** — at the staff+ level, nobody is managing your time for you. Without deliberate investment in the right problems, you will drift toward visible urgent work and away from the invisible important work that constitutes the actual job.
4. **Opinions must be defensible, not just instinctive** — staff engineers are expected to have strong technical opinions, but those opinions must be grounded in reasoning that can survive challenge. The goal is not to win arguments; it is to make better decisions collectively.
5. **Influence at scale requires changing systems, not convincing individuals** — if you are trying to improve code quality by reviewing every PR yourself, you have not solved the problem — you have become a bottleneck. The staff-level move is to build the process, write the guide, create the linter, or change the incentive that makes good quality automatic.

---

## Introduction — The Staff Engineer Role

Reilly opens by observing that the career ladder for engineers has two tracks above senior: management and staff/principal IC. Both are legitimate. The staff path is often described negatively — "it's like management but without the reports" — which obscures what it actually is.

### The Three Archetypes (after Will Larson's Staff Engineer)

| Archetype | Primary Mode | Where You See Them |
|---|---|---|
| Tech Lead | Guides technical direction of a team; part manager, part architect | Product-focused engineering teams |
| Architect | Owns technical direction for a specific domain or system | Infrastructure, platform, data systems |
| Solver | Parachutes into the hardest problems across the org | Firefighting, migrations, new domains |
| Right Hand | Amplifies a senior leader's scope and capacity | Org-wide strategic work |

Reilly's key insight: **your archetype is not fixed and not entirely your choice**. It is a negotiation between your strengths, your manager's needs, and your organisation's gaps. Understand which archetype your role requires before optimising for the wrong one.

### What Staff Engineers Actually Do

Four categories of work that did not exist at senior level:

| Category | Senior Engineer | Staff Engineer |
|---|---|---|
| Scope | Team or project | Multiple teams, domain, or organisation |
| Ambiguity | Given a problem | Finds the problem worth solving |
| Decision-making | Contributes to decisions | Drives or arbitrates decisions |
| Leverage | Personal output | Organisational capability |

The anti-pattern Reilly warns against: **the "glue work" trap** — doing the invisible coordination, documentation, and unblocking work that nobody else will do, and doing it so effectively that you never get credit for it. Glue work is necessary; making it your entire job is a career stall.

---

## Part 1: The Big Picture

### Chapter 1 — What Would You Say You Do Here?

This chapter addresses the identity crisis most engineers experience when promoted to staff. The job description is vague. Nobody has time to onboard you. The pull toward familiar, concrete, individually-executable work is overwhelming.

#### The Core Mandate

Reilly's definition: **a staff engineer's job is to be the technical adult in the room for problems the organisation cannot otherwise solve.** This includes:

- Problems with no clear owner across team boundaries
- Decisions that have long-term architectural implications the team can't see
- Gaps in technical capability that compound over time
- Projects that stall because they are politically hard, not technically hard

#### Proving Your Value at the Staff Level

The paradox: at senior level, impact was visible (PR count, feature velocity, bugs fixed). At staff level, the highest-impact work is often invisible by design — you prevented a bad architectural decision, aligned two teams before they wrote conflicting systems, or wrote a strategy doc that changed how three teams prioritise their roadmaps.

**FAANG interview implication**: when asked about impact, staff-level candidates must learn to narrate invisible impact. The frame is: "here was the problem the organisation had, here is the counterfactual if I hadn't acted, here is what I did instead." The counterfactual is the impact.

#### Navigating the Role With Your Manager

Reilly identifies five things to align on with your manager:
1. **What does success look like for me in the next 6 months?** Explicit, written, agreed.
2. **Which problems are mine to own vs which am I contributing to?** Ownership is not always obvious.
3. **How much autonomy do I have to pursue the work I identify as important?** Some managers want control of your roadmap; some want you entirely self-directed.
4. **What is my manager's biggest problem right now?** The most politically safe place to apply leverage is directly on your manager's top priority.
5. **Who are the other staff+ engineers and how do we coordinate?** Knowing the informal technical leadership network is essential.

---

### Chapter 2 — Three Maps

The most conceptually dense chapter in the book. Reilly argues that navigating a large organisation requires three distinct mental models simultaneously.

#### Map 1: The Locator Map (Where Are You?)

Your immediate team context:
- What are your team's goals and OKRs?
- What problems does your team own? What do they avoid?
- What is the team's relationship with adjacent teams?
- What does your manager's manager care about?

This is the map most engineers have instinctively. The mistake is to believe this is sufficient.

#### Map 2: The Topographical Map (What Is the Terrain?)

The political, social, and organisational terrain of the company:
- Where are the power centres? Which teams have budget, headcount, and C-suite attention?
- Where are the fault lines? Which teams have chronic conflict, misaligned incentives, or territorial boundaries?
- Who are the informal influencers? The engineer whose opinion closes debates, the PM who has the VP's ear?
- What are the unwritten rules? What proposals get funded? What gets killed?

**This is the map most senior engineers lack.** The topographical map is not cynical politics — it is essential context for getting anything done. A technically perfect proposal fails without it. A technically imperfect proposal in the right hands with the right framing succeeds.

#### Map 3: The Treasure Map (Where Is the Organisation Going?)

The direction and destination:
- What does the company care about in 2–3 years, not just the next quarter?
- What bets is leadership making? Where is investment flowing?
- What is the technical strategy? Is it explicitly documented or inferred from decisions?
- What will the organisation need to be capable of doing in 3 years that it cannot do today?

The treasure map is where staff engineers add unique value. Individual contributors are optimising for the next sprint. Product managers are optimising for the next quarter. Staff engineers should be optimising for the next 3 years.

**FAANG interview framing**: "Tell me about a technical initiative you drove" — the best answers use all three maps. *Locator*: here is the team context. *Topographical*: here is how I navigated stakeholders. *Treasure*: here is why this mattered for where the company was going.

#### Understanding the Organisation's Communication Channels

Three modes Reilly identifies:

| Mode | What It Is | Why It Matters |
|---|---|---|
| Formal channels | Org charts, meeting structures, documented processes | Starting point; rarely reflects how work actually gets done |
| Informal network | Trusted relationships across teams, skip-level conversations, hallway chats | Where most real alignment happens |
| Written artefacts | Design docs, RFCs, decision memos | The durable record; the only thing that scales org-wide |

A staff engineer who only uses formal channels is operating at 40% capacity. A staff engineer who cultivates the informal network and creates written artefacts operates at 100%.

---

### Chapter 3 — Creating the Big Picture

Technical strategy and vision — the highest-leverage output a staff engineer can produce, and the most commonly skipped because it requires months of sustained focus with no immediate deliverable.

#### What a Technical Vision Is (and Is Not)

**Is**: A 2–3 year description of where the technical organisation needs to be — the capabilities it needs, the systems it needs to have retired, the architectural principles it needs to have adopted — to execute the business strategy.

**Is not**: A list of projects. A wish list. An architecture diagram. A technology selection doc.

The test for a good technical vision: if you gave it to a team that had never worked with you, would they be able to make autonomous decisions about which technical investments to prioritise? If yes — it's a vision. If it requires you to interpret it for every decision — it's notes.

#### Writing the Vision: The Process

Reilly's prescribed approach:

1. **Read the existing artefacts** — strategy docs, OKRs, post-mortems, ADRs, incident reviews. Understand what the organisation has already decided.
2. **Interview the humans** — talk to engineers, TPMs, PMs, and leadership. The vision must reflect the problems people actually have, not the problems the architect thinks they should have.
3. **Identify the gaps and the bets** — where is the current technical landscape failing to support the business strategy? What changes in the next 3 years will stress the current architecture?
4. **Draft in public, early** — share rough drafts. The goal is to surface disagreements before the vision is "done" and people treat it as fait accompli.
5. **Make the tradeoffs explicit** — a vision that doesn't say "we are choosing X over Y, and accepting the following consequences" is not a vision; it is a collection of aspirations.

#### The Technical Strategy Document

Below the vision, a strategy document translates direction into decisions:

```
Vision:        Where we need to be in 3 years
Strategy:      The set of choices that get us there
Initiatives:   The projects that execute on the strategy
```

**FAANG interview framing**: if asked "how do you think about technical strategy," the answer that lands at principal level is: vision → strategy → initiatives with explicit prioritisation and trade-offs. The answer that lands at senior level is: "we should rewrite X in Y." Know the difference.

#### Socialising the Vision

A vision document is worthless if nobody reads it and nobody changes their behaviour because of it. Socialisation requires:

- **Top-down sponsorship**: a VP or director who publicly endorses the direction
- **Bottom-up buy-in**: the teams who will execute on it believe it reflects their reality
- **Repeated reference**: the vision is cited in design reviews, RFC discussions, and prioritisation meetings — not just published once and forgotten

---

## Part 2: Execution

### Chapter 4 — Finite Time

Time management for staff engineers. Reilly's thesis: nobody will manage your time for you at this level, and the default allocation of time at a staff engineer who doesn't deliberately protect it will drift almost entirely to low-leverage reactive work.

#### The Time Allocation Problem

| Activity Type | Where Actual Time Goes | Where It Should Go |
|---|---|---|
| Reactive (Slack, PR reviews, incident response) | 60–80% | 30–40% |
| Proactive technical work (design docs, prototypes, research) | 10–20% | 30–40% |
| Org work (strategy, alignment, sponsoring others) | 5–10% | 20–30% |

The reactive/proactive split is the single most important time management decision a staff engineer makes.

#### Categories of Staff Engineer Work

Reilly's taxonomy:

- **Core technical work**: The hands-on technical work you are expert in — coding, architecture, reviewing. At the staff level, this should be narrowing in focus (deep in fewer areas) and increasing in quality (you are setting the bar, not hitting it).
- **Glue work**: Documentation, coordination, process work. Essential but should not dominate. Danger sign: you are doing glue work because nobody else will, not because it is the highest leverage thing you can do.
- **Org work**: Understanding the terrain, building relationships, influencing direction. Chronically underinvested.
- **Learning**: Staying current, reading, research. Drops to near zero under pressure. Fatal long-term.

#### Deciding What to Work On

Reilly's decision framework for evaluating what to take on:

```
1. Is this problem real? (not a theoretical concern but an actual pain)
2. Does it need me specifically? (or would any capable engineer do)
3. Is it in the critical path of something the organisation cares about?
4. Can I make a dent in a reasonable timeframe?
5. What is the cost of not doing it?
```

If the answer to 2 is "any capable engineer could do this," that is a delegation signal, not a work queue item.

#### Saying No Without Burning Bridges

The staff engineer's dilemma: you have the authority to say no to work in ways seniors cannot, but exercising that authority requires political capital and social skill. Reilly's approach:

- Say no to the *work*, not to the *person or team*
- Offer an alternative: "I can't take this on now, but here is who should / here is a later date when I can / here is a lighter-touch way I can help"
- Explain the trade-off: "If I do this, I can't do X, which is higher priority for the business"
- Never ghost — slow non-response is worse than a clear no

---

### Chapter 5 — Leading Big Projects

The chapter most directly applicable to "tell me about a cross-team initiative you led" interview questions.

#### What Makes a Project "Big"

- Multiple teams involved with different priorities and constraints
- Timeline of months to years, not days to weeks
- Technical direction not fully known at the start
- Success requires coordination and alignment, not just execution
- Failure would have significant business or architectural consequences

#### The Staff Engineer as Technical Program Lead

Reilly distinguishes between the PM/TPM role and the staff engineer role on big projects:

| Dimension | TPM/PM | Staff Engineer |
|---|---|---|
| Authority | Formal — owns the project charter | Informal — owns the technical direction |
| Focus | Timeline, stakeholders, status | Architecture, trade-offs, technical risk |
| Blocker resolution | Escalation and resourcing | Technical clarity and decision-making |
| Success metric | On time, in scope | Technically right AND on time/in scope |

The staff engineer is not a TPM and should not try to be one. The staff engineer's job is to be the person in the room who can answer "why are we doing it this way?" at every level — and change course when the answer is wrong.

#### Project Leadership Phases

**Phase 1: Clarifying the Problem**

Before writing a line of code or a design doc:
- What is the actual problem? (not the proposed solution)
- Who are the stakeholders and what do they each need?
- What does success look like — and who gets to define it?
- What are the constraints: timeline, headcount, budget, technology choices?

The most common failure mode of large projects: skipping this phase because there is social pressure to "get moving." The cost of moving fast before clarity is misalignment discovered 4 months in.

**Phase 2: Designing in Public**

Write the design doc early, when it is still wrong:
- An early wrong design doc generates the disagreements you need to have
- A late polished design doc generates the disagreements you should have had 3 months ago
- Iterate publicly — each revision should be visible and attributable so the team can see thinking evolve

The RFC process is the institutional mechanism for this phase. A good RFC answers:
```
Problem      → What is broken and why does it matter?
Proposal     → What are we going to do?
Alternatives → What did we consider and reject, and why?
Trade-offs   → What are we giving up with this approach?
Rollout      → How do we get from here to there safely?
```

**Phase 3: Maintaining Momentum**

The middle of a large project is where most projects die. Reilly's checklist:
- Regular written status updates — one paragraph, three audiences (team, stakeholder, leadership) — different levels of detail
- Decision log — every significant decision recorded: what was decided, who was in the room, what alternatives were rejected
- Risk register — live document of "here is what could go wrong and what we are doing about it"
- Blockers as first-class artifacts — a blocker that exists in someone's head is not a blocker; a blocker in the decision log with an owner and a date is

**Phase 4: Landing It**

The last 20% of a large project takes 80% of the energy. Common failure modes:
- "Done" defined by the code being written, not the users using it
- Migration not complete — old system still running, new system not trusted
- Documentation not written — institutional knowledge locked in the implementation team's heads
- Retrospective skipped — lessons not captured, same mistakes made in the next project

#### Handling Conflict on Big Projects

Reilly's approach to the inevitable technical disagreements:
- **Separate the decision from the relationship** — disagree on the approach, not on the person
- **Make the disagreement explicit** — document the competing views in the design doc. "Team A prefers X because [reasons]. Team B prefers Y because [reasons]." Forces specificity.
- **Identify the decision criterion** — what would make one approach better than the other? A shared criterion is more likely to produce agreement than advocacy.
- **Time-box the debate** — "we will decide by Thursday" prevents indefinite bikeshedding
- **Escalate as a last resort with a clear framing** — "we have exhausted our ability to align; here is the decision we need made; here are the two options and their trade-offs"

---

### Chapter 6 — Why Have Opinions?

The chapter on forming and defending technical positions — a direct probe area in principal engineer interviews.

#### Why Opinions Matter at the Staff Level

Senior engineers contribute technical opinions in their domain. Staff engineers are expected to have opinions about technical direction across domains, to hold those opinions under challenge, and to update them when evidence warrants.

The pathological alternatives:
- **No opinion**: The staff engineer who avoids positions to avoid conflict is abdicating the core job
- **Undefended opinion**: "I just think X is better" without reasoning — collapses under any challenge
- **Rigid opinion**: Refuses to update even when wrong — destroys trust and blocks good decisions

#### Building Defensible Opinions

Reilly's process for forming positions on technical questions:

1. **Gather evidence, not just instinct** — read the docs, the post-mortems, the benchmarks, the academic papers. An opinion grounded in evidence survives challenge; an instinct does not.
2. **Understand the alternatives** — you cannot credibly prefer X over Y if you have not seriously engaged with Y. "I haven't looked at Y deeply" is fine to say; "Y is worse" without engagement is not.
3. **Identify the failure modes** — every approach fails in some scenario. Know how yours fails. This is what separates an engineering opinion from a sales pitch.
4. **State your assumptions explicitly** — "I think X is better assuming [load profile / team size / timeline / consistency requirements]" — this makes the opinion updatable when assumptions change.

#### The Opinion-Forming Table

| Step | Question | Why It Matters |
|---|---|---|
| Understand the problem | What is actually being solved? | Wrong frame → wrong answer |
| Evaluate alternatives | What are the realistic options? | Can't prefer X over Y without knowing Y |
| Identify trade-offs | What does each option cost? | Reveals hidden costs and risks |
| Check your assumptions | What would make this wrong? | Makes opinion updatable |
| State the recommendation | What should we do and why? | Forces commitment, enables challenge |

#### Changing Your Mind Gracefully

The most underrated staff engineer skill: updating a position visibly and without defensiveness.

The wrong way: silently stop advocating for position A and start advocating for position B without acknowledging the shift.

The right way: "I've been thinking more about X. Team Y raised [consideration] that I hadn't fully weighted. I now think B is the better approach because [reasoning]. Here is what changed."

Changing your mind explicitly demonstrates intellectual honesty, models the behaviour you want from others, and — critically — gives the team the signal that updating is safe. Teams where the most senior person never admits to being wrong become teams where nobody tells the most senior person they are wrong.

---

## Part 3: Leveling Up

### Chapter 7 — You're a Role Model Now

The chapter on how staff engineers shape culture through behaviour — whether they intend to or not.

#### The Unearned Weight of Seniority

When a staff engineer acts in a meeting, writes code, reviews a PR, or sends a message — every engineer in the room is taking notes. The behaviours of senior people define what is normal, what is rewarded, and what is tolerated.

This is not optional. You are a role model whether you have chosen to be or not. The only choice is whether you are a role model deliberately.

#### Behaviours That Shape Culture at Scale

| Behaviour | What It Models |
|---|---|
| Asking "why" before diving into "how" | Problem understanding comes before solution generation |
| Writing clear, concise design docs | Written communication is a professional skill, not a chore |
| Crediting others' ideas explicitly | Collaboration is rewarded, not punished |
| Saying "I don't know, let me find out" | Intellectual honesty is valued over appearing to know everything |
| Updating public positions with reasoning | Being wrong and learning is a virtue, not a weakness |
| Investing time in people who are struggling | Senior engineers help others grow, not just deliver |

#### Sponsorship vs. Mentorship vs. Advice

| Mode | What It Is | Staff Engineer Role |
|---|---|---|
| Advice | "Here is what I would do" — one-directional | Occasional; don't over-advise |
| Mentorship | Ongoing relationship; guidance on career and technical growth | Important; invest in 1–2 people deliberately |
| Sponsorship | Advocating for someone in rooms they are not in | Highest leverage; underused by most staff engineers |

Sponsorship is the highest-leverage people investment a staff engineer can make. Mentoring someone makes them better. Sponsoring someone opens doors they couldn't open themselves. At principal level, you should have an active list of 3–5 people you are sponsoring.

#### Scaling Your Technical Impact Through Others

The staff engineer who is the best technical resource in the room for every question has not scaled. The staff engineer whose former mentees are now the best technical resources in the room has scaled.

Concrete mechanisms:
- **Technical talks**: One hour of talk, 50 engineers upskilled, replayable
- **Design doc reviews**: Feedback on one doc teaches the author and every reader the standard
- **Pairing on hard problems**: Transfers context and approach, not just solutions
- **Writing guides and runbooks**: The knowledge that was in your head is now in the organisation

---

### Chapter 8 — Good Influence at Scale

The final chapter — how to change the technical direction of the organisation without having line authority.

#### The Influence Stack

| Level | Mechanism | Scope |
|---|---|---|
| Personal credibility | Deep expertise, track record, reliability | People who know you |
| Written artefacts | Design docs, RFCs, ADRs, strategy docs | Anyone who reads |
| Process and standards | Coding standards, review guidelines, approval gates | Everyone who ships |
| Hiring and onboarding | Who gets hired, what they are taught first | Organisational capability over time |

Most staff engineers operate at level 1 (personal credibility) and occasionally level 2. Lasting change happens at levels 3 and 4.

#### Changing Behaviour Through Systems, Not Persuasion

The persuasion approach: convince each person, one at a time, that the new approach is better. Linear in effort. Does not survive the person leaving.

The systems approach: change the default. Invest the time once to create the mechanism that makes the right behaviour the path of least resistance.

Examples:
- Don't tell people to write tests — wire a test coverage gate into the CI pipeline
- Don't review every PR for security issues — write a linter that catches the common ones automatically
- Don't remind people to update the runbook — make the deploy pipeline fail if the runbook hasn't been touched in 6 months
- Don't advocate for code review quality in every meeting — write the review checklist that is linked from every PR template

**FAANG interview framing**: "How do you influence engineers across teams?" — the principal-level answer is about building systems and standards, not about being a charismatic advocate. The senior-level answer is about being a charismatic advocate.

#### Working With (Not Around) Formal Authority

Staff engineers sometimes believe they should be able to drive change purely through technical merit and persuasion. This is idealistic. Large organisations have formal authority for good reasons.

Reilly's framework for working with formal channels:
- **Seek sponsorship early** — find the VP or director who owns the problem space. Make them a co-author of the solution, not a reviewer.
- **Make it easy for decision-makers to say yes** — write the decision memo. Provide the trade-off table. Do the pre-work that converts a vague org desire into a signed-off initiative.
- **Be the person who implements the decision** — proposals without implementation plans are ignored. Proposals with a credible team and a credible timeline get funded.

#### Managing Up Effectively

Reilly dedicates specific attention to the staff engineer's relationship with their skip-level and above:

- **Make your work visible deliberately** — at the staff level, the most important work is often the least visible. Send the written status update. Drop the one-paragraph summary in the right Slack channel. Make it easy for leadership to know what you are doing and why it matters.
- **Frame problems in business terms, not technical terms** — "the monolith is causing architectural debt" does not move executives. "The monolith is why we cannot launch in a new region without 6 months of prep work" does.
- **Come with a recommendation, not just a problem** — "we have a scaling problem" is an information transfer. "We have a scaling problem; here are three options; I recommend option 2; here is why" is what executive-level communication looks like.

---

## Key Frameworks Summary

### The Three Maps (Chapter 2)
```
Locator Map    → Immediate team context, relationships, constraints
Topographical  → Political and social terrain, power centres, fault lines
Treasure Map   → Where the org is going in 2–3 years
```

### Time Allocation Target (Chapter 4)
```
Reactive work    → 30–40% (not 60–80%)
Proactive work   → 30–40% (design, strategy, research)
Org work         → 20–30% (alignment, sponsorship, influencing direction)
```

### Decision-Making Framework (Chapter 6)
```
1. What is the actual problem?
2. What are the realistic alternatives?
3. What does each alternative cost?
4. What are my assumptions?
5. What is my recommendation and why?
```

### The Influence Ladder (Chapter 8)
```
Level 1: Personal credibility (scales to people who know you)
Level 2: Written artefacts (scales to readers)
Level 3: Process and standards (scales to everyone who ships)
Level 4: Hiring and onboarding (scales to future organisation)
```

---

## FAANG Interview Application: Composite SSTAR Framework

Combining Reilly's frameworks, a FAANG principal engineer answer to a cross-functional leadership question should hit all of these beats:

| Beat | What to Say | Reilly Chapter |
|---|---|---|
| **Context** | The technical and organisational situation — use the three maps | Ch 2 |
| **Problem identification** | Why this was the right problem to work on — use the time allocation framework | Ch 4 |
| **Technical leadership** | How you drove the technical design — RFC, design doc, opinion formation | Ch 5, 6 |
| **Org navigation** | How you aligned stakeholders, managed up, handled conflict | Ch 5, 8 |
| **Leverage through others** | Who you brought in, developed, or sponsored | Ch 7 |
| **Systemic outcome** | What process, standard, or capability you left behind — not just the artifact | Ch 8 |
| **Result** | Business impact, technical improvement, and org capability change | All |

If your SSTAR answers are missing the **systemic outcome** beat — the thing that outlasts you — they are calibrated at senior engineer, not principal engineer.

---

## Actionable Takeaways

| Priority | Action |
|---|---|
| **Immediate** | Draw your three maps for your current role. Where are the gaps in your topographical map? |
| **This week** | Audit your last 2 weeks of calendar. What percentage was reactive vs proactive vs org work? |
| **This month** | Identify one technical decision coming up and practice the defensible opinion framework |
| **This quarter** | Start or update a technical vision document for your domain |
| **Ongoing** | Name 3 engineers you are actively sponsoring. If you can't, add it to your weekly calendar |
| **Interview prep** | For every SSTAR answer, add a "systemic outcome" beat — what did you put in place that outlasts you? |
