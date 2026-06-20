# 05 — Practical: Web Automation Agent (Firecrawl-Style)

---

## Goal

Build a production-grade web research agent that, given a search query or URL, crawls, scrapes, and extracts structured data. This mirrors the core pipeline of tools like **Firecrawl**, **Apify**, and enterprise web connectors.

This file is a complete, runnable reference — every design decision is explained and tied back to the concepts in files 01–04.

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    WEB RESEARCH AGENT                           │
│                                                                 │
│  User Query: "Extract product listings from example.com"        │
│                        │                                        │
│                        ▼                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              ORCHESTRATOR AGENT                         │   │
│  │  Model: claude-sonnet-4-6                               │   │
│  │  Budget: 32K input + 4K output                          │   │
│  │  Role: Decomposes task, coordinates subagents           │   │
│  └──────────┬──────────────┬──────────────┬───────────────┘   │
│             │              │              │                     │
│             ▼              ▼              ▼                     │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐           │
│  │ SEARCH AGENT │ │ SCRAPE AGENT │ │EXTRACT AGENT │           │
│  │ (Haiku)      │ │ (Haiku)      │ │ (Sonnet)     │           │
│  │ web_search   │ │ fetch_page   │ │ extract_json │           │
│  └──────┬───────┘ └──────┬───────┘ └──────┬───────┘           │
│         │                │                │                    │
│         └────────────────┴────────────────┘                    │
│                          │                                     │
│                          ▼                                     │
│             ┌────────────────────────┐                         │
│             │    SENTINEL AGENT      │                         │
│             │    (Haiku)             │                         │
│             │    Validates output    │                         │
│             └────────────────────────┘                         │
└─────────────────────────────────────────────────────────────────┘
```

---

## How Firecrawl Works (Analogy Map)

Understanding a real production system grounds the design decisions:

| Firecrawl Component | Our Agent Equivalent | Notes |
|--------------------|---------------------|-------|
| Crawl graph (BFS/DFS URL discovery) | Orchestrator loop with `discover_links` tool | Firecrawl explores sitemaps + link following |
| Playwright headless browser | `fetch_page` tool with Playwright fallback | JS-rendered pages require real browser |
| HTML → Markdown conversion | `html_to_markdown()` in scrape agent | Reduces 500K HTML to 20K markdown |
| LLM extraction | Extract agent with structured schema | Most expensive step — minimize calls |
| Caching layer | In-session tool result cache | Firecrawl caches scraped pages for 24h |
| Rate limiting | Per-domain rate limiter in `fetch_page` | Polite crawling — avoid bans |
| Job queue | Async task queue (SQS/Celery) | Firecrawl runs as an async API |

---

## Tool Definitions (Full Schemas)

```python
import anthropic

TOOLS = [
    {
        "name": "web_search",
        "description": (
            "Search the web for URLs and snippets matching a query. "
            "Use to discover relevant pages before scraping. "
            "Returns a list of results with title, URL, and snippet."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Search query. Be specific. Max 200 chars."
                },
                "max_results": {
                    "type": "integer",
                    "description": "Number of results (1-10). Default 5.",
                    "default": 5
                }
            },
            "required": ["query"]
        }
    },
    {
        "name": "fetch_page",
        "description": (
            "Fetch a webpage and return its content as clean markdown. "
            "Automatically handles HTML-to-markdown conversion and removes boilerplate. "
            "For JavaScript-heavy pages, pass use_browser=true. "
            "Returns markdown content truncated to 8000 chars."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "url": {
                    "type": "string",
                    "description": "Full URL including https://"
                },
                "use_browser": {
                    "type": "boolean",
                    "description": "Use headless browser for JS-rendered pages. Slower (~5s) but handles SPAs.",
                    "default": False
                },
                "wait_for_selector": {
                    "type": "string",
                    "description": "CSS selector to wait for before capturing content (use_browser must be true).",
                    "default": None
                }
            },
            "required": ["url"]
        }
    },
    {
        "name": "extract_structured_data",
        "description": (
            "Given markdown content and a JSON schema, extract structured data. "
            "Use after fetch_page to extract specific fields. "
            "Returns a JSON object matching the provided schema."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "content": {
                    "type": "string",
                    "description": "Markdown content to extract from (max 8000 chars)"
                },
                "schema": {
                    "type": "object",
                    "description": "JSON Schema describing the data to extract"
                },
                "instruction": {
                    "type": "string",
                    "description": "Natural language hint for extraction. E.g., 'Extract all product listings with name and price'"
                }
            },
            "required": ["content", "schema", "instruction"]
        }
    },
    {
        "name": "discover_links",
        "description": (
            "Extract all links from a webpage that match a pattern. "
            "Use to discover pages to crawl from a listing page or sitemap."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "url": {"type": "string"},
                "pattern": {
                    "type": "string",
                    "description": "Substring or regex pattern the href must match. E.g., '/products/' or '^https://example.com/item/\\d+'"
                },
                "max_links": {
                    "type": "integer",
                    "description": "Max links to return (1-50). Default 20.",
                    "default": 20
                }
            },
            "required": ["url", "pattern"]
        }
    },
    {
        "name": "save_result",
        "description": "Save extracted data to the result store. Call once per page after extraction is complete.",
        "input_schema": {
            "type": "object",
            "properties": {
                "url": {"type": "string"},
                "data": {"type": "object", "description": "Extracted structured data"},
                "confidence": {
                    "type": "number",
                    "description": "Extraction confidence 0.0-1.0",
                    "minimum": 0.0,
                    "maximum": 1.0
                }
            },
            "required": ["url", "data", "confidence"]
        }
    }
]
```

---

## System Prompts

### Orchestrator Prompt

```python
ORCHESTRATOR_SYSTEM = """
You are a web research orchestrator. Your job is to:
1. Understand what data the user wants to extract from the web
2. Discover the right pages to scrape using web_search and discover_links
3. Coordinate scraping and extraction systematically
4. Save results for each page successfully processed

GUIDELINES:
- Start with web_search or discover_links to find target pages before scraping
- Use fetch_page for each target URL, then extract_structured_data immediately after
- Save each result with save_result before moving to the next URL
- If a page fails (403, timeout), skip it and continue — don't retry more than once
- Stop when you have extracted data from at least 5 pages OR exhausted all discovered URLs
- Be systematic: don't re-visit pages you've already processed

You have a budget of 20 iterations. Use them wisely.
"""
```

### Extractor Sub-Prompt (used for extract_structured_data internally)

```python
EXTRACTOR_SYSTEM = """
You are a precise data extractor. Given markdown content and a schema:
- Extract ONLY data explicitly present in the content
- Do not infer, guess, or fill in missing fields with assumptions
- Use null for fields not found in the content
- Return ONLY valid JSON matching the schema
- No explanation, no markdown code blocks, just the JSON object
"""
```

---

## Core Tool Implementations

```python
import httpx
import json
import re
import time
from typing import Any
from urllib.parse import urljoin
from html.parser import HTMLParser

# Simple HTML-to-markdown converter (production: use markdownify or html2text)
def html_to_markdown(html: str) -> str:
    # Remove scripts, styles, nav, footer
    html = re.sub(r'<script[^>]*>.*?</script>', '', html, flags=re.DOTALL)
    html = re.sub(r'<style[^>]*>.*?</style>', '', html, flags=re.DOTALL)
    html = re.sub(r'<nav[^>]*>.*?</nav>', '', html, flags=re.DOTALL)
    html = re.sub(r'<footer[^>]*>.*?</footer>', '', html, flags=re.DOTALL)
    # Convert common tags to markdown
    html = re.sub(r'<h[1-3][^>]*>(.*?)</h[1-3]>', r'## \1\n', html)
    html = re.sub(r'<p[^>]*>(.*?)</p>', r'\1\n\n', html, flags=re.DOTALL)
    html = re.sub(r'<a[^>]*href="([^"]*)"[^>]*>(.*?)</a>', r'[\2](\1)', html)
    html = re.sub(r'<[^>]+>', '', html)   # Strip remaining tags
    html = re.sub(r'\n{3,}', '\n\n', html)  # Normalize whitespace
    return html.strip()

def truncate_to_chars(text: str, max_chars: int = 8000) -> str:
    if len(text) <= max_chars:
        return text
    mid = max_chars // 2
    tail = max_chars // 4
    omitted = len(text) - mid - tail
    return f"{text[:mid]}\n\n[... {omitted} chars omitted ...]\n\n{text[-tail:]}"


# Tool implementations
def impl_web_search(query: str, max_results: int = 5) -> str:
    # Replace with Brave Search API, SerpAPI, or Tavily in production
    response = httpx.get(
        "https://api.search.brave.com/res/v1/web/search",
        params={"q": query, "count": max_results},
        headers={"Accept": "application/json", "X-Subscription-Token": BRAVE_API_KEY},
        timeout=10,
    )
    results = response.json().get("web", {}).get("results", [])
    output = []
    for r in results[:max_results]:
        output.append(f"Title: {r['title']}\nURL: {r['url']}\nSnippet: {r.get('description', '')}\n")
    return "\n---\n".join(output) if output else "No results found."


def impl_fetch_page(url: str, use_browser: bool = False, wait_for_selector: str = None) -> str:
    if use_browser:
        return _fetch_with_playwright(url, wait_for_selector)
    
    try:
        response = httpx.get(
            url,
            headers={"User-Agent": "Mozilla/5.0 (compatible; ResearchBot/1.0)"},
            follow_redirects=True,
            timeout=15,
        )
        if response.status_code == 403:
            return f"ERROR: 403 Forbidden — {url} blocks automated access. Try use_browser=true."
        if response.status_code != 200:
            return f"ERROR: HTTP {response.status_code} for {url}"
        
        markdown = html_to_markdown(response.text)
        return truncate_to_chars(markdown, max_chars=8000)
    
    except httpx.TimeoutException:
        return f"ERROR: Timeout fetching {url}"
    except Exception as e:
        return f"ERROR: {str(e)}"


def impl_extract_structured_data(content: str, schema: dict, instruction: str) -> str:
    client = anthropic.Anthropic()
    
    prompt = f"""
Extract data from the following content according to this instruction:
{instruction}

JSON Schema to follow:
{json.dumps(schema, indent=2)}

Content:
{truncate_to_chars(content, max_chars=6000)}

Return ONLY the JSON object. No markdown, no explanation.
"""
    response = client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=2000,
        system=EXTRACTOR_SYSTEM,
        messages=[{"role": "user", "content": prompt}],
        temperature=0,
    )
    
    raw = response.content[0].text.strip()
    # Validate it's parseable JSON
    try:
        json.loads(raw)
        return raw
    except json.JSONDecodeError:
        # Try to extract JSON from response
        match = re.search(r'\{.*\}', raw, re.DOTALL)
        if match:
            return match.group(0)
        return json.dumps({"error": "extraction_failed", "raw": raw[:500]})


def impl_discover_links(url: str, pattern: str, max_links: int = 20) -> str:
    result = impl_fetch_page(url)
    if result.startswith("ERROR"):
        return result
    
    # Extract URLs from markdown links and href attributes
    found = []
    for match in re.finditer(r'\[.*?\]\((https?://[^\)]+)\)', result):
        href = match.group(1)
        if re.search(pattern, href):
            found.append(href)
    
    unique = list(dict.fromkeys(found))[:max_links]  # Dedupe, preserve order
    return json.dumps(unique) if unique else "[]"


result_store = []
def impl_save_result(url: str, data: dict, confidence: float) -> str:
    result_store.append({"url": url, "data": data, "confidence": confidence})
    return f"Saved result for {url}. Total results: {len(result_store)}"


TOOL_DISPATCH = {
    "web_search": impl_web_search,
    "fetch_page": impl_fetch_page,
    "extract_structured_data": impl_extract_structured_data,
    "discover_links": impl_discover_links,
    "save_result": impl_save_result,
}
```

---

## The Orchestrator Loop

```python
import anthropic
import json
import time
from dataclasses import dataclass, field

client = anthropic.Anthropic()

@dataclass
class AgentRunStats:
    iterations: int = 0
    total_input_tokens: int = 0
    total_output_tokens: int = 0
    tool_calls: int = 0
    errors: int = 0
    start_time: float = field(default_factory=time.time)

    @property
    def duration_seconds(self) -> float:
        return time.time() - self.start_time

    @property
    def estimated_cost_usd(self) -> float:
        # claude-sonnet-4-6 pricing
        return (self.total_input_tokens * 3.0 / 1_000_000 +
                self.total_output_tokens * 15.0 / 1_000_000)


def run_web_agent(
    task: str,
    max_iterations: int = 20,
    token_budget: int = 80_000,
) -> tuple[list[dict], AgentRunStats]:
    """
    Run the web research orchestrator agent.
    Returns (results, stats).
    """
    messages = [{"role": "user", "content": task}]
    stats = AgentRunStats()
    tool_cache: dict[str, str] = {}   # In-session dedup cache

    for iteration in range(max_iterations):
        stats.iterations = iteration + 1

        # Token budget check — compress if needed
        estimated = estimate_tokens(messages)
        if estimated > token_budget * 0.8:
            messages = compress_with_haiku(messages, target_tokens=token_budget // 2)

        # Call the orchestrator model
        response = client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=4096,
            system=ORCHESTRATOR_SYSTEM,
            tools=TOOLS,
            messages=messages,
        )

        stats.total_input_tokens += response.usage.input_tokens
        stats.total_output_tokens += response.usage.output_tokens

        # Terminal condition
        if response.stop_reason == "end_turn":
            print(f"[Agent] Completed in {stats.iterations} iterations, "
                  f"${stats.estimated_cost_usd:.4f}, {stats.duration_seconds:.1f}s")
            return result_store.copy(), stats

        # Tool use
        if response.stop_reason == "tool_use":
            messages.append({"role": "assistant", "content": response.content})
            tool_results = []

            for block in response.content:
                if block.type != "tool_use":
                    continue

                stats.tool_calls += 1
                tool_name = block.name
                tool_input = block.input

                # Check in-session cache (skip repeat calls)
                cache_key = f"{tool_name}:{json.dumps(tool_input, sort_keys=True)}"
                if cache_key in tool_cache and tool_name in ("web_search", "fetch_page", "discover_links"):
                    result = f"[CACHED] {tool_cache[cache_key]}"
                else:
                    print(f"  [Tool] {tool_name}({json.dumps(tool_input)[:80]}...)")
                    try:
                        fn = TOOL_DISPATCH[tool_name]
                        result = fn(**tool_input)
                        tool_cache[cache_key] = result
                    except Exception as e:
                        stats.errors += 1
                        result = f"ERROR: Tool {tool_name} failed: {str(e)}"

                # Truncate result before injecting
                truncated = truncate_tool_result(result, max_chars=4000)

                tool_results.append({
                    "type": "tool_result",
                    "tool_use_id": block.id,
                    "content": truncated,
                })

            messages.append({"role": "user", "content": tool_results})

    raise AgentMaxIterationsError(
        f"Agent exceeded {max_iterations} iterations. "
        f"Stats: {stats}"
    )
```

---

## Token Management in Practice

### How We Truncate Scraped Content

Web pages are the biggest token hazard. A full HTML page is 50K–500K characters. After `html_to_markdown()` conversion, it's still 10K–50K. We cap at 8K chars in `fetch_page` and at 4K when injecting into tool results.

```
Raw HTML:    ~200K chars → 50K tokens  (would fill entire context!)
After markdown: ~20K chars → 5K tokens
After truncation: 8K chars → 2K tokens ← what gets injected into agent context
```

That 25× reduction is why **html_to_markdown + truncation** is not optional — it's the difference between agents that work and agents that explode.

### Context Growth Per Turn

```
Turn 1:  ~1K tokens (task + first tool call)
Turn 3:  ~5K tokens (3 fetch results accumulated)
Turn 7:  ~15K tokens (7 tool results + reasoning)
Turn 15: ~35K tokens — approaching compression threshold
```

At 80% of 80K budget (~64K), we trigger `compress_with_haiku` which summarizes all but the last 4 turns.

```python
def compress_with_haiku(messages: list[dict], target_tokens: int) -> list[dict]:
    if len(messages) <= 4:
        return messages
    
    to_compress = messages[:-4]
    recent = messages[-4:]
    
    formatted = format_messages_as_text(to_compress)
    
    summary_response = client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=800,
        messages=[{
            "role": "user",
            "content": (
                "Summarize this agent session history. Preserve all URLs visited, "
                "data extracted, errors encountered, and decisions made. Be concise.\n\n"
                f"{formatted}"
            )
        }]
    )
    
    summary = summary_response.content[0].text
    
    return [
        {"role": "user", "content": f"[SESSION SUMMARY]\n{summary}"},
        *recent
    ]
```

---

## Error Handling

### Rate Limits (429)

```python
def fetch_with_rate_limit(url: str) -> str:
    domain = urlparse(url).netloc
    
    # Per-domain rate limiter: 1 request/second
    rate_limiter.wait(domain, min_interval=1.0)
    
    try:
        return impl_fetch_page(url)
    except httpx.HTTPStatusError as e:
        if e.response.status_code == 429:
            retry_after = int(e.response.headers.get("Retry-After", 60))
            time.sleep(retry_after)
            return impl_fetch_page(url)   # One retry
        raise
```

### 403 Blocked / Bot Detection

```python
# In fetch_page: if HTTP fetch gets 403, try browser automatically
def impl_fetch_page(url: str, use_browser: bool = False) -> str:
    result = _fetch_http(url)
    if "ERROR: 403" in result and not use_browser:
        print(f"  [fetch_page] HTTP blocked, retrying with browser: {url}")
        return _fetch_with_playwright(url)
    return result
```

### JS-Rendered Pages (Playwright)

```python
def _fetch_with_playwright(url: str, wait_for_selector: str = None) -> str:
    from playwright.sync_api import sync_playwright
    
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(
            user_agent="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)..."
        )
        
        page.goto(url, wait_until="networkidle", timeout=30_000)
        
        if wait_for_selector:
            page.wait_for_selector(wait_for_selector, timeout=10_000)
        
        html = page.content()
        browser.close()
    
    markdown = html_to_markdown(html)
    return truncate_to_chars(markdown, max_chars=8000)
```

---

## Putting It Together — Full Example Run

```python
if __name__ == "__main__":
    task = """
    Extract product listings from https://books.toscrape.com/
    For each book on the main page, extract: title, price, rating, availability.
    Return structured JSON data for at least 10 books.
    """
    
    extraction_schema = {
        "type": "object",
        "properties": {
            "books": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "title": {"type": "string"},
                        "price_gbp": {"type": "number"},
                        "rating_stars": {"type": "integer", "minimum": 1, "maximum": 5},
                        "availability": {"type": "string", "enum": ["In stock", "Out of stock"]}
                    },
                    "required": ["title", "price_gbp", "rating_stars", "availability"]
                }
            }
        }
    }
    
    # Inject schema into task so orchestrator passes it to extract_structured_data
    full_task = f"{task}\n\nUse this schema for extraction:\n{json.dumps(extraction_schema, indent=2)}"
    
    results, stats = run_web_agent(full_task, max_iterations=15)
    
    print(f"\n=== Results ===")
    print(f"Pages scraped: {len(results)}")
    print(f"Iterations: {stats.iterations}")
    print(f"Cost: ${stats.estimated_cost_usd:.4f}")
    print(f"Duration: {stats.duration_seconds:.1f}s")
    print(json.dumps(results, indent=2))
```

**Expected output:**
```
[Agent] Completed in 8 iterations, $0.0247, 23.4s

=== Results ===
Pages scraped: 5
Iterations: 8
Cost: $0.0247
Duration: 23.4s
[
  {"url": "https://books.toscrape.com/", "data": {"books": [...]}, "confidence": 0.95},
  ...
]
```

---

## Production Considerations

### Caching Scraped Pages

```python
import hashlib
import redis

page_cache = redis.Redis()

def fetch_with_cache(url: str, ttl_seconds: int = 86400) -> str:
    cache_key = f"page:{hashlib.md5(url.encode()).hexdigest()}"
    cached = page_cache.get(cache_key)
    if cached:
        return cached.decode()
    
    content = impl_fetch_page(url)
    if not content.startswith("ERROR"):
        page_cache.setex(cache_key, ttl_seconds, content)
    
    return content
```

A 24-hour page cache reduces costs by 60–80% for agents that re-visit pages (e.g., monitoring jobs).

### Async Fan-Out for Multiple URLs

```python
import asyncio
import httpx

async def fetch_pages_parallel(urls: list[str], max_concurrent: int = 5) -> dict[str, str]:
    semaphore = asyncio.Semaphore(max_concurrent)  # Polite crawling
    
    async def fetch_one(url: str) -> tuple[str, str]:
        async with semaphore:
            async with httpx.AsyncClient() as client:
                resp = await client.get(url, timeout=15, follow_redirects=True)
                markdown = html_to_markdown(resp.text)
                return url, truncate_to_chars(markdown)
    
    tasks = [fetch_one(url) for url in urls]
    results = await asyncio.gather(*tasks, return_exceptions=True)
    
    return {
        url: content if not isinstance(content, Exception) else f"ERROR: {content}"
        for url, content in results
    }
```

**Latency impact**: 10 URLs fetched sequentially at 3s each = 30s. Parallel with `max_concurrent=5`: max(3s, 3s) = 3s. 10× speedup.

### Cost Per 100 URLs

```
Assumption: avg page = 3K tokens after truncation, 1 extraction per page

Fetch (no model): $0 (just HTTP)
Extract (Haiku):  100 × (3K input + 500 output) × $0.25/M input + $1.25/M output
                = 100 × ($0.00075 + $0.000625) = ~$0.14

Orchestrator (Sonnet): 10 orchestration turns × 5K tokens avg
                      = 50K input + 5K output × $3/M + $15/M
                      = $0.15 + $0.075 = ~$0.23

Total for 100 URLs: ~$0.37 per batch run
At scale (10,000 URLs/day): ~$37/day
```

---

## "Design a Web Data Extraction Agent" — FAANG Interview Walkthrough

### Requirements (state these first)

- **Functional**: Given a URL or search query, extract structured data into a user-defined JSON schema
- **Non-functional**: Throughput 1000 URLs/day, p99 latency < 60s per URL, < $0.01 per URL

### High-Level Design

1. **API layer**: `POST /extract {url, schema}` → `{task_id}`, `GET /extract/{task_id}` → `{status, data}`
2. **Task queue**: SQS → worker fleet (async, horizontal scale)
3. **Worker**: orchestrator agent + scrape subagent + extract subagent (tiered models)
4. **Cache**: Redis for scraped pages (24h TTL), reduces cost on repeat URLs
5. **Storage**: S3 for raw markdown, DynamoDB for extracted JSON + metadata

### Key Trade-offs to State

| Decision | Choice | Trade-off |
|---------|--------|-----------|
| Sync vs async | Async | Most pages take > 5s — blocking caller is a bad UX |
| Model for extraction | Haiku | 10× cheaper than Sonnet; structured output is not a reasoning task |
| JS pages | Playwright on demand | 5s per browser launch — only pay when needed |
| Page cache TTL | 24h | Fresh data vs cost; make configurable per use case |
| Max concurrent fetches | 5 per domain | Polite crawling — avoids bans and legal issues |

### Failure Modes to Address

- **403/bot detection**: Browser fallback, rotating user-agents, respect robots.txt
- **LLM extraction failure**: Retry with different instruction, fall back to regex for simple schemas
- **Cost blowup**: Hard limit per task ($0.50), alert on anomalous token usage
- **Infinite crawl loop**: Max URLs per job, visited-URL set to prevent cycles

---

## FAANG Interview Callout

> **30-second system design pitch:**
>
> "I'd build this as an async API with a three-layer agent: an orchestrator that plans the crawl, a scrape subagent that handles HTTP fetching + Playwright fallback + HTML-to-markdown, and an extraction subagent that runs schema-constrained LLM extraction. Key cost controls: Haiku for extraction (not Sonnet), 24h Redis cache for scraped pages, and a hard limit of 50 URLs per job run. The biggest non-obvious challenge is token management — an untruncated HTML page would fill the entire context window, so we convert to markdown and cap at 8K chars before any LLM sees it. At 1000 URLs/day, projected cost is ~$3.70/day, or $0.0037 per URL, well within budget."
