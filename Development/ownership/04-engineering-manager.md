# Role: Engineering Manager (EM)

## Core Identity

The Engineering Manager owns **people and team**. They are accountable for the health, growth, and delivery of their engineering team. At FAANG, EMs are explicitly **not the technical decision-makers** — that's the Tech Lead or Principal Engineer. EMs are measured on team output over time, not individual technical contributions.

An EM's job is to make engineers maximally effective: by removing blockers, developing careers, ensuring a healthy team culture, and interfacing with cross-functional partners on behalf of the team.

---

## Primary Accountabilities

### 1. People Development
- Own each direct report's career growth, performance, and promotion path
- Conduct weekly 1:1s — coaching-focused, not status updates
- Write performance reviews calibrated to level expectations
- Create individual development plans (IDPs) for each engineer
- Champion promotions; build the case with artifacts (PRs, designs, leadership moments)

### 2. Team Health & Culture
- Set team norms: how decisions are made, how conflict is resolved, how feedback flows
- Monitor psychological safety — do engineers feel safe raising issues?
- Identify and address burnout before it causes attrition
- Run retrospectives that produce real process changes, not complaint sessions
- Handle interpersonal conflict: mediate, coach, escalate when necessary

### 3. Hiring & Headcount
- Define headcount needs with evidence (velocity, scope, attrition)
- Own the hiring funnel: job descriptions, sourcing, interview loops, offers
- Calibrate hiring bar across the team — resist grade inflation, resist being too stringent on talent
- Own onboarding experience: new engineers productive within 30/60/90 days

### 4. Delivery & Execution
- Translate quarterly OKRs into engineering milestones
- Maintain team velocity and surface risks early (not the week before deadline)
- Remove blockers that engineers can't remove themselves (cross-team, org, resource)
- Shield the team from organizational noise and politics
- Manage stakeholder expectations on timeline, scope, and quality

### 5. Org Design & Headcount Planning
- Right-size the team (typically 6-10 direct reports for a first-line EM)
- Identify when to split teams, merge teams, or reorganize for new initiatives
- Work with directors and VPs on org restructuring

### 6. Cross-Functional Coordination
- Represent the engineering team to PM, Design, QA, Ops, and leadership
- Negotiate scope trade-offs on behalf of the team (not unilaterally)
- Align on delivery dates with stakeholders; surface trade-offs before committing

---

## EM vs Tech Lead vs Principal Engineer

This distinction is **critical** for FAANG principal engineer interviews.

| Dimension | Engineering Manager | Tech Lead | Principal Engineer |
|-----------|-------------------|-----------|-------------------|
| Accountability | People, team health, delivery | Technical quality of team's output | Technical strategy, cross-org influence |
| Decision type | People, process, prioritization | Design choices, code quality, standards | Architecture, platform, tech strategy |
| Scope | One team | One team or project | Multiple teams or org |
| Performance measured by | Team output, attrition, eng health | Team technical health, delivery quality | Technical impact across teams |
| On-call for | Team blockers, morale, hiring | Technical crises, design questions | Architectural emergencies, complex root cause |
| Career ladder | EM → Sr EM → Director | TL → Staff → Principal | Senior → Staff → Principal → Distinguished |
| Reports to | EM → Senior EM → Engineering Director | EM (typically) | EM or Senior EM or Director |

**Key nuance**: At FAANG, the EM-TL split is explicit. EMs are not expected to be the best engineers on the team. In fact, EMs who try to be the technical authority while managing people fail at both. The Tech Lead handles technical direction; the EM handles people direction.

---

## EM Artifacts

| Artifact | Purpose |
|----------|---------|
| 1:1 Notes | Coaching track, action items, patterns over time |
| Performance Review | Semi-annual calibrated assessment of each engineer |
| Individual Development Plan (IDP) | 6-12 month growth plan per engineer |
| Team Charter | How the team operates: norms, escalation, decision rights |
| Headcount Plan | Justification for new hires with ROI argument |
| Hiring Scorecard | Calibrated criteria for engineering interviews |
| Team Retro Action Items | Process improvements tracked and followed up |
| OKR Tracker | Team's quarterly objectives and key results |

---

## Management Frameworks an EM Uses

### Situational Leadership (Blanchard)
Adapt leadership style to each engineer's skill + will:
- **Directing**: High task, low relationship — new engineer, clear instructions
- **Coaching**: High task, high relationship — developing engineer, teach and guide
- **Supporting**: Low task, high relationship — competent but low confidence, encourage
- **Delegating**: Low task, low relationship — senior, autonomous, just check in

### 1:1 Framework
```
1:1 Structure (45-60 min weekly):
├── 5 min: What's on your mind? (engineer drives this part)
├── 10 min: Ongoing projects, blockers, anything stuck?
├── 15 min: Coaching / development topic (IDP-linked)
├── 10 min: Feedback (bi-directional)
└── 10 min: Career / growth conversation (monthly)
```

### Performance Calibration
- At Amazon: bar-raisers calibrate across teams
- At Google: peer group calibration (promo packets reviewed by committee)
- At Meta: 360 reviews feed calibration; managers defend ratings
- Avoid: rating inflation, recency bias, halo/horn effect

### Radical Candor (Kim Scott)
- Care personally + challenge directly = Radical Candor (ideal)
- Care personally + fail to challenge = Ruinous Empathy (most common failure mode)
- Challenge without caring = Obnoxious Aggression
- Neither = Manipulative Insincerity

---

## EM ↔ Principal Engineer Interface

This relationship is one of the most important in engineering org design. **It must be a partnership, not a hierarchy.**

### What Each Owns

| Decision | Owner | How |
|----------|-------|-----|
| Architectural direction | Principal Engineer | Consults with EM on team capacity |
| Sprint priorities | EM + Tech Lead | Aligned with PM |
| Engineer performance | EM | Principal provides input on technical impact |
| Promotion decisions | EM | Principal Engineer provides evidence and endorsement |
| Technical hiring bar | Principal Engineer | EM ensures process runs and fair |
| Team morale | EM | Principal contributes by being a great technical leader |
| Cross-team design alignment | Principal Engineer | EM helps clear organizational blockers |
| Roadmap trade-offs | PM + EM | Principal provides technical feasibility input |

### When Conflict Arises
- EM wants to ship faster; Principal says the architecture needs more time
- **Resolution**: Principal quantifies risk in business terms; EM takes it to PM; decision made with all three aligned
- Never: Principal engineer goes around EM to PM; EM overrides architectural decision without technical understanding

### Principal Engineer Supporting the EM
- Provide clear technical input for performance reviews
- Flag when an engineer is struggling technically — EM may not see it
- Be a technical reference point for hiring — "would I work with this person?"
- Help EMs understand technical risk so they can represent it accurately upward

---

## Common EM Failure Modes

| Failure Mode | Symptom | Impact |
|-------------|---------|--------|
| **Seagull management** | Shows up only to criticize, then leaves | Low morale, engineers hide problems |
| **Technical over-involvement** | EM reviews every PR, overrides designs | Disempowers Tech Lead and seniors |
| **Over-protection from org** | Engineers never see business context | Disconnected team, low ownership |
| **Promotion avoidance** | Never champions engineers upward | Top talent leaves for recognition |
| **1:1 as status updates** | Meeting becomes PM-style check-in | No coaching, no relationship, attrition |
| **Bias toward visible work** | Rewards those who shout loudest | Devalues steady, high-quality work |
| **Headcount hoarding** | Keeps under-performers to protect team size | Drags team velocity, rots culture |

---

## FAANG EM Nuances

### Amazon
- EMs write 6-page narratives for team reviews; no PowerPoint
- Bar Raiser program: independent interviewer with veto power over any hire
- Amazonian Leadership Principles apply to EMs as much as ICs
- Strong "single-threaded owner" culture — one person accountable per initiative

### Google
- Eng Manager / TL split is explicit and formalized (TLM = rare hybrid)
- Promo committees are blind to manager preference — packet must stand alone
- 20% time historically allowed engineers to self-direct; EM must support this
- OKR system: EMs write team OKRs aligned to org OKRs

### Meta
- Move fast culture means EMs are expected to execute and iterate quickly
- Strong emphasis on "disagree and commit" — EM commits to decisions they don't fully agree with
- "People is the product" — recruiting and growing talent is explicit KPI for EM
- IC → EM transitions are common; ICs can go back to IC track

### Netflix
- Freedom + Responsibility: very flat management structure
- EMs are coaches, not directors; engineers have extreme autonomy
- "Keeper test": would I fight to keep this person? If not, act
- Generous severance enables hard conversations

---

## Interview Angles for Principal Engineers

**"How do you work with your manager to ensure technical direction is respected?"**
- Establish a shared vocabulary: I explain technical risks in business terms
- Regular syncs: 1:1 with EM weekly; surface risks before they become blockers
- When we disagree, I bring data: "here's what happens architecturally if we ship this quarter vs next"
- I support the EM in representing technical concerns upward — they're my amplifier, not my gatekeeper

**"How do you handle a situation where the EM wants to promote someone you don't think is technically ready?"**
- I provide specific, evidence-based technical feedback — not vague concerns
- "Here's what I'd expect to see at the next level, and here's where I see gaps"
- I help create a growth plan so the engineer can close the gap
- If I disagree with the final decision, I commit to it but continue coaching the engineer

**"What's your philosophy on the EM / Principal Engineer partnership?"**
- Complementary, not competitive: EM owns the team, Principal owns the architecture
- We align before taking positions to others — disagreements are resolved between us first
- I make the EM look good by making the team technically excellent
- EM clears org obstacles; I clear technical obstacles — both serving the team
