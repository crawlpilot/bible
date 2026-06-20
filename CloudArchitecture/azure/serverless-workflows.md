# Azure Serverless Workflows — Durable Functions, Logic Apps, vs Step Functions

**AWS Equivalents**:  
- Azure Durable Functions → AWS Step Functions (Standard Workflows)  
- Azure Logic Apps (Standard) → AWS Step Functions + EventBridge Pipes  
- Azure Logic Apps (Consumption) → AWS Step Functions Express + EventBridge Pipes  
- Durable Entities → AWS Step Functions (no direct equivalent)  

**Mental model**: Azure offers two workflow engines for different audiences. Durable Functions = code-first orchestration for developers (Step Functions equivalent). Logic Apps = low-code/no-code workflow automation for business users and integration scenarios (Step Functions + MuleSoft alternative). Both run on the same underlying durable execution infrastructure.

---

## Decision: Durable Functions vs Logic Apps

```
Who builds and maintains the workflow?
├── Developer (code-first, git-controlled, unit-testable)
│   └── Azure Durable Functions
└── Business analyst / integration team (GUI, connectors, minimal code)
    └── Azure Logic Apps

What type of workflow?
├── Complex orchestration with branching, compensation, fan-out/fan-in
│   └── Durable Functions (more flexible)
└── Enterprise integration: SAP, Salesforce, O365, 400+ SaaS connectors
    └── Logic Apps (built-in connectors)

How long is the workflow?
├── Days/months (human approvals, waiting for external events)
│   └── Both — but Logic Apps is simpler for long waits
└── Sub-minute, high-throughput
    └── Durable Functions (lower overhead per orchestration)
```

---

## 1. Azure Durable Functions

### What It Is

Extension of Azure Functions that adds state, orchestration, and long-running workflow capabilities. All state is automatically persisted to Azure Storage (queues + tables or Netherite backend).

**Code-first**: Workflows are defined in Python, C#, JavaScript, Java — not JSON/YAML.

### How It Works Internally

```
Client Function: start_orchestration()
       │
       ▼
Orchestration queue (Storage Queue)
       │
Orchestrator Function (replays from history to restore state)
       │
       ├── schedule Activity 1 → Activity queue → Activity Function (executes)
       ├── wait for result...
       ├── schedule Activity 2 (parallel)
       ├── schedule Activity 3 (parallel)
       └── await task_all([Activity 2, Activity 3]) → Fan-in
```

**Replay-based execution**: The orchestrator function is deterministic and replays from its event history on each execution. This is how state is preserved without a running process.

**Storage backends**:
- **Azure Storage** (default): Queues + Tables for state; free with storage account
- **Netherite** (high performance): Event Hubs + Faster RocksDB-based storage; orders-of-magnitude throughput improvement for high-scale

### Orchestration Patterns

#### 1. Function Chaining
```python
@app.orchestration_trigger(context_name="context")
def order_processing(context: df.DurableOrchestrationContext):
    order_id = yield context.call_activity("ValidateOrder", context.get_input())
    payment_id = yield context.call_activity("ProcessPayment", order_id)
    shipping_id = yield context.call_activity("CreateShipment", payment_id)
    return {"orderId": order_id, "shippingId": shipping_id}
```

#### 2. Fan-out / Fan-in
```python
@app.orchestration_trigger(context_name="context")
def batch_processor(context: df.DurableOrchestrationContext):
    items = context.get_input()
    # Fan-out: process all items in parallel
    tasks = [context.call_activity("ProcessItem", item) for item in items]
    # Fan-in: wait for ALL
    results = yield context.task_all(tasks)
    return results
```

#### 3. Async HTTP API (status polling)
```python
# Client starts orchestration
instance_id = await client.start_new("long_running_job", input={"data": "..."})
# Returns immediately with polling URL
return client.create_check_status_response(request, instance_id)

# Consumer polls: GET /runtime/webhooks/durabletask/instances/{instanceId}
# → { "runtimeStatus": "Running", "customStatus": "Step 2 of 5" }
```

#### 4. Human Interaction / External Events
```python
@app.orchestration_trigger(context_name="context")
def approval_workflow(context: df.DurableOrchestrationContext):
    # Send approval request (email via SendGrid)
    yield context.call_activity("SendApprovalEmail", {"approver": "manager@company.com"})
    
    # Wait up to 7 days for approval (no compute consumed while waiting)
    event = yield context.wait_for_external_event("ApprovalDecision")
    
    if event == "Approved":
        yield context.call_activity("ExecuteAction", context.get_input())
    else:
        yield context.call_activity("SendRejectionNotification", context.get_input())
```

Approval is sent via:
```http
POST /runtime/webhooks/durabletask/instances/{id}/raiseEvent/ApprovalDecision
Content-Type: application/json
"Approved"
```

#### 5. Durable Entities (Stateful Actors)
```python
@app.entity_trigger(context_name="context")
def counter(context: df.DurableEntityContext):
    current_value = context.get_state(lambda: 0)
    operation = context.operation_name
    
    if operation == "add":
        context.set_state(current_value + context.get_input())
    elif operation == "get":
        context.set_result(current_value)
    elif operation == "reset":
        context.set_state(0)
```

**No AWS equivalent for Entities**: Step Functions has no actor model. Approximated with DynamoDB + conditional updates.

### Durable Functions vs AWS Step Functions

| Feature | Durable Functions | Step Functions Standard |
|---------|-----------------|------------------------|
| Definition format | **Code** (Python/C#/JS/Java) | **JSON** (Amazon States Language) |
| Max duration | Unlimited | 1 year |
| Activity cost | Function execution time | $0.025/1K state transitions |
| Orchestration cost | Function execution time | $0.025/1K state transitions |
| Local debugging | **Yes** (full local emulator) | Limited (SAM local, no SF emulator) |
| Version management | Manual (in code) | Via alias/versioning |
| Replay-based execution | **Yes** (key concept) | No (event-based) |
| Stateful actors | **Yes** (Durable Entities) | No |
| External event signaling | `raise_event()` | `send_task_success` / `send_task_failure` |
| Parallel execution | `task_all()` / `task_any()` | Parallel state |
| History storage | Azure Storage / Netherite | DynamoDB (internal) |
| Max execution history | 25 MB per orchestration | Unlimited (Step Functions manages) |
| SDK language support | C#, Python, JS, Java | Any language via Lambda |
| Throughput (high) | Netherite backend (millions/day) | 25K state transitions/sec per account |

---

## 2. Azure Logic Apps

### What It Is

Low-code/no-code workflow automation with 400+ built-in connectors. For integration engineers, business analysts, and developers building enterprise integration patterns without writing orchestration code.

**Two tiers**:

| Tier | Model | Use Case | Pricing |
|------|-------|---------|---------|
| **Consumption** | Multi-tenant, per-action billing | Low-frequency, simple integrations | Pay per action execution |
| **Standard** | Single-tenant (dedicated), vCore billing | High-frequency, complex, VNet support | Pay for vCores + storage |

### Connectors (400+)

Built-in connectors include:

| Category | Connectors |
|----------|-----------|
| **Microsoft 365** | Outlook, Teams, SharePoint, Excel, OneDrive |
| **CRM** | Salesforce, Dynamics 365, HubSpot |
| **ERP** | SAP, Oracle, Workday |
| **Databases** | SQL Server, Cosmos DB, Oracle DB, MySQL |
| **Cloud** | AWS S3, AWS SQS, Slack, GitHub, Jira |
| **Messaging** | Service Bus, Event Hubs, Twilio, SendGrid |
| **DevOps** | Azure DevOps, GitHub Actions |
| **AI** | Azure OpenAI, Cognitive Services |

### Built-in Actions

```
Logic Apps workflow example:
When new email arrives in Outlook (trigger)
  └── Extract attachments
  └── Upload to SharePoint
  └── Extract text with AI Document Intelligence
  └── Send Teams notification with summary
  └── Create Jira ticket
```

All visually configured — no code for basic flows.

### Logic Apps vs AWS Step Functions

| Feature | Logic Apps (Standard) | Step Functions Standard |
|---------|----------------------|------------------------|
| Definition format | JSON (workflow.json) or GUI | JSON (ASL) |
| Pre-built connectors | **400+** | ~20 native service integrations |
| SaaS integrations | **Excellent** (Salesforce, SAP, O365) | Limited (EventBridge Pipes helps) |
| Code steps | JavaScript / C# inline scripts | Lambda invocations |
| Run history | Full action-by-action history | Full state history |
| Monitoring | Azure Monitor integration | CloudWatch integration |
| VNet isolation | Standard tier | Available |
| B2B EDI | **Yes** (EDI standards, AS2, X12, EDIFACT) | No native EDI |
| Local development | Logic Apps extension for VS Code | SAM CLI (limited) |
| Pricing (simple flow) | ~$0.000025/action (Consumption) | $0.025/1K transitions |

**Logic Apps for EDI**: Logic Apps is the standard choice for electronic data interchange (B2B trading partner integration) — processing X12 (ANSI), EDIFACT, AS2 messages. No AWS service approaches this without a third-party (MuleSoft, etc.).

---

## 3. Pattern Implementations

### Saga Pattern: Durable Functions vs Step Functions

**Problem**: Book a trip — hotel + flight + car rental. If any step fails, compensate all previous steps.

**Durable Functions (code)**:
```python
@app.orchestration_trigger(context_name="context")
def book_trip(context: df.DurableOrchestrationContext):
    booking_id = context.get_input()
    hotel_id = None
    flight_id = None
    
    try:
        hotel_id = yield context.call_activity("ReserveHotel", booking_id)
        flight_id = yield context.call_activity("ReserveFlight", booking_id)
        car_id = yield context.call_activity("ReserveCar", booking_id)
        return {"hotel": hotel_id, "flight": flight_id, "car": car_id}
    except Exception as e:
        # Compensate in reverse order
        if flight_id:
            yield context.call_activity("CancelFlight", flight_id)
        if hotel_id:
            yield context.call_activity("CancelHotel", hotel_id)
        raise
```

**Step Functions (JSON ASL)**:
```json
{
  "StartAt": "ReserveHotel",
  "States": {
    "ReserveHotel": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:::function:reserve-hotel",
      "Next": "ReserveFlight",
      "Catch": [{"ErrorEquals": ["States.ALL"], "Next": "CompensateNoFlight"}]
    },
    "ReserveFlight": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:::function:reserve-flight",
      "Next": "ReserveCar",
      "Catch": [{"ErrorEquals": ["States.ALL"], "Next": "CompensateHotel"}]
    },
    "CompensateHotel": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:::function:cancel-hotel",
      "End": true
    }
  }
}
```

**Readability verdict**: Durable Functions code is significantly more readable for complex compensation logic. Step Functions ASL becomes deeply nested for multi-step Sagas.

### Long-Running Process: Human Approval

**Durable Functions**: `wait_for_external_event()` — pauses indefinitely (no compute consumed)  
**Step Functions**: `.waitForTaskToken` + callback  
**Logic Apps**: Built-in "Approve/Reject" action with email/Teams integration (no code)

**For non-technical approvals**: Logic Apps wins — approval emails with Approve/Reject buttons sent natively, no custom API needed.

---

## 4. EventBridge Pipes (AWS) — No Direct Azure Equivalent

AWS EventBridge Pipes is a point-to-point connector (source → optional filter/enrichment → target) that connects services without Lambda:

```
SQS → [filter] → [Lambda enrichment] → EventBridge Bus
Kinesis → [filter] → [Lambda] → SQS
DynamoDB Streams → [filter] → Step Functions
```

**Azure closest equivalents**:
- **Logic Apps with Service Bus trigger**: More powerful but requires GUI workflow
- **Event Grid subscription**: Push-based, no filter/enrich
- **Azure Data Factory**: For data movement pipelines (heavier)

---

## When to Use Each Service

| Scenario | Azure | AWS |
|----------|-------|-----|
| Complex code-defined orchestration | Durable Functions | Step Functions |
| Long-running (human approval, external wait) | Durable Functions (wait_for_external_event) | Step Functions (.waitForTaskToken) |
| SaaS integration (Salesforce, SAP, O365) | Logic Apps | EventBridge Pipes + custom Lambda |
| EDI / B2B trading partner integration | **Logic Apps (built-in EDI)** | No AWS native; third-party needed |
| Stateful actor / counter / aggregate | **Durable Entities** | DynamoDB + Lambda (manual) |
| High-throughput (millions/day) | Durable Functions + Netherite | Step Functions Express |
| Low-code business workflow | Logic Apps | Step Functions (code still needed) |
| Real-time streaming pipeline | — | EventBridge Pipes |
| Short workflows < 5 min, high volume | Durable Functions | Step Functions Express ($1/million) |

---

## Key Numbers for Interviews

| Service | Number | Notes |
|---------|--------|-------|
| Durable Functions max orchestration history | 25 MB | Netherite backend increases this significantly |
| Step Functions max workflow duration | 1 year | Standard; Express = 5 minutes |
| Logic Apps Consumption max run duration | 90 days | Standard tier = unlimited |
| Logic Apps built-in connectors | **400+** | vs Step Functions ~20 native integrations |
| Durable Functions local emulator | Full support | Step Functions has limited SAM local support |
| Step Functions Standard max transitions | 25,000/sec per account | Soft limit; increase via support |
| Step Functions Express pricing | $1 per million state transitions | vs Standard $25 per million |

---

> **FAANG Interview Callout**: "For orchestration questions in interviews, I distinguish two scenarios: (1) Developer-owned workflows with complex business logic, branching, and compensation — Durable Functions code is readable, git-versioned, and unit-testable where Step Functions JSON becomes unwieldy for multi-step Sagas. (2) Enterprise integration connecting SaaS systems (Salesforce → SAP → O365) — Logic Apps built-in connectors mean a solution that would take months building Lambda integrations is configured in days. The Durable Entities feature is something I highlight specifically: it's an actor model for managing shared mutable state across distributed workflows — no direct Step Functions equivalent, and on AWS you'd approximate it with DynamoDB conditional writes, which is significantly more code and harder to reason about under concurrency."
