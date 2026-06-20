# T-Digest
**Category**: Probabilistic Data Structure — accurate tail percentile estimation (p99, p999); used in Prometheus, Elasticsearch, Netflix, Circonus

---

## 1. The Problem It Solves

### Percentile Estimation at Scale

"What is our p99 API latency over the last 5 minutes?"

Exact percentile requires storing and sorting every data point:
```
100K requests/min × 5 min = 500K latency samples
500K × 8 bytes = 4 MB per metric per service
With 1000 services × 100 endpoints = 400 GB just for latency histograms
```

Alternatives:
- **Fixed histogram buckets** (Prometheus default): fast but bucket boundaries are guessed upfront. p99 inside a wide bucket (e.g., 100ms–500ms) is imprecise — you only know the count, not the distribution within the bucket.
- **HyperLogLog**: estimates cardinality, not percentiles.
- **Count-Min Sketch**: estimates frequency of values, not rank.

**T-Digest** accurately estimates percentiles — especially tail percentiles (p99, p999) — using a fixed-memory sketch that allocates more precision at the extremes where it matters most.

```
T-Digest with compression=100:
  Memory: ~100 centroids × ~24 bytes = ~2.4 KB per metric
  p50 error: ±1–2%
  p99 error: ±0.1%  ← tail precision is the key advantage
  p999 error: ±0.01%
```

---

## 2. Algorithm

### 2.1 Centroids

A T-Digest maintains a list of **centroids**, each representing a cluster of values:

```
centroid = (mean, count)

Example centroids for latency data [1,2,3,...,100ms]:
  (1.0, 1), (2.0, 1), (3.0, 1),   ← sparse near min (few points per centroid)
  ...
  (40.0, 5), (50.0, 10), (60.0, 5) ← dense in middle (many points merged)
  ...
  (98.0, 1), (99.0, 1), (100.0, 1) ← sparse near max (few points per centroid)
```

**Key invariant**: centroids near the tails (rank close to 0 or 1) are kept small (few points merged). Centroids in the middle can be large (many points merged). This allocation of precision exactly where tail accuracy matters.

### 2.2 Scale Function

The limit on how large a centroid at quantile `q` can grow:

```
k(q) = compression × q × (1 - q) / (1 + q × (1 - q))  [k2 scale function]

At q = 0.5 (median): limit is large — many points merged → imprecise
At q = 0.99 (p99):   limit is small — few points merged → precise
At q = 0.999 (p999): limit even smaller → very precise

Compression parameter (δ): higher → fewer centroids → less memory, less accurate
                            lower  → more centroids → more memory, more accurate
Typical: 100 (good balance), 200 (high accuracy for SLOs)
```

### 2.3 Add Operation

1. Find the nearest centroid(s) to the new value.
2. If merging respects the size limit for that centroid's quantile: merge (update mean and count).
3. Otherwise: create a new centroid.
4. Periodically compress: merge small adjacent centroids that together still respect the limit.

### 2.4 Query (quantile → value)

1. Compute the target rank: `r = q × total_count`.
2. Walk centroids in order, accumulating counts.
3. Interpolate linearly between the centroid whose cumulative count crosses `r` and its neighbour.

---

## 3. Java Implementation

### 3.1 T-Digest Core

```java
import java.util.*;

public class TDigest {

    private static final class Centroid implements Comparable<Centroid> {
        double mean;
        long count;

        Centroid(double mean, long count) { this.mean = mean; this.count = count; }

        void add(double value, long c) {
            count += c;
            mean += c * (value - mean) / count;
        }

        public int compareTo(Centroid o) { return Double.compare(this.mean, o.mean); }
    }

    private final double compression;
    private final List<Centroid> centroids = new ArrayList<>();
    private long totalCount = 0;
    private boolean sorted = true;

    // Buffer for batch processing
    private final List<double[]> buffer = new ArrayList<>(); // [value, count]
    private static final int BUFFER_SIZE = 1000;

    public TDigest(double compression) {
        this.compression = compression;
    }

    public void add(double value) {
        add(value, 1);
    }

    public void add(double value, long count) {
        buffer.add(new double[]{value, count});
        totalCount += count;
        if (buffer.size() >= BUFFER_SIZE) compress();
    }

    private void compress() {
        if (buffer.isEmpty()) return;
        // Sort and merge buffer into centroids
        buffer.sort(Comparator.comparingDouble(a -> a[0]));
        for (double[] item : buffer) mergeCentroid(item[0], (long) item[1]);
        buffer.clear();
        // Trim: merge adjacent centroids that are small enough
        trimCentroids();
        sorted = false;
    }

    private void mergeCentroid(double value, long count) {
        if (centroids.isEmpty()) { centroids.add(new Centroid(value, count)); return; }

        double rank = 0;
        int bestIdx = -1;
        double bestDist = Double.MAX_VALUE;

        for (int i = 0; i < centroids.size(); i++) {
            Centroid c = centroids.get(i);
            double dist = Math.abs(c.mean - value);
            if (dist < bestDist) {
                double q = (rank + c.count / 2.0) / totalCount;
                double limit = sizeLimit(q);
                if (c.count + count <= limit) { bestDist = dist; bestIdx = i; }
            }
            rank += c.count;
        }

        if (bestIdx >= 0) centroids.get(bestIdx).add(value, count);
        else centroids.add(new Centroid(value, count)); // new centroid
    }

    private void trimCentroids() {
        if (centroids.size() < 2) return;
        Collections.sort(centroids);
        List<Centroid> merged = new ArrayList<>();
        merged.add(centroids.get(0));
        double rank = centroids.get(0).count;

        for (int i = 1; i < centroids.size(); i++) {
            Centroid prev = merged.getLast();
            Centroid curr = centroids.get(i);
            double q = rank / totalCount;
            double limit = sizeLimit(q);
            if (prev.count + curr.count <= limit) {
                prev.add(curr.mean, curr.count);
            } else {
                merged.add(curr);
            }
            rank += curr.count;
        }
        centroids.clear();
        centroids.addAll(merged);
    }

    // Scale function k2: allocates more precision at tails
    private double sizeLimit(double q) {
        double z = Math.max(1, compression * q * (1 - q));
        return z;
    }

    public double quantile(double q) {
        compress(); // flush buffer
        if (centroids.isEmpty()) return Double.NaN;
        if (!sorted) { Collections.sort(centroids); sorted = true; }

        double targetRank = q * totalCount;
        double rank = 0;

        for (int i = 0; i < centroids.size(); i++) {
            Centroid c = centroids.get(i);
            double lower = rank;
            double upper = rank + c.count;
            double midRank = (lower + upper) / 2.0;

            if (targetRank <= midRank) {
                if (i == 0) return c.mean;
                Centroid prev = centroids.get(i - 1);
                double prevMid = lower - prev.count / 2.0 + lower;
                // Linear interpolation between prev and curr centroid midpoints
                double t = (targetRank - (lower - c.count / 2.0)) / c.count;
                return prev.mean + t * (c.mean - prev.mean);
            }
            rank = upper;
        }
        return centroids.getLast().mean;
    }

    // Merge another T-Digest into this one (for distributed aggregation)
    public void merge(TDigest other) {
        other.compress();
        for (Centroid c : other.centroids) add(c.mean, c.count);
    }

    public long totalCount() { return totalCount; }
    public int centroidCount() { compress(); return centroids.size(); }

    public double p50()  { return quantile(0.50); }
    public double p90()  { return quantile(0.90); }
    public double p95()  { return quantile(0.95); }
    public double p99()  { return quantile(0.99); }
    public double p999() { return quantile(0.999); }
}
```

### 3.2 Sliding Window T-Digest (time-windowed percentiles)

```java
import java.time.Instant;
import java.util.*;

public class SlidingWindowTDigest {

    private record Slice(Instant time, TDigest digest) {}

    private final Deque<Slice> slices = new ArrayDeque<>();
    private TDigest activeSlice;
    private Instant activeStart;
    private final long windowSeconds;
    private final long sliceDurationSeconds;
    private final double compression;

    public SlidingWindowTDigest(long windowSeconds, long sliceDurationSeconds, double compression) {
        this.windowSeconds = windowSeconds;
        this.sliceDurationSeconds = sliceDurationSeconds;
        this.compression = compression;
        this.activeSlice = new TDigest(compression);
        this.activeStart = Instant.now();
    }

    public synchronized void record(double valueMs) {
        Instant now = Instant.now();
        if (now.getEpochSecond() - activeStart.getEpochSecond() >= sliceDurationSeconds) {
            slices.addLast(new Slice(activeStart, activeSlice));
            activeSlice = new TDigest(compression);
            activeStart = now;
            evictOld(now);
        }
        activeSlice.add(valueMs);
    }

    public synchronized double quantile(double q) {
        evictOld(Instant.now());
        TDigest merged = new TDigest(compression);
        for (Slice s : slices) merged.merge(s.digest());
        merged.merge(activeSlice);
        return merged.quantile(q);
    }

    private void evictOld(Instant now) {
        Instant cutoff = now.minusSeconds(windowSeconds);
        slices.removeIf(s -> s.time().isBefore(cutoff));
    }
}
```

### 3.3 Distributed Latency Tracking (Prometheus-style)

```java
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

public class LatencyTracker {

    // endpoint → T-Digest (one per endpoint)
    private final Map<String, TDigest> digests = new ConcurrentHashMap<>();
    private final double compression;

    public LatencyTracker(double compression) { this.compression = compression; }

    public void record(String endpoint, double latencyMs) {
        digests.computeIfAbsent(endpoint, k -> new TDigest(compression))
               .add(latencyMs);
    }

    public LatencyReport report(String endpoint) {
        TDigest d = digests.get(endpoint);
        if (d == null) return null;
        return new LatencyReport(endpoint, d.p50(), d.p90(), d.p95(), d.p99(), d.p999(), d.totalCount());
    }

    // Merge per-instance digests for fleet-wide p99
    public LatencyReport mergedReport(String endpoint, Iterable<LatencyTracker> instances) {
        TDigest merged = new TDigest(compression);
        for (LatencyTracker tracker : instances) {
            TDigest d = tracker.digests.get(endpoint);
            if (d != null) merged.merge(d);
        }
        return new LatencyReport(endpoint, merged.p50(), merged.p90(), merged.p95(),
                                  merged.p99(), merged.p999(), merged.totalCount());
    }

    public record LatencyReport(
        String endpoint, double p50, double p90, double p95,
        double p99, double p999, long totalRequests) {}
}
```

---

## 4. T-Digest vs Fixed Histograms vs DDSketch

| Attribute | Fixed Histogram | T-Digest | DDSketch (Datadog) |
|---|---|---|---|
| Memory | O(buckets) fixed | O(compression) fixed | O(relative_accuracy⁻¹) |
| p50 accuracy | ±bucket_width/2 | ±1–2% | ±α |
| p99 accuracy | ±bucket_width/2 (poor if wide) | ±0.1% | ±α (uniform) |
| Mergeability | Yes (add counts) | Yes (merge centroids) | Yes (add buckets) |
| Bucket pre-config | Required | Not required | Not required |
| Outlier handling | Poor (max bucket) | Good (tail centroids small) | Good (logarithmic) |
| Used in | Prometheus (default) | Elasticsearch, Circonus, Netflix | Datadog, Sketch++ |

**DDSketch** (Datadog): guarantees uniform relative error `α` at all quantiles using logarithmically-spaced buckets. No guessing bucket boundaries. p99 error = ±α of the true value. T-Digest has better tail accuracy for the same memory; DDSketch has more uniform accuracy across the distribution.

---

## 5. Where T-Digest Appears at FAANG

| System | Use | Notes |
|---|---|---|
| **Netflix Atlas** | Fleet-wide p99 latency | T-Digest per host, merged server-side |
| **Elasticsearch** | `percentiles` aggregation | `tdigest` algorithm in `percentiles` agg |
| **Prometheus** (via client) | `Summary` metric type | Client-side T-Digest, but no merge |
| **Apache Flink** | Streaming latency metrics | T-Digest in latency tracking histogram |
| **Circonus** | Histogram streaming | T-Digest-based H2 histogram format |
| **Cloudera** | Impala query latency | Approximate percentiles via T-Digest |

---

## 6. FAANG Interview Callouts

**"Design a system to track p99 latency across 10K microservices, 1M RPS total:"**
> Each service instance maintains a T-Digest (compression=100, ~2.4 KB). Every 10s, serialize the centroid list (200 bytes compressed) and push to a metrics aggregator. Aggregator merges T-Digests from all instances of a service (element-wise merge) for the fleet-wide p99. Memory: 10K services × 2.4 KB = 24 MB total. Query latency: merge 100 instances × O(compression) = O(10K) centroid comparisons — sub-millisecond. Alternative (Prometheus default Summary): cannot merge across instances; only per-instance percentiles visible.

**"Why can't you average p99s across instances?"**
> Averaging percentiles is mathematically invalid. If instance A has p99=200ms (low traffic) and instance B has p99=800ms (high traffic), averaging gives 500ms — which tells you nothing about the actual 99th percentile of the combined distribution. You must merge the raw distributions (T-Digests) before computing percentiles.

**Follow-up questions to expect:**
1. "How does T-Digest handle bimodal distributions?" → It merges values near the center more aggressively, so the two modes may blur together. For bimodal data with widely separated peaks, the centroids between the modes merge — you lose the valley. Use DDSketch or store both distributions separately.
2. "What's the memory cost of tracking a 5-minute sliding window at 1ms resolution?" → Window = 5 × 60 × 60K samples/min ≈ 18M data points raw = 144 MB. T-Digest with compression=100: ~2.4 KB regardless of sample count. Use a sliding window of 30 10-second T-Digest slices, merge on query — total 30 × 2.4 KB = 72 KB.
3. "Can T-Digest compute exact min and max?" → Yes — the leftmost centroid's mean is the minimum, rightmost is the maximum (since centroids are sorted by mean and tail centroids contain exactly one point each).
