# Change Management Process

**Category**: Engineering Operations · Risk Management · Deployment Safety  
**Audience**: Principal / Staff Engineers owning safe change delivery and deployment practices  
**Related**: [Incident Response Playbook](incident-response-playbook.md) · [PRR](production-readiness-review.md) · [CI/CD Pipeline Design](../ci-cd/01-pipeline-design.md)

> "Every change is a risk. Good change management doesn't eliminate risk — it makes risk visible, measurable, and bounded. The goal is not to slow down change but to ensure that when a change causes a problem, you can detect it in minutes and reverse it in seconds."

---

## Change Risk Model

Not all changes are equal. Risk is a function of blast radius (how many users are affected if this goes wrong) and reversibility (how quickly can this be undone).

**Change risk matrix**:

```
                    HIGH blast radius
                         │
    HIGH risk            │           HIGHEST risk
    (requires approval)  │           (requires extensive gates)
                         │
─────────────────────────┼─────────────────────────────
                         │
    LOWEST risk          │           MEDIUM risk
    (standard deployment)│           (requires testing + review)
                         │
                   LOW blast radius

        ◄──── Hard to reverse ────────── Easy to reverse ────►
```

| Risk Level | Example | Process Required |
|-----------|---------|-----------------|
| **Low** | Bug fix to non-critical path, feature flag toggle | Standard CI/CD, single reviewer |
| **Medium** | New endpoint, config change, dependency upgrade | PRR review, load test, staging validation |
| **High** | Database schema change, auth system change, pricing change | Change window, additional reviewer, rollback tested |
| **Critical** | Production database migration, security system change, payment flow | CAB approval, change window, staged rollout, war room |

---

## Change Categories

### Category 1: Standard Changes (pre-approved)

Standard changes are low-risk, well-understood changes that have been executed many times before. They follow a pre-approved process with no additional approval required.

**Examples**:
- Code deployments through CI/CD pipeline to tested code
- Feature flag toggles (enabling/disabling features)
- Certificate renewals (automated)
- Log level adjustments
- Auto-scaling policy adjustments within approved bounds

**Process**:
```
1. Engineer submits PR → automated CI checks run
2. Peer review (1 approver minimum for production services)
3. Staging deployment + automated validation
4. Canary deployment (1-5% traffic)
5. Automated promotion if metrics healthy
6. Full rollout
7. Monitor for 30 minutes post-rollout
```

**Rollback**: Automatic (error rate threshold) or manual (< 5 minutes via CI/CD pipeline)

---

### Category 2: Normal Changes (standard approval)

Changes that follow the standard process but require additional verification due to moderate risk.

**Examples**:
- New API endpoints
- New service dependencies
- Configuration changes with moderate impact
- Database index additions (no data changes)
- Third-party library major version upgrades

**Process**:
```
1. Engineer creates change request (PR + change description)
2. Two-reviewer code review (one domain expert, one ops/reliability)
3. Staging deployment with integration test suite
4. Performance validation (load test if traffic-impacting)
5. Canary deployment (1% → 5% → 25% with manual gates)
6. Change owner monitors for 2 hours post-rollout
7. Post-change review if any anomalies observed
```

**Change window**: Weekdays 10am–4pm local time (avoids peak traffic hours + ensures full team available)  
**Rollback**: Manual, < 10 minutes

---

### Category 3: Emergency Changes

Changes that must be deployed immediately to resolve or prevent a production incident.

**Examples**:
- Hotfix for active SEV-1 incident
- Security vulnerability patch (actively exploited)
- Data loss prevention fix

**Process**:
```
1. Incident Commander approves emergency change
2. One technical reviewer (can be concurrent with deployment for SEV-0)
3. Expedited CI/CD pipeline (may skip non-critical tests)
4. Canary if time permits (at minimum: 5 minutes of monitoring at 1% traffic)
5. Full rollout with continuous monitoring
6. Post-incident review documents the emergency change
7. Normal change process retroactively applied (post-mortem action item)
```

**Change window**: Any time (by definition — this is an emergency)  
**Approval authority**: Incident Commander + one senior engineer  
**Rollback**: Must be defined before deployment is authorized

---

### Category 4: Major Changes (CAB or equivalent review)

Changes with the highest risk profile that require formal review by a Change Advisory Board or equivalent process.

**Examples**:
- Database schema migrations on large tables (> 10M rows)
- Authentication system changes (affects all users)
- Payment processing changes
- Pricing or billing system changes
- Cryptographic key rotation
- Major infrastructure migrations (cloud provider, region change)

**Process**:
```
1. Change Proposal submitted 5 business days before target date
   Contents: what changes, why, risk assessment, rollback plan, success criteria
2. CAB review: SRE/Platform + Security + EM + affected team leads
3. Test in staging with production-equivalent data volume (or subset)
4. Dry-run rehearsal (if applicable — e.g., DB migration tested on a copy of production data)
5. Change window scheduled (typically weekend, off-hours for user-facing systems)
6. War room during change window: change owner + SRE + relevant team leads available
7. Staged rollout with defined checkpoints and rollback triggers
8. 24-48h monitoring period with reduced deployment activity
9. Post-change review (all Category 4 changes)
```

**Approval authority**: Engineering Manager + SRE/Platform lead + Security (for security-related changes)

---

## Database Schema Changes

Database schema changes deserve special treatment because they are among the most dangerous changes in any system.

### Why DB Migrations Are Dangerous

- **Table locks**: `ALTER TABLE` on a large table can lock the table for minutes to hours (blocks all reads/writes)
- **Long-running transactions**: A schema migration running alongside normal traffic can cause deadlocks
- **Irreversibility**: Some migrations are hard or impossible to reverse cleanly
- **Data consistency**: Migration bugs can corrupt data silently

### Safe Migration Patterns

**Pattern 1: Expand-Contract (the standard pattern for additive changes)**

```
Phase 1: Expand (additive, non-breaking)
  - Add new column (nullable or with default)
  - Add new table
  - Add new index (in background, non-blocking)
  Application writes to both old and new; reads from old
  Deploy: standard change process

Phase 2: Backfill (data migration)
  - Populate new column from old column
  - Run in batches with rate limiting (avoid lock contention)
  - Example: UPDATE table SET new_col = old_col WHERE new_col IS NULL LIMIT 1000
  Monitor: replication lag, table lock wait time, query performance

Phase 3: Contract (remove old, now safe)
  - Switch application to read new column
  - Remove old column (after application is fully migrated)
  Deploy: standard change process after Phase 2 is 100% complete
```

**Pattern 2: Rename Column (the dangerous one)**
```
WRONG:  Rename column in one atomic change → all apps break until deployed
RIGHT:
  Step 1: Add new column alongside old
  Step 2: Deploy app that writes to both old AND new
  Step 3: Backfill new column where null
  Step 4: Deploy app that reads new column
  Step 5: Deploy app that no longer writes old column
  Step 6: Drop old column
  This takes 5 deploys and 2 weeks — that is correct for production safety
```

**Pattern 3: Large Table Index**
```
WRONG:  CREATE INDEX ON large_table(column) -- blocks all reads/writes during build

RIGHT:  CREATE INDEX CONCURRENTLY ON large_table(column) -- runs in background, no lock
        Note: CONCURRENTLY takes longer but does not lock; standard in PostgreSQL, MySQL 8+
        Monitor: index build progress, replication lag, query performance during build
```

**Migration safety checklist**:
```
□ Migration is reviewed by a database-experienced engineer
□ Migration tested on a copy of production data (or proportional sample)
□ Estimated duration measured in staging (time scales with data volume)
□ Table lock risk assessed (any LOCK TABLE or non-concurrent index?)
□ Rollback plan documented and tested
□ Migration is idempotent (safe to run twice without corrupting data)
□ Batching implemented for data backfills (max 1,000 rows per batch with SLEEP)
□ Change window booked (off-peak hours for large tables)
□ Monitoring dashboard open during migration
□ DBA notified if table size > 100GB or estimated duration > 30 minutes
```

---

## Change Windows

### When to Use Change Windows

A **change window** is a pre-scheduled time slot reserved for high-risk changes, where the team is available to monitor and respond if something goes wrong.

**Use change windows for**:
- Database migrations on tables > 10M rows
- Infrastructure migrations (new load balancer, new database cluster)
- Third-party service migrations (changing CDN, payment processor)
- Authentication or authorization system changes
- Any change where rollback takes > 10 minutes

**Standard change windows**:

| Window Type | Time | Duration | Use For |
|------------|------|----------|---------|
| **Low-traffic window** | Tuesday–Thursday, 2am–4am local | 2 hours | Large DB migrations |
| **Business hours** | Tuesday–Thursday, 10am–4pm | 6 hours | Medium-risk changes with team available |
| **Weekend window** | Saturday, 6am–10am | 4 hours | Infrastructure migrations, high-risk changes |
| **Freeze window** | None — no changes | N/A | Holiday periods, major events |

### Change Freeze Periods

**When to freeze changes**:
- 2 weeks before a major product launch
- Holiday shopping season (e.g., Black Friday week for e-commerce)
- During an ongoing SEV-1/SEV-0 incident
- When error budget < 10% (see SLO policy)

**What is allowed during a freeze**:
- Security patches for actively exploited vulnerabilities
- Emergency hotfixes for active incidents
- Read-only infrastructure changes (adding monitoring, not modifying services)

**What is not allowed during a freeze**:
- Feature deployments
- Database migrations
- Infrastructure upgrades
- Dependency upgrades

---

## Rollback Protocol

Every change must have a rollback plan defined before it is deployed.

### Rollback Criteria (when to roll back)

```
Automatic rollback triggers (configured in deployment system):
  □ Error rate increase > 2× pre-deployment baseline within 10 minutes
  □ P99 latency increase > 1.5× pre-deployment baseline within 10 minutes
  □ Success rate drops below SLO threshold

Manual rollback triggers (human decides to roll back):
  □ Alert fires within 30 minutes of deployment
  □ Unexpected error patterns in logs
  □ Downstream service reports increased errors after deployment
  □ Business metrics drop unexpectedly (order rate, conversion rate)
```

### Rollback Methods by Change Type

| Change Type | Rollback Method | Time to Rollback |
|------------|----------------|-----------------|
| Code deployment | Re-deploy previous container image | 3-5 minutes |
| Feature flag | Toggle flag off | < 1 minute |
| Config change | Re-apply previous config | 2-5 minutes |
| DB column addition (expand phase) | Drop the column (if no writes yet) | Minutes |
| DB column removal | Restore from backup — cannot rollback fast | Hours |
| Index addition | Drop index | Minutes (CONCURRENTLY for large tables) |
| Infrastructure change | Depends on change; test in staging first | Hours |

**Golden rule**: If rollback takes > 30 minutes, the change requires a change window, war room, and explicit go/no-go checkpoints.

---

## Change Communication

### Communication Template (for normal and major changes)

```
Announcement (sent to engineering-changes Slack channel, 24h before):

[CHANGE NOTICE] [service-name] — [brief description]
Date/Time: [date], [start time]–[end time] UTC
Risk Level: [Low / Medium / High / Critical]
Expected Impact: [None / Brief latency increase (< 30s) / Brief error spike / Potential downtime]
Rollback Plan: [Rollback method and time]
Owner: @[name]
War Room: [Zoom link, if applicable]
Dashboard: [link to service dashboard]
```

**Post-change communication** (within 1 hour of completion):
```
[CHANGE COMPLETE] [service-name] — [brief description]
Status: [Successful / Rolled Back / Partially Complete]
Duration: [actual duration]
Issues observed: [None / describe issues]
Current status: [Service healthy / Monitoring / Investigating]
```

---

## FAANG Interview Framing

### "How do you manage risk when deploying changes to a system serving 100M users?"

> "Risk management in deployments starts before code is written, not at deploy time. My framework has three components: change categorization, deployment mechanics, and automatic rollback. For categorization, I classify every change by blast radius and reversibility — a nullable column addition is low risk; removing a column is high risk. For deployment mechanics, I use progressive rollout by default: 1% canary with automatic promotion based on error rate and latency signals. The key is measuring the right things during the rollout window — not just that the service is running, but that the specific functionality the change touches is working correctly. For automatic rollback, I configure the deployment system to revert if error rate increases more than 2× within 10 minutes of deployment. The goal is that a bad deploy is detected and reversed before most users experience it. At 100M users, 1% canary means 1M users — that's still a large blast radius, so I also invest in pre-production environments that mirror production scale."

### "Walk me through how you would manage a database schema migration on a 500M row table."

> "A migration on a 500M row table requires the expand-contract pattern, not a single ALTER TABLE. First, I add the new column as nullable alongside the existing column — this is instant and non-blocking. Then I backfill in batches of 1,000 rows with a sleep between batches to avoid lock contention and replication lag. At 500M rows, even at 1,000 rows/second that's 8 minutes of backfill — in practice much slower with sleep, so I'd estimate 2-4 hours and schedule a change window. I run the backfill in a transaction block with monitoring on table lock wait time and replication lag. The application is updated to write to both columns in parallel while the backfill runs. Only after 100% of rows are populated do I cut the read path over to the new column. The old column is dropped in a separate change after the application is confirmed working. The total process takes 2-3 deploys over 2 weeks, which is the correct cadence for production safety at this scale."
