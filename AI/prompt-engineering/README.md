# Prompt Engineering

Patterns, best practices, and production techniques for prompting large language models — with a focus on Claude/Anthropic specifics, agentic architectures, and running prompts reliably at scale.

## Files in This Directory

| File | What it covers |
|------|---------------|
| [01-core-prompting-techniques.md](01-core-prompting-techniques.md) | Zero-shot, few-shot, CoT, self-consistency, role prompting — fundamentals with benchmark numbers |
| [02-claude-best-practices.md](02-claude-best-practices.md) | Claude/Anthropic-specific: XML tags, system prompt anatomy, extended thinking, prompt caching, tool use, model selection |
| [03-advanced-agentic-patterns.md](03-advanced-agentic-patterns.md) | ReAct, Tree of Thoughts, Reflexion, multi-agent orchestration, prompt chaining, agent failure modes |
| [04-production-prompt-engineering.md](04-production-prompt-engineering.md) | Prompt-as-code, evaluation (LLM-as-judge), A/B testing, cost optimisation, monitoring, regression testing |
| [05-context-engineering.md](05-context-engineering.md) | Context engineering definition, vs. prompt engineering, context rot, position bias, Write/Select/Compress/Isolate strategies, trade-offs, FAANG framing |

---

## Technique Decision Matrix

Map from task type to the prompting technique(s) most likely to work:

| Task type | Primary technique | Enhancement | When NOT to use enhancement |
|-----------|------------------|-------------|------------------------------|
| **Simple extraction** (parse date, extract name) | Zero-shot + format constraint | — | CoT adds tokens, no accuracy gain |
| **Classification** (sentiment, category) | Few-shot (3–8 examples) | Self-consistency if accuracy critical | — |
| **Structured output** (JSON, XML) | Zero-shot + JSON mode / XML schema | Few-shot examples of target format | — |
| **Multi-step reasoning** (math, logic, planning) | Chain-of-Thought (standard or zero-shot) | Self-consistency (K=5–8 samples) | Skip if P99 latency < 500ms |
| **Hard single problem** (Game of 24, proof) | Tree of Thoughts (beam search) | — | 10–100× cost — only for genuinely hard tasks |
| **Question answering over documents** | Long context + document-first | CoT for multi-hop | — |
| **Tool-using agent** | ReAct (Thought→Action→Observation) | Reflexion on failure | Infinite loop risk — always set max_steps |
| **Multi-step agent pipeline** | Plan-and-Execute | Reflexion + memory | Context overflow — use JSON handoffs, not free text |
| **Creative / generative** | Role prompting + examples | Temperature tuning | CoT (kills creativity) |
| **Code generation** | Few-shot with test cases | Extended thinking (Claude) | — |
| **Summarisation** | Zero-shot + length constraint | Map-reduce for very long docs | — |

---

## Source Index

### Research Papers
| Paper | Key finding | Technique |
|-------|------------|-----------|
| Wei et al. 2022, "Chain-of-Thought Prompting" | CoT unlocks reasoning in 100B+ models; +33% on GSM8K | Chain-of-Thought |
| Kojima et al. 2022, "Large Language Models are Zero-Shot Reasoners" | "Let's think step by step" → zero-shot CoT | Zero-shot CoT |
| Wang et al. 2023, "Self-Consistency Improves CoT" | +17.9% on grade-school math vs. greedy CoT | Self-Consistency |
| Yao et al. 2022, "ReAct: Synergizing Reasoning and Acting" | HotpotQA +34% vs. CoT alone | ReAct |
| Yao et al. 2023, "Tree of Thoughts" | Game of 24: 1% (CoT) → 74% (ToT) | Tree of Thoughts |
| Shinn et al. 2023, "Reflexion" | AlfWorld +22% over ReAct with verbal reflection | Reflexion |
| Liu et al. 2023, "G-Eval: NLG Evaluation using GPT-4" | LLM-as-judge correlates 0.88 with human eval | Evaluation |
| Liang et al. 2022, "HELM" | Holistic evaluation across 42 scenarios | Evaluation benchmark |

### Books
| Book | Authors | Key contribution |
|------|---------|-----------------|
| *Prompt Engineering for Generative AI* | James Phoenix & Mike Taylor (O'Reilly, 2024) | Production patterns, evaluation, prompt testing |
| *Building LLM Applications* | Various | Application architecture patterns |

### Anthropic Documentation
| Resource | Content |
|----------|---------|
| docs.anthropic.com/en/docs/build-with-claude/prompt-engineering | Official prompt engineering guide |
| docs.anthropic.com/en/docs/build-with-claude/extended-thinking | Extended thinking (budget tokens) |
| docs.anthropic.com/en/docs/build-with-claude/prompt-caching | Prompt caching API + cost model |
| docs.anthropic.com/en/docs/build-with-claude/tool-use | Tool use / function calling |
