# Pub/Sub & Streams — Redis Reference

Two distinct messaging mechanisms:
- **Pub/Sub**: Fire-and-forget broadcast. No persistence. Subscribers must be connected to receive.
- **Streams**: Persistent, append-only log. Consumer groups. Messages survive Redis restarts. The right choice for reliable messaging.

---

## PUB/SUB Quick Reference

| Command | Syntax | Returns | Complexity | Notes |
|---------|--------|---------|-----------|-------|
| SUBSCRIBE | `SUBSCRIBE channel [channel ...]` | stream of messages | O(N) | Enters subscriber mode |
| UNSUBSCRIBE | `UNSUBSCRIBE [channel ...]` | stream of messages | O(N) | No args = unsubscribe all |
| PSUBSCRIBE | `PSUBSCRIBE pattern [pattern ...]` | stream of messages | O(N) | Glob pattern: `news.*`, `user:*:events` |
| PUNSUBSCRIBE | `PUNSUBSCRIBE [pattern ...]` | stream of messages | O(N) | |
| PUBLISH | `PUBLISH channel message` | integer (subscribers) | O(N) | N = subscribers to channel |
| PUBSUB CHANNELS | `PUBSUB CHANNELS [pattern]` | array | O(N) | List active channels |
| PUBSUB NUMSUB | `PUBSUB NUMSUB [channel ...]` | pairs | O(N) | Subscriber count per channel |
| PUBSUB NUMPAT | `PUBSUB NUMPAT` | integer | O(1) | Pattern subscription count |
| PUBSUB SHARDCHANNELS | `PUBSUB SHARDCHANNELS [pattern]` | array | O(N) | Redis 7.0+ cluster sharded |
| SSUBSCRIBE | `SSUBSCRIBE channel [channel ...]` | stream | O(N) | Redis 7.0+ sharded pub/sub |
| SUNSUBSCRIBE | `SUNSUBSCRIBE [channel ...]` | stream | O(N) | Redis 7.0+ |
| SPUBLISH | `SPUBLISH channel message` | integer | O(N) | Redis 7.0+ sharded pub/sub |

---

## Pub/Sub Usage

```bash
# --- Terminal 1: Subscribe ---
redis-cli SUBSCRIBE seat-updates:SHOW_001
# Enters listen mode — blocks until Ctrl+C
# Messages received as:
# 1) "message"
# 2) "seat-updates:SHOW_001"
# 3) "{\"seats\":[{\"id\":\"A1\",\"status\":\"LOCKED\"}]}"

# --- Terminal 2: Pattern subscribe ---
redis-cli PSUBSCRIBE "seat-updates:*"    # all shows
redis-cli PSUBSCRIBE "user:*:events"     # any user's events

# --- Terminal 3: Publish ---
redis-cli PUBLISH seat-updates:SHOW_001 '{"seats":[{"id":"A1","status":"LOCKED"}]}'
# → 2  (2 subscribers received the message)

# Publish to pattern-matched subscribers
redis-cli PUBLISH user:42:events "login"
```

---

## Inspect Active Subscriptions

```bash
# List channels with at least one subscriber
PUBSUB CHANNELS             # all active channels
PUBSUB CHANNELS "seat-*"    # filtered by pattern

# Subscriber count per named channel
PUBSUB NUMSUB seat-updates:SHOW_001 seat-updates:SHOW_002
# → 1) "seat-updates:SHOW_001"
#    2) (integer) 15
#    3) "seat-updates:SHOW_002"
#    4) (integer) 3

# Total pattern subscriptions
PUBSUB NUMPAT               # → 2
```

---

## Pub/Sub Limitations

```
Messages are NOT persisted — if subscriber is offline, message is lost
No acknowledgement — publisher has no way to confirm delivery
No consumer groups — all subscribers receive every message
Cluster: channel hashes to a single slot — all subscribers must be on that shard
  Use SSUBSCRIBE/SPUBLISH for cluster-native sharded pub/sub (Redis 7.0+)
In subscriber mode, only SUBSCRIBE/UNSUBSCRIBE/PING/RESET/QUIT are allowed
Connection drop = missed messages; reconnect requires full re-subscribe
```

---

---

## STREAMS Quick Reference

| Command | Syntax | Returns | Complexity | Notes |
|---------|--------|---------|-----------|-------|
| XADD | `XADD key [NOMKSTREAM] [MAXLEN [~] n] [MINID [~] id] *\|id field val [field val...]` | entry-id | O(1) | `*` = auto-generate ID |
| XLEN | `XLEN key` | integer | O(1) | Entry count |
| XRANGE | `XRANGE key start end [COUNT n]` | entries | O(N) | Ascending; `-` = min, `+` = max |
| XREVRANGE | `XREVRANGE key end start [COUNT n]` | entries | O(N) | Descending |
| XREAD | `XREAD [COUNT n] [BLOCK ms] STREAMS key [key...] id [id...]` | entries | O(N) | `$` = only new messages |
| XTRIM | `XTRIM key MAXLEN [~] n` | trimmed count | O(N) | ~ = approximate (faster) |
| XDEL | `XDEL key id [id...]` | deleted count | O(N) | Creates tombstone, doesn't reclaim space |
| XINFO STREAM | `XINFO STREAM key [FULL [COUNT n]]` | info map | O(N) | |
| XINFO GROUPS | `XINFO GROUPS key` | array | O(N) | |
| XINFO CONSUMERS | `XINFO CONSUMERS key group` | array | O(N) | |
| XGROUP CREATE | `XGROUP CREATE key group id [MKSTREAM] [ENTRIESREAD n]` | OK | O(1) | `$` = start from latest, `0` = from beginning |
| XGROUP CREATECONSUMER | `XGROUP CREATECONSUMER key group consumer` | 0 or 1 | O(1) | Pre-create consumer |
| XGROUP DELCONSUMER | `XGROUP DELCONSUMER key group consumer` | PEL count | O(N) | |
| XGROUP DESTROY | `XGROUP DESTROY key group` | 0 or 1 | O(N) | |
| XGROUP SETID | `XGROUP SETID key group id` | OK | O(1) | Reset consumer group cursor |
| XREADGROUP | `XREADGROUP GROUP group consumer [COUNT n] [BLOCK ms] [NOACK] STREAMS key [key...] id [id...]` | entries | O(N) | `>` = get undelivered; id = re-read PEL |
| XACK | `XACK key group id [id...]` | acknowledged count | O(N) | Remove from PEL |
| XPENDING | `XPENDING key group [[IDLE ms] start end count [consumer]]` | PEL entries | O(N) | Pending (unacked) messages |
| XCLAIM | `XCLAIM key group consumer min-idle-ms id [id...] [TIME ms] [RETRYCOUNT n] [FORCE] [JUSTID]` | entries | O(N) | Transfer PEL ownership |
| XAUTOCLAIM | `XAUTOCLAIM key group consumer min-idle-ms start [COUNT n] [JUSTID]` | [cursor, entries, deleted] | O(N) | Redis 6.2+; auto-reassign idle messages |

---

## Basic Stream Produce and Consume

```bash
# --- Producer ---
# Add entry; * = auto-generate ID (timestamp-sequence)
XADD events:orders * event_type "ORDER_PLACED" order_id "ord_abc" user_id "42"
# → "1717890000000-0"   ← generated ID: {ms}-{seq}

# Add with explicit ID (must be monotonically increasing)
XADD events:orders 1717890001000-0 event_type "PAYMENT_OK" order_id "ord_abc"

# Cap stream length (keep last 1000 entries)
XADD events:orders MAXLEN 1000 * event_type "SHIPPED" order_id "ord_abc"
XADD events:orders MAXLEN ~ 1000 * event_type "DELIVERED"  # ~ = approx trim (faster)

# Stream length
XLEN events:orders                    # → 4

# --- Consumer (simple, no consumer groups) ---
# Read from beginning
XRANGE events:orders - +
# → 1) 1) "1717890000000-0"
#       2) 1) "event_type"  2) "ORDER_PLACED"  3) "order_id"  4) "ord_abc"

# Read with count limit
XRANGE events:orders - + COUNT 10

# Read in reverse
XREVRANGE events:orders + - COUNT 5

# Read entries AFTER a specific ID
XRANGE events:orders 1717890000000-0 +

# Blocking read: wait for new entries (like tail -f)
XREAD COUNT 10 BLOCK 5000 STREAMS events:orders $
# $ = only entries added AFTER this command; 5000ms timeout
# → nil if no new entries within timeout
```

---

## Consumer Groups — Reliable Delivery

```bash
# Create consumer group (start from beginning '0', or from now '$')
XGROUP CREATE events:orders notification-svc 0 MKSTREAM
# MKSTREAM: create stream if doesn't exist
# 0 = process all existing messages
# $ = only new messages from this point forward

# --- Consumer worker reads ---
# '>' means: give me messages not yet delivered to any consumer in this group
XREADGROUP GROUP notification-svc worker-1 COUNT 10 BLOCK 2000 STREAMS events:orders >
# → 1) 1) "events:orders"
#       2) 1) 1) "1717890000000-0"
#               2) 1) "event_type"  2) "ORDER_PLACED"  ...

# Process the message... then acknowledge
XACK events:orders notification-svc 1717890000000-0
# → 1  (acknowledged 1 message, removed from PEL)

# Acknowledge multiple
XACK events:orders notification-svc 1717890000000-0 1717890001000-0
```

---

## PEL — Pending Entry List (Unacked Messages)

```bash
# List all pending messages in the group
XPENDING events:orders notification-svc - + 10
# → 1) 1) "1717890002000-0"    ← message ID
#       2) "worker-1"           ← consumer who received it
#       3) (integer) 45000      ← ms since last delivery
#       4) (integer) 1          ← delivery count

# Show pending idle more than 30s (for re-routing stale)
XPENDING events:orders notification-svc IDLE 30000 - + 10

# Re-claim a message stuck with worker-1 (idle > 60s) and give to worker-2
XCLAIM events:orders notification-svc worker-2 60000 1717890002000-0

# Auto-claim all idle > 60s, starting from '0-0' (Redis 6.2+)
XAUTOCLAIM events:orders notification-svc worker-2 60000 0-0 COUNT 50
# → 1) "0-0"         ← next cursor (0-0 = all processed)
#    2) [claimed entries]
#    3) [deleted IDs] (messages that no longer exist)
```

---

## Stream Inspection

```bash
XINFO STREAM events:orders
# → length, groups, first/last entry, radix-tree size, etc.

XINFO STREAM events:orders FULL COUNT 2    # detailed view with PEL

XINFO GROUPS events:orders
# → group name, consumers, pending count, last-delivered-id

XINFO CONSUMERS events:orders notification-svc
# → consumer name, pending count, idle time
```

---

## Trim Strategies

```bash
# MAXLEN: keep at most N entries (approximate for performance)
XTRIM events:orders MAXLEN ~ 10000     # keep ~10K most recent

# MINID: keep entries with ID >= minid (time-based trim)
# Keep last 7 days (ID is timestamp-based)
XTRIM events:orders MINID 1717200000000   # trim entries older than this ms timestamp

# Auto-trim on add (preferred — avoids separate XTRIM call)
XADD events:orders MAXLEN ~ 10000 * field val

# Delete a specific entry (tombstone — doesn't free memory immediately)
XDEL events:orders 1717890000000-0
```

---

## Pub/Sub vs Streams Decision

| Concern | Pub/Sub | Streams |
|---------|---------|---------|
| Persistence | No | Yes (survives restart) |
| Consumer groups | No | Yes (XREADGROUP) |
| Message replay | No | Yes (XRANGE from any ID) |
| Fan-out to multiple consumers | Yes (all subscribers) | One consumer per group gets each message |
| Delivery guarantee | At-most-once (fire-and-forget) | At-least-once (PEL + ACK) |
| Backpressure / slow consumer | No (messages dropped) | Yes (PEL fills up, slows producer) |
| Latency | Sub-ms | Low ms |
| Use case | Real-time seat map updates to WebSocket clients | Booking events, payment confirmations, email queue |

**Rule**: Use **Pub/Sub** for ephemeral real-time fan-out (seat status to browsers). Use **Streams** when you need durable delivery, consumer groups, or message replay.

---

→ **See also**: [08-transactions-scripting.md](08-transactions-scripting.md) for Lua atomic operations | [10-patterns-recipes.md](10-patterns-recipes.md) for pub/sub fan-out pattern
