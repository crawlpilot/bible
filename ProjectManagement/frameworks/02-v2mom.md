# V2MOM — Vision, Values, Methods, Obstacles, Measures

## What V2MOM Is

V2MOM was created by Marc Benioff at Salesforce and has been used to run the company since its founding in 1999. It is Salesforce's operating system — every team from the CEO to individual contributors writes a V2MOM that cascades from the one above it.

Unlike OKRs (which are quarterly), V2MOM is typically an **annual** strategic document. It answers the fundamental question: "Why do we exist, what do we believe, how will we get there, what's in the way, and how will we know we succeeded?"

**When to use it over OKRs**: V2MOM is better for setting annual direction and connecting work to values. OKRs are better for quarterly execution tracking. Many organizations use both: V2MOM sets annual direction, OKRs track quarterly progress toward it.

---

## The Five Components

### V — Vision
A single sentence describing the desired future state. The "north star" that everything else serves.

- Should be ambitious — a vision you can't achieve in one year
- Should be qualitative and inspirational
- Should not change quarterly

**Example (engineering org)**:
> "Be the engineering platform that enables any team at the company to build and ship production-grade services without infrastructure expertise."

### V — Values
The principles and beliefs that will guide decision-making on the path to the vision. Non-negotiable.

- 3–5 values maximum (more = dilution)
- Values are used to resolve conflicts: "Given two options, which one aligns better with our values?"
- Should be specific enough to be actionable, not generic ("integrity," "excellence")

**Example**:
> 1. Developer experience is a first-class product concern — friction is a bug
> 2. Systems over heroes — reliability comes from design, not individual effort
> 3. Simplicity over completeness — a focused platform everyone uses beats a complete platform nobody understands
> 4. Data before opinion — every significant decision is backed by measurement

### M — Methods
The specific actions, initiatives, and strategies you will execute to achieve the vision.

- Ordered by priority (most important first)
- Each method should be concrete and actionable
- Typically 4–8 methods
- This is the "how" — the work the team will actually do

**Example**:
> 1. Launch a self-service developer portal (Backstage) with golden-path service templates
> 2. Reduce mean deployment pipeline duration to < 10 minutes across all services
> 3. Build automated canary analysis that eliminates manual deployment approval for standard services
> 4. Migrate 80% of teams from shared VMs to Kubernetes-based infra
> 5. Establish SRE practice with SLO ownership for all platform services

### O — Obstacles
The known challenges, risks, and blockers that could prevent achieving the vision. Honest and specific.

- This is the most important component that other frameworks omit
- Forces you to name risks before they become surprises
- Makes your plan credible: you've thought through what could go wrong

**Example**:
> 1. Legacy monolith dependencies prevent clean Kubernetes migration without application changes from product teams
> 2. Platform team is 30% under-staffed for the scope of migration work
> 3. Product teams are skeptical of golden path adoption — they believe their service is "different"
> 4. No current observability tooling to measure developer experience objectively
> 5. On-call burden consumes 40% of team capacity — limits ability to invest in improvement

### M — Measures
The specific, quantified outcomes that will prove the vision was achieved. These are essentially leading and lagging indicators.

- Must be measurable (not "improve developer experience" — that's a vision)
- Include both leading indicators (in-progress signals) and lagging indicators (final outcomes)
- Typically tied to the Methods

**Example**:
> 1. 90% of teams using golden-path pipelines (measure of Method 1)
> 2. Mean deployment pipeline < 10 minutes for 95% of services (Method 2)
> 3. Zero manual deployment approvals required for services passing automated canary (Method 3)
> 4. 80% Kubernetes migration complete (Method 4)
> 5. Platform SLO compliance: 99.9% availability for all platform services (Method 5)
> 6. Developer NPS for platform team > 40 (outcome measure for overall vision)

---

## Full V2MOM Example: Engineering Platform Team

```
VISION
  Become the invisible backbone of product engineering — every team ships confidently 
  without thinking about infrastructure.

VALUES
  1. Paved roads over guard rails — make the right way easy, not mandatory
  2. Measure, don't assume — instrument before optimizing
  3. Reliability is a feature — downtime is a product bug
  4. Reduce cognitive load — every abstraction should simplify, not shift complexity

METHODS (priority ordered)
  1. Launch self-service developer portal with 10 service templates by end of Q1
  2. Reduce CI/CD pipeline p50 duration from 40 min to 12 min by end of Q2
  3. Migrate 3 most critical shared services to Kubernetes by end of Q3
  4. Establish SLO framework and on-call escalation path for all platform services by Q2
  5. Run quarterly engineering experience survey and publish results to all teams

OBSTACLES
  1. Two team members are on-call rotation for legacy systems consuming 25% of capacity
  2. Golden path requires breaking changes to 40% of existing service configurations
  3. No executive sponsor for the Kubernetes migration — product VPs are risk-averse
  4. Current monitoring stack can't measure developer experience metrics
  5. Budget approval for Backstage license is in procurement for 6 weeks

MEASURES
  1. Golden path adoption: 90% of new services, 60% of existing services by end of year
  2. CI/CD p50 pipeline duration: < 12 min (from 40 min)
  3. Platform availability SLO: 99.9% for all tier-1 platform services
  4. Developer NPS: > 40 (from current -5)
  5. Kubernetes migration: 3 critical services fully migrated and stable
  6. On-call burden: < 15% of team capacity consumed by reactive work (from 40%)
```

---

## V2MOM vs. OKRs

| | V2MOM | OKRs |
|--|-------|------|
| Cadence | Annual | Quarterly |
| Includes "why we believe" | Yes (Values) | No |
| Includes risks | Yes (Obstacles) | No |
| Execution tracking | Light (Measures at year-end) | Heavy (weekly/bi-weekly check-ins) |
| Cascades | Yes (CEO → org → team) | Yes (company → team) |
| Grading | No formal grading | 0.0–1.0 per KR |
| Best for | Setting annual direction + culture | Quarterly execution + accountability |
| Invented at | Salesforce | Intel (Andy Grove) |

**Using both**: write a V2MOM at the start of the year to set direction and values. Derive quarterly OKRs from the V2MOM Methods and Measures. Each quarter's OKRs should visibly contribute to the V2MOM Measures.

---

## The Cascading Model at Salesforce

```
CEO V2MOM
  "Become the #1 CRM platform globally..."
  Methods: Enterprise expansion, AI integration, international growth
         │
         ▼
  SVP Engineering V2MOM
    Vision: "Build the most reliable, developer-friendly CRM platform"
    Methods cascade from CEO methods: "AI integration → ML Platform team"
         │
         ▼
  ML Platform Team V2MOM
    Vision: "Enable every Salesforce product to ship AI features in days, not months"
    Methods: Feature store, model serving platform, experimentation framework
```

**Alignment check**: every team V2MOM should visibly trace to its parent. If a Method in your V2MOM doesn't contribute to any Method in your manager's V2MOM — either it's a gap in the parent V2MOM (escalate) or it's not the right work (cut it).

---

## FAANG Interview Callouts

**Q: When would you use V2MOM vs. OKRs for your engineering org?**

V2MOM for annual strategic alignment — especially useful when:
- The team has a culture/values problem, not just a goal problem
- There are known obstacles that need to be named publicly (V2MOM forces this)
- You want a single document that captures both strategy and execution in one place

OKRs for quarterly execution tracking — especially useful when:
- You need tight accountability loops with visible progress
- Multiple teams need to see each other's progress and coordinate
- You want a lightweight, fast-to-write format that keeps pace with quarterly product cycles

In practice at principal level: use V2MOM to write your annual team strategy document, then derive each quarter's OKRs from it. The V2MOM gives you the "why" and annual context; the OKRs give you the "what this quarter" and measurable progress tracking.

**Q: Your V2MOM Obstacles section lists "no executive sponsor for the migration." How do you fix that?**

Naming the obstacle is the first step — it makes it visible to your leadership chain. Then:
1. Present the obstacle with its cost: "Without exec sponsorship, product teams can opt out of the migration. Current opt-out rate is 60%, which means we won't hit the Measure of 80% migration."
2. Quantify what's at stake: "Each month of delay costs $X in legacy infrastructure, and creates $Y in reliability risk."
3. Propose a specific ask: "I need 30 minutes with the CTO to align on migration priority, and a mandate that blocks new product launches on the old stack after Q3."

V2MOM obstacles are an escalation mechanism, not a complaint box.
