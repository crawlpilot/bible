# Fine-Tuning Base Models

**Running example throughout this file**: fine-tuning Mistral-7B-Instruct to extract structured product data from raw HTML — price, title, availability, and currency — returning a JSON object.

---

## Why Fine-Tune?

Prompting asks the model to generalize from its pre-training. Fine-tuning teaches it a specific behavior pattern. The signal is crisp: loss flows through examples that directly match your task.

When fine-tuning wins over prompting:
- Output format must be strictly consistent (JSON, YAML, SQL) at high volume
- Task requires domain-specific jargon the base model handles poorly
- Latency budget can't afford a 4K-token few-shot prompt every request
- You have 500+ labeled examples

When prompting still wins:
- < 200 examples (risk of overfitting + forgetting)
- Task changes frequently
- You need to ship in days, not weeks

---

## The HTML Parsing Task

**Input**:
```html
<div class="product-container" data-id="B08N5WRWNW">
  <h1 class="product-title">Sony WH-1000XM5 Headphones</h1>
  <span class="price" data-currency="USD">$279.99</span>
  <span class="availability in-stock">In Stock</span>
</div>
```

**Target output**:
```json
{"title": "Sony WH-1000XM5 Headphones", "price": 279.99, "currency": "USD", "in_stock": true}
```

This is a good fine-tuning candidate: the output schema is fixed, the input structure varies (different retailers use different class names), and few-shot prompting reaches ~85% accuracy while a fine-tuned model can hit ~97%.

---

## Data Preparation Pipeline

Quality >> Quantity. 1,000 clean examples beat 10,000 noisy ones.

```
Raw HTML pages
      │
      ▼
1. Scrape & deduplicate
      │  (remove near-duplicate pages, same product across retailers)
      ▼
2. Extract ground truth
      │  (use structured sources: Amazon Product API, schema.org markup as labels)
      ▼
3. Format as instruction pairs
      │
      ▼
4. Train/val/test split (80/10/10)
      │
      ▼
5. Tokenize + verify length distribution
```

**Instruction pair format** (chat template for Mistral):
```
<s>[INST] Extract product data from the following HTML as JSON with keys:
title, price, currency, in_stock.

HTML:
<div class="product-container">...</div>
[/INST]
{"title": "Sony WH-1000XM5 Headphones", "price": 279.99, "currency": "USD", "in_stock": true}
</s>
```

**Dataset sizing guide**:
| Task Complexity | Minimum Examples | Target Examples |
|----------------|-----------------|----------------|
| Format conversion (fixed schema) | 200–500 | 2,000–5,000 |
| Domain-specific extraction | 1,000–2,000 | 5,000–20,000 |
| New capability (reasoning, math) | 10,000+ | 50,000+ |
| Behavior change (tone, persona) | 500–1,000 | 5,000+ |

---

## Full Fine-Tune vs. Parameter-Efficient (PEFT)

| Approach | Updates | VRAM (7B) | Quality | Risk |
|----------|---------|-----------|---------|------|
| **Full fine-tune** | All 7B params | ~140 GB | Best | Catastrophic forgetting |
| **LoRA** | Rank decomposition of select layers | ~20 GB | 90–95% of full | Low |
| **QLoRA** | LoRA on 4-bit quantized base | ~6 GB | 85–92% of full | Low |
| **Prompt tuning** | Soft prompt tokens only | Smallest | Weakest | Minimal |

**QLoRA is the practical default** for individual researchers and small teams: a 7B model fine-tunes on a single A100 80GB in under 4 hours.

---

## LoRA Mechanics

LoRA (Hu et al., 2021) freezes pretrained weights W and adds a low-rank decomposition:

```
W' = W + ΔW = W + B·A

where:
  W ∈ R^(d×k)       (frozen, original weight)
  A ∈ R^(r×k)       (trainable, initialized random)
  B ∈ R^(d×r)       (trainable, initialized zero)
  r << d,k           (rank — typically 8, 16, or 64)

Parameter count reduction: (d×k) → r×(d+k)
For d=4096, k=4096, r=16: 16M → 131K params per matrix (99% reduction)
```

B is initialized to zero so ΔW starts at zero — training begins from the original model, not random noise.

**Which layers to target**:
```python
target_modules = ["q_proj", "k_proj", "v_proj", "o_proj",  # attention
                  "gate_proj", "up_proj", "down_proj"]       # FFN (optional)
```

Targeting attention projections only is fastest. Adding FFN layers slightly improves quality for complex tasks like our HTML extractor.

**LoRA hyperparameters**:
| Parameter | Value | Notes |
|-----------|-------|-------|
| `r` (rank) | 16 | Start here; double to 32 if quality insufficient |
| `lora_alpha` | 32 | Scaling factor = alpha/r; keep alpha = 2r |
| `lora_dropout` | 0.05 | Regularization |
| `target_modules` | q,k,v,o projections | Add FFN for harder tasks |

---

## Training Code: HTML Parser Fine-Tune

```python
from transformers import AutoModelForCausalLM, AutoTokenizer, TrainingArguments
from peft import LoraConfig, get_peft_model
from trl import SFTTrainer
from datasets import load_dataset

# 1. Load base model + tokenizer
model_id = "mistralai/Mistral-7B-Instruct-v0.2"
tokenizer = AutoTokenizer.from_pretrained(model_id)
tokenizer.pad_token = tokenizer.eos_token

# 2. QLoRA: load in 4-bit
from transformers import BitsAndBytesConfig
import torch

bnb_config = BitsAndBytesConfig(
    load_in_4bit=True,
    bnb_4bit_quant_type="nf4",       # NormalFloat4 — better than int4 for weights
    bnb_4bit_compute_dtype=torch.bfloat16,
    bnb_4bit_use_double_quant=True,  # nested quantization saves ~0.4 bits/param
)
model = AutoModelForCausalLM.from_pretrained(model_id, quantization_config=bnb_config)

# 3. LoRA config
lora_config = LoraConfig(
    r=16,
    lora_alpha=32,
    target_modules=["q_proj", "k_proj", "v_proj", "o_proj"],
    lora_dropout=0.05,
    bias="none",
    task_type="CAUSAL_LM",
)
model = get_peft_model(model, lora_config)
model.print_trainable_parameters()
# Output: trainable params: 20,971,520 || all params: 3,773,239,296 || trainable%: 0.56%

# 4. Dataset (instruction format)
dataset = load_dataset("json", data_files={"train": "html_extract_train.jsonl",
                                            "test": "html_extract_test.jsonl"})

def format_prompt(example):
    return f"<s>[INST] Extract product data as JSON.\n\nHTML:\n{example['html']}\n[/INST]\n{example['output']}</s>"

# 5. Training
training_args = TrainingArguments(
    output_dir="./html-extractor-mistral",
    num_train_epochs=3,
    per_device_train_batch_size=4,
    gradient_accumulation_steps=8,     # effective batch = 32
    learning_rate=2e-4,
    lr_scheduler_type="cosine",
    warmup_ratio=0.03,
    bf16=True,
    logging_steps=10,
    eval_strategy="steps",
    eval_steps=100,
    save_strategy="steps",
    save_steps=100,
    load_best_model_at_end=True,
)

trainer = SFTTrainer(
    model=model,
    args=training_args,
    train_dataset=dataset["train"],
    eval_dataset=dataset["test"],
    formatting_func=format_prompt,
    max_seq_length=2048,
)
trainer.train()

# 6. Save adapter only (not full 14GB model)
model.save_pretrained("./html-extractor-adapter")
```

---

## Evaluation

Never trust training loss alone. Evaluate on task metrics:

```python
# Exact-match JSON accuracy
import json

def evaluate_extraction(model, tokenizer, test_set):
    results = {"exact_match": 0, "field_accuracy": {}, "parse_error": 0}
    fields = ["title", "price", "currency", "in_stock"]
    field_hits = {f: 0 for f in fields}

    for example in test_set:
        prompt = format_prompt_inference(example["html"])
        output = generate(model, tokenizer, prompt)

        try:
            pred = json.loads(output)
            gt = json.loads(example["output"])

            if pred == gt:
                results["exact_match"] += 1

            for f in fields:
                if pred.get(f) == gt.get(f):
                    field_hits[f] += 1
        except json.JSONDecodeError:
            results["parse_error"] += 1

    n = len(test_set)
    results["exact_match"] /= n
    results["field_accuracy"] = {f: field_hits[f]/n for f in fields}
    results["parse_error"] /= n
    return results
```

**Baseline vs. fine-tuned results** (500-example HTML extraction test):

| Metric | Mistral-7B (0-shot) | Mistral-7B (8-shot prompt) | Fine-tuned (LoRA) |
|--------|--------------------|--------------------------|--------------------|
| Exact match | 48% | 82% | 97% |
| Price accuracy | 71% | 91% | 99% |
| Parse error rate | 23% | 8% | 0.4% |
| Avg latency (1 req) | 380ms | 1,100ms | 380ms |

The latency advantage of fine-tuning over few-shot is significant at scale — 1,100ms vs 380ms per request = 3× cheaper inference at the same model size.

---

## Anti-Patterns

**Catastrophic forgetting**: Fine-tuning on a narrow task can degrade general capabilities.
- Mitigation: Mix 5–10% general instruction data into your training set ("replay").

**Data leakage**: Test HTML pages from the same sites as training data will overestimate accuracy.
- Mitigation: Split by domain (retailer), not by page.

**Overfitting on small datasets**: Loss goes to 0 on training but test accuracy is poor.
- Mitigation: Reduce LoRA rank, increase dropout, add more diverse data.

**Training on the prompt**: If loss is computed on input tokens, the model learns to predict HTML — useless.
- Mitigation: Set `DataCollatorForCompletionOnlyLM` to mask input tokens from loss.

**Skipping output length analysis**: If some outputs are 50 tokens and others 500 tokens, your batch efficiency is terrible.
- Mitigation: Pack sequences or sort by length before batching.

---

## FAANG Interview Callout

> **"How would you build a fine-tuned model for structured data extraction at Amazon scale?"**
>
> "I'd start by establishing a prompt-only baseline to measure how much headroom exists — for extraction tasks the base model often reaches 80–85% accuracy with good few-shot examples. Fine-tuning is worth the investment when you need consistent JSON schemas at high volume or when the latency cost of 4K-token few-shot prompts is unacceptable. The implementation would use QLoRA on a 7B instruction-tuned base: it trains on a single A100 in a few hours and the adapter file is only ~100MB. The critical risk is data quality — I'd invest heavily in the labeling pipeline, use structured sources as ground truth rather than human annotation where possible, and evaluate on held-out domains (not just held-out pages) to avoid leakage. I'd monitor parse error rate in production as the primary health metric because that's the failure mode that hits downstream systems hardest."

---

## Related Files

- [01-transformer-architecture.md](01-transformer-architecture.md) — Architecture of the base model being fine-tuned
- [04-inference-patterns.md](04-inference-patterns.md) — Serving the fine-tuned model with vLLM
- [AI/ml-systems/ollama-local-models-finetuning.md](../ml-systems/ollama-local-models-finetuning.md) — Local dev workflow with Ollama
