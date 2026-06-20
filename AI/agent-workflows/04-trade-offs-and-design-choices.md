# 04 — Trade-offs & Design Choices

---

## Single Agent vs. Multi-Agent

The most fundamental architectural decision. Get this wrong and you'll either over-engineer a simple task or hit a wall on a complex one.

| Dimension | Single Agent | Multi-Agent |
|-----------|-------------|-------------|
| **Latency** | Lower — one model, sequential | Higher — orchestration overhead (~200-500ms per hop) |
| **Cost** | Lower — one model invoked | Higher — N models × their individual costs |
| **Context** | One shared window — everything visible | Isolated per agent — clean context per subtask |
| **Parallelism** | None — sequential tool calls | Natural — subagents run in parallel |
| **Debuggability** | Easy — one trace | Harder — distributed traces needed |
| **Scalability** | Limited by context window size | Horizontal — add more subagents |
| **Failure blast radius** | Entire task fails together | One subagent can fail without killing others |
| **Coordination complexity** | None | High — result aggregation, ordering, timeouts |
| **Best for** | ≤ 5 tool calls, linear tasks, simple workflows | Parallel subtasks, specialization, large context |

**Decision rule**:  
- If you can draw the execution path as a linear flowchart → single agent  
- If two or more branches of the flowchart can run independently → multi-agent  
- If subtasks need different tools or expertise → multi-agent with specialization  

### Concretely: When Multi-Agent Pays Off

```
Single agent:
  Task: "Summarize this document and translate it to French"
  Steps: read_doc → summarize → translate → return
  Duration: 3s, Cost: $0.05    ← just use single agent

Multi-agent:
  Task: "Research 5 competitor companies and write a comparison report"
  Steps: [research_A || research_B || research_C || research_D || research_E] → aggregate → report
  Duration with single: 5 × 10s = 50s
  Duration with multi:  max(10s, 10s, 10s, 10s, 10s) = 10s    ← 5× speedup
  Cost: 2× (orchestration overhead) but 5× faster — worth it for latency-sensitive use cases
```

---

## Orchestration Patterns: Centralized vs. Decentralized

### Centralized Orchestrator

One agent coordinates all others. All state flows through it.

```
                  ┌─────────────────┐
                  │   Orchestrator  │
                  │  (all state,    │
                  │   all routing)  │
                  └────────┬────────┘
              ┌────────────┼────────────┐
              ▼            ▼            ▼
         Agent A       Agent B       Agent C
```

**Strengths**:
- Simple mental model — one place to look for state
- Deterministic routing — orchestrator decides who does what
- Easy to add new agents without changing existing ones
- Clear audit log — orchestrator logs all decisions

**Weaknesses**:
- Single point of failure — orchestrator crash kills everything
- Orchestrator context becomes a bottleneck — must summarize all subagent results
- Vertical scaling limit — one LLM context window

**Use when**: Task has complex dependencies, ordering matters, strong auditability needed.

### Decentralized Mesh

Agents communicate peer-to-peer. No single coordinator.

```
Agent A ──────► Agent B
   ▲               │
   │               ▼
Agent D ◄────── Agent C
```

**Strengths**:
- No single point of failure — any agent can continue if another fails
- Agents can be added/removed without central reconfiguration
- Naturally scales to very large agent networks

**Weaknesses**:
- Very hard to debug — no single trace captures the full picture
- Eventual consistency risk — agents may act on stale information from peers
- Difficult to reason about global state
- Loop detection needed — A→B→A creates infinite cycles

**Use when**: Research/experimental systems, very large networks where centralization is impractical.

### Hierarchical (Tree)

Multiple levels of orchestrators. Each level manages the level below.

```
L1: Executive Orchestrator (global state, final synthesis)
    ├── L2: Research Team Lead (manages research subagents)
    │   ├── L3: Search Agent
    │   └── L3: Document Agent
    └── L2: Writing Team Lead (manages writing subagents)
        ├── L3: Outline Agent
        └── L3: Draft Agent
```

**Strengths**:
- Scales well — each level is independently bounded
- Mirrors real org structures — natural decomposition
- Each level can use a different model (L1: Opus, L2: Sonnet, L3: Haiku)

**Weaknesses**:
- Adds latency per level (each hop is one LLM call)
- Complex to debug — N levels of traces
- Over-engineering risk for simple tasks

**Use when**: Complex multi-domain tasks with natural team structure, cost tiering desired.

---

## State Management

### Stateless Agents

All state lives in the `messages` array passed to each LLM call.

```
Turn 1: messages = [task, tool_result_1]
Turn 2: messages = [task, tool_result_1, assistant_1, tool_result_2]
Turn N: messages = [task, tool_result_1, ..., tool_result_N]  ← grows linearly
```

**Strengths**: Simple, portable, no external dependencies, trivially restartable.  
**Weaknesses**: Cost grows linearly (re-send all history each turn), context window limit.  
**Use when**: Tasks < 5 turns, no session persistence needed, simplicity prioritized.

### Stateful Agents (External Store)

Agent checkpoints progress to Redis/DB. Each turn only sends recent context.

```
Turn 1: send [task, tool_result_1]         → save state to Redis
Turn 2: send [summary_of_1, tool_result_2] → save state to Redis
Turn N: send [rolling_summary, tool_result_N]
```

**Strengths**: Cost is O(1) per turn (not O(N)), survives restarts, cross-session persistence.  
**Weaknesses**: Summary quality matters — lossy compression loses context. Requires consistency model.  
**Use when**: Long-running tasks, session persistence needed, cost control required.

### Hybrid: Hot/Cold State Split

Hot state (current task context) in-memory. Cold state (historical facts, past sessions) in vector/KV store.

```python
class AgentState:
    # Hot: fast, in-context
    recent_messages: list[dict]     # Last N turns
    current_step: int
    active_tools: list[str]

    # Cold: retrieved on demand
    vector_store: VectorStore       # Past sessions, large knowledge base
    kv_store: Redis                 # Structured state, preferences
    
    def get_context_for_turn(self, query: str) -> list[dict]:
        # Retrieve relevant cold state
        memories = self.vector_store.search(query, top_k=3)
        structured = self.kv_store.get_relevant(query)
        
        # Combine hot + retrieved cold
        return [
            *memories_as_messages(memories),
            *structured_as_messages(structured),
            *self.recent_messages  # Most recent turns always included
        ]
```

**Recommendation**: This is the pattern to use for production agents with sessions > 5 minutes or cross-session memory.

---

## Synchronous vs. Asynchronous

| | Synchronous | Asynchronous |
|---|---|---|
| Caller interface | `result = run_agent(task)` — blocks | `task_id = submit_agent(task)` — returns immediately |
| Latency (caller) | Total agent latency | Near-zero (just submit) |
| Infrastructure | None beyond the LLM | Task queue (Celery, SQS, Redis Queue) |
| Result delivery | Direct return value | Polling endpoint or webhook |
| Error handling | Exception in caller | Callback or error status in task store |
| Best for | < 10s tasks, interactive user flows | > 10s tasks, batch processing, expensive workflows |

### When to Go Async

```
Decision: Is any of these true?
  □ p50 tool latency > 2s (web scraping, browser, slow APIs)
  □ Fan-out N > 3 parallel subagents
  □ User doesn't need to wait for result (batch report, background enrichment)
  □ Agent may need human approval in the middle (unknown wait time)

If any box is checked → go async
```

### Async Agent Pattern

```python
# Submit
@app.post("/agent/run")
async def submit_agent_task(task: str, user_id: str) -> dict:
    task_id = str(uuid.uuid4())
    await task_queue.enqueue(
        "run_agent_task",
        task_id=task_id,
        task=task,
        user_id=user_id
    )
    return {"task_id": task_id, "status": "queued"}

# Poll
@app.get("/agent/result/{task_id}")
async def get_agent_result(task_id: str) -> dict:
    result = await task_store.get(task_id)
    if not result:
        return {"status": "not_found"}
    return {
        "task_id": task_id,
        "status": result["status"],   # queued | running | complete | failed
        "result": result.get("answer"),
        "error": result.get("error"),
        "token_usage": result.get("token_usage"),
    }

# Worker (runs in background process)
@task_queue.task
async def run_agent_task(task_id: str, task: str, user_id: str):
    await task_store.set(task_id, {"status": "running"})
    try:
        answer = run_agent(task)
        await task_store.set(task_id, {"status": "complete", "answer": answer})
    except Exception as e:
        await task_store.set(task_id, {"status": "failed", "error": str(e)})
```

---

## Human-in-the-Loop Design

### Where to Insert

| Decision point | When to require human | Automation OK |
|---------------|----------------------|---------------|
| Before irreversible action | Always (delete, send, pay) | Never |
| When confidence < threshold | Model score < 0.7 | Score ≥ 0.9 |
| At task checkpoints | High-stakes tasks | Low-stakes tasks |
| On unexpected deviation | Plan changed significantly | Minor routing change |
| When escalation tool called | Model explicitly requests | N/A |

### Latency Budget for Human Gates

```
If human response time is < 30s: synchronous flow is acceptable (use WebSocket or SSE to push approval request)
If human response time is > 30s: go async — store pending approval, notify via email/Slack, resume on callback
```

### Audit Trail Requirements

Every human interaction must be logged:

```python
@dataclass
class HumanInteraction:
    task_id: str
    timestamp: datetime
    interaction_type: str       # "approval_request" | "approval_granted" | "approval_denied"
    proposed_action: str        # What the agent wanted to do
    agent_context_snapshot: str # Full messages at time of request (compressed)
    human_user_id: str
    human_decision: str | None
    human_note: str | None
```

---

## Framework Comparison

| Framework | Model | Strengths | Weaknesses | Verdict |
|-----------|-------|-----------|------------|---------|
| **LangGraph** | Graph-based state machine | Explicit state transitions, visualization, supports cycles | Steep learning curve, overkill for simple agents | Best for complex workflows with explicit state |
| **CrewAI** | Role-based agents | Easy multi-agent setup, readable YAML config | Less control over internals, abstraction leaks | Good for prototyping, limited production control |
| **AutoGen** | Conversational multi-agent | Natural agent-to-agent dialogue | Verbose, heavy Microsoft stack, non-deterministic by design | Research/demo, not production |
| **LlamaIndex Workflows** | Event-driven pipeline | Good RAG integration, typed events | Less general-purpose than LangGraph | Good if already using LlamaIndex for RAG |
| **Raw Anthropic SDK** | Direct API | Full control, no magic, lightweight | More boilerplate, no graph visualization | Best for production — you control everything |
| **OpenAI Assistants API** | Managed threads | Built-in thread management, file search | Vendor lock-in, black box, limited customization | Only if OpenAI-only shop |

**Recommendation for FAANG interview**: Default to describing **raw SDK + custom loop** for max control, then mention you'd evaluate LangGraph if the state machine complexity justifies it. Never design around a framework as the first decision.

---

## Model Selection Strategy

Don't use one model for everything. Tier by task complexity:

| Agent Role | Recommended Model | Reason |
|-----------|-------------------|--------|
| Complex reasoning, synthesis | claude-sonnet-4-6 | Best quality-cost tradeoff |
| High-stakes decisions, planning | claude-opus-4-8 | When quality > cost |
| Classification, routing | claude-haiku-4-5 | 10× cheaper, fast |
| Summarization, compression | claude-haiku-4-5 | Simple task, cheap |
| Sentinel / judge | claude-opus-4-8 or claude-sonnet-4-6 | Should be ≥ quality of judged model |

```python
MODEL_TIERS = {
    "orchestrator":  "claude-sonnet-4-6",
    "subagent":      "claude-sonnet-4-6",
    "router":        "claude-haiku-4-5-20251001",
    "summarizer":    "claude-haiku-4-5-20251001",
    "sentinel":      "claude-opus-4-8",
    "extractor":     "claude-haiku-4-5-20251001",   # structured output, template-driven
}
```

---

## Observability Design

Agents are black boxes without instrumentation. You cannot debug what you cannot see.

### What to Trace

```python
@dataclass
class AgentSpan:
    span_id: str
    parent_span_id: str | None    # For subagent hierarchy
    task_id: str
    agent_role: str               # "orchestrator" | "research_subagent" | etc.
    start_time: datetime
    end_time: datetime | None
    
    # LLM call metrics
    model: str
    input_tokens: int
    output_tokens: int
    stop_reason: str
    
    # Tool call (if this span is a tool invocation)
    tool_name: str | None
    tool_input: dict | None
    tool_result_size_chars: int | None
    tool_duration_ms: int | None
    tool_success: bool | None
    
    # Outcome
    status: str                   # "running" | "complete" | "failed"
    error: str | None
```

### Key Metrics to Monitor

| Metric | Alert threshold | Why |
|--------|----------------|-----|
| `agent_p99_latency` | > 60s | SLA breach |
| `cost_per_task` | > 2× baseline | Tool output inflation or loop regression |
| `max_iterations_hit_rate` | > 5% | Agent can't complete tasks — prompt or tool issue |
| `sentinel_rejection_rate` | > 10% | Agent output quality degraded |
| `tool_error_rate` | > 15% | External dependency degraded |
| `context_overflow_rate` | > 2% | Context strategy needs tuning |

---

## FAANG Interview Callout

> **"How would you design the agent infrastructure for a product that runs 10,000 agent tasks per day?"**
>
> State these five decisions upfront:
> 1. **Async by default**: Submit-poll pattern with SQS + workers. No customer waits synchronously for an agent.
> 2. **Hierarchical agents**: Orchestrator (Sonnet) + specialized subagents (Haiku for simple, Sonnet for complex). Model tiering cuts cost by 40–60%.
> 3. **Stateful with Redis checkpoints**: Agents resume on failure. Max 3 auto-retries per task, then dead-letter queue for human review.
> 4. **Observability first**: Every LLM call emits a span to Datadog/Honeycomb. Alert on cost_per_task drift. Weekly LLM-as-judge eval on random 1% sample.
> 5. **Cost cap per task**: Hard limit of $1.00 per task. Soft alert at $0.50. Tasks exceeding limit are aborted and flagged — never let a runaway agent drain the budget.
>
> At 10,000 tasks/day × $0.15 average = $1,500/day. That's a $45K/month line item. You need cost observability from day one, not as an afterthought.
