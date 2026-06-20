# Core Prompting Techniques

**Category:** Prompt Engineering · LLM Systems · Applied AI  
**References:** Wei et al. 2022 (CoT), Kojima et al. 2022 (zero-shot CoT), Wang et al. 2023 (Self-Consistency), Brown et al. 2020 (GPT-3 few-shot), Phoenix & Taylor O'Reilly 2024

> "Prompting is not a hack around a lack of fine-tuning — it is the API for instructing a reasoning engine. The quality of the instruction determines the quality of the reasoning."

---

## Why Prompt Quality Is a Principal Engineer Problem

Prompting seems like a frontend concern — a UX detail for the team writing user-facing copy. This is wrong. At production scale, a 10% improvement in prompt reliability translates to a 10% reduction in fallback rate, reprocessing cost, and latency from retries. A prompt that generates invalid JSON 2% of the time causes 2% of all requests to fail or retry — at 1M requests/day, that is 20,000 failures.

The principal engineer designing an LLM application must own prompting decisions as first-class architecture decisions:
- Which technique (CoT vs. self-consistency vs. ToT) is appropriate for this task's accuracy/latency/cost budget?
- How does the prompt compose with the retrieval layer (RAG), tool use, and output parsing?
- How is the prompt versioned, tested, and deployed?

These are not implementation details. They are architectural choices that determine whether the system meets its SLOs.

---

## Technique 1: Zero-Shot Prompting

**What it is:** Prompt the model with role + task + format. No examples. Rely on the model's pre-training knowledge.

**Structure:**
```
[Role]: You are an expert [domain] analyst.
[Task]: [Specific instruction with constraints]
[Format]: Respond in [format]. [Length/structure constraints].
```

**Concrete example:**
```python
prompt = """You are a senior financial analyst.

Extract the following fields from the earnings call transcript below:
- Revenue (quarterly, in USD millions)
- YoY revenue growth (%)
- EBITDA margin (%)
- Forward guidance (one sentence)

Respond as valid JSON with keys: revenue_m, yoy_growth_pct, ebitda_margin_pct, guidance.
If a field is not mentioned, use null.

<transcript>
{transcript_text}
</transcript>"""
```

**When zero-shot works:**
- The task is well-defined and the model has seen similar tasks in pre-training
- Output format is simple and structured (JSON, list, boolean)
- Low error tolerance is acceptable — no need for maximally reliable output

**When zero-shot fails:**
- Multi-step reasoning where each step must be correct to get a valid final answer (math, logic)
- Tasks with subtle edge cases that examples would clarify
- Novel task types the model hasn't seen

**FAANG signal:** Zero-shot is the baseline. In an interview, proposing zero-shot without discussing when it's insufficient signals shallow thinking about production reliability.

---

## Technique 2: Few-Shot / In-Context Learning

**What it is:** Include 3–8 (input, output) examples in the prompt before the actual input. The model infers the task structure from examples rather than needing explicit instruction.

Brown et al. 2020 (GPT-3 paper) established that few-shot examples dramatically improve performance on tasks where zero-shot fails. The model learns the pattern — format, style, edge case handling — from demonstration.

**Example selection matters more than example count:**

| Selection strategy | Accuracy | When to use |
|-------------------|----------|------------|
| Random from training set | Baseline | Default starting point |
| Semantically similar to query (retrieved) | +5–15% | When task distribution is wide |
| Diverse (cover different cases) | +3–8% | When task has subtypes the model must handle |
| Most difficult examples | +2–5% | When easy examples give false confidence |

**Implementation — semantic retrieval of few-shot examples:**
```python
from anthropic import Anthropic
import numpy as np

client = Anthropic()

def get_few_shot_examples(query: str, example_bank: list[dict], k: int = 5) -> list[dict]:
    """Retrieve the K most semantically similar examples to the query."""
    query_embedding = embed(query)  # your embedding function
    similarities = [
        cosine_similarity(query_embedding, embed(ex["input"]))
        for ex in example_bank
    ]
    top_k_indices = np.argsort(similarities)[-k:][::-1]
    return [example_bank[i] for i in top_k_indices]

def build_few_shot_prompt(query: str, examples: list[dict]) -> str:
    """Build a prompt with retrieved few-shot examples."""
    example_text = "\n\n".join([
        f"<example>\n<input>{ex['input']}</input>\n<output>{ex['output']}</output>\n</example>"
        for ex in examples
    ])
    return f"""<examples>
{example_text}
</examples>

Now process this input:
<input>
{query}
</input>"""
```

**Label balance:** For classification tasks, ensure your examples are balanced across labels. If 5 of 6 examples are "positive", the model will bias toward "positive" regardless of the input. This is one of the most common production bugs in few-shot prompting.

**Format consistency:** Every example must use exactly the same output format. If one example outputs `{"label": "positive"}` and another outputs `label: positive`, the model will produce inconsistent output.

**Research numbers (Brown et al. 2020, GPT-3 on SuperGLUE):**

| Examples (K) | Accuracy |
|-------------|----------|
| 0 (zero-shot) | 71.8% |
| 1 | 76.4% |
| 4 | 80.2% |
| 8 | 82.1% |
| 16 | 82.4% |

Returns diminish past K=8 for most tasks. Optimal K for most production prompts is 3–8.

**FAANG signal:** If asked "how do you improve a prompt that isn't accurate enough?" — retrieved few-shot examples (not adding more examples randomly) is the production-grade answer.

---

## Technique 3: Chain-of-Thought (CoT) Prompting

**What it is:** Instruct or demonstrate the model to produce a step-by-step reasoning trace before giving the final answer. The reasoning steps are intermediate context that guides the model to the correct conclusion.

Wei et al. 2022 established that CoT dramatically improves performance on multi-step reasoning tasks — but only in models with ~100B+ parameters (the reasoning capability emerges at scale).

### Standard CoT (few-shot with reasoning examples)

```python
system_prompt = """Solve the following problem step by step. Show your reasoning before 
giving the final answer."""

# Example included in prompt:
example = """
Problem: A store sells apples at $0.50 each. If I buy 3 dozen apples and get a 20% 
discount, how much do I pay?

Reasoning:
1. 3 dozen = 3 × 12 = 36 apples
2. Full price: 36 × $0.50 = $18.00
3. 20% discount: $18.00 × 0.20 = $3.60
4. Final price: $18.00 - $3.60 = $14.40

Answer: $14.40
"""
```

### Zero-Shot CoT ("Let's think step by step")

Kojima et al. 2022 found that appending "Let's think step by step" to a zero-shot prompt elicits reasoning without providing examples. The phrase acts as a trigger for chain-of-thought mode.

```python
prompt = f"""Solve this problem: {problem}

Let's think step by step."""
```

Performance on MultiArith (arithmetic reasoning):
- Zero-shot: 17.7%
- Zero-shot CoT ("Let's think step by step"): 78.7%
- Few-shot CoT: 88.6%

### When CoT Helps vs. Doesn't

| Task type | CoT helps? | Why |
|-----------|-----------|-----|
| Arithmetic, algebra | ✅ +40–60% | Each step gates the next; errors compound without reasoning |
| Multi-hop QA (HotpotQA) | ✅ +20–35% | Requires combining information from multiple sources |
| Symbolic reasoning (logic puzzles) | ✅ +30–50% | Explicit state tracking in reasoning steps |
| Common sense reasoning | ✅ +10–20% | Externalizes implicit reasoning |
| Simple classification | ❌ adds tokens, marginal gain | Model already confident; CoT just adds cost |
| Simple extraction (date, name) | ❌ | No reasoning steps required |
| Creative writing | ❌ | Kills fluency; planning and execution should be separate steps |

**Latency + cost trade-off:**

| Configuration | Tokens (input+output) | Cost (Sonnet 4.6) | Latency |
|--------------|----------------------|--------------------|---------|
| Zero-shot | 150 + 20 = 170 | ~$0.0009 | ~0.5s |
| Zero-shot CoT | 160 + 200 = 360 | ~$0.002 | ~1.2s |
| Few-shot CoT | 600 + 250 = 850 | ~$0.004 | ~2.5s |

CoT increases token cost 2–5× and latency 2–3×. Worth it for reasoning tasks; not worth it for simple tasks.

**FAANG signal:** "When would you NOT use chain-of-thought?" — for simple classification, extraction, or creative tasks where the reasoning overhead is wasted. Interviewers probe whether you apply CoT indiscriminately.

---

## Technique 4: Self-Consistency

**What it is:** Sample the model K times with temperature > 0, producing K independent reasoning chains and K final answers. Take the majority vote as the final output.

Wang et al. 2023: this is more reliable than greedy decoding (temperature=0) because different valid reasoning paths may reach the same correct answer, while incorrect paths tend to diverge.

**Results (Wang et al. 2023 on GSM8K, grade-school math):**

| Approach | Accuracy |
|----------|---------|
| CoT (greedy, T=0) | 56.5% |
| Self-consistency K=5 | 67.9% |
| Self-consistency K=10 | 72.1% |
| Self-consistency K=40 | 74.4% |

**Implementation:**
```python
import asyncio
from collections import Counter

async def self_consistent_answer(
    prompt: str,
    k: int = 8,
    temperature: float = 0.7
) -> tuple[str, float]:
    """
    Sample K completions and return majority-vote answer + confidence.
    """
    tasks = [
        client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=1024,
            temperature=temperature,
            messages=[{"role": "user", "content": prompt}]
        )
        for _ in range(k)
    ]
    
    responses = await asyncio.gather(*tasks)
    
    # Extract final answers (assumes answer is on last line or after "Answer:")
    answers = [extract_final_answer(r.content[0].text) for r in responses]
    
    # Majority vote
    vote_counts = Counter(answers)
    majority_answer, majority_count = vote_counts.most_common(1)[0]
    confidence = majority_count / k
    
    return majority_answer, confidence

def extract_final_answer(text: str) -> str:
    """Extract the final answer from a CoT response."""
    lines = text.strip().split('\n')
    for line in reversed(lines):
        if line.lower().startswith('answer:') or line.lower().startswith('final answer:'):
            return line.split(':', 1)[1].strip()
    return lines[-1].strip()  # fallback: last line
```

**Cost model:** Self-consistency K=8 costs 8× more than a single call. With Claude Sonnet at ~$0.004/call with CoT, K=8 costs ~$0.032/call. At 100K calls/day: ~$3,200/day just for self-consistency.

**When worth it:**
- Accuracy requirement > 95% on a reasoning task
- Cost of a wrong answer (in downstream errors, user trust, legal liability) exceeds the API cost
- Not on the hot path — batch processing, async quality checks

**FAANG signal:** "How do you increase reliability of an LLM on a math reasoning task?" → Self-consistency. Then: "What's the cost?" → K× API calls. Then: "How do you decide on K?" → Accuracy curve flattens after K=10–15; pick K where marginal gain < 0.5%.

---

## Technique 5: Least-to-Most Prompting

**What it is:** Decompose a complex problem into subproblems from simplest to hardest, solve each sequentially, and feed each answer into the next step. Contrast with CoT: CoT solves in one pass; Least-to-Most explicitly stages the decomposition.

**Structure:**
```
Step 1 (decompose): "List the subproblems needed to solve: {problem}"
Step 2 (solve each): "Given that {subproblem 1 answer}, solve {subproblem 2}"
Step 3 (compose): "Given {all subanswers}, give the final answer to {original problem}"
```

**Best for:**
- Multi-hop reasoning where intermediate results are dependencies
- Compositional tasks (e.g., "what is X of Y where Y is defined as...?")
- When CoT conflates steps that should be separate

**When NOT to use:** When the problem is already straightforward or when CoT works — least-to-most adds multi-turn overhead and context accumulation.

---

## Technique 6: Role / Persona Prompting

**What it is:** "You are a [expert role]" framing at the start of the system or user prompt. Activates the model's representation of that expert's communication style and knowledge emphasis.

**Effectiveness:** Empirical evidence is mixed. Role prompting reliably improves **style and tone** (expert sounds more authoritative, concise, domain-specific). Impact on **factual accuracy** is minor and sometimes negative (model may confabulate expertise it doesn't have).

**When role prompting works well:**
- Improving output style (code review tone, medical report formatting, legal language)
- Setting the level of assumed reader expertise ("explain to a senior engineer" vs. "explain to a 5-year-old")
- Establishing interaction norms ("ask clarifying questions before answering")

**When role prompting backfires:**
- "You are a world expert in X" → model may confidently hallucinate rare details it doesn't know
- Very specific expert roles → model may pattern-match to stereotypes rather than actual expertise

**Production pattern:** Combine role with explicit task definition. Role sets the style; task definition sets what to do.

```python
system_prompt = """You are a senior software architect specialising in distributed systems.
When reviewing architecture proposals:
- Identify single points of failure
- Check for scalability bottlenecks at 10× current load
- Assess data consistency implications
- Be direct and specific — no vague feedback

If you are uncertain about a claim, say so explicitly rather than stating it as fact."""
```

---

## Technique 7: Format Constraints

**What it is:** Explicitly instruct the model to produce output in a specific format (JSON, XML, table, numbered list). The most underrated technique for production reliability.

**Why it matters:** Unstructured LLM output requires fragile regex parsing in application code. Structured output (JSON with a defined schema, XML with defined tags) enables programmatic parsing with validation.

**JSON output:**
```python
# With schema definition (most reliable)
prompt = """Extract the following fields from the job posting and return valid JSON.

Schema:
{
  "job_title": "string",
  "company": "string", 
  "location": "string (city, state) or 'Remote'",
  "salary_min": "integer or null (USD/year)",
  "salary_max": "integer or null (USD/year)",
  "required_years_experience": "integer or null",
  "tech_stack": ["list of strings"]
}

Return ONLY the JSON object. No preamble, no explanation.

Job posting:
{posting_text}"""
```

**Reliability improvement from format constraints:**

| Format instruction | JSON parse success rate |
|-------------------|------------------------|
| None ("extract fields") | ~60% |
| "Respond as JSON" | ~85% |
| JSON with schema + "return ONLY JSON" | ~97% |
| JSON mode (API parameter) + schema | ~99.5% |

**FAANG signal:** "How do you ensure reliable structured output from an LLM?" → Format instruction + schema + validation + retry loop. In Claude: use `tool_use` with a defined input schema — the model is required to call the tool with valid parameters, which acts as enforced structured output.

---

## Master Comparison Table

| Technique | Task fit | Accuracy gain | Token cost | Latency | When to use in production |
|-----------|---------|--------------|-----------|---------|--------------------------|
| **Zero-shot** | Extraction, classification, simple generation | Baseline | 1× | 1× | Default starting point |
| **Few-shot** | Any task with diverse patterns | +5–20% | 2–5× | 1.5–2× | When zero-shot misses edge cases |
| **CoT** | Reasoning, math, planning | +20–50% on reasoning | 2–4× | 2–3× | Multi-step reasoning tasks |
| **Zero-shot CoT** | Reasoning, quick improvement | +30–40% vs. zero-shot | 1.5× | 1.5× | When few-shot examples unavailable |
| **Self-consistency** | Math, logic, high-stakes answers | +10–20% over CoT | K× | K× | Async/batch, accuracy > cost |
| **Least-to-most** | Compositional, multi-hop | +15–30% on compositional | 3–6× (multi-turn) | 3–5× | When CoT conflates steps |
| **Role prompting** | Style, tone, expert framing | Small (+2–5%) | 0 | 0 | Always (no cost) |
| **Format constraints** | Structured output | +20–40% parse success | 0 | 0 | Always for structured output |

---

## Quick-Reference: Technique Selection for Common Tasks

```
Is the output structured (JSON, XML, table)?
  └──► Always add format constraint + schema. Add "return ONLY JSON" guard.

Does the task require multi-step reasoning (math, logic, planning)?
  └──► Use CoT. If accuracy is critical, add self-consistency (K=5–8).

Is the task novel or the model making errors on edge cases?
  └──► Add few-shot examples. Use semantic retrieval to find relevant examples.

Is the task compositional (A depends on B depends on C)?
  └──► Use least-to-most prompting (decompose then solve sequentially).

Is the task very hard with low P(correct) even with CoT?
  └──► Try Tree of Thoughts (see 03-advanced-agentic-patterns.md). Expect 10–100× cost.

Is the task simple (classify sentiment, extract a name)?
  └──► Zero-shot + format constraint. Don't add CoT — wasted tokens.
```

---

## Common Interview Questions

**"How do you improve prompt reliability in production?"**

> "Start with the simplest thing that might work: zero-shot with a clear format constraint and schema. Measure the failure rate. If failures are due to edge cases the model hasn't seen — add few-shot examples, selected semantically from a curated bank rather than randomly. If failures are due to multi-step reasoning errors — add CoT. If the task has high stakes and accuracy requirements above 95% — add self-consistency with K=5–8. The key discipline is to not add complexity before measuring whether it's needed. CoT adds 2–5× token cost; self-consistency adds K× cost. Those costs are real at production scale."

**"What's the difference between CoT and self-consistency?"**

> "Chain-of-thought is a prompting technique that produces a single reasoning trace and answer — it improves accuracy by forcing explicit reasoning steps. Self-consistency is a decoding strategy: you sample the model K times with temperature > 0, each time getting a different reasoning path, and take the majority vote over final answers. The insight is that different valid reasoning paths often converge on the same correct answer, while incorrect paths are more scattered. Wang et al. 2023 showed +17.9% on grade-school math vs. greedy CoT at K=8. The trade-off is K× the API cost — justified for high-stakes batch tasks, not for real-time interactive applications."
