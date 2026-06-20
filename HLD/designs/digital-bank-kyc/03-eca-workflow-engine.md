# 03 — ECA Workflow Engine

## 1. Why ECA over BPMN / Traditional Workflow Engines

| Dimension | BPMN (Camunda/Flowable) | ECA Engine |
|---|---|---|
| Rule updates | Redeploy process definition | Hot-reload rules from DB — no deployment |
| Complexity | Visual but rigid DAG | Composable; conditions are predicates |
| Event-driven fit | Poll-based or webhook injection | Native event consumption from Kafka |
| Multi-channel | Single orchestrator | Each channel emits same event taxonomy |
| Testability | Process context coupling | Each rule independently unit-testable |
| Lead tracking | Built-in audit | Custom but explicit in `lead_events` |

**Decision**: ECA wins for fintech onboarding because compliance rules change every quarter (RBI MD updates). With ECA, a compliance analyst can add a new rule "if PAN linked to 3+ existing accounts → REVIEW" as a DB row without a code release.

---

## 2. ECA Pattern Definition

```
An ECA rule is:
  ON  <Event>
  IF  <Condition expression>
  DO  <Action>

Examples:
  ON  KYC_STEP_COMPLETED(step=AADHAAR_OTP)
  IF  lead.account_type == INDIVIDUAL AND lead.kyc_tier == FULL
  DO  TRIGGER_FACE_LIVENESS

  ON  FRAUD_SCREENING_RESULT(result=BLOCK)
  IF  TRUE                          // unconditional
  DO  REJECT_LEAD, NOTIFY_USER(template=REJECTION), LOG_FIU_IND_SAR

  ON  LEAD_CREATED
  IF  lead.account_type IN [MERCHANT, NODAL, CURRENT]
  DO  SCHEDULE_DOCUMENT_COLLECTION_REMINDER(delay=24h)
```

---

## 3. System Architecture

```
                    ┌─────────────────────────────────────────┐
                    │            ECA Engine                   │
                    │                                         │
  Kafka Topic       │  ┌─────────────┐   ┌────────────────┐  │
  onboarding.events │  │  Event      │   │  Rule          │  │
  ────────────────► │  │  Consumer   │──►│  Matcher       │  │
                    │  │  (per-lead  │   │  (in-memory    │  │
                    │  │  partition) │   │  rule cache)   │  │
                    │  └─────────────┘   └───────┬────────┘  │
                    │                            │            │
                    │                    ┌───────▼────────┐  │
                    │                    │  Condition     │  │
                    │                    │  Evaluator     │  │
                    │                    │  (SpEL / CEL)  │  │
                    │                    └───────┬────────┘  │
                    │                            │            │
                    │                    ┌───────▼────────┐  │
                    │                    │  Action        │  │
                    │                    │  Dispatcher    │  │
                    │                    └───────┬────────┘  │
                    │                            │            │
                    └────────────────────────────┼────────────┘
                                                 │
                 ┌───────────────────────────────┼────────────────┐
                 │                               │                │
          ┌──────▼──────┐              ┌─────────▼──────┐  ┌─────▼──────┐
          │Lead Service │              │Notification Svc│  │Scheduler   │
          │(state update│              │(SMS/Email/Push)│  │(cron jobs) │
          │+ audit)     │              └────────────────┘  └────────────┘
          └─────────────┘
```

### 3.1 Event Consumer

- Kafka consumer group `eca-engine`, partitioned by `leadId` (ensures ordering per lead)
- At-least-once delivery; action dispatcher is idempotent (dedup via `event_id`)
- Consumer lag alert threshold: 30 seconds (99th percentile normal: < 2s)

### 3.2 Rule Cache

```java
@Component
public class RuleCache {
    // Rules loaded from PostgreSQL `eca_rules` table at startup
    // Hot-reload every 60 seconds via scheduled refresh
    // Version vector: if DB version > cache version, reload
    private final ConcurrentHashMap<String, List<EcaRule>> rulesByEventType;

    public List<EcaRule> getRulesFor(String eventType) {
        return rulesByEventType.getOrDefault(eventType, List.of());
    }
}
```

### 3.3 Condition Evaluator

Uses **Common Expression Language (CEL)** — Google's CEL, used in Firebase, Kubernetes admission webhooks — for safe, sandboxed evaluation of arbitrary expressions without Turing-completeness risks.

```java
public class ConditionEvaluator {
    private final CelRuntime celRuntime;

    public boolean evaluate(String expression, LeadContext ctx) {
        // ctx is the evaluation context: lead fields, event payload, time
        // Expression: "lead.account_type == 'INDIVIDUAL' && lead.fraud_score < 50"
        Program program = celRuntime.createProgram(expression);
        return (Boolean) program.eval(Map.of("lead", ctx.toLead(), "event", ctx.getEvent()));
    }
}
```

**Why CEL over SpEL?** CEL is evaluated in a sandbox with no reflection or side effects. A compromised rule cannot call arbitrary Java methods. SpEL allows `T(Runtime).getRuntime().exec(...)`.

### 3.4 Action Dispatcher

```java
public interface EcaAction {
    String actionType();           // matches rule.action_type
    void execute(ActionContext ctx); // idempotent
}

// Registry of actions:
// ADVANCE_LEAD_STATE
// TRIGGER_KYC_STEP
// REJECT_LEAD
// APPROVE_LEAD
// NOTIFY_USER
// NOTIFY_COMPLIANCE_TEAM
// SCHEDULE_JOB
// UPLOAD_TO_CKYC
// FLAG_FOR_MANUAL_REVIEW
// FREEZE_ACCOUNT
// TRIGGER_REKYC
// EMIT_SAR
// CLOSE_ACCOUNT
```

---

## 4. ECA Rules Data Model

```sql
CREATE TABLE eca_rules (
    id              UUID PRIMARY KEY,
    name            VARCHAR(128) UNIQUE NOT NULL,
    description     TEXT,
    event_type      VARCHAR(64) NOT NULL,     -- e.g. KYC_STEP_COMPLETED
    event_filter    JSONB,                    -- pre-filter before CEL (index-friendly)
    condition_expr  TEXT NOT NULL,            -- CEL expression
    actions         JSONB NOT NULL,           -- [{type, params}, ...]
    priority        SMALLINT DEFAULT 100,     -- lower = higher priority
    enabled         BOOLEAN DEFAULT TRUE,
    effective_from  TIMESTAMPTZ,
    effective_until TIMESTAMPTZ,              -- for time-bounded compliance rules
    created_by      VARCHAR(64),
    version         INT DEFAULT 1,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Example row:
INSERT INTO eca_rules (name, event_type, event_filter, condition_expr, actions, priority) VALUES (
  'wallet-min-kyc-completion',
  'MOBILE_OTP_VERIFIED',
  '{"account_type": "WALLET_MIN"}',
  'lead.kyc_tier == "MINIMUM"',
  '[{"type": "ADVANCE_LEAD_STATE", "params": {"to_state": "KYC_COMPLETE"}},
    {"type": "TRIGGER_FRAUD_SCREENING", "params": {}},
    {"type": "NOTIFY_USER", "params": {"template": "KYC_PENDING_COMPLETION"}}]',
  10
);
```

---

## 5. Complete Event Taxonomy

### 5.1 Onboarding Lifecycle Events

| Event Type | Payload Fields | Trigger |
|---|---|---|
| `LEAD_CREATED` | leadId, accountType, channel | POST /leads |
| `CONSENT_CAPTURED` | leadId, consentVersion, timestamp | Consent step done |
| `MOBILE_OTP_VERIFIED` | leadId, mobile_hash | OTP verified |
| `CKYC_FOUND` | leadId, ckycNumber, source | CKYC registry hit |
| `CKYC_NOT_FOUND` | leadId | CKYC registry miss |
| `KYC_STEP_COMPLETED` | leadId, step, method | Each verification step |
| `KYC_STEP_FAILED` | leadId, step, reason, attemptCount | Verification failure |
| `KYC_COMPLETE` | leadId, kycTier | All steps passed |
| `FRAUD_SCREENING_STARTED` | leadId | Screening initiated |
| `FRAUD_SCREENING_RESULT` | leadId, result, score, flags[] | Screening done |
| `MANUAL_REVIEW_ASSIGNED` | leadId, agentId | Assigned to reviewer |
| `MANUAL_REVIEW_APPROVED` | leadId, agentId, notes | Reviewer approves |
| `MANUAL_REVIEW_REJECTED` | leadId, agentId, reason | Reviewer rejects |
| `ACCOUNT_CREATED` | leadId, accountId, accountType | Account provisioned |
| `LEAD_EXPIRED` | leadId | TTL elapsed |
| `LEAD_ABANDONED` | leadId | User dropped off |
| `LEAD_REJECTED` | leadId, reason | Final rejection |

### 5.2 Post-Onboarding Events (Account Lifecycle)

| Event Type | ECA Action |
|---|---|
| `ACCOUNT_ACTIVATED` | Send welcome pack; schedule CKYC upload (T+3 days); set re-KYC reminder |
| `TRANSACTION_SUSPICIOUS` | Trigger AML review; possibly freeze |
| `KYC_EXPIRY_APPROACHING` | Send re-KYC reminder (T-30, T-7, T-1 days) |
| `KYC_EXPIRED` | Restrict account to view-only; notify user |
| `PEP_STATUS_CHANGED` | Upgrade to EDD; notify compliance team |
| `ADDRESS_CHANGE_REQUEST` | Trigger address proof re-verification |
| `HIGH_VALUE_TRANSACTION` | Trigger enhanced monitoring |
| `REGULATORY_CHANGE` | Batch re-process affected accounts' rules |

---

## 6. Lead State Machine (FSM)

```
CREATED
  │
  ▼ [CONSENT_CAPTURED event]
CONSENT_CAPTURED
  │
  ▼ [MOBILE_OTP_VERIFIED event]
KYC_IN_PROGRESS ◄────────────────────────────────────────────────┐
  │                                                               │
  ├── [KYC_STEP_FAILED × 3] ─────────────────────────────────────┤
  │                                                               │
  ▼ [KYC_COMPLETE event]                                   MANUAL_REVIEW
KYC_COMPLETE                                                      │
  │                                                               │
  ▼ [FRAUD_SCREENING_STARTED event]                               │
FRAUD_SCREENING                                                   │
  │                                                               │
  ├──[result=BLOCK]──► REJECTED (terminal)                        │
  │                                                               │
  ├──[result=REVIEW]──────────────────────────────────────────────┘
  │
  ▼ [result=PASS]
SCREENED_PASS
  │
  ▼ [account creation initiated]
ACCOUNT_CREATION
  │
  ├──[failure]──► MANUAL_REVIEW
  │
  ▼ [ACCOUNT_CREATED event]
ACTIVE (terminal — lead is done; account lifecycle begins)

ABANDONED: from any non-terminal state after user inactivity timeout (7 days)
EXPIRED:   from CREATED / CONSENT_CAPTURED after 7 days
```

### 6.1 Concurrency Control

Each lead has a **version counter** (optimistic locking). State transitions use:

```sql
UPDATE leads
SET state = :newState, version = version + 1, updated_at = NOW()
WHERE id = :leadId AND version = :expectedVersion AND state = :expectedCurrentState;
-- If 0 rows updated → concurrent modification detected → retry with exponential backoff
```

ECA consumers process events per-lead on the same Kafka partition, providing ordering. The optimistic lock is a safety net for rare race conditions (e.g., two rules firing simultaneously on the same lead).

---

## 7. Lead Tracking Dashboard (Ops)

ECA engine emits `lead_events` with full context. The ops dashboard queries:

```sql
-- Funnel drop-off analysis
SELECT
    state,
    account_type,
    COUNT(*) as count,
    AVG(EXTRACT(EPOCH FROM (updated_at - created_at))) as avg_time_in_state_sec
FROM leads
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY state, account_type
ORDER BY account_type, state;

-- KYC step failure rates
SELECT
    (metadata->>'step') as kyc_step,
    COUNT(*) as failures,
    (metadata->>'reason') as top_reason
FROM lead_events
WHERE event_type = 'KYC_STEP_FAILED'
  AND created_at > NOW() - INTERVAL '1 day'
GROUP BY kyc_step, top_reason
ORDER BY failures DESC;

-- Manual review queue SLA (RBI: must resolve within 3 days)
SELECT
    lead_id,
    assigned_agent,
    EXTRACT(EPOCH FROM (NOW() - entered_review_at))/3600 as hours_in_review
FROM manual_review_queue
WHERE status = 'OPEN'
  AND entered_review_at < NOW() - INTERVAL '60 hours'
ORDER BY entered_review_at ASC;
```

---

## 8. Rule Hot-Reload Safety

Adding a new ECA rule without deployment introduces risk:

| Safety Mechanism | Implementation |
|---|---|
| Rule dry-run mode | `effective_from` in future; engine logs what would fire but doesn't act |
| Shadow mode | Rule fires in shadow (logs only) for 24h before activation |
| Canary rollout | Rule enabled for 1% of leads by feature flag |
| Rollback | Set `enabled = FALSE`; takes effect within 60s (next cache refresh) |
| Rule audit log | Every rule evaluation logged with input context + outcome |
| Approval workflow | DB insert requires 2-person approval (maker-checker) via compliance portal |

---

## FAANG Interview Callout

> "How do you prevent an ECA rule from creating an infinite event loop? (e.g., Action emits Event X → Rule fires on X → Action emits X again)"

**Answer**: 
1. CEL conditions are sandboxed — actions cannot directly emit events; they call registered action handlers which go through the Dispatcher.
2. Dispatcher tracks `(leadId, ruleId, eventId)` in Redis with 5-minute TTL — same rule cannot fire twice for the same event.
3. Event emission from an action requires a different event type than the triggering event (validated at rule-save time by a DAG cycle detector run against the rule graph).
4. Circuit breaker on the action dispatcher: if a single lead fires > 20 actions in 60 seconds, freeze that lead and alert on-call.
