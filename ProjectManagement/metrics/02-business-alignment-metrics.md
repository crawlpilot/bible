# Business Alignment Metrics

## The Gap Problem

Engineering teams measure what they control: deployments, test coverage, latency. Executives measure what they care about: revenue, customer satisfaction, market share, cost. There is almost always a translation gap.

**Principal engineer responsibility**: bridge this gap. Connect the technical metrics your team tracks to the business outcomes leadership cares about. If you can't draw that line, your engineering work may be excellent and your team invisible — or worse, vulnerable to budget cuts.

---

## The Business Metric Stack

```
Business Outcomes (L4)
  Revenue, Customer Growth, Market Share, Cost Efficiency
       ↑ driven by
       
Customer Outcomes (L3)
  User Satisfaction (NPS/CSAT), Retention, Feature Adoption, Conversion
       ↑ driven by
       
Product Outcomes (L2)
  Feature Availability, Reliability, Performance, Time-to-Market
       ↑ driven by
       
Engineering Outcomes (L1) — what teams directly control
  Deployment Frequency, Lead Time, Error Rate, MTTR
```

A principal engineer articulates the full stack — not just L1. "We improved deployment frequency from weekly to daily" means nothing to a CFO. "We improved deployment frequency from weekly to daily, which reduced time-to-market for features by 5×, contributing to a 12% increase in feature adoption this quarter" means something.

---

## Key Business Metrics and Their Engineering Levers

### Revenue Impact

| Business metric | Engineering connection | Your lever |
|-----------------|----------------------|------------|
| Checkout conversion rate | Checkout latency, error rate | p99 latency, payment retry logic |
| Subscription renewal | Reliability, feature satisfaction | Availability SLO, lead time (shipping value faster) |
| Enterprise upsell | Platform stability, security posture | CFR, CVE age, SOC2 compliance |
| Ad revenue | Page load performance | Core Web Vitals, CDN optimization |

**Example (Amazon)**: 100ms of latency costs ~1% of sales. A team that reduces checkout p99 from 2s to 300ms can directly quantify revenue impact. This is why latency KPIs are business metrics at Amazon, not just engineering metrics.

### Customer Satisfaction (NPS / CSAT)

**Net Promoter Score (NPS)**: "How likely are you to recommend us? (0–10)"
- Promoters: 9–10
- Passives: 7–8
- Detractors: 0–6
- NPS = % Promoters - % Detractors

**Engineering impact on NPS**:
- Outages and incidents directly tank NPS (every P1 incident correlates with a dip)
- Slow UI/API responses are the #1 user frustration in most SaaS products
- Feature delivery speed correlates with user satisfaction — "the product keeps getting better"

**Track**: incident impact on NPS by correlating incident windows with survey responses collected in the same week.

**Customer Satisfaction Score (CSAT)**: post-transaction survey ("How satisfied were you with this interaction? 1–5"). More granular than NPS, often tied to specific features or support interactions.

### Feature Adoption Rate

**Definition**: percentage of target users who have used a feature within N days of launch.

```
Feature Adoption = (users who used feature / target users) × 100
Measured at: D7, D30, D90 post-launch

Example:
  New search experience launched to 50,000 users
  D7 adoption: 22% (11,000 users used new search)
  D30 adoption: 61% (30,500 users)
  D90 adoption: 78% (39,000 users)
```

**Engineering connection**:
- Low adoption at D7 may indicate a performance problem (new feature is slow) or a discoverability bug (UI doesn't surface the feature)
- High D30 but low D90 indicates a retention/stickiness problem with the feature itself
- Time-to-feature (how fast from idea to GA) affects competitive adoption — if competitors ship first, your adoption starts from a smaller addressable base

### Time to Market

**Definition**: calendar time from product decision to feature in production for all users.

```
Time to Market = GA Launch Date - Feature Commitment Date

Breakdown:
  Design: commitment → design finalized
  Engineering: design finalized → feature shipped to staging
  QA/Validation: staging → canary
  Rollout: canary → 100% users
```

**Engineering's share**: the Engineering + QA phases are where engineering lead time and pipeline speed matter. If design takes 4 weeks and engineering takes 1 week — optimizing lead time from 3 days to 1 day saves 2 days out of a 5-week cycle. Marginal. If engineering takes 6 weeks and design takes 1 week — that's the bottleneck.

**Benchmark**: FAANG-level teams ship features in 2–4 weeks from design-complete to GA. Enterprise companies often take 3–6 months for similar scope.

### Engineering Cost Efficiency

Executives track revenue per engineer as a proxy for engineering productivity (imperfect but widely used).

```
Revenue per Engineer = Annual Revenue / Total Engineering Headcount

Benchmark:
  Google:   ~$1.5M revenue/engineer
  Amazon:   ~$2M revenue/engineer  
  Stripe:   ~$1.2M revenue/engineer
  Enterprise SaaS: $200K–$500K revenue/engineer
  
Engineering Cost as % of Revenue:
  Healthy SaaS:   15–25%
  R&D intensive:  25–40%
  > 40%:          usually a scaling problem (revenue hasn't grown with headcount)
```

**Engineering levers on efficiency**:
- Automation: replacing manual processes with automated systems (on-call automation, testing, deployment)
- Platform investment: reducing per-team overhead via golden-path tooling
- Tech debt: reducing the drag of maintenance work that crowds out feature development
- Incident cost: each major incident costs 10–50 engineer-days across response, RCA, and remediation

---

## Connecting Engineering Metrics to Business Metrics: Template

Use this template when presenting to leadership or writing an engineering strategy:

```
[Engineering Metric] → [Product Impact] → [Business Outcome]

Example 1:
  Deployment Frequency: 1×/week → 5×/day
  → Feature time-to-market: 8 weeks → 2 weeks
  → Business: 4 more feature cycles/year, product iterates 4× faster on user feedback

Example 2:
  MTTR: 4 hours → 45 minutes
  → Incidents: users experience 4h of degradation → 45 min
  → Business: CSAT impact per incident reduced; annualized, ~200 hours of downtime avoided
              At 2% revenue impact per hour of checkout outage = $X saved/year

Example 3:
  Test coverage + canary: CFR 18% → 4%
  → Incidents per month: 12 → 3
  → Business: 9 fewer incidents/month × $25K avg cost per incident = $2.7M/year
```

---

## OKR-to-Business-Metric Alignment

OKRs should have at least one KR that connects directly to a business metric. If all KRs are technical (latency, coverage, deploy frequency), the team may be optimizing locally without moving business needles.

**Aligned OKR example**:

```
Objective: Make checkout reliable enough that payment errors stop hurting retention

KR1: Reduce payment timeout errors from 2.1% → 0.5%         [engineering metric]
KR2: Reduce checkout p99 latency from 3.2s → 1.0s            [engineering metric]
KR3: Checkout-related CSAT score increases from 3.1 → 4.2   [customer metric]
KR4: Payment-related support tickets decrease by 40%         [business metric]
```

KR3 and KR4 are business metrics. KR1 and KR2 are the engineering levers that drive them. This structure makes the causal chain explicit and gives leadership both the "how" (KR1/2) and the "so what" (KR3/4).

---

## FAANG Interview Callouts

**Q: How do you justify a 6-month platform re-architecture to a CFO who only sees cost?**

Translate into CFO language:

1. **Current cost**: each major incident costs ~$200K in eng time, customer compensation, and churn. We have 8/month = $1.6M/month.
2. **Cost reduction**: re-architecture reduces incident rate by 70% based on root cause analysis. Projected savings: $1.12M/month.
3. **Investment**: 6 months × 5 engineers = ~$750K fully loaded.
4. **Payback period**: the investment pays back in < 1 month of savings.
5. **Opportunity cost**: current architecture forces 40% of eng time into maintenance. Freeing that capacity is equivalent to hiring 8 engineers at $0 incremental cost.

This framing is unambiguous to a CFO. Technical arguments (faster deploys, better architecture) are irrelevant. Revenue protection and cost efficiency are the language.

**Q: Product says engineering is slow because features take 8 weeks. Engineering says they're moving as fast as possible. How do you resolve this?**

Break down the 8-week time-to-market and measure each phase:

```
Product decision → design finalized: 2 weeks (product/design time)
Design finalized → staging: 3 weeks (engineering time)
Staging → canary: 1 week (QA/validation time)
Canary → 100% rollout: 2 weeks (cautious rollout)
Total: 8 weeks
```

Now both sides have data. Engineering owns 3 of the 8 weeks. Product and QA own the other 5. If engineering wants to reduce their 3 weeks to 1 week (achievable with better test automation and smaller PRs), that's a 25% improvement in total time-to-market — not the 75% reduction product expects. The honest conversation: "Engineering can improve their phase. But the bigger gains are in design cycle time and QA automation." That's a cross-functional conversation the data makes possible.
