# Ring Buffer (Circular Buffer)
**Category**: Fixed-Size Sequential Data Structure — used in Kafka, LMAX Disruptor, OS kernel I/O buffers, networking stacks

---

## 1. The Problem It Solves

### Bounded Producer-Consumer Queues

A standard queue (`LinkedList`, `ArrayDeque`) allocates nodes on the heap — GC pressure, cache misses, and unbounded memory growth under sustained load.

A ring buffer uses a **fixed pre-allocated array**. Producers and consumers chase each other around the array using integer cursors. When the cursor reaches the end, it wraps to 0.

```
Benefits:
  - Zero allocation after initialisation: no GC pressure
  - Cache-friendly: array laid out contiguously in memory
  - Lock-free variants (Disruptor): throughput 25M+ messages/sec on a single core
  - Bounded: applies back-pressure when full (no unbounded memory growth)

Used in:
  Kafka segment files (sequential append, read from arbitrary offset)
  LMAX Disruptor (financial trading, HFT)
  Linux kernel I/O ring (io_uring)
  TCP receive/send buffers
  Audio/video streaming pipelines
```

---

## 2. Structure

```
Capacity = 8 (must be power of 2 for fast modulo via bitmask)

        head (read)                tail (write)
          │                            │
          ▼                            ▼
┌───┬───┬───┬───┬───┬───┬───┬───┐
│ 0 │ 1 │ 2 │ 3 │ 4 │ 5 │ 6 │ 7 │   indices
└───┴───┴───┴───┴───┴───┴───┴───┘
      consumed   [  available  ]

head % capacity = read position
tail % capacity = write position
size = tail - head  (using long counters that never wrap)
full when: tail - head == capacity
empty when: tail == head
```

Using **monotonically increasing long** counters (never reset to 0) instead of wrapping head/tail avoids the empty-vs-full ambiguity and simplifies concurrent access.

---

## 3. Java Implementation

### 3.1 Single-Producer Single-Consumer Lock-Free Ring Buffer

```java
import java.util.concurrent.atomic.AtomicLong;

public class SPSCRingBuffer<T> {

    private final Object[] buffer;
    private final int capacity;
    private final int mask;         // capacity - 1, for fast modulo

    // Separate cache lines to avoid false sharing (64-byte padding)
    private final AtomicLong head = new AtomicLong(0); // consumer reads here
    private final AtomicLong tail = new AtomicLong(0); // producer writes here

    public SPSCRingBuffer(int capacity) {
        if (Integer.bitCount(capacity) != 1)
            throw new IllegalArgumentException("Capacity must be a power of 2");
        this.capacity = capacity;
        this.mask = capacity - 1;
        this.buffer = new Object[capacity];
    }

    // Producer: returns false if buffer is full (back-pressure)
    public boolean offer(T item) {
        long currentTail = tail.get();
        long currentHead = head.get();
        if (currentTail - currentHead == capacity) return false; // full

        buffer[(int) (currentTail & mask)] = item;
        tail.lazySet(currentTail + 1); // lazySet: ordered store, avoids StoreLoad fence
        return true;
    }

    // Consumer: returns null if buffer is empty
    @SuppressWarnings("unchecked")
    public T poll() {
        long currentHead = head.get();
        if (currentHead == tail.get()) return null; // empty

        T item = (T) buffer[(int) (currentHead & mask)];
        buffer[(int) (currentHead & mask)] = null; // prevent memory leak
        head.lazySet(currentHead + 1);
        return item;
    }

    public boolean isEmpty() { return head.get() == tail.get(); }
    public boolean isFull()  { return tail.get() - head.get() == capacity; }
    public int size()         { return (int) (tail.get() - head.get()); }
    public int capacity()     { return capacity; }
}
```

### 3.2 Multi-Producer Multi-Consumer (Blocking)

```java
import java.util.concurrent.locks.Condition;
import java.util.concurrent.locks.ReentrantLock;

public class MPMCRingBuffer<T> {

    private final Object[] buffer;
    private final int capacity;
    private final int mask;
    private long head = 0;
    private long tail = 0;

    private final ReentrantLock lock = new ReentrantLock();
    private final Condition notFull  = lock.newCondition();
    private final Condition notEmpty = lock.newCondition();

    public MPMCRingBuffer(int capacity) {
        if (Integer.bitCount(capacity) != 1)
            throw new IllegalArgumentException("Capacity must be a power of 2");
        this.capacity = capacity;
        this.mask = capacity - 1;
        this.buffer = new Object[capacity];
    }

    public void put(T item) throws InterruptedException {
        lock.lock();
        try {
            while (tail - head == capacity) notFull.await(); // block when full
            buffer[(int) (tail & mask)] = item;
            tail++;
            notEmpty.signal();
        } finally {
            lock.unlock();
        }
    }

    public boolean offer(T item) {
        lock.lock();
        try {
            if (tail - head == capacity) return false;
            buffer[(int) (tail & mask)] = item;
            tail++;
            notEmpty.signal();
            return true;
        } finally {
            lock.unlock();
        }
    }

    @SuppressWarnings("unchecked")
    public T take() throws InterruptedException {
        lock.lock();
        try {
            while (head == tail) notEmpty.await(); // block when empty
            T item = (T) buffer[(int) (head & mask)];
            buffer[(int) (head & mask)] = null;
            head++;
            notFull.signal();
            return item;
        } finally {
            lock.unlock();
        }
    }

    @SuppressWarnings("unchecked")
    public T poll() {
        lock.lock();
        try {
            if (head == tail) return null;
            T item = (T) buffer[(int) (head & mask)];
            buffer[(int) (head & mask)] = null;
            head++;
            notFull.signal();
            return item;
        } finally {
            lock.unlock();
        }
    }

    public int size()     { lock.lock(); try { return (int)(tail - head); } finally { lock.unlock(); } }
    public boolean isEmpty() { return size() == 0; }
    public boolean isFull()  { return size() == capacity; }
}
```

### 3.3 Disruptor-Style Ring Buffer (Sequence-Based)

The LMAX Disruptor achieves 25M+ events/sec by:
1. Pre-allocating all event objects and mutating them in-place (no GC).
2. Using a **sequence number** per slot, not a global head/tail.
3. Applying mechanical sympathy: padding to avoid false sharing, cache-aligned sequences.

```java
import java.util.concurrent.atomic.AtomicLong;
import java.util.function.Consumer;

public class DisruptorRingBuffer<E> {

    // Sequence per slot: slot available to producer when sequence == slot_index
    private final long[] sequences;
    private final Object[] events;
    private final int capacity;
    private final int mask;

    private final AtomicLong producerSequence = new AtomicLong(-1);
    private final AtomicLong consumerSequence = new AtomicLong(-1);

    @SuppressWarnings("unchecked")
    public DisruptorRingBuffer(int capacity, java.util.function.Supplier<E> eventFactory) {
        if (Integer.bitCount(capacity) != 1)
            throw new IllegalArgumentException("Capacity must be a power of 2");
        this.capacity = capacity;
        this.mask = capacity - 1;
        this.events = new Object[capacity];
        this.sequences = new long[capacity];
        for (int i = 0; i < capacity; i++) {
            events[i] = eventFactory.get(); // pre-allocate all event objects
            sequences[i] = i;               // initially each slot = its index (available)
        }
    }

    // Claim next slot (producer), returns sequence number for the claimed slot
    public long claimNext() {
        long seq;
        do {
            seq = producerSequence.get() + 1;
            // Wait if this slot hasn't been consumed yet
            long wrapPoint = seq - capacity;
            long gatingSeq = consumerSequence.get();
            if (gatingSeq >= wrapPoint) break; // slot free
            Thread.onSpinWait();
        } while (!producerSequence.compareAndSet(seq - 1, seq));
        return seq;
    }

    @SuppressWarnings("unchecked")
    public E get(long sequence) {
        return (E) events[(int) (sequence & mask)];
    }

    public void publish(long sequence) {
        sequences[(int) (sequence & mask)] = sequence; // mark as published
    }

    // Consumer: process next available event
    public boolean consumeNext(Consumer<E> handler) {
        long nextConsume = consumerSequence.get() + 1;
        if (sequences[(int) (nextConsume & mask)] < nextConsume) return false; // not published

        @SuppressWarnings("unchecked")
        E event = (E) events[(int) (nextConsume & mask)];
        handler.accept(event);
        consumerSequence.lazySet(nextConsume);
        return true;
    }
}
```

### 3.4 Sliding Window Statistics (Ring Buffer Pattern)

```java
public class SlidingWindowStats {

    private final long[] timestamps;
    private final double[] values;
    private final int capacity;
    private int head = 0, tail = 0, size = 0;

    public SlidingWindowStats(int maxEvents) {
        this.capacity = maxEvents;
        this.timestamps = new long[capacity];
        this.values = new double[capacity];
    }

    public void record(double value) {
        timestamps[tail] = System.currentTimeMillis();
        values[tail] = value;
        tail = (tail + 1) % capacity;
        if (size < capacity) size++;
        else head = (head + 1) % capacity; // overwrite oldest
    }

    public double average(long windowMs) {
        long cutoff = System.currentTimeMillis() - windowMs;
        double sum = 0;
        int count = 0;
        for (int i = 0; i < size; i++) {
            int idx = (head + i) % capacity;
            if (timestamps[idx] >= cutoff) { sum += values[idx]; count++; }
        }
        return count == 0 ? 0 : sum / count;
    }

    public long countInWindow(long windowMs) {
        long cutoff = System.currentTimeMillis() - windowMs;
        long count = 0;
        for (int i = 0; i < size; i++) {
            int idx = (head + i) % capacity;
            if (timestamps[idx] >= cutoff) count++;
        }
        return count;
    }
}
```

---

## 4. Kafka's Use of Sequential Log (Ring Buffer Principle)

Kafka's segment file structure applies the ring buffer principle at the file level:

```
Partition log directory:
  00000000000000000000.log    ← oldest segment
  00000000000000123456.log
  00000000000000246912.log    ← active segment (current write position)
  00000000000000246912.index  ← sparse offset → byte offset index

Write: always append to active segment (sequential I/O, O(1))
Read:  binary search index → seek to byte offset → read
Retention: delete/compact oldest segments when size > log.retention.bytes
           (acts as a ring: head advances as tail writes)
```

Key performance property: **sequential writes** on spinning disks achieve 200 MB/s, nearly matching SSDs. Kafka's throughput comes from treating the disk as a ring buffer, not a random-access store.

---

## 5. Ring Buffer vs Queue Alternatives

| Attribute | Ring Buffer | LinkedList Queue | ArrayDeque | java.util.concurrent.LinkedBlockingQueue |
|---|---|---|---|---|
| Memory allocation | Pre-allocated | Per-node | Amortised | Per-node |
| GC pressure | None | High | Low | High |
| Cache locality | Excellent | Poor (scattered) | Good | Poor |
| Bounded | Yes (fixed) | No | No | Optional |
| Lock-free (SPSC) | Yes | No | No | No |
| Throughput (SPSC) | ~100M ops/sec | ~10M | ~50M | ~5M |
| Latency (SPSC) | ~10 ns | ~100 ns | ~20 ns | ~300 ns |

---

## 6. Where Ring Buffers Appear at FAANG

| System | Use | Notes |
|---|---|---|
| **Kafka** | Log segment (disk-level ring) | Sequential append, configurable retention |
| **LMAX Disruptor** | Financial order processing | 6M+ orders/sec, used by LMAX exchange |
| **Linux io_uring** | Async I/O submission ring | Shared memory ring between kernel and user space |
| **Netty** | `ByteBuf` ring buffer | Zero-copy network I/O buffers |
| **Flink** | Network buffer pool | Inter-operator data transfer between tasks |
| **GPU drivers / CUDA** | Command queues | Ring buffer of GPU commands from CPU |
| **OS TCP stack** | Socket receive/send buffers | Fixed-size ring; back-pressure via window size |

---

## 7. FAANG Interview Callouts

**"How does Kafka achieve 100K+ writes/sec on a single broker?"**
> Kafka writes to an active log segment as a sequential append — identical to writing to a ring buffer on disk. Sequential I/O on HDDs delivers 200 MB/s vs ~1 MB/s for random writes. OS page cache absorbs both writes and reads, so consumer reads often hit RAM, not disk. Zero-copy transfers via `sendfile()` syscall eliminate CPU overhead in the write path.

**"Why does the LMAX Disruptor outperform a `ConcurrentLinkedQueue`?"**
> Three reasons: (1) Pre-allocated ring eliminates GC — no object allocation during steady-state. (2) Cache line padding on `Sequence` objects prevents false sharing between producer and consumer cursors. (3) Single-writer principle — each producer/consumer only writes to its own sequence, enabling lock-free CAS-free updates. Result: ~25M messages/sec vs ~5M for CLQ.

**Follow-up questions to expect:**
1. "What does 'false sharing' mean and how does the Disruptor fix it?" → Two threads writing to different variables that happen to share a CPU cache line cause cache invalidation on every write. The Disruptor pads each `Sequence` object with 56 bytes of padding to ensure it occupies its own 64-byte cache line.
2. "How do you implement back-pressure in a ring buffer?" → When the buffer is full, the producer either: blocks (blocking queue semantics), drops/samples (lossy), or routes to overflow storage (spill to disk). Kafka uses the broker's segment log as the overflow — producers can always write; consumers catch up at their own pace.
3. "How would you size the ring buffer for a trading system processing 1M orders/sec?" → At 1M events/sec with ~1 μs consumer latency: buffer needs to hold at most 1 event in-flight → capacity = 1M × 1μs = 1 slot average. Add safety margin for bursts: 1024–65536 slots. Memory: 65536 × 200 bytes per event = 13 MB.
