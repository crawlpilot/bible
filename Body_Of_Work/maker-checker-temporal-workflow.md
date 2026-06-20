# Maker-Checker Product Mapping Workflow — Temporal Implementation

**Domain:** Competitive Intelligence / Data Quality  
**Pattern:** Maker-Checker (4-eyes principle)  
**Orchestration:** Temporal.io Workflow Engine  
**Problem solved:** Long-running, human-in-the-loop business processes that span days, have complex state machines, require audit trails, and must survive process restarts without losing state

---

## Problem Statement

The business needed a system to map internal product catalog items to equivalent competitor products — critical for price comparison, assortment analysis, and market benchmarking. The mapping process combined:

- **Automated matching** (UPC/GTIN, title fuzzy match, attribute similarity, image similarity)
- **Human review** (Mapping Analyst creates/validates)
- **Independent audit** (Audit Analyst approves/rejects/escalates)

The naive implementation — REST API calls between services + a database state machine — had fundamental weaknesses:

1. **Durability:** A server restart mid-workflow lost in-progress state; tasks had to be rebuilt from DB polling
2. **Timeout management:** Tasks sitting in analyst queues for days required cron jobs to detect SLA breaches
3. **Retry logic:** Downstream service failures (matching engine, notification service) needed manual retry code scattered across services
4. **Audit trail:** Reconstructing "what happened and why" required joining 6 tables
5. **Complexity of state machine:** 9 states × N transition rules — every new state required careful DB migration + code change coordination

**Decision:** Model the entire lifecycle as a **Temporal workflow**. Each product mapping request becomes a durable, long-running workflow execution. The workflow encodes the state machine, the timeouts, the retry policies, and the audit history — all in one place.

---

## Why Temporal

Temporal's core value proposition for this use case:

| Requirement | Without Temporal | With Temporal |
|-------------|-----------------|---------------|
| Workflow survives server restart | DB polling + rebuild logic | Automatic — event sourced replay |
| Human task waits for days | Cron jobs + queue sweepers | `workflow.WaitForSignal()` — zero infra |
| SLA timeout on analyst action | Scheduled job checks deadlines | `workflow.Sleep()` + timeout branch |
| Retry failed service calls | Manual try/catch + retry table | Activity retry policy (exponential backoff) |
| Audit trail | Event log table (manually maintained) | Temporal event history (free) |
| State visibility | Custom admin UI querying DB | Temporal Web UI / `tctl` |
| Pause / resume / cancel | Complex state machine code | Built-in workflow signals |

Temporal's execution model: **workflows are code that appears to execute sequentially but is actually event-sourced and replayed**. The Temporal server durably records every event (activity scheduled, completed, signal received, timer fired). On worker restart, the workflow code replays from the beginning using recorded events — reaching the same state deterministically without re-executing side effects.

---

## System Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                        Client Applications                           │
│   Product Ingestion API    Analyst Portal    Operations Dashboard    │
└──────────┬───────────────────────┬──────────────────┬───────────────┘
           │ Start workflow        │ Signal (action)  │ Query (state)
           ▼                       ▼                  ▼
┌──────────────────────────────────────────────────────────────────────┐
│                         Temporal Server                              │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                    Workflow Execution                        │    │
│  │  ProductMappingWorkflow (one per source product)            │    │
│  │  - Durable state machine                                    │    │
│  │  - Signal handlers (APPROVE, REJECT, ESCALATE, REWORK)      │    │
│  │  - Query handlers (currentStatus, auditTrail)               │    │
│  │  - Timer-based SLA enforcement                              │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                              │                                        │
│                   Schedules Activities on                            │
└──────────────────────────────┼───────────────────────────────────────┘
                               │
              ┌────────────────┼─────────────────┐
              ▼                ▼                  ▼
   ┌──────────────────┐  ┌──────────────┐  ┌─────────────────────┐
   │  Matching Worker │  │ Audit Worker │  │ Notification Worker │
   │  (Activities)    │  │ (Activities) │  │ (Activities)        │
   │  - runUPCMatch   │  │ - assignAudit│  │ - notifyAnalyst     │
   │  - runTitleMatch │  │ - submitAudit│  │ - notifyEscalation  │
   │  - runAttrMatch  │  │ - escalate   │  │ - sendSLAAlert      │
   │  - runImgMatch   │  └──────────────┘  └─────────────────────┘
   └──────────────────┘
              │
              ▼
   ┌──────────────────┐
   │  Matching Engine │
   │  (ML Service)    │
   │  - UPC lookup    │
   │  - Embedding sim │
   │  - Image CV      │
   └──────────────────┘
```

---

## Workflow State Machine

```
                       ┌─────────────┐
                       │     NEW     │
                       │ (ingested)  │
                       └──────┬──────┘
                              │ Start automated matching
                              ▼
                       ┌─────────────┐
                       │  MATCHING   │
                       │ (in-flight) │
                       └──────┬──────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
        High conf       Medium conf       No match
              │               │               │
              ▼               ▼               ▼
      ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
      │ AUTO-MATCHED │  │ PENDING      │  │ MANUAL       │
      │              │  │ REVIEW       │  │ MAPPING      │
      └──────┬───────┘  └──────┬───────┘  └──────┬───────┘
             │                 │                  │
             │          Maker reviews       Maker creates
             │          / confirms          mapping
             │                 │                  │
             └─────────────────┴──────────────────┘
                               │
                               ▼
                       ┌──────────────┐
                       │ PENDING      │
                       │ AUDIT        │◄─────── (Rejected: rework)
                       └──────┬───────┘
                              │
              ┌───────────────┼────────────────┐
              │               │                │
           Approve         Reject          Escalate
              │               │                │
              ▼               ▼                ▼
      ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
      │   APPROVED   │  │   REJECTED   │  │  ESCALATED   │
      │ (Active Map) │  │ (Back to     │  │ (SME Review) │
      └──────────────┘  │  Maker)      │  └──────┬───────┘
                        └──────────────┘         │
                                                 │ SME resolves
                                                 ▼
                                         ┌──────────────┐
                                         │   APPROVED   │
                                         │  or REJECTED │
                                         └──────────────┘
```

---

## Core Workflow Implementation

### Workflow Definition (Java — Temporal SDK)

```java
@WorkflowInterface
public interface ProductMappingWorkflow {
    @WorkflowMethod
    MappingResult execute(MappingRequest request);

    // Signals — external events that drive the workflow forward
    @SignalMethod
    void submitMakerAction(MakerAction action);

    @SignalMethod
    void submitAuditDecision(AuditDecision decision);

    @SignalMethod
    void submitEscalationResolution(EscalationResolution resolution);

    // Queries — read current state without modifying it
    @QueryMethod
    MappingStatus getCurrentStatus();

    @QueryMethod
    List<AuditEvent> getAuditTrail();
}
```

### Workflow Implementation

```java
public class ProductMappingWorkflowImpl implements ProductMappingWorkflow {

    private final MatchingActivities matchingActivities =
        Workflow.newActivityStub(MatchingActivities.class,
            ActivityOptions.newBuilder()
                .setStartToCloseTimeout(Duration.ofMinutes(5))
                .setRetryOptions(RetryOptions.newBuilder()
                    .setMaximumAttempts(3)
                    .setInitialInterval(Duration.ofSeconds(2))
                    .setBackoffCoefficient(2.0)
                    .build())
                .build());

    private final NotificationActivities notificationActivities =
        Workflow.newActivityStub(NotificationActivities.class,
            ActivityOptions.newBuilder()
                .setStartToCloseTimeout(Duration.ofSeconds(30))
                .setRetryOptions(RetryOptions.newBuilder()
                    .setMaximumAttempts(5)
                    .build())
                .build());

    // Workflow-local mutable state (safe: only one thread executes workflow code)
    private MappingStatus currentStatus = MappingStatus.NEW;
    private List<AuditEvent> auditTrail = new ArrayList<>();
    private MakerAction pendingMakerAction;
    private AuditDecision pendingAuditDecision;
    private EscalationResolution pendingEscalationResolution;

    @Override
    public MappingResult execute(MappingRequest request) {

        // ── STEP 1: Run automated matching ──────────────────────────────
        currentStatus = MappingStatus.MATCHING;
        MatchingResult matchResult = matchingActivities.runAutomatedMatching(request);
        recordAuditEvent("SYSTEM", "Automated matching completed",
            "confidence=" + matchResult.getConfidenceScore());

        // ── STEP 2: Route based on confidence ───────────────────────────
        if (matchResult.getConfidenceScore() >= HIGH_CONFIDENCE_THRESHOLD) {
            currentStatus = MappingStatus.AUTO_MATCHED;
            notificationActivities.notifyAuditQueue(request.getSourceProductId(),
                matchResult.getBestCandidate());
            recordAuditEvent("SYSTEM", "High-confidence match: routed to audit queue",
                matchResult.getBestCandidate().getCompetitorProductId());

        } else if (matchResult.getConfidenceScore() >= MEDIUM_CONFIDENCE_THRESHOLD) {
            currentStatus = MappingStatus.PENDING_REVIEW;
            notificationActivities.notifyMakerQueue(request.getSourceProductId(),
                matchResult.getCandidates());
            recordAuditEvent("SYSTEM", "Medium-confidence match: routed to maker review",
                "candidates=" + matchResult.getCandidates().size());

            // Wait for maker action — or SLA breach
            boolean makerActed = Workflow.await(
                Duration.ofHours(MAKER_SLA_HOURS),
                () -> pendingMakerAction != null
            );

            if (!makerActed) {
                // SLA breached — escalate to operations
                currentStatus = MappingStatus.ESCALATED;
                notificationActivities.sendSLAAlert(request.getSourceProductId(),
                    "MAKER_SLA_BREACH", MAKER_SLA_HOURS + "h SLA exceeded");
                recordAuditEvent("SYSTEM", "Maker SLA breached — escalated",
                    "SLA=" + MAKER_SLA_HOURS + "h");
                return handleEscalation(request);
            }

            processMakerAction(pendingMakerAction);

        } else {
            currentStatus = MappingStatus.MANUAL_MAPPING;
            notificationActivities.notifyManualMappingQueue(request.getSourceProductId());
            recordAuditEvent("SYSTEM", "No match found: sent to manual mapping queue", "");

            // Wait for maker to create manual mapping — or SLA breach
            boolean makerActed = Workflow.await(
                Duration.ofHours(MANUAL_MAPPING_SLA_HOURS),
                () -> pendingMakerAction != null
            );

            if (!makerActed) {
                currentStatus = MappingStatus.ESCALATED;
                notificationActivities.sendSLAAlert(request.getSourceProductId(),
                    "MANUAL_MAPPING_SLA_BREACH",
                    MANUAL_MAPPING_SLA_HOURS + "h SLA exceeded");
                recordAuditEvent("SYSTEM", "Manual mapping SLA breached — escalated", "");
                return handleEscalation(request);
            }

            processMakerAction(pendingMakerAction);
        }

        // ── STEP 3: Audit ────────────────────────────────────────────────
        return runAuditPhase(request);
    }

    private MappingResult runAuditPhase(MappingRequest request) {
        currentStatus = MappingStatus.PENDING_AUDIT;
        notificationActivities.notifyAuditQueue(request.getSourceProductId(), null);
        recordAuditEvent("SYSTEM", "Submitted to audit queue", "");

        boolean auditActed = Workflow.await(
            Duration.ofHours(AUDIT_SLA_HOURS),
            () -> pendingAuditDecision != null
        );

        if (!auditActed) {
            currentStatus = MappingStatus.ESCALATED;
            notificationActivities.sendSLAAlert(request.getSourceProductId(),
                "AUDIT_SLA_BREACH", AUDIT_SLA_HOURS + "h SLA exceeded");
            recordAuditEvent("SYSTEM", "Audit SLA breached — escalated", "");
            return handleEscalation(request);
        }

        AuditDecision decision = pendingAuditDecision;
        pendingAuditDecision = null;

        switch (decision.getOutcome()) {
            case APPROVED:
                currentStatus = MappingStatus.APPROVED;
                recordAuditEvent(decision.getAuditorId(), "APPROVED", decision.getComments());
                notificationActivities.publishApprovedMapping(
                    request.getSourceProductId(), decision.getMappingId());
                return MappingResult.approved(decision.getMappingId(), auditTrail);

            case REJECTED:
                currentStatus = MappingStatus.REJECTED;
                recordAuditEvent(decision.getAuditorId(), "REJECTED", decision.getComments());
                notificationActivities.notifyMakerRejection(
                    request.getSourceProductId(), decision.getRejectionReason());

                // Reset and return to maker — workflow continues (no recursion limit)
                pendingMakerAction = null;
                pendingAuditDecision = null;
                currentStatus = MappingStatus.PENDING_REVIEW;
                notificationActivities.notifyMakerQueue(
                    request.getSourceProductId(), List.of());
                recordAuditEvent("SYSTEM", "Returned to maker after rejection", "");

                // Wait for rework
                Workflow.await(Duration.ofHours(REWORK_SLA_HOURS),
                    () -> pendingMakerAction != null);
                processMakerAction(pendingMakerAction);
                return runAuditPhase(request);  // Re-enter audit phase

            case ESCALATED:
                currentStatus = MappingStatus.ESCALATED;
                recordAuditEvent(decision.getAuditorId(), "ESCALATED", decision.getComments());
                return handleEscalation(request);

            default:
                throw new IllegalStateException("Unknown audit outcome: " + decision.getOutcome());
        }
    }

    private MappingResult handleEscalation(MappingRequest request) {
        notificationActivities.notifyEscalationQueue(request.getSourceProductId());
        recordAuditEvent("SYSTEM", "Escalated to SME queue", "");

        Workflow.await(Duration.ofHours(ESCALATION_SLA_HOURS),
            () -> pendingEscalationResolution != null);

        if (pendingEscalationResolution == null) {
            // Hard stop — archive after max escalation wait
            currentStatus = MappingStatus.ARCHIVED;
            recordAuditEvent("SYSTEM", "Archived: escalation timeout exceeded", "");
            return MappingResult.archived(auditTrail);
        }

        EscalationResolution resolution = pendingEscalationResolution;
        recordAuditEvent(resolution.getResolverId(), "ESCALATION_RESOLVED",
            resolution.getOutcome() + ": " + resolution.getNotes());

        if (resolution.getOutcome() == EscalationOutcome.APPROVED) {
            currentStatus = MappingStatus.APPROVED;
            notificationActivities.publishApprovedMapping(
                request.getSourceProductId(), resolution.getMappingId());
            return MappingResult.approved(resolution.getMappingId(), auditTrail);
        } else {
            currentStatus = MappingStatus.ARCHIVED;
            return MappingResult.archived(auditTrail);
        }
    }

    // ── Signal Handlers ────────────────────────────────────────────────

    @Override
    public void submitMakerAction(MakerAction action) {
        recordAuditEvent(action.getMakerId(), "MAKER_ACTION",
            action.getActionType() + ": " + action.getNotes());
        this.pendingMakerAction = action;
    }

    @Override
    public void submitAuditDecision(AuditDecision decision) {
        recordAuditEvent(decision.getAuditorId(), "AUDIT_DECISION",
            decision.getOutcome() + ": " + decision.getComments());
        this.pendingAuditDecision = decision;
    }

    @Override
    public void submitEscalationResolution(EscalationResolution resolution) {
        recordAuditEvent(resolution.getResolverId(), "ESCALATION_RESOLUTION",
            resolution.getOutcome() + ": " + resolution.getNotes());
        this.pendingEscalationResolution = resolution;
    }

    // ── Query Handlers ─────────────────────────────────────────────────

    @Override
    public MappingStatus getCurrentStatus() {
        return currentStatus;
    }

    @Override
    public List<AuditEvent> getAuditTrail() {
        return Collections.unmodifiableList(auditTrail);
    }

    // ── Helpers ────────────────────────────────────────────────────────

    private void processMakerAction(MakerAction action) {
        currentStatus = MappingStatus.PENDING_AUDIT;
        pendingMakerAction = null;
    }

    private void recordAuditEvent(String actorId, String action, String detail) {
        auditTrail.add(AuditEvent.builder()
            .actorId(actorId)
            .action(action)
            .detail(detail)
            .timestamp(Workflow.currentTimeMillis())  // deterministic — not System.currentTimeMillis()
            .workflowId(Workflow.getInfo().getWorkflowId())
            .build());
    }
}
```

---

## Activity Implementations

Activities are the units of side-effectful work — external API calls, DB writes, notifications. Temporal retries activities automatically on failure.

### Matching Activities

```java
@ActivityInterface
public interface MatchingActivities {
    MatchingResult runAutomatedMatching(MappingRequest request);
}

public class MatchingActivitiesImpl implements MatchingActivities {

    @Override
    public MatchingResult runAutomatedMatching(MappingRequest request) {
        List<MatchCandidate> candidates = new ArrayList<>();

        // Strategy 1: UPC/GTIN exact match — highest confidence
        if (request.getUpc() != null) {
            Optional<MatchCandidate> upcMatch = productCatalogClient
                .findByUpc(request.getUpc());
            upcMatch.ifPresent(c -> candidates.add(c.withConfidence(0.99)));
        }

        // Strategy 2: Title fuzzy match (Levenshtein + token-based)
        if (candidates.isEmpty()) {
            candidates.addAll(titleMatchingService.findSimilar(
                request.getProductTitle(), TOP_K = 5));
        }

        // Strategy 3: Attribute-based matching (brand + size + variant)
        candidates.addAll(attributeMatchingService.findByAttributes(
            request.getBrand(),
            request.getPackageSize(),
            request.getCategory(),
            TOP_K = 3));

        // Strategy 4: Semantic embedding similarity
        candidates.addAll(embeddingService.findSemanticallyEquivalent(
            request.getProductTitle(), TOP_K = 3));

        // Strategy 5: Image similarity (optional, if image URL provided)
        if (request.getImageUrl() != null) {
            candidates.addAll(imageMatchingService.findSimilar(
                request.getImageUrl(), TOP_K = 2));
        }

        // Deduplicate and rank by composite confidence score
        List<MatchCandidate> ranked = rankingService.dedupAndRank(candidates);

        return MatchingResult.builder()
            .candidates(ranked)
            .bestCandidate(ranked.isEmpty() ? null : ranked.get(0))
            .confidenceScore(ranked.isEmpty() ? 0.0 : ranked.get(0).getConfidence())
            .build();
    }
}
```

### Notification Activities

```java
@ActivityInterface
public interface NotificationActivities {
    void notifyMakerQueue(String sourceProductId, List<MatchCandidate> candidates);
    void notifyAuditQueue(String sourceProductId, MatchCandidate candidate);
    void notifyManualMappingQueue(String sourceProductId);
    void notifyMakerRejection(String sourceProductId, String reason);
    void notifyEscalationQueue(String sourceProductId);
    void sendSLAAlert(String sourceProductId, String alertType, String message);
    void publishApprovedMapping(String sourceProductId, String mappingId);
}
```

---

## API Layer: Triggering and Driving the Workflow

### Start Workflow (Product Ingestion)

```java
@RestController
@RequestMapping("/api/v1/mappings")
public class MappingController {

    private final WorkflowClient temporalClient;

    @PostMapping
    public ResponseEntity<StartMappingResponse> startMapping(
            @RequestBody MappingRequest request) {

        String workflowId = "mapping-" + request.getSourceProductId();

        ProductMappingWorkflow workflow = temporalClient.newWorkflowStub(
            ProductMappingWorkflow.class,
            WorkflowOptions.newBuilder()
                .setWorkflowId(workflowId)
                .setTaskQueue("product-mapping-queue")
                .setWorkflowExecutionTimeout(Duration.ofDays(30))  // max lifecycle
                .setWorkflowIdReusePolicy(
                    WorkflowIdReusePolicy.WORKFLOW_ID_REUSE_POLICY_REJECT_DUPLICATE)
                .build()
        );

        WorkflowClient.start(workflow::execute, request);

        return ResponseEntity.accepted()
            .body(new StartMappingResponse(workflowId));
    }

    // Maker submits review/correction
    @PostMapping("/{productId}/maker-action")
    public ResponseEntity<Void> submitMakerAction(
            @PathVariable String productId,
            @RequestBody MakerAction action) {

        String workflowId = "mapping-" + productId;
        ProductMappingWorkflow workflow = temporalClient.newWorkflowStub(
            ProductMappingWorkflow.class, workflowId);

        workflow.submitMakerAction(action);
        return ResponseEntity.ok().build();
    }

    // Auditor submits decision
    @PostMapping("/{productId}/audit-decision")
    public ResponseEntity<Void> submitAuditDecision(
            @PathVariable String productId,
            @RequestBody AuditDecision decision) {

        String workflowId = "mapping-" + productId;
        ProductMappingWorkflow workflow = temporalClient.newWorkflowStub(
            ProductMappingWorkflow.class, workflowId);

        workflow.submitAuditDecision(decision);
        return ResponseEntity.ok().build();
    }

    // Query current status without side effects
    @GetMapping("/{productId}/status")
    public ResponseEntity<MappingStatusResponse> getStatus(
            @PathVariable String productId) {

        String workflowId = "mapping-" + productId;
        ProductMappingWorkflow workflow = temporalClient.newWorkflowStub(
            ProductMappingWorkflow.class, workflowId);

        MappingStatus status = workflow.getCurrentStatus();
        List<AuditEvent> trail = workflow.getAuditTrail();

        return ResponseEntity.ok(new MappingStatusResponse(status, trail));
    }
}
```

---

## SLA Enforcement — How `Workflow.await` Works

This is one of Temporal's most powerful features. The code below looks like a blocking wait — but it is actually a **durable timer**:

```java
boolean acted = Workflow.await(
    Duration.ofHours(48),        // SLA deadline
    () -> pendingMakerAction != null  // condition to unblock
);
```

What actually happens:
1. Temporal records a `TimerStarted` event in the workflow history
2. The workflow thread is suspended (no thread blocked, no resource held)
3. When a signal arrives → Temporal fires the condition check → workflow resumes
4. When 48 hours elapses → Temporal fires the timer → `await` returns `false`
5. If the worker crashes → Temporal replays the history, restores state, continues waiting

**This is zero-infrastructure SLA enforcement.** No cron jobs. No scheduled tasks. No "dead letter queue scanner." The SLA is expressed as code, and Temporal guarantees it runs.

---

## Workflow Identity and Idempotency

Every product maps to exactly one workflow execution, keyed by `workflowId = "mapping-{sourceProductId}"`.

```java
WorkflowOptions.newBuilder()
    .setWorkflowId("mapping-" + sourceProductId)
    .setWorkflowIdReusePolicy(
        WorkflowIdReusePolicy.WORKFLOW_ID_REUSE_POLICY_REJECT_DUPLICATE)
```

- Submitting the same product twice → second request rejected (idempotent)
- Looking up state → always by workflowId, no secondary key management needed
- Signals always route to the correct execution — no fan-out logic needed

---

## Audit Trail — What Temporal Gives for Free

The Temporal event history for a single workflow execution is itself a complete audit log:

```
WorkflowExecutionStarted      {sourceProductId: "SKU-123", ts: 2024-01-10T09:00Z}
ActivityTaskScheduled         {activity: runAutomatedMatching}
ActivityTaskStarted           {worker: matching-worker-1}
ActivityTaskCompleted         {confidence: 0.87, bestCandidate: "COMP-456"}
TimerStarted                  {fireAfter: 48h}              ← maker SLA
SignalReceived                 {signal: submitMakerAction, makerId: "analyst-7"}
TimerCanceled                 {}
ActivityTaskScheduled         {activity: notifyAuditQueue}
ActivityTaskCompleted         {}
TimerStarted                  {fireAfter: 24h}              ← audit SLA
SignalReceived                 {signal: submitAuditDecision, auditorId: "auditor-2", outcome: APPROVED}
TimerCanceled                 {}
ActivityTaskScheduled         {activity: publishApprovedMapping}
ActivityTaskCompleted         {}
WorkflowExecutionCompleted    {result: APPROVED, mappingId: "MAP-789"}
```

This history is:
- **Tamper-evident** — stored in the Temporal database, not editable via application code
- **Complete** — every transition, every actor, every timestamp
- **Queryable** — via Temporal Web UI or the SDK's `WorkflowHistory` API
- **Exportable** — can be streamed to an audit data warehouse via Temporal's archival feature

The application's `auditTrail` list in workflow state is an additional application-level audit record (richer comments, rejection reasons) that complements the Temporal event history.

---

## Determinism Constraints in Workflow Code

Temporal replays workflow code to restore state after a worker restart. This requires workflow code to be **deterministic** — same inputs must always produce same outputs.

**Rules followed in this implementation:**

| Constraint | Wrong | Correct |
|-----------|-------|---------|
| Time | `System.currentTimeMillis()` | `Workflow.currentTimeMillis()` |
| Random | `Math.random()` | `Workflow.newRandom()` |
| Thread sleep | `Thread.sleep(5000)` | `Workflow.sleep(Duration.ofSeconds(5))` |
| External calls | Direct HTTP in workflow | Via Activity (wrapped side-effect) |
| Non-deterministic branching | Any result that varies on re-run | Must be identical on replay |

The Temporal Java SDK enforces this at runtime — `WorkflowUnsafeCallException` is thrown if non-deterministic APIs are called directly in workflow code.

---

## Worker Configuration

```java
@Configuration
public class TemporalWorkerConfig {

    @Bean
    public WorkerFactory workerFactory(WorkflowClient client) {
        WorkerFactory factory = WorkerFactory.newInstance(client);

        Worker worker = factory.newWorker("product-mapping-queue",
            WorkerOptions.newBuilder()
                .setMaxConcurrentWorkflowTaskExecutionSize(100)
                .setMaxConcurrentActivityExecutionSize(50)
                .build());

        // Register workflow implementations
        worker.registerWorkflowImplementationTypes(
            ProductMappingWorkflowImpl.class);

        // Register activity implementations
        worker.registerActivitiesImplementations(
            new MatchingActivitiesImpl(matchingEngineClient),
            new NotificationActivitiesImpl(notificationService),
            new AuditActivitiesImpl(auditRepository));

        factory.start();
        return factory;
    }
}
```

---

## Operational Runbook

### Viewing workflow state

```bash
# List all active mapping workflows
tctl workflow list --query 'WorkflowType="ProductMappingWorkflow" AND ExecutionStatus="Running"'

# Query a specific product's status
tctl workflow query \
  --workflow_id "mapping-SKU-123" \
  --query_type getCurrentStatus

# View full audit trail
tctl workflow query \
  --workflow_id "mapping-SKU-123" \
  --query_type getAuditTrail
```

### Manually unblocking a stuck workflow

```bash
# If an analyst is unable to action — operations can signal manually
tctl workflow signal \
  --workflow_id "mapping-SKU-123" \
  --name submitAuditDecision \
  --input '{"auditorId":"ops-override","outcome":"APPROVED","comments":"Manual override by ops"}'
```

### Terminating a workflow (last resort)

```bash
tctl workflow terminate \
  --workflow_id "mapping-SKU-123" \
  --reason "Duplicate product — archived by data team"
```

---

## Key Design Decisions

### ADR 1: Temporal over State Machine in DB

**Context:** The workflow has 9 states, timeouts at each state, retry logic for external calls, and an audit requirement.  
**Decision:** Use Temporal workflow instead of a DB-backed state machine with cron jobs.  
**Why:** A DB state machine requires: transition table, timeout scanner cron, retry table, separate audit log table, and careful handling of crashes mid-transition. Temporal provides all of these out of the box. The workflow code is the state machine — it is readable, testable, and version-controlled.  
**Consequence:** Temporal cluster is a new operational dependency. Team needs Temporal training.

### ADR 2: Signal-driven for human steps

**Context:** Maker and Auditor actions arrive asynchronously via the analyst portal, potentially days later.  
**Decision:** Human actions delivered as Temporal signals; workflow awaits them with SLA timers.  
**Why:** Signals are durable — even if a signal is received while the worker is down, Temporal queues it and delivers it when the worker recovers. The workflow never misses a signal.  
**Consequence:** Signal ordering must be handled carefully if two signals arrive simultaneously (Temporal processes them sequentially, in receive order).

### ADR 3: One workflow per product per lifetime

**Context:** A product may be re-mapped if the original mapping is deprecated.  
**Decision:** Use `WORKFLOW_ID_REUSE_POLICY_ALLOW_DUPLICATE_FAILED_ONLY` on re-map, and archive old workflow before starting new.  
**Why:** Keeps history clean — each workflow execution represents one mapping lifecycle. Avoids confusion between current and historical mapping state.

### ADR 4: Audit trail in workflow state + Temporal history

**Context:** Compliance requires a full audit trail with actor IDs, timestamps, reasons.  
**Decision:** Maintain application-level `auditTrail` list in workflow state (rich context) and rely on Temporal event history as the tamper-evident backend.  
**Why:** Temporal event history captures all transitions but doesn't capture business-level rejection reasons or free-text comments. Application-level list captures these. Both are needed.

---

## Metrics and Observability

Temporal exposes metrics via Prometheus. Key metrics tracked:

| Metric | Alert threshold | Owner |
|--------|----------------|-------|
| `temporal_workflow_task_schedule_to_start_latency` | > 5s | SRE |
| `temporal_activity_task_schedule_to_start_latency` | > 30s | SRE |
| Workflows in `PENDING_REVIEW` state > 48h | Count > 0 | Operations |
| Workflows in `PENDING_AUDIT` state > 24h | Count > 0 | Operations |
| `matching_confidence_score` (p50, p90) | p50 < 0.5 | Data Quality |
| Audit rejection rate | > 20% | Data Quality |
| Auto-mapping rate | < 60% | Data Quality |

Custom metrics emitted from workflow/activity code via Micrometer:

```java
// In MatchingActivitiesImpl
meterRegistry.counter("mapping.automated.result",
    "outcome", result.getConfidenceScore() >= HIGH_THRESHOLD ? "high" :
               result.getConfidenceScore() >= MEDIUM_THRESHOLD ? "medium" : "no_match"
).increment();
```

---

## Impact and Results

| Metric | Before (DB state machine) | After (Temporal) |
|--------|--------------------------|-----------------|
| SLA breach detection latency | ~15 min (cron frequency) | Real-time (timer fires exactly) |
| State recovery after crash | Manual intervention / cron catch-up | Automatic (Temporal replay) |
| Audit trail completeness | 78% (missing events on crash) | 100% (event-sourced) |
| Failed activity retry rate | Manual re-queue | Automatic (configured retry policy) |
| Dev time to add a new workflow state | ~3 days (migration + code) | ~4 hours (code only) |
| Workflow visibility | Custom admin UI required | Temporal Web UI (zero cost) |
| Code lines for timeout logic | ~400 (cron + DB polling) | ~15 (`Workflow.await`) |

---

## Interview Angles

**On choosing Temporal:**
> The core issue was durability. A REST + DB state machine works until the server restarts mid-transaction or a cron job misses a SLA window. Every edge case — retry on failure, SLA enforcement, crash recovery — required custom infrastructure. Temporal's model inverts this: the workflow is the source of truth, and Temporal handles all the infrastructure concerns. The code became dramatically simpler — a `Workflow.await(48h, condition)` replaced a 400-line combination of cron job, polling query, and dead letter queue.

**On the Maker-Checker pattern:**
> Maker-Checker is fundamentally a two-actor approval flow — no single person can both create and approve a mapping. The challenge is that this is a long-lived, asynchronous interaction: a Maker might act in 5 minutes or 3 days. Temporal's signal/await model fits this exactly: the workflow pauses at a human step, holds its full state durably, resumes when the signal arrives, and enforces the SLA timer if no one acts. The governance property (Maker ≠ Checker) is enforced at the API layer — the signal handler validates that the auditorId is not the same as the makerId.

**On the audit trail:**
> Temporal's event history is inherently tamper-evident because application code cannot modify it — only Temporal can append to it. We use this as the authoritative compliance audit trail and export it nightly to our data warehouse via Temporal's archival feature. The application-level `auditTrail` list captures richer business context (rejection reasons, free-text notes) that we expose through the analyst portal. Both layers serve different consumers.
