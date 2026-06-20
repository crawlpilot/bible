# AI/ML Systems Design

AI and ML system design is now a first-class topic at FAANG principal engineer interviews. This section covers both ML systems infrastructure and LLM-native application design.

## Sub-directories

| Folder | Contents |
|--------|----------|
| `llm-applications/` | RAG systems, AI agents, tool use, LLM API design |
| `ml-systems/` | Feature stores, training infra, model serving, MLOps; Ollama + local LLM finetuning trade-offs |
| `ai-architecture/` | AI-native system design patterns (human-in-loop, evaluation pipelines) |
| `prompt-engineering/` | Prompting patterns for production systems |
| `agent-workflows/` | Agent design patterns, agentic loops, token management, determinism, practical web agent |
| `llm-engineering/` | Transformer internals, fine-tuning (LoRA/QLoRA), pre-training from scratch, inference (vLLM), production deployment |
| `resources/` | **Curated links**: foundational papers, courses, frameworks, standards, benchmarks, blogs — [important-links.md](resources/important-links.md) |

## Priority HLD Topics in AI (Agent Workflows)

- **Agent Design Patterns**: ReAct, Plan-Execute, Orchestrator-Subagent, Critic-Refiner — see [agent-workflows/01](agent-workflows/01-foundations-and-design-patterns.md)
- **Token Management**: Context strategies, cost modeling, prompt caching — see [agent-workflows/02](agent-workflows/02-agentic-loops-and-token-management.md)
- **Agent Reliability**: Determinism, guardrails, LLM-as-judge evaluation — see [agent-workflows/03](agent-workflows/03-determinism-and-reliability.md)
- **Agent Architecture Trade-offs**: Single vs multi-agent, state management, framework selection — see [agent-workflows/04](agent-workflows/04-trade-offs-and-design-choices.md)
- **Practical Web Agent**: Full Firecrawl-style web automation agent with code — see [agent-workflows/05](agent-workflows/05-practical-web-automation-agent.md)

## Priority HLD Topics in AI

- **Recommendation System**: collaborative filtering, two-tower model, feature store, serving latency
- **Search System**: embedding-based retrieval, ANN index (HNSW/FAISS), re-ranking
- **ML Platform**: experiment tracking, feature store, training orchestration, model registry, A/B framework
- **RAG System**: chunking strategy, embedding model selection, vector DB, retrieval evaluation
- **LLM API Gateway**: rate limiting, caching, fallback chains, cost attribution
- **Local LLM Deployment**: Ollama architecture, quantization (GGUF/Q4_K_M/Q8), LoRA/QLoRA finetuning, local vs cloud decision — see [ml-systems/ollama-local-models-finetuning](ml-systems/ollama-local-models-finetuning.md)

## Priority Topics in LLM Engineering

- **Transformer Architecture**: attention, RoPE, KV cache, scaling laws — see [llm-engineering/01](llm-engineering/01-transformer-architecture.md)
- **Fine-Tuning with LoRA/QLoRA**: data pipeline, training code, HTML-parser example — see [llm-engineering/02](llm-engineering/02-fine-tuning-base-models.md)
- **Pre-Training from Scratch**: data at scale, distributed training, FSDP — see [llm-engineering/03](llm-engineering/03-pretraining-and-llm-from-scratch.md)
- **Inference Patterns**: vLLM, PagedAttention, quantization (AWQ/GPTQ/GGUF), speculative decoding — see [llm-engineering/04](llm-engineering/04-inference-patterns.md)
- **Production Deployment**: serving architecture, hardware sizing, autoscaling, cost optimization — see [llm-engineering/05](llm-engineering/05-deployment-and-production.md)
