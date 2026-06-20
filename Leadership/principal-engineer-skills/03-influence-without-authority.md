# Influence Without Authority

**Category:** Principal Engineer Skills · Cross-Team Leadership · Organisational Influence  
**Framework:** Trust → Credibility → Coalition → Decision  
**Interview context:** "Tell me about a time you influenced a decision you didn't own." / "How do you get teams to adopt a standard you proposed?" / "How do you drive change across teams when you have no direct authority?"

> Authority is borrowed. Trust is earned. Influence built on trust outlasts any org chart. A principal engineer who can only drive change through their manager's manager is half the engineer they could be.

---

## Why Influence Without Authority is a PE-Level Skill

A senior engineer's scope of impact is roughly equal to their team. A principal engineer's scope spans teams, domains, and sometimes the entire engineering organisation. But a principal engineer rarely has line authority over the teams they need to influence. They have:

- A title that signals seniority
- A track record that builds credibility
- A network that enables coalition-building
- Frameworks and data that make arguments hard to dismiss

The question "how do you influence without authority?" is really asking: *do you know how to lead without the shortcut of telling people what to do?*

---

## The Foundations: Why People Follow Without Being Told To

Before tactics, understand the underlying mechanics. People follow principal engineers who:

**1. Have demonstrated competence in the domain**  
The fastest path to influence is being visibly right before you ask anyone to do anything. If you've diagnosed problems accurately, predicted outcomes correctly, and shipped things that worked — people come to you. Influence is an output of being useful, not a technique you apply.

**2. Are known for making others successful, not for being right**  
There's a specific type of senior engineer who is always technically correct and whose presence engineers dread. They win arguments and lose influence. The principal engineers who have outsized influence are the ones who make you look good: they give you credit, they unblock your team, they help you solve hard problems. When that person asks your team to do something, the answer is usually yes — because they're seen as an ally, not a competitor.

**3. Can be trusted to represent trade-offs fairly**  
An engineer who always advocates for the same solution regardless of context (always microservices, always event-driven, always rewrite) is predictable and discountable. An engineer who says "in this situation, the monolith is the right call, even though I've generally advocated for decomposition" is credible — because they're willing to be wrong about their own prior positions.

---

## The Core Patterns

### Pattern 1: Conviction + Data (Not Title)

Do not lead with your title or your org relationship. Lead with evidence.

**Wrong:**  
"As a principal engineer, I'm recommending we adopt service mesh company-wide."

**Right:**  
"I've been looking at our incident data for the last 6 months. 34% of our P1 incidents involve service-to-service authentication failures or certificate expiry. Service mesh handles both automatically. Here are the numbers from the team that piloted it last quarter — MTTR for auth-related incidents dropped from 40 min to 3 min."

When your recommendation is backed by data that people can challenge (and can't), the conversation shifts from "who should I believe?" to "is this data correct?" That's a much stronger position.

**The "pre-mortem" technique:**  
Before presenting your position, ask the audience: "What would need to be true for this to be a bad idea?" Then address each condition. This forces skeptics to state their concerns as falsifiable conditions rather than vague resistance.

---

### Pattern 2: Coalition Building (Bottom-Up Before Top-Down)

Never present a recommendation to leadership that hasn't already been vetted by the people who will implement it.

**Why bottom-up matters:**  
A VP who approves a technical direction but whose engineers resist it has achieved nothing. A VP whose engineers are already aligned achieves everything with one approval.

**How to build the coalition:**

Step 1: Identify the 3–4 tech leads most affected by the change. Schedule 1:1 conversations with each before any group discussion.

Step 2: In each 1:1, ask about the problem first — don't pitch your solution. "I've been thinking about [problem area]. What's your read on it?" If they describe the same problem you've identified, they're already invested in a solution. If they don't see the problem, find out why before proceeding.

Step 3: Share your thinking informally: "I've been sketching out an approach. Can I walk you through it? I want your pushback before I write anything formal." Engineers who contribute to shaping a proposal are more likely to support it.

Step 4: When you present formally, you can say: "I've discussed this with the tech leads of all affected teams. Alice's team had a concern about migration sequencing — we've addressed that by phasing the rollout. The others are aligned." This removes the perception that you're asking people to commit to something untested.

---

### Pattern 3: Give Credit, Take Blame

The fastest way to lose influence at senior levels is to be seen as someone who takes credit. The fastest way to build it is to be seen as someone who amplifies others.

**Tactics:**
- In meetings, give attribution explicitly: "Bob raised this concern last week — I think it's worth the group hearing it." You don't lose anything by crediting Bob; you gain Bob's loyalty.
- In written proposals, list contributors prominently, even if you wrote 90% of it.
- When an initiative you sponsored fails, own it publicly. "I recommended this approach; the data showed it didn't work as expected; here's what I learned." Engineers respect this enormously.
- When an initiative succeeds, give credit to the team that executed. "The platform team built this in half the time I estimated — I want to call that out."

The counterintuitive result: engineers who give away credit accumulate influence, because everyone wants to work with them and to be seen working with them.

---

### Pattern 4: Write Publicly Internally

A principal engineer who writes well and shares their thinking widely multiplies their influence without being in any meeting.

**Forms this takes:**
- **Engineering blog posts** (internal): "Why we switched from REST to gRPC for our internal services — what we learned after 6 months"
- **Post-mortem retrospectives** shared beyond the incident team
- **Tech talks** at engineering all-hands or guild meetings
- **Weekly/monthly tech notes**: "Three things I've been thinking about this week" — distributed to the engineering team

The effect: engineers in teams you've never met start forming an opinion of your judgment before you've ever spoken to them. When you later propose something that affects them, they already have a frame: "Oh, that's the person who wrote that post about gRPC — their thinking is usually grounded."

Writing is leverage. One good internal post reaches 500 engineers in the same time a meeting reaches 10.

---

### Pattern 5: The Sponsorship Flywheel

Sponsor junior and mid-level engineers actively. Help them get visibility, amplify their work, advocate for their promotions.

This is not altruism (though it should be ethical and genuine). It creates a network of people across the organisation who trust you, vouch for you, and give you information. When you need to influence a team, you often know someone on that team whose judgment you've supported — and who will help you understand the local context.

The principal engineers with the broadest influence usually have the deepest informal networks. Those networks are built through genuine investment in others' careers, not through transactional favours.

---

### Pattern 6: The "Controlled Experiment" Approach

The most persuasive argument is not a proposal — it's a result.

When you want a team to adopt a new approach they're skeptical of:
- Don't ask them to commit org-wide
- Offer to run a pilot on one service, one team, one quarter
- Make the pilot low-risk: "We'll run this alongside your current approach for 6 weeks. If the data doesn't show the improvement I'm predicting, we stop."
- Collect the data rigorously
- Present the results at a team meeting or in writing — not just to the tech lead, but to the engineers who will implement it

A proof-of-concept that works converts skeptics faster than any argument. And a pilot that fails honestly ("I was wrong about this") builds more credibility than a hundred successful pitches.

---

## Handling Resistance

### Type 1: Principled Technical Objection

*"I don't think this approach handles the concurrency case correctly."*

Response: Engage directly and seriously. This person may be right. Ask them to walk you through their concern. If they're right, fix it and credit them. If they're wrong, explain why specifically and provide evidence. This is the healthiest form of resistance — it makes the proposal better.

### Type 2: Procedural Resistance

*"We never got to review this before it was presented to leadership."*

This is usually legitimate. It means you failed to socialise early enough. Acknowledge it: "You're right, I should have brought this to you sooner. Can we schedule time this week so I can get your input before we proceed?" The person typically wants to feel heard, not to block the proposal.

### Type 3: Territorial Resistance

*"This feels like you're trying to take over our architecture."*

This is the most common form of resistance for principal engineers who are driving cross-cutting changes. The engineer feels that your proposal undermines their team's ownership.

Response: Explicitly acknowledge the ownership concern. "This service stays 100% owned by your team — the RFC is about the communication protocol between services, not about how your service works internally. I want to make sure you have full veto power over the interface design." Find the genuine ownership boundary and protect it clearly. What feels like territorial resistance is often a legitimate concern about losing agency.

### Type 4: Status Quo Bias

*"This is how we've always done it."*

This is the hardest to address because it requires someone to admit the current state is suboptimal — which can feel like admitting they've been doing it wrong.

Response: Frame the current state as the right decision for its time, not a mistake. "The synchronous approach made complete sense when we had 5 services and 100 req/s. We're now at 40 services and 15K req/s — the same approach that was correct then is creating the incidents we're seeing now. This isn't about changing what was wrong — it's about adapting to a context that has changed."

### Type 5: Rational Actor Who Has Already Committed Elsewhere

*"We've already told our product team we'll ship X this quarter — we don't have capacity for a migration."*

This is legitimate and non-personal. The engineer is not resisting your idea; they're protecting their team's commitments.

Response: Work with it, not against it. "I hear you — I'm not asking you to do this in Q3. Can we plan for Q4, and I'll help you scope the work? I can also advocate to your EM that this migration is a platform-team-sponsored priority, which might free up capacity." Find a path that doesn't require them to choose between your request and their existing commitments.

---

## PE vs. Mid-Level on Influence

| Dimension | Principal Engineer | Senior / Staff Engineer |
|-----------|-------------------|------------------------|
| **Source of influence** | Track record + data + network | Technical correctness |
| **Approach to resistance** | Understands the type of resistance and responds differently to each | Defends the proposal more forcefully |
| **Coalition building** | Builds coalition before formal proposal | Presents to leadership and hopes for support |
| **Credit** | Distributes credit actively | Retains credit for own work |
| **Failure handling** | Owns publicly, extracts learning, moves on | Minimises or attributes to external factors |
| **Pilot approach** | "Let's test it on one team first" | "The whole org should adopt this" |
| **Writing** | Regular internal publishing to build ambient credibility | Writes when required |
| **Reach** | Influences engineers they've never met through writing and reputation | Influences their immediate team |

---

## Common Interviewer Follow-Up Questions

**"Tell me about a time you failed to influence a decision you thought was important. What did you learn?"**

> "I tried to get 4 teams to adopt a unified error handling library. I wrote the RFC, presented it at architecture review, got an informal 'sounds reasonable' from the principals — and then 6 months later none of the teams had adopted it. The failure was that I hadn't understood what was actually blocking adoption: the library required changes to each team's error logging format, which meant updates to their dashboards and alerts. The technical change was small, but the operational change was significant and nowhere in my RFC. I had confused 'technical buy-in' with 'adoption.' After that I started asking explicitly: 'What would make this hard to actually implement, not just technically approve?' The answer to that question is often different from what you get in a design review."

**"How do you influence a VP or engineering director who disagrees with your technical recommendation?"**

> "I start by understanding whether the disagreement is about the solution or the problem. If we don't agree on the problem, no technical argument about the solution will land — I need to present the problem more compellingly first: more data, more concrete user impact, more cost of inaction. If we agree on the problem but disagree on the solution, I ask what concerns would need to be addressed for them to change their position — specifically. Executives often resist technical proposals not because of the technology but because of risk, timeline, or org disruption. If I can isolate the actual concern, I can often address it. If I can't — maybe they have information I don't. The most important question I've learned to ask is: 'What are you seeing that I might be missing?'"

**"How do you avoid the perception that you're a principal engineer who just overrides team decisions?"**

> "By being explicit about what I'm deciding and what the team is deciding. My role is to set constraints and standards that apply across teams — the 'what we must do' and 'what we must not do.' Within those constraints, each team makes their own decisions. When I propose something cross-team, I try to be clear: 'I'm asking for alignment on the interface standard, not the implementation.' And I'm genuine about it — if a team has a better approach within the standard, I adopt it for the standard. Engineers stop worrying about overrides when they see that engaging with you leads to their ideas being incorporated, not replaced."
