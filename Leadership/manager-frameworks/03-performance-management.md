# Managing Performance at Principal Scope

**Category:** Manager Frameworks · Performance Management · Calibration  
**Framework:** Results × Behaviours Matrix · Performance Conversation Structure  
**Interview context:** "How do you handle a sustained underperformer?" / "Tell me about a time you had a hard performance conversation." / "How do you participate in calibrations as a principal engineer?"

> A sustained performance problem that goes unaddressed is not kindness to the underperformer. It is unfairness to the team that carries the gap, and it communicates that standards don't matter.

---

## Why Performance Management is a PE-Level Skill

Line managers own performance management formally — the reviews, the ratings, the PIPs, the HR conversations. A principal engineer without direct reports might assume this is not their domain. That assumption is wrong.

Principal engineers shape performance outcomes in three ways:
1. **Calibration influence:** You are often in calibration meetings as the technical voice. Your assessment of whether an engineer is performing at bar shapes their rating.
2. **Informal performance signals:** You observe technical quality, collaboration patterns, and ownership behaviours that the manager may not see directly. Your feedback to the manager is an input to their formal assessment.
3. **Coaching before it becomes a formal problem:** You are often the person who can identify a performance trajectory problem early — when coaching can still change the outcome — before it reaches a formal process.

The principal engineer who stays silent about a performance problem they've observed, waiting for the manager to "handle it," is failing the team and the engineer.

---

## The Performance Matrix: Results × Behaviours

Performance at its simplest is two-dimensional:

```
                    Results
                       │
    High Behaviour     │     High Results
    Low Results        │     High Behaviour
    ─ ─ ─ ─ ─ ─ ─ ─ ─ ┼ ─ ─ ─ ─ ─ ─ ─ ─ ─
    "Hero"             │     "Model"
    "Well-meaning but  │     (promote, retain,
     not delivering"   │      challenge more)
                       │
Behaviour ─────────────┼─────────────────────
 (how they work)       │
                       │
    Low Results        │     High Results
    Low Behaviour      │     Low Behaviour
    ─ ─ ─ ─ ─ ─ ─ ─ ─ ─     ─ ─ ─ ─ ─ ─ ─ ─
    "Exit candidate"   │     "Brilliant Jerk"
    (PIP or out)       │     (hardest case)
                       │
                    Results
```

**Results:** Did they deliver what was expected? At what quality? On time?  
**Behaviours:** How did they work? Collaboration, communication, ownership, growth mindset, treatment of teammates.

### The Four Quadrants

**High Results / High Behaviour (Model):**  
These engineers are doing the right things in the right way. Retain them aggressively. Challenge them with harder scope. Promote them when they're ready. The most common mistake with this quadrant: undercommunicating your appreciation and making them feel taken for granted.

**Low Results / High Behaviour (Well-meaning):**  
Committed engineers who aren't hitting the bar technically. This is a coaching and capability problem. Intervention: identify the specific gaps, provide development resources, set clear milestones. Most people in this quadrant respond well to direct, supportive coaching.

**High Results / Low Behaviour (Brilliant Jerk):**  
The hardest category. This engineer ships impressive technical work but is toxic to the team — dismissive in reviews, hoards knowledge, takes credit, creates fear of disagreement. The results make managers reluctant to act. The behaviour destroys team culture over time.

**The data on brilliant jerks:** Research consistently shows that one toxic high-performer on a team reduces overall team output by more than the individual contributes. The damage is distributed: collaborative output drops, psychological safety drops, good engineers leave, other high-performers become uncomfortable.

**The principal engineer's role:** Don't soften the behaviour feedback because of the technical output. "You're technically excellent AND the way you engage in design reviews is damaging this team" — both things are true simultaneously.

**Low Results / Low Behaviour (Exit candidate):**  
If sustained over multiple quarters despite clear feedback, and a PIP does not produce improvement, exit is the right outcome. Being clear-eyed about this is part of the job.

---

## Coaching Problem vs. Performance Problem

Before intervening, diagnose correctly. The wrong intervention wastes time and damages trust.

| Indicator | Coaching problem | Performance problem |
|-----------|-----------------|---------------------|
| **Duration** | Recent / new pattern | Sustained (2+ quarters) |
| **Pattern** | Specific gap in a defined area | Broad underperformance across dimensions |
| **Effort** | High effort, wrong approach | Low effort, checked out |
| **Response to feedback** | Engages, tries to change | Defensive, doesn't change behaviour |
| **Self-awareness** | Recognises the gap | Attributes problems externally |
| **Trajectory** | Improving with coaching | Flat or declining despite intervention |

**Coaching problem response:** GROW coaching, targeted development, concrete milestones, regular check-ins.

**Performance problem response:** Direct feedback with documented expectations, formal check-in cadence, escalation to manager if no improvement over a defined period.

The critical error is treating a performance problem as a coaching problem indefinitely. If an engineer has been "being coached" for 12 months on the same issues with no trajectory change, it is not a coaching problem anymore.

---

## The Hard Performance Conversation

Most managers and principals avoid these conversations, or have them so softened that the engineer walks away unclear that they have a problem. The most common failure: the manager believes they gave hard feedback; the engineer heard encouragement.

### The Conversation Structure

```
1. State the purpose directly
"I want to talk to you about your performance. I have some concerns
I need to be direct with you about."
Not: "I wanted to check in on how things are going..."

2. Describe the pattern with specifics (SBI)
Not isolated incidents — a pattern over a defined period.
"Over the last quarter, three of your projects missed the agreed
milestone dates. In the Q2 platform migration, you committed to
completing the auth service work by June 15; it shipped July 3.
In the API versioning work, the first working implementation was
delivered 2 weeks after the committed date."

3. State the impact clearly
"The downstream consequence has been that two other teams had to
delay their work waiting on your deliverables. That's a team-level
reliability problem, not just a scheduling problem."

4. State what needs to change, specifically and time-bound
"What I need to see change: you commit to realistic dates, and when
you see a risk of missing them, you flag it at least 5 business days
before the deadline so we can adjust. I need to see this consistently
over the next 6 weeks."

5. Ask for their understanding
"I want to make sure I've been clear. What did you hear?"
(Not "Does that make sense?" — that invites "yes" without confirmation.)

6. Ask for their perspective
"Is there anything I'm missing about the context here?"
(Genuinely — they may have information you don't.)

7. Document
Same day: email or written note summarising what was discussed,
what was agreed, and the timeline. Not for HR — for shared clarity.
```

### The Calibration Test

After the conversation, ask yourself: if this engineer were to describe the conversation to a trusted friend, would they say "I got some hard feedback and I know I need to change X by Y date" — or would they say "my manager gave me some feedback about being more timely"?

If the answer is the second — the conversation was not hard enough. Try again with more specificity.

---

## PIPs: When They Work and When They're Theater

A Performance Improvement Plan (PIP) is a formal documented process with specific goals, a defined timeline, and explicit consequences for non-improvement. When used correctly, they are a genuine last attempt to help someone succeed. When used incorrectly, they are a documentation exercise before an exit that has already been decided.

### A PIP that works:
- Is not the first time the person has heard serious concerns about their performance
- Has specific, measurable success criteria ("delivers agreed milestones on time for 6 consecutive weeks" not "shows improvement in delivery")
- Has a realistic timeline (6–12 weeks — enough time to demonstrate change)
- Comes with genuine support: coaching, resources, check-ins
- Is initiated when there is still a genuine belief that the person can succeed

### A PIP that is theater:
- Arrives as a surprise — the first formal signal of a problem the manager has been observing for a year
- Has vague success criteria that can be interpreted either way
- Has a timeline that is unrealistically short
- Is initiated after the manager has already concluded the person should exit
- Is used purely for legal/HR documentation purposes

**The principal engineer's role:** If you are asked to participate in a PIP (as a coach, a technical mentor, or a calibration participant), ensure it is genuine. A PIP as theater is unfair to the engineer — it wastes 6–12 weeks of their time when they could be job-searching or in a better-fit role. If the decision has already been made, the more honest path is a direct conversation about the fit.

---

## Top Performer Retention

High performers leave quietly. They don't complain — they update their LinkedIn and take a call from a recruiter.

**Why high performers leave:**
- Feeling undervalued or unrecognised
- Stagnation — no new challenges, no growth trajectory
- Culture: a brilliant jerk being tolerated signals that behaviour is acceptable
- Management: feel micromanaged or unsupported
- Compensation: for senior engineers, the market is active and they know their value

**What the principal engineer can do:**
- Name their contributions explicitly, in public, regularly. "Alice's work on the streaming pipeline was the reason we hit the Q3 deadline" — in the team retro, in an all-hands, in writing.
- Advocate loudly in calibrations. "This person is performing at the next level. I want to make the case for a promotion this cycle." If you don't make the case, the manager may not have enough context to.
- Give them the harder, more interesting problems. High performers want stretch. If they're coasting, they're leaving.
- Have the "what do you want next?" conversation proactively — not in response to a resignation.

**The retention conversation:**  
"I want to make sure you're getting what you need to stay engaged and growing. What does your ideal next 12 months look like?" Have this annually, not just in a crisis.

---

## Principal Engineer's Role in Calibration Meetings

Calibration is the process where managers compare engineer performance across teams and align on ratings. As a principal engineer (non-manager), you are often invited as the technical voice.

**What you should bring:**
- Specific, evidence-based observations: "Alice's technical execution on the platform migration was genuinely exemplary — she identified a failure mode in our rollout plan that would have cost us 2 additional weeks"
- Honest assessments of behaviour, not just output: "Bob ships solid code but his collaboration in cross-team reviews has been a persistent friction point that I've heard from multiple teams"
- Calibrated language: know the difference between "performing solidly at this level" and "exceeding this level consistently"

**What to avoid:**
- Vague advocacy without evidence: "She's great — I think she should get the top rating" (not useful)
- Lobbying for people you like vs. people who performed: calibration should be evidence-based, not relationship-based
- Silence: if you've observed something relevant and don't say it, you're failing the process

**The recency bias correction:**  
Calibration often over-weights the last 6 weeks. If an engineer had a strong first 3 quarters and a difficult Q4, advocate for the full-year picture. "I want to make sure we're rating the year, not the quarter."

---

## PE vs. Mid-Level on Performance Management

| Dimension | Principal Engineer | Senior / Staff Engineer |
|-----------|-------------------|------------------------|
| **Problem detection** | Identifies performance patterns early, before formal process | Notices problems but waits for the manager to act |
| **Hard conversations** | Has them directly, promptly, with specifics | Avoids or softens to the point of obscuring the message |
| **Calibration participation** | Comes with evidence; advocates specifically; corrects bias | Attends but defers to managers; little independent input |
| **Brilliant jerk response** | Names the behaviour alongside the output; doesn't soften | Ignores behaviour because "technically they're great" |
| **PIP assessment** | Assesses whether a PIP is genuine or theater; acts accordingly | Doesn't engage with the process |
| **Top performer retention** | Advocates loudly and specifically in calibrations; gives public recognition | Assumes someone else will notice |
| **Coaching vs. performance** | Diagnoses correctly; uses different interventions | Treats all underperformance as a coaching problem indefinitely |

---

## Common Interviewer Follow-Up Questions

**"Tell me about a time you had to deliver a hard performance message."**

> "I had a senior engineer who was technically solid but persistently late on cross-team commitments. Three teams had flagged it to me in separate conversations over a quarter. The manager was aware but had been having soft check-ins that weren't changing the pattern. I had a direct conversation with the engineer. I named the pattern specifically — three deliverables in Q2, the specific dates committed vs. delivered, the downstream impact on the other teams. I was clear: 'This isn't a one-time miss. It's a pattern, and it's affecting the teams that depend on you.' I also asked for their perspective — they surfaced a dependency they hadn't flagged that was genuine. We worked out a practice: when any deadline is at risk, they flag it 5 working days before the date. Over the following 6 weeks the pattern changed noticeably. The key was being specific rather than vague, and being early enough that there was time to course-correct."

**"How do you handle a brilliant jerk — someone who delivers great technical work but is toxic to the team?"**

> "I address the behaviour separately from the technical output — and I'm explicit that both things are true simultaneously. 'Your technical contributions on the platform have been genuinely impressive. And the way you engage in design reviews is damaging how the team works together. Both of these things are real.' The resistance I often encounter is 'but the technical output is high' — as if that justifies the behaviour. I push back on that framing: the technical output is measurable and visible; the impact on the team's psychological safety, on junior engineers who stop contributing, on the senior engineers who start looking for other jobs — that's also real, just harder to measure. I've found that most brilliant jerks aren't malicious — they have low awareness of how their behaviour lands. Specific, well-observed feedback is often genuinely new information. That said, if the behaviour doesn't change after direct feedback, it becomes a performance issue regardless of the technical output."

**"How do you participate in calibration as a non-manager?"**

> "I come with evidence, not advocacy. Before the calibration meeting I go through my interactions with the engineers in scope and document specifics: who demonstrated initiative in a cross-team problem, whose code reviews were substantive vs. rubber-stamped, who I saw grow and who I saw stagnate. In the meeting, I offer that evidence when it's relevant — and I name both positive and negative observations. I've been in calibrations where a strong engineer wasn't getting appropriate recognition because the manager only had visibility into one project — I've surfaced observations from other projects I'd been involved in. I've also corrected recency bias: 'We're talking about her Q4 miss, but her first three quarters were genuinely strong and I want to make sure we're rating the year.' My goal isn't to advocate for the people I like. It's to make sure the calibration is based on evidence from the full year and full scope of their work."
