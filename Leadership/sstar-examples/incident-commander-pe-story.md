# SSTAR: Leading a High-Stakes Production Incident as Principal Engineer

**Category**: Leadership · Behavioral · Incident Management · Principal Engineer Scope
**Framework**: SSTAR (Situation → Strategy → Task → Action → Result)
**Interview context**: "Tell me about a time you led a major incident response" / "Describe a time you had to make a high-stakes technical decision under pressure" / "How do you handle failures at scale?"

> At PE level, the behavioral question is not about whether you fixed a bug — it is about how you shaped the outcome for the organization, what you changed systemically, and how you demonstrated judgment under ambiguity.

---

## Why Incident Leadership is a PE-Level SSTAR

An incident SSTAR at PE scope demonstrates:
- **Technical depth**: you understood the system well enough to form hypotheses quickly
- **Organizational leadership**: you coordinated across teams without authority
- **Systems thinking**: your fixes addressed the class of problem, not just the instance
- **Communication**: you kept executive stakeholders informed without panic
- **Culture building**: you drove blameless post-mortem practices and reliability investment

Interviewers at FAANG PE level are evaluating whether you can operate effectively at organizational scale under pressure.

---

## SSTAR Template — Checkout Payment Incident

### S — Situation

**Set the scale and stakes immediately.** The interviewer must understand why this mattered.

---

*"At [Company], I was the Staff Engineer for our Payments Platform — a system processing $2M in GMV per hour, serving 15 million customers across 12 countries. We had an 11-day streak where our checkout SLO (99.9% success rate) was at 98% budget remaining — the best we'd had in a year.*

*At 2:17 PM on a Tuesday, our checkout error rate went from 0.03% to 6.8% in under 90 seconds. At that burn rate, we would exhaust our entire monthly SLO budget in 2 hours. In 20 minutes, we'd have burned through what a normal month produces. I was the IC on that incident."*

---

**What makes this PE-level**:
- Concrete scale ($2M/hr, 15M customers) — not abstract
- Stakes are quantified in SLO terms, not just "it was bad"
- The framing establishes context before diving into action

### ST — Strategy

**State your approach before listing actions.** This is what separates PE-level answers from mid-level answers.

---

*"My strategy was to separate the roles immediately — IC controls the process, TL controls the investigation — and apply our mitigation hierarchy: rollback first, understand second. I've seen incidents get worse when engineers try to understand root cause before mitigating. MTTR is the priority.*

*I also made a decision at the outset: this was a SEV-1 by our burn rate definition, but given the trajectory, I escalated it to SEV-0 protocols at T+8 minutes before we hit the 20-minute threshold — because waiting for the threshold to officially pass before activating the full response would have wasted 12 minutes of mitigation time."*

---

**What makes this PE-level**:
- You made a proactive judgment call (escalating early) — not just following the playbook
- You articulated a strategy, not just a series of actions
- You demonstrate awareness of the IC/TL separation pattern

### T — Task

**Your specific responsibility in the situation.**

---

*"My responsibility as IC was to: own the coordination, protect the TL's ability to investigate without distraction, manage stakeholder communication, and make the decision to escalate or mitigate in a way that balanced speed against risk of making things worse. I also had to make a judgment call about whether to use our nuclear option — taking checkout offline and redirecting users to a 'temporarily unavailable' message — if the normal mitigation path wasn't resolving quickly."*

---

### A — Action

**Be specific about what you personally did.** The interviewer is evaluating your judgment at each step.

---

*"First minute: I opened the incident channel, assigned our most senior payments engineer as TL, pulled in our Comms Lead, and posted the first external status page update — 'investigating reports of checkout issues' — before we knew anything. Customers seeing errors for 8 minutes with no status page update is worse than a vague status page update. We can always update with more detail; we can't un-alarm customers who've already called support.*

*Minutes 2–5: While TL started investigating, I was on the phone with our VP of Engineering providing a 60-second situation brief: severity level, user impact estimate, what we were doing. I kept the call under 90 seconds — she didn't need my analysis, she needed to know whether to cancel her customer meeting. She cancelled. Good call.*

*Minutes 5–15: TL messaged me: 'traces show Stripe API calls taking 2.9 seconds — above our 2-second timeout. Stripe status page shows no incident. Correlating with deploy log...' — T+7 minutes, TL found that payment-service v2.3.4 had been deployed at T-12 minutes (12 minutes before the first alert). The new version changed our Stripe timeout from 3 seconds to 500ms. At 500ms, we were timing out on 94% of Stripe calls that normally take 800-1200ms.*

*I made the call at T+12: 'Initiate rollback of payment-service to v2.3.3.' I did not wait for a second opinion. The evidence was clear — the change was identified, the rollback was low-risk, and every additional minute was costing us $33,000 in GMV. I communicated the decision to the channel before executing it, so TL and the broader team knew not to make additional changes while the rollback was in flight.*

*T+15: Rollback complete. Error rate dropping: 6.8% → 2.1% → 0.4% → 0.08% over 4 minutes.*

*T+20: I ran a structured stability check — not 'the error rate looks better,' but: 'SLO burn rate is now 0.8× [below the 1× baseline], P99 latency is 290ms [pre-incident was 310ms], no active customer escalations in the support queue.' Three minutes of clean metrics before I declared stability.*

*T+25: Resolution declared. External status page updated with duration, user impact summary, and post-mortem ETA. I briefed the VP and CEO's chief of staff with a 3-sentence summary: what happened, what we did, what we're doing to prevent recurrence.*

*Where my PE scope showed up was in what I did AFTER the incident. I reviewed our incident history and found this was the THIRD timeout-related payment incident in 18 months. The previous two post-mortems had 'add better documentation' as action items — neither fixed the underlying gap.*

*I wrote a post-mortem that identified the systemic pattern and proposed an architectural fix: a timeout policy service that continuously measures external API P99 latency and enforces at deploy time that our configured timeouts exceed (measured P99 + 20% buffer). I presented this to the VP of Engineering as a 3-week engineering investment that would eliminate an entire class of incidents. It was approved and shipped 6 weeks later."*

---

**What makes this PE-level**:
- You made a time-sensitive escalation decision before the threshold was hit
- You quantified the cost of delay ($33K/min GMV) to justify the rollback decision without consensus
- You ran a structured stability check rather than declaring resolution on instinct
- You identified the systemic pattern across 3 incidents, not just fixed this one
- You drove an architectural change that closed the class of incidents — this is PE-scope impact

### R — Result

**Quantify impact across dimensions: immediate, medium-term, organizational.**

---

*"Immediate: We restored checkout in 25 minutes. The incident burned 18% of our monthly SLO error budget — significant, but not budget-exhausting. We lost approximately $825,000 in GMV during the outage window — our estimate was $1.1M when I briefed the VP at T+90 seconds, so the rapid recovery beat the projection.*

*Medium-term: The post-mortem drove 5 action items, all completed within 30 days. The timeout policy service shipped 6 weeks later. In the 12 months after the fix, we had zero timeout-configuration incidents across all external API integrations — across Stripe, Twilio, SendGrid, and 4 other providers.*

*Organizational: I used this incident as the opportunity to establish a formal error budget review process. Before this, reliability was discussed informally after incidents. After this, we have a monthly reliability review where each team presents their SLO burn rate, budget consumed, and action item status. The VP of Engineering and product leads attend. Reliability became a first-class conversation, not just an engineering post-incident task.*

*The reliability review format I proposed is now used across 3 other product areas at [Company]."*

---

## Coaching Notes — What Interviewers Are Looking For

### At PE Level, Evaluate These Dimensions

| Dimension | What PE Looks Like | What Mid-Level Looks Like |
|-----------|-------------------|--------------------------|
| **Decision-making** | Made rollback call with incomplete info, based on risk calculus and cost of delay | Waited for consensus or certainty before acting |
| **Scope of impact** | Identified the class of incidents; drove architectural fix | Fixed this specific incident; wrote "add a test" |
| **Stakeholder management** | Proactively briefed executives with 60-second summary; separated their need from yours | Waited for executives to ask; gave 10-minute technical brief to people who needed a 60-second business brief |
| **Systems thinking** | Connected this incident to 2 prior incidents; proposed policy service to close the class | Wrote a post-mortem about this incident in isolation |
| **Process creation** | Established error budget review that became organizational norm | Participated in post-mortems |
| **Blameless framing** | "The system allowed a human to set a timeout without validation" | "The engineer changed the timeout without checking" |

### Common Interviewer Follow-up Questions

**"How did you make the rollback decision so quickly without more analysis?"**
> "The decision calculus was: rollback risk is low (returns to last known-good state), cost of delay is high (>$30K/min at peak), and the evidence was sufficiently correlated (deploy at T-12 matches symptom onset at T+0 exactly). I didn't need certainty — I needed the risk of rolling back to be lower than the cost of not rolling back. That math was clear at T+12 minutes."

**"What would you have done if rollback didn't fix it?"**
> "We had a mitigation hierarchy. Next step after rollback failure would have been: check if the problem was deploy-independent by examining traces from both v2.3.3 and v2.3.4. If rollback truly didn't help, we'd look at: Stripe-side (their status page, their support), infrastructure (network route changes, TLS cert expiry), database (connection pool exhaustion). I had already tasked the TL to run parallel investigation during the rollback so we had that analysis ready."

**"How do you handle the pressure of making high-cost decisions quickly?"**
> "I've found that preparation removes most of the pressure. If I've pre-agreed with my team and my manager on our mitigation hierarchy and decision criteria, then in the moment I'm not making a judgment call — I'm applying a pre-made framework. The preparation also helps others trust the decision. The harder pressure is when the situation is genuinely outside the pre-agreed framework — in those cases, I articulate my reasoning clearly, make the call, and take ownership of the outcome."

**"What was the hardest part of this incident?"**
> "The hardest part was the 5 minutes between when I first looked at the traces and when the TL confirmed the deploy correlation. I had a strong prior that it was the deploy — the timing was too perfect — but I resisted the urge to order the rollback before the TL confirmed it. Acting on a hunch and having it be wrong during an incident erodes team trust and can make the situation worse. Waiting for one piece of corroborating evidence before escalating from hypothesis to action is the discipline that separates good IC performance from bad."

---

## Alternative SSTAR Angles (for variety across interviews)

### Angle 2: Improving the Detection System (proactive reliability)

Situation: Our MTTD (mean time to detect) was 8–15 minutes for checkout incidents because we were alerting on raw error rate rather than SLO burn rate. Customers were calling support before our alerts fired.

Strategy: Redesign the alerting framework — burn rate multi-window alerting, exemplars in histograms for trace correlation.

Task: Lead the design and adoption across 6 service teams without direct authority.

Action: Built proof-of-concept for payments; ran 30-day retrospective showing MTTD dropped from 12 min to 2.5 min; presented findings at engineering all-hands; wrote the alerting standards document; held office hours for other teams.

Result: MTTD dropped from 12 minutes to 2.5 minutes org-wide. Estimated 4 SEV-2 incidents per quarter become SEV-3 because of earlier detection.

### Angle 3: Building the On-Call Culture (organizational change)

Situation: On-call rotation had 40% burnout rate. Engineers were dreading the rotation. Alerts were noisy (200+ per week, 80% requiring no action). Post-mortems were blame sessions masquerading as learning.

Strategy: Attack the three components — alert quality, runbook quality, and blameless culture — simultaneously but with different tactics for each.

Task: Lead the transformation of on-call culture for the Payments Platform (12 engineers).

Action: (1) Alert audit: reviewed 4 weeks of PagerDuty data; eliminated 60% of alerts that fired but required no action; raised thresholds based on SLO burn rate not raw metrics. (2) Runbook sprint: 2-week sprint where engineers each owned 3 runbooks; reviewed against "would a new engineer be able to resolve this at 3 AM?" standard. (3) Post-mortem rewrite: facilitated the first blameless post-mortem after our next SEV-2; modeled the "system is the defendant" framing explicitly.

Result: Alert noise reduced from 200/week to 35/week. On-call escalations (calls to people who aren't on-call) dropped 70%. In our next survey, 0 engineers cited on-call as a burnout factor (was 40%). This model was adopted by 2 other teams.
