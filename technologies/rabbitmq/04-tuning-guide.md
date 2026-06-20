# RabbitMQ — Tuning Guide

## Broker Configuration (`rabbitmq.conf`)

### Memory and Disk (Most Critical)

```ini
# Memory: trigger flow control when broker uses > 40% of system RAM
# Recommendation: raise to 0.6 if broker is dedicated host; lower to 0.3 on shared hosts
vm_memory_high_watermark.relative = 0.4

# Disk: trigger alarm when free disk falls below this
# Default is 50MB — dangerously low. Raise to 1x RAM or at least 2GB.
disk_free_limit.relative = 1.0      # 1x system RAM (recommended)
# OR
disk_free_limit.absolute = 2GB      # minimum 2GB free

# Paging: start paging queue messages to disk when memory usage exceeds this fraction
# of the high watermark. Messages paged to disk are slower to deliver.
vm_memory_high_watermark_paging_ratio = 0.5
```

**Why this matters**: The default 50MB disk threshold causes the broker to block ALL publishers the moment disk drops below 50MB — too late to react operationally. At 1GB or 1x RAM, you get time to expand disk before the alarm triggers.

---

### Network and Connection Settings

```ini
# Heartbeat: detect stale connections. 60s is safe; lower for faster detection.
heartbeat = 60

# Max channels per connection (protocol ceiling: 65535, but AMQP default: 2047)
channel_max = 2047

# Max frame size in bytes (128KB default). Increase if sending messages > 128KB.
# Note: increasing frame_max does NOT mean you should send large messages.
frame_max = 131072

# Connection close timeout during shutdown (graceful drain)
consumer_timeout = 1800000   # 30 minutes (how long to wait for unacked messages on shutdown)
```

---

### Cluster Settings

```ini
# How long a node will wait for cluster peers on startup
cluster_formation.node_cleanup.only_log_warning = false
cluster_formation.peer_discovery_backend = rabbit_peer_discovery_classic_config

# Erlang distribution port (inter-node)
# Default: 25672. Change if firewall conflicts.
distribution_listener.port = 25672

# Enable mutual TLS between cluster nodes (production hardening)
cluster_ssl.cacertfile = /etc/rabbitmq/ssl/ca.crt
cluster_ssl.certfile   = /etc/rabbitmq/ssl/node.crt
cluster_ssl.keyfile    = /etc/rabbitmq/ssl/node.key
```

---

## Queue Configuration

### Quorum Queue Settings (Per-Queue via Policy)

```bash
# Set quorum queue replication factor (default: 3, i.e., all nodes in a 3-node cluster)
rabbitmqctl set_policy ha-all "^quorum\." \
  '{"queue-mode":"default","quorum-initial-group-size":3,"delivery-limit":5}' \
  --apply-to quorum_queues

# Key arguments when declaring quorum queue programmatically
Map<String, Object> args = new HashMap<>();
args.put("x-queue-type", "quorum");               // quorum queue
args.put("x-delivery-limit", 5);                  // max retries before dead-lettering
args.put("x-dead-letter-exchange", "dlx");        // DLX on max retry
args.put("x-dead-letter-strategy", "at-least-once"); // ensure DLX delivery
```

### Classic Queue Settings (Legacy)

```java
Map<String, Object> args = new HashMap<>();
args.put("x-message-ttl",   30_000);          // messages expire after 30 seconds
args.put("x-max-length",    100_000);         // max 100K messages; oldest dropped
args.put("x-max-length-bytes", 104_857_600); // max 100MB total queue size
args.put("x-overflow",      "reject-publish-dlx"); // dead-letter when overflow (vs drop)
args.put("x-dead-letter-exchange", "dlx");
args.put("x-dead-letter-routing-key", "dlq.orders");
args.put("x-queue-mode",    "lazy");           // page to disk immediately (for large queues)
```

### Queue TTL (x-expires)

```java
// Queue auto-deleted if unused for N milliseconds
args.put("x-expires", 3_600_000); // 1 hour; useful for ephemeral reply queues in RPC
```

---

## Consumer Tuning

### Prefetch (Most Important Consumer Setting)

```java
// Rule: set prefetch BEFORE basicConsume, not after.
// prefetch = 1: fair dispatch (task queues, variable processing time)
channel.basicQos(1, false);  // false = per-consumer (not per-channel)

// prefetch = 50: batch delivery (fast, uniform processing)
channel.basicQos(50, false);

// Per-channel global limit (applies to all consumers on this channel)
channel.basicQos(200, true);  // true = global per-channel
```

**Prefetch Calculator**:
```
Optimal prefetch ≈ (consumer throughput in msg/sec) × (round-trip latency in sec) × 1.5
Example: consumer processes 1000 msg/sec, RTT = 10ms
  prefetch = 1000 × 0.010 × 1.5 = 15
```

### Consumer Ack Strategy

```java
// CORRECT: manual ack with error handling
channel.basicConsume(queueName, false, (consumerTag, delivery) -> {
    try {
        processMessage(delivery.getBody());
        channel.basicAck(delivery.getEnvelope().getDeliveryTag(), false);
    } catch (RetryableException e) {
        // requeue for retry (risk: infinite loop — use DLX delivery-limit instead)
        channel.basicNack(delivery.getEnvelope().getDeliveryTag(), false, true);
    } catch (FatalException e) {
        // nack without requeue → DLX handles it
        channel.basicNack(delivery.getEnvelope().getDeliveryTag(), false, false);
    }
}, consumerTag -> {});

// WRONG: autoAck — message deleted before processing; loss on crash
channel.basicConsume(queueName, true, deliverCallback, cancelCallback);
```

### Consumer Connection Pooling

```java
// WRONG: one connection per message (TCP overhead)
for (Message m : messages) {
    try (Connection c = factory.newConnection()) { /* process */ }
}

// CORRECT: one connection per process, one channel per thread
Connection conn = factory.newConnection();          // once per application
ThreadLocal<Channel> channelPerThread = ThreadLocal.withInitial(() -> {
    try { return conn.createChannel(); }
    catch (IOException e) { throw new RuntimeException(e); }
});
```

---

## Producer Tuning

### Async Publisher Confirms with Batch Size

```java
// Optimal batch size: 100–1000 messages per confirm batch
// Smaller = more overhead; larger = more exposure on broker crash
int BATCH_SIZE = 200;
channel.confirmSelect();

int outstanding = 0;
for (Message msg : messagesToPublish) {
    channel.basicPublish(exchange, routingKey, props, msg.getBody());
    outstanding++;
    if (outstanding >= BATCH_SIZE) {
        channel.waitForConfirmsOrDie(5_000);  // 5 second timeout
        outstanding = 0;
    }
}
if (outstanding > 0) channel.waitForConfirmsOrDie(5_000);
```

### Mandatory Flag and Returned Messages

```java
// mandatory=true: broker returns message if no queue matches (vs silently dropping)
channel.basicPublish(exchange, routingKey, true /* mandatory */, false, props, body);

channel.addReturnListener(returnMessage -> {
    // Called if message was returned (no matching queue/binding)
    System.err.println("Message returned: " + returnMessage.getReplyText());
    handleReturnedMessage(returnMessage);
});
```

Without `mandatory=true`, a message published to an exchange with no matching binding is silently discarded. Use this in production for routing correctness validation.

---

## Connection Factory Settings

```java
ConnectionFactory factory = new ConnectionFactory();
factory.setHost("rabbitmq-cluster");
factory.setPort(5672);

// Heartbeat: must match server setting
factory.setRequestedHeartbeat(60);

// Connection recovery (auto-reconnect on broker failure)
factory.setAutomaticRecoveryEnabled(true);
factory.setNetworkRecoveryInterval(5_000);        // retry every 5 sec
factory.setTopologyRecoveryEnabled(true);         // redeclare exchanges/queues/bindings after recovery

// Channel max per connection
factory.setRequestedChannelMax(200);

// Connection timeout (fail fast rather than hang)
factory.setConnectionTimeout(10_000);             // 10 seconds

// TLS (production)
factory.useSslProtocol();
factory.enableHostnameVerification();
```

---

## Anti-Patterns

| Anti-Pattern | Impact | Fix |
|---|---|---|
| **Unlimited prefetch (default)** | One consumer monopolises the queue; others starve | Set `basicQos(1)` for task queues; 10–100 for fast consumers |
| **autoAck=true for task queues** | Message lost if consumer crashes mid-processing | Manual acks with `basicAck/Nack` |
| **No publisher confirms** | Silent message loss on broker crash | Enable `confirmSelect()` + async confirm listener |
| **Classic mirrored queues in production** | Data loss during failover (async mirror lag) | Migrate to quorum queues |
| **Queue depth growing unbounded** | Memory exhaustion → flow control → all publishers blocked | Set `x-max-length` and DLX; monitor queue depth |
| **Large messages (> 1MB)** | High memory usage; slow delivery; frame fragmentation | Store payload in S3; put reference URL in message body |
| **One connection per request** | TCP handshake overhead per message; connection exhaustion | One long-lived connection per process; channels per thread |
| **Sharing channels between threads** | Race conditions on AMQP frames; protocol errors | One channel per thread (channels are not thread-safe) |
| **Default disk alarm (50MB)** | Alarm triggers too late to react; sudden publisher block | Set `disk_free_limit.relative = 1.0` |
| **No DLX configured** | Failed messages silently discarded on nack | Always configure DLX for production queues |
| **Nack with requeue=true on poison messages** | Infinite retry loop; queue grows; broker overwhelmed | Use quorum queue `x-delivery-limit` + DLX for max retries |
| **RAM node in cluster** | All metadata lost on full cluster restart | Use disc nodes exclusively in production |
| **Not using TLS** | Credentials and messages transmitted in plaintext | Always use TLS (port 5671) in production |

---

## Monitoring Metrics

### Key Metrics to Alert On

| Metric | Healthy | Warning | Critical | Alert Condition |
|---|---|---|---|---|
| `rabbitmq_queue_messages` | < 1K | 1K–100K | > 500K | Consumer lag growing |
| `rabbitmq_queue_messages_ready` | ~ 0 (consumed quickly) | > 10K | > 100K | Consumers offline or slow |
| `rabbitmq_queue_messages_unacked` | ≤ prefetch × consumers | Growing | > 50K | Consumer not acking |
| `rabbitmq_node_mem_used` | < 30% | 30–40% | > 40% | Flow control imminent |
| `rabbitmq_node_disk_free` | > 5GB | < 2GB | < 1GB | Disk alarm risk |
| `rabbitmq_connections` | < 500 | 500–2K | > 5K | Connection leak |
| `rabbitmq_channels` | < 2K | 2K–10K | > 20K | Channel leak |
| Publish rate / Deliver rate | Balanced | Diverging | Publish >> Deliver | Queue growing |

### Prometheus + Grafana Stack

```bash
# Enable the Prometheus plugin
rabbitmq-plugins enable rabbitmq_prometheus

# Scrape endpoint
http://rabbitmq-node:15692/metrics

# Key Prometheus metric names
rabbitmq_queue_messages{queue="orders", vhost="/"}
rabbitmq_queue_messages_ready{queue="orders"}
rabbitmq_queue_messages_unacked{queue="orders"}
rabbitmq_node_mem_used
rabbitmq_node_disk_free
rabbitmq_connections_total
rabbitmq_channels_total
rabbitmq_consumers
```

### Management API (Quick Health Check)

```bash
# Queue depth for all queues
curl -u guest:guest http://localhost:15672/api/queues | jq '.[].messages'

# Node memory and disk
curl -u guest:guest http://localhost:15672/api/nodes | jq '.[].mem_used, .[].disk_free'

# Alarms
curl -u guest:guest http://localhost:15672/api/alarms
# Empty array [] = no alarms
# ["memory"] = memory alarm triggered
# ["disk"] = disk alarm triggered
```

---

## Capacity Planning

### Queue Memory Estimation

```
Memory per message ≈ message_size + 512 bytes (metadata overhead)
Queue RAM ≈ messages_in_flight × (message_size + 512)

Example: 100K messages × 2KB average = ~250MB RAM for that queue
Rule: keep total queue RAM below 40% of broker RAM
```

### Channel / Connection Estimation

```
Connections = services × instances × (1 connection per instance)
Channels    = services × instances × threads_per_instance
RAM per connection ≈ 100KB
RAM per channel    ≈ 2KB

Example: 50 services × 3 instances × 8 threads
  Connections: 50 × 3     = 150 (fine)
  Channels:    150 × 8    = 1,200 (fine, < 2047 per connection)
  Channel RAM: 1200 × 2KB = 2.4MB (negligible)
```

---

## FAANG Interview Callout

> "The three most impactful RabbitMQ tuning decisions are: (1) prefetch — default unlimited means one consumer buffers the entire queue; set it to 1 for task queues, 10–100 for fast consumers; (2) publisher confirms — without confirms, a broker crash silently drops messages in flight; use async confirms for throughput + safety; (3) disk alarm threshold — the default 50MB will trigger a sudden publisher block when you're already in trouble; set it to 1x RAM for operational reaction time. For queue design: always configure a DLX so that failed messages land somewhere observable rather than disappearing silently. And always use quorum queues — the throughput penalty (3x) is worth the data safety guarantee."

---

## Related Files

| File | Topic |
|---|---|
| [02-read-write-path.md](02-read-write-path.md) | Publisher confirms, prefetch, and flow control internals |
| [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) | Quorum vs classic trade-offs that inform tuning choices |
| [05-production-and-research.md](05-production-and-research.md) | Real-world operational lessons from production deployments |
