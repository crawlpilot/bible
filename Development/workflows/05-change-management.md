# Change Management

## Why This Matters at Principal Engineer Level

Change management is how engineering organizations make high-risk, high-impact changes safely — without slowing down routine work. A principal engineer designs the change management process: which changes need review gates, how to communicate changes to stakeholders, how to sequence a large migration, and how to handle rollbacks when things go wrong. The failure mode at principal level is either too much process (every change requires a committee) or too little (a schema migration takes down prod with no plan).

---

## Change Risk Classification

Not all changes are equal. Classify before deciding on process.

| Class | Risk | Examples | Process |
|-------|------|----------|---------|
| Routine | Low | Bug fixes, minor features, config updates | Standard PR + CI |
| Standard | Medium | New API endpoint, library upgrade, performance tuning | PR + staging validation + canary |
| Significant | High | Schema migration, auth changes, pricing logic, new service | PR + design doc + staging + canary + release gate |
| Emergency | Variable | Production incident fix | Expedited review (1 approver), post-hoc documentation |
| Major | Critical | Database engine upgrade, re-architecture, public API breaking change | RFC + multi-team review + phased rollout + exec sign-off |

---

## The RFC (Request for Comments) Process

Use RFCs for significant and major changes. An RFC forces you to think through the change before implementing it — and surfaces concerns from stakeholders early.

### When to write an RFC
- Changes that affect more than one team
- Changes that can't be easily rolled back
- Changes to public APIs or shared contracts
- Changes that require significant infrastructure investment (> 2 weeks of work)
- Changes with meaningful security or compliance implications

### RFC Template

```markdown
# RFC-NNNN: [Title]

**Status:** Draft | Review | Accepted | Rejected | Superseded  
**Author:** @name  
**Reviewers:** @team1 @team2  
**Created:** YYYY-MM-DD  
**Decision deadline:** YYYY-MM-DD  

---

## Problem Statement

What problem are we solving? Why does it need to be solved now?
(Include data: error rates, latency, cost, developer friction)

## Motivation

Why is this worth doing over other priorities?

## Proposed Design

How exactly will this work? Include:
- Architecture diagram (Mermaid or ASCII)
- API contracts / interface changes
- Data model changes
- Rollout plan (phases with success criteria)

## Trade-offs

| Dimension | Current State | Proposed State |
|-----------|--------------|----------------|
| Latency | 150ms p99 | 80ms p99 |
| Operational complexity | Low | Medium |
| Migration risk | N/A | Medium (2-week window) |

## Alternatives Considered

What else did you evaluate? Why did you reject those options?

## Rollout Plan

Phase 1: ...  
Phase 2: ...  
Rollback: ...

## Success Metrics

How will we know this worked?  
- Metric 1: p99 latency < 100ms within 2 weeks
- Metric 2: Zero data inconsistency incidents within 30 days

## Open Questions

List unresolved questions for reviewers.
```

### RFC Review Process
```
Author writes RFC → shares in #eng-rfcs Slack channel
    │
    ├─ 5 business days: async comment period
    │
    ├─ Optional: 1-hour RFC review meeting for complex ones
    │
    ├─ Author updates RFC based on feedback
    │
    └─ Decision: Accepted / Rejected / Needs revision
              (made by author + tech lead/principal)
```

---

## Database Schema Change Management

Schema changes are the highest-risk routine operation. A bad migration on a 500M-row table can lock the table for hours or corrupt data permanently.

### The Three-Phase Migration Pattern

Phase 1 (backward-compatible): Add new schema, old code still works
Phase 2 (code uses new schema): Deploy new code, both old and new schema valid
Phase 3 (cleanup): Remove old schema

**Example: Rename column `user_name` to `display_name`**

```sql
-- Phase 1: Add new column (no lock, instant)
ALTER TABLE users ADD COLUMN display_name VARCHAR(255);
UPDATE users SET display_name = user_name;  -- backfill (batched)

-- Deploy code that reads display_name, falls back to user_name
-- Wait and validate...

-- Phase 2: Deploy code that writes only display_name
-- Wait for all old code to drain...

-- Phase 3: Drop old column (no lock risk — data already gone)
ALTER TABLE users DROP COLUMN user_name;
```

**Migration checklist:**
```
□ Migration tested on production-size dataset in staging
□ Estimated duration measured (use pt-online-schema-change or gh-ost for large tables)
□ Rollback plan documented
□ DBA reviewed migration script
□ Deploy window booked and SRE notified
□ Table row count and size noted (to estimate lock duration)
□ Backfill job designed as idempotent batches (can resume if interrupted)
```

**Tools for zero-downtime schema changes:**
- `gh-ost` (GitHub Online Schema Changer) — copies table online, no lock
- `pt-online-schema-change` (Percona) — trigger-based online ALTER
- Liquibase / Flyway — migration versioning and tracking

---

## Large-Scale Migration Strategy

When migrating a cross-cutting concern (e.g., monolith to microservices, moving to a new auth system, replacing a shared library):

### Strangler Fig Pattern

Wrap the legacy system with a new layer. Migrate routes one-by-one. Delete legacy code when all routes migrated.

```
Phase 1: New system handles /api/v2/*, legacy handles /api/v1/*
Phase 2: Migrate consumers of v1 to v2 one by one (track on dashboard)
Phase 3: v1 routes return HTTP 301 to v2 (grace period)
Phase 4: Decommission legacy
```

### Migration Dashboard
Track progress visibly. Every team should be able to see where they stand:

| Service | Migration status | Target date | Owner |
|---------|-----------------|-------------|-------|
| payment-service | Done | 2025-01-15 | @alice |
| auth-service | In progress | 2025-02-01 | @bob |
| notification-svc | Not started | 2025-03-01 | @carol |

Stale "in progress" items are the principal engineer's concern — they become blockers.

---

## Change Freeze and Deploy Lock

### Types of Change Freezes

**Hard freeze:** No changes of any kind except P0 incident response.
- Major holidays (Thanksgiving, Christmas, New Year)
- Company earnings period (if public)
- Known peak traffic events (Black Friday, major product launch)

**Soft freeze:** No new features; bug fixes and security patches allowed.
- 2 weeks before a major feature launch
- On-call handoff week
- During an extended incident investigation

**Service-level freeze:** Only the affected service is locked.
- Post-incident: no changes until postmortem is complete and action items are addressed
- During active migration: freeze dependent services to avoid interference

### Freeze enforcement
```bash
# GitHub Actions gate: check if in freeze window
- name: Check deploy freeze
  run: |
    FREEZE=$(curl -s https://internal.tools/api/deploy-freeze | jq '.active')
    if [ "$FREEZE" == "true" ]; then
      echo "🚫 Deploy freeze active. Emergency changes require SRE approval."
      exit 1
    fi
```

---

## Change Communication

### Internal communication matrix

| Audience | Channel | When | What |
|----------|---------|------|------|
| Same team | PR description + Slack | At merge | Technical details, rollback plan |
| Dependent teams | #platform-changes Slack | 1 week before | API/contract changes, migration needed |
| All engineering | #engineering Slack | 2 weeks before | Major changes, freeze windows |
| Engineering leadership | Weekly eng digest | As needed | Risk summary, go/no-go decisions |
| Non-technical stakeholders | Email / Confluence | For user-facing changes | Impact, timeline, mitigation |

### Breaking change notification template
```
Subject: [BREAKING CHANGE] Payment API v1 deprecation — action required by 2025-03-01

Team,

What's changing:
  Payment API /v1/charge endpoint will be removed on 2025-03-01.
  It is being replaced by /v2/charge with improved idempotency support.

Who's affected:
  Services currently calling /v1/charge: payment-service, subscription-service, invoicing-service

What you need to do:
  1. Update your client to use /v2/charge (migration guide: link)
  2. Test in staging (both endpoints active until 2025-02-15)
  3. Confirm migration complete to @alice by 2025-02-20

Timeline:
  2025-01-15: v2 available in staging
  2025-02-15: v1 deprecated in staging (returns 410)
  2025-03-01: v1 removed from production

Questions? #payments-eng or DM @alice
```

---

## Change Audit Trail

Every significant change must be traceable:

- **Who** made the change (git blame, PR author)
- **What** changed (PR diff, release notes)
- **Why** it changed (linked RFC, JIRA ticket, incident report)
- **When** it was deployed (deployment log with timestamp)
- **Where** it was deployed (which environment, which region)

For compliance-driven industries (financial services, healthcare), this audit trail is not optional — it's audited by external parties.

Store in: deployment log → linked to CI/CD run → linked to PR → linked to JIRA ticket → linked to RFC.

---

## Interview Framing

**Q: How do you manage a major database migration in production without downtime?**

> I'd use the three-phase migration pattern: first deploy a backward-compatible schema change (add the new column or table, backfill data in batches), then update the code to read and write the new schema while falling back to the old, and finally clean up the old schema after confirming no traffic hits it. For large tables I'd use gh-ost or pt-online-schema-change to avoid locking. I'd test the migration on a production-size dataset in staging first, measure the duration, and book a deploy window with SRE standing by. The key principle is: every phase must be individually deployable and individually rollback-able.

**Q: How do you communicate a breaking API change across a large org?**

> I announce it early and track adoption. Six weeks minimum before the sunset date, with a detailed migration guide and a dashboard showing which services have and haven't migrated. I send the initial notice to #engineering, send direct pings to the team leads of affected services, and check in weekly on blockers. The day before sunset, I re-confirm with every unconverted service. I'm willing to extend the deadline once if there's a legitimate blocker — but I don't let the old API exist indefinitely. The principal engineer's job is to move the org forward, and that sometimes means setting and enforcing a hard date.
