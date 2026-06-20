# Timing Wheel (Hierarchical Timer Wheel)
**Category**: Timer Data Structure — O(1) timer insert/cancel/fire; used in Kafka, Netty, Linux kernel, TCP retransmission

---

## 1. The Problem It Solves

### Managing Millions of Timeouts

Every distributed system needs timers: retries, session expiry, idle connection cleanup, lease renewal, request timeouts. At scale:

```
10M active connections × 30s idle timeout = 10M timers in flight
New connection/request every μs → timer insert must be O(1)
Expired timer must fire promptly → O(1) scan, not O(N)
```

| Data Structure | Insert | Cancel | Fire next | Memory |
|---|---|---|---|---|
| Sorted list | O(N) | O(N) | O(1) | O(N) |
| Heap (PriorityQueue) | O(log N) | O(log N) | O(log N) | O(N) |
| **Timing Wheel** | **O(1)** | **O(1)** | **O(1) amortised** | O(wheel_size + N) |

A timing wheel achieves O(1) for all operations by hashing expiry times into fixed-size circular buckets — exactly like a clock face.

---

## 2. Simple Timing Wheel

### 2.1 Concept

A circular array of `N` buckets, where each bucket represents a time tick. A pointer advances one bucket per tick.

```
tick_ms = 10ms, wheel_size = 60 buckets → max range = 600ms

  59  0  1
 /         \
58           2
|    tick    |
57   ──►     3     ← current tick = 3
|            |
56           4
 \         /
  55 ... 5

Insert timer expiring in 250ms:
  bucket = (current_tick + 250/10) % 60 = (3 + 25) % 60 = 28
  Place timer in bucket[28]

Each tick: advance pointer, fire all timers in current bucket
```

**Limitation**: max range = tick_ms × wheel_size. For 30s timeouts with 10ms ticks you'd need a 3000-slot wheel.

---

## 3. Hierarchical Timing Wheel

Chain multiple wheels at different resolutions (like clock: second hand → minute hand → hour hand):

```
Wheel 1 (fine): 512 slots × 1ms   = 512ms range
Wheel 2 (med):  64 slots  × 512ms = 32s range
Wheel 3 (coarse): 64 slots × 32s  = 34 min range

Insert timer expiring in 10s:
  > Wheel 1 range (512ms) → escalate
  Wheel 2: slot = (10000ms / 512ms) % 64 = 19
  Place in Wheel2[19]

When Wheel2's pointer reaches slot 19:
  "Cascade" its timers down to Wheel1 for precise firing
  Each timer redistributed into Wheel1 based on remaining ms
```

This is the exact design in **Kafka's `TimingWheel`** and **Netty's `HashedWheelTimer`**.

---

## 4. Java Implementation

### 4.1 Simple Timing Wheel

```java
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;

public class SimpleTimingWheel {

    private final int wheelSize;
    private final long tickMs;
    private final List<Set<TimerTask>> buckets;
    private volatile int currentTick = 0;
    private final ScheduledExecutorService ticker;

    public SimpleTimingWheel(int wheelSize, long tickMs) {
        this.wheelSize = wheelSize;
        this.tickMs = tickMs;
        this.buckets = new ArrayList<>(wheelSize);
        for (int i = 0; i < wheelSize; i++) buckets.add(ConcurrentHashMap.newKeySet());
        this.ticker = Executors.newSingleThreadScheduledExecutor(r -> {
            Thread t = new Thread(r, "timing-wheel-tick");
            t.setDaemon(true);
            return t;
        });
        ticker.scheduleAtFixedRate(this::tick, tickMs, tickMs, TimeUnit.MILLISECONDS);
    }

    public TimerTask schedule(Runnable task, long delayMs) {
        long ticks = Math.max(1, delayMs / tickMs);
        int bucket = (int) ((currentTick + ticks) % wheelSize);
        TimerTask tt = new TimerTask(task, bucket, ticks / wheelSize);
        buckets.get(bucket).add(tt);
        return tt;
    }

    private void tick() {
        currentTick = (currentTick + 1) % wheelSize;
        Set<TimerTask> due = buckets.get(currentTick);
        List<TimerTask> toFire = new ArrayList<>();
        for (TimerTask tt : due) {
            if (tt.isCancelled()) { due.remove(tt); continue; }
            if (tt.remainingRounds() == 0) toFire.add(tt);
            else tt.decrementRound();
        }
        for (TimerTask tt : toFire) {
            due.remove(tt);
            tt.run();
        }
    }

    public void shutdown() { ticker.shutdown(); }

    public static final class TimerTask {
        private final Runnable task;
        private final int bucket;
        private volatile int rounds;
        private volatile boolean cancelled = false;

        TimerTask(Runnable task, int bucket, long rounds) {
            this.task = task; this.bucket = bucket; this.rounds = (int) rounds;
        }

        public void cancel() { cancelled = true; }
        boolean isCancelled() { return cancelled; }
        int remainingRounds() { return rounds; }
        void decrementRound() { rounds--; }
        void run() { if (!cancelled) task.run(); }
    }
}
```

### 4.2 Hierarchical Timing Wheel (Kafka-style)

```java
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicLong;
import java.util.function.Consumer;

public class HierarchicalTimingWheel {

    private static final int WHEEL_SIZE = 20;     // slots per wheel
    private final long tickMs;                     // finest tick
    private final long[] wheelMs;                  // tick duration per level
    private final Bucket[][] wheels;               // [level][slot]
    private final long[] currentTime;              // current time pointer per level
    private final DelayQueue<Bucket> delayQueue;   // drives expiry

    public HierarchicalTimingWheel(long tickMs, int levels) {
        this.tickMs = tickMs;
        this.wheelMs = new long[levels];
        this.wheels = new Bucket[levels][WHEEL_SIZE];
        this.currentTime = new long[levels];
        this.delayQueue = new DelayQueue<>();

        long tick = tickMs;
        long now = System.currentTimeMillis();
        for (int i = 0; i < levels; i++) {
            wheelMs[i] = tick;
            currentTime[i] = now - (now % tick); // floor to tick boundary
            for (int j = 0; j < WHEEL_SIZE; j++) wheels[i][j] = new Bucket();
            tick *= WHEEL_SIZE;
        }
    }

    public TimerEntry schedule(Runnable task, long delayMs) {
        long expiry = System.currentTimeMillis() + delayMs;
        TimerEntry entry = new TimerEntry(task, expiry);
        add(entry);
        return entry;
    }

    private boolean add(TimerEntry entry) {
        long expiry = entry.expiry;
        for (int level = 0; level < wheels.length; level++) {
            long levelTick = wheelMs[level];
            long levelRange = levelTick * WHEEL_SIZE;
            if (expiry < currentTime[level] + levelRange) {
                int slot = (int) ((expiry / levelTick) % WHEEL_SIZE);
                Bucket bucket = wheels[level][slot];
                bucket.add(entry);
                bucket.setExpiry((slot + 1) * levelTick); // when this bucket fires
                delayQueue.offer(bucket);
                return true;
            }
        }
        // expiry beyond all wheels → fire immediately (already expired)
        entry.run();
        return false;
    }

    // Called by a background thread consuming the delayQueue
    public void advanceClock(long timeMs) {
        Bucket bucket;
        while ((bucket = delayQueue.poll()) != null) {
            // Advance clock to bucket expiry
            for (int i = 0; i < wheels.length; i++) {
                if (bucket.expiry() > currentTime[i] + wheelMs[i]) continue;
                currentTime[i] = bucket.expiry() - (bucket.expiry() % wheelMs[i]);
                break;
            }
            // Cascade: re-add all entries in this bucket
            for (TimerEntry entry : bucket.drain()) {
                if (!entry.isCancelled()) add(entry); // may land in finer wheel or fire
            }
        }
    }

    // ─── Inner classes ───────────────────────────────────────────────────────

    static final class Bucket implements Delayed {
        private final List<TimerEntry> entries = Collections.synchronizedList(new ArrayList<>());
        private volatile long expiry = Long.MAX_VALUE;

        void add(TimerEntry e)  { entries.add(e); }
        void setExpiry(long ms) { expiry = ms; }
        long expiry()           { return expiry; }
        List<TimerEntry> drain() { List<TimerEntry> copy = new ArrayList<>(entries); entries.clear(); return copy; }

        public long getDelay(TimeUnit unit) {
            return unit.convert(expiry - System.currentTimeMillis(), TimeUnit.MILLISECONDS);
        }
        public int compareTo(Delayed other) {
            return Long.compare(expiry, ((Bucket) other).expiry);
        }
    }

    public static final class TimerEntry {
        private final Runnable task;
        final long expiry;
        private volatile boolean cancelled = false;

        TimerEntry(Runnable task, long expiry) { this.task = task; this.expiry = expiry; }
        public void cancel() { cancelled = true; }
        boolean isCancelled() { return cancelled; }
        void run() { if (!cancelled) task.run(); }
    }
}
```

### 4.3 Netty HashedWheelTimer Usage

```java
import io.netty.util.HashedWheelTimer;
import io.netty.util.Timeout;
import io.netty.util.TimerTask;
import java.util.concurrent.TimeUnit;

public class ConnectionTimeoutManager {

    // tickDuration=100ms, ticksPerWheel=512 → max≈51.2s, resolution=100ms
    private final HashedWheelTimer timer = new HashedWheelTimer(100, TimeUnit.MILLISECONDS, 512);

    public Timeout scheduleIdleTimeout(String connectionId, Runnable onTimeout) {
        return timer.newTimeout(
            timeout -> { if (!timeout.isCancelled()) onTimeout.run(); },
            30, TimeUnit.SECONDS
        );
    }

    public void refreshTimeout(Timeout existing, String connectionId, Runnable onTimeout) {
        existing.cancel(); // O(1) — just sets a cancelled flag
        scheduleIdleTimeout(connectionId, onTimeout);
    }

    public void shutdown() { timer.stop(); }
}
```

### 4.4 Session Expiry Service (Practical Pattern)

```java
import java.util.*;
import java.util.concurrent.*;

public class SessionExpiryService {

    private final SimpleTimingWheel wheel;
    // sessionId → current timer task
    private final Map<String, SimpleTimingWheel.TimerTask> timers = new ConcurrentHashMap<>();
    private final long sessionTtlMs;

    public SessionExpiryService(long sessionTtlMs) {
        this.sessionTtlMs = sessionTtlMs;
        // tick=1s, 120 slots → 120s max range
        this.wheel = new SimpleTimingWheel(120, 1000);
    }

    public void createSession(String sessionId) {
        scheduleExpiry(sessionId);
    }

    public void refreshSession(String sessionId) {
        SimpleTimingWheel.TimerTask old = timers.get(sessionId);
        if (old != null) old.cancel(); // O(1)
        scheduleExpiry(sessionId);
    }

    public void destroySession(String sessionId) {
        SimpleTimingWheel.TimerTask t = timers.remove(sessionId);
        if (t != null) t.cancel();
    }

    private void scheduleExpiry(String sessionId) {
        SimpleTimingWheel.TimerTask task = wheel.schedule(
            () -> {
                timers.remove(sessionId);
                onExpiry(sessionId);
            },
            sessionTtlMs
        );
        timers.put(sessionId, task);
    }

    private void onExpiry(String sessionId) {
        System.out.println("Session expired: " + sessionId);
        // Invalidate cache, close resources, emit event...
    }

    public void shutdown() { wheel.shutdown(); }
}
```

---

## 5. Kafka's `DelayedOperationPurgatory` (Real Usage)

Kafka uses a timing wheel to manage delayed produce/fetch operations:

```
Scenario: producer requests acks=all (wait for all replicas to acknowledge)
  → Create DelayedProduce with timeout = request.timeout.ms
  → Add to TimingWheel

When all replicas ack (before timeout):
  → Complete the operation early, cancel the timer (O(1))

When timer fires (not all replicas responded):
  → Fail the operation with TIMEOUT error

Key insight: the vast majority of operations complete before timeout.
  TimingWheel advantage: cancel is O(1) — just mark cancelled, no heap rebalance.
  At 500K produce requests/sec, PriorityQueue cancel would be O(log N) × 500K = 9.5M ops/sec
  TimingWheel cancel: O(1) × 500K = 500K ops/sec
```

```java
// Simplified Kafka DelayedOperation pattern
public abstract class DelayedOperation {
    private final long delayMs;
    private volatile HierarchicalTimingWheel.TimerEntry timerEntry;

    protected DelayedOperation(long delayMs) { this.delayMs = delayMs; }

    public abstract boolean tryComplete(); // returns true if operation completed
    public abstract void onExpiration();   // called on timeout

    public final void maybeTryComplete() {
        if (tryComplete() && timerEntry != null) {
            timerEntry.cancel(); // O(1)
        }
    }

    void setTimerEntry(HierarchicalTimingWheel.TimerEntry entry) { timerEntry = entry; }
    long delayMs() { return delayMs; }
}
```

---

## 6. Timing Wheel vs Alternatives

| Approach | Insert | Cancel | Fire | Memory | Max Timers at Scale |
|---|---|---|---|---|---|
| `ScheduledThreadPoolExecutor` | O(log N) | O(log N) | O(log N) | O(N) | ~1M (GC pressure) |
| `PriorityQueue` | O(log N) | O(N) find | O(log N) | O(N) | ~10M |
| Simple Timing Wheel | O(1) | O(1) | O(1) amortised | O(W+N) | 100M+ |
| Hierarchical TW | O(1) | O(1) | O(1) amortised | O(L×W+N) | 100M+ |
| `DelayQueue` only | O(log N) | O(log N) | O(log N) | O(N) | ~10M |

W = wheel size, L = levels, N = active timers.

---

## 7. FAANG Interview Callouts

**"Design a system to manage 100M session timeouts with 30s TTL and refresh-on-activity:"**
> Use a hierarchical timing wheel (tickMs=1s, 3 levels). Each session → O(1) insert. On activity: O(1) cancel old timer + O(1) insert new. On expiry: fire callback to invalidate session in Redis. At 100M sessions with ~10K refreshes/sec: O(10K) cancels + O(10K) inserts per second — trivial. Heap alternative: O(10K × log 100M) = 270K comparisons/sec + GC pressure for 100M heap objects.

**"Why does Netty use a timing wheel instead of Java's ScheduledThreadPoolExecutor for connection timeouts?"**
> Netty handles millions of concurrent connections. STPE uses a heap internally: O(log N) insert/cancel. At 1M connections each refreshing timeouts on activity, that's O(20M) comparisons/sec. The HashedWheelTimer gives O(1) for all operations, and cancel is a single `volatile` write. Also: STPE creates a task object per schedule, causing GC pressure at scale.

**Follow-up questions to expect:**
1. "What's the trade-off of a coarser tick vs a finer tick in a timing wheel?" → Finer tick (1ms): timers fire more precisely but the background thread burns more CPU scanning more buckets. Coarser tick (100ms): lower CPU overhead, timers may fire up to 1 tick late. Production default: 100ms (Netty) or 1ms for low-latency systems.
2. "How does Kafka handle the case where a timer fires but the operation is already complete?" → Every `TimerTask.run()` checks an `isCancelled` flag first. Cancel is a CAS on the flag — zero allocation, no lock. Fire path just skips cancelled tasks, no cleanup needed.
3. "How many levels does Kafka's timing wheel have?" → Kafka uses a flat timing wheel with overflow handled by cascading into a second wheel (effectively 2 levels). Netty uses a single wheel with `rounds` counter (similar to what's shown in `SimpleTimingWheel` above). True hierarchical wheels appear in the Linux kernel (4 wheels: `tv1`–`tv5`).
