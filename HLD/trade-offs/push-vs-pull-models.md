# Trade-off: Push vs Pull Models

**Category**: HLD · System Design · Architecture Decision  
**FAANG interview trigger**: "How would you design a notification system?" / "How does the news feed work?" / "How do you deliver updates to millions of subscribers?"

---

## Context

Push vs. pull is a fundamental design decision in distributed systems that appears in news feeds, notification systems, live dashboards, event delivery, and cache invalidation. The right answer depends on the ratio of producers to consumers, update frequency, and latency requirements.

---

## Definitions

**Push model**: the server sends data to clients proactively when updates occur. Clients are passive receivers. Examples: WebSocket notifications, email delivery, SSE (Server-Sent Events), Firebase Realtime Database.

**Pull model**: clients request data on a schedule or when they need it. Servers are passive providers. Examples: REST API polling, RSS, email clients checking IMAP, Prometheus scraping.

---

## Comparison

| Dimension | Push | Pull |
|-----------|------|------|
| **Latency** | Near-real-time (milliseconds) | Bounded by poll interval (seconds to minutes) |
| **Server load** | Proportional to events × subscribers (fan-out) | Proportional to subscribers × poll frequency |
| **Client complexity** | Lower — client waits for data | Higher — client manages polling schedule, deduplication |
| **Network connections** | Long-lived (WebSocket, SSE) — expensive to maintain | Short-lived (HTTP) — connection per request |
| **Offline clients** | Must buffer or drop events during downtime | Client catches up naturally on next poll |
| **Fan-out problem** | Severe for high-follower users (1 post → N pushes) | Absent — each client fetches their own view |
| **Consistency** | Eventual (delivery order not guaranteed without design) | Read-your-writes with appropriate headers |
| **Scalability** | Hard at extreme scale — millions of open connections | Easier to scale horizontally |

---

## When to Choose Push

**Choose push when:**

1. **Latency is critical**: messaging apps (WhatsApp, Slack), stock tickers, collaborative editing, live sports scores. Users expect updates within 1 second, not "the next time they refresh."

2. **Update frequency is unpredictable and sparse**: push is efficient when events are infrequent but must be delivered immediately when they occur. If you're pulling every second for an event that happens once per hour, 99.9% of polls are wasted.

3. **Mobile battery efficiency**: push (APNs, FCM) wakes the device only when there's a notification. Polling every 5 minutes drains battery, fails background restrictions, and hits rate limits.

4. **Many subscribers, few events**: a company-wide status page update — 1 event, 10,000 subscribers. Push delivers once to all; pull requires 10,000 polls at the next interval.

**Real examples**: Slack uses WebSockets for real-time message delivery. Firebase uses WebSocket push for its Realtime Database. Apple APNs and Google FCM push mobile notifications.

---

## When to Choose Pull

**Choose pull when:**

1. **Clients are unreliable or intermittently connected**: email is pull (IMAP/POP3) because your phone may be offline for hours. The server stores messages; the client fetches when online. A push server can't maintain persistent connections to billions of intermittently-connected devices.

2. **Tolerance for delay is high**: RSS readers, batch analytics dashboards, daily digest emails. Polling every 15 minutes is perfectly acceptable.

3. **Fan-out is extreme**: celebrity Twitter accounts with 100M followers. Pushing to 100M connections per tweet is infeasible. Pull (or hybrid fan-out) is required.

4. **Metrics collection (Prometheus model)**: monitoring systems pull metrics from targets on a scrape interval (15–60 seconds). This gives the monitoring system control over scrape rate and makes it resilient to individual service restarts — the target just needs to expose a `/metrics` endpoint.

5. **Simple operational model**: pull systems are easier to debug (you can curl the endpoint), easier to scale (just add servers), and have no long-lived connection state.

**Real examples**: Prometheus uses pull. RSS readers use pull. IMAP email uses pull. Git fetch/pull is a pull model.

---

## Hybrid: Fan-out on Write vs Fan-out on Read

For social network feeds (the canonical FAANG system design problem), neither pure push nor pure pull works at extreme scale. The solution is a hybrid based on user characteristics:

### Fan-out on Write (Push)
When a user posts, immediately write the post to the feed of every follower.

**Pro**: feed reads are O(1) — just read pre-computed results  
**Con**: a user with 10M followers triggers 10M write operations per post

**When it works**: users with low follower count (<10K). Most users on Twitter/Instagram/Facebook.

### Fan-out on Read (Pull)
When a user reads their feed, dynamically merge posts from everyone they follow.

**Pro**: no write amplification  
**Con**: feed reads are expensive — merge N sorted lists from N followees

**When it works**: celebrity accounts with millions of followers. You can't afford to write to 100M feeds.

### The Hybrid (Facebook/Twitter/Instagram approach)

1. For normal users (followers < threshold, e.g., 10K): fan-out on write — push to all follower feeds
2. For celebrities (followers ≥ threshold): fan-out on read — when loading the feed, pull celebrity posts separately and merge

```
User feed load:
  ├── Read pre-computed feed (from write fan-out for normal followees) → O(1)
  ├── For each followed celebrity: read their latest posts → O(celebrities × posts)
  └── Merge and rank results → O(N log N) where N = results
```

**Twitter's implementation**: Twitter uses this hybrid. "Big users" (Katy Perry, Barack Obama) are on read fan-out; everyone else is on write fan-out. The threshold is ~10K followers.

---

## Notification System Architecture

A notification system typically combines push (for real-time delivery) and pull (for notification history):

```
Event source → Notification Service → 
  ├── WebSocket push → active web clients (millisecond delivery)
  ├── APNs/FCM push → mobile devices (5-30 second delivery)
  └── Notification store (DB/Redis) → pull for notification history, unread counts
```

**Why both?**:
- Push: user sees the notification immediately if online
- Pull (notification store): user can see past notifications after returning from offline, see unread count, mark as read

**Delivery guarantee**: push is best-effort (WebSocket connection may drop). For guaranteed delivery, the event must also be stored and the client must pull the history on reconnect.

---

## Long-Polling (Middle Ground)

Long-polling is a pull mechanism that simulates push: the client makes a GET request; the server holds the connection open until there's an update (or a timeout), then responds. The client immediately makes another request.

```
Client → GET /updates?since=<timestamp>
Server holds request open (up to 30 seconds)
[Event occurs]
Server → 200 OK with update
Client immediately → GET /updates?since=<new_timestamp>
```

**When to use**: when WebSockets are not available (firewalls, proxies), for simple low-frequency update scenarios, or as a fallback for WebSocket failure.

**Problems**: each long-poll request holds a server thread (in blocking frameworks). With 100K concurrent long-polling clients, you need 100K threads or an async server (Node.js, Netty, asyncio).

---

## Connection Models for Push

| Protocol | Latency | Bidirectional | Browser Support | Best For |
|----------|---------|---------------|----------------|----------|
| **WebSocket** | Milliseconds | Yes | Full | Chat, gaming, collaborative apps |
| **SSE (Server-Sent Events)** | Milliseconds | No (server → client only) | Full | Live feeds, notifications |
| **Long-polling** | Seconds | Sort of | Full | Fallback, low-frequency |
| **HTTP/2 Server Push** | Milliseconds | No | Full | Pre-loading resources |
| **APNs/FCM** | 1–30 seconds | No | Mobile only | Mobile notifications |
| **gRPC streaming** | Milliseconds | Both | Limited (needs proxy) | Internal service-to-service |

---

## FAANG Interview Callouts

**Demonstrate this thinking:**
- "For the notification system, I'd push via WebSocket for active users (real-time delivery) and APNs/FCM for mobile. But I'd also write every notification to a `notifications` table so users can pull notification history when they open the notifications panel or after being offline."
- "For the news feed, pure fan-out on write gives O(1) reads but breaks for celebrity accounts. I'd use hybrid fan-out: write to follower feeds for normal users, pull from celebrity accounts at read time and merge."
- "Prometheus is a pull model by design — it gives the monitoring system control over scrape rate and avoids the need for every service to know the monitoring endpoint. The trade-off is a scrape-interval floor on alerting latency (~15-60 seconds), which is acceptable for infrastructure metrics but not for business SLO alerting."

**Red flags:**
- Designing a notification system with only push and no persistence — offline users lose notifications
- Recommending pure fan-out on write for Twitter (celebrity accounts make this infeasible)
- Not mentioning the connection scaling challenge for WebSocket push (10M concurrent connections ≠ 10M HTTP servers)
- Ignoring what happens when push delivery fails
