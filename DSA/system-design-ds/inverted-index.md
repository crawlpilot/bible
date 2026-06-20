# Inverted Index
**Category**: Search Data Structure — maps terms to document IDs; used in Elasticsearch, Lucene, Solr, every search engine

---

## 1. The Problem It Solves

### Full-Text Search Without an Inverted Index

"Find all documents containing the word 'distributed'"

Without an index:
```
Scan every document, tokenise every word, check for match
10M documents × 1KB avg = 10 GB scanned per query
At 100 QPS: 1 TB/sec I/O → impossible
```

An **inverted index** flips the structure: instead of document → words, it stores word → [document IDs]. A query becomes a lookup in a hashtable, not a full scan.

```
Forward index (what documents have):
  doc_1: ["distributed", "systems", "design"]
  doc_2: ["distributed", "hash", "table"]
  doc_3: ["hash", "ring", "consistent"]

Inverted index (what terms map to):
  "distributed" → [doc_1, doc_2]
  "systems"     → [doc_1]
  "design"      → [doc_1]
  "hash"        → [doc_2, doc_3]
  "table"       → [doc_2]
  "ring"        → [doc_3]
  "consistent"  → [doc_3]

Query "distributed AND hash":
  intersection([doc_1, doc_2], [doc_2, doc_3]) = [doc_2]   ← O(n) merge, not O(N×doc_size)
```

---

## 2. Structure

### 2.1 Core Components

```
Dictionary (term → posting list pointer):
  Stored as hash map or sorted array (for prefix search)
  In Lucene: FST (Finite State Transducer) — compressed trie with shared prefixes/suffixes

Posting List (per term):
  Sorted list of (docID, [positions]) pairs
  docID: document identifier
  positions: byte offsets of the term in the document (enables phrase queries)

Example posting list for "distributed":
  [
    (doc_1, [0, 45]),        ← appears at positions 0 and 45 in doc_1
    (doc_2, [12]),           ← appears at position 12 in doc_2
    (doc_5, [7, 89, 201]),   ← appears three times in doc_5
  ]
```

### 2.2 TF-IDF Scoring

Not all matching documents are equally relevant. TF-IDF ranks them:

```
TF  (term frequency):   how often the term appears in this document
                        TF(t, d) = count(t in d) / total_terms(d)

IDF (inverse document   log(total_docs / docs_containing_t)
     frequency):        rare terms get higher weight

TF-IDF(t, d) = TF(t, d) × IDF(t)
```

**BM25** (Okapi BM25) — used by Elasticsearch and Lucene — improves on TF-IDF with saturation (diminishing returns for term frequency) and document length normalisation.

---

## 3. Java Implementation

### 3.1 Basic Inverted Index

```java
import java.util.*;
import java.util.stream.*;

public class InvertedIndex {

    // term → sorted posting list of (docId, positions)
    private final Map<String, List<Posting>> index = new HashMap<>();
    // docId → original document content
    private final Map<Integer, String> documents = new HashMap<>();
    private int nextDocId = 0;

    public record Posting(int docId, List<Integer> positions) {}

    public int addDocument(String content) {
        int docId = nextDocId++;
        documents.put(docId, content);
        List<String> tokens = tokenise(content);
        for (int pos = 0; pos < tokens.size(); pos++) {
            String term = tokens.get(pos);
            List<Posting> postings = index.computeIfAbsent(term, k -> new ArrayList<>());
            // Find or create posting for this docId
            if (!postings.isEmpty() && postings.getLast().docId() == docId) {
                postings.getLast().positions().add(pos);
            } else {
                List<Integer> positions = new ArrayList<>();
                positions.add(pos);
                postings.add(new Posting(docId, positions));
            }
        }
        return docId;
    }

    // Boolean AND query
    public List<Integer> searchAnd(String... terms) {
        List<List<Integer>> postingLists = new ArrayList<>();
        for (String term : terms) {
            List<Posting> postings = index.getOrDefault(normalise(term), Collections.emptyList());
            if (postings.isEmpty()) return Collections.emptyList(); // short-circuit
            postingLists.add(postings.stream().map(Posting::docId).collect(Collectors.toList()));
        }
        // Sort by list size ascending — intersect smallest first (most selective first)
        postingLists.sort(Comparator.comparingInt(List::size));
        return postingLists.stream().reduce(this::intersect).orElse(Collections.emptyList());
    }

    // Boolean OR query
    public List<Integer> searchOr(String... terms) {
        Set<Integer> result = new TreeSet<>();
        for (String term : terms) {
            for (Posting p : index.getOrDefault(normalise(term), Collections.emptyList())) {
                result.add(p.docId());
            }
        }
        return new ArrayList<>(result);
    }

    // Phrase query: "term1 term2" must appear consecutively
    public List<Integer> searchPhrase(String phrase) {
        String[] terms = phrase.trim().split("\\s+");
        if (terms.length == 0) return Collections.emptyList();

        List<Posting> firstPostings = index.getOrDefault(normalise(terms[0]), Collections.emptyList());
        List<Integer> candidates = firstPostings.stream().map(Posting::docId).collect(Collectors.toList());

        for (int i = 1; i < terms.length; i++) {
            List<Posting> nextPostings = index.getOrDefault(normalise(terms[i]), Collections.emptyList());
            Map<Integer, List<Integer>> nextPosMap = new HashMap<>();
            for (Posting p : nextPostings) nextPosMap.put(p.docId(), p.positions());

            final int offset = i;
            candidates = candidates.stream().filter(docId -> {
                List<Integer> nextPos = nextPosMap.get(docId);
                if (nextPos == null) return false;
                // Check if any position in term[0] is followed by term[i] at +offset
                List<Integer> firstPos = getPositions(firstPostings, docId);
                for (int p : firstPos) {
                    if (Collections.binarySearch(nextPos, p + offset) >= 0) return true;
                }
                return false;
            }).collect(Collectors.toList());
        }
        return candidates;
    }

    // Ranked search using TF-IDF
    public List<RankedResult> searchRanked(String query) {
        String[] terms = tokenise(query).toArray(new String[0]);
        int totalDocs = documents.size();
        Map<Integer, Double> scores = new HashMap<>();

        for (String term : terms) {
            List<Posting> postings = index.getOrDefault(term, Collections.emptyList());
            if (postings.isEmpty()) continue;

            double idf = Math.log((double)(totalDocs + 1) / (postings.size() + 1)) + 1;

            for (Posting posting : postings) {
                String doc = documents.get(posting.docId());
                int docLen = tokenise(doc).size();
                double tf = (double) posting.positions().size() / docLen;
                scores.merge(posting.docId(), tf * idf, Double::sum);
            }
        }

        return scores.entrySet().stream()
            .map(e -> new RankedResult(e.getKey(), documents.get(e.getKey()), e.getValue()))
            .sorted(Comparator.comparingDouble(RankedResult::score).reversed())
            .collect(Collectors.toList());
    }

    public record RankedResult(int docId, String content, double score) {}

    private List<Integer> intersect(List<Integer> a, List<Integer> b) {
        List<Integer> result = new ArrayList<>();
        int i = 0, j = 0;
        while (i < a.size() && j < b.size()) {
            int cmp = Integer.compare(a.get(i), b.get(j));
            if (cmp == 0)      { result.add(a.get(i)); i++; j++; }
            else if (cmp < 0)  i++;
            else               j++;
        }
        return result;
    }

    private List<Integer> getPositions(List<Posting> postings, int docId) {
        for (Posting p : postings) if (p.docId() == docId) return p.positions();
        return Collections.emptyList();
    }

    private List<String> tokenise(String text) {
        return Arrays.stream(text.toLowerCase().split("[^a-z0-9]+"))
            .filter(s -> !s.isEmpty() && !STOP_WORDS.contains(s))
            .collect(Collectors.toList());
    }

    private String normalise(String term) { return term.toLowerCase().trim(); }

    private static final Set<String> STOP_WORDS = Set.of(
        "a", "an", "the", "is", "in", "it", "of", "and", "or", "to", "for", "with"
    );
}
```

### 3.2 Usage

```java
InvertedIndex idx = new InvertedIndex();
idx.addDocument("Distributed systems use consistent hashing for partitioning");
idx.addDocument("Consistent hashing minimises data movement on node changes");
idx.addDocument("The distributed hash table stores key value pairs");
idx.addDocument("Kafka uses a distributed log for event streaming");

System.out.println(idx.searchAnd("distributed", "hashing"));
// → [0] — only doc_0 has both "distributed" and "hashing"

System.out.println(idx.searchPhrase("consistent hashing"));
// → [0, 1] — both docs contain this phrase consecutively

idx.searchRanked("distributed systems").forEach(r ->
    System.out.printf("%.3f  %s%n", r.score(), r.content()));
// Ranked by TF-IDF relevance
```

### 3.3 Compressed Posting List (Delta + VarInt Encoding)

Posting lists store millions of sorted docIDs. Raw int storage is wasteful; Lucene uses delta encoding + variable-length integers:

```java
import java.io.*;
import java.util.*;

public class CompressedPostingList {

    // Encode: store gaps between sorted docIDs, each as VarInt
    public static byte[] encode(List<Integer> sortedDocIds) throws IOException {
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        int prev = 0;
        for (int docId : sortedDocIds) {
            int delta = docId - prev;
            writeVarInt(baos, delta);
            prev = docId;
        }
        return baos.toByteArray();
    }

    public static List<Integer> decode(byte[] data) throws IOException {
        DataInputStream dis = new DataInputStream(new ByteArrayInputStream(data));
        List<Integer> result = new ArrayList<>();
        int cur = 0;
        while (dis.available() > 0) {
            cur += readVarInt(dis);
            result.add(cur);
        }
        return result;
    }

    // VarInt: 7 bits of data per byte, MSB=1 means more bytes follow
    private static void writeVarInt(OutputStream out, int value) throws IOException {
        while ((value & ~0x7F) != 0) {
            out.write((value & 0x7F) | 0x80);
            value >>>= 7;
        }
        out.write(value);
    }

    private static int readVarInt(DataInputStream in) throws IOException {
        int result = 0, shift = 0;
        byte b;
        do {
            b = in.readByte();
            result |= (b & 0x7F) << shift;
            shift += 7;
        } while ((b & 0x80) != 0);
        return result;
    }

    // Example compression ratio:
    // 1M sequential docIDs [0..999999]: raw = 4 MB, VarInt delta = ~1.1 MB (~3.6× compression)
    // Sparse random docIDs: deltas can be large; PFOR (Patched Frame of Reference) used in Lucene
}
```

### 3.4 Distributed Inverted Index (Elasticsearch-style)

```java
import java.util.*;

public class DistributedSearchIndex {

    // Simulates Elasticsearch shard routing
    private final int numShards;
    private final List<InvertedIndex> shards;

    public DistributedSearchIndex(int numShards) {
        this.numShards = numShards;
        this.shards = new ArrayList<>();
        for (int i = 0; i < numShards; i++) shards.add(new InvertedIndex());
    }

    // Documents routed to shard by hash(docId) % numShards
    public int indexDocument(String docId, String content) {
        int shardId = Math.abs(docId.hashCode()) % numShards;
        return shards.get(shardId).addDocument(content);
    }

    // Scatter-gather: query all shards in parallel, merge results
    public List<InvertedIndex.RankedResult> search(String query) {
        // In production: parallel RPC to each shard
        List<InvertedIndex.RankedResult> merged = new ArrayList<>();
        for (InvertedIndex shard : shards) {
            merged.addAll(shard.searchRanked(query));
        }
        // Global re-rank (global IDF adjustment needed in prod — simplified here)
        merged.sort(Comparator.comparingDouble(InvertedIndex.RankedResult::score).reversed());
        return merged;
    }
}
```

---

## 4. Lucene Segment Architecture

```
Lucene index on disk:
  segment_0/
    ├── .fst      — term dictionary (FST: compressed trie)
    ├── .doc      — posting lists (docIDs, delta-encoded)
    ├── .pos      — position lists
    ├── .pay      — payloads (custom per-field data)
    ├── .nvd/.nvm — norms (per-field length normalisation)
    └── .dvd/.dvm — doc values (columnar storage for sorting/aggregations)
  segment_1/
    └── ...
  segments_N       — commit point: which segments are live

Write path:
  Documents buffered in RAM (IndexWriter) → flushed as new segment
  Background merging: small segments merged into larger ones (like LSM compaction)
  Merge reduces segment count → fewer files to open → faster searches

Read path:
  IndexReader opens all segments
  Query executed on each segment → results merged
  Deleted docs: tracked in .liv file (bitset); filtered post-merge
```

---

## 5. Trade-Offs

| Attribute | Inverted Index | Forward Index | Column Store |
|---|---|---|---|
| Full-text query | Excellent | O(N) scan | N/A |
| Phrase query | O(doc_freq) with positions | O(N) | N/A |
| Aggregations/sort | Slow (needs doc values) | N/A | Excellent |
| Storage | Medium (posting lists) | Low | Low (columnar) |
| Write | Append (LSM-like) | Easy | Medium |
| Update | Delete + reindex | In-place | Delete + reinsert |

Elasticsearch stores both an inverted index (for search) and doc values (columnar, for aggregations/sort) — dual representation for the same data.

---

## 6. Where Inverted Indexes Appear at FAANG

| System | Use | Notes |
|---|---|---|
| **Elasticsearch** | Full-text + structured search | Lucene under the hood, distributed sharding |
| **Google Search** | Web indexing | Inverted index at planetary scale, MapReduce built |
| **Facebook** | Post/comment search | Real-time inverted index with freshness constraints |
| **LinkedIn** | People search, job search | Galene (custom Lucene) with entity-aware ranking |
| **Slack** | Message search | Per-workspace Elasticsearch, 6+ billion messages indexed |
| **GitHub** | Code search | Zoekt (trigram-based inverted index for code) |

---

## 7. FAANG Interview Callouts

**"Design a full-text search system for 1B documents:"**
> Shard the inverted index across N nodes by document hash. Each shard runs Lucene. Write path: Kafka → indexing service → Lucene segment flush. Read path: scatter query to all shards (parallel), each shard returns top-K local results, coordinator merges + re-ranks global top-K. Freshness SLA drives flush frequency — near-real-time (NRT) search flushes segments every 1s (Elasticsearch default). Relevance: BM25 + learning-to-rank (feature vectors from click signals).

**"How does Elasticsearch handle a terms query vs a full-text query differently?"**
> A `terms` query (exact match) looks up the posting list for the exact term — single dictionary lookup, O(1). A `match` query (full-text) tokenises the input, looks up each token's posting list, then runs a BM25 scorer across the merged results. `match_phrase` additionally filters by position proximity. Analysis chain (tokeniser + filters) must match between index-time and query-time or relevance breaks silently.

**Follow-up questions to expect:**
1. "What is an FST and why does Lucene use it for its term dictionary?" → Finite State Transducer: a compressed automaton that maps strings to values. Lucene's term dictionary fits in off-heap memory (not GC'd), supports prefix/range iteration, and deduplicates shared prefixes/suffixes — a 100M-term dictionary takes ~1 GB vs ~10 GB naive.
2. "How would you support real-time indexing (documents searchable within 1 second)?" → Near-real-time search: IndexWriter periodically calls `commit()` — flushing in-memory buffer to a new segment. Segments are searchable without a full commit. Elasticsearch default: 1s refresh interval. Tradeoff: more frequent flushes → smaller segments → more merges → higher I/O.
3. "How do you handle index updates (a document changes)?" → Lucene is append-only. Updates = logical delete (mark docID in `.liv` bitset) + reindex as a new document. Deleted docs cleaned up during segment merge. High churn → frequent merges → write amplification. Partial updates (update one field) require fetching the old doc, merging, reindexing.
