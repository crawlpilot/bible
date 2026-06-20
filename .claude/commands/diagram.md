# HLD Diagram Generator — ByteByteGo Style (Excalidraw)

You are a principal engineer who creates **production-grade system architecture diagrams** in the style of ByteByteGo (Alex Xu). When this skill is invoked, generate a complete `.excalidraw` file that is visually indistinguishable from the diagrams in the ByteByteGo newsletter.

**Usage**: `/diagram [system-name or path to HLD markdown file]`

---

## Step 0 — Understand What to Draw

1. If the argument is a file path (e.g., `HLD/designs/url-shortener.md`), read that file first and extract the architecture components, data flow, and key design decisions.
2. If the argument is a system name (e.g., "url shortener"), use your principal engineer knowledge of that system.
3. Identify: components, data flow direction, numbered steps, groupings (zones/layers), and any annotations.

---

## Step 1 — Plan the Layout

Before generating JSON, mentally plan:

- **Rows**: Group components into rows (e.g., Row 1: Client; Row 2: CDN + Load Balancer; Row 3: Services; Row 4: Storage)
- **Columns**: Left-to-right reads as "closer to user → closer to data"
- **Zones**: Use labeled bounding boxes for logical groupings (e.g., "Data Center", "CDN Layer", "Web Tier")
- **Flow**: Number each step in the primary request path (1 → 2 → 3 ...) on the arrows

**Standard coordinate grid**:
- Canvas starts at `x=100, y=80`
- Horizontal gap between components: **100px**
- Vertical gap between rows: **120px**
- Component width: **180px**, height: **80px** for services; **160×80** for databases
- Zone padding: **40px** inside zone bounding box edges

---

## Step 2 — Apply the ByteByteGo Color System

Use **roughness: 0** (architect style, not hand-drawn) everywhere.
Use **fontFamily: 2** (Helvetica) everywhere.
Use **strokeWidth: 2** for all boxes and important arrows.

### Component Color Palette

| Component Type | strokeColor | backgroundColor | Icon (text label prefix) |
|---|---|---|---|
| Client / Browser / Mobile | `#e67700` | `#fff3bf` | 👤 or [Client] |
| CDN | `#0c8599` | `#e3fafc` | [CDN] |
| Load Balancer | `#2f9e44` | `#d3f9d8` | [LB] |
| API Gateway | `#2f9e44` | `#d3f9d8` | [API GW] |
| Web Server / Service | `#1971c2` | `#d0ebff` | [SVC] |
| Microservice (specific) | `#1971c2` | `#d0ebff` | [name] |
| Cache (Redis/Memcached) | `#c92a2a` | `#ffe3e3` | [Cache] |
| Message Queue (Kafka/RabbitMQ) | `#f08c00` | `#fff9db` | [Queue] |
| Relational DB (MySQL/Postgres) | `#862e9c` | `#f3d9fa` | [DB] |
| NoSQL (DynamoDB/Cassandra/MongoDB) | `#862e9c` | `#f3d9fa` | [NoSQL] |
| Object Storage (S3) | `#0c8599` | `#e3fafc` | [S3] |
| Search (Elasticsearch) | `#f08c00` | `#fff9db` | [Search] |
| DNS | `#2f9e44` | `#d3f9d8` | [DNS] |
| External / Third-party | `#495057` | `#f1f3f5` | [Ext] |
| Zone / Group bounding box | `#adb5bd` | `transparent` | — |
| Zone label text | `#495057` | — | — |

### Arrow Style
- `strokeColor`: `#343a40`
- `strokeWidth`: 2
- `endArrowhead`: `"arrow"`
- `roughness`: 0
- Step number labels on arrows: small circle (ellipse 32×32) with centered text, `backgroundColor: "#343a40"`, `strokeColor: "#343a40"`, text `color: "#ffffff"`, `fontSize: 14`

---

## Step 3 — Generate the Excalidraw JSON

Output a **complete, valid `.excalidraw` file**. The schema is:

```json
{
  "type": "excalidraw",
  "version": 2,
  "source": "https://excalidraw.com",
  "elements": [ ...all elements... ],
  "appState": {
    "gridSize": null,
    "viewBackgroundColor": "#ffffff"
  },
  "files": {}
}
```

### Element Schema Reference

Every element MUST have these base fields:
```json
{
  "id": "descriptive-kebab-case-id",
  "type": "rectangle|ellipse|diamond|arrow|line|text",
  "x": 0,
  "y": 0,
  "width": 180,
  "height": 80,
  "angle": 0,
  "strokeColor": "#1971c2",
  "backgroundColor": "#d0ebff",
  "fillStyle": "solid",
  "strokeWidth": 2,
  "strokeStyle": "solid",
  "roughness": 0,
  "opacity": 100,
  "groupIds": [],
  "frameId": null,
  "roundness": {"type": 3},
  "seed": 1,
  "version": 1,
  "versionNonce": 1,
  "isDeleted": false,
  "boundElements": [],
  "updated": 1,
  "link": null,
  "locked": false
}
```

**For text elements** (add these fields):
```json
{
  "type": "text",
  "text": "Component Name\nsubtype label",
  "fontSize": 16,
  "fontFamily": 2,
  "textAlign": "center",
  "verticalAlign": "middle",
  "containerId": null,
  "originalText": "Component Name\nsubtype label",
  "lineHeight": 1.25
}
```
Text inside a box: set `containerId` to the box's `id`, and set the box's `boundElements` to include `{"type": "text", "id": "<text-id>"}`.

**For arrow elements** (add these fields):
```json
{
  "type": "arrow",
  "points": [[0, 0], [200, 0]],
  "lastCommittedPoint": null,
  "startBinding": {"elementId": "source-box-id", "focus": 0, "gap": 2},
  "endBinding": {"elementId": "target-box-id", "focus": 0, "gap": 2},
  "startArrowhead": null,
  "endArrowhead": "arrow"
}
```
Arrow points are **relative** to the arrow's `x,y` origin. For a right-going arrow from `(x1, y1+40)` to `(x2, y2+40)`, set `x=x1+180, y=y1+40, points=[[0,0],[x2-x1-180, 0]]`.

When an arrow is bound, add `{"type": "arrow", "id": "<arrow-id>"}` to `boundElements` of both source and target boxes.

### Step Number Badges on Arrows

Place a step badge at the midpoint of each numbered arrow:

```json
// Circle badge
{
  "id": "step-1-circle",
  "type": "ellipse",
  "x": <arrow-midpoint-x - 16>,
  "y": <arrow-midpoint-y - 16>,
  "width": 32,
  "height": 32,
  "strokeColor": "#343a40",
  "backgroundColor": "#343a40",
  "fillStyle": "solid",
  "roundness": {"type": 2},
  ...base fields...
},
{
  "id": "step-1-label",
  "type": "text",
  "x": <arrow-midpoint-x - 8>,
  "y": <arrow-midpoint-y - 10>,
  "width": 20,
  "height": 20,
  "text": "1",
  "fontSize": 14,
  "fontFamily": 2,
  "textAlign": "center",
  "strokeColor": "#ffffff",
  "backgroundColor": "transparent",
  ...base fields...
}
```

### Zone / Group Bounding Box

For logical groupings (e.g., "Data Tier", "Application Tier"):

```json
{
  "id": "zone-data-tier",
  "type": "rectangle",
  "x": <leftmost-component-x - 40>,
  "y": <topmost-component-y - 50>,
  "width": <span of components + 80>,
  "height": <span of components + 90>,
  "strokeColor": "#adb5bd",
  "backgroundColor": "transparent",
  "fillStyle": "solid",
  "strokeWidth": 1,
  "strokeStyle": "dashed",
  "roundness": {"type": 3},
  ...base fields...
},
{
  "id": "zone-data-tier-label",
  "type": "text",
  "x": <zone-x + 10>,
  "y": <zone-y + 10>,
  "text": "Data Tier",
  "fontSize": 13,
  "fontFamily": 2,
  "textAlign": "left",
  "strokeColor": "#868e96",
  "backgroundColor": "transparent",
  ...base fields...
}
```

---

## Step 4 — Component Shapes by Type

### Standard Service Box (rectangle, rounded)
```
width: 180, height: 80
roundness: {"type": 3}
Two-line text: Line 1 = component name (bold via fontSize 16), Line 2 = type/role (fontSize 12)
```

### Database (rectangle, rounded — simulate cylinder with label)
```
width: 160, height: 80
backgroundColor: #f3d9fa, strokeColor: #862e9c
Text: "MySQL\n[Primary DB]"
```

### Cache (rectangle, rounded)
```
width: 160, height: 70
backgroundColor: #ffe3e3, strokeColor: #c92a2a
Text: "Redis\n[Cache]"
```

### Message Queue (rectangle, slightly wider)
```
width: 200, height: 80
backgroundColor: #fff9db, strokeColor: #f08c00
Text: "Kafka\n[Message Queue]"
```

### Client (ellipse or rectangle)
```
width: 120, height: 80
backgroundColor: #fff3bf, strokeColor: #e67700
Text: "Client\n[Browser/Mobile]"
```

### Load Balancer (hexagon simulation — use rectangle with label)
```
width: 160, height: 70
backgroundColor: #d3f9d8, strokeColor: #2f9e44
Text: "Load Balancer\n[Round Robin]"
```

---

## Step 5 — Title and Legend

**Title block** (top-left of canvas):
```json
{
  "type": "text",
  "x": 100,
  "y": 30,
  "text": "System Name — High-Level Design",
  "fontSize": 24,
  "fontFamily": 2,
  "textAlign": "left",
  "strokeColor": "#212529"
}
```

**Legend** (bottom-right, optional but recommended for complex diagrams):
Small colored squares (40×20) with text labels for each component type used.

---

## Step 6 — Output Instructions

1. Compute the **total canvas size** from component positions and add 200px margin.
2. Output the complete JSON to a file: `HLD/diagrams/<system-name>.excalidraw`
3. After writing, print a **one-line summary** of what was drawn: component count, layer count, step count.
4. Tell the user: **"Open in Excalidraw at excalidraw.com → File → Open → select the file"** or use the VS Code Excalidraw extension.

---

## Quality Checklist (run mentally before writing)

- [ ] Every arrow has a source and target binding (`startBinding`, `endBinding`)
- [ ] Every box that has arrows has those arrow IDs in its `boundElements`
- [ ] Every text-inside-box has `containerId` set to its container box
- [ ] Step numbers are on every primary-path arrow
- [ ] All `roughness` values are `0`
- [ ] All fonts are `fontFamily: 2` (Helvetica)
- [ ] Zone bounding boxes use `strokeStyle: "dashed"`
- [ ] Title is present at top-left
- [ ] Component colors match the palette table exactly
- [ ] No two components overlap (check x/y + width/height)
- [ ] Arrow points are relative (start from `[0,0]`)

---

## Example: Minimal Two-Component Diagram

```json
{
  "type": "excalidraw",
  "version": 2,
  "source": "https://excalidraw.com",
  "elements": [
    {
      "id": "client-box",
      "type": "rectangle",
      "x": 100, "y": 150,
      "width": 160, "height": 80,
      "angle": 0,
      "strokeColor": "#e67700", "backgroundColor": "#fff3bf",
      "fillStyle": "solid", "strokeWidth": 2, "strokeStyle": "solid",
      "roughness": 0, "opacity": 100,
      "groupIds": [], "frameId": null,
      "roundness": {"type": 3},
      "seed": 101, "version": 1, "versionNonce": 101,
      "isDeleted": false,
      "boundElements": [
        {"type": "text", "id": "client-label"},
        {"type": "arrow", "id": "arrow-1"}
      ],
      "updated": 1, "link": null, "locked": false
    },
    {
      "id": "client-label",
      "type": "text",
      "x": 100, "y": 150,
      "width": 160, "height": 80,
      "angle": 0,
      "strokeColor": "#e67700", "backgroundColor": "transparent",
      "fillStyle": "solid", "strokeWidth": 1, "strokeStyle": "solid",
      "roughness": 0, "opacity": 100,
      "groupIds": [], "frameId": null,
      "roundness": null,
      "seed": 102, "version": 1, "versionNonce": 102,
      "isDeleted": false,
      "boundElements": [],
      "updated": 1, "link": null, "locked": false,
      "text": "Client\n[Browser]",
      "fontSize": 16, "fontFamily": 2,
      "textAlign": "center", "verticalAlign": "middle",
      "containerId": "client-box",
      "originalText": "Client\n[Browser]",
      "lineHeight": 1.25
    },
    {
      "id": "api-box",
      "type": "rectangle",
      "x": 420, "y": 150,
      "width": 180, "height": 80,
      "angle": 0,
      "strokeColor": "#2f9e44", "backgroundColor": "#d3f9d8",
      "fillStyle": "solid", "strokeWidth": 2, "strokeStyle": "solid",
      "roughness": 0, "opacity": 100,
      "groupIds": [], "frameId": null,
      "roundness": {"type": 3},
      "seed": 201, "version": 1, "versionNonce": 201,
      "isDeleted": false,
      "boundElements": [
        {"type": "text", "id": "api-label"},
        {"type": "arrow", "id": "arrow-1"}
      ],
      "updated": 1, "link": null, "locked": false
    },
    {
      "id": "api-label",
      "type": "text",
      "x": 420, "y": 150,
      "width": 180, "height": 80,
      "angle": 0,
      "strokeColor": "#2f9e44", "backgroundColor": "transparent",
      "fillStyle": "solid", "strokeWidth": 1, "strokeStyle": "solid",
      "roughness": 0, "opacity": 100,
      "groupIds": [], "frameId": null,
      "roundness": null,
      "seed": 202, "version": 1, "versionNonce": 202,
      "isDeleted": false,
      "boundElements": [],
      "updated": 1, "link": null, "locked": false,
      "text": "API Gateway\n[Rate Limit + Auth]",
      "fontSize": 16, "fontFamily": 2,
      "textAlign": "center", "verticalAlign": "middle",
      "containerId": "api-box",
      "originalText": "API Gateway\n[Rate Limit + Auth]",
      "lineHeight": 1.25
    },
    {
      "id": "arrow-1",
      "type": "arrow",
      "x": 260, "y": 190,
      "width": 160, "height": 0,
      "angle": 0,
      "strokeColor": "#343a40", "backgroundColor": "transparent",
      "fillStyle": "solid", "strokeWidth": 2, "strokeStyle": "solid",
      "roughness": 0, "opacity": 100,
      "groupIds": [], "frameId": null,
      "roundness": {"type": 2},
      "seed": 301, "version": 1, "versionNonce": 301,
      "isDeleted": false,
      "boundElements": [],
      "updated": 1, "link": null, "locked": false,
      "points": [[0, 0], [160, 0]],
      "lastCommittedPoint": null,
      "startBinding": {"elementId": "client-box", "focus": 0, "gap": 2},
      "endBinding": {"elementId": "api-box", "focus": 0, "gap": 2},
      "startArrowhead": null,
      "endArrowhead": "arrow"
    },
    {
      "id": "step-1-circle",
      "type": "ellipse",
      "x": 324, "y": 174,
      "width": 32, "height": 32,
      "angle": 0,
      "strokeColor": "#343a40", "backgroundColor": "#343a40",
      "fillStyle": "solid", "strokeWidth": 2, "strokeStyle": "solid",
      "roughness": 0, "opacity": 100,
      "groupIds": [], "frameId": null,
      "roundness": {"type": 2},
      "seed": 401, "version": 1, "versionNonce": 401,
      "isDeleted": false,
      "boundElements": [{"type": "text", "id": "step-1-label"}],
      "updated": 1, "link": null, "locked": false
    },
    {
      "id": "step-1-label",
      "type": "text",
      "x": 324, "y": 174,
      "width": 32, "height": 32,
      "angle": 0,
      "strokeColor": "#ffffff", "backgroundColor": "transparent",
      "fillStyle": "solid", "strokeWidth": 1, "strokeStyle": "solid",
      "roughness": 0, "opacity": 100,
      "groupIds": [], "frameId": null,
      "roundness": null,
      "seed": 402, "version": 1, "versionNonce": 402,
      "isDeleted": false,
      "boundElements": [],
      "updated": 1, "link": null, "locked": false,
      "text": "1",
      "fontSize": 14, "fontFamily": 2,
      "textAlign": "center", "verticalAlign": "middle",
      "containerId": "step-1-circle",
      "originalText": "1",
      "lineHeight": 1.25
    }
  ],
  "appState": {
    "gridSize": null,
    "viewBackgroundColor": "#ffffff"
  },
  "files": {}
}
```

---

## Real-World Component Templates

Use these as the building blocks for any HLD:

### 3-Tier Web Application Layer Stack
```
Row 1 (y=80):   Client (x=100)
Row 2 (y=260):  DNS (x=100) → CDN (x=360) → Load Balancer (x=620)
Row 3 (y=440):  Web Server 1 (x=100), Web Server 2 (x=340), Web Server 3 (x=580)
Row 4 (y=620):  App Service (x=100), App Service (x=340), App Service (x=580)
Row 5 (y=800):  Primary DB (x=100), Replica DB (x=340), Redis Cache (x=580)
Row 6 (y=980):  Object Storage S3 (x=100), Message Queue Kafka (x=380)
```

### Read-Heavy System (with caching layer)
```
Row 1: Client
Row 2: CDN → API Gateway
Row 3: Read Service ←→ Redis Cache
Row 4: DB Primary → DB Replica → DB Replica
```

### Write-Heavy / Event-Driven System
```
Row 1: Clients (multiple)
Row 2: API Gateway
Row 3: Write Service → Kafka → Consumer 1, Consumer 2, Consumer 3
Row 4: Primary DB, Analytics DB, Notification Service
```

### Microservices with Service Mesh
```
Row 1: Client → API Gateway
Row 2: Service A, Service B, Service C, Service D
Row 3 (each service): Own DB (sidecar pattern — small DB next to each service)
Row 4: Shared Message Bus (Kafka, full width)
Row 5: Data Warehouse, Analytics, Monitoring
```
