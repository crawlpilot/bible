# GraphQL — Deep Dive

## What Is GraphQL

GraphQL is a query language for APIs and a runtime for executing those queries. Created at Facebook (Meta) in 2012, open-sourced in 2015. Unlike REST where the server defines fixed response shapes, GraphQL lets clients declare exactly what data they need in a single request.

The core insight: different clients (web, mobile, TV) need different shapes of the same data. REST forces you to choose between over-fetching (too many fields) or multiple round-trips. GraphQL solves both.

---

## Core Concepts

### Schema — The Contract

```graphql
# Scalar types
scalar DateTime
scalar Money   # custom scalar

# Object types
type Order {
    id: ID!                      # ! = non-null
    status: OrderStatus!
    customer: Customer!          # resolved by CustomerResolver
    lines: [OrderLine!]!         # non-null list of non-null items
    total: Money!
    createdAt: DateTime!
    # deprecated field — clients told to use 'total' instead
    amount: Float @deprecated(reason: "Use 'total' field")
}

type Customer {
    id: ID!
    name: String!
    email: String!
    orders(first: Int, after: String): OrderConnection!  # paginated
}

type OrderLine {
    product: Product!
    quantity: Int!
    unitPrice: Money!
}

# Enum
enum OrderStatus {
    SUBMITTED
    CONFIRMED
    SHIPPED
    DELIVERED
    CANCELLED
}

# Pagination types (Relay connection spec)
type OrderConnection {
    edges: [OrderEdge]
    pageInfo: PageInfo!
    totalCount: Int!
}

type OrderEdge {
    node: Order!
    cursor: String!
}

type PageInfo {
    hasNextPage: Boolean!
    hasPreviousPage: Boolean!
    startCursor: String
    endCursor: String
}

# Union — result is one of multiple types
union SearchResult = Order | Customer | Product

# Interface — shared fields across types
interface Node {
    id: ID!
}
```

### Query — Read

```graphql
# Client specifies exactly what fields it needs
query GetOrderWithDetails($orderId: ID!) {
    order(id: $orderId) {
        id
        status
        createdAt
        customer {
            name
            email            # only name and email — not address, preferences, etc.
        }
        lines {
            quantity
            unitPrice
            product {
                id
                name
                sku
            }
        }
        total
    }
}

# Aliases — fetch same field with different args
query GetMultipleOrders {
    recentOrder: order(id: "ord_abc") {
        id
        status
    }
    oldOrder: order(id: "ord_xyz") {
        id
        status
    }
}

# Fragments — reusable field sets
fragment OrderSummary on Order {
    id
    status
    total
    createdAt
}

query GetOrders {
    pendingOrders: orders(status: SUBMITTED) {
        ...OrderSummary
    }
    shippedOrders: orders(status: SHIPPED) {
        ...OrderSummary
    }
}
```

### Mutation — Write

```graphql
# Mutations are named operations with side effects
mutation SubmitOrder($orderId: ID!) {
    submitOrder(id: $orderId) {
        id
        status
        updatedAt
    }
}

mutation CreateOrder($input: CreateOrderInput!) {
    createOrder(input: $input) {
        order {
            id
            status
        }
        errors {            # mutation errors in response body (not HTTP 4xx)
            field
            message
            code
        }
    }
}

# Input types — complex arguments
input CreateOrderInput {
    customerId: ID!
    lines: [OrderLineInput!]!
    paymentMethodId: ID!
}

input OrderLineInput {
    productId: ID!
    quantity: Int!
}
```

### Subscription — Real-Time

```graphql
subscription OnOrderStatusChange($orderId: ID!) {
    orderStatusChanged(id: $orderId) {
        id
        status
        updatedAt
    }
}
```

Subscriptions typically run over WebSocket. The client subscribes; the server pushes events when state changes.

---

## Resolvers

A resolver is the function that fetches data for a field. Each field in the schema can have a resolver.

```javascript
const resolvers = {
    Query: {
        // Root resolver for 'order' query
        order: async (parent, args, context) => {
            const { orderId } = args;
            const { user, dataSources } = context;
            
            // Authorization check
            if (!user.canViewOrders()) throw new AuthenticationError();
            
            return dataSources.orderService.getOrderById(orderId);
        },
    },

    Order: {
        // Field resolver — called once per Order in the result
        customer: async (order, args, context) => {
            // Without DataLoader: N queries for N orders
            // return context.dataSources.customerService.getById(order.customerId);
            
            // With DataLoader: 1 batch query for all N orders
            return context.loaders.customer.load(order.customerId);
        },

        lines: async (order, args, context) => {
            return context.loaders.orderLines.loadMany(order.lineIds);
        },
    },

    Mutation: {
        submitOrder: async (parent, { id }, context) => {
            return context.dataSources.orderService.submit(id);
        },
    },
};
```

---

## The N+1 Problem and DataLoader

The most critical performance problem in GraphQL.

```
Query:
  { orders { customer { name } } }

Naive resolver execution:
  1. Resolve orders → returns 20 orders [orderId: 1..20]
  2. For order 1: resolve customer(customerId: "cust_a") → 1 DB query
  3. For order 2: resolve customer(customerId: "cust_b") → 1 DB query
  ... 20 more queries
  Total: 1 + 20 = 21 DB queries

With DataLoader:
  1. Resolve orders → returns 20 orders
  2. For each order: DataLoader.load(customerId) → deferred, added to batch
  3. End of tick: DataLoader fires ONE batch: SELECT * FROM customers WHERE id IN (...)
  Total: 2 DB queries
```

```javascript
const { DataLoader } = require('dataloader');

// Create per-request (never singleton — each request needs a clean cache)
function createLoaders(db) {
    return {
        customer: new DataLoader(async (customerIds) => {
            // Batch fetch all requested customers in one query
            const customers = await db.customers.findManyByIds(customerIds);
            
            // DataLoader requires results in the same order as keys
            const customerMap = new Map(customers.map(c => [c.id, c]));
            return customerIds.map(id => customerMap.get(id) || null);
        }),

        orderLines: new DataLoader(async (lineIdArrays) => {
            const allIds = lineIdArrays.flat();
            const lines = await db.orderLines.findManyByIds(allIds);
            // Group lines back by their order
            return lineIdArrays.map(ids => lines.filter(l => ids.includes(l.id)));
        }),
    };
}

// Add to context per request
app.use('/graphql', graphqlHTTP(async (req) => ({
    schema,
    context: {
        user: req.user,
        loaders: createLoaders(db),  // NEW DataLoader per request
    },
})));
```

**DataLoader is not optional.** Every production GraphQL server must use it.

---

## Query Complexity and Depth Limits

Without limits, a malicious or careless client can write a query that generates millions of DB calls.

```graphql
# Recursive explosion — each order has customers, each customer has orders, etc.
{
    orders {
        customer {
            orders {
                customer {
                    orders {
                        customer { name }
                    }
                }
            }
        }
    }
}
```

### Depth Limit

```javascript
const depthLimit = require('graphql-depth-limit');

const server = new ApolloServer({
    schema,
    validationRules: [depthLimit(7)],  // max 7 levels of nesting
});
```

### Query Complexity Scoring

```javascript
const { createComplexityLimitRule } = require('graphql-validation-complexity');

// Assign cost to each field type
const complexityLimit = createComplexityLimitRule(1000, {
    scalarCost: 1,
    objectCost: 2,
    listFactor: 10,   // list fields multiply cost by 10
});

const server = new ApolloServer({
    validationRules: [complexityLimit],
});
```

### Persisted Queries (production best practice)

```javascript
// Client sends a hash of the query (pre-registered)
// Server only executes known queries — prevents arbitrary query injection
const persistedQueries = {
    'sha256:abc123...': `query GetOrder($id: ID!) { order(id: $id) { id status } }`,
};

// Request: { "id": "sha256:abc123...", "variables": { "id": "ord_1" } }
// Server looks up the query by hash — unknown hashes are rejected
```

---

## Error Handling

GraphQL always returns HTTP 200. Errors appear in the `errors` array alongside partial `data`.

```json
{
  "data": {
    "order": {
      "id": "ord_abc123",
      "status": "SUBMITTED",
      "customer": null   // ← resolver failed; error below
    }
  },
  "errors": [
    {
      "message": "Customer service unavailable",
      "locations": [{ "line": 4, "column": 5 }],
      "path": ["order", "customer"],
      "extensions": {
        "code": "SERVICE_UNAVAILABLE",
        "service": "customer-service",
        "requestId": "a8b3c4d5"
      }
    }
  ]
}
```

**Partial results are a feature**: if one resolver fails but others succeed, clients get whatever data is available. This is more resilient than REST where one downstream failure causes the entire response to fail.

### Error Classification

```javascript
// Don't expose internal errors to clients
class AuthenticationError extends ApolloError {
    constructor(message) {
        super(message, 'UNAUTHENTICATED');  // safe to expose
    }
}

class ForbiddenError extends ApolloError {
    constructor(message) {
        super(message, 'FORBIDDEN');
    }
}

// In resolver
throw new AuthenticationError('Token expired');
// → extensions.code: "UNAUTHENTICATED" (exposed to client)
// Internal stack traces are logged server-side but NOT sent to client
```

---

## Pagination — Relay Connection Spec

The de-facto standard for GraphQL pagination. Cursor-based.

```graphql
type Query {
    orders(
        first: Int          # forward pagination: first N after cursor
        after: String       # cursor
        last: Int           # backward pagination: last N before cursor
        before: String      # cursor
        filter: OrderFilter
        orderBy: OrderSort
    ): OrderConnection!
}

# Query
query {
    orders(first: 20, after: "cursor_abc") {
        edges {
            cursor
            node {
                id
                status
            }
        }
        pageInfo {
            hasNextPage
            endCursor
        }
        totalCount
    }
}
```

---

## Apollo Federation — GraphQL at Scale

At FAANG scale, one monolithic GraphQL schema owned by one team is a bottleneck. Federation lets each team own part of the schema.

```
                        ┌─────────────────────┐
Client ──GraphQL──▶     │   Apollo Gateway     │   (supergraph)
                        │   (composition layer)│
                        └──────────┬──────────┘
                                   │ routes by entity type
                    ┌──────────────┼──────────────┐
                    ▼              ▼              ▼
            ┌──────────┐  ┌──────────┐  ┌──────────┐
            │  Orders  │  │Customers │  │Inventory │
            │  Subgraph│  │ Subgraph │  │ Subgraph │
            └──────────┘  └──────────┘  └──────────┘
```

```graphql
# Orders subgraph — owns Order type, extends Customer
type Order @key(fields: "id") {
    id: ID!
    customerId: ID!
    status: OrderStatus!
}

# Customer subgraph — owns Customer type
type Customer @key(fields: "id") {
    id: ID!
    name: String!
    email: String!
}

# Orders subgraph — extends Customer to add 'orders' field
extend type Customer @key(fields: "id") {
    id: ID! @external
    orders: [Order!]!
}
```

The gateway merges subgraph schemas into a supergraph. Teams own their subgraphs independently. The gateway routes query fragments to the right subgraph and assembles the result.

**Used at**: Expedia, Netflix (for some APIs), Wayfair, Xfinity.

---

## GraphQL vs REST: Trade-offs

| Dimension | GraphQL | REST |
|---|---|---|
| **Over/under-fetching** | Eliminated — client asks for exactly what it needs | Common; fixed response shapes |
| **N+1 DB queries** | Risk without DataLoader; solved with DataLoader | Not a problem in REST resolvers |
| **Caching** | Complex — HTTP GET caching doesn't apply to POST queries; needs client-side Apollo cache or persisted queries | HTTP-native: CDN, ETags, Cache-Control |
| **Error model** | Always HTTP 200; errors in body — breaks standard observability | HTTP status codes; 4xx/5xx trigger alerts |
| **Rate limiting** | Complexity-based (hard to implement); can't use simple request counting | Simple: requests-per-second per API key |
| **File uploads** | Awkward (multipart spec non-standard) | Straightforward multipart POST |
| **Schema evolution** | @deprecated directive; additive-only safe | URL versioning or header versioning |
| **Tooling** | GraphiQL, Apollo Studio, Apollo DevTools | Postman, curl, Swagger UI |
| **Learning curve** | Higher (schema, resolvers, DataLoader, Federation) | Low |
| **Client flexibility** | Very high — clients own queries | Low — server defines response shape |
| **Security** | Query injection risk; needs depth/complexity limits | Standard input validation |

---

## When to Use GraphQL

**Use GraphQL when:**
- Multiple clients (web, iOS, Android, TV) need different shapes of the same data
- Frontend teams want to move independently without backend API changes for each UI feature
- The data model is a graph: many relationships between entity types
- N+1 is unavoidable in REST because clients always need related data together

**Don't use GraphQL when:**
- Simple CRUD service with uniform consumers — REST is simpler
- The API is server-to-server internal — use gRPC for performance
- CDN caching is critical — GraphQL queries aren't GET-cacheable by default
- The team lacks GraphQL expertise and query security discipline (depth limits, complexity limits, persisted queries)
- File upload is a primary use case

---

## FAANG Usage

| Company | How They Use GraphQL |
|---|---|
| **Meta** | Invented it. News Feed, React Native app, Graph API for Platform |
| **GitHub** | API v4 is GraphQL. Replaced REST v3 for rich queries (PR + reviews + files in one call) |
| **Shopify** | Storefront API and Admin API (v2) are GraphQL |
| **Twitter** | Internal GraphQL for some client-side data fetching |
| **Netflix** | Studio apps use GraphQL for complex relationship queries across catalogue data |
| **Airbnb** | Replaced REST endpoints for search and listing views with GraphQL |

---

## FAANG Interview Callouts

**"How does Meta serve News Feed to different clients efficiently?"**
GraphQL. Web, iOS, and Android all query the same schema but request different fields. The server resolves what each client needs from multiple microservices in one query. DataLoader batches DB calls. Federation distributes schema ownership across teams (Friends team owns social graph, Ads team owns ad targeting, etc.).

**"What's the N+1 problem in GraphQL and how do you fix it?"**
If a query returns 20 orders and each order has a `customer` field, a naive resolver fires 20 separate `SELECT * FROM customers WHERE id = ?` queries — one per order. DataLoader collects all `customer.load(id)` calls within a single event loop tick, then fires one batch `SELECT * FROM customers WHERE id IN (...)` query. The resolver API is unchanged; DataLoader is injected through context.

**"How would you secure a public GraphQL API?"**
Four layers: (1) Persisted queries — only execute pre-registered query hashes, rejecting arbitrary queries; (2) Depth limits — reject queries beyond 7 levels of nesting; (3) Complexity scoring — assign cost to each field type, reject queries scoring above a threshold; (4) Rate limiting per client on complexity cost, not just request count. Additionally: auth in context (not resolvers), field-level authorization via directive (`@auth(requires: ADMIN)`).
