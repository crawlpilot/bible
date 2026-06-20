# 02 — Agentic Loops & Token Management

---

## The Core Loop Anatomy

Every agentic loop is a variation of one pattern:

```
┌──────────────────────────────────────────────────────────────┐
│                    AGENTIC LOOP                              │
│                                                              │
│  ┌─────────┐    ┌──────────┐    ┌────────────┐              │
│  │  Think  │───►│   Act    │───►│  Observe   │              │
│  │(LLM gen)│    │(tool call│    │(inject     │              │
│  │         │◄───│ dispatch)│    │ result)    │              │
│  └─────────┘    └──────────┘    └─────────┬──┘              │
│       ▲                                   │                  │
│       └──────── Update Context ◄──────────┘                  │
│                                                              │
│  Exit when: task_complete OR max_iterations OR error_limit   │
└──────────────────────────────────────────────────────────────┘
```

### The Full Reference Loop

```python
import anthropic
from typing import Any

client = anthropic.Anthropic()

def run_agent(
    task: str,
    tools: list[dict],
    system_prompt: str,
    max_iterations: int = 20,
    max_tokens_per_turn: int = 4096,
) -> str:
    messages = [{"role": "user", "content": task}]
    total_input_tokens = 0
    total_output_tokens = 0

    for iteration in range(max_iterations):
        response = client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=max_tokens_per_turn,
            system=system_prompt,
            tools=tools,
            messages=messages,
        )

        total_input_tokens += response.usage.input_tokens
        total_output_tokens += response.usage.output_tokens

        # Terminal condition: model decided it's done
        if response.stop_reason == "end_turn":
            final_text = next(
                (b.text for b in response.content if b.type == "text"), ""
            )
            log_cost(total_input_tokens, total_output_tokens)
            return final_text

        # Tool use: dispatch all tool calls, collect results
        if response.stop_reason == "tool_use":
            # Append assistant turn FIRST (critical — must mirror the exchange)
            messages.append({"role": "assistant", "content": response.content})

            tool_results = []
            for block in response.content:
                if block.type == "tool_use":
                    result = dispatch_tool(block.name, block.input)
                    tool_results.append({
                        "type": "tool_result",
                        "tool_use_id": block.id,
                        "content": truncate_tool_result(result, max_chars=4000),
                    })

            messages.append({"role": "user", "content": tool_results})

        # Token budget check — prevent context overflow
        estimated_tokens = estimate_message_tokens(messages)
        if estimated_tokens > 100_000:
            messages = compress_context(messages, target_tokens=60_000)

    raise AgentMaxIterationsError(
        f"Agent exceeded {max_iterations} iterations. "
        f"Tokens used: input={total_input_tokens}, output={total_output_tokens}"
    )
```

---

## Stop Conditions — Getting Them Right

A loop that doesn't terminate correctly is the most dangerous failure mode. Define ALL exit conditions explicitly before starting.

| Stop Condition | When to Use | Implementation |
|---------------|-------------|----------------|
| `stop_reason == "end_turn"` | Model signals completion | Built into API response |
| `max_iterations` exceeded | Hard safety limit | Counter, always present |
| Token budget exhausted | Context overflow prevention | Count tokens each turn |
| Error threshold exceeded | Too many tool failures | Counter on exceptions |
| Human escalation triggered | Low confidence or risky action | Model signals via special tool |
| Task validation passed | External check confirms done | Sentinel agent call |
| Time budget exceeded | Latency-sensitive systems | Wall clock timer |

**Never rely on only one stop condition.** Production agents need at minimum:
1. `max_iterations` (prevents infinite loops)
2. `stop_reason == "end_turn"` (normal exit)
3. Token budget check (prevents context overflow errors)

### Human-in-the-Loop as a Stop Condition

```python
# Give the model a special tool to request human input
human_escalation_tool = {
    "name": "request_human_input",
    "description": "Use when you are uncertain, lack permission, or the action is irreversible. This pauses execution and waits for human confirmation.",
    "input_schema": {
        "type": "object",
        "properties": {
            "reason": {"type": "string", "description": "Why you need human input"},
            "proposed_action": {"type": "string", "description": "What you would do if approved"},
            "risk_level": {"type": "string", "enum": ["low", "medium", "high", "critical"]}
        },
        "required": ["reason", "proposed_action", "risk_level"]
    }
}
```

---

## Token Management — The Critical Resource

Tokens are the **atomic currency** of agent cost and context capacity. Mismanaging them is the #1 cause of blown budgets and context overflow errors.

### Token Budget Framework

```
Context Window (200K for claude-sonnet)
├── System Prompt                    ~2K–8K tokens  (fixed)
├── Tool Definitions                 ~1K–4K tokens  (fixed)
├── Conversation History             grows each turn (managed)
│   ├── User messages
│   ├── Assistant turns
│   └── Tool results                 can be large — always truncate
└── Reserved for Output              ~4K–8K tokens  (headroom)

Available for conversation history = 200K - 8K (system) - 4K (tools) - 8K (output) = ~180K
```

**Budget by agent role:**

| Agent Role | Recommended Budget | Reason |
|-----------|-------------------|--------|
| Orchestrator | 128K input + 8K output | Needs full task context, synthesizes many results |
| Research Subagent | 32K input + 4K output | Focused on one search subtask |
| Extraction Subagent | 16K input + 2K output | Reads one document, structured output |
| Sentinel / Critic | 8K input + 1K output | Checks output, not full conversation |

### Strategy 1: Tool Result Truncation

The single most impactful strategy. Never inject raw tool output verbatim.

```python
def truncate_tool_result(result: str, max_chars: int = 4000) -> str:
    if len(result) <= max_chars:
        return result
    
    # Keep head and tail for context; cut middle
    head = result[:max_chars // 2]
    tail = result[-(max_chars // 4):]
    omitted = len(result) - len(head) - len(tail)
    
    return f"{head}\n\n[... {omitted} characters omitted ...]\n\n{tail}"
```

**Tool result size guide:**

| Tool | Raw size | Cap at | Why |
|------|----------|--------|-----|
| Web page (HTML) | 50K–500K chars | 4K chars | After markdown conversion |
| Search results (5 hits) | 5K–20K chars | 3K chars | Snippet per result |
| File read (source code) | 1K–100K chars | 8K chars | Can be larger for code analysis |
| Database row | Usually < 1K | No cap needed | Already small |
| Error message | Usually < 500 chars | No cap needed | Already small |

### Strategy 2: Sliding Window

When conversation history grows too long, drop oldest non-critical turns.

```python
def apply_sliding_window(
    messages: list[dict],
    max_tokens: int = 80_000,
    keep_first_n: int = 2,   # Always keep original user request
) -> list[dict]:
    estimated = estimate_tokens(messages)
    if estimated <= max_tokens:
        return messages
    
    # Always preserve the first N messages (original task context)
    protected = messages[:keep_first_n]
    sliding = messages[keep_first_n:]
    
    # Drop oldest from sliding window until within budget
    while estimate_tokens(protected + sliding) > max_tokens and len(sliding) > 2:
        sliding = sliding[2:]   # Drop oldest user+assistant pair
    
    return protected + sliding
```

**Risk**: Dropping messages loses context the model may need. Always check: does the model still have enough context to complete the task?

### Strategy 3: Summarization Checkpoint

Every K turns, summarize conversation history with a cheap model call.

```python
CHECKPOINT_EVERY_N_TURNS = 5

def maybe_checkpoint(messages: list[dict], turn: int) -> list[dict]:
    if turn % CHECKPOINT_EVERY_N_TURNS != 0:
        return messages
    
    # Summarize everything except the last 2 turns
    to_summarize = messages[:-2]
    recent = messages[-2:]
    
    summary_response = client.messages.create(
        model="claude-haiku-4-5-20251001",   # Cheap model for summarization
        max_tokens=1000,
        messages=[{
            "role": "user",
            "content": f"Summarize the following agent conversation history concisely, preserving all facts, tool results, and decisions made:\n\n{format_messages(to_summarize)}"
        }]
    )
    
    summary_text = summary_response.content[0].text
    
    # Replace history with summary + keep recent turns
    return [
        {"role": "user", "content": f"[CONVERSATION SUMMARY]\n{summary_text}"},
        *recent
    ]
```

**Cost note**: Each checkpoint call costs ~$0.001–$0.005 (Haiku). Worth it if it prevents a context overflow that would abort the entire agent run.

### Strategy 4: Prompt Caching (Anthropic-Specific)

For static content reused across many agent runs (system prompt, tool docs, large context), use cache_control to avoid re-charging for the same tokens.

```python
system_with_cache = [
    {
        "type": "text",
        "text": LONG_SYSTEM_PROMPT,   # e.g., 8000 tokens of instructions + examples
        "cache_control": {"type": "ephemeral"}   # Cache this block
    }
]

response = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=4096,
    system=system_with_cache,    # Pass as list, not string
    messages=messages,
)

# response.usage.cache_read_input_tokens tells you how much was served from cache
# Cache hit pricing: ~10% of normal input token price (as of 2025)
```

**When caching pays off**: Any static content > 1024 tokens reused > 5 times per hour.

---

## Memory Architecture Deep-Dive

### In-Context Memory (Working Memory)

Everything in the `messages` array. The model sees it all on every call.

```
Characteristics:
- Access time:    0ms (already in prompt)
- Capacity:       Context window (up to 200K tokens)
- Cost:           Billed every call — the most expensive memory
- Durability:     Session only — lost when agent terminates
- Consistency:    Perfect — deterministic read

When to use: Current task state, recent tool results, active decisions
When to flush: When token count exceeds 60% of window; at task boundaries
```

### External Vector Memory (Episodic)

Embed observations → store in vector DB → retrieve by semantic similarity.

```python
# Write to episodic memory
def remember(text: str, metadata: dict):
    embedding = embed(text)   # 1536-dim vector
    vector_store.upsert(embedding, text, metadata)

# Read from episodic memory
def recall(query: str, top_k: int = 5) -> list[str]:
    query_embedding = embed(query)
    results = vector_store.query(query_embedding, top_k=top_k)
    return [r.text for r in results]

# In agent loop: recall before each LLM call
relevant_memories = recall(current_task, top_k=3)
messages = [
    {"role": "user", "content": f"Relevant past context:\n{relevant_memories}\n\nCurrent task: {task}"}
]
```

```
Characteristics:
- Access time:    50–200ms (embedding + ANN search)
- Capacity:       Unlimited
- Cost:           Embedding call + vector DB read
- Durability:     Persistent across sessions
- Consistency:    Approximate — semantic match, not exact

When to use: Cross-session memory, large knowledge bases, past experiences
When NOT to use: Exact lookups (use KV store instead), real-time data
```

### Structured Memory (KV / Database)

Exact state stored in Redis, Postgres, or similar. Perfect for agent state machines.

```python
# State machine with Redis
agent_state = {
    "task_id": "task-abc123",
    "status": "in_progress",          # pending | in_progress | complete | failed
    "current_step": 3,
    "completed_steps": [1, 2],
    "artifacts": {"step1_result": "...", "step2_result": "..."},
    "iteration_count": 7,
    "token_usage": {"input": 12400, "output": 3200}
}

redis.set(f"agent:{task_id}", json.dumps(agent_state), ex=3600)  # 1hr TTL

# Resume from checkpoint after failure
saved_state = json.loads(redis.get(f"agent:{task_id}"))
if saved_state and saved_state["status"] == "in_progress":
    resume_from_step(saved_state["current_step"], saved_state["artifacts"])
```

---

## Cost Modeling

### Cost Formula

```
Total Cost = Σ over all iterations:
    (input_tokens_i × input_price) + (output_tokens_i × output_price)
    + Σ over all tool calls:
        (tool_cost_i)   # external API costs (search APIs, browser, etc.)
```

### Reference Costs (Claude Sonnet 4.6, 2025)

| Token type | Price (per 1M tokens) |
|-----------|----------------------|
| Input (standard) | ~$3.00 |
| Input (cache read) | ~$0.30 |
| Input (cache write) | ~$3.75 |
| Output | ~$15.00 |

### Cost Per Agent Run — Worked Examples

**Simple research agent (5 tool calls, 10 iterations):**
```
Per iteration average:
  Input:  2,000 tokens (context grows) × avg over 10 turns = ~15,000 total
  Output: 500 tokens × 10 turns = 5,000 total

Cost: (15,000 × $3/M) + (5,000 × $15/M) = $0.045 + $0.075 = ~$0.12
```

**Orchestrator + 3 subagents (30 total tool calls):**
```
Orchestrator: 40,000 input + 8,000 output = $0.12 + $0.12 = $0.24
Subagent A:   10,000 input + 2,000 output = $0.03 + $0.03 = $0.06
Subagent B:   10,000 input + 2,000 output = $0.03 + $0.03 = $0.06
Subagent C:   10,000 input + 2,000 output = $0.03 + $0.03 = $0.06
Total: ~$0.42 per run
```

### Cost Blowup Patterns (Avoid These)

| Pattern | Root cause | Fix |
|---------|-----------|-----|
| Injecting full HTML page | No truncation on web tool | Truncate to 4K, convert to markdown |
| Re-summarizing entire history every turn | Bad checkpointing logic | Summarize every N turns, not every turn |
| Orchestrator calls full-size model for trivial routing | No model tiering | Use Haiku for classification, Sonnet for synthesis |
| Infinite loop on parse error | Missing error exit condition | Count consecutive errors; abort after 3 |
| Subagent leaks orchestrator context | Shared message list | Each subagent gets isolated message list |
| Redundant tool calls (same query twice) | No deduplication | Cache tool results in-session by (name, input) |

### Tool Result Cache (In-Session)

```python
tool_cache: dict[str, str] = {}

def dispatch_tool_cached(name: str, input: dict) -> str:
    cache_key = f"{name}:{json.dumps(input, sort_keys=True)}"
    if cache_key in tool_cache:
        return tool_cache[cache_key]   # Free — no API call
    
    result = dispatch_tool(name, input)
    tool_cache[cache_key] = result
    return result
```

This catches the common case where the model calls `web_search(query="X")` twice in the same session.

---

## Loop Depth vs. Breadth

| | Deep Loop | Wide (Parallel) |
|---|---|---|
| Structure | Single agent, many sequential steps | Orchestrator + N parallel subagents |
| Context | One context, grows with each step | N isolated contexts |
| Latency | Additive (step1 + step2 + ... + stepN) | Max(subagent latencies) |
| Debugging | Easy — one trace | Harder — N traces to correlate |
| Cost | Lower (one model) | Higher (N models) |
| Token pressure | High (context fills up) | Low (each starts fresh) |

**Rule**: If steps are truly sequential (output of N needed for N+1), go deep. If steps are independent, go wide.

---

## FAANG Interview Callout

> **"How would you prevent cost blowup in a long-running agent?"**
>
> Answer framework (state all five):
> 1. **Hard limits**: `max_iterations=20`, token budget hard cap at 80% of context window
> 2. **Tool result truncation**: cap all tool outputs at 4K chars, convert HTML to markdown before injecting
> 3. **Prompt caching**: cache static system prompt + tool schemas — 90% cost reduction on cached tokens
> 4. **Summarization checkpoints**: every 5 turns, compress history with Haiku — costs ~$0.002, saves potentially thousands of input tokens in subsequent turns
> 5. **Model tiering**: route leaf-node tasks (classification, simple lookup) to Haiku; only Sonnet/Opus for synthesis and planning
>
> Then add: "In production I also track `cost_per_task` as a metric and alert if any agent type exceeds 2× its baseline — drift in tool output size is the most common silent cost driver."
