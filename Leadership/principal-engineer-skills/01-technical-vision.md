# Technical Vision and Direction Setting

**Category:** Principal Engineer Skills · Technical Strategy · Leadership  
**Framework:** Vision → Strategy → Roadmap hierarchy  
**Interview context:** "Where do you see our platform in 3 years?" / "How do you set technical direction for your org?" / "Tell me about a time you defined the technical strategy for a significant initiative."

> A roadmap is a list of features. A strategy is a set of trade-offs. A vision is a picture of a better world that explains why the trade-offs are worth it. Principal engineers set visions. Senior engineers execute roadmaps.

---

## Why Technical Vision is a PE-Level Skill

Any strong senior engineer can design a system. The PE-level question is: *which* system should we be building, and why — for the next 2–3 years, not the next sprint?

Technical vision is PE-scope because:
- It requires understanding the **business trajectory**, not just the current technical state
- It forces **trade-off decisions** that lock in constraints for years — wrong calls here are hard to undo
- It requires **influencing without authority** — you don't control all the teams whose direction you're shaping
- It must **survive leadership transitions** — a vision that lives only in your head isn't a vision, it's a personal preference

Interviewers at FAANG PE level test this by asking you to describe a time you set technical direction — and then probing whether you had a *reasoned* direction vs. just executing what was obvious.

---

## The Hierarchy: Vision → Strategy → Roadmap

These three terms are often used interchangeably. They shouldn't be.

```
VISION (2–3 years)
"What does success look like for our technical platform?"
"What problems will we have solved that we can't solve today?"
Audience: Engineering leadership, product, cross-functional partners
Frequency: Set once, reviewed annually, updated rarely

    │
    ▼

STRATEGY (6–18 months)
"What are the key bets we're making to close the gap to the vision?"
"What are we explicitly NOT doing?"
Audience: Tech leads, EMs, senior engineers
Frequency: Set quarterly, adjusted as signals arrive

    │
    ▼

ROADMAP (0–6 months)
"What are we shipping, in what order, to execute on the strategy?"
Audience: Teams, product, stakeholders
Frequency: Updated continuously
```

A common failure mode: engineers who are good at roadmaps get promoted and asked to set vision, but they write a longer roadmap and call it a vision. A vision is not a list of features 3 years out. It's a description of the world you're building toward — and a set of principles for making decisions along the way.

---

## How to Develop a Technical Vision

### Step 1: Start with Problems, Not Solutions

The wrong starting point: "What technology should we adopt in 3 years?"  
The right starting point: "What problems will we have in 3 years if we don't change anything?"

**Discovery questions to ask before writing anything:**
- What is the most common reason our engineers are slowed down today?
- What incidents keep recurring that we keep patching instead of solving?
- Where do our seams break? (Service boundaries, team handoffs, data ownership)
- What would we build differently if we were starting from scratch today?
- What business capabilities are we being asked to deliver that our current architecture makes expensive?
- What are our top 3 competitors doing technically that we can't match with our current system?

Interview these people: your team's engineers (they see the daily friction), your team's PMs (they see the business capability gaps), the SRE/on-call team (they see the operational pain), engineers who recently joined from competitors (they have comparative perspective).

---

### Step 2: Identify the Forcing Functions

A vision that ignores external constraints isn't a vision — it's a wish list. Identify the forces that make the current trajectory untenable:

**Scale forcing functions:**  
"We're at 5M users. Our current architecture becomes unstable past 20M based on our growth trajectory. We'll hit that in 18 months."

**Organisational forcing functions:**  
"We have 8 teams sharing a monolith. Each team's deploy requires coordinating with 7 others. This is already our #1 delivery bottleneck. At 12 teams (our hiring plan for 18 months), it becomes untenable."

**Technology forcing functions:**  
"Our core dependency (library X / cloud service Y) reaches end-of-life in 24 months. Migrating is 6 months of work regardless of when we start."

**Business forcing functions:**  
"The product wants to expand to 3 new markets in 24 months. Our current data model is country-specific, not multi-tenant. Every new market would cost 8 engineer-weeks of bespoke integration."

Forcing functions create urgency and specificity. They make your vision grounded in reality rather than technology preference.

---

### Step 3: Write the North Star Document

The technical vision lives in a written document — typically 3–6 pages. Not a slide deck (too shallow). Not a 30-page treatise (too long to read).

**Structure:**

```markdown
## Executive Summary
One paragraph: what future we're building toward and why it matters.

## Current State: What's Holding Us Back
The 3–5 most significant technical constraints we face today.
Quantify each: latency, deploy time, incident rate, engineer hours wasted.

## The Vision: What Success Looks Like
Describe the platform 2–3 years from now.
NOT a feature list. A description of capabilities and properties:
"Any team can deploy independently, with confidence, in under 10 minutes."
"Our data model supports any currency and locale without bespoke engineering."
"An engineer new to the codebase can trace any production issue to root cause 
in under 30 minutes."

## Principles: How We'll Make Decisions Along the Way
3–5 guiding principles that resolve trade-offs as they arise.
Example: "Incremental migration over big-bang rewrites."
Example: "Owned complexity over borrowed complexity — we take on infra debt 
to remove platform debt."
Example: "Consistency over local optimization — each team's choices must work 
for all teams, not just themselves."

## What We're NOT Doing
Explicitly stating what's out of scope is as important as what's in scope.
"We are not building a general-purpose platform for all of [company]. We are 
building a platform for the checkout and payments surface."
This prevents scope creep and manages expectations.

## The Key Bets
3–4 high-level strategic initiatives that close the gap.
"Migrate to a service-oriented architecture with clear domain boundaries."
"Build a self-service deployment pipeline that doesn't require SRE involvement 
for routine deploys."
These are strategies, not projects. Projects come out of strategy.

## How We'll Know We're Succeeding
Measurable outcomes (not outputs):
"Deploy frequency: from 1 per week per service to 5+ per week."
"MTTR: from 45 min median to under 15 min."
"Engineer onboarding: time to first PR from 2 weeks to 3 days."
```

---

### Step 4: Socialise Before Presenting

Do not write the vision document in isolation and then present it as complete.

**The socialisation path:**
1. **Draft with a small group** (2–3 trusted technical peers) — pressure-test the problem framing and the principles
2. **Test the "so what?" with EMs and PMs** — do they agree the problems you've identified are real? Do the principles resonate?
3. **Share with skeptics explicitly** — find the senior engineer most likely to disagree and get their feedback before the formal review. Either incorporate it or understand the objection well enough to address it in the room
4. **Present to leadership as a co-creation** — "I've been working through this with Alice, Bob, and the tech leads of the affected teams. Here's where we've landed." This lands differently than "here's my vision."

By the time you present to the CTO or VP Eng, the conclusion should not be new to them. The formal presentation confirms and documents; it doesn't surprise.

---

### Step 5: Maintain and Evolve the Vision

A vision document written once and never updated becomes religious doctrine — people cite it but no longer believe in it.

**Quarterly review cadence:**
- Are the forcing functions still accurate? (Technology landscape, org structure, business priorities change)
- Have the key metrics moved? Are we on the right trajectory?
- Are any principles creating unintended friction?
- Has the business strategy shifted in a way that changes what "success" means?

**When to update the vision:**
- Major organisational change (acquisition, reorg, leadership change)
- A forcing function accelerates or disappears
- A key bet fails or succeeds and changes the strategy

**When NOT to update the vision:**
- Because the roadmap is behind schedule (that's an execution problem, not a vision problem)
- Because an individual team disagrees with a principle (principles are supposed to constrain, not please everyone)
- Every time you have a new idea (vision stability builds trust)

---

## PE vs. Mid-Level on Technical Direction

| Dimension | Principal Engineer | Senior / Staff Engineer |
|-----------|-------------------|------------------------|
| **Time horizon** | 2–3 year vision + 6–18 month strategy | 6-month roadmap, maybe 12 months |
| **Scope** | Cross-team, org-level platform | One team's service or component |
| **Starting point** | "What problems will we have?" | "What should we build next?" |
| **Forcing functions** | Incorporates business trajectory, org growth, market pressure | Incorporates current team backlog and tech debt |
| **Principles** | Explicitly states what we're NOT doing | Plans all the things |
| **Socialisation** | Pre-socialises with skeptics; co-creates | Presents plan to team after writing it |
| **Measurement** | Outcome metrics (MTTR, deploy frequency, onboarding time) | Output metrics (features shipped, story points) |
| **Maintenance** | Quarterly review, explicit update cadence | Updates the Jira backlog |

---

## Common Interview Follow-Up Questions

**"How do you handle it when your vision conflicts with what the product team wants to build?"**

> "Vision is not an excuse to do purely technical work. A technical vision that doesn't serve the product is self-indulgent. When I see a conflict, I first check whether the conflict is real — sometimes what looks like a conflict is actually a sequencing question: 'we need to do X before the product can do Y.' If it's a real conflict — the product wants to build a feature that would entrench a pattern I'm trying to move away from — I make the trade-off explicit and time-bound: 'we can build this feature in the current architecture in 3 weeks, or we can build it in the new architecture in 6 weeks. The new architecture also enables features B and C you want next quarter.' I bring the data to the decision; I don't make the decision for the PM."

**"What happens when you set a vision and then leadership changes and the new leader has a different direction?"**

> "This happens. A vision document that is well-grounded in problem statements and forcing functions is more durable than one built on personal preference — because the problems don't change with the leader. When I present a vision to a new leader, I start with the problems and ask if they agree the problems are real. If they do, the vision logic usually follows. If they disagree about the problems themselves, that's a productive conversation I need to have — maybe the new leader has information I don't about the business direction that changes what problems matter. A vision that can't withstand a new leader's scrutiny wasn't robust enough."

**"How do you prevent the vision from becoming a 3-year excuse to not ship anything useful?"**

> "By separating vision from strategy and strategy from roadmap explicitly — and holding the team accountable to the roadmap. The vision describes the destination; the roadmap shows the quarterly stepping stones. If the vision is 'service-oriented architecture with independent deployment,' the roadmap should show concrete milestones: 'extract the payment service by Q2, the notification service by Q3.' If the roadmap isn't progressing, that's a delivery problem — you address it at the roadmap level, not by abandoning the vision. The vision also includes measurable outcomes, so there's no ambiguity about whether we're making progress."

**"What if engineers on your team don't buy into the vision?"**

> "I distinguish between engineers who have principled technical objections and engineers who are resistant to change. For the first group, their objections either improve the vision (I update it) or reveal a gap in my reasoning that I need to address. I actively want them in the room. For the second group, the strategy is to show the vision working — pick an early win that makes the vision tangible. Abstract vision is easy to resist; a service that deploys independently in 5 minutes when the rest take 2 days is hard to argue against. I try to create the proof-of-concept that makes the vision real before asking everyone to commit to it."
