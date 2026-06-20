# Event Storming, Domain Storytelling & Stakeholder Collaboration

## Overview
The most common reason DDD fails in practice: developers model the domain in isolation. They build what they *assume* the business does. Domain experts review it and say "that's not quite right." The model is revised. Six months later, the model has drifted further from reality, and nobody is sure who owns the discrepancy.

**Collaborative Discovery** is DDD's answer: domain models are built *with* domain experts, not *for* them. The two primary tools are **Event Storming** (Alberto Brandolini) and **Domain Storytelling** (Hofer & Schwentner). Both are facilitated workshops that bring domain experts and engineers into the same room (physical or virtual) to model the domain together.

---

## Event Storming

Event Storming is a facilitated, collaborative modelling technique that uses sticky notes on a large surface to build a shared understanding of a business domain through its **domain events** — things that happen that the business cares about.

### Why Domain Events First?

Starting with events instead of entities or data structures forces everyone to think about **what the system does**, not how it is stored. Domain experts naturally think in events ("a customer places an order", "an invoice becomes overdue", "a shipment is delayed"). Events are the natural language of the business.

### The Three Levels

#### Level 1: Big Picture Event Storming

**Goal**: understand the whole business end-to-end. Identify domain events across the entire timeline. Find Bounded Context boundaries. Surface hotspots and areas of confusion.

**Duration**: 4–8 hours for a complex domain.

**Who to invite**: domain experts from all areas (not just one team), senior engineers, product managers, UX. 8–20 participants.

**Output**: a timeline of domain events, Bounded Context boundaries, a list of hotspots (areas of confusion, conflict, or complexity), and the beginning of a Context Map.

**Sticky note colour protocol**:

| Colour | Represents | Example |
|---|---|---|
| 🟠 Orange | **Domain Event** — something that happened (past tense, passive voice) | "Order Placed", "Payment Failed", "Shipment Delayed" |
| 🔵 Blue | **Command** — the intention that triggered the event | "Place Order", "Process Payment", "Create Shipment" |
| 🟡 Yellow | **Aggregate** — the domain object that handled the command | `Order`, `Payment`, `Shipment` |
| 🟣 Purple | **Policy** — "whenever X happens, do Y" (business rule triggered by an event) | "When Payment Failed → Send notification" |
| 🩷 Pink | **External System** — system outside the domain | "Stripe", "Warehouse System", "Email Provider" |
| 🟢 Green | **Read Model** — data needed to make a decision | "Order Summary", "Customer Credit Limit" |
| 🔴 Red | **Hotspot** — area of confusion, conflict, or unknown | "What happens if the warehouse rejects the order?" |

**Running the session**:
1. Empty wall (or Miro board); infinite horizontal space
2. Facilitator introduces orange sticky notes: "What are the most important things that can happen in our domain?"
3. Participants write events and place them on the timeline (left = earlier, right = later)
4. Facilitator groups events into rough Bounded Context swim lanes
5. Conflicts and confusions get red hotspot notes — not resolved in the room, but surfaced
6. After the initial storm: add commands (blue) that trigger events; add aggregates (yellow) that handle commands

#### Level 2: Process Level Event Storming

**Goal**: model a specific business process in detail. Map the full flow: commands, events, policies, read models, and external systems for one process.

**Duration**: 2–4 hours per process.

**Who to invite**: the team(s) that own the relevant Bounded Context(s), domain experts for that process.

**Output**: a detailed process flow including all business rules (policies), data dependencies (read models), and external system integrations. Direct input to the service design.

**Example: Order Submission Process**

```
[Customer]  →  "Submit Order" (command)
             → Order (aggregate) checks: items in stock? payment method valid?
             → "Order Submitted" (event) 🟠
             → Policy: "When Order Submitted → Reserve Inventory" 🟣
             → Inventory System (external) 🩷
             → "Inventory Reserved" (event) 🟠
             → Policy: "When Inventory Reserved → Authorise Payment" 🟣
             → Stripe (external) 🩷
             → "Payment Authorised" (event) 🟠
             → Policy: "When Payment Authorised → Notify Customer" 🟣
             → Email Provider (external) 🩷
             → "Order Confirmed" (event) 🟠

Read models needed at "Submit Order":
  - "Customer's available balance" (from Accounts context)
  - "Product availability" (from Inventory context)
```

#### Level 3: Design Level Event Storming

**Goal**: design the detailed domain model for one Bounded Context. Discover Aggregates, their commands, events, and invariants.

**Duration**: 1–3 hours.

**Who to invite**: the team that will build the context. Domain expert present for domain questions.

**Output**: Aggregate candidates, their commands and events, domain event schemas, Bounded Context data model draft.

---

## Domain Storytelling

**Creator**: Stefan Hofer and Henning Schwentner (*Domain Storytelling*, 2021).

Domain Storytelling uses a **pictographic language** where a domain expert tells a story about how they do their work, and a modeller draws it using a simple notation: actors, work objects, and activities.

### Notation

```
[actor] does [activity] with [work object] → [actor] receives [work object]

Example:
Customer → places → Order
Warehouse → picks → Items (from Inventory)
Shipping Provider → delivers → Package (to Customer)
```

### How It Differs from Event Storming

| Dimension | Event Storming | Domain Storytelling |
|---|---|---|
| **Perspective** | Timeline of events across the whole domain | One story at a time, from the actor's point of view |
| **Granularity** | System-level first, then zoom in | Process-level from the start |
| **Best for** | Finding Bounded Context boundaries | Understanding user workflows and terminology |
| **Output** | Context Map, hotspot list, Aggregate candidates | Domain vocabulary, actor-work object relationships |
| **Facilitation** | Large group; lots of energy | Smaller group; quieter, more structured |
| **Onboarding** | Too noisy for new team members | Excellent for new joiner orientation |

**Recommendation**: Start a new domain exploration with Big Picture Event Storming to find boundaries. Use Domain Storytelling for specific workflows once the Bounded Contexts are known.

---

## Building the Ubiquitous Language

Collaborative discovery sessions produce the raw material for the Ubiquitous Language. After the session:

### Building the Domain Glossary

```markdown
# Orders Domain Glossary

**Order**: A customer's intention to purchase one or more products.
  - Valid statuses: DRAFT → SUBMITTED → CONFIRMED → FULFILLED → CANCELLED
  - An Order is immutable once CONFIRMED (business rule surfaced in Event Storming)

**Qualifying Purchase**: A purchase with a total value > $50 that has been FULFILLED.
  - Used in: loyalty tier calculation
  - NOT the same as any completed order (disputed payments don't qualify)

**Loyalty Tier Upgrade**: The transition to a higher loyalty tier.
  - Triggered when: 3 qualifying purchases in a rolling 90-day window
  - Eligibility recalculated: on every OrderFulfilled event
```

### Resolving Vocabulary Conflicts

In Event Storming, vocabulary conflicts surface as disagreements:

- "I'd call that 'invoice' but she calls it 'bill' — they're the same, right?" → Maybe not. Explore the difference.
- "For us in Finance, 'cancel' means void the invoice. For Fulfilment, 'cancel' means stop the shipment." → Bounded Context boundary. Each context has its own 'cancel'.

Unresolved conflicts become red hotspots. Resolved conflicts become glossary entries with explicit definitions.

---

## Stakeholder Management

### How DDD Reduces "Lost in Translation"

In traditional projects:
```
Business Analyst → writes requirements document
                 → developer reads (and misunderstands)
                 → developer implements something different
                 → QA finds issues
                 → BA writes clarification
                 → iterate
```

With DDD collaborative discovery:
```
Domain expert + developer → model domain together in Event Storming
                          → domain expert reviews the model in the code (method names match their language)
                          → "Place Order" in the UI = place_order() in the code = "Order Placed" event
                          → no translation required
```

### Context Map as Organisational Transparency

The Context Map makes **team dependencies explicit** to stakeholders:

```
Context Map shows:
  "The Payments team is upstream of the Reporting team (Customer-Supplier relationship)"
  "The Reporting team must accept Payments' event schema, or raise a change request with the Payments team"

Stakeholder impact:
  - PMs can see which team dependencies will block a roadmap item before planning
  - Engineering managers can staff the right teams at the right time
  - Leadership can see whether team boundaries match the architecture (or not)
```

### Translating DDD to OKRs and Roadmaps

| DDD concept | Stakeholder equivalent |
|---|---|
| Core Domain | "Strategic bets" on the roadmap; highest investment priority |
| Supporting Subdomain | "Enablers" — necessary but not headline features |
| Generic Subdomain | "Buy vs. build" decisions; reduce engineering investment here |
| Bounded Context boundary | Team charter and ownership boundary |
| Hotspot (Event Storming) | Engineering risk items; may need spike before committing to estimate |
| Anti-Corruption Layer | Technical debt item: "we need to build an adapter before we can integrate with legacy system X" |

---

## Cognitive Load Reduction

### How Bounded Contexts Reduce Cognitive Load

**Without explicit contexts**: every engineer must understand the entire system to make safe changes. "If I change the Order table, what breaks in the Billing service? The Reporting service? The Fulfilment API?"

**With Bounded Contexts**:
- Each team owns one context's complete model
- The context boundary = the extent of what they must understand
- Cross-context interactions are via explicit contracts (APIs, events), not implicit shared state
- A new engineer joining the Payments team needs to understand the Payments context — not the entire platform

### Team Topologies and Cognitive Load

Team Topologies (Skelton & Pais) defines **cognitive load** as the primary constraint on team effectiveness. DDD's Bounded Contexts are the architectural implementation of cognitive load management:

| Team Topologies concept | DDD equivalent | Cognitive load control |
|---|---|---|
| Stream-aligned team | Owns one Bounded Context (Core Domain) | Cognitive load bounded by context size |
| Platform team | Owns Generic subdomain Bounded Contexts | Shared infrastructure; reduces cognitive load of all stream-aligned teams |
| Complicated subsystem team | Owns a specialised Supporting subdomain | Specialist knowledge isolated from generalist teams |
| Enabling team | Facilitates DDD practice (Event Storming, modelling workshops) | Reduces learning curve; builds modelling capability across teams |

**The practical rule**: if a team's Bounded Context has grown too complex for the team to fully own, it's time to split the context — not to add more people to the team. Adding people to a too-large context increases communication overhead without reducing cognitive load.

---

## Facilitation Anti-Patterns

| Anti-pattern | Problem | Fix |
|---|---|---|
| **Developers only** | The model will reflect developer assumptions, not domain reality | Require domain expert presence; no session without them |
| **Architecture astronaut** | One person dominates and models their preferred architecture | Facilitator enforces equal participation; no whiteboards, only sticky notes |
| **Too much detail too early** | Spending 2 hours on one event's edge cases | Facilitator enforces: "hotspot it and move on" |
| **No hotspot tracking** | Conflicts are resolved in the room through force of personality | All conflicts → red hotspot; resolved after with the right people |
| **One-time event** | A single Event Storming session is treated as complete and final | Event Storming is ongoing — the model evolves; revisit quarterly |
| **Remote with video only** | Participants can't contribute equally | Use Miro/Mural with video; same sticky note protocol; breakout rooms for smaller discussions |

---

## Best Practices

1. **No Event Storming without domain experts** — developers alone produce a technical model, not a domain model
2. **Big Picture first, then zoom** — discover context boundaries before modelling internal details
3. **Hotspot everything, resolve later** — don't resolve conflicts in the session; surface them and assign owners to resolve offline
4. **The model lives in the code** — after the session, translate the model directly into code with the same vocabulary; don't let the model diverge from the implementation
5. **Run Event Storming at the start of major features** — not just greenfield; any significant new capability benefits from a modelling session
6. **Keep domain glossary up to date** — it is a living document; stale glossaries cause the language to diverge
7. **Share the Context Map with leadership** — it is not just an engineering artefact; it shows team dependencies that affect roadmap planning
8. **Treat hotspots as risk items** — they are the parts of the domain that are least understood; they will bite you in implementation if not resolved

---

## FAANG Interview Points

**"How do you get alignment between product, business, and engineering on a complex system before you start building?"**: Event Storming. I bring domain experts, product managers, and engineers into the same room. We spend 4–8 hours building a shared event timeline — mapping what happens in the business domain, not what the system does. The output is a shared vocabulary (which becomes the Ubiquitous Language), a rough Bounded Context map (which drives team structure), and a hotspot list (which becomes the engineering risk register). The model then lives in the code — method names and class names match the vocabulary we built together.

**"How do you onboard a new engineer onto a complex domain quickly?"**: Domain Storytelling sessions. Rather than reading code or documentation, the new engineer watches domain experts tell stories about their work — what they do, with what objects, in what sequence. A modeller draws it using the pictographic notation. After a few sessions, the new engineer understands the vocabulary and workflows. Then they read the code — and because we use Ubiquitous Language, the code makes sense immediately.

**"How does Event Storming discover microservice boundaries?"**: Language divergence and team ownership patterns surface in the session. When the same sticky note word (e.g., "Order") is used differently in the Fulfilment swim lane vs. the Billing swim lane, you've found a Bounded Context boundary. Hotspots cluster around boundaries — these are the seams. Aggregates that keep appearing together likely belong in the same context. The resulting Context Map becomes the first draft of the microservice boundary definition.
