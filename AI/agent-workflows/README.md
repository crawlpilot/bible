# Agent Workflows — Deep-Dive

**Type**: AI Systems Architecture  
**CAP Position**: Availability + Partition Tolerance (agents must keep working despite tool failures)  
**Complexity Model**: O(loop_depth × tool_calls × context_tokens) — cost and latency compound non-linearly

---

## What Is an Agent?

An **agent** is the minimal closed loop that allows an LLM to take actions in the world:

```
Agent = LLM + Tools + Memory + Loop
```

| Component | Role | Failure mode if missing |
|-----------|------|------------------------|
| LLM | Reasoning and decision-making | No agent — just a function |
| Tools | Ability to affect the world or retrieve data | Agent can only hallucinate answers |
| Memory | Context across steps and sessions | Each step starts blind |
| Loop | Iteration until goal is reached | One-shot, no correction |

A **simple LLM call** answers a question. A **chain** pipes outputs through fixed steps. An **agent** decides at runtime which steps to take, in what order, and when to stop.

---

## Decision Matrix: When to Use Agents

| Signal | Use simple LLM call | Use chain | Use agent |
|--------|---------------------|-----------|-----------|
| Steps known at design time | ✓ (if 1 step) | ✓ (fixed N steps) | — |
| Steps depend on intermediate results | — | — | ✓ |
| Requires external data/actions | — | sometimes | ✓ |
| Latency budget | < 2s | 2–10s | > 5s acceptable |
| Cost sensitivity | low | medium | high — plan carefully |
| Reliability required > 99% | ✓ | ✓ | use determinism patterns |
| Task is exploratory / open-ended | — | — | ✓ |

**Rule of thumb**: If you can write the execution path as a static flowchart before seeing the input, you don't need an agent.

---

## Agent Taxonomy

```
┌─────────────────────────────────────────────────┐
│                  Single Agent                   │
│  One LLM, multiple tools, one context window   │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│            Orchestrator + Subagents             │
│  Parent LLM delegates subtasks to children     │
│  Children return results to parent             │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│              Multi-Agent Mesh                   │
│  Agents communicate peer-to-peer               │
│  No central orchestrator                       │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│            Hierarchical (Tree)                  │
│  L1 orchestrator → L2 team leads → L3 workers  │
│  Like org charts for software                  │
└─────────────────────────────────────────────────┘
```

---

## Quick-Reference Card

| Parameter | Typical Value | Notes |
|-----------|--------------|-------|
| Orchestrator context budget | 128K tokens | Leave 20K for output |
| Subagent context budget | 32K tokens | Focused task only |
| Tool result size cap | 4K tokens | Truncate + summarize beyond this |
| Max loop iterations | 10–25 | Hard limit to prevent runaway cost |
| Agentic loop p50 latency | 5–30s | Depends on tool latency |
| Cost per agent run (simple) | $0.01–$0.10 | Claude Sonnet, 3–5 tool calls |
| Cost per agent run (complex) | $0.50–$5.00 | Orchestrator + 3 subagents, 10 iterations |
| Temperature for structured output | 0.0 | Determinism over creativity |
| Temperature for planning/reasoning | 0.3–0.7 | Some creativity needed |

---

## Anti-Patterns (When NOT to Use Agents)

1. **Wrapping a simple lookup in an agent**: SQL query, API call with known parameters — use a direct call.
2. **Agents for real-time responses**: if p50 must be < 500ms, agents won't fit.
3. **Unbounded loops without exit criteria**: always define `max_iterations` and `success_condition` before starting.
4. **Giving agents irreversible tools without human-in-the-loop**: never let an agent `DELETE` production data autonomously.
5. **Sharing one context window across unrelated tasks**: context pollution causes hallucination; isolate subagent contexts.
6. **Using agents where deterministic code works**: if the logic can be expressed as `if/else`, don't burn tokens on it.

---

## File Map

| File | What you'll learn |
|------|-------------------|
| [01-foundations-and-design-patterns.md](01-foundations-and-design-patterns.md) | Agent primitives, tool anatomy, orchestration topologies, sub-agent patterns |
| [02-agentic-loops-and-token-management.md](02-agentic-loops-and-token-management.md) | Loop design, stop conditions, token budgeting, context strategies, cost model |
| [03-determinism-and-reliability.md](03-determinism-and-reliability.md) | Non-determinism sources, guardrails, evaluation, failure recovery, testing |
| [04-trade-offs-and-design-choices.md](04-trade-offs-and-design-choices.md) | Single vs multi-agent, state management, sync vs async, framework comparison |
| [05-practical-web-automation-agent.md](05-practical-web-automation-agent.md) | End-to-end Firecrawl-style web agent: tools, prompts, loop code, production ops |

---

## FAANG Interview Callout

> **30-second pitch on agents vs pipelines**:
> 
> "A pipeline is the right choice when you know the execution path at design time — it's cheaper, faster, and more debuggable. An agent is right when the path through the problem depends on what you discover along the way. The cost is non-determinism: you trade predictability for flexibility. In production, I always pair agents with max_iteration limits, structured output schemas, and checkpoint-based recovery. The hardest part isn't the loop — it's deciding when to give the agent a tool that has real-world side effects, because that's where 'retry on failure' becomes 'retry the mistake.'"

---

## Related Files in This Repo

- [AI/prompt-engineering/01-core-prompting-techniques.md](../prompt-engineering/01-core-prompting-techniques.md) — Prompting patterns underpinning agent reasoning
- [AI/llm-applications/vector-retrieval-patterns.md](../llm-applications/vector-retrieval-patterns.md) — Memory layer for agents using vector stores
- [AI/ai-architecture/rag-system-hld.md](../ai-architecture/rag-system-hld.md) — RAG as a subagent retrieval pattern
