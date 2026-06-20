# browser-use: Architecture Deep-Dive

> **Source**: https://github.com/browser-use/browser-use  
> **Stars**: ~99k | **Language**: Python | **Core deps**: Playwright, LangChain-compatible LLMs  
> **Purpose**: Make websites accessible for AI agents — a framework that gives LLMs a real browser as a tool

---

## 1. What Is browser-use?

browser-use is an open-source Python framework that lets any LLM (GPT-4, Claude, Gemini, Llama, etc.) control a real Chromium browser via CDP (Chrome DevTools Protocol) to complete arbitrary web tasks. The agent sees the page through a combination of DOM snapshots and screenshots, decides what to do next, and dispatches keyboard/mouse actions back through the browser.

The three-layer execution pipeline:

```
Your Task String
     │
     ▼
┌─────────────────────────────────────┐
│  Python Agent (orchestration loop)  │
└─────────────────────────────────────┘
     │  events + CDP calls
     ▼
┌─────────────────────────────────────┐
│  BrowserSession (CDP session pool)  │
└─────────────────────────────────────┘
     │  Chrome DevTools Protocol (WebSocket)
     ▼
┌─────────────────────────────────────┐
│  Chromium / Remote Browser          │
└─────────────────────────────────────┘
```

---

## 2. Repository Structure

```
browser_use/
├── agent/                  # Orchestration loop, prompts, state, history
│   ├── service.py          # Agent class — the main orchestrator (163 KB)
│   ├── views.py            # Pydantic models: AgentOutput, AgentHistory, AgentState
│   ├── prompts.py          # System prompt templates + per-step context assembly
│   ├── judge.py            # LLM-based task completion evaluator
│   ├── message_manager/    # History compression + token-window management
│   └── system_prompts/     # Markdown prompt templates (model-specific variants)
│
├── browser/                # Browser session management
│   ├── session.py          # BrowserSession — CDP connections, target pool (156 KB)
│   ├── profile.py          # BrowserProfile — all launch/connect configuration
│   ├── events.py           # 30+ typed event definitions (EventBus via bubus)
│   ├── session_manager.py  # CDP session pool (one session per target)
│   ├── watchdog_base.py    # BaseWatchdog — event-handler composition pattern
│   └── watchdogs/          # Concrete watchdogs: security, DOM, screenshots, etc.
│
├── dom/                    # DOM-to-text pipeline for LLM consumption
│   ├── service.py          # DomService — builds enhanced element tree (47 KB)
│   ├── views.py            # EnhancedDOMTreeNode, EnhancedAXNode, SerializedDOMState
│   ├── serializer/         # DOMTreeSerializer — prunes tree, produces prompt text
│   └── markdown_extractor.py # LLM-powered page → structured markdown extraction
│
├── tools/                  # Action registry + browser action implementations
│   ├── service.py          # Tools class — action registration + act() dispatch (90 KB)
│   ├── registry/           # Registry — decorator-based action store
│   └── extraction/         # Structured data extraction from pages
│
├── llm/                    # Multi-provider LLM abstraction
│   ├── base.py             # BaseChatModel Protocol
│   ├── models.py           # Concrete wrappers per provider
│   └── {provider}/         # anthropic/, openai/, google/, azure/, groq/, etc.
│
├── actor/                  # High-level action executor (wraps tools layer)
├── beta/                   # Rust-powered experimental agent (v0.13+)
├── mcp/                    # Model Context Protocol server integration
├── skills/                 # Skill definitions (reusable task sub-routines)
├── integrations/           # Third-party service integrations
├── filesystem/             # Sandboxed file I/O for agent use
├── telemetry/              # Cloud event emission
├── config.py               # CONFIG singleton (env vars + JSON config store)
└── cli.py                  # CLI entry point
```

---

## 3. Core Architecture: Component Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│                         User / Application                           │
│                   agent = Agent(task, llm, ...)                      │
│                       await agent.run()                              │
└─────────────────────┬────────────────────────────────────────────────┘
                      │
          ┌───────────▼───────────┐
          │     Agent Service     │  ← orchestration loop (service.py)
          │  - AgentState         │
          │  - MessageManager     │
          │  - LoopDetector       │
          │  - PlanManager        │
          └──┬──────────┬─────────┘
             │          │
    ┌─────────▼──┐   ┌──▼────────────────┐
    │  LLM Layer │   │   Tools / Actions  │
    │ (BaseLLM   │   │  - click()         │
    │  protocol) │   │  - navigate()      │
    │  11+ provs │   │  - extract()       │
    └─────────┬──┘   │  - done()  ...30+  │
              │      └──────────┬──────────┘
    structured│                 │ events
    output    │          ┌──────▼───────────────────────┐
              │          │       BrowserSession          │
              │          │  - CDPClient (WebSocket)      │
              │          │  - SessionManager (pool)      │
              │          │  - EventBus (bubus)           │
              │          │  - Watchdog registry          │
              │          └──┬───────────────────────────┘
              │             │  CDP
              │    ┌────────▼──────────┐
              │    │  Chromium Browser │
              │    │  (local or cloud) │
              │    └────────┬──────────┘
              │             │
              │    ┌────────▼──────────┐
              │    │   DOM Service     │
              │    │  (snapshot →      │
              │    │   element tree →  │
              │    │   prompt text)    │
              │    └───────────────────┘
              │
    ┌─────────▼─────────────────────────┐
    │      AgentMessagePrompt           │  ← per-step context builder
    │  task + history + DOM + screenshot│
    │  + tabs + plan + file state       │
    └───────────────────────────────────┘
```

---

## 4. Agent Execution Loop

The `Agent.run()` method drives a finite-step loop. Each iteration is a `step()` call, decomposed into four explicit phases:

### Phase Sequence

```
┌────────────────────── step() ───────────────────────┐
│                                                      │
│  1. _prepare_context()                               │
│     ├── Get browser state (DOM snapshot + screenshot)│
│     ├── Build AgentMessagePrompt                     │
│     └── Compress message history if needed           │
│                                                      │
│  2. _get_next_action()                               │
│     ├── Call LLM with structured output schema       │
│     ├── Parse AgentOutput (thinking + actions list)  │
│     ├── Restore shortened URLs in LLM response       │
│     └── Apply max_actions_per_step cap               │
│                                                      │
│  3. _execute_actions()                               │
│     ├── For each action in AgentOutput.actions:      │
│     │   └── tools.act(action) → ActionResult         │
│     └── Collect results + handle errors              │
│                                                      │
│  4. _post_process() + _finalize()                    │
│     ├── Update plan state                            │
│     ├── Check loop detection                         │
│     ├── Record AgentHistory entry                    │
│     └── Emit telemetry events                        │
│                                                      │
└──────────────────────────────────────────────────────┘
         │
    Done? ──Yes──► Judge evaluation ──► done callbacks
         │
         No
         │
    ◄────┘  (next step)
```

### Key Design Decisions in the Loop

| Decision | Mechanism | Why |
|----------|-----------|-----|
| LLM gets structured output | Pydantic schema passed as `output_format` | Eliminates parsing ambiguity; actions are typed |
| Graceful degradation | `fallback_llm` on rate limits / auth errors | Agent survives transient provider failures |
| Loop detection | Hash of (actions + page fingerprint) in a rolling window | Prevents infinite click-same-button loops |
| URL shortening | Replace long URLs before LLM call; restore after parse | Saves tokens without losing fidelity |
| Message compaction | Summarize old history when token budget exceeded | Enables long-running tasks (100+ steps) |
| Step counter advances on timeout | `consecutive_failures` incremented; step still logs | Prevents silent hangs consuming max_steps |
| Multi-step planning | Optional `enable_planning=True` with `PlanItem` list | Helps on complex multi-page tasks |

---

## 5. Browser Session & CDP Architecture

`BrowserSession` is a Pydantic BaseModel (not a context manager) that owns the CDP connection.

### Connection Modes

```
BrowserSession
├── Local mode: launch Chromium via Playwright
│   └── BrowserProfile → LocalBrowserWatchdog → subprocess
└── Cloud mode: connect to remote Chrome
    └── BrowserProfile.cdp_url → WebSocket CDP client
```

### CDP Session Pooling

Each browser tab is a CDP "target." `SessionManager` maintains a pool:

```
BrowserSession
└── SessionManager
    ├── CDPSession(target_id=A, page="https://google.com")
    ├── CDPSession(target_id=B, page="https://github.com")
    └── CDPSession(target_id=C, page="about:blank")
              │
              └── agent_focus_target_id points to active tab
```

`get_or_create_cdp_session()` fetches the pooled session for the focused tab — no new WebSocket handshake per action.

### Auto-Reconnection

```
WebSocket drops
      │
      ▼
_auto_reconnect() with exponential backoff (1s → 2s → 4s)
      │
      ├── BrowserReconnectingEvent → watchdogs pause non-lifecycle work
      │
      └── BrowserReconnectedEvent → watchdogs resume
```

---

## 6. Watchdog System (Composable Browser Behaviors)

All browser behaviors are implemented as watchdogs — event handlers attached to BrowserSession. This is the key extensibility mechanism.

### BaseWatchdog Pattern

```python
class BaseWatchdog:
    LISTENS_TO: ClassVar[list[type[BaseEvent]]] = [NavigateToUrlEvent]
    EMITS:      ClassVar[list[type[BaseEvent]]] = [NavigationCompleteEvent]

    def on_NavigateToUrlEvent(self, event: NavigateToUrlEvent) -> ...:
        # execute CDP call
        # dispatch NavigationCompleteEvent
```

Methods named `on_<EventType>` auto-register on `attach_to_session()`. No boilerplate.

### Built-in Watchdogs

| Watchdog | Listens to | Emits | Purpose |
|----------|-----------|-------|---------|
| LocalBrowserWatchdog | BrowserStartEvent, BrowserStopEvent | BrowserLaunchEvent, BrowserKillEvent | Launch/kill local Chrome |
| SecurityWatchdog | NavigateToUrlEvent | BrowserErrorEvent | Enforce allowed_domains allowlist |
| DOMWatchdog | BrowserStateRequestEvent | — | Build DOM snapshot + selector map |
| ScreenshotWatchdog | ScreenshotEvent | — | Capture viewport screenshots |
| DefaultActionWatchdog | ClickElementEvent, TypeTextEvent, ScrollEvent, … | — | Perform actual browser interactions |
| DownloadsWatchdog | DownloadStartedEvent | FileDownloadedEvent | Track file downloads |
| StorageStateWatchdog | SaveStorageStateEvent | — | Persist cookies / localStorage |
| CaptchaWatchdog | — | CaptchaSolverStartedEvent | Integrate CAPTCHA solvers |

New behaviors are added by implementing a watchdog — no changes to BrowserSession itself.

---

## 7. DOM Processing Pipeline

The `DomService` converts a live browser page into a token-efficient text representation suitable for LLM prompts.

### Pipeline Stages

```
Chrome page
    │
    ▼ CDP: DOM.getDocument() + Accessibility.getFullAXTree()
    │     + CSS.captureSnapshot() (parallel requests)
    │
EnhancedDOMTreeNode tree
    │  ├── visibility = f(CSS display, opacity, viewport intersection)
    │  ├── absolute coordinates (adjusted for iframe offsets)
    │  ├── JS click listener detection
    │  └── AX role/name/description overlaid from accessibility tree
    │
    ▼ DOMTreeSerializer
    │
SerializedDOMState
    │  ├── selector_map: { 0: node, 1: node, … }  ← index per interactive element
    │  └── element_tree: pruned text representation
    │
    ▼ AgentMessagePrompt
    │
LLM prompt excerpt:
  "[0] <button>Submit</button>"
  "[1] <input placeholder='Search'>"
  "[2] <a href='…'>Next page</a>"
  ... (capped at 40,000 chars)
```

### Key Design Choices

- **Backend Node IDs** from CDP are the stable element identifier — correlates DOM and AX trees
- **Cross-origin iframe** handling: each iframe processed with its own coordinate offset
- **Shadow DOM** traversal: content documents recursed separately
- **Paint order filtering**: optional mode that orders elements by visual rendering sequence, not DOM order
- **Hidden element hints**: scrollable elements outside viewport noted so LLM knows to scroll

---

## 8. Tools / Action System

`Tools` (aliased as `Controller`) is a generic action registry. Actions are registered with a decorator and exposed to the LLM as structured schemas.

### Registration Pattern

```python
@tools.registry.action(
    'Click an element by its index',
    param_model=ClickElementAction
)
async def click(params: ClickElementAction, browser_session: BrowserSession):
    await browser_session.event_bus.dispatch(ClickElementEvent(index=params.index))
    return ActionResult(extracted_content='Clicked element')
```

### Available Action Categories

| Category | Actions |
|----------|---------|
| Navigation | navigate, go_back, go_forward, refresh, search |
| Element interaction | click (index), click (coordinates), type, scroll, send_keys, upload_file |
| Page exploration | find_elements (CSS), search_page (text grep), screenshot |
| Data extraction | extract (LLM-powered, supports structured schemas) |
| Forms | dropdown_options, select_dropdown |
| Tabs | switch_tab, close_tab, open_tab |
| File system | read_file, write_file, replace_file |
| Advanced | evaluate (JavaScript), save_as_pdf |
| Termination | done (with optional structured output) |

### Execution Flow

```
agent._execute_actions(AgentOutput.actions)
      │
      ▼ for each ActionModel in list:
Tools.act(action)
      ├── validate timeout
      ├── registry.execute_action(name, params, injected_deps)
      │       └── handler(params, browser_session, page_extraction_llm, …)
      │               └── event_bus.dispatch(ClickElementEvent / TypeTextEvent / …)
      │                       └── DefaultActionWatchdog.on_ClickElementEvent()
      │                               └── CDP: Input.dispatchMouseEvent()
      └── return ActionResult
```

### Dependency Injection

Action handlers receive injected dependencies beyond their param model:
- `browser_session` — live CDP connection
- `page_extraction_llm` — for the `extract` action
- `sensitive_data` — dict of secrets (logged masked, never in prompts)
- `available_file_paths` — sandboxed file access whitelist

---

## 9. LLM Abstraction Layer

### Provider Support

```
browser_use/llm/
├── anthropic/     ChatAnthropic
├── openai/        ChatOpenAI
├── google/        ChatGoogle
├── azure/         ChatAzureOpenAI
├── groq/          ChatGroq
├── mistral/       ChatMistral
├── litellm/       ChatLiteLLM      ← any LiteLLM-supported provider
├── ollama/        ChatOllama
├── deepseek/      (via OpenAI-compat)
├── vercel/        ChatVercel
├── aws/           ChatBedrock
└── browser_use/   ChatBrowserUse   ← proprietary optimized model
```

### BaseChatModel Protocol

```python
class BaseChatModel(Protocol):
    model: str
    provider: str

    async def ainvoke(
        self,
        messages: list[BaseMessage],
        output_format: type[T] | None = None,
        **kwargs
    ) -> ChatInvokeCompletion[T]: ...
```

All providers implement this Protocol without inheritance — duck typing with runtime checkability. Structured output (Pydantic schema) is passed as `output_format`, allowing each provider to use their native structured output API (OpenAI function calling, Anthropic tool use, Gemini JSON mode, etc.).

---

## 10. Prompt Architecture

### System Prompt Strategy

Templates selected at startup based on model capabilities:

| Template | When used |
|----------|-----------|
| `system_prompt.md` | Default — all providers |
| `system_prompt_no_thinking.md` | Models without thinking/reasoning mode |
| `system_prompt_flash.md` | Flash/small models (cost-optimized) |
| `system_prompt_anthropic.md` | Claude-specific (longer for prompt caching) |

### Per-Step Context Assembly (`AgentMessagePrompt`)

```
Message structure sent to LLM each step:
┌──────────────────────────────────────────┐  ← cacheable prefix (doesn't change)
│  [SYSTEM]  system_prompt.md              │
├──────────────────────────────────────────┤
│  [USER]    Task: "book a flight to NYC"  │
│  [ASST]    Step 1: { navigate… }         │
│  [USER]    Step 1 result: …              │
│  …         (history, compressed if long) │
├──────────────────────────────────────────┤  ← changes each step
│  [USER]    Current page state:           │
│              - URL: https://…            │
│              - Tabs: [tab1, tab2]        │
│              - DOM: [0]<btn>… [1]<a>…   │
│              - Screenshot: <image>       │
│              - Plan: step 2 of 5         │
│              - Step: 3/50, date: …       │
└──────────────────────────────────────────┘
```

**Caching optimization**: the stable prefix (system + task + early history) is marked `cache=True` so provider-side prompt caching (Anthropic, OpenAI) reuses KV cache across steps.

---

## 11. Event System

### EventBus (bubus library)

The central pub/sub bus is an instance of `bubus.EventBus` held on `BrowserSession`. All components communicate through it — no direct method calls between layers.

### Event Flow Example: Click Action

```
Tools.act(ClickElementAction(index=3))
      │
      ▼ dispatch
EventBus → ClickElementEvent(index=3)
      │
      ▼ subscribed handler
DefaultActionWatchdog.on_ClickElementEvent()
      ├── Look up selector_map[3] → EnhancedDOMTreeNode
      ├── CDP: Input.dispatchMouseEvent(x, y)
      └── return ClickResult
```

### All Event Categories (30+)

```
Agent → Browser:         NavigateToUrlEvent, ClickElementEvent, TypeTextEvent,
                         ScrollEvent, UploadFileEvent, ScreenshotEvent, ...

Browser lifecycle:       BrowserStartEvent, BrowserConnectedEvent,
                         BrowserStopEvent, BrowserReconnectingEvent, ...

Tab management:          TabCreatedEvent, TabClosedEvent, SwitchTabEvent,
                         AgentFocusChangedEvent, ...

Navigation signals:      NavigationStartedEvent, NavigationCompleteEvent, ...

Storage/Downloads:       SaveStorageStateEvent, FileDownloadedEvent, ...

Error/Recovery:          BrowserErrorEvent, BrowserReconnectedEvent,
                         TargetCrashedEvent, DialogOpenedEvent, ...

Captcha:                 CaptchaSolverStartedEvent, CaptchaSolverFinishedEvent
```

---

## 12. Data Models

### Core Pydantic Models

```
AgentSettings          — all Agent() constructor params with defaults
AgentState             — mutable runtime state (step count, failures, plan)
AgentOutput            — LLM response: thinking + evaluation + memory + actions[]
AgentHistory           — one step record: output + results + browser state
AgentHistoryList       — full run history with serialize/deserialize

ActionResult           — tool execution outcome: content + error + is_done + attachments
JudgementResult        — task completion verdict: success/fail + reasoning

BrowserProfile         — all browser config (headless, proxy, domains, extensions…)
BrowserSession         — live session: cdp_url + session_manager + event_bus + watchdogs

EnhancedDOMTreeNode    — enriched DOM node: visibility + coords + AX data + listeners
SerializedDOMState     — prompt-ready: element_tree text + selector_map {idx: node}

PlanItem               — individual plan step with status lifecycle
PageFingerprint        — (url, element_count, dom_hash) for loop detection
```

---

## 13. Key Design Patterns

### Pattern 1: Event-Driven Loose Coupling

No layer calls another layer's methods directly. Agent dispatches `NavigateToUrlEvent`; `DefaultActionWatchdog` handles it and dispatches `NavigationCompleteEvent`. This makes all behaviors swappable without touching the core agent.

### Pattern 2: Watchdog Composition

Behaviors are composed by attaching watchdogs, not subclassing. To add a captcha solver: implement `CaptchaWatchdog.on_DialogOpenedEvent()` and attach it. The agent, tools, and DOM layers remain unchanged.

### Pattern 3: Protocol-Based LLM Abstraction

`BaseChatModel` is a Python Protocol, not an abstract class. Any object with `ainvoke()` and `model` works. This means users can inject custom wrappers, proxies, or ensemble models without touching the framework.

### Pattern 4: Dependency Injection in Actions

Actions receive dependencies via injection, not globals. This makes them unit-testable and allows the agent to swap out the extraction LLM per action, inject mock sessions, or provide per-run sensitive data dictionaries.

### Pattern 5: Phase-Separated Agent Step

The four-phase step (`prepare → LLM → execute → finalize`) means each phase can fail independently and be instrumented separately. Timeouts apply per phase. Errors in `execute` don't prevent history recording in `finalize`.

### Pattern 6: Lazy Import + Deferred Initialization

`browser_use/__init__.py` uses `__getattr__` to defer heavy module imports until first use, keeping import time minimal for CLI invocations that may not use all providers.

---

## 14. Scalability & Production Considerations

### Memory Pressure

Each agent run holds one Chromium process. For parallel agents:

- **Local**: Each Chrome instance ~200–500 MB RAM. Use connection pooling against shared remote Chrome.
- **Cloud mode**: browser-use cloud manages process lifecycle, stealth fingerprinting, and proxy rotation.

### Token Budget Management

| Problem | Solution |
|---------|----------|
| DOM too large | Truncated at 40,000 chars; elements outside viewport noted |
| Long task history | `MessageCompactionSettings` — old steps summarized by LLM |
| Repeated screenshots | Vision optional; placeholder used on blank pages |
| Long URLs | Shortened in prompts, restored in parsed output |

### Failure Modes

| Failure | Behavior |
|---------|----------|
| CDP WebSocket drop | `_auto_reconnect()` with exponential backoff |
| Browser crash | `TargetCrashedEvent` → graceful step failure |
| LLM rate limit | Switch to `fallback_llm`, increment failure counter |
| Empty LLM action | Retry with nudge (up to 3x) |
| Behavioral loop | Loop detector triggers escalating nudges → forced replan |
| Max failures reached | Agent terminates cleanly with history preserved |

---

## 15. Extension Points

| Extension | How |
|-----------|-----|
| Custom actions | `@tools.registry.action(...)` decorator |
| Custom skills | `Agent(skill_ids=[...])` or `skills=[MySkill()]` |
| Custom LLM | Implement `BaseChatModel` Protocol |
| Custom watchdog | Subclass `BaseWatchdog`, implement `on_*` handlers |
| Custom output schema | `Agent(output_model_schema=MySchema)` — `done()` validates against it |
| Step callbacks | `register_new_step_callback(fn)`, `register_done_callback(fn)` |
| MCP integration | `browser_use/mcp/` — expose as MCP tool server |

---

## 16. FAANG Interview Angles

### System Design Questions This Architecture Answers

**"Design an AI browser agent"** — Use browser-use's architecture as your answer:
- Separate the orchestration (Agent), perception (DOM service), action (Tools), and actuation (BrowserSession) layers
- Use event-driven architecture so behaviors are composable without tight coupling
- CDP over Playwright APIs gives direct protocol access needed for reliability at scale

**"How do you handle long-running LLM tasks with large context?"**
- Token budget management: DOM truncation, screenshot sizing, URL shortening
- History compaction: summarize old steps, keep recent N steps verbatim
- Prompt caching: stable prefix cached server-side across steps

**"How would you scale browser automation to 1000 concurrent users?"**
- Connection pooling: many agents share a browser pool, not one process per agent
- Event-driven reconnect: no blocking waits on browser operations
- Cloud browser delegation: offload stealth, proxy rotation, CAPTCHA to a managed layer

### Principal Engineer Calibration Points

- **Abstraction at the right level**: Browser behaviors as watchdogs (not subclassing) demonstrates "composition over inheritance" in production code
- **Protocol-based LLM interface**: duck typing instead of ABC prevents vendor lock-in — a cross-cutting architecture concern
- **Observability baked in**: Telemetry events emitted at every lifecycle point before they're needed, not after incidents

---

## 17. Quick Reference

```python
from browser_use import Agent, BrowserSession, BrowserProfile
from browser_use.llm import ChatAnthropic

# Minimal usage
agent = Agent(
    task="Find the cheapest flight from SFO to JFK next Friday",
    llm=ChatAnthropic(model="claude-sonnet-4-6"),
)
result = await agent.run()

# With configuration
profile = BrowserProfile(
    headless=True,
    allowed_domains=["google.com", "kayak.com"],
    downloads_path="/tmp/downloads"
)
session = BrowserSession(browser_profile=profile)
agent = Agent(
    task="...",
    llm=ChatAnthropic(model="claude-opus-4-8"),
    browser_session=session,
    max_steps=50,
    use_vision=True,
    enable_planning=True,
    max_failures=5,
)
history: AgentHistoryList = await agent.run()
print(history.final_result())
```

**Environment variables that matter in production:**

| Variable | Default | Purpose |
|----------|---------|---------|
| `BROWSER_USE_HEADLESS` | null | Force headless mode |
| `BROWSER_USE_ALLOWED_DOMAINS` | null | Domain allowlist (CSV) |
| `BROWSER_USE_ACTION_TIMEOUT_S` | 180 | Per-action timeout |
| `ANONYMIZED_TELEMETRY` | true | Disable if air-gapped |
| `IN_DOCKER` | auto | Disables Chrome sandbox |
| `DEFAULT_LLM` | empty | Default model ID |
