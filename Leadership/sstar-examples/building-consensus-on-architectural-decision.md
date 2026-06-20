# SSTAR: Building Consensus Across Teams on an Architectural Decision

**Category**: Leadership · Influence · Architecture · Principal Engineer Scope  
**Framework**: SSTAR (Situation → Strategy → Task → Action → Result)  
**Interview context**: "Tell me about a time you drove a controversial technical decision" / "How do you handle strong disagreement between senior engineers?" / "Describe a time you had to choose between two valid technical approaches with divided opinion"

> The hardest architectural decisions are not the ones where the answer is technically obvious. They're the ones where reasonable, experienced engineers disagree — and someone has to drive to a decision without losing the team.

---

## Why Consensus-Building is a PE-Level Skill

At principal engineer level:
- You're often the person who must break ties between teams with competing technical positions
- Your decisions affect multiple teams' roadmaps, not just your own
- Pushing a decision through without buy-in creates resentment, compliance without commitment, and a team that undermines the decision in execution
- But consensus paralysis — endless deliberation with no decision — is equally damaging

Interviewers are evaluating whether you can navigate the space between "dictatorship" and "committee."

---

## SSTAR — Service Mesh vs. Library-Based Service Communication

### S — Situation

*"At [Company], our microservices architecture had reached a scale where cross-service communication was becoming a reliability problem: inconsistent retry policies across 40 services, 4 different implementations of circuit breakers, no standard for mutual TLS between services, and observability gaps because each service was emitting traces with different formats and sampling rates.*

*Two camps had formed around the solution:*

*Camp A (Platform team + 3 senior engineers): adopt Istio as a service mesh. Inject Envoy sidecar proxies into all services, handle retries, mTLS, circuit breaking, and observability at the infrastructure layer without application code changes.*

*Camp B (Application teams + 2 staff engineers): adopt a shared internal library (we'd call it 'ServiceKit') that every service imports. The library would standardize retries, circuit breakers, and trace emission in code, without adding sidecar overhead.*

*The debate had been running for 3 months with no resolution. Both camps had valid points. The VP of Engineering asked me — as the Staff Engineer for Platform — to drive the decision within 4 weeks."*

---

### ST — Strategy

*"My strategy was to separate the process from the content. The previous 3 months of debate had conflated 'which option is technically better' with 'whose team wins.' I needed to step outside that dynamic.*

*Three principles I committed to:*

*1. I would not advocate for Camp A's position (even though I was from the Platform team) before doing a structured evaluation. Appearing to defend my own team's proposal would poison the process.*

*2. I would make the decision criteria explicit before evaluating the options. Disagreements persist when people argue about conclusions but have never agreed on what matters.*

*3. I would drive to a decision, not to consensus. Consensus means everyone agrees. That may not be achievable. What I needed was: everyone was heard, the decision was made transparently with documented reasoning, and we had a clear path to move forward. Disagreeing and committing is a professional expectation at this level."*

---

### T — Task

*"My responsibility: (1) facilitate a structured evaluation process with representatives from both camps, (2) develop the evaluation framework and criteria, (3) produce a written ADR (Architecture Decision Record) with the decision and full reasoning, (4) present the decision to the VP and get formal approval, and (5) own the communication to both camps."*

---

### A — Action

**Step 1 — Define criteria before evaluating options (Week 1):**

*"I convened a working session with 3 engineers from each camp. My first ask was: 'Before we discuss Istio vs ServiceKit, let's agree on what criteria matter for this decision.' I put 8 candidate criteria on a whiteboard and asked the group to rank them by importance:*

*1. Operational complexity (who maintains it?)*
*2. Performance overhead (latency, memory)*
*3. Language/framework agnosticism (we run Java, Python, Go)*
*4. Time to adopt across all 40 services*
*5. Feature completeness (retries, mTLS, circuit breaking, observability)*
*6. Debuggability (when something fails, can engineers diagnose it?)*
*7. Vendor lock-in risk*
*8. Consistency guarantee (will all services actually use it correctly?)*

*Getting agreement on criteria before evaluating options was crucial. It prevented the debate from regressing to 'but Istio has X feature' vs. 'but ServiceKit avoids Y cost' without a framework.*

*The group reached quick agreement on the top 4: operational complexity, language agnosticism, debuggability, and consistency guarantee. We disagreed on how to weight performance overhead — Camp B rated it higher than Camp A. We resolved this by agreeing to measure it rather than debate it."*

**Step 2 — Structured evaluation against agreed criteria (Weeks 1–2):**

*"I assigned each camp the responsibility of building the best possible case for their own option against the agreed criteria — not to attack the other option. I gave them 1 week.*

*Then I did something unexpected: I asked each camp to also write a 'steelman' of the other option — the strongest possible case for the option they opposed. This had two effects: (1) it forced each camp to genuinely understand the other's position, and (2) it surfaced arguments that each camp hadn't considered.*

*I also ran a performance test. Two of the engineers set up a benchmark: 10K RPS through an Envoy sidecar (Istio) vs. 10K RPS with ServiceKit in-process. Results: Istio added ~1.5ms P99 latency overhead (from 18ms to 19.5ms). ServiceKit added ~0.3ms. For our latency budget (P99 < 50ms), both were acceptable. This moved performance overhead from 'fatal objection to Istio' to 'notable but non-blocking.'*

*Key findings from the evaluation:*
- *Language agnosticism: Istio wins clearly — sidecar handles Java, Python, Go without per-language library work*
- *Operational complexity: ServiceKit wins — Istio's control plane (Istiod) adds an operational layer most teams had no experience with*
- *Consistency guarantee: Istio wins — you cannot opt out of a sidecar; ServiceKit adoption requires teams to actively import and use it correctly*
- *Debuggability: split — Istio's Envoy logs are powerful but unfamiliar; ServiceKit is 'just code' but debugging distributed behavior is still hard*"*

**Step 3 — The decision (Week 3):**

*"After the evaluation, I had a private conversation with the two most vocal advocates — one from each camp — before the group decision meeting.*

*I told each of them: 'Based on the criteria we agreed on, I'm leaning toward Istio because language agnosticism and consistency guarantee outweigh the operational overhead concern for our specific context. I want to hear if there's something I'm missing before I finalize this.' Both conversations were constructive. The Camp B advocate raised a legitimate concern I hadn't fully weighted: our Platform team was already stretched, and owning Istio's control plane would require dedicated SRE time we didn't have budgeted.*

*That input changed my recommendation. Instead of full Istio adoption, I recommended a phased approach: implement ServiceKit as an interim standard for immediate consistency improvement, with a formal 12-month review to evaluate service mesh adoption once our platform team had the capacity to operate it properly.*

*This was not a compromise — it was a better answer based on a constraint I hadn't fully accounted for. The Camp B advocate who raised it felt heard and turned from an opponent into a supporter of the phased approach.*

*I wrote the ADR: Title, Status (Accepted), Context (the problem), Decision (phased: ServiceKit now, service mesh evaluation in 12 months), Consequences, Alternatives Considered. I circulated it 48 hours before the decision meeting for written comments. 4 comments came in; I addressed each one in the document."*

**Step 4 — Decision meeting and communication:**

*"The meeting was 45 minutes. I presented the ADR, the evaluation summary, and the decision. I opened explicitly with: 'The goal of this meeting is to hear final objections and then close. We are not re-opening the evaluation today.' That framing prevented the meeting from becoming a rehash of the 3-month debate.*

*One engineer from Camp A raised a strong objection: he felt we were deferring Istio indefinitely. I acknowledged his concern directly: 'The 12-month review is a firm commitment. I'm going to put this in the ADR with explicit criteria for what would make service mesh adoption the right call at that review. If we hit those criteria, we adopt. This is not 'never' — it's 'after we've solved the operational readiness problem.'*

*The VP of Engineering formally approved the ADR the next day."*

---

### R — Result

*"ServiceKit was adopted across all 40 services in 5 months — 3 months faster than the previous estimate for full Istio rollout — because teams owned the implementation and the library was familiar to work with.*

*The 3 reliability problems we'd targeted (inconsistent retries, missing circuit breakers, observability gaps) were resolved in the first 3 months of ServiceKit adoption. Retry-storm incidents dropped from 8 in the prior 12 months to 1.*

*At the 12-month review, we evaluated service mesh adoption. Our Platform team had hired 2 SREs with Envoy experience. We had better operational baseline. The team voted to move to Istio for new services while keeping ServiceKit in existing services during a 2-year transition. That transition is now underway.*

*The ADR process itself was adopted by the architecture review committee as the standard for all major technical decisions. 12 ADRs have been written in the 18 months since, all following the same format: explicit criteria before evaluation, steelman of alternatives, decision with documented reasoning."*

---

## Coaching Notes

| Dimension | PE-Level Signal | Mid-Level Signal |
|-----------|----------------|-----------------|
| **Process design** | Criteria first, evaluation second, decision third — in that order | Jumped to evaluating options without agreeing on criteria |
| **Neutrality** | Didn't advocate for Platform team's position early | Ran the evaluation to justify the Platform team's preferred choice |
| **Incorporating new information** | Phased approach came from a private conversation with a Camp B advocate | Stuck with original recommendation despite new constraint |
| **Decision framing** | "Disagree and commit is a professional expectation" | Sought consensus until everyone agreed |
| **ADR quality** | Criteria, decision, alternatives considered, and explicit 12-month review trigger | "We chose Istio because it's better" |

---

## Common Follow-up Questions

**"How do you handle a situation where you make a call and it turns out to be wrong?"**
> "The ADR format is specifically designed for this. The 'Consequences' section of an ADR includes anticipated risks. When a decision turns out to have been wrong, I first check whether the failure mode was in the Consequences section — if so, the decision was reasonable given the information available, and the system worked as designed. If the failure mode wasn't anticipated, that's a diagnosis question: what information did we have that we didn't weight correctly, and how do we improve our evaluation process? Either way, the response is the same: write the post-decision review, document what we'd do differently, and make the corrective decision quickly. Prolonged post-mortem on a bad decision is worse than a fast corrective decision."

**"What would you have done if the VP had a strong personal preference for one option?"**
> "I would have surfaced that preference early in the process and asked the VP to weigh in on the criteria rather than the options. If the VP's preferred criteria led to a different decision, that's a legitimate input. What I wouldn't do is let an undisclosed executive preference undermine a fair process — that destroys trust in the process for everyone who participated. If a VP wants to make a unilateral decision, that's within their authority, but it should be transparent and not disguised as a participatory process."
