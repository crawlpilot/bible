# Scaled Agile and Anti-Patterns

Scrum is usually workable for a single team. It becomes fragile when multiple teams share dependencies, common services, or release coordination. At that point, the right question is not "How do we do Scrum harder?" It is "What coordination mechanism actually fits the org structure?"

## When Scrum Starts to Break

- Multiple teams must deliver the same user-facing capability
- Shared platform work blocks product teams
- Release dependencies exceed a single sprint boundary
- Planning becomes dominated by dependency negotiation
- The org confuses ceremony with alignment

## Common Anti-Patterns

| Anti-pattern | Why it is harmful |
|-------------|-------------------|
| Story-point targets as performance metrics | Encourages gaming and bad slicing |
| Committing every sprint to 100% capacity | Leaves no room for reality |
| Large stories that span multiple sprints | Hides progress and increases risk |
| Retro action items with no follow-up | Creates the illusion of improvement |
| Scrum of Scrums with no decision rights | Adds coordination cost without reducing dependency risk |

## Better Coordination Moves

- Align on a shared quarterly outcome, not just sprint commitments
- Put dependency owners in the room early
- Use architecture or product slicing to reduce coupling
- Track cross-team risks in a visible decision log
- Reserve explicit capacity for platform or integration work

## How to Know You Need a Different Model

| Symptom | Likely issue |
|---------|--------------|
| Repeated sprint spillover | Stories are too large or too coupled |
| Endless dependency discussions | Ownership boundaries are unclear |
| Release weekends are common | Coordination model is too manual |
| Velocity is volatile across teams | Work mix is inconsistent |

## Principal Engineer Recommendation

Use Scrum when it helps the team inspect and adapt. Stop using it as the default if it is primarily creating reporting overhead. The real objective is predictable delivery with low coordination cost.

## Interview Callout

If asked about scaling agile, avoid buzzwords. Explain the operational problem first: dependency management, planning accuracy, and ownership clarity. Then explain the coordination structure you would choose.

---

## Scaled Agile Frameworks — Comparison

When a single Scrum team grows into multiple teams, different scaling approaches solve different coordination problems.

### SAFe (Scaled Agile Framework)

SAFe is the most widely adopted enterprise agile framework. It introduces the **Agile Release Train (ART)** — a virtual organisation of 5–12 Scrum teams aligned to a shared value stream.

**Key ceremonies in SAFe:**

| Ceremony | Frequency | Purpose |
|----------|-----------|---------|
| **PI Planning** | Every 8–12 weeks | Cross-team planning for a Program Increment (2–3 months of work) |
| **ART Sync** | Weekly | Short cross-team check on dependencies and risks |
| **System Demo** | Every sprint | Integrated demo across all teams in the ART |
| **Inspect & Adapt** | End of PI | Large-scale retrospective + root cause analysis |

**PI Planning format (2-day event):**
- Day 1 AM: Vision, architecture briefing, team breakouts
- Day 1 PM: Draft plan creation per team
- Day 2 AM: Risk review, dependency identification, cross-team adjustments
- Day 2 PM: Final plan presentation, risk board (ROAM), confidence vote

**Where SAFe excels:** large enterprises, regulated industries, complex multi-team dependencies with long planning horizons.

**Where SAFe fails:** small organisations adopting it without the coordination problems that justify it; creates process overhead that kills velocity.

---

### LeSS (Large-Scale Scrum)

LeSS is simpler than SAFe. It scales Scrum by applying the same Scrum rules across multiple teams working from a single product backlog.

**LeSS principles:**
- One Product Owner for all teams
- One shared Product Backlog
- One Sprint across all teams (synchronised)
- Shared Sprint Review — all teams demo together
- Shared Retrospective for cross-cutting systemic issues
- Teams are self-organising and cross-functional

**LeSS vs. SAFe comparison:**

| Aspect | LeSS | SAFe |
|--------|------|------|
| Product Backlog | Single, shared | Per team + ART backlog |
| Roles added | Almost none (just Product Owner for all) | Many new roles (RTE, ART, SA) |
| Planning cadence | Sprint-level (2 weeks) | PI-level (8–12 weeks) |
| Best fit | 2–8 teams, same product | 5–12+ teams, program-level coordination |
| Risk | PO bandwidth; shared backlog contention | Process overhead; bureaucracy risk |

---

### Nexus (Scrum.org)

Nexus sits between LeSS and SAFe in complexity. It adds one coordination layer — the **Nexus Integration Team** — responsible for resolving cross-team dependencies and integration.

**Nexus Sprint:** each team runs its own sprint but contributes to a shared integrated increment. A Nexus Daily Scrum (15 min) surfaces cross-team blockers.

---

### Kanban for Platform and Infrastructure Teams

Platform and infrastructure teams often don't have sprint-based work. Their work is demand-driven: fix this, provision that, integrate this service. Kanban is better suited:

- No fixed sprint cadence — work flows continuously
- WIP limits enforce focus without artificial sprint deadlines
- SLAs replace velocity as the commitment mechanism
- Service requests are triaged and pulled, not estimated and planned

**Hybrid model at scale:** product teams use Scrum; platform teams use Kanban; dependency interfaces are managed through explicit SLAs and request queues.

---

## Scrum Anti-Patterns — Comprehensive Reference

### Process Anti-Patterns

| Anti-pattern | What it looks like | The actual problem | Fix |
|-------------|-------------------|-------------------|-----|
| **Sprint commitment as a contract** | Stories "committed" to stakeholders who hold the team accountable to each story | Confuses forecast with promise | Reframe: sprint goal is the commitment; story list is the plan |
| **Velocity as a KPI** | Management tracks velocity week-over-week and asks why it dropped | Velocity is a planning tool, not a performance measure | Track outcome metrics: deployment frequency, DORA, customer impact |
| **100% sprint planning** | Team fills every available hour with stories, no buffer | Ignores interrupt load and estimation uncertainty | Reserve 20% explicitly for support, review, unplanned work |
| **Permanent carry-over stories** | Same story appears sprint after sprint | Story is too large, too vague, or being blocked | Block until resolved; split if > 8 points; spike if unclear |
| **Backlog as a dumping ground** | Backlog has 600 items, most never touched | No prioritisation discipline | Keep backlog to < 2 sprints of refined stories; archive the rest |
| **Meeting-heavy Scrum** | Daily standups run 45 min; planning takes a full day | Ceremonies are not timeboxed; facilitation is poor | Enforce timebox; reject unready stories; delegate ceremony ownership |

### Team Dynamics Anti-Patterns

| Anti-pattern | What it looks like | Fix |
|-------------|-------------------|-----|
| **Hero culture** | One engineer always saves the sprint | Pair; reduce WIP; bus factor is a risk |
| **Scrum but** | "We do Scrum, but without retros / standups / PO involvement" | Name which elements are dropped and why; be intentional |
| **Siloed standups** | "I worked on X, will work on X, no blockers" × everyone | Reformat to: "what do we need to do as a team today?" |
| **PO as requirements secretary** | PO writes tickets without engineering input | Co-create stories; three amigos sessions (PO + dev + QA) |
| **Absentee PO** | PO rarely available for questions or sign-off | This is a blocking risk; escalate to leadership |
| **Sprint demo theater** | Demo shows only the best case; stakeholders can't ask questions | Make demos interactive; show failure cases; invite questions |

### Engineering Anti-Patterns in an Agile Context

| Anti-pattern | Why it matters in Scrum |
|-------------|------------------------|
| **No Definition of Done for tech debt** | Tech debt stories never get done unless DoD includes quality gates |
| **Skip tests to close the sprint** | Raises change failure rate; collapses DoD integrity |
| **Big bang integration** | Cross-team integration work hidden until sprint end causes spillover |
| **Feature flags not used** | Prevents continuous deployment; forces release coordination |
| **No observability in DoD** | Code ships without metrics/alerts; issues caught in prod, not sprint |

---

## Dependency Management at Scale

Cross-team dependencies are the #1 cause of missed sprint goals at scale. Treat them as risks, not tasks.

### Dependency Types

| Type | Example | Resolution strategy |
|------|---------|-------------------|
| **Upstream data** | Team A needs Team B's API before they can start | API contract agreed upfront; API team stubs the endpoint first |
| **Shared component** | Two teams modifying the same service | Designate an owner; use feature flags to merge safely |
| **Shared platform** | Both teams need a platform capability that doesn't exist yet | Platform team treats it as a product; SLAs agreed upfront |
| **Release coordination** | Feature requires both teams to deploy at the same time | Feature flags; decouple deploy from release |

### ROAM Framework (from SAFe)

For each identified risk or dependency in planning, apply ROAM:

| Action | Meaning |
|--------|---------|
| **R** — Resolved | Risk is resolved; no action needed |
| **O** — Owned | Someone owns it and has a plan |
| **A** — Accepted | Risk is understood and accepted; no mitigation |
| **M** — Mitigated | Mitigation action taken; risk reduced |

Any risk that is not ROAM'd is an untracked risk — which is worse than an accepted one.

---

## Communities of Practice (CoP)

At scale, technical standards drift across teams without a coordination mechanism. Communities of Practice fill this role without adding org hierarchy.

**What a CoP is:** a voluntary, cross-team group of practitioners who share knowledge and maintain standards around a domain (backend engineering, data engineering, mobile, security).

**What a CoP is not:** a governance body with approval rights. CoPs inform and recommend; teams decide.

**CoP rituals:**
- Monthly or bi-weekly knowledge share (30–60 min)
- Rotating presenter: each team brings a problem or solution to discuss
- Shared decision log for standards decisions (ADRs)
- Slack/Teams channel for async knowledge sharing
- Annual tech radar update (Thoughtworks format)

**Principal engineer role in a CoP:** set the agenda, not just attend. The principal owns the technical standards that come out of the CoP and drives adoption through example.

---

## When to Stop Using Scrum

Scrum is not the right tool for all situations. Know when to recommend a different model.

| Situation | Better model |
|-----------|-------------|
| Continuous operational work (platform, infra) | Kanban with SLAs |
| R&D / exploratory work with no clear outcome | Shape Up (Basecamp model) — 6-week cycles with explicit appetite |
| Single engineer or very small team | Personal Kanban; Scrum overhead exceeds value |
| Emergency incident response | Incident command, not sprint-based |
| Long-running integration project (> 6 months) | PRINCE2 or PMI for milestone-based tracking |

**Shape Up summary (Basecamp):**
- Fixed time, variable scope (opposite of most planning)
- 6-week build cycles, 2-week cool-down
- "Appetite" replaces estimates: "We'll spend 6 weeks on this, no more"
- No backlog grooming; betting table decides what to build next cycle

---

## FAANG Interview Framing

**"How do you coordinate planning across 3 teams that share dependencies?"**

> The key is to make dependencies visible before the sprint starts, not after. I use a dependency map at the start of planning: each team identifies which stories have an external dependency and names the owner in the other team. Any dependency without a named owner and a committed delivery date doesn't go into the sprint. We also decouple deploy from release using feature flags wherever possible, so teams can merge independently without waiting for each other to be ready. For longer planning horizons, I use a lightweight PI Planning session — two half-days where all teams map their roadmaps and surface cross-team risks before committing.

**"What agile anti-pattern do you see most often and how do you fix it?"**

> The most damaging one is velocity as a KPI. Once a team knows velocity is being reported to leadership, story points inflate, scope gets cut to hit the number, and the metric stops representing anything real. I fix it by replacing velocity reporting with outcome metrics: deployment frequency, lead time for changes, and customer-facing impact. I keep velocity as an internal planning tool only, visible to the team, not the dashboard. It usually takes two or three sprint cycles before the pressure to "hit a number" fades.
