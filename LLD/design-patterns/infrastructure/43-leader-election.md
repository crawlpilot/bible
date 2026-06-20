# 43. Leader Election
**Category**: Infrastructure / Distributed Systems  
**GoF**: No  
**Complexity**: High  
**Frequency in FAANG interviews**: Common

> In a cluster of N identical nodes, ensure exactly one node — the leader — is responsible for coordinating work (shard assignment, scheduled jobs, lock holding) at any point in time. When the leader fails, the remaining nodes elect a new leader automatically and within a bounded time.

---

## Problem It Solves

A distributed scheduler runs on 10 identical pods. Without leader election: all 10 pods attempt to run the same cron job at the same time → 10× duplicate emails, 10× DB writes, race conditions on shared state. With leader election: exactly one pod is the leader and runs the job; the other 9 stand by. When the leader pod is killed, one standby is elected within seconds.

Leader election is needed whenever: a cluster performs a single-writer operation, shard assignments must be consistent, distributed locks must be held, or a primary-secondary replication model is used.

## Structure (Participants)

```
  Cluster nodes: [Node-1, Node-2, Node-3, Node-4, Node-5]
                                 │
                         LeaderElection
                         ┌──────────────────────────────────┐
                         │  Candidate: try to acquire lock  │
                         │  Leader:    hold lock + heartbeat │
                         │  Follower:  watch for leader loss │
                         └──────────────────────────────────┘
                                 │
                   ┌─────────────┴──────────────┐
                   ▼                            ▼
            Coordination Store          Leader Callbacks
            (ZooKeeper / etcd /         (onElected / onRevoked)
             Redis / DB)
```

Key participants:
- **Candidate**: any node attempting to become leader
- **Leader**: the node holding the exclusive lease; performs leader-only work
- **Follower**: monitors the leader; ready to take over
- **Coordination Store**: provides the atomic compare-and-swap or ephemeral node semantics needed for safe election
- **Lease / Heartbeat**: the leader periodically renews its lease; expiry triggers a new election

---

## Real-World Use Case: Distributed Job Scheduler

Spring Batch / Quartz cluster: exactly one pod should trigger `DailyReportJob` at 02:00. Other pods must stand by. On pod crash, a standby takes over within 5 seconds.

### Implementation: Lease-Based Leader Election

The core invariant: **one atomic operation creates the lease**. All candidates race to create the same key; only one wins.

```java
// Leader election configuration
public record LeaderConfig(
    String  nodeId,          // unique identifier for this node (pod name / UUID)
    String  leaseKey,        // shared key in the coordination store
    Duration leaseDuration,  // how long the lease is valid
    Duration renewInterval,  // how often leader renews (must be << leaseDuration)
    Duration retryInterval   // how often followers retry for the lease
) {}

// Callbacks invoked on leader transitions
public interface LeaderCallbacks {
    void onElected();   // this node became leader — start leader-only work
    void onRevoked();   // this node lost leadership — stop leader-only work
}

// Lease state held by current leader
public record LeaderLease(
    String  holderId,
    Instant acquiredAt,
    Instant expiresAt,
    long    term          // monotonically increasing — prevents stale leaders
) {}

// ─── Redis-backed implementation ─────────────────────────────────────────────

public class RedisLeaderElection implements AutoCloseable {
    private final RedisTemplate<String, String> redis;
    private final LeaderConfig   config;
    private final LeaderCallbacks callbacks;
    private final ScheduledExecutorService scheduler;

    private volatile boolean isLeader = false;
    private volatile long    currentTerm = 0;

    public RedisLeaderElection(RedisTemplate<String, String> redis,
                                LeaderConfig config,
                                LeaderCallbacks callbacks) {
        this.redis     = redis;
        this.config    = config;
        this.callbacks = callbacks;
        this.scheduler = Executors.newSingleThreadScheduledExecutor(r -> {
            Thread t = new Thread(r, "leader-election-" + config.nodeId());
            t.setDaemon(true);
            return t;
        });
    }

    public void start() {
        // Run election loop: try to acquire lease if not leader; renew if leader
        scheduler.scheduleAtFixedRate(this::electionCycle,
            0, config.retryInterval().toMillis(), TimeUnit.MILLISECONDS);
    }

    private void electionCycle() {
        try {
            if (isLeader) {
                renewLease();
            } else {
                tryAcquireLease();
            }
        } catch (Exception e) {
            log.error("Election cycle error on node {}", config.nodeId(), e);
            if (isLeader) {
                // Conservative: if we can't renew, step down
                stepDown();
            }
        }
    }

    private void tryAcquireLease() {
        // SET NX EX — atomic: only one node succeeds
        String leaseValue = config.nodeId() + ":" + (currentTerm + 1);
        Boolean acquired = redis.opsForValue().setIfAbsent(
            config.leaseKey(),
            leaseValue,
            config.leaseDuration()
        );

        if (Boolean.TRUE.equals(acquired)) {
            currentTerm++;
            isLeader = true;
            log.info("Node {} elected leader for term {}", config.nodeId(), currentTerm);
            callbacks.onElected();
        }
    }

    private void renewLease() {
        String leaseValue = config.nodeId() + ":" + currentTerm;
        // Lua: only renew if WE still hold the lease (prevents renewing after losing it)
        String luaScript = """
            if redis.call('get', KEYS[1]) == ARGV[1] then
                redis.call('pexpire', KEYS[1], ARGV[2])
                return 1
            else
                return 0
            end
            """;

        Long result = redis.execute(
            new DefaultRedisScript<>(luaScript, Long.class),
            List.of(config.leaseKey()),
            leaseValue,
            String.valueOf(config.leaseDuration().toMillis())
        );

        if (result == null || result == 0) {
            // Someone else took the lease — we lost leadership
            log.warn("Node {} lost lease for term {} — another node took over",
                config.nodeId(), currentTerm);
            stepDown();
        }
    }

    private void stepDown() {
        isLeader = false;
        callbacks.onRevoked();
    }

    public boolean isLeader() { return isLeader; }

    @Override
    public void close() {
        scheduler.shutdown();
        if (isLeader) {
            // Release lease voluntarily — fast failover instead of waiting for expiry
            String leaseValue = config.nodeId() + ":" + currentTerm;
            redis.execute(
                new DefaultRedisScript<>("if redis.call('get',KEYS[1])==ARGV[1] then return redis.call('del',KEYS[1]) else return 0 end", Long.class),
                List.of(config.leaseKey()),
                leaseValue
            );
            stepDown();
        }
    }
}

// ─── ZooKeeper-backed implementation (ephemeral nodes) ───────────────────────

public class ZookeeperLeaderElection implements LeaderLatch.Listener {
    private final CuratorFramework curator;
    private final LeaderLatch      latch;
    private final LeaderCallbacks  callbacks;

    public ZookeeperLeaderElection(CuratorFramework curator,
                                    String lockPath,
                                    LeaderCallbacks callbacks) {
        this.curator   = curator;
        // LeaderLatch uses ZK ephemeral sequential nodes: /election/lock-0000000001
        // The node with the lowest sequence number is the leader.
        // On disconnect, ZK deletes ephemeral nodes → automatic failover.
        this.latch     = new LeaderLatch(curator, lockPath);
        this.callbacks = callbacks;
        latch.addListener(this);
    }

    public void start() throws Exception {
        latch.start();
    }

    @Override
    public void isLeader() {
        log.info("This node became ZK leader");
        callbacks.onElected();
    }

    @Override
    public void notLeader() {
        log.info("This node lost ZK leadership");
        callbacks.onRevoked();
    }
}

// ─── etcd-backed implementation ──────────────────────────────────────────────
//
// etcd lease-based: PUT /leader/<leaseId> with TTL
// Renew via KeepAlive gRPC stream
// Watch /leader/ prefix — any change triggers re-election
//
// Advantage over Redis: etcd uses Raft internally → linearizable reads/writes
// No split-brain: if etcd quorum is lost, election stalls (safe, not live)

// ─── Application integration ─────────────────────────────────────────────────

@Component
public class DistributedScheduler implements LeaderCallbacks {
    private final RedisLeaderElection election;
    private final JobScheduler        scheduler;
    private ScheduledFuture<?>        jobHandle;

    @Override
    public void onElected() {
        log.info("Elected leader — starting scheduled jobs");
        // Start all leader-only work
        jobHandle = scheduler.schedule(this::runDailyReport,
            nextOccurrence(LocalTime.of(2, 0)), ChronoUnit.DAYS);
    }

    @Override
    public void onRevoked() {
        log.info("Lost leadership — stopping scheduled jobs");
        if (jobHandle != null) jobHandle.cancel(false);
    }

    private void runDailyReport() {
        // Guard: double-check we are still leader before doing expensive work
        // (there is a small window between revocation and job cancellation)
        if (!election.isLeader()) {
            log.warn("Skipping job — no longer the leader");
            return;
        }
        reportService.generateDailyReport();
    }
}
```

### Failure Scenarios

| Scenario | Behaviour | Recovery Time |
|----------|-----------|---------------|
| Leader pod crashes (OOMKill) | Lease expires after `leaseDuration` | `leaseDuration` (typically 5–30s) |
| Leader pod loses network (partition) | Lease expires; leader steps down; new leader elected | `leaseDuration` |
| Redis crashes (single node) | All nodes lose the lease; all try to re-acquire when Redis recovers | Redis recovery time + `retryInterval` |
| Redis network partition (split brain) | **Risk**: two nodes may both acquire the lease | Mitigated with Redlock (N Redis nodes, quorum) or switching to etcd/ZK |
| Voluntary shutdown | Leader deletes lease proactively → fast failover | `retryInterval` (seconds, not `leaseDuration`) |

### Split-Brain Prevention

```
Single Redis node: NOT safe for true single-leader guarantee.
  → Acceptable for advisory locks (scheduler, cache warmup)
  → NOT acceptable for primary DB writes, billing

Redlock (Redis): acquire lease on 3 of 5 Redis nodes.
  → Much safer; but Raft-based systems (etcd, ZooKeeper) are stronger

etcd / ZooKeeper: Raft consensus → linearizable → no split-brain.
  → Use for: Kafka partition leadership, HBase master election, Kubernetes controller leader election
  → K8s uses: ConfigMap/Lease object in kube-system with leader-election library
```

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | `RedisLeaderElection` manages lease lifecycle; `DistributedScheduler` runs leader work — separate concerns |
| Open/Closed | ✅ | Swap Redis → ZooKeeper → etcd by swapping `LeaderElection` implementation; callbacks unchanged |
| Liskov Substitution | ✅ | Redis, ZK, and etcd implementations are interchangeable behind `LeaderCallbacks` |
| Interface Segregation | ✅ | `LeaderCallbacks` has exactly two methods: `onElected()` / `onRevoked()` |
| Dependency Inversion | ✅ | Business logic depends on `LeaderCallbacks` contract; not on Redis or ZK internals |

---

## When to Use

- A scheduled job must run on exactly one node in a cluster
- A distributed lock must be held by at most one node at a time (e.g., shard assignment)
- Primary-secondary replication: one node is primary (accepts writes); others are standbys
- Cluster coordinator role: one node handles membership changes, rebalancing, metrics aggregation

## When NOT to Use

- You only need distributed mutual exclusion for a short duration → use a distributed lock (Redisson, DynamoDB conditional write) instead of a full leader election
- All nodes can perform the operation safely with idempotency → no election needed
- Stateless operations where any node can handle any request → use a load balancer

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Exactly-once execution for leader-only operations | Failover latency: `leaseDuration` (5–30s) window where no leader exists |
| Automatic recovery — no manual intervention on pod crash | Split-brain risk with single Redis: two leaders briefly possible if Redis partitions |
| Voluntary step-down → fast failover (seconds not minutes) | Implementation complexity: renew loop, step-down logic, race conditions on lease expiry |
| Works with any process/language via Redis/etcd | `leaseDuration` vs `renewInterval` tuning: too short → frequent false failovers; too long → slow recovery |

---

**FAANG interview application**: "Leader election is the pattern behind Kafka partition leadership (ZooKeeper/KRaft), HBase master election, Elasticsearch master, and Kubernetes controller manager. At the implementation level: use Redis SET NX with a TTL as the simplest advisory lock — works well for 99% of scheduler use cases. For true split-brain prevention (e.g., shard assignment where two leaders would corrupt data), use etcd or ZooKeeper which provide linearizable consensus via Raft/ZAB. The critical operational concern is `leaseDuration` tuning: 5s means 5s of no leader during failover but only 5s of double-leader if split-brain occurs; 30s is safer for the coordinator but the split-brain window is longer."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Singleton](../creational/01-singleton.md) | Leader election is a distributed Singleton — ensuring one active instance across a cluster |
| [Object Pool](../modern/38-object-pool.md) | The leader is often responsible for managing shared resource pools (connection pools, shard maps) |
| [Circuit Breaker](../modern/29-circuit-breaker.md) | Followers can monitor the coordination store; if the store is unreachable, apply circuit breaker logic to avoid flapping |
| [Competing Consumers](../modern/37-competing-consumers.md) | Opposite model: Competing Consumers intentionally have many workers; Leader Election intentionally has one |
