# External Sorting

**Category**: Sorting & Searching  
**Time Complexity**: O(N log N) total; O(N/B × log(N/B)) I/O operations (B = block size)  
**Space Complexity**: O(M) RAM (M = available memory)  
**Real-world connection**: Database sort-merge join, MapReduce shuffle phase, PostgreSQL ORDER BY on large datasets, Spark repartition/sort, database index creation

---

## Why External Sorting Matters in System Design Interviews

Internal sorting algorithms (quicksort, mergesort) assume the data fits in RAM. External sorting addresses the case where data is much larger than available memory — a scenario that appears constantly in:
- Database systems (sorting a 500GB table with 8GB RAM)
- MapReduce (sorting 100TB of log data across a cluster)
- Building an index on a 10TB dataset
- Merging sorted runs from multiple sources (database backup restoration)

At FAANG scale (petabytes of data), external sorting is not a theoretical exercise — it's embedded in every big-data processing system. Understanding it at the algorithmic level demonstrates the "depth" interviewers expect of principal engineers.

---

## Core Algorithm: External Merge Sort

External merge sort has two phases:

### Phase 1: Create Sorted Runs

Divide the input into chunks that fit in memory. Sort each chunk in memory. Write sorted chunk (a "run") to disk.

```python
import heapq
import os

def create_sorted_runs(input_file: str, memory_limit: int) -> list[str]:
    """
    Read input_file in memory_limit-sized chunks.
    Sort each chunk. Write to temp files.
    Returns list of temp file paths.
    """
    run_files = []
    run_id = 0
    with open(input_file) as f:
        while True:
            chunk = []
            bytes_read = 0
            for line in f:
                chunk.append(int(line.strip()))
                bytes_read += len(line)
                if bytes_read >= memory_limit:
                    break
            if not chunk:
                break
            chunk.sort()
            run_file = f"run_{run_id}.tmp"
            with open(run_file, 'w') as rf:
                rf.write('\n'.join(map(str, chunk)))
            run_files.append(run_file)
            run_id += 1
    return run_files
```

**After Phase 1**: we have `N/M` sorted runs, each of size M. (N = total data, M = memory limit)

### Phase 2: K-Way Merge

Merge all sorted runs simultaneously using a min-heap. At each step, extract the minimum element across all runs.

```python
def k_way_merge(run_files: list[str], output_file: str):
    """
    Merge sorted run files into a single sorted output.
    Uses a min-heap to track the current minimum across all runs.
    """
    readers = [open(f) for f in run_files]
    heap = []

    # Initialize heap with first element from each run
    for i, reader in enumerate(readers):
        line = reader.readline().strip()
        if line:
            heapq.heappush(heap, (int(line), i))  # (value, run_index)

    with open(output_file, 'w') as out:
        while heap:
            val, run_idx = heapq.heappop(heap)
            out.write(f"{val}\n")
            # Read next element from the same run
            line = readers[run_idx].readline().strip()
            if line:
                heapq.heappush(heap, (int(line), run_idx))

    for reader in readers:
        reader.close()
    for f in run_files:
        os.remove(f)
```

**Total I/O cost**: 2 reads + 2 writes per element per pass. With 1-pass merge: O(N) total I/O. With multi-pass merge: O(N × log_K(N/M)) I/O.

---

## Optimizations

### Replacement Selection (Larger Runs)
Instead of filling memory with M records, sort, and dump, use a priority queue. When you read a new element: if it's ≥ the last output element, add it to the current run's heap; otherwise, add it to the next run's heap. This produces runs of average size 2M instead of M — halving the number of runs and passes.

```python
def replacement_selection(stream, memory_size: int) -> list[list[int]]:
    """Produces runs of average size 2×memory_size."""
    runs = []
    current_heap = []
    next_heap = []
    current_run = []
    last_output = float('-inf')

    # Fill initial heap
    buffer = [next(stream) for _ in range(memory_size)]
    heapq.heapify(buffer)
    current_heap = buffer

    while current_heap or next_heap:
        if not current_heap:
            # Flush current run, start next
            runs.append(current_run)
            current_run = []
            current_heap = next_heap
            heapq.heapify(current_heap)
            next_heap = []
            last_output = float('-inf')

        val = heapq.heappop(current_heap)
        current_run.append(val)
        last_output = val

        try:
            new_val = next(stream)
            if new_val >= last_output:
                heapq.heappush(current_heap, new_val)
            else:
                next_heap.append(new_val)
        except StopIteration:
            pass

    if current_run:
        runs.append(current_run)
    return runs
```

### Multi-Pass Merging vs. One-Pass
If you have K runs and can hold K file handles in memory simultaneously, merge all runs in one pass. If K is too large (>available file descriptors or buffer memory), use multi-pass: merge K runs at a time, producing larger merged runs, then merge again.

**Example**: 1000 runs, memory holds 10 file handles at once.
- Pass 1: merge groups of 10 → 100 runs
- Pass 2: merge 10 groups of 10 → 10 runs
- Pass 3: merge 10 runs → 1 final output

Total passes: `log_10(1000) = 3`. Cost: 3 × N × (read + write) = 6N I/O operations.

### Polyphase Merge Sort
Advanced variant that distributes runs across multiple tapes/disks to minimize the number of merge passes. Used in tape-based systems; less relevant for disk-based systems with large block sizes.

---

## I/O Complexity Analysis

| Metric | Formula | Example (N=1TB, M=8GB, B=4MB block) |
|--------|---------|-------------------------------------|
| Number of initial runs | N/M | 1TB/8GB = 128 runs |
| I/O operations (1-pass merge) | 2N/B × 2 | 2×(1TB/4MB)×2 = 1M I/O ops |
| Total time (100 MB/s disk) | 2N/throughput | ~5.5 hours for single node |

With distributed external sort (MapReduce/Spark), the same 1TB sorts in minutes by parallelizing both phases across hundreds of nodes.

---

## Real-World System Design Connections

### PostgreSQL ORDER BY (External Sort)
When `work_mem` (default 4MB) is insufficient for the sort, PostgreSQL switches to disk-based external sort. It creates temporary files for sorted runs, merges them, and streams the result. The `EXPLAIN ANALYZE` output shows "Sort Method: external merge Disk: 8192kB" when this occurs.

Tuning: `SET work_mem = '256MB'` before a large sort reduces or eliminates external sort. But setting it globally risks OOM on concurrent queries.

### MapReduce Shuffle Phase
The MapReduce sort step is external sort distributed across the cluster. Each mapper produces sorted intermediate key-value pairs (Phase 1: local sort). The shuffle phase transfers data to reducers by key hash. Each reducer receives sorted input from multiple mappers and performs a K-way merge (Phase 2) to produce sorted input for the reduce function.

### Apache Spark Sort-Based Shuffle
Spark's sort-based shuffle replaces hash-based shuffle (which had too many small files). Each executor sorts its partition locally (external sort if data exceeds `spark.shuffle.spill.bufferSize`) then writes a single sorted file per shuffle partition. Reducers then do a K-way merge across executor files.

### Database Index Creation (B-Tree Bulk Load)
Creating a B-tree index on a 100GB column uses external sort to produce sorted key-pointer pairs, then bulk-loads the sorted sequence into the B-tree bottom-up. This is O(N log N) for sorting + O(N) for B-tree construction — much faster than inserting records one at a time (O(N log N) with high constant from random I/O).

### ClickHouse MergeTree
ClickHouse's MergeTree engine writes each insert as a sorted run (a "part"). Background merge jobs perform K-way merges of parts, similar to external sort Phase 2. The `ORDER BY` clause on the table determines the sort key. Queries that filter on the sort key use the sorted order for efficient range scans.

---

## Interview Application

**When to bring up external sorting in a system design interview:**

1. **"How would you sort 100TB of log data?"**: describe MapReduce/Spark external sort — local sort per node, shuffle sort, K-way merge at reducer.

2. **"Design a database sort operator"**: describe external merge sort with replacement selection and the role of `work_mem`/`sort_buffer_size`.

3. **"How does a database create an index on a large column?"**: bulk sort of key-pointer pairs using external sort, then B-tree construction.

4. **"How would you merge sorted data from 1000 different sources?"**: K-way merge with a min-heap — this is Phase 2 of external sort without Phase 1.

**The key insight to communicate**: external sorting is about minimizing I/O operations, not minimizing comparisons. The bottleneck is disk throughput, not CPU. Sequential I/O (reading sorted runs in order) is 100–1000× faster than random I/O (what a hash-based approach would require at large scale).

---

## Common Mistakes

1. **Using random-access algorithms at scale**: quicksort with random pivots causes random I/O at disk scale. Always use sequential-read algorithms (merge sort) for external data.

2. **Not accounting for the merge fan-in limit**: you can't merge 10,000 files simultaneously — you're limited by file descriptors and buffer memory per file. Multi-pass merging solves this.

3. **Forgetting Phase 1 in the design**: saying "I'll use a K-way merge" without explaining how you produced the sorted runs. Phase 1 is what makes external sort external.

4. **Assuming all data fits in the merge buffer**: the Phase 2 heap holds one element per run (plus a read buffer per file). For 1000 runs, that's 1000 heap entries — trivial. But if each run requires a 1MB read buffer, you need 1GB just for read buffers.
