# SSTAR: Defining a 2-Year Platform Roadmap and Getting Buy-In

**Category**: Leadership · Technical Vision · Strategic Planning · Principal Engineer Scope  
**Framework**: SSTAR (Situation → Strategy → Task → Action → Result)  
**Interview context**: "How do you think about technical strategy over a multi-year horizon?" / "Describe a time you built a technical vision that aligned the organization" / "How do you balance long-term platform investment with short-term product needs?"

> At PE level, this question tests whether you can translate a technical vision into business language, negotiate competing priorities, and sustain an investment thesis through the quarterly pressure that will always try to cannibalize platform work for feature development.

---

## Why Long-Term Technical Vision is a PE-Level Differentiator

Most engineers optimize for 1–2 sprints. Senior engineers optimize for the quarter. Principal engineers must hold a 2–3 year view while keeping one foot in the current sprint's reality. The question evaluates:
- Can you identify platform investments that compound in value over time?
- Can you connect engineering investments to business outcomes in language VPs and CPOs understand?
- Do you have the organizational skills to protect long-term investment against short-term pressure?
- Can you phase a roadmap so progress is visible before year 2?

---

## SSTAR — Developer Platform 2-Year Roadmap

### S — Situation

*"At [Company], I was the Principal Engineer for Developer Experience — a team of 8 engineers responsible for internal tooling, CI/CD infrastructure, and service scaffolding. Our 200-engineer organization was scaling rapidly: we'd doubled headcount in 18 months and planned to double again in the next 24.*

*The symptoms were accumulating: median time from merge to production was 47 minutes for a trivial change. New engineers were taking 3–4 weeks to ship their first production feature because of undocumented environment setup and fragmented tooling. Our CI flakiness rate was 23% — nearly 1 in 4 builds was a false negative. Platform tickets to my team had grown 140% year-over-year as the number of teams grew, but my team headcount had grown only 25%.*

*We were reactive — fielding tickets, fixing flaky tests, updating deprecated tooling — and had no coherent story about where we were taking developer experience. I had been in the role for 8 months and hadn't been asked to produce a roadmap. I decided to write one anyway."*

---

### ST — Strategy

*"My strategy had two parts: (1) reframe developer productivity as a business capability, not an engineering cost center, and (2) structure the roadmap as a series of measurable bets with clear success criteria and business linkage so the investment was defensible quarter-by-quarter.*

*The reframing was essential. When I presented developer experience as 'we need better tooling,' I got polite interest and small budgets. When I framed it as 'our 47-minute deploy cycle means a feature with a production bug takes 47 minutes minimum to fix — and with 200 engineers shipping 30+ times per day, we are accumulating 24 hours of deploy wait time per day, every day,' the conversation shifted.*

*I also decided to anchor the roadmap on a DORA metrics baseline — deployment frequency, change failure rate, MTTR, and lead time for changes — so we could measure progress in terms the industry recognized and leadership could benchmark against."*

---

### T — Task

*"My responsibility was: (1) benchmark our current DORA metrics and map them to business impact, (2) identify the highest-ROI platform investments for the next 24 months, (3) phase the work so value was delivered every quarter, (4) present to engineering leadership and get budget approval for 4 additional headcount and 2 dedicated SRE partners, and (5) build a communication cadence that kept product and engineering leadership informed of progress without requiring my constant intervention."*

---

### A — Action

**Phase 1 — Baseline and business case (Weeks 1–4):**

*"I ran a 2-week measurement sprint: instrumented our deployment pipeline to capture lead time at each stage, reviewed 90 days of CI results to quantify flakiness by root cause, and surveyed 60 engineers with a 10-question developer experience NPS survey.*

*The data produced three flagship findings:*
- *Lead time for changes: 47 minutes median, 3.2 hours P95. Industry elite (DORA) benchmark: under 1 hour median, under 24 hours P95. We were median but our P95 was 3× slower than elite.*
- *CI flakiness: 23% of builds required at least one manual retry. Engineers spent an estimated 35 minutes/day waiting for and re-triggering builds. At 200 engineers, that was 116 engineering-hours wasted per day — approximately 3 full-time engineers.*
- *Developer NPS: 28 (mediocre). The lowest-scoring dimension was 'I can ship my work without hitting blockers I don't own.'*

*I translated the 116 engineering-hours/day finding into a cost figure the CFO could engage with. At our fully-loaded engineering cost, we were spending $2.1M per year on CI retries alone. The cost of a 4-person platform team investment that reduced flakiness from 23% to 5%: approximately $800K/year. The ROI was obvious, but no one had quantified it before."*

**Phase 2 — Roadmap definition (Weeks 5–8):**

*"I structured the roadmap as three horizons across 24 months:*

*H1 (Months 1–6): Eliminate the biggest known waste — CI flakiness and deploy pipeline bottlenecks. Goal: flakiness from 23% → 8%, deploy lead time P95 from 3.2 hours → 90 minutes. Measurable within 2 quarters.*

*H2 (Months 7–14): Paved-road developer experience — golden paths for service creation, local development, and testing that work for 80% of use cases without escalating to the platform team. Goal: time-to-first-deploy for a new engineer from 3 weeks → 3 days. Platform ticket volume flat-to-declining despite headcount growth.*

*H3 (Months 15–24): Self-serve infrastructure — teams can provision databases, queues, and caches through a self-serve catalog without platform team involvement. Goal: platform team becomes advisory, not operational. Teams deploy infrastructure changes in hours, not weeks.*

*Each horizon had: a 1-sentence investment thesis, 3–4 measurable outcomes, quarterly milestones, and a dependency map showing which H2 work required H1 completion.*

*I deliberately did not spec H3 in detail. Long-horizon roadmap detail is fictional precision — the world in Month 15 will differ from today. I described the outcome we were aiming for, not the implementation."*

**Phase 3 — Alignment and approval:**

*"I presented to 3 audiences, with distinct framings:*

*Engineering managers (30-minute working session): technical details, quarterly milestones, ask for their input on priority tradeoffs. Result: 2 EMs asked to be involved in the self-serve catalog design. 1 EM flagged that his team's monorepo structure would break our golden path assumptions — incorporated into the plan.*

*VP of Engineering (15-minute executive brief): DORA baseline, 3 headline business impacts ($2.1M wasted on CI retries; 3-week onboarding tax; deploy frequency as a strategic capability), resource ask (4 HC + 2 SREs), 24-month goal state. Handed her a 1-page summary she could share with the CPO. Result: in-principle approval; asked me to present to the CPO.*

*CPO (10-minute slot in leadership meeting): I led with the product angle — 'your feature velocity is gated by deploy frequency. Here's what our current deploy lead time costs in terms of how quickly we can respond to a failed A/B test or a UX bug that's hurting conversion.' Result: CPO became an active sponsor, not just an approver. When budget was challenged in Q3, she was the one defending the investment.*

*Formal approval came 3 weeks after the CPO meeting. 4 new headcount, budget for tooling, and a quarterly review cadence with the VP."*

**Execution — 18 months in:**

*"H1 delivered in 5 months: CI flakiness from 23% to 6.4%. Deploy P95 from 3.2 hours to 74 minutes. We used the 2 months we'd budgeted but not used to begin H2 early.*

*H2's golden path service template became the moment the roadmap became culturally real: the first team to use it deployed a new service to production in 4 hours. That was a Tuesday. By Thursday, 3 other teams had started their own services using the template. I posted the deploy screenshot in #engineering-announcements and tagged the 4 engineers who had built the template. The CPO reposted it to the company Slack.*

*One thing that went wrong: our H2 local development environment tool (based on Docker Compose) broke badly when Apple Silicon Macs rolled out in Month 12. We lost 3 weeks rebuilding the local dev stack for ARM. I surfaced this to the VP immediately — not as an excuse, but with a 2-week recovery plan and a root cause analysis showing that our roadmap had no budget for Apple platform changes. We added a 10% contingency buffer to H3."*

---

### R — Result

*"At the 18-month mark:*
- *DORA deployment frequency: 3.8 deploys/engineer/week, up from 1.1. Top quartile by DORA benchmark.*
- *Change failure rate: 2.8%, down from 11.4%. This was driven partly by CI quality, partly by the golden path's built-in contract test requirement.*
- *MTTR: 52 minutes median, down from 4.1 hours.*
- *Lead time for changes: 22 minutes P50, 68 minutes P95 — both now at DORA elite benchmark.*
- *New engineer time-to-first-deploy: 2.5 days, down from 3 weeks.*
- *Platform ticket volume: +8% despite 40% headcount growth — effectively flat per-engineer.*

*Business impact: the CPO cited faster deploy frequency in a board presentation as one of the engineering capabilities that allowed us to run 3× more A/B tests per quarter than the prior year.*

*The roadmap process itself became reusable: I ran it again for the Security Platform team when they asked for the same type of 2-year investment framing. I coached their lead through the process. He's now doing it independently for his third cycle."*

---

## Coaching Notes

| Dimension | PE-Level Signal | Mid-Level Signal |
|-----------|----------------|-----------------|
| **Business framing** | Translated CI flakiness to $2.1M annual cost and board-level velocity metrics | "We need to fix our CI pipeline because it's slow" |
| **Stakeholder differentiation** | 3 distinct presentations for EMs, VP, CPO — each with different framing | One deck sent to all stakeholders |
| **Roadmap structure** | 3 horizons with measurable outcomes; H3 described by goal state, not spec | Detailed 2-year sprint plan that became fiction by Month 6 |
| **Sponsor cultivation** | Made the CPO an active defender of the budget | Got approval, moved on |
| **Handling setbacks** | Surfaced Apple Silicon issue immediately with recovery plan; added contingency to H3 | Stayed quiet until deadline missed |

---

## Common Follow-up Questions

**"How do you protect long-term platform investment from being cannibalized for feature work?"**
> "Two mechanisms: active sponsor and visible metrics. The CPO became a sponsor, not just an approver, because I spent time connecting the roadmap to her problem (A/B test velocity) rather than mine (CI flakiness). When a VPE tried to pull 2 of my engineers for a product sprint in Month 9, the CPO pushed back first. I didn't have to fight the battle alone. The DORA metrics dashboard was the other protection: when leadership could see deployment frequency trending up in real time, the 'pause platform work' argument had a visible opportunity cost."

**"How did you decide which metrics to track?"**
> "I used DORA's four key metrics because they're industry-standard, which meant I could benchmark against external data and leadership didn't have to take my word for whether our performance was good or bad. I also chose metrics that the platform team could actually move — not revenue metrics that are many steps removed from our work. The tricky one was developer NPS: it's subjective and gameable, but it captures things DORA metrics miss (e.g., cognitive load, interrupt-driven work). I tracked it alongside DORA but didn't treat it as primary."

**"What would you have done if the CPO had said no?"**
> "If the full investment was rejected, I would have asked for a 90-day pilot: fund H1 (the CI flakiness work) as a standalone project with no commitment beyond that. The H1 business case was self-funding — the $2.1M waste reduction from CI retries justified the investment cost within the quarter. Once H1 results were in, the conversation about H2 would have had a different quality: I'd be asking for more investment based on demonstrated results, not a promise."
