# Agentic AI Engineering — Design Patterns, Best Practices & Tools

Production-focused resources for building, shipping, and operating AI agent systems. Curated for principal engineer interview preparation and real-world system design.

> Legend: ⭐ = essential / must-read | 🎓 = course/tutorial | 📄 = paper | 🛠 = tool/framework | 📏 = standard/guideline | 🏢 = from a major lab

---

## Table of Contents

1. [Production Agent Engineering — Courses & Guides](#1-production-agent-engineering--courses--guides)
2. [Agent Design Patterns](#2-agent-design-patterns)
3. [Multi-Agent Frameworks & Orchestration](#3-multi-agent-frameworks--orchestration)
4. [Agent Memory & State Management](#4-agent-memory--state-management)
5. [Tool Use & Function Calling](#5-tool-use--function-calling)
6. [Agent Observability, Evaluation & Testing](#6-agent-observability-evaluation--testing)
7. [Agent Security & Safety](#7-agent-security--safety)
8. [Reference Architectures & Case Studies](#8-reference-architectures--case-studies)
9. [Quick-Access by Use Case](#9-quick-access-by-use-case)

---

## 1. Production Agent Engineering — Courses & Guides

### GitHub Repositories & Courses

| Resource | Stars | What It Covers | Best For |
|---------|-------|----------------|---------|
| ⭐ [AI Agents for Beginners (Microsoft)](https://github.com/microsoft/ai-agents-for-beginners) | 20k+ | 10-lesson curriculum: ReAct, tool use, multi-agent, AutoGen, Semantic Kernel; Python code throughout | Foundational agent mental models; enterprise patterns |
| ⭐ [Agents Towards Production (Nir Diamant)](https://github.com/NirDiamant/agents-towards-production) | 8k+ | Production-grade patterns: reliability, memory, routing, evaluation, orchestration; end-to-end notebooks | Going from prototype to production agent |
| ⭐ [Production Agentic RAG Course](https://github.com/jamwithai/production-agentic-rag-course) | — | Agentic RAG patterns: query planning, tool-augmented retrieval, multi-step reasoning over documents | RAG systems that need reasoning, not just retrieval |
| ⭐ [GenAI Agents (Nir Diamant)](https://github.com/NirDiamant/GenAI_Agents) | 15k+ | Tutorial collection: single-agent to multi-agent; memory, planning, tool use; runnable notebooks | Broad pattern library with working code |
| [Anthropic Cookbook](https://github.com/anthropics/anthropic-cookbook) | 10k+ | Official Claude recipes: tool use, multi-agent, RAG, computer use; production-quality examples | Claude-specific agent implementation patterns |
| [OpenAI Cookbook — Agents](https://github.com/openai/openai-cookbook/tree/main/examples/agents) | 58k+ | Function calling, tool use, Assistants API patterns | OpenAI-specific agent patterns; Swarm examples |
| [LLM Engineer Handbook](https://github.com/PacktPublishing/LLM-Engineers-Handbook) | 3k+ | End-to-end LLM system: data → training → RAG → agents → deployment | Full production LLM system reference |
| [Decoding ML — LLM Twin Course](https://github.com/decodingml/llm-twin-course) | 5k+ | Real production system: RAG + fine-tuning + agents + MLOps on AWS | Full-stack production AI with infra |

### Official Labs Guides

| Resource | Publisher | What It Covers |
|---------|-----------|----------------|
| ⭐ [Building Effective Agents](https://www.anthropic.com/research/building-effective-agents) 🏢 | Anthropic | When NOT to use agents; augmented LLMs → agents → multi-agent; orchestrator/subagent pattern |
| [Agent Design Patterns (Google)](https://cloud.google.com/blog/products/ai-machine-learning/agent-design-patterns) 🏢 | Google Cloud | Sequential, parallel, loop, DAG patterns; production deployment considerations |
| [AutoGen Documentation](https://microsoft.github.io/autogen/) 🏢 | Microsoft | Conversable agents, group chat, code execution; enterprise multi-agent |
| [Agents (Google DeepMind Whitepaper)](https://arxiv.org/abs/2401.03003) 🏢 📄 | Google DeepMind | Agent anatomy: model + tools + memory + planning; production design decisions |

---

## 2. Agent Design Patterns

### Core Architectural Patterns

| Pattern | Description | When to Use | Reference |
|---------|-------------|-------------|-----------|
| ⭐ **ReAct** | Interleave reasoning traces + actions; observe results; loop | General-purpose tool-using agents | [ReAct paper](https://arxiv.org/abs/2210.03629) |
| ⭐ **Orchestrator–Subagent** | Central orchestrator delegates subtasks to specialized subagents | Complex multi-step workflows; domain separation | [Anthropic agent guide](https://www.anthropic.com/research/building-effective-agents) |
| **Plan-and-Execute** | Planner generates full plan upfront; executor runs steps sequentially | Long-horizon tasks where upfront planning reduces errors | [LangGraph Plan-and-Execute](https://langchain-ai.github.io/langgraph/tutorials/plan-and-execute/plan-and-execute/) |
| **Reflection / Self-Critique** | Agent critiques its own output; revises iteratively | Quality-sensitive tasks (code review, writing, analysis) | [Reflexion paper](https://arxiv.org/abs/2303.11366) |
| **Tool-Augmented LLM** | LLM with access to external tools; no memory/planning loop | Simple, single-turn tool calls | [Toolformer](https://arxiv.org/abs/2302.04761) |
| **Multi-Agent Debate** | Multiple agents argue opposing views; synthesize answer | High-stakes reasoning; reduces hallucinations | [Society of Mind paper](https://arxiv.org/abs/2305.14325) |
| **Routing / Triage Agent** | Classifier agent routes requests to specialized agents | When tasks span multiple domains; cost optimization | [LangGraph Routing](https://langchain-ai.github.io/langgraph/tutorials/customer-support/customer-support/) |
| **Hierarchical Agents** | Manager → worker tree; manager decomposes, workers execute | Large scope tasks; parallel execution possible | [HuggingGPT](https://arxiv.org/abs/2303.17580) |

### Workflow Patterns (from Anthropic's Guide)

| Workflow | Pattern | Best For |
|---------|---------|---------|
| **Prompt Chaining** | Output of step N feeds into step N+1 | Sequential transformation pipelines |
| **Parallelization** | Multiple LLM calls run concurrently; results merged | Independent subtasks; voting/consensus |
| **Routing** | Classifier decides which specialized prompt to use | Multi-category inputs with different handling |
| **Orchestrator–Workers** | Orchestrator dynamically plans; workers execute | Dynamic, unpredictable task decomposition |
| **Evaluator–Optimizer** | One agent generates, another critiques, loop until pass | Quality threshold matters (code, documents) |

### Anti-Patterns to Avoid

| Anti-Pattern | Problem | Better Approach |
|-------------|---------|----------------|
| Agent for everything | Adds latency + cost + failure modes for simple tasks | Use deterministic code for predictable steps |
| Unbounded loops | Agent runs indefinitely without convergence criteria | Set max_iterations + explicit termination conditions |
| No human-in-the-loop for irreversible actions | Agent takes destructive actions autonomously | Gate irreversible tool calls with human approval step |
| Monolithic system prompt | Context bloat; model forgets earlier instructions | Role-specific agents with focused prompts |
| No intermediate state checkpointing | Full restart on any failure | Persist state after each step; support resumability |

---

## 3. Multi-Agent Frameworks & Orchestration

### Production Frameworks

| Framework | Stars | Language | Strengths | When to Use |
|-----------|-------|----------|-----------|-------------|
| ⭐ [LangGraph](https://github.com/langchain-ai/langgraph) | 12k+ | Python | Stateful graphs; human-in-loop; persistence; streaming; best production choice | Complex stateful workflows; need checkpointing |
| ⭐ [Microsoft AutoGen](https://github.com/microsoft/autogen) | 35k+ | Python | Multi-agent conversation; code execution sandbox; enterprise | Multi-agent code execution; Microsoft stack |
| [Microsoft Semantic Kernel](https://github.com/microsoft/semantic-kernel) | 22k+ | Python/C#/.NET | Plugin architecture; Azure AI integration; enterprise | .NET shops; Azure-native |
| [CrewAI](https://github.com/crewAIInc/crewAI) | 25k+ | Python | Role-based agents; crew/task abstraction; simple API | Structured role workflows; quick prototyping |
| [smolagents (HuggingFace)](https://github.com/huggingface/smolagents) | 12k+ | Python | Minimal code agents; code-as-action; fast iteration | Lightweight; code-executing agents; OSS models |
| [PydanticAI](https://github.com/pydantic/pydantic-ai) | 8k+ | Python | Type-safe agents; Pydantic validation; structured outputs | Production Python; type safety matters |
| [Google ADK (Agent Developer Kit)](https://github.com/google/adk-python) | 5k+ | Python | Google's official framework; Vertex AI integration; multi-agent | Google Cloud; Gemini-based agents |
| [LlamaIndex Workflows](https://docs.llamaindex.ai/en/stable/understanding/workflows/) | — | Python | Event-driven; async; good for RAG-heavy agents | When LlamaIndex is already the data layer |
| [Haystack Pipelines](https://github.com/deepset-ai/haystack) | 18k+ | Python | DAG-based pipelines; enterprise search + agents | Document-heavy; enterprise NLP pipelines |

### Lightweight / Protocol Layer

| Tool | What It Does | Why It Matters |
|------|-------------|----------------|
| ⭐ [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) 📏 | Standard for LLM ↔ tool/data connectivity; tool definitions, resources, prompts | Becoming the USB-C of agent tool connectivity; Anthropic + community |
| [LiteLLM](https://github.com/BerriAI/litellm) 🛠 | Unified API over 100+ LLM providers; drop-in OpenAI replacement | Multi-model agents; fallback routing; cost tracking |
| [Agent Protocol](https://github.com/Div99/agent-protocol) 📏 | Open standard for agent APIs; start/step/artifact endpoints | Interoperability between agent frameworks |
| [OpenAI Swarm](https://github.com/openai/swarm) 🛠 | Experimental lightweight multi-agent handoff framework | Understanding agent handoff patterns; educational |

---

## 4. Agent Memory & State Management

### Memory Types & Implementations

| Memory Type | Scope | Implementation | Use Case |
|-------------|-------|----------------|---------|
| **In-context (working)** | Single session | System prompt + message history | Short interactions; few-shot examples |
| **External (episodic)** | Persistent across sessions | Vector DB + semantic search | "Remember what user told me last week" |
| **Semantic (knowledge)** | Static facts | Vector DB / KV store | Domain knowledge; product catalog |
| **Procedural** | Skills / learned behaviors | Fine-tuned weights or few-shot examples | Recurring task patterns |

### Memory Frameworks & Tools

| Tool | What It Does | When to Use |
|------|-------------|------------|
| ⭐ [Mem0](https://github.com/mem0ai/mem0) | Intelligent memory layer for AI apps; personalization; multi-level memory | Production agents that need persistent personalization |
| [Zep](https://github.com/getzep/zep) | Long-term memory for LLM apps; entity extraction; temporal context | Conversation history + entity memory at scale |
| [LangMem (LangGraph)](https://langchain-ai.github.io/langgraph/concepts/memory/) | LangGraph-native memory: in-thread + cross-thread | LangGraph agents needing long-term memory |
| [Letta (MemGPT)](https://github.com/cpacker/MemGPT) | OS-inspired hierarchical memory; self-editing context | Unbounded conversation context; long-running agents |

---

## 5. Tool Use & Function Calling

### Key Resources

| Resource | Type | Why It Matters |
|---------|------|----------------|
| ⭐ [Anthropic Tool Use Guide](https://docs.anthropic.com/en/docs/build-with-claude/tool-use) | 🏢 🎓 | Official best practices: tool definition, parallel tool use, tool choice, streaming |
| ⭐ [OpenAI Function Calling Guide](https://platform.openai.com/docs/guides/function-calling) | 🏢 🎓 | JSON Schema tool definitions; parallel calls; strict mode |
| [MCP Tool Definitions](https://modelcontextprotocol.io/docs/concepts/tools) | 📏 | Standard tool schema format; server ↔ client protocol |
| [Gorilla LLM (Tool Benchmark)](https://github.com/ShishirPatil/gorilla) | 📄 🛠 | Benchmark + fine-tuned model for accurate API/tool calls |
| [ToolBench (Benchmark)](https://github.com/OpenBMB/ToolBench) | 📄 | 16k+ real-world APIs; tool-augmented agent evaluation |

### Tool Design Best Practices

| Practice | Why | Source |
|---------|-----|--------|
| One tool per action; avoid overloaded tools | Reduces model confusion; clearer error attribution | Anthropic tool use guide |
| Include usage examples in tool descriptions | Model follows examples better than instructions | Empirical from production |
| Return structured error messages | Agent can self-correct; improves ReAct loop reliability | LangGraph best practices |
| Implement tool-level retries with backoff | Network failures shouldn't kill agent runs | Production engineering standard |
| Gate side-effectful tools with confirmation | Prevents irreversible actions in autonomous loops | Anthropic safety guidelines |

---

## 6. Agent Observability, Evaluation & Testing

### Observability Tools

| Tool | Stars | What It Does | When to Use |
|------|-------|-------------|------------|
| ⭐ [LangSmith](https://smith.langchain.com/) 🛠 | — | Full LLM + agent trace; step-by-step tool calls; prompt comparison; dataset eval | LangChain/LangGraph apps; production debugging |
| ⭐ [Langfuse](https://github.com/langfuse/langfuse) 🛠 | 7k+ | Open-source LLM observability; traces, evals, datasets, cost tracking | Open-source alternative to LangSmith; self-hosted |
| [AgentOps](https://github.com/AgentOps-AI/agentops) 🛠 | 3k+ | Agent-native observability; session replay; multi-agent support; cost/token tracking | Agent-specific observability; works with CrewAI/AutoGen |
| [Phoenix (Arize)](https://github.com/Arize-ai/phoenix) 🛠 | 4k+ | Open-source; traces + spans; embedding drift; RAG evaluation | Local + production; OTEL-compatible |
| [OpenLLMetry](https://github.com/traceloop/openllmetry) 🛠 | 2k+ | OpenTelemetry for LLMs; vendor-neutral tracing | Teams standardizing on OTEL for all services |
| [Helicone](https://www.helicone.ai/) 🛠 | 2k+ | LLM proxy: logging, caching, rate limiting, cost tracking | Minimal-setup cost + latency tracking |

### Evaluation Frameworks

| Tool | What It Evaluates | Key Metrics |
|------|------------------|-------------|
| ⭐ [RAGAS](https://docs.ragas.io/) | RAG pipelines | Faithfulness, answer relevancy, context recall, context precision |
| [DeepEval](https://github.com/confident-ai/deepeval) | LLM + agent outputs | Hallucination, answer relevancy, contextual precision, G-Eval |
| [TruLens](https://github.com/truera/trulens) | RAG + LLM apps | RAG triads; custom feedback functions; multi-turn agent evals |
| [PromptFlow (Microsoft)](https://github.com/microsoft/promptflow) | LLM workflows | Build, eval, deploy LLM flows; Azure AI Studio integration |
| [Inspect AI (UK AISI)](https://github.com/UKGovernmentAIOS/inspect_ai) | Model + agent capabilities | Safety evals; task performance; tool use accuracy |
| [AgentBench](https://github.com/THUDM/AgentBench) 📄 | Agent task performance | 8 environments: code, browsing, OS tasks, DB operations |

### Testing Patterns for Agents

| Pattern | What to Test | Tools |
|---------|-------------|-------|
| **Evals-as-tests** | Agent produces correct final answer given fixtures | DeepEval, RAGAS, custom pytest fixtures |
| **Trace-based assertions** | Correct tool was called with correct args | LangSmith datasets, Langfuse experiments |
| **Adversarial inputs** | Agent handles malformed tool responses, empty results | Inject errors into tool mocks |
| **Latency + cost regression** | Token count and wall time stay within bounds | Helicone / LangSmith metrics |
| **Human-in-loop checkpoints** | Approval gates trigger correctly | LangGraph interrupt mechanism |

---

## 7. Agent Security & Safety

### Key Resources

| Resource | Type | What It Covers |
|---------|------|----------------|
| ⭐ [OWASP Top 10 for LLM Applications](https://owasp.org/www-project-top-10-for-large-language-model-applications/) | 📏 | LLM01: Prompt Injection, LLM06: Sensitive Info Disclosure, LLM08: Excessive Agency |
| [Prompt Injection: A Practical Guide](https://promptinjection.org/) | 🎓 | Attack taxonomy; direct vs indirect injection; defenses |
| [NIST AI RMF for Agentic AI](https://airc.nist.gov/RMF_Overview) | 📏 | Governance controls mapped to agentic system risks |
| [Anthropic Agent Safety Guidance](https://www.anthropic.com/research/building-effective-agents) | 🏢 | Minimal permissions; human-in-loop; prefer reversible actions |
| [LLM Security (Johann Rehberger)](https://embracethered.com/blog/posts/2023/chatgpt-plugin-vulnerabilities-chat-with-code/) | 🎓 | Practical attack demonstrations; plugin vulnerabilities; agent compromise |

### Security Checklist for Agents

| Control | Why | Implementation |
|---------|-----|----------------|
| Minimal tool permissions | Reduce blast radius of prompt injection | Scope each tool to least necessary capability |
| Input sanitization at tool boundary | Prevent injected tool parameters | Validate + escape all LLM-generated tool args |
| Output validation before execution | LLM may generate malicious code/commands | Sandbox code execution; validate schemas |
| Audit log every tool call | Forensics + compliance | Structured log: tool, args, result, timestamp, agent_id |
| Rate limit + cost cap per session | Prevent runaway agent spend | Hard limits in LLM gateway (Helicone, LiteLLM) |
| Human approval for irreversible actions | Prevent data deletion, external sends | LangGraph interrupt / approval node |

---

## 8. Reference Architectures & Case Studies

### Real-World Agent Systems

| System | Company | Architecture | Key Lessons |
|--------|---------|-------------|-------------|
| [SWE-agent](https://arxiv.org/abs/2405.15793) | Princeton | ReAct + file editor + shell; ACIs (Agent-Computer Interfaces) | Interface design matters as much as the model |
| [Devin](https://www.cognition.ai/blog/introducing-devin) | Cognition | Long-horizon coding agent; persistent workspace; planning + execution | State management for multi-hour tasks |
| [OpenHands (OpenDevin)](https://github.com/All-Hands-AI/OpenHands) | Community | Software agent; sandbox; browser + terminal + editor | Open-source Devin alternative; production agent infra |
| [AutoGPT](https://github.com/Significant-Gravitas/AutoGPT) | Community | One of first autonomous agent frameworks; memory + web search | Shows limits of unbounded autonomy; eval is hard |
| [STORM (Stanford)](https://github.com/stanford-oval/storm) | Stanford | Multi-agent knowledge curation; perspective-guided research | Multi-agent debate improves output quality |
| [GPT Researcher](https://github.com/assafelovic/gpt-researcher) | Community | Parallel research agent; source aggregation; structured reports | Parallel tool calls reduce latency 5–10× |

### Architecture Decision Patterns

| Decision | Options | Recommendation | Trade-off |
|---------|---------|---------------|----------|
| **Single vs multi-agent** | One agent with many tools vs specialized subagents | Single agent first; split when context bloat degrades quality | Multi-agent adds latency + orchestration complexity |
| **ReAct vs Plan-and-Execute** | Interleaved vs upfront plan | Plan-and-Execute for predictable long tasks; ReAct for dynamic | ReAct is more flexible; P&E is more reliable for known workflows |
| **Synchronous vs async execution** | Block on each tool vs parallel tool calls | Parallel wherever tools are independent (I/O bound) | Async complicates error handling + state management |
| **In-context vs external memory** | History in prompt vs RAG over past sessions | In-context for < 20 turns; external memory beyond that | External memory retrieval is imprecise; adds latency |
| **Stateless vs stateful agent** | No persistence vs checkpointed state | Stateful for multi-session; stateless for single-turn | Stateful requires storage + versioning; harder to scale horizontally |

---

## 9. Quick-Access by Use Case

### "I'm building my first production agent" →
Start: [Microsoft AI Agents for Beginners](https://github.com/microsoft/ai-agents-for-beginners) · [Anthropic Building Effective Agents](https://www.anthropic.com/research/building-effective-agents) · [LangGraph docs](https://langchain-ai.github.io/langgraph/) · [Agents Towards Production](https://github.com/NirDiamant/agents-towards-production)

### "I need production-grade agentic RAG" →
Start: [Production Agentic RAG Course](https://github.com/jamwithai/production-agentic-rag-course) · [LlamaIndex Workflows](https://docs.llamaindex.ai/en/stable/understanding/workflows/) · [RAGAS eval](https://docs.ragas.io/) · [Nir Diamant GenAI Agents](https://github.com/NirDiamant/GenAI_Agents)

### "I'm designing a multi-agent orchestration system" →
Start: [LangGraph multi-agent tutorial](https://langchain-ai.github.io/langgraph/tutorials/multi_agent/multi-agent-collaboration/) · [AutoGen docs](https://microsoft.github.io/autogen/) · [LLM-based Multi-Agent Survey](https://arxiv.org/abs/2402.01680) · [Orchestrator–Subagent pattern](https://www.anthropic.com/research/building-effective-agents)

### "I need to observe and debug agent behavior in production" →
Start: [LangSmith](https://smith.langchain.com/) · [Langfuse](https://github.com/langfuse/langfuse) · [AgentOps](https://github.com/AgentOps-AI/agentops) · [DeepEval](https://github.com/confident-ai/deepeval)

### "I need to secure an agent that calls external tools" →
Start: [OWASP Top 10 for LLMs](https://owasp.org/www-project-top-10-for-large-language-model-applications/) · [Anthropic safety guidance](https://www.anthropic.com/research/building-effective-agents) · [Prompt Injection guide](https://promptinjection.org/) · [LiteLLM rate limiting](https://github.com/BerriAI/litellm)

### "I want patterns for long-horizon coding/software agents" →
Start: [SWE-agent paper](https://arxiv.org/abs/2405.15793) · [OpenHands](https://github.com/All-Hands-AI/OpenHands) · [smolagents](https://github.com/huggingface/smolagents) · [GPT Researcher](https://github.com/assafelovic/gpt-researcher)
