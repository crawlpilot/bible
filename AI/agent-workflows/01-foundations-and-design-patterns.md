# 01 — Agent Foundations & Design Patterns

---

## The Four Agent Primitives

Every agent, regardless of framework, is assembled from exactly four components. Understanding the interface between them is more important than any framework choice.

```
┌────────────────────────────────────────────────────────────┐
│                        AGENT                               │
│                                                            │
│   ┌─────────┐    ┌─────────┐    ┌──────────┐  ┌───────┐  │
│   │   LLM   │◄──►│  Tools  │    │  Memory  │  │  Loop │  │
│   │(Reasoner│    │(Actuator│    │ (Context │  │(Ctrl  │  │
│   │         │    │         │    │  Store)  │  │ Flow) │  │
│   └─────────┘    └─────────┘    └──────────┘  └───────┘  │
└────────────────────────────────────────────────────────────┘
```

### 1. LLM (The Reasoner)

The model's job is **decision-making under uncertainty**:
- Which tool to call next, with what arguments
- Whether the task is complete
- How to interpret a tool result that doesn't match expectations
- When to ask for clarification vs. proceed with assumptions

The model does NOT need to know how tools work internally — only their schema and semantics. This is the same interface-not-implementation principle as dependency injection.

### 2. Tools (The Actuators)

Tools are the **only way an agent can affect the world** or retrieve real data. Everything else is the model reasoning over its training data.

**Tool anatomy:**
```json
{
  "name": "web_search",
  "description": "Search the web for current information. Use when you need recent facts, prices, or data not in training.",
  "input_schema": {
    "type": "object",
    "properties": {
      "query": {
        "type": "string",
        "description": "The search query. Be specific. Max 200 chars."
      },
      "max_results": {
        "type": "integer",
        "description": "Number of results to return (1-10)",
        "default": 5
      }
    },
    "required": ["query"]
  }
}
```

**Tool design principles:**

| Principle | Correct | Incorrect |
|-----------|---------|-----------|
| Atomic | `read_file(path)` | `read_and_parse_and_summarize_file(path)` |
| Idempotent | `get_user(id)` → same result | `send_email()` without idempotency key |
| Descriptive name | `search_product_catalog` | `tool_1` |
| Explicit schema | `required: ["query"]` | No schema, free-form string |
| Side-effect declared | description says "this WRITES to db" | Silent mutation |

**Retry semantics — the most important tool property:**

```
Safe to retry (idempotent):    read_file, web_search, get_user, calculate
NOT safe to retry:             send_email, charge_payment, delete_record
Safe with idempotency key:     create_order(idempotency_key="req-abc123")
```

Never give an agent a non-idempotent tool without either: (a) human-in-the-loop confirmation, or (b) an idempotency key the agent must generate and pass.

### 3. Memory (The Context Store)

| Memory Type | Storage | Latency | Capacity | Persistence | Best for |
|-------------|---------|---------|----------|-------------|---------|
| Working (in-context) | Messages array | ~0ms | Context window | Session only | Current task state |
| Episodic (vector store) | Embedding DB | 50–200ms | Unlimited | Across sessions | Past experiences, docs |
| Structured (KV/DB) | Redis/Postgres | 1–10ms | Unlimited | Across sessions | State, user prefs |
| Procedural (system prompt) | Hardcoded | ~0ms | Limited (~8K) | Forever | Skills, personality |

**Memory hierarchy in practice:**
```
System Prompt (procedural)
    │ "You are a research agent. Always cite sources."
    ▼
In-context Messages (working)
    │ [User: "Find me info on X"] [Tool: search → result] [Assistant: "Based on..."]
    ▼
Vector Store lookup (episodic)           KV Store read (structured)
    │ "Similar past queries..."              │ "User's saved preferences..."
    └─────────────────┬───────────────────┘
                      ▼
              Merged context sent to LLM
```

### 4. Loop (Control Flow)

The loop governs **when to continue vs. stop**. Bad loop design is the #1 cause of runaway costs and infinite loops.

```python
# Minimal correct loop structure
MAX_ITERATIONS = 20
iteration = 0

while iteration < MAX_ITERATIONS:
    response = llm.generate(messages=context)
    
    if response.stop_reason == "end_turn":          # Model decided it's done
        break
    
    if response.stop_reason == "tool_use":
        for tool_call in response.tool_calls:
            result = execute_tool(tool_call)
            context.append(tool_result(result))     # Observe
    
    iteration += 1
else:
    raise AgentTimeoutError(f"Exceeded {MAX_ITERATIONS} iterations")
```

---

## Orchestration Topologies

### Pattern 1: ReAct (Reason + Act)

The most common pattern. The model interleaves reasoning steps with tool calls.

```
User: "What's the current stock price of AAPL and how does it compare to last month?"

Loop iteration 1:
  [Think] I need the current price. I'll call get_stock_price.
  [Act]   get_stock_price(ticker="AAPL", period="current") → $185.20

Loop iteration 2:
  [Think] Now I need last month's price.
  [Act]   get_stock_price(ticker="AAPL", period="1month_ago") → $172.40

Loop iteration 3:
  [Think] I have both values. Calculate difference: +$12.80 (+7.4%). Done.
  [Stop]  Return answer.
```

**Strengths**: Simple, debuggable, natural for sequential tasks.  
**Weaknesses**: Sequential — each step waits for the previous. No parallelism.  
**Use when**: Steps are inherently sequential, context from step N needed for step N+1.

### Pattern 2: Plan-Execute

The agent produces a complete plan first, then executes each step.

```
Phase 1 (Plan):
  LLM receives task → outputs structured plan:
  [
    {"step": 1, "action": "search", "query": "AAPL current price"},
    {"step": 2, "action": "search", "query": "AAPL price 1 month ago"},
    {"step": 3, "action": "calculate", "expression": "step1_result - step2_result"}
  ]

Phase 2 (Execute):
  For each step in plan: execute deterministically
  No LLM reasoning during execution — just dispatch + collect
```

**Strengths**: More deterministic, steps can be parallelized if independent, easier to audit.  
**Weaknesses**: Plan must be correct upfront; can't adapt mid-execution; replanning is expensive.  
**Use when**: Task structure is predictable, auditability matters, steps are parallelizable.

### Pattern 3: Orchestrator-Subagent

A parent (orchestrator) decomposes a task and delegates subtasks to specialized child agents (subagents).

```
Orchestrator receives: "Research the top 3 competitors of Stripe and write a comparison report"

Orchestrator plan:
├── Subagent A: "Research Adyen — pricing, market share, tech stack"
├── Subagent B: "Research Braintree — pricing, market share, tech stack"
└── Subagent C: "Research Square — pricing, market share, tech stack"
         ↓ (all run in parallel)
Orchestrator: synthesize A + B + C results into report
```

**Key design decisions:**
- Each subagent gets its **own isolated context** — no shared mutable state
- Subagent results returned as structured data (JSON), not prose, to prevent context pollution
- Orchestrator should be a **bigger model** with more context; subagents can use smaller/faster models
- Timeout each subagent independently — one slow subagent shouldn't block all

**Strengths**: Parallelism, isolation, specialization, scales horizontally.  
**Weaknesses**: Coordination overhead, harder to debug, result aggregation complexity.  
**Use when**: Task decomposes into independent parallel subtasks, specialized expertise needed.

### Pattern 4: Critic-Refiner

A generator agent produces output; a separate critic agent evaluates and scores it; the generator refines based on feedback.

```
Generator: Draft answer to complex question
Critic:    Score answer on: accuracy (7/10), completeness (6/10), clarity (8/10)
           Feedback: "Missing discussion of edge case X"
Generator: Refine based on feedback → v2 answer
Critic:    Score v2: accuracy (9/10), completeness (9/10), clarity (8/10)
           All scores ≥ 8 → ACCEPT
```

**Strengths**: Higher output quality, catches errors before returning to user.  
**Weaknesses**: 2× model cost minimum, adds latency, critic can be wrong.  
**Use when**: Output quality is critical, errors are expensive (legal docs, code for prod, medical).

### Pattern 5: Event-Driven

Agents are triggered by external events rather than running in a continuous loop.

```
Event: new_order_created → trigger Order Agent
Event: payment_failed → trigger Retry Agent
Event: user_question → trigger Support Agent
Event: anomaly_detected → trigger Investigation Agent
```

**Strengths**: Resource-efficient (no idle spinning), natural fit for async workflows.  
**Weaknesses**: Complex to debug across events, ordering guarantees harder.  
**Use when**: Agents should react to real-world triggers, not run continuously.

---

## Sub-Agent Design Patterns

### Specialization Pattern

Each agent has a single domain. The orchestrator routes to the right specialist.

```
User request
    │
    ▼
Router Agent (classifies intent)
    ├── SQL Agent        (database queries)
    ├── Code Agent       (write/review code)
    ├── Research Agent   (web search + synthesis)
    └── Calendar Agent   (scheduling, availability)
```

**When to specialize**: When different subtasks need different tools, context, or system prompts. Specialization reduces context pollution and allows smaller/cheaper models per agent.

### Fan-Out / Fan-In Pattern

Orchestrator spawns N subagents for the same task type with different inputs, collects results.

```python
# Fan-out
subtasks = ["research company A", "research company B", "research company C"]
futures = [spawn_subagent(task) for task in subtasks]   # parallel

# Fan-in
results = await gather(futures)                          # wait for all
synthesis = orchestrator.synthesize(results)             # aggregate
```

**Critical**: Define a timeout. Never `await gather(futures)` without a deadline. One hung subagent blocks the fan-in indefinitely.

### Chain of Responsibility Pattern

Context flows through a pipeline of agents, each adding to or transforming it.

```
Raw Input
    │
    ▼
Agent 1: Preprocessor (clean, normalize)
    │
    ▼
Agent 2: Extractor (identify entities, intents)
    │
    ▼
Agent 3: Enricher (fetch external data for each entity)
    │
    ▼
Agent 4: Responder (generate final answer)
    │
    ▼
Output
```

**Use when**: Task has a natural sequential pipeline where each stage transforms the artifact. Similar to Unix pipes.

### Sentinel Pattern

A dedicated agent validates output before it leaves the system. The sentinel is the last line of defense.

```
Worker Agent: produces output
    │
    ▼
Sentinel Agent: checks output against policy
    ├── PASS: return output to caller
    └── FAIL: reject + reason → Worker Agent retries
```

Sentinel checks: safety policy, format compliance, factual consistency, scope adherence.  
**Never skip the sentinel** when the worker agent has access to irreversible tools.

---

## Tool Calling Internals (Anthropic SDK)

Understanding the wire protocol prevents bugs in custom tool dispatch:

```python
import anthropic

client = anthropic.Anthropic()

# The model returns tool_use blocks when it wants to call a tool
response = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=4096,
    tools=[{
        "name": "web_search",
        "description": "Search the web",
        "input_schema": {
            "type": "object",
            "properties": {"query": {"type": "string"}},
            "required": ["query"]
        }
    }],
    messages=[{"role": "user", "content": "What's the weather in SF?"}]
)

# response.stop_reason == "tool_use" when model wants to call a tool
for block in response.content:
    if block.type == "tool_use":
        tool_name = block.name          # "web_search"
        tool_input = block.input        # {"query": "weather San Francisco"}
        tool_use_id = block.id          # "toolu_01XYZ..."  -- must be echoed back

# After executing the tool, append results to messages:
messages.append({"role": "assistant", "content": response.content})
messages.append({
    "role": "user",
    "content": [{
        "type": "tool_result",
        "tool_use_id": tool_use_id,     # Must match the tool_use block id
        "content": "San Francisco: 62°F, partly cloudy"
    }]
})

# Continue the loop — model will now reason over the tool result
```

**Common bugs:**
- Forgetting to append `response.content` (the assistant turn) before the tool result
- Not echoing `tool_use_id` — the model can't correlate results to calls
- Calling the model again with `stop_reason == "end_turn"` — causes an extra empty turn

---

## FAANG Interview Callout

> **"Design an agent that can answer questions about our internal codebase"**
>
> Key decisions to state immediately:
> 1. **Pattern choice**: Orchestrator-Subagent — orchestrator routes, specialized agents handle search, code execution, and documentation lookup
> 2. **Tool set**: `semantic_search(query)`, `read_file(path)`, `run_test(file)`, `lookup_docs(topic)`
> 3. **Memory**: in-context for current session, vector store (Pinecone/Weaviate) for codebase embeddings
> 4. **Guardrails**: sentinel agent validates answer cites real file paths; no hallucinated paths allowed
> 5. **Cost control**: subagents use claude-haiku for simple lookups, only escalate to claude-sonnet for synthesis
>
> The interviewer wants to hear: isolation, specialization, cost tiering, and failure recovery.
