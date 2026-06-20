# SSTAR: Stopping a Project That Was Heading in the Wrong Direction

**Category**: Leadership · Judgment · Technical Courage · Principal Engineer Scope  
**Framework**: SSTAR (Situation → Strategy → Task → Action → Result)  
**Interview context**: "Tell me about a time you had to deliver bad news about a project" / "Describe a time you demonstrated technical courage" / "Have you ever had to stop a project mid-execution? How did you handle it?"

> At PE level, the ability to stop — not just pause, but shut down — a sunk-cost project is one of the highest-leverage and hardest skills to demonstrate. Interviewers are looking for intellectual honesty, organizational courage, and the ability to reframe loss as learning.

---

## Why "Stopping a Project" is a PE-Level Skill

Most organizations are bad at stopping projects. The sunk cost fallacy, political investment, and fear of appearing to have wasted money all combine to keep bad projects running long past their useful life. A PE-level response demonstrates:
- **Technical honesty**: you called the problem before leadership did
- **Organizational courage**: you delivered the assessment even when it was unpopular
- **Proposal skills**: you didn't just kill the project, you redirected the investment
- **Reframing**: you defined what was learned, not just what was lost
- **Follow-through**: you owned the execution of the wind-down, not just the recommendation

---

## SSTAR — Stopping a Real-Time Recommendations Rewrite

### S — Situation

*"At [Company], our recommendation engine served 40M product recommendations per day to 8M active users. The existing engine was a 4-year-old Python service built on a simple collaborative filtering model — rule-based, deterministic, easy to debug. It had one critical limitation: it couldn't personalize recommendations below the segment level (it treated all 'frequent buyers of category X' identically, not as individuals).*

*9 months before I joined the team, the organization had committed to rebuilding the recommendation engine from scratch using a real-time deep learning model — a transformer-based architecture trained on user interaction sequences. The project was 9 months in, had consumed $1.4M in engineering cost, and had 6 engineers assigned full-time. Launch had already slipped twice. The original 6-month estimate was now at 'another 6–9 months.'*

*I was brought in as Staff Engineer to 'help accelerate the project.' Within 3 weeks of joining, I believed the project should be stopped."*

---

### ST — Strategy

*"The instinct to stop a $1.4M project 9 months in, with 6 engineers assigned and executive visibility, is not one you act on quickly or loudly. My first move was to verify my read of the situation rather than assume I was right after 3 weeks.*

*My strategy was: (1) do a structured technical and timeline assessment with specifics before forming a final opinion, (2) present the assessment to the team leads before escalating — they deserved to hear my conclusions from me first, not from their manager, and (3) come in with a concrete alternative proposal, not just a 'stop' recommendation. An engineer who says 'this won't work' without an alternative is identifying a problem; an engineer who says 'this won't work, and here's what will' is solving one."*

---

### T — Task

*"My responsibility was: (1) produce an honest technical and timeline assessment within 4 weeks, (2) present my findings to the engineering lead and head of ML before escalating, (3) prepare a written recommendation for the VP of Product with both the assessment and an alternative path, and (4) if the stop decision was made, own the transition — the wind-down plan, the team communication, and the salvage of reusable work."*

---

### A — Action

**Step 1 — Structured assessment:**

*"I spent 4 weeks doing what the team should have done at the start: A/B testing the existing model's business impact, reviewing the new model's performance metrics, assessing the infrastructure readiness, and scoping the remaining work honestly.*

*Key findings:*

*The existing model's personalization limitation was real but its business impact was smaller than assumed. I ran an analysis comparing recommendations clicked by users in the same segment but with different behavior histories — 78% of the time, the top 5 recommended items overlapped. The 22% delta where personalization would have made a difference mapped to power users (top 8% by engagement). The new model was being built for a problem that affected 8% of users.*

*The new model's offline metrics looked good (recall@10 was 31% vs. 22% for the existing model), but the model had never served real traffic. No online A/B test had been run. The team was planning to launch straight to 100% traffic because 'the offline metrics are strong.' I had seen this pattern fail at a previous company.*

*Infrastructure readiness: the real-time serving infrastructure required to run a transformer model at 40M recommendations/day needed a GPU cluster that we didn't have and hadn't budgeted. The existing estimate of 'another 6–9 months' didn't include the 3–4 months to procure and configure the GPU infrastructure. Actual remaining timeline: 10–13 months.*

*I documented all of this in a 6-page assessment with specific data points for each finding."*

**Step 2 — Present to the team before escalating:**

*"I met with the engineering lead and ML lead together. I showed them my assessment and walked through the data. The engineering lead pushed back on the timeline estimate — he thought the GPU procurement could be accelerated. We spent an hour working through the procurement timeline together; we landed on an optimistic estimate of 8 months remaining, not 10–13.*

*The ML lead was more forthcoming: she acknowledged that the lack of online A/B testing was a risk she'd been uncomfortable with but hadn't escalated because the team was already behind and 'we didn't want to add more work.' That admission was important — it confirmed this wasn't a disagreement about facts, it was a case where the team knew the situation and hadn't surfaced it.*

*I asked both of them: 'If you were starting this project today with what you know now, would you build this?' The engineering lead said yes. The ML lead said no — she'd build a two-tower model (faster inference, no GPU requirement) and A/B test incrementally.*

*That divergence told me what I needed to know. I told them I was going to bring my assessment to the VP of Product and that I'd make sure their perspectives were represented accurately."*

**Step 3 — Recommendation to VP:**

*"I scheduled a 45-minute meeting with the VP of Product and VP of Engineering. I opened with: 'I have an assessment that recommends stopping the recommendation engine rewrite. I want to walk you through the data and the alternative I'm proposing.'*

*I presented 4 findings: (1) the personalization gap affects 8% of users, not 40% as originally framed; (2) we have no online validation of the new model's business impact; (3) remaining timeline is 8–13 months depending on GPU procurement; (4) we have an alternative path that delivers meaningful personalization improvement in 10–12 weeks.*

*The alternative path was the key to making the stop recommendation land. I proposed: A/B test 3 targeted improvements to the existing model — segment splitting (doubling the number of user segments from 50 to 100), recency weighting (down-weight items the user has already seen), and cold-start handling (better behavior for new users). These changes were 3 weeks of engineering work each, could run in parallel, and would give us real data on business impact before committing to a multi-month rebuild.*

*The VP of Product's first question was: 'What do we do with the 6 engineers?' I had a transition plan: 2 engineers had built reusable model serving infrastructure that could be open-sourced internally for other ML projects; 2 engineers would work on the incremental improvements; 2 would move to the Catalog team, which was understaffed.*

*The VPs approved the recommendation the next day."*

**Step 4 — Execution:**

*"The hardest part was the team communication. 6 engineers had spent 9 months on this project. I wrote the all-hands announcement carefully — not 'the project was cancelled' but 'we've completed the investigation phase; based on what we've learned, we're pivoting to an incremental approach.' I named specifically what had been built that was valuable and would be reused. I held 1:1s with each engineer the same day.*

*The engineer who had originally architected the deep learning approach was visibly demoralized. I spent 45 minutes with him. His concern was that the cancellation would look like his fault. I told him directly that the post-mortem I wrote would focus on the process failure — not having online A/B test gating — not on the architectural choice. The architecture was reasonable; the lack of validation gates was the systemic issue. I made sure that framing was in the post-mortem, which I shared with the full team and the VPs."*

---

### R — Result

*"The 3 incremental improvements shipped in 11 weeks:*
- *Segment splitting: +3.1% click-through rate (CTR) in A/B test. Shipped.*
- *Recency weighting: +2.4% CTR. Shipped.*
- *Cold-start handling: +8.7% CTR for new users (top business impact). Shipped.*

*Combined impact: 7.4% improvement in recommendation CTR across all users — compared to the new model's 31% offline recall improvement that had never been validated online.*

*At this point, leadership asked: do we still need the deep learning rewrite? I proposed: run a smaller-scope version. Build a two-tower model (as the ML lead had originally suggested), run it on 10% of traffic as a challenger, and compare to the improved existing model. If the two-tower model wins by >3% CTR on 10% traffic, we scale it. If not, the existing model with incremental improvements remains the production system.*

*That scoped version ran 8 months later. The two-tower model won by 6.3% CTR on the power-user segment. It was scaled to 100% of traffic for users with >30-day history, while the improved existing model served newer users.*

*The final outcome was better than the original plan: we got meaningful personalization for power users (which is where personalization matters most), delivered incremental improvements to all users faster, and spent approximately $600K less in engineering time to get there.*

*The post-mortem process change I drove: any ML project with >4 weeks of effort must have an online A/B test at the 20% completion mark, before committing to full build. That gate is now in the ML team's project checklist."*

---

## Coaching Notes

| Dimension | PE-Level Signal | Mid-Level Signal |
|-----------|----------------|-----------------|
| **First response** | 4 weeks of structured assessment before forming a final opinion | "This project is wrong" after 3 weeks |
| **Stakeholder sequencing** | Presented to team leads before escalating — they deserved to hear it first | Went straight to VP with the assessment |
| **Stop recommendation** | Came with a concrete alternative and transition plan | Presented the problem without a solution |
| **Team communication** | 1:1s with each engineer; post-mortem framed process failure, not person failure | All-hands announcement; moved on |
| **Outcome framing** | Defined what was learned and reused; ran scoped version that ultimately succeeded | "$1.4M wasted" |

---

## Common Follow-up Questions

**"How did you handle the sunk cost pressure — $1.4M and 9 months of work?"**
> "The reframe I used is: the $1.4M is already spent regardless of what we decide today. The question is whether the next $1–2M will produce better returns in this direction or a different one. Sunk cost is a past fact, not a future constraint. What I had to manage was the emotional dimension — people had invested identity, not just money, in this project. That's why the 1:1s and the post-mortem framing mattered as much as the business case."

**"How did you maintain credibility after recommending stopping a major project?"**
> "The incremental improvements shipping in 11 weeks and producing measurable CTR gains was the most important credibility moment. 'You told us to stop that project and nothing useful came of it' would have been a career-limiting outcome. Making the alternative path concrete before recommending the stop — and then personally driving its execution — was how I made sure the stop was a pivot, not a failure."

**"What would you have done if the VPs had rejected your recommendation and told you to continue the project?"**
> "I would have asked what additional information they needed to feel confident in the decision, provided it, and then disagreed and committed. If they still wanted to continue after having all the information, that's their call — they have context I don't have (other strategic bets, investor expectations, team morale considerations). What I wouldn't do is continue leading the project with my heart not in it. I'd have asked for the ML lead to take the technical lead role, with me in an advisory capacity, and been honest with the VP about why."
