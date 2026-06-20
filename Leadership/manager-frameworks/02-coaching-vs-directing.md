# Coaching Engineers to Independence

**Category:** Manager Frameworks · Coaching · Engineering Development  
**Framework:** GROW Model · Situational Leadership · Competence × Commitment Matrix  
**Interview context:** "How do you develop the engineers around you?" / "Tell me about an engineer you grew significantly." / "How do you develop judgment in senior engineers?"

> The engineer who always asks your opinion is not learning to think — they are learning to ask. Your goal is to make yourself unnecessary.

---

## Why Coaching is a PE-Level Skill

A senior engineer's impact is bounded by their own output. A principal engineer's impact is bounded by the output of everyone they make more effective. The leverage multiplier is coaching — the ability to develop engineers' capability and judgment so they can operate more independently, handle harder problems, and eventually grow others.

At principal engineer level, you are expected to:
- Develop engineers who become the next tech leads and staff engineers
- Build judgment in senior engineers, not just provide answers
- Scale your technical perspective across people, not just across code
- Recognise when someone needs coaching vs. directing — and choose correctly

The failure mode is the **"brilliant helper"** principal: technically excellent, always available, and inadvertently stunting every engineer around them by providing answers instead of developing capability.

---

## Coaching vs. Directing: When Each is Right

These are not interchangeable. Using the wrong one at the wrong time is either inefficient (coaching a crisis) or limiting (directing instead of developing).

**Directing:** You tell the person what to do and how to do it.  
Right when: urgency is high, the stakes of a wrong decision are severe, or the person genuinely doesn't have the capability yet. A production incident is not the moment for a Socratic coaching conversation.

**Coaching:** You ask questions that help the person develop their own answer.  
Right when: the person has sufficient capability to reach a good answer themselves with guidance, and the cost of them thinking through it is acceptable. This is the majority of day-to-day engineering decisions.

The test: *"Does this person have the raw material to figure this out, or will they need significantly more expertise than they currently have?"* If yes — coach. If no — direct and explain.

**Common mistake:** Defaulting to directing because it's faster. Faster today; slower over 6 months because you are still answering the same questions.

**Other common mistake:** Coaching a genuinely novel problem the person has no framework for. "What do you think you should do?" to an engineer who has never encountered distributed transactions is not coaching — it's abandonment.

---

## The Situational Leadership Matrix

Blanchard's Situational Leadership model maps coaching style to where the engineer sits on two dimensions:

```
                  High Competence
                        │
     S3: Supporting     │     S4: Delegating
     High support       │     Low direction
     Low direction      │     Low support
     (they know how,    │     (they can own it
      need confidence)  │      fully — trust them)
                        │
Committed ──────────────┼──────────────── Uncommitted
 (motivated)            │                  (disengaged)
                        │
     S2: Coaching       │     S1: Directing
     High support       │     High direction
     High direction     │     Low support
     (learning +        │     (new to task,
      motivated)        │      needs structure)
                        │
                  Low Competence
```

**S1 — Directing (low competence, uncommitted):**  
Engineer is new to the problem domain and not yet engaged. Give clear structure: "Here's what I need you to do and why." Explain the reasoning so engagement builds.

**S2 — Coaching (low-medium competence, motivated):**  
Engineer is learning and motivated but needs guidance. Most development happens here. Ask questions, offer frameworks, provide feedback on their reasoning, not just their output.

**S3 — Supporting (high competence, variable commitment):**  
Engineer can do the work but may be losing confidence or motivation. Reduce direction (they know the technical path); increase support (ask about obstacles, celebrate progress, ask what they need from you). Don't coach someone who already knows — listen and remove friction.

**S4 — Delegating (high competence, committed):**  
Engineer is capable and engaged. Get out of the way. Check in on outcomes, not process. Over-managing here actively damages motivation.

**The principal engineer diagnostic:** Run through your 3–4 closest engineering collaborators. Where does each sit in this matrix? If most are in S4 — are you genuinely delegating or are you staying in S2 because you enjoy the engagement? If most are in S1 — are you coaching enough, or directing and moving on?

---

## The GROW Model

GROW is the most practical coaching framework for technical conversations. It structures a 20–30 minute coaching conversation into four questions:

```
G — Goal:     What are you trying to achieve?
R — Reality:  What is the current situation?
O — Options:  What approaches could you take?
W — Will:     What will you actually do, and when?
```

### Worked Example

**Situation:** A senior engineer, Maya, is struggling to get her RFC adopted. She's asked you for advice.

**Without GROW (directing mode):**  
> "The problem is you didn't socialise it early enough. Go talk to the tech leads of the affected teams before the next review."

Maya does what you said. She doesn't understand why. The next RFC she writes, she'll need your advice again.

**With GROW (coaching mode):**

*Goal:*  
**You:** "What outcome are you trying to achieve with this RFC?"  
**Maya:** "I want the three teams to commit to adopting the new logging standard."  
**You:** "And beyond the RFC being approved — what would a successful adoption look like in 3 months?"  
**Maya:** "All three services emitting structured logs in the new format, without me having to chase each team."  
*(Now you know the real goal is adoption, not approval. This changes the coaching.)*

*Reality:*  
**You:** "Where are you right now? Who's engaged, who's not?"  
**Maya:** "The platform team reviewed it and they're on board. The two product teams haven't reviewed it at all."  
**You:** "What's your read on why?"  
**Maya:** "I think they just haven't had time. Or maybe they see it as low priority."  
**You:** "What's the difference between those two explanations in terms of what you'd do?"  
*(Maya pauses — this is the moment she develops judgment, not just an action.)*

*Options:*  
**You:** "What are your options for getting the product teams engaged?"  
**Maya:** "I could go to their weekly sync. I could talk to their tech leads 1:1. I could escalate to the directors."  
**You:** "What are the trade-offs of each?"  
**Maya:** *(walks through the trade-offs)*  
**You:** "What would you do differently if you'd talked to them before writing the RFC?"  
**Maya:** "I would have included their concerns in the alternatives section... and they probably would have felt more ownership."  
*(She's now developed an insight she'll carry to future RFCs, not just this one.)*

*Will:*  
**You:** "What's your plan from here?"  
**Maya:** "I'm going to meet with both tech leads this week, understand their actual concerns, and update the RFC before the next review."  
**You:** "What might get in the way of that?"  
**Maya:** "Finding time on their calendars."  
**You:** "What's your fallback if they're not available this week?"  
*(Concrete commitment + obstacle planning.)*

**What GROW produced:** Maya has a plan she developed herself. She understands the reasoning. She has an insight (socialise before writing) that she'll apply to the next RFC without needing you. The 25 minutes you spent now saves you from being her RFC consultant for the next year.

---

## The "What Would You Do?" Habit

The single highest-leverage coaching behaviour is replacing answers with questions.

When an engineer comes to you: *"I'm trying to decide between approach A and B. What do you think?"*

**Directing response:** "Use A — here's why..."  
**Coaching response:** "What's your current lean, and what's driving it?"

The engineer who asked had already been thinking about this. They have a partial answer. Your job is to help them complete the reasoning, not to replace it. By asking what their lean is, you:

1. Discover they already know the answer and just need confirmation (common)
2. Hear their reasoning, which tells you where the gap is (more useful than the answer)
3. Force them to articulate their thinking, which often resolves the question on its own

**The follow-up question:** After they give their lean and reasoning — "What would need to be true for you to change your mind?" This teaches them to hold opinions provisionally and identify falsifiable conditions. This is judgment development.

**When to stop coaching and just answer:** When the engineer has given you their best reasoning and it's genuinely incomplete in a way they can't close themselves. At that point, explain the gap and why, not just the answer.

---

## The Brilliant Helper Trap

The brilliant helper is the principal engineer who is technically excellent, generous with their time, and available for every question. Engineers love working with them. They are also, often, a bottleneck — and are inadvertently limiting the growth of every engineer who gets in the habit of asking them.

**Signs you're a brilliant helper:**
- Engineers come to you with problems they could solve themselves with 20 more minutes of thinking
- You are consulted on decisions within teams you don't work on
- You are the first call when something goes wrong, even outside your area
- You enjoy being the person people come to

The brilliant helper pattern feels good on both sides — the engineer gets a fast answer, the principal feels useful. It is a negative-sum exchange: the principal's time is consumed, the engineer doesn't grow.

**The shift:** From "I'll answer this" to "Let me help you figure this out." The transition is uncomfortable for both parties initially. Engineers accustomed to getting answers feel slowed down. The principal feels less immediately useful. The payoff: in 3 months, you have engineers who are solving harder problems without you.

---

## Developing Senior Engineers Toward Staff

The development of a senior engineer toward staff scope requires specific coaching — it's not just encouraging them to do more. Staff scope involves different skills, not more of the same skills.

**What changes from senior to staff:**

| Dimension | Senior (L5) | Staff (L6) |
|-----------|------------|-----------|
| Problem source | Problems assigned to them | Problems they identify themselves |
| Scope | One service, one team | Cross-team, multiple services |
| Ambiguity | Handles well-defined ambiguity | Defines the problem from first principles |
| Influence | Within the team | Across teams without authority |
| Output | High-quality technical work | Multiplied output through others |

**Coaching moves for developing toward staff:**

- *Widen their problem horizon:* "What do you think the biggest technical risk to the platform is over the next 12 months?" Not a question with a right answer — a question that develops strategic thinking.
- *Give them cross-team problems:* Assign them to lead the RFC for a cross-team standard. Coach them through the social dynamics, not just the technical content.
- *Make your reasoning visible:* "I'm going to walk you through how I'm thinking about this trade-off — not the answer, the reasoning process." They can't learn to think at staff scope if they only see outputs.
- *Push back on their certainty:* When they give a confident technical opinion, ask "What would change your mind?" A staff engineer holds positions provisionally and updates on evidence.

---

## PE vs. Mid-Level on Coaching

| Dimension | Principal Engineer | Senior / Staff Engineer |
|-----------|-------------------|------------------------|
| **Default mode** | Coaching — asks before answers | Directing — answers efficiently |
| **Recognition of need** | Diagnoses whether the person needs coaching vs. directing | Defaults to one mode regardless |
| **Development awareness** | Tracks where each engineer sits on the maturity matrix | Doesn't explicitly track |
| **Brilliant helper risk** | Actively guards against it | Often falls into it willingly |
| **Staff development** | Coaches toward staff scope — widens problem horizon | Helps the person do their current job better |
| **GROW usage** | Used naturally in most development conversations | Doesn't exist as a framework |
| **Impact horizon** | Measured in who they develop over 1–2 years | Measured in technical problems solved this quarter |

---

## Common Interviewer Follow-Up Questions

**"Tell me about an engineer you developed significantly. What was your approach?"**

> "There was a senior engineer on the platform team — technically strong, but all of his thinking was narrowly scoped to his service. He'd come to design reviews with technically excellent proposals that didn't account for the 4 other teams who'd have to integrate his changes. My coaching focus was on widening his aperture. Every time he came to me with a technical proposal, my first question was always 'who else does this affect and have you talked to them?' Not as a gotcha — as a genuine question. I also assigned him to lead the API versioning RFC, knowing it would require him to manage disagreement across 3 teams. I met with him weekly during that process — but my questions were about the stakeholder dynamics, not the technical content. 'What's David's actual concern — is it the standard itself or is it the migration effort?' He shipped the RFC and got it adopted. More importantly, he started identifying cross-team risks in his own proposals before bringing them to me. He was promoted to staff 14 months later. The development wasn't in giving him harder technical problems — it was in expanding the problems he thought were his to own."

**"How do you handle an engineer who keeps coming to you for answers instead of developing their own judgment?"**

> "I stop giving answers and start asking questions — and I'm explicit about the shift. 'I've noticed you often come to me when you're deciding between options. I want to try something different: tell me your current lean and your reasoning before I weigh in.' The first few times it feels frustrating to them — they came for an answer and got a question. But once they see that their own reasoning usually produces a good answer with a bit of guided questioning, it builds confidence. The other thing I do is make the meta-conversation explicit: 'Part of what I want to help you develop is the ability to make this class of decision without me. You'll hit the ceiling on the kinds of problems you can take on if every complex trade-off requires a consult.' Most engineers respond well to the honesty — they don't want to be dependent either."

**"How do you develop judgment rather than just knowledge in senior engineers?"**

> "Knowledge is transferable — you can share it in a document or a talk. Judgment requires encountering real situations and processing them, which is why it can't be shortcut. My approach is to expose engineers to the reasoning process, not just the conclusions. When I'm making a significant technical decision, I narrate my thinking: 'Here's what I know, here's what I'm uncertain about, here's the trade-off I'm making and why, here's what I'd need to see to change my mind.' I also create safe-to-fail situations where they make consequential decisions with support. Not 'you're in charge of this critical migration alone,' but 'you're leading this RFC — I'll be available, and I'll give you feedback on your process, but the decision is yours to drive.' Judgment develops through making decisions and seeing the outcomes. My job is to make the feedback loop fast and safe — debrief honestly, name what worked and what didn't, and make them the protagonist of their own learning."
