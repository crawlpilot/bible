# AWS Step Functions

## Overview
Step Functions is a fully managed workflow orchestration service. It lets you define and execute state machines where each state can invoke AWS services, Lambda functions, ECS tasks, or HTTP endpoints. It provides durable execution — a workflow can run for up to a year and survives Lambda restarts, EC2 failures, and transient AWS errors.

**Core value**: Externalise workflow state from application code. Instead of managing retries, state persistence, parallel fan-out, and timeout logic in your code, Step Functions handles it declaratively.

---

## Workflow Types

| | Standard Workflow | Express Workflow |
|---|---|---|
| **Execution duration** | Up to 1 year | Up to 5 minutes |
| **Delivery semantics** | Exactly-once | At-least-once |
| **Execution model** | Durable (state persisted to DDB internally) | High-throughput, event-driven |
| **Audit history** | Full event history in console | CloudWatch Logs only |
| **Throughput** | 2,000 executions/s (account limit) | 100,000 executions/s |
| **Pricing** | $0.025/1,000 state transitions | $0.00001/state transition + duration |
| **Use when** | Long-running, exactly-once, auditable | High-volume, short-lived, event-driven |

**Examples**:
- Standard: order fulfillment (hours), document approval, ETL pipeline, saga orchestration
- Express: API orchestration, IoT message processing, real-time event processing

---

## Amazon States Language (ASL) — Key State Types

```json
{
  "Comment": "Order Processing Saga",
  "StartAt": "ValidateOrder",
  "States": {
    "ValidateOrder": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:function:validate-order",
      "Retry": [{"ErrorEquals": ["Lambda.ServiceException"], "IntervalSeconds": 2, "MaxAttempts": 3, "BackoffRate": 2}],
      "Catch": [{"ErrorEquals": ["ValidationError"], "Next": "OrderFailed"}],
      "Next": "ReserveInventory"
    },
    "ProcessPaymentParallel": {
      "Type": "Parallel",
      "Branches": [
        {"StartAt": "ChargeCreditCard", "States": {...}},
        {"StartAt": "UpdateLedger", "States": {...}}
      ],
      "Next": "ShipOrder"
    },
    "WaitForShipment": {
      "Type": "Wait",
      "Seconds": 86400,
      "Next": "CheckShipmentStatus"
    },
    "OrderFailed": {"Type": "Fail", "Error": "OrderFailed", "Cause": "Validation failed"}
  }
}
```

**State types**:
| Type | Purpose |
|---|---|
| `Task` | Invoke Lambda, ECS, Glue, SageMaker, HTTP endpoint, SDK integrations |
| `Choice` | Branch based on input data (if/else routing) |
| `Parallel` | Run multiple branches concurrently; wait for all to complete |
| `Map` | Iterate over an array; process each item (inline or distributed) |
| `Wait` | Pause for a fixed duration or until a timestamp |
| `Pass` | Transform/pass data without calling a service |
| `Succeed` / `Fail` | Terminal states |

---

## SDK Integrations (no Lambda needed)

Step Functions can call 200+ AWS services directly via **optimised integrations**, eliminating Lambda boilerplate:

| Integration | States example |
|---|---|
| DynamoDB PutItem / GetItem | Direct state with `"Resource": "arn:aws:states:::dynamodb:putItem"` |
| SQS SendMessage | Direct queue publish from workflow |
| SNS Publish | Direct notification publish |
| ECS RunTask | Start a container task |
| Glue StartJobRun | Trigger ETL job |
| SageMaker CreateTrainingJob | ML pipeline |
| HTTP endpoint (any URL) | `"Resource": "arn:aws:states:::http:invoke"` |
| EventBridge PutEvents | Publish event from workflow |

**Request-response vs. .sync vs. .waitForTaskToken**:
| Mode | Behaviour |
|---|---|
| `request-response` | Fire and forget; next state immediately |
| `.sync:2` | Wait for the job to complete (e.g., Glue job polling) |
| `.waitForTaskToken` | Pause indefinitely until external system calls `SendTaskSuccess` with token |

**`.waitForTaskToken`** is the pattern for human approval gates:
```
Workflow pauses → sends task token to SQS → human reviews → Lambda calls SendTaskSuccess(token) → workflow resumes
```

---

## Saga Pattern Implementation

Step Functions is the canonical AWS implementation of the Saga orchestration pattern.

```
StartAt: ReserveInventory
  ↓ success
ChargePayment
  ↓ failure → CompensateInventory (release reservation) → OrderFailed
  ↓ success
SendConfirmation
  ↓ failure → RefundPayment → CompensateInventory → OrderFailed
  ↓ success
OrderComplete
```

**Compensating transaction pattern**:
- Each forward step has a compensating step defined in the `Catch` block
- Compensations run in reverse order (Last-In-First-Out)
- All tasks must be **idempotent** — Step Functions may retry on timeout

---

## Distributed Map (Parallel Processing at Scale)

`Map` state in **Distributed** mode processes millions of items in parallel — directly from S3.

```json
{
  "Type": "Map",
  "ItemReader": {
    "Resource": "arn:aws:states:::s3:getObject",
    "Parameters": {"Bucket": "my-bucket", "Key": "items.json"}
  },
  "MaxConcurrency": 1000,
  "ItemProcessor": {
    "ProcessorConfig": {"Mode": "DISTRIBUTED", "ExecutionType": "EXPRESS"},
    "StartAt": "ProcessItem",
    "States": {"ProcessItem": {"Type": "Task", ...}}
  }
}
```

**Use case**: Process 10M S3 objects in parallel with 1,000 concurrent child Express workflows. Pattern used for: ETL, ML batch inference, compliance scanning, large-scale data migrations.

---

## Error Handling, Retry & Backoff

```json
"Retry": [{
  "ErrorEquals": ["Lambda.TooManyRequestsException", "Lambda.AWSLambdaException"],
  "IntervalSeconds": 1,
  "MaxAttempts": 3,
  "BackoffRate": 2,
  "JitterStrategy": "FULL"
}]
```

**JitterStrategy FULL**: adds random jitter up to the backoff interval — prevents thundering herd when many workflows retry simultaneously.

**Catch** overrides retry for specific errors:
```json
"Catch": [
  {"ErrorEquals": ["InsufficientFundsError"], "Next": "HandleInsufficientFunds"},
  {"ErrorEquals": ["States.ALL"], "Next": "GenericErrorHandler"}
]
```

---

## Key Tuning Parameters

| Parameter | Consideration |
|---|---|
| Execution timeout | Set `TimeoutSeconds` on each state AND on the overall execution |
| Map `MaxConcurrency` | Controls parallelism; 0 = unlimited (can overwhelm downstream services) |
| Input/output `ResultSelector` | Filter state output before passing to next state — reduces payload size |
| `HeartbeatSeconds` | For long-running tasks; Step Functions fails the state if no heartbeat received |
| Standard vs Express selection | Duration > 5 min or exactly-once required → Standard; otherwise Express |
| State machine execution history | Standard keeps 90 days; query with GetExecutionHistory API |

---

## Use Cases

| Use case | Pattern |
|---|---|
| Order fulfillment | Saga: reserve → charge → ship; compensations on failure |
| ETL pipeline | Glue Crawler → Glue Job → notify on completion |
| Human-in-the-loop approval | `.waitForTaskToken` pauses until human approves |
| Batch file processing | Distributed Map over S3 prefix |
| ML pipeline | SageMaker training → evaluation → conditional deploy |
| Microservice orchestration | Chain of Lambda/ECS calls with retries and error handling |
| Scheduled maintenance | EventBridge cron → Step Functions for multi-step operations |
| Document processing | Upload → virus scan → OCR → classify → store |

---

## Monitoring

| Metric | Alert condition |
|---|---|
| `ExecutionsFailed` | > 0 for critical workflows → PagerDuty alert |
| `ExecutionThrottled` | > 0 → increase account limit or reduce trigger rate |
| `ExecutionTime` | P99 > SLA threshold |
| `ExecutionsTimedOut` | Timeout too short or downstream too slow |
| `LambdaFunctionsFailed` | Task-level failures within the workflow |
| X-Ray trace | End-to-end latency breakdown per state |

**Enable X-Ray tracing** on every Step Functions state machine — trace propagates through Lambda and SDK integrations automatically.

---

## Best Practices

1. **Set execution and state timeouts** — without them, a stuck `.waitForTaskToken` workflow runs forever (billed for 1 year)
2. **Use SDK integrations over Lambda wrappers** — calling DynamoDB directly from a state is faster and cheaper than Lambda → DynamoDB
3. **Keep Lambda functions thin** — business logic in Lambda; orchestration logic in the state machine
4. **Use `ResultSelector` and `OutputPath`** to trim state payloads — Step Functions has a 256KB payload limit per state
5. **Idempotent task functions** — Step Functions will retry; make sure your Lambda/ECS tasks are safe to call twice
6. **Use Express workflows for high-volume, short** (< 5 min) scenarios — much cheaper than Standard
7. **Enable logging to CloudWatch** for Express workflows — no built-in execution history
8. **Tag executions** with business identifiers (order_id, user_id) — simplifies debugging
9. **Use Distributed Map** for batch processing, not nested Lambda fan-outs — built-in parallelism with S3 integration
10. **Test with Step Functions Local** — run state machines locally against mock Lambda responses before deploying

---

## FAANG Interview Points

**"How do you implement a saga for a payment workflow?"**: Step Functions Standard workflow with explicit compensating transactions in `Catch` blocks at each step. `.waitForTaskToken` for async payment gateway responses. Idempotency keys passed through the state machine payload.

**"Choreography vs orchestration for microservices?"**: Step Functions = orchestration. The workflow state is visible in the console, debuggable via execution history, and all compensations are explicit. Choreography (Kafka events) has no central visibility. Use Step Functions when you need audit trails, complex branching, or human approval steps.

**"How do you process 10 million records nightly?"**: Distributed Map in DISTRIBUTED mode targeting S3. Set `MaxConcurrency` based on downstream capacity. Use Express workflows for child executions (sub-5-min items). Total cost: (10M × 2 states × $0.00001) = $0.20. Compare with SQS + Lambda (fan-out) for <5 min items.

**"What's the payload size limit?"**: 256KB per state input/output. For larger data, use S3 as intermediate store: `PutObject` state writes output to S3, `GetObject` state reads input — the S3 URI is the state payload.
