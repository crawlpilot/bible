# Engineering Ownership & Role Definitions

A principal engineer operates across all these roles — not performing them, but **partnering with, influencing, and unblocking** each. Understanding the exact accountability surface of each role is critical for cross-functional leadership and org design conversations at FAANG.

---

## Folder Index

| File | Role | Primary Accountability |
|------|------|------------------------|
| [01-product.md](01-product.md) | Product Manager / Product Owner | What gets built and why |
| [02-operations.md](02-operations.md) | Operations / SRE / Reliability | System runs, SLOs met, incidents resolved |
| [03-devops.md](03-devops.md) | DevOps / Platform Engineer | How code ships — pipelines, infra, tooling |
| [04-engineering-manager.md](04-engineering-manager.md) | Engineering Manager | People, team health, delivery, org design |
| [05-lead-engineer.md](05-lead-engineer.md) | Tech Lead / Lead Engineer | Technical direction within a team or project |
| [06-senior-engineer.md](06-senior-engineer.md) | Senior Engineer | Deep individual ownership, mentorship, quality |
| [07-engineer.md](07-engineer.md) | Software Engineer (L3–L5) | Feature delivery, component ownership |
| [08-principal-engineer.md](08-principal-engineer.md) | Principal / Staff Engineer | Org-wide technical strategy, cross-team influence |

---

## RACI at a Glance — Product Delivery Lifecycle

| Phase | Product | Operations | DevOps | EM | Tech Lead | Senior SWE | SWE | Principal |
|-------|---------|------------|--------|-----|-----------|------------|-----|-----------|
| Requirements | A/R | I | I | C | C | C | I | C |
| Architecture | I | C | C | I | R | C | I | A |
| Sprint Planning | C | I | I | A | R | C | C | I |
| Implementation | I | I | I | I | C | R | R | I |
| Code Review | I | I | I | I | A | R | C | C |
| CI/CD Pipeline | I | C | A/R | I | C | I | I | C |
| Testing / QA | C | C | I | I | R | R | C | I |
| Deployment | C | R | A/R | I | C | I | I | I |
| Incident Response | C | A/R | R | I | C | C | I | C |
| Post-Mortem | C | A/R | R | I | C | C | I | C |
| Roadmap Planning | A/R | C | I | C | C | I | I | C |

> **A** = Accountable (the buck stops here) · **R** = Responsible (does the work) · **C** = Consulted · **I** = Informed

---

## Principal Engineer Interview Angle

When asked "how do you work across functions?" — walk the interviewer through this matrix. Demonstrate that you:

1. Know **where each role's decision authority ends** and yours begins
2. Can **fill gaps** when ownership is unclear (ambiguous problems, nobody owns it yet)
3. Operate through **influence, not authority** — you don't manage PMs or EMs
4. Design systems that **respect role boundaries** (e.g., runbooks for Ops, platform abstractions for DevOps)
