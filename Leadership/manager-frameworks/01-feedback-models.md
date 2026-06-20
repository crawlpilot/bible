# Giving and Receiving Feedback

**Category:** Manager Frameworks · Coaching · Engineering Culture  
**Framework:** SBI (Situation-Behaviour-Impact) · Radical Candor 2×2  
**Interview context:** "Tell me about a time you gave difficult feedback to a peer or senior engineer." / "How do you build a feedback culture on your team?" / "Describe a time your feedback changed someone's trajectory."

> Feedback is not a gift. It is a professional obligation. Withholding honest feedback to protect someone's feelings is protecting your own comfort at their expense.

---

## Why Feedback is a PE-Level Skill

Any engineer can say "good job" or "that code looks fine." The PE-level skill is delivering feedback that:

- Is specific enough to act on
- Is calibrated to what the person needs to hear, not what's comfortable to say
- Lands without triggering defensiveness that prevents it from being heard
- Is given consistently — not just during reviews or incidents, but in the flow of work
- Applies to peers, senior engineers, and skip-level reports — not just junior engineers

Principal engineers are expected to shape the feedback culture of their teams, not just participate in it. When the culture doesn't give honest feedback — when everyone is polite but no one is honest — it is a PE-level failure to let that persist.

---

## Framework 1: SBI — Situation, Behaviour, Impact

SBI is the most reliable structure for delivering feedback that is specific, fair, and actionable. It separates observable fact from interpretation, which removes most of the defensiveness that feedback triggers.

```
Situation:  When and where did this happen?
            "In yesterday's architecture review..."
            "During the production incident on Tuesday..."

Behaviour:  What specifically did the person do or say?
            Observable, not interpreted. Not "you were dismissive" (interpretation).
            "You interrupted Alice twice while she was presenting her proposal"
            (observable).

Impact:     What was the consequence — for you, the team, the system?
            "Alice stopped contributing for the rest of the meeting.
             We lost her perspective on the database design."
```

### Weak vs. Strong Feedback

**Weak (vague, interpretive, easy to dispute):**
> "You need to be more collaborative in design reviews."

The recipient doesn't know what specifically to change. "Collaborative" is an interpretation, not a behaviour. They can disagree ("I thought I was being collaborative").

**Strong (SBI, specific, actionable):**
> "In yesterday's design review, when Alice was walking through her caching proposal, you interrupted her three times to redirect to your own approach before she'd finished explaining the trade-offs. Alice stopped engaging and we ended the meeting without hearing her full proposal. I want you to let people finish before responding — even when you disagree. The quality of our decisions depends on everyone's perspective being heard."

The recipient knows exactly what happened, when, what the consequence was, and what to do differently. They can disagree with your interpretation of the impact ("I don't think she stopped because of me"), but they can't dispute the observable behaviour.

### Delivering SBI: The Conversation

```
Step 1: State intent
"I want to give you some feedback about [situation]. Is now a good time?"
Never ambush. Giving someone a chance to say "can we do this in 15 minutes?"
is basic respect and increases the likelihood of being heard.

Step 2: State the SBI
One clear statement. Don't hedge, qualify, or soften to the point of
obscuring the message. "I noticed..." is fine. "I may be wrong but I
sort of thought maybe..." is not.

Step 3: Pause and ask
"What's your read on what happened?"
You may have incomplete information. The person may have context you don't.
A good feedback conversation is not a monologue; it's a diagnosis.

Step 4: Agree on a specific behaviour change
"What would you do differently in the same situation?"
The goal is a concrete change, not a general commitment to "be better."

Step 5: Offer support
"What can I do to help?" — sometimes nothing, sometimes a lot.
```

---

## Framework 2: Radical Candor — The 2×2

Kim Scott's Radical Candor framework maps feedback behaviour on two axes:

```
                        Challenge Directly
                               │
          Radical Candor       │      Obnoxious Aggression
          (care + challenge)   │      (challenge without care)
                               │
Care   ────────────────────────┼────────────────────────────  Don't
Personally                     │                             Care
                               │
          Ruinous Empathy      │      Manipulative Insincerity
          (care without        │      (neither)
           challenge)          │
                               │
                        Don't Challenge
```

**Radical Candor (top-left):** You care about the person AND you challenge them directly. This is the goal. Hard feedback delivered by someone who clearly cares about the recipient's growth lands very differently than the same words from someone who seems indifferent.

**Ruinous Empathy (bottom-left):** You care about the person but you don't challenge them. You see a problem and you say nothing — or you soften the feedback until it's meaningless — because you don't want to hurt their feelings. This is the most common failure mode for engineers who are promoted into leadership. It feels kind; it is actually a form of professional negligence.

*Example of ruinous empathy:* An engineer has been producing consistently mediocre architecture proposals. You've noticed it for 6 months. You haven't said anything because you don't want to discourage them. In their annual review, they are surprised to learn they're not on track for promotion. You have failed them — not this year, but for 6 months.

**Obnoxious Aggression (top-right):** You challenge directly but without evident care. Technically accurate, personally dismissive. "That design is obviously wrong — here's why." Even if the design is wrong, this feedback creates defensiveness, damages the relationship, and makes the person less likely to share their work next time.

**Manipulative Insincerity (bottom-right):** You neither care nor challenge. Vague positive feedback that means nothing ("great job!"), or indirect negative feedback through a third party. This destroys trust when people realise the feedback wasn't genuine.

### Diagnosing Where You Are

Most engineers default to Ruinous Empathy, not Obnoxious Aggression. Ask yourself:

- Have you ever watched a colleague make a mistake in a meeting and said nothing to spare their embarrassment?
- Have you written a code review comment as "nit: ..." when you actually meant it as a blocking concern?
- Have you described an engineer's performance as "developing" in a calibration when you meant "significantly below bar"?

If yes to any: you are operating in Ruinous Empathy. It is common. It is understandable. And it is failing the people around you.

---

## Types of Feedback at PE Scope

### Peer Feedback (to a colleague of equal seniority)

The most commonly skipped type. Peers are the people most likely to observe your actual day-to-day behaviour — and the most likely to say nothing because of the social cost.

**The rule for peer feedback:** If you would say it to a junior engineer in their position, say it to your peer. Seniority does not exempt someone from feedback; if anything, it makes accurate feedback more important because senior engineers' patterns are more influential and harder for managers to observe.

Delivered as: "I want to give you some feedback about [situation] — is that okay?" The permission-asking is genuine, not performative.

### Upward Feedback (to your manager or a more senior leader)

The rarest type. Most engineers give their manager almost no useful feedback. This is a disservice.

**When to give upward feedback:**
- Your manager's behaviour in a meeting is having a negative effect on team dynamics
- A decision your manager made had a consequence they may not be aware of
- A pattern in how they communicate is creating confusion or reducing trust

**How to give it:** Private, specific, SBI. "In the sprint review last week, when you redirected Alice's demo to cover your concerns about timeline — Alice told me afterward she felt her work wasn't valued. I want you to know the effect it had, in case it's useful." You are not telling your manager what to do. You are sharing an observation that they may not have.

### Feedback vs. Coaching vs. Criticism

| Type | Direction | Goal | When to use |
|------|-----------|------|-------------|
| **Feedback** | About the past | Awareness — "here's what I observed and its impact" | After a specific event |
| **Coaching** | Toward the future | Development — "here's how to grow" | When building long-term capability |
| **Criticism** | About the past | Judgment — "that was wrong" | Almost never productively |

The reason to distinguish: coaching a performance problem is a common mistake. "Let me help you get better at X" when you actually need to say "X happened and it had this consequence" avoids the real conversation and delays the person's opportunity to correct.

---

## Receiving Feedback

Receiving feedback graciously is as much a skill as giving it — and it is modelled from the top. If the principal engineer on the team responds defensively to feedback, the team observes and calibrates: feedback is not safe here.

**The receive-first rule:** Do not respond immediately to feedback. Your first instinct is usually to defend or explain. Neither helps you hear what's being said. Instead:

1. **Receive it without rebuttal:** "Thank you for telling me that." Full stop.
2. **Ask clarifying questions if needed:** "Can you tell me more about what you observed?"
3. **Process separately:** "I want to think about this — can I come back to you in a day or two?"
4. **Follow up:** Whatever you decide about the feedback — whether you agree or disagree — close the loop. "I thought about what you said. I think you're right about X. I don't fully agree about Y because [reason], and I wanted to share that reasoning with you."

**When you disagree with feedback:**  
You are allowed to disagree. What is not allowed is dismissing it without consideration. "I hear what you're saying, and I don't think I agree, but let me sit with it" is honest and respectful. "That's not what happened" in the moment of receiving feedback is defensiveness, not dialogue.

---

## Building a Feedback Culture

Individual feedback skills are necessary but not sufficient. The principal engineer shapes the team's feedback environment.

**Signals that a team has a weak feedback culture:**
- Code reviews are rubber-stamped ("LGTM") rather than substantive
- Post-mortems identify system failures but not process or behaviour failures
- Annual reviews are the first time engineers hear serious concerns about their work
- Engineers describe feedback as "rare" or "only from the manager"

**What the PE can do:**
- Give feedback publicly when it's positive (models that feedback is normal and safe)
- Give feedback in 1:1s immediately after events, not saved for reviews
- Ask for feedback explicitly: "What's one thing I could do differently?" at the end of any collaboration
- Acknowledge when feedback you received changed your approach: "Alice gave me feedback last month about how I was running design reviews — I want to try something different today as a result"

---

## PE vs. Mid-Level on Feedback

| Dimension | Principal Engineer | Senior / Staff Engineer |
|-----------|-------------------|------------------------|
| **Frequency** | Continuous — in the flow of work | Saved for formal reviews or only after serious incidents |
| **Audience** | Peers, seniors, reports, upward | Primarily junior engineers they mentor |
| **Specificity** | SBI — observable behaviour, named impact | "You should communicate better" |
| **Courage** | Names the hard thing directly | Softens until the message is lost (ruinous empathy) |
| **Receiving** | Responds with curiosity, follows up | Defends or dismisses |
| **Culture building** | Models giving/asking publicly; shapes team norms | Participates when feedback culture already exists |
| **Peer feedback** | Gives it regularly, unsolicited | Avoids to protect peer relationships |

---

## Common Interviewer Follow-Up Questions

**"Tell me about a time you gave difficult feedback that was hard to deliver."**

> "I had a senior engineer — technically very strong — who was consistently shutting down junior engineers in design reviews. Not maliciously; they just moved fast and interrupted before junior engineers finished their reasoning. I'd observed it in 3 reviews over 6 weeks. I used SBI: 'In the last three design reviews, you've cut off the junior engineers before they finished — specifically, last Tuesday you interrupted Priya twice while she was explaining her approach to the cache invalidation problem. After both interruptions she stopped contributing. The risk is that she and others stop sharing their thinking, and we lose the perspective of the engineers closest to the implementation.' They were surprised — they hadn't realised the pattern. We talked about what they could do differently: waiting until the speaker finishes, even if they already see the issue. In the next 4 reviews, I saw the behaviour change significantly. Priya's engagement in reviews measurably increased. The reason the feedback landed was specificity — I had named dates, names, and the observable consequence. A vague 'be more patient in reviews' wouldn't have worked."

**"How do you handle someone who is resistant or defensive when you give them feedback?"**

> "Defensiveness is almost always a signal that the person doesn't feel safe, not that the feedback is wrong. My first move is to acknowledge it: 'I can see this is landing differently than I intended — can you tell me what's coming up for you?' Often the defensive response contains information I need: they believe the feedback is factually wrong, or they believe there's context I don't have, or they feel blindsided because this is the first time they're hearing it. If it's a factual dispute, I ask them to walk me through their perspective — I might be wrong, and if I am I want to know. If it's a context issue, I incorporate it and update my assessment. If it's a 'why am I hearing this now?' issue — that's on me. The person is right to be frustrated if this is the first time they're hearing about a 6-month pattern. I own that and commit to being more timely going forward."

**"How do you build a culture where feedback is normal and not feared?"**

> "Two things: frequency and modelling. Feedback that only comes during formal reviews or after crises is associated with bad news. Feedback that comes regularly — after a presentation, after a design review, after an incident — normalises it as a routine part of professional life. The modelling piece is asking for feedback publicly. If I finish a design review and say 'That was useful — what could I have framed better?' in front of the whole team, I'm demonstrating two things: feedback is safe to give, even upward, and it's an expected part of how we improve. The first few times I ask publicly, I get polite nothing. After a few rounds where I visibly incorporate the feedback I receive, people start engaging genuinely. Culture is downstream of behaviour, and my behaviour sets the floor."
