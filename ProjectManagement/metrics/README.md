# Metrics — Engineering KPIs, Tracking & Accountability

> What gets measured gets managed. What gets measured wrong gets gamed. The principal engineer's job is to define metrics that reflect real outcomes — not metrics that are easy to collect.

---

## Contents

| File | Topic |
|------|-------|
| [01-engineering-kpis.md](01-engineering-kpis.md) | Technical KPIs: DORA, reliability, quality, security, delivery metrics |
| [02-business-alignment-metrics.md](02-business-alignment-metrics.md) | Connecting engineering metrics to business outcomes — what executives actually care about |
| [03-tracking-and-monitoring.md](03-tracking-and-monitoring.md) | Dashboards, review cadences, OKR progress tracking, accountability structures |
| [04-team-health-metrics.md](04-team-health-metrics.md) | Team health indicators: velocity, review turnaround, on-call burden, attrition signals |

---

## The Metric Hierarchy

```
Mission / Strategy
       │
       ▼
   OKRs (quarterly)         ← "Are we achieving outcomes?"
       │
       ▼
   Leading indicators       ← "Are we on track to achieve outcomes?"
       │
       ▼
   Operational metrics      ← "Is the system healthy day-to-day?"
       │
       ▼
   Alerts / SLOs            ← "Is something broken right now?"
```

---

## Metric Quality Checklist

Before adopting any metric, run it through these checks:

| Check | Question |
|-------|----------|
| **Outcome-linked** | Does this metric reflect real user or business value, or just activity? |
| **Actionable** | Can the team change their behavior to improve it? |
| **Leading vs. lagging** | Does it predict future outcomes (leading) or confirm past ones (lagging)? |
| **Gameable** | Can the team hit this number without actually improving? |
| **Measurable** | Can it be collected reliably without significant manual effort? |
| **Time-bounded** | Does it have a target and a review cadence? |

A metric that fails 2+ of these checks is not a KPI — it is noise.
