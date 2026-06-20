# AI/ML — Important Links, References & Standards

Curated links across foundational papers, courses, frameworks, standards, benchmarks, and community resources. Organized for principal engineer interview preparation and production AI system design.

> Legend: ⭐ = essential / must-read | 🎓 = course/tutorial | 📄 = paper | 🛠 = tool/framework | 📏 = standard/guideline | 🏢 = from a major lab

---

## Table of Contents

1. [Foundational Papers](#1-foundational-papers)
2. [LLM Engineering & Architecture](#2-llm-engineering--architecture)
3. [RAG & Retrieval Systems](#3-rag--retrieval-systems)
4. [Agents & Agentic Systems](#4-agents--agentic-systems)
5. [Courses & Learning Paths](#5-courses--learning-paths)
6. [Frameworks & Libraries](#6-frameworks--libraries)
7. [Standards, Guidelines & Safety](#7-standards-guidelines--safety)
8. [Benchmarks & Evaluation](#8-benchmarks--evaluation)
9. [Model Cards, Transparency & Governance](#9-model-cards-transparency--governance)
10. [Production & MLOps](#10-production--mlops)
11. [Blogs, Newsletters & Communities](#11-blogs-newsletters--communities)
12. [Conferences & Venues](#12-conferences--venues)
13. [Interactive Playgrounds & Tools](#13-interactive-playgrounds--tools)
14. [Interview-Specific Resources](#14-interview-specific-resources)

---

## 1. Foundational Papers

### Transformers & Attention

| Paper | Authors | Year | Why It Matters |
|-------|---------|------|----------------|
| ⭐ [Attention Is All You Need](https://arxiv.org/abs/1706.03762) | Vaswani et al. (Google) | 2017 | Introduced the Transformer architecture; foundation of every modern LLM |
| ⭐ [BERT: Pre-training of Deep Bidirectional Transformers](https://arxiv.org/abs/1810.04805) | Devlin et al. (Google) | 2018 | Bidirectional pretraining; masked language modeling; changed NLP |
| [RoPE: Rotary Position Embedding](https://arxiv.org/abs/2104.09864) | Su et al. | 2021 | Position encoding used in LLaMA, Mistral, Gemma; enables context length extrapolation |
| [FlashAttention](https://arxiv.org/abs/2205.14135) | Dao et al. (Stanford) | 2022 | IO-aware exact attention; 2–4× speedup; now standard in production |
| [FlashAttention-2](https://arxiv.org/abs/2307.08691) | Dao (Stanford) | 2023 | Better parallelism; 2× faster than FA1; used in all modern inference |
| [GQA: Grouped-Query Attention](https://arxiv.org/abs/2305.13245) | Ainslie et al. (Google) | 2023 | Reduces KV cache size; used in LLaMA 2, Mistral, Gemma |
| [Ring Attention](https://arxiv.org/abs/2310.01889) | Liu et al. (Berkeley) | 2023 | Enables million-token context by distributing KV cache across devices |

### GPT Family & Scaling

| Paper | Authors | Year | Why It Matters |
|-------|---------|------|----------------|
| ⭐ [Language Models are Few-Shot Learners (GPT-3)](https://arxiv.org/abs/2005.14165) | Brown et al. (OpenAI) | 2020 | 175B parameter model; in-context learning; defined the modern LLM era |
| ⭐ [Scaling Laws for Neural Language Models](https://arxiv.org/abs/2001.08361) | Kaplan et al. (OpenAI) | 2020 | Data-model-compute scaling laws; drives all pretraining budget decisions |
| [Chinchilla: Training Compute-Optimal LLMs](https://arxiv.org/abs/2203.15556) | Hoffmann et al. (DeepMind) | 2022 | Revised scaling laws: train smaller models on more data; Chinchilla-optimal |
| [GPT-4 Technical Report](https://arxiv.org/abs/2303.08774) | OpenAI | 2023 | Sparse details on GPT-4; important for understanding multimodal LLM design |
| [Llama 2](https://arxiv.org/abs/2307.09288) | Touvron et al. (Meta) | 2023 | Open-weight 7B–70B; RLHF details; Ghost Attention; de facto open baseline |
| [Llama 3 Technical Report](https://arxiv.org/abs/2407.21783) | Meta AI | 2024 | 405B model; GQA; improved tokenizer; multi-modal; production training at scale |
| [Mistral 7B](https://arxiv.org/abs/2310.06825) | Jiang et al. (Mistral AI) | 2023 | Sliding window attention + GQA; best-in-class 7B; architecture reference |

### Alignment & RLHF

| Paper | Authors | Year | Why It Matters |
|-------|---------|------|----------------|
| ⭐ [InstructGPT (RLHF)](https://arxiv.org/abs/2203.02155) | Ouyang et al. (OpenAI) | 2022 | Introduced RLHF for alignment; foundation of ChatGPT; SFT → RM → PPO pipeline |
| [Constitutional AI](https://arxiv.org/abs/2212.08073) | Bai et al. (Anthropic) | 2022 | Self-critique + revision for alignment; replaced human labelers with AI feedback |
| [Direct Preference Optimization (DPO)](https://arxiv.org/abs/2305.18290) | Rafailov et al. (Stanford) | 2023 | Eliminates reward model; directly fine-tunes on preferences; simpler than PPO |
| [RLAIF: AI Feedback vs Human Feedback](https://arxiv.org/abs/2309.00267) | Lee et al. (Google) | 2023 | AI-generated feedback matches human feedback quality at a fraction of cost |
| [Reward Model Ensembles](https://arxiv.org/abs/2310.02743) | Coste et al. | 2023 | Addressing reward hacking; reference for robust alignment |

### Mixture of Experts

| Paper | Authors | Year | Why It Matters |
|-------|---------|------|----------------|
| [Switch Transformer](https://arxiv.org/abs/2101.03961) | Fedus et al. (Google) | 2021 | First trillion-parameter MoE model; sparse routing; training stability |
| [Mixtral 8x7B](https://arxiv.org/abs/2401.04088) | Jiang et al. (Mistral AI) | 2024 | Open MoE; top-2 routing; beats LLaMA 2 70B at 13B active params |
| [DeepSeek-V2 MoE](https://arxiv.org/abs/2405.04434) | DeepSeek AI | 2024 | Multi-head latent attention + fine-grained MoE; 21B active / 236B total |

---

## 2. LLM Engineering & Architecture

### Inference Optimization

| Resource | Type | Why It Matters |
|----------|------|----------------|
| ⭐ [vLLM Paper: PagedAttention](https://arxiv.org/abs/2309.06180) | 📄 | KV cache memory management via paging; up to 24× throughput; now standard |
| [Continuous Batching (Orca)](https://www.usenix.org/conference/osdi22/presentation/yu) | 📄 | Dynamic request scheduling; eliminates static batching bottleneck |
| [Speculative Decoding](https://arxiv.org/abs/2211.17192) | 📄 | Draft model + verification; 2–3× latency reduction; used in Gemini, Claude |
| [Medusa: Multiple Decoding Heads](https://arxiv.org/abs/2401.10774) | 📄 | Self-speculative decoding; no separate draft model |
| [AWQ: Activation-Aware Weight Quantization](https://arxiv.org/abs/2306.00978) | 📄 | 4-bit quantization with minimal quality loss; production inference |
| [GGUF Format Documentation](https://github.com/ggerganov/ggml/blob/master/docs/gguf.md) | 🛠 | File format for quantized models (llama.cpp, Ollama); Q4_K_M, Q8 variants |

### Fine-Tuning

| Resource | Type | Why It Matters |
|----------|------|----------------|
| ⭐ [LoRA: Low-Rank Adaptation](https://arxiv.org/abs/2106.09685) | 📄 | Train 1% of parameters; full-model quality; now universal fine-tuning standard |
| [QLoRA: Efficient Fine-Tuning of Quantized LLMs](https://arxiv.org/abs/2305.14314) | 📄 | 4-bit quantization + LoRA; fine-tune 65B on single GPU; democratized fine-tuning |
| [DoRA: Weight-Decomposed Low-Rank Adaptation](https://arxiv.org/abs/2402.09353) | 📄 | Separates magnitude and direction in LoRA; better than LoRA on most tasks |
| [LLaMA-Factory](https://github.com/hiyouga/LLaMA-Factory) | 🛠 | Unified fine-tuning framework; SFT/DPO/PPO; supports all major models |
| [Unsloth](https://github.com/unslothai/unsloth) | 🛠 | 2× faster, 70% less memory for LoRA fine-tuning; best for single-GPU |
| [Axolotl](https://github.com/OpenAccess-AI-Collective/axolotl) | 🛠 | Config-driven fine-tuning; multi-GPU; DPO/RLHF support |
| [Hugging Face Fine-Tuning Tutorial](https://huggingface.co/docs/transformers/training) | 🎓 | Official HF guide for SFT; PEFT integration; good starting point |

### Pretraining & Distributed Training

| Resource | Type | Why It Matters |
|----------|------|----------------|
| ⭐ [Megatron-LM](https://github.com/NVIDIA/Megatron-LM) | 🛠 📄 | Tensor + pipeline + data parallelism; used for GPT-3, LLaMA, Falcon training |
| [PyTorch FSDP Documentation](https://pytorch.org/docs/stable/fsdp.html) | 🛠 | Fully Sharded Data Parallel; LLaMA 2/3 training framework |
| [ZeRO: Memory Optimization for LLM Training](https://arxiv.org/abs/1910.02054) | 📄 | DeepSpeed ZeRO stages 1/2/3; shards optimizer state, gradients, params |
| [The Pile: 800GB Text Dataset](https://arxiv.org/abs/2101.00027) | 📄 | Open pretraining dataset; benchmark for dataset curation decisions |
| [DataComp](https://arxiv.org/abs/2304.14108) | 📄 | Framework for dataset curation; shows data quality > data quantity |

---

## 3. RAG & Retrieval Systems

### Core Papers

| Paper | Authors | Year | Why It Matters |
|-------|---------|------|----------------|
| ⭐ [RAG: Retrieval-Augmented Generation](https://arxiv.org/abs/2005.11401) | Lewis et al. (Meta) | 2020 | Original RAG paper; dense retrieval + generation; foundation of the pattern |
| [REALM: Retrieval-Enhanced Language Model](https://arxiv.org/abs/2002.08909) | Guu et al. (Google) | 2020 | Knowledge-grounded LM pre-training; early retrieval-augmentation |
| [HNSW: Hierarchical Navigable Small World](https://arxiv.org/abs/1603.09320) | Malkov & Yashunin | 2016 | ANN index used in every vector DB (Pinecone, Weaviate, Milvus, Qdrant) |
| [ColBERT: Efficient Document Retrieval](https://arxiv.org/abs/2004.12832) | Khattab & Zaharia (Stanford) | 2020 | Late interaction; token-level similarity; better recall than bi-encoder |
| [Sentence-BERT](https://arxiv.org/abs/1908.10084) | Reimers & Gurevych | 2019 | Semantic sentence embeddings; still competitive baseline for RAG |
| [BGE-M3: Multi-Lingual, Multi-Granularity](https://arxiv.org/abs/2402.03216) | Chen et al. (BAAI) | 2024 | Dense + sparse + multi-vector retrieval; state-of-art open embedding model |

### RAG Patterns & Guides

| Resource | Type | Why It Matters |
|----------|------|----------------|
| ⭐ [RAG Survey (2023)](https://arxiv.org/abs/2312.10997) | 📄 | Comprehensive taxonomy: naive → advanced → modular RAG; great interview reference |
| [LlamaIndex RAG Documentation](https://docs.llamaindex.ai/en/stable/understanding/rag/) | 🎓 🛠 | Best practical RAG tutorials; covers chunking, retrieval, evaluation |
| [Anthropic's Guide to RAG](https://www.anthropic.com/research/contextual-retrieval) | 🏢 📄 | Contextual retrieval: prepend chunk context → 67% reduction in retrieval failures |
| [HyDE: Hypothetical Document Embeddings](https://arxiv.org/abs/2212.10496) | 📄 | Generate hypothetical answer → embed it → retrieve; better than query embedding |
| [RAGAS: Evaluation Framework for RAG](https://arxiv.org/abs/2309.15217) | 📄 🛠 | Automated RAG evaluation: faithfulness, answer relevancy, context precision |
| [Chunking Strategies Guide](https://www.pinecone.io/learn/chunking-strategies/) | 🎓 | Fixed vs semantic vs hierarchical chunking; practical tradeoffs |

---

## 4. Agents & Agentic Systems

### Core Papers

| Paper | Authors | Year | Why It Matters |
|-------|---------|------|----------------|
| ⭐ [ReAct: Reason + Act](https://arxiv.org/abs/2210.03629) | Yao et al. (Google/Princeton) | 2022 | Interleaved reasoning + tool use; foundation of most agent frameworks |
| ⭐ [Toolformer](https://arxiv.org/abs/2302.04761) | Schick et al. (Meta) | 2023 | LLM learns to use APIs via self-supervised training; tool use fundamentals |
| [HuggingGPT / Jarvis](https://arxiv.org/abs/2303.17580) | Shen et al. (Microsoft) | 2023 | LLM as controller for specialized models; multi-model orchestration |
| [AutoGPT Analysis](https://arxiv.org/abs/2306.02224) | Yang et al. | 2023 | Benchmark study of autonomous agents; reveals current failure modes |
| [Tree of Thoughts](https://arxiv.org/abs/2305.10601) | Yao et al. (Princeton) | 2023 | Deliberate exploration of reasoning paths; better than CoT for planning |
| [LLM-based Multi-Agent Survey](https://arxiv.org/abs/2402.01680) | Guo et al. | 2024 | Comprehensive taxonomy; communication patterns; orchestration strategies |
| [SWE-agent](https://arxiv.org/abs/2405.15793) | Yang et al. (Princeton) | 2024 | Software engineering agent; agent-computer interfaces; benchmark on SWE-bench |

### Frameworks & Guides

> For a production-focused deep-dive on agent design patterns, tools, observability, and security, see **[agent-engineering-resources.md](agent-engineering-resources.md)**.

| Resource | Type | Why It Matters |
|----------|------|----------------|
| ⭐ [Anthropic's Guide to Building Effective Agents](https://www.anthropic.com/research/building-effective-agents) | 🏢 🎓 | Multi-agent patterns; orchestrator-subagent; when to use agents vs pipelines |
| [LangGraph Documentation](https://langchain-ai.github.io/langgraph/) | 🛠 🎓 | Stateful agent graphs; human-in-loop; production agent framework |
| [OpenAI Assistants API](https://platform.openai.com/docs/assistants/overview) | 🏢 🛠 | Managed agent runtime; threads + tool calls + files |
| [Microsoft AutoGen](https://github.com/microsoft/autogen) | 🛠 | Multi-agent conversation framework; enterprise-focused |
| [CrewAI](https://github.com/joaomdmoura/crewAI) | 🛠 | Role-based multi-agent coordination; good for structured workflows |
| [Model Context Protocol (MCP)](https://modelcontextprotocol.io/introduction) | 📏 🛠 | Anthropic's open standard for LLM ↔ tool/data connectivity; becoming industry standard |
| [Agency Survey: A Unified Framework](https://arxiv.org/abs/2309.02427) | 📄 | Formalization of agent components; good for interview vocabulary |

### Prompt Engineering for Agents

| Resource | Type | Why It Matters |
|----------|------|----------------|
| ⭐ [Chain-of-Thought Prompting](https://arxiv.org/abs/2201.11903) | 📄 | Wei et al. (Google); step-by-step reasoning; emergent at ~100B params |
| [Self-Consistency Improves CoT](https://arxiv.org/abs/2203.11171) | 📄 | Sample multiple reasoning paths; vote on answer; +10–15% accuracy |
| [Step-Back Prompting](https://arxiv.org/abs/2310.06117) | 📄 | Abstract to principle first, then solve; Google DeepMind |
| ⭐ [Anthropic Prompt Engineering Guide](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/overview) | 🏢 🎓 | Official Claude prompting best practices; XML tags, examples, edge cases |
| [OpenAI Prompt Engineering Guide](https://platform.openai.com/docs/guides/prompt-engineering) | 🏢 🎓 | Official OpenAI guide; six strategies for better results |
| [DSPY: Programming Language Models](https://github.com/stanfordnlp/dspy) | 🛠 📄 | Declarative, optimizer-based prompting; replaces manual prompt tuning |

---

## 5. Courses & Learning Paths

### Foundational (Required)

| Course | Provider | Instructor | What You'll Learn |
|--------|---------|-----------|------------------|
| ⭐ [Neural Networks: Zero to Hero](https://karpathy.ai/zero-to-hero.html) | Independent | Andrej Karpathy | Build GPT/LLM from scratch in Python; micrograd → makemore → nanoGPT |
| ⭐ [Fast.ai Practical Deep Learning](https://course.fast.ai/) | fast.ai | Jeremy Howard | Top-down DL; production focus; best first DL course |
| ⭐ [CS229: Machine Learning](https://cs229.stanford.edu/) | Stanford | Andrew Ng | Mathematical foundations: supervised, unsupervised, RL; essential theory |
| [CS231n: CNNs for Visual Recognition](http://cs231n.stanford.edu/) | Stanford | Fei-Fei Li et al. | Deep DL intuition; backprop; convolutions; strong foundation builder |
| [CS224N: NLP with Deep Learning](https://web.stanford.edu/class/cs224n/) | Stanford | Christopher Manning | NLP fundamentals → Transformers; lectures + assignments are excellent |

### LLM-Specific

| Course | Provider | What You'll Learn |
|--------|---------|------------------|
| ⭐ [LLM Twin Course](https://github.com/decodingml/llm-twin-course) | Decoding ML | End-to-end LLM system: data → fine-tuning → RAG → deployment; full code |
| [Hugging Face NLP Course](https://huggingface.co/learn/nlp-course/en/chapter0/1) | Hugging Face | Transformers library; tokenizers; fine-tuning; pipelines |
| [LLM Bootcamp (Full Stack Deep Learning)](https://fullstackdeeplearning.com/llm-bootcamp/) | FSDL | Production LLM apps; evaluation; deployment; cost optimization |
| [DeepLearning.AI Short Courses](https://www.deeplearning.ai/short-courses/) | deeplearning.ai + partners | LangChain, RAG, fine-tuning, agents, evaluation (free; 1–2 hours each) |
| [Prompt Engineering for Developers](https://www.deeplearning.ai/short-courses/chatgpt-prompt-engineering-for-developers/) | deeplearning.ai + OpenAI | Andrew Ng + Isa Fulford; best free intro to PE |
| [Generative AI for Everyone](https://www.coursera.org/learn/generative-ai-for-everyone) | Coursera | Andrew Ng | Non-technical LLM overview; good for explaining AI to stakeholders |

### MLOps & Production

| Course | Provider | What You'll Learn |
|--------|---------|------------------|
| ⭐ [Made With ML](https://madewithml.com/) | Goku Mohandas | MLOps from code to production; data, train, serve, monitor; best free MLOps course |
| [Full Stack MLOps (Duke)](https://www.coursera.org/specializations/mlops-machine-learning-duke) | Coursera | Rust + Python MLOps; CI/CD; model deployment |
| [ML Engineering for Production (MLOps)](https://www.coursera.org/specializations/machine-learning-engineering-for-production-mlops) | deeplearning.ai | Andrew Ng; model lifecycle; data pipeline; monitoring |

---

## 6. Frameworks & Libraries

### LLM Inference

| Tool | Stars | What It Does | When to Use |
|------|-------|-------------|------------|
| ⭐ [vLLM](https://github.com/vllm-project/vllm) | 25k+ | PagedAttention; continuous batching; OpenAI-compatible API | Production LLM serving; high throughput |
| [llama.cpp](https://github.com/ggerganov/llama.cpp) | 60k+ | CPU/GPU inference; GGUF format; Ollama's backend | Local/edge inference; resource-constrained |
| [TGI (Text Generation Inference)](https://github.com/huggingface/text-generation-inference) | 9k+ | HuggingFace's production server; tensor parallelism | HF ecosystem; enterprise |
| [Ollama](https://github.com/ollama/ollama) | 75k+ | Local LLM runner; GGUF models; REST API | Local dev; privacy-sensitive workloads |
| [TensorRT-LLM](https://github.com/NVIDIA/TensorRT-LLM) | 8k+ | NVIDIA-optimized inference; FP8; best NVIDIA GPU throughput | Maximum throughput on NVIDIA hardware |
| [SGLang](https://github.com/sgl-project/sglang) | 5k+ | Structured generation; RadixAttention; faster than vLLM for structured output | Constrained generation; JSON schemas |

### LLM Application Frameworks

| Tool | What It Does | When to Use |
|------|-------------|------------|
| ⭐ [LangChain](https://github.com/langchain-ai/langchain) | Chains, agents, RAG; ecosystem of integrations | Prototyping; broad integrations needed |
| ⭐ [LlamaIndex](https://github.com/run-llama/llama_index) | Data ingestion, indexing, RAG; superior data layer | RAG-heavy applications; structured data |
| [LangGraph](https://github.com/langchain-ai/langgraph) | Stateful agent graphs; cyclical workflows | Production agents; human-in-loop; complex workflows |
| [Haystack](https://github.com/deepset-ai/haystack) | Pipeline-based NLP + RAG; enterprise focus | Document Q&A; enterprise search; production RAG |
| [DSPy](https://github.com/stanfordnlp/dspy) | Declarative LLM programming; auto-optimizes prompts | When manual prompt tuning is a bottleneck |
| [Instructor](https://github.com/jxnl/instructor) | Structured outputs from LLMs using Pydantic | Whenever you need reliable JSON/structured responses |

### Vector Databases

| Tool | Type | Strengths | When to Use |
|------|------|-----------|-------------|
| ⭐ [Pinecone](https://www.pinecone.io/docs/) | Managed | Serverless; auto-scaling; simplest ops | Prod: managed cloud, fastest to launch |
| ⭐ [Weaviate](https://weaviate.io/developers/weaviate) | OSS + Managed | Hybrid search (BM25 + vector); GraphQL | Hybrid search; complex metadata filtering |
| [Milvus](https://milvus.io/docs) | OSS + Managed | Scalable; HNSW/IVF; Zilliz Cloud | Self-hosted at scale; > 100M vectors |
| [Qdrant](https://qdrant.tech/documentation/) | OSS + Managed | Rust; fast; rich payload filtering | Self-hosted; performance-sensitive |
| [ChromaDB](https://docs.trychroma.com/) | OSS | Embedded; no infra; Python-native | Local dev; small datasets; prototyping |
| [pgvector](https://github.com/pgvector/pgvector) | PostgreSQL ext | SQL + vector; ACID | < 10M vectors; already on Postgres; avoid extra infra |

### ML Training & Experiment Tracking

| Tool | What It Does | When to Use |
|------|-------------|------------|
| ⭐ [Weights & Biases (wandb)](https://wandb.ai/site) | Experiment tracking; model registry; sweeps | Industry standard for training runs |
| [MLflow](https://mlflow.org/) | Experiment tracking; model packaging; registry | Open-source; enterprise; multi-framework |
| [DVC](https://dvc.org/) | Data versioning + pipeline; Git for ML | Data pipeline reproducibility |
| [ZenML](https://zenml.io/) | ML pipeline framework; cloud-agnostic | Production ML pipelines; MLOps platform |
| [Prefect](https://www.prefect.io/) | Workflow orchestration; ML pipeline scheduling | General data + ML pipeline orchestration |

---

## 7. Standards, Guidelines & Safety

### Government & Regulatory

| Standard | Issuer | Scope | Why It Matters |
|---------|--------|-------|----------------|
| ⭐ [NIST AI Risk Management Framework (AI RMF 1.0)](https://airc.nist.gov/RMF_Overview) | NIST (US) | AI risk governance lifecycle | US federal AI governance baseline; referenced in enterprise AI contracts |
| [EU AI Act](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32024R1689) | EU | Regulatory classification of AI systems by risk | Affects any system serving EU users; high-risk AI requirements |
| [EU AI Act Summary (Ada Lovelace Institute)](https://www.adalovelaceinstitute.org/explainer/eu-ai-act/) | Ada Lovelace | Plain-language explainer | Best overview for engineers; risk tiers, prohibited uses |
| [Executive Order on Safe AI (US)](https://www.whitehouse.gov/briefing-room/presidential-actions/2023/10/30/executive-order-on-the-safe-secure-and-trustworthy-development-and-use-of-artificial-intelligence/) | White House | US government AI policy | Mandatory reporting for frontier models; safety standards |
| [UK AI Safety Institute](https://www.gov.uk/government/organisations/ai-safety-institute) | UK DSIT | Frontier model evaluation | UK safety testing regime; evaluation methodology |

### Industry & Lab Standards

| Standard / Guide | Issuer | What It Covers |
|----------------|--------|----------------|
| ⭐ [Responsible Scaling Policy](https://www.anthropic.com/news/anthropics-responsible-scaling-policy) | Anthropic | ASL-2/3/4 safety levels; model capabilities → safety requirements mapping |
| [Model Spec](https://www.anthropic.com/claude-s-model-spec) | Anthropic | Claude's values, behaviors, harm avoidance; authoritative alignment document |
| [OpenAI Preparedness Framework](https://openai.com/safety/preparedness) | OpenAI | Catastrophic risk categories; evaluation thresholds; safety levels |
| [Google DeepMind Safety Policy](https://deepmind.google/about/safety/) | Google DeepMind | Research-oriented safety commitments; evaluation methodology |
| [Partnership on AI Guidelines](https://partnershiponai.org/resources/) | Multi-org coalition | Responsible AI practices; cross-industry standards |
| [MLCOMMONS AI Safety](https://mlcommons.org/working-groups/ai-safety/ai-safety/) | MLCommons | Benchmark standards for AI safety evaluation |

### Engineering Best Practices

| Resource | Issuer | What It Covers |
|---------|--------|----------------|
| ⭐ [Anthropic's Responsible Development](https://www.anthropic.com/responsible-development) | Anthropic | Production AI safety practices; red-teaming; evaluations |
| [Google's People + AI Research (PAIR) Guidebook](https://pair.withgoogle.com/guidebook/) | Google | Human-centered AI design; UX for AI; bias evaluation |
| [Microsoft Responsible AI Principles](https://www.microsoft.com/en-us/ai/responsible-ai) | Microsoft | Fairness, reliability, privacy, inclusiveness, transparency, accountability |
| [IEEE Ethically Aligned Design](https://standards.ieee.org/content/dam/ieee-standards/standards/web/documents/other/ead_v2.pdf) | IEEE | Technical standards for ethical AI system design |
| [AI Incident Database](https://incidentdatabase.ai/) | AIID | Catalog of real-world AI failures and harms; use for risk analysis |
| [OWASP Top 10 for LLMs](https://owasp.org/www-project-top-10-for-large-language-model-applications/) | OWASP | Prompt injection, insecure output handling, training data poisoning, etc. |

### Safety & Alignment Research

| Paper / Resource | Authors | Year | Why It Matters |
|-----------------|---------|------|----------------|
| ⭐ [Concrete Problems in AI Safety](https://arxiv.org/abs/1606.06565) | Amodei et al. (OpenAI) | 2016 | Foundational taxonomy of AI safety problems; still the best overview |
| [Measuring Massive Multitask Language Understanding (MMLU)](https://arxiv.org/abs/2009.03300) | Hendrycks et al. | 2020 | 57-task benchmark; standard for measuring model knowledge |
| [Constitutional AI](https://arxiv.org/abs/2212.08073) | Bai et al. (Anthropic) | 2022 | Scalable alignment via AI feedback; CAI method |
| [Sleeper Agents](https://arxiv.org/abs/2401.05566) | Hubinger et al. (Anthropic) | 2024 | Deceptive alignment; hidden backdoors persist through safety training |
| [Scaling Monosemanticity](https://transformer-circuits.pub/2024/scaling-monosemanticity/index.html) | Templeton et al. (Anthropic) | 2024 | Mechanistic interpretability at scale; features in Claude Sonnet |

---

## 8. Benchmarks & Evaluation

### Model Capability Benchmarks

| Benchmark | What It Measures | Key Numbers to Know |
|-----------|-----------------|-------------------|
| ⭐ [MMLU](https://huggingface.co/datasets/cais/mmlu) | 57 academic tasks; knowledge breadth | GPT-4: 86.4% / Claude 3.5: 88.7% / Llama 3 70B: 82% |
| ⭐ [HumanEval](https://github.com/openai/human-eval) | Python coding; function completion | GPT-4: 67% / Claude 3.5: 92% / Llama 3 70B: 81% |
| [MATH](https://github.com/hendrycks/math) | Competition math; AMC/AIME | Hard ceiling; tests true reasoning |
| [GSM8K](https://github.com/openai/grade-school-math) | Grade-school math word problems | CoT dramatically improves scores; standard reasoning benchmark |
| [BIG-Bench Hard (BBH)](https://github.com/suzgunmirac/BIG-Bench-Hard) | 23 hard BIG-Bench tasks | Tests LLM reasoning limits |
| [HELM (Holistic Evaluation of LMs)](https://crfm.stanford.edu/helm/latest/) | Multi-metric, multi-scenario | Stanford; most comprehensive benchmark suite |
| [Chatbot Arena (LMSYS)](https://chat.lmsys.org/) | Human preference via blind pairwise comparison | Elo-based; most trusted real-world ranking |
| [SWE-bench](https://www.swebench.com/) | Real GitHub issues → code fixes | Best coding agent benchmark; production-realistic |

### RAG & Retrieval Evaluation

| Benchmark / Tool | What It Measures |
|-----------------|-----------------|
| ⭐ [RAGAS](https://docs.ragas.io/) | RAG pipeline: faithfulness, relevancy, context recall |
| [BEIR](https://github.com/beir-cellar/beir) | 18 retrieval benchmarks; zero-shot generalization |
| [MTEB](https://huggingface.co/spaces/mteb/leaderboard) | 56 embedding tasks; best embedding model leaderboard |
| [TruLens](https://github.com/truera/trulens) | LLM app evaluation; RAG triads; feedback functions |

### Safety & Alignment Evaluation

| Benchmark | What It Measures |
|-----------|-----------------|
| [TruthfulQA](https://github.com/sylinrl/TruthfulQA) | Truthfulness vs. imitative falsehoods |
| [WinoBias](https://uclanlp.github.io/corefBias/overview) | Gender bias in coreference resolution |
| [BBQ](https://github.com/nyu-mll/BBQ) | Social bias across 9 categories (age, race, religion, etc.) |
| [HarmBench](https://www.harmbench.org/) | Standardized red-teaming / jailbreak evaluation |
| [AIR-Bench](https://huggingface.co/datasets/AIR-Bench/air-bench-2024) | Safety across 314 risk categories |

---

## 9. Model Cards, Transparency & Governance

| Resource | What It Is |
|---------|-----------|
| ⭐ [Model Cards (Mitchell et al.)](https://arxiv.org/abs/1810.03993) | Original model card paper; standard for model documentation |
| [Hugging Face Model Cards Guide](https://huggingface.co/docs/hub/en/model-cards) | How to write model cards; HF standard |
| [Claude Model Card](https://www.anthropic.com/claude-3-model-card) | Anthropic's official Claude 3 model card; evaluation methodology |
| [GPT-4 System Card](https://cdn.openai.com/papers/gpt-4-system-card.pdf) | OpenAI's safety evaluation; red-teaming methodology |
| [Llama 3 Model Card](https://github.com/meta-llama/llama3/blob/main/MODEL_CARD.md) | Meta's open model documentation; responsible use guidelines |
| [Datasheets for Datasets](https://arxiv.org/abs/1803.09010) | Gebru et al.; standard for documenting training data |
| [AI Factsheets (IBM)](https://aifs360.res.ibm.com/) | IBM's transparency artifact for AI systems |

---

## 10. Production & MLOps

### Serving & Infrastructure

| Resource | Type | Why It Matters |
|---------|------|----------------|
| ⭐ [Chip Huyen: Designing ML Systems](https://huyenchip.com/ml-systems-design/toc.html) | 🎓 Book | Best ML systems design reference; data, training, serving, monitoring |
| [LLM Engineering (Maxime Labonne)](https://github.com/mlabonne/llm-course) | 🎓 | Road map: Transformer → fine-tuning → RLHF → quantization → deployment |
| [Modal Documentation](https://modal.com/docs/guide) | 🛠 | Serverless GPU compute for ML; excellent for LLM fine-tuning + serving |
| [Ray Serve Documentation](https://docs.ray.io/en/latest/serve/index.html) | 🛠 | Distributed model serving; Python-native; multi-model; dynamic batching |
| [BentoML](https://docs.bentoml.org/en/latest/) | 🛠 | ML serving framework; model packaging; Kubernetes integration |
| [Evidently AI](https://docs.evidentlyai.com/) | 🛠 | ML monitoring; data drift; model performance degradation detection |

### Feature Stores & Data Pipelines

| Resource | Type | Why It Matters |
|---------|------|----------------|
| [Feast: Open Source Feature Store](https://docs.feast.dev/) | 🛠 | Point-in-time correct feature retrieval; training-serving consistency |
| [Tecton Feature Store](https://www.tecton.ai/blog/) | 🛠 | Enterprise feature store; real-time features; DoorDash, Lyft use it |
| [Streaming Feature Engineering (Flink)](https://nightlies.apache.org/flink/flink-docs-master/docs/dev/datastream/overview/) | 🛠 | Real-time features for recommendations, fraud detection |
| [dbt (Data Build Tool)](https://docs.getdbt.com/) | 🛠 | SQL-first data transformation; used upstream of feature stores |

### Observability & Monitoring

| Resource | Type | Why It Matters |
|---------|------|----------------|
| ⭐ [LangSmith](https://docs.smith.langchain.com/) | 🛠 | LLM app observability; trace, evaluate, debug; best for LangChain apps |
| [Arize AI](https://docs.arize.com/arize/) | 🛠 | ML + LLM observability; embedding drift; prompt monitoring |
| [Phoenix (Arize)](https://docs.arize.com/phoenix/) | 🛠 | Open-source LLM + ML observability; runs locally |
| [Helicone](https://www.helicone.ai/docs) | 🛠 | LLM proxy with logging, cost tracking, caching |
| [OpenTelemetry for LLMs (OpenLLMetry)](https://github.com/traceloop/openllmetry) | 🛠 | OpenTelemetry-compatible LLM tracing; vendor-neutral |

---

## 11. Blogs, Newsletters & Communities

### Essential Blogs

| Blog | Author / Org | What It Covers | Update Frequency |
|------|-------------|----------------|-----------------|
| ⭐ [Anthropic Research Blog](https://www.anthropic.com/research) | Anthropic | Constitutional AI, interpretability, alignment, Claude | Monthly |
| ⭐ [Lilian Weng's Blog](https://lilianweng.github.io/) | Lilian Weng (OpenAI) | Deep ML/RL/LLM explainers; best technical writing in AI | Monthly |
| ⭐ [Chip Huyen's Blog](https://huyenchip.com/) | Chip Huyen | ML systems; LLM production; AI engineering | Monthly |
| [Sebastian Ruder's Blog](https://www.ruder.io/) | Sebastian Ruder (Google DeepMind) | NLP research; transfer learning; fine-tuning | Monthly |
| [The Batch (deeplearning.ai)](https://www.deeplearning.ai/the-batch/) | Andrew Ng | Weekly AI news + Andrew's letter; broad coverage | Weekly |
| [Google DeepMind Blog](https://deepmind.google/research/publications/) | Google DeepMind | Gemini, AlphaFold, research publications | Frequent |
| [Meta AI Blog](https://ai.meta.com/blog/) | Meta | LLaMA, Segment Anything, research | Frequent |
| [Hugging Face Blog](https://huggingface.co/blog) | Hugging Face | Open models, fine-tuning guides, evaluations | Weekly |
| [Eugene Yan's Blog](https://eugeneyan.com/) | Eugene Yan (Amazon) | Applied ML; RAG patterns; recommendations; system design | Monthly |
| [Simon Willison's Blog](https://simonwillison.net/) | Simon Willison | LLM tools; prompting; practical AI engineering | Daily |

### Newsletters

| Newsletter | Focus | Why Subscribe |
|-----------|-------|--------------|
| ⭐ [The Sequence](https://thesequence.substack.com/) | Research + engineering weekly | Best weekly AI research summary |
| [TLDR AI](https://tldr.tech/ai) | Daily AI news digest | 5-minute read; broad coverage |
| [Import AI (Jack Clark)](https://jack-clark.net/) | AI policy + research | Anthropic co-founder; policy + safety focus |
| [Last Week in AI](https://lastweekinai.substack.com/) | Weekly news digest | Curated research papers + industry news |
| [Ahead of AI (Sebastian Raschka)](https://magazine.sebastianraschka.com/) | LLM research deep-dives | Detailed technical breakdowns |

### Communities & Forums

| Community | Platform | Best For |
|-----------|----------|---------|
| [AI Alignment Forum](https://www.alignmentforum.org/) | Forum | Safety + alignment research; MIRI, Anthropic, OpenAI researchers |
| [LessWrong](https://www.lesswrong.com/) | Forum | Rationality + AI safety; foundational safety thinking |
| [Hugging Face Discord](https://discord.com/invite/huggingface) | Discord | Open-source models; fine-tuning help; community |
| [LocalLLaMA (Reddit)](https://www.reddit.com/r/LocalLLaMA/) | Reddit | Local model inference; quantization; Ollama; fine-tuning |
| [MLOps Community](https://mlops.community/) | Slack | Production ML; feature stores; serving; monitoring |
| [LAION Discord](https://discord.com/invite/laion) | Discord | Open datasets; diffusion models; open-source AI |

---

## 12. Conferences & Venues

### Top Research Venues

| Conference | Focus | Acceptance Rate | Notable For |
|-----------|-------|----------------|------------|
| ⭐ [NeurIPS](https://nips.cc/) | Broad ML + AI | ~25% | Largest ML conference; all major papers |
| ⭐ [ICML](https://icml.cc/) | ML theory + applications | ~28% | Strong theory; optimization; generalization |
| ⭐ [ICLR](https://iclr.cc/) | Representation learning | ~32% | Open review; LLM papers dominate |
| [ACL / EMNLP / NAACL](https://aclanthology.org/) | NLP | ~25% | Primary NLP venues; transformers, fine-tuning |
| [CVPR / ICCV / ECCV](https://www.computer.org/publications/tech-news/research/top-10-computer-vision-conferences) | Computer Vision | ~25% | Diffusion, multimodal, vision-language |
| [MLSys](https://mlsys.org/) | ML Systems | ~20% | vLLM, FlashAttention, and other systems papers |
| [USENIX OSDI / ATC](https://www.usenix.org/conferences) | Systems + ML infra | ~15% | PagedAttention (vLLM), Orca, serving systems |

### Paper Discovery

| Resource | What It Does |
|---------|-------------|
| ⭐ [Papers with Code](https://paperswithcode.com/) | Papers + implementations + SOTA tables; best for finding current SOTA |
| [Semantic Scholar](https://www.semanticscholar.org/) | Citation graph; "Papers that cite this" + AI-powered summaries |
| [ArXiv Sanity Preserver](http://www.arxiv-sanity.com/) | Karpathy's arxiv filter + recommendation |
| [HuggingFace Papers](https://huggingface.co/papers) | Daily curated AI papers with community discussion |
| [AI2 Semantic Scholar Feed](https://api.semanticscholar.org/graph/v1/) | Programmatic paper discovery + citation data |

---

## 13. Interactive Playgrounds & Tools

### Model Access & Experimentation

| Tool | What It Does | Best For |
|------|-------------|---------|
| ⭐ [Claude.ai](https://claude.ai) | Anthropic's Claude interface | Best for long-context, code, analysis |
| ⭐ [OpenAI Playground](https://platform.openai.com/playground) | GPT-4/o model API interface | API parameter experimentation |
| [Google AI Studio](https://aistudio.google.com/) | Gemini models + prompt design | Multimodal; Gemini context window (1M) |
| [Hugging Face Spaces](https://huggingface.co/spaces) | Community-built ML demos | Find and test open models instantly |
| [Perplexity Labs](https://labs.perplexity.ai/) | Free frontier model access (Llama 3, Mistral) | Testing open models without setup |
| [Groq](https://console.groq.com/) | Ultra-fast LLM inference (LPU hardware) | Lowest latency testing; Llama 3 at 800 tok/s |
| [Together AI](https://api.together.xyz/) | Open model API | Open-source model API access; fine-tuning |

### Code & Development

| Tool | What It Does |
|------|-------------|
| ⭐ [LangChain Playground / LangSmith](https://smith.langchain.com/) | Chain visualization; trace debugging |
| [Jupyter Notebooks (Kaggle)](https://www.kaggle.com/code) | Free GPU notebooks; public kernels for reference |
| [Google Colab](https://colab.research.google.com/) | Free T4 GPU; best for quick experiments |
| [Lightning AI Studios](https://lightning.ai/studios) | Cloud IDE with GPU; PyTorch Lightning team |
| [Replicate](https://replicate.com/) | Run models via API; no infrastructure needed |

### Visualization & Understanding

| Tool | What It Does |
|------|-------------|
| [BertViz](https://github.com/jessevig/bertviz) | Visualize transformer attention heads |
| [TransformerLens](https://github.com/neelnanda-io/TransformerLens) | Mechanistic interpretability toolkit (Anthropic / EleutherAI) |
| [Neuronpedia](https://www.neuronpedia.org/) | SAE feature visualization; what neurons mean |
| [Tokenizer Visualizer](https://tiktokenizer.vercel.app/) | See how text is tokenized (tiktoken / cl100k) |
| [LLM Visualization (3Blue1Brown)](https://bbycroft.net/llm) | Interactive 3D transformer visualization |

---

## 14. Interview-Specific Resources

### AI System Design Interview Prep

| Resource | Type | What It Covers |
|---------|------|----------------|
| ⭐ [Designing ML Systems (Chip Huyen)](https://www.oreilly.com/library/view/designing-machine-learning/9781098107956/) | 📚 Book | ML system design interview standard; data, training, deployment, monitoring |
| [Machine Learning Systems Design (CS329S)](https://stanford-cs329s.github.io/) | 🎓 Stanford | Course on production ML systems; case studies |
| [ML System Design Template (Eugeneyan)](https://eugeneyan.com/writing/ml-design/) | 🎓 | Step-by-step template: requirements → data → modeling → serving → monitoring |
| [Grokking ML Interview (Educative)](https://www.educative.io/courses/grokking-the-machine-learning-interview) | 🎓 | Common ML interview problems with solutions |
| [ML Design Primer](https://github.com/donnemartin/system-design-primer) | 🎓 | General systems design; adapt for ML context |

### LLM-Specific Interview Topics

| Topic | Best Resource | Key Concept |
|-------|-------------|-------------|
| Transformer architecture | [Karpathy's nanoGPT video](https://www.youtube.com/watch?v=kCc8FmEb1nY) | Attention, FFN, positional encoding |
| Scaling laws | [Chinchilla paper](https://arxiv.org/abs/2203.15556) | Compute-optimal training |
| Fine-tuning | [LoRA paper](https://arxiv.org/abs/2106.09685) + [QLoRA](https://arxiv.org/abs/2305.14314) | Parameter efficiency |
| Inference optimization | [vLLM paper](https://arxiv.org/abs/2309.06180) | PagedAttention, continuous batching |
| RAG design | [RAG survey](https://arxiv.org/abs/2312.10997) | Chunking, retrieval, evaluation |
| Agent design | [ReAct paper](https://arxiv.org/abs/2210.03629) + [Anthropic agent guide](https://www.anthropic.com/research/building-effective-agents) | ReAct loop, multi-agent |
| RLHF/alignment | [InstructGPT](https://arxiv.org/abs/2203.02155) + [DPO](https://arxiv.org/abs/2305.18290) | SFT → RM → PPO vs direct preference |
| Evaluation | [HELM](https://crfm.stanford.edu/helm/latest/) + [Chatbot Arena](https://chat.lmsys.org/) | Benchmark choice rationale |
| AI safety | [Concrete Problems](https://arxiv.org/abs/1606.06565) + [NIST RMF](https://airc.nist.gov/RMF_Overview) | Safety taxonomy, governance |

### Mock Interview Resources

| Resource | Type | What It Covers |
|---------|------|----------------|
| [ML Engineer Interview Guide (Interviewquery)](https://www.interviewquery.com/p/machine-learning-engineer-interview) | 🎓 | ML system design + coding + behavioral |
| [Data Science Interview Handbook](https://github.com/khangich/machine-learning-interview) | 🎓 | Comprehensive ML interview compendium |
| [AI Research Interview (Cohere)](https://cohere.com/blog/ml-interviews) | 🎓 | Research-track ML interview guidance |

---

## Quick-Access Index: By Role / Use Case

### "I'm designing a RAG system" →
Core: [RAG paper](https://arxiv.org/abs/2005.11401) · [RAG survey](https://arxiv.org/abs/2312.10997) · [Anthropic contextual retrieval](https://www.anthropic.com/research/contextual-retrieval) · [LlamaIndex docs](https://docs.llamaindex.ai/) · [RAGAS evaluation](https://docs.ragas.io/) · [MTEB leaderboard](https://huggingface.co/spaces/mteb/leaderboard)

### "I'm designing a production LLM serving system" →
Core: [vLLM paper](https://arxiv.org/abs/2309.06180) · [PagedAttention](https://arxiv.org/abs/2309.06180) · [Continuous batching (Orca)](https://www.usenix.org/conference/osdi22/presentation/yu) · [TGI docs](https://github.com/huggingface/text-generation-inference) · [Ray Serve](https://docs.ray.io/en/latest/serve/index.html) · [LangSmith monitoring](https://docs.smith.langchain.com/)

### "I'm designing a multi-agent system" →
Core: [ReAct](https://arxiv.org/abs/2210.03629) · [Anthropic agent guide](https://www.anthropic.com/research/building-effective-agents) · [LangGraph docs](https://langchain-ai.github.io/langgraph/) · [MCP protocol](https://modelcontextprotocol.io/) · [Multi-agent survey](https://arxiv.org/abs/2402.01680)

### "I need to fine-tune a model" →
Core: [LoRA](https://arxiv.org/abs/2106.09685) · [QLoRA](https://arxiv.org/abs/2305.14314) · [LLaMA-Factory](https://github.com/hiyouga/LLaMA-Factory) · [Unsloth](https://github.com/unslothai/unsloth) · [Karpathy nanoGPT tutorial](https://www.youtube.com/watch?v=kCc8FmEb1nY)

### "I'm preparing for AI safety / governance questions" →
Core: [NIST AI RMF](https://airc.nist.gov/RMF_Overview) · [Anthropic RSP](https://www.anthropic.com/news/anthropics-responsible-scaling-policy) · [OWASP Top 10 LLM](https://owasp.org/www-project-top-10-for-large-language-model-applications/) · [Concrete Problems in AI Safety](https://arxiv.org/abs/1606.06565) · [EU AI Act explainer](https://www.adalovelaceinstitute.org/explainer/eu-ai-act/)

### "I want to learn transformers from scratch" →
Core: [Karpathy Zero to Hero](https://karpathy.ai/zero-to-hero.html) · [Attention Is All You Need](https://arxiv.org/abs/1706.03762) · [CS224N Stanford](https://web.stanford.edu/class/cs224n/) · [Illustrated Transformer (Jay Alammar)](https://jalammar.github.io/illustrated-transformer/) · [Fast.ai Part 2](https://course.fast.ai/Lessons/part2.html)
