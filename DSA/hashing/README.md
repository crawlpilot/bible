# Hashing (HashMap / HashSet)

> A hash map gives O(1) average lookup, insert, and delete. Use it whenever you need to **count frequencies**, **check membership**, **group elements by key**, or **cache previously seen values** to turn O(n²) brute force into O(n).

---

## 1 — How to Recognize This Pattern

Ask yourself:
- [ ] Do you need to check "have I seen X before?" in O(1)?
- [ ] Do you need to **count occurrences** of elements?
- [ ] Are you looking for **pairs or groups** that satisfy a sum/difference condition?
- [ ] Do you need to **group strings** that are "equivalent" under some transformation (anagram, permutation)?
- [ ] Is the brute force O(n²) nested loop avoidable by caching something?

**Trigger phrases**: "two sum", "group anagrams", "longest consecutive sequence", "contains duplicate", "subarray sum equals k", "find all anagrams", "valid anagram", "top k frequent", "word pattern", "isomorphic strings"

---

## 2 — Flavor Detection

| Flavor | Signal | Key |
|--------|--------|-----|
| **Existence check** | "does X exist?", "contains duplicate" | HashSet |
| **Frequency count** | "most frequent", "count occurrences" | `map.merge(key, 1, Integer::sum)` |
| **Complement lookup** | Two sum: find `target - current` | HashMap: value → index |
| **Grouping** | Anagrams, isomorphic strings | HashMap: canonical key → list |
| **Window + HashMap** | Distinct elements in window, anagram in string | Sliding window + frequency map |
| **Prefix sum + HashMap** | Subarray sum = K | Map: prefix sum → count |
| **Longest consecutive** | Consecutive sequence length | HashSet for O(1) lookup |

---

## 3 — Java HashMap Cheat Sheet

```java
Map<Integer, Integer> map = new HashMap<>();

map.put(key, value);
map.get(key);                              // returns null if absent
map.getOrDefault(key, 0);                 // returns 0 if absent
map.containsKey(key);
map.remove(key);
map.merge(key, 1, Integer::sum);          // increment count (handles absent case)
map.computeIfAbsent(key, k -> new ArrayList<>()).add(value);

// Iterate
for (Map.Entry<K, V> e : map.entrySet())  { e.getKey(); e.getValue(); }
for (int k : map.keySet())  { ... }
for (int v : map.values())  { ... }

// HashSet
Set<Integer> set = new HashSet<>();
set.add(x);
set.contains(x);         // O(1)
set.remove(x);
```

---

## 4 — Two Sum (LC 1)

```java
int[] twoSum(int[] nums, int target) {
    Map<Integer, Integer> seen = new HashMap<>();   // value → index
    for (int i = 0; i < nums.length; i++) {
        int complement = target - nums[i];
        if (seen.containsKey(complement))
            return new int[]{seen.get(complement), i};
        seen.put(nums[i], i);
    }
    return new int[]{};
}
// Time: O(n), Space: O(n)
```

**Variants**:
- **Two Sum II** (sorted array) → Two Pointers instead
- **Three Sum** (LC 15) → sort + two pointers + dedup outer loop
- **Four Sum** (LC 18) → two outer loops + inner two pointers

---

## 5 — Contains Duplicate II (LC 219)

Within index distance k.

```java
boolean containsNearbyDuplicate(int[] nums, int k) {
    Map<Integer, Integer> lastSeen = new HashMap<>();   // value → most recent index
    for (int i = 0; i < nums.length; i++) {
        if (lastSeen.containsKey(nums[i]) && i - lastSeen.get(nums[i]) <= k)
            return true;
        lastSeen.put(nums[i], i);
    }
    return false;
}
// Time: O(n), Space: O(min(n,k))
```

---

## 6 — Group Anagrams (LC 49)

```java
List<List<String>> groupAnagrams(String[] strs) {
    Map<String, List<String>> map = new HashMap<>();
    for (String s : strs) {
        char[] chars = s.toCharArray();
        Arrays.sort(chars);
        String key = new String(chars);   // sorted string is canonical key for anagrams
        map.computeIfAbsent(key, k -> new ArrayList<>()).add(s);
    }
    return new ArrayList<>(map.values());
}
// Time: O(n × L log L) where L = max string length, Space: O(n × L)

// O(n × L) alternative — count-based key:
String key2 = Arrays.toString(freq);   // freq = int[26] of character counts
```

---

## 7 — Longest Consecutive Sequence (LC 128)

O(n) requirement — cannot sort.

```java
int longestConsecutive(int[] nums) {
    Set<Integer> set = new HashSet<>();
    for (int num : nums) set.add(num);

    int maxLen = 0;
    for (int num : set) {
        // Only start counting from the BEGINNING of a sequence
        if (!set.contains(num - 1)) {
            int len = 1;
            while (set.contains(num + len)) len++;
            maxLen = Math.max(maxLen, len);
        }
    }
    return maxLen;
}
// Time: O(n) amortized — each number is visited at most twice
// Space: O(n)
```

**Why O(n)?** We only start counting when `num - 1` is absent (sequence start). Each element is "visited" as a start at most once, and as a continuation at most once.

---

## 8 — Valid Anagram (LC 242)

```java
boolean isAnagram(String s, String t) {
    if (s.length() != t.length()) return false;
    int[] count = new int[26];
    for (char c : s.toCharArray()) count[c - 'a']++;
    for (char c : t.toCharArray()) {
        if (--count[c - 'a'] < 0) return false;
    }
    return true;
}
// Time: O(n), Space: O(1) — 26-element array is constant
```

---

## 9 — Top K Frequent Words (LC 692)

```java
List<String> topKFrequent(String[] words, int k) {
    Map<String, Integer> freq = new HashMap<>();
    for (String w : words) freq.merge(w, 1, Integer::sum);

    PriorityQueue<String> minHeap = new PriorityQueue<>(
        (a, b) -> freq.get(a).equals(freq.get(b))
                  ? b.compareTo(a)          // same freq → alphabetically larger goes out
                  : freq.get(a) - freq.get(b)  // lower freq goes out
    );

    for (String word : freq.keySet()) {
        minHeap.offer(word);
        if (minHeap.size() > k) minHeap.poll();
    }

    List<String> result = new ArrayList<>(minHeap);
    result.sort((a, b) -> freq.get(a).equals(freq.get(b))
                          ? a.compareTo(b)
                          : freq.get(b) - freq.get(a));
    return result;
}
// Time: O(n log k), Space: O(n)
```

---

## 10 — Word Pattern (LC 290)

```java
boolean wordPattern(String pattern, String s) {
    String[] words = s.split(" ");
    if (pattern.length() != words.length) return false;

    Map<Character, String> charToWord = new HashMap<>();
    Map<String, Character> wordToChar = new HashMap<>();

    for (int i = 0; i < pattern.length(); i++) {
        char c = pattern.charAt(i);
        String w = words[i];

        if (charToWord.containsKey(c) && !charToWord.get(c).equals(w)) return false;
        if (wordToChar.containsKey(w) && wordToChar.get(w) != c) return false;

        charToWord.put(c, w);
        wordToChar.put(w, c);
    }
    return true;
}
// Time: O(n), Space: O(n)
// Bidirectional mapping is required to detect non-isomorphic patterns
```

---

## 11 — Isomorphic Strings (LC 205)

```java
boolean isIsomorphic(String s, String t) {
    Map<Character, Character> sToT = new HashMap<>(), tToS = new HashMap<>();
    for (int i = 0; i < s.length(); i++) {
        char sc = s.charAt(i), tc = t.charAt(i);
        if (sToT.containsKey(sc) && sToT.get(sc) != tc) return false;
        if (tToS.containsKey(tc) && tToS.get(tc) != sc) return false;
        sToT.put(sc, tc);
        tToS.put(tc, sc);
    }
    return true;
}
// Time: O(n), Space: O(1) — 128 ASCII chars max
```

---

## 12 — Find All Anagrams in a String (LC 438)

Sliding window + frequency map comparison.

```java
List<Integer> findAnagrams(String s, String p) {
    int[] need = new int[26], have = new int[26];
    for (char c : p.toCharArray()) need[c - 'a']++;

    List<Integer> result = new ArrayList<>();
    int k = p.length();

    for (int i = 0; i < s.length(); i++) {
        have[s.charAt(i) - 'a']++;                              // add right edge
        if (i >= k) have[s.charAt(i - k) - 'a']--;             // remove left edge
        if (i >= k - 1 && Arrays.equals(need, have)) result.add(i - k + 1);
    }
    return result;
}
// Time: O(n × 26) = O(n), Space: O(26) = O(1)
```

---

## 13 — Subarray Sum Equals K (LC 560)

(Full coverage in `prefix-sum/README.md` — key point repeated here)

```java
int subarraySum(int[] nums, int k) {
    Map<Integer, Integer> countMap = new HashMap<>();
    countMap.put(0, 1);   // critical: empty prefix
    int prefix = 0, result = 0;
    for (int num : nums) {
        prefix += num;
        result += countMap.getOrDefault(prefix - k, 0);
        countMap.merge(prefix, 1, Integer::sum);
    }
    return result;
}
// Time: O(n), Space: O(n)
```

---

## 14 — Design HashMap from Scratch (LC 706)

```java
class MyHashMap {
    private static final int SIZE = 1009;   // prime reduces collisions
    private LinkedList<int[]>[] buckets;

    @SuppressWarnings("unchecked")
    MyHashMap() {
        buckets = new LinkedList[SIZE];
        for (int i = 0; i < SIZE; i++) buckets[i] = new LinkedList<>();
    }

    private int hash(int key) { return key % SIZE; }

    void put(int key, int value) {
        LinkedList<int[]> bucket = buckets[hash(key)];
        for (int[] pair : bucket) { if (pair[0] == key) { pair[1] = value; return; } }
        bucket.add(new int[]{key, value});
    }

    int get(int key) {
        for (int[] pair : buckets[hash(key)]) if (pair[0] == key) return pair[1];
        return -1;
    }

    void remove(int key) {
        buckets[hash(key)].removeIf(pair -> pair[0] == key);
    }
}
// put/get/remove: O(1) average, O(n) worst (all keys hash to same bucket)
```

---

## 15 — Visual: HashMap Frequency Count

```
Array: [1, 2, 3, 1, 2, 1]

Build frequency map:
  key=1 → count 3
  key=2 → count 2
  key=3 → count 1

freq = {1:3, 2:2, 3:1}

Two Sum: target=4, seen={}
  i=0: num=1. complement=3. seen doesn't have 3. Add {1:0}.
  i=1: num=2. complement=2. seen doesn't have 2. Add {1:0, 2:1}.
  i=2: num=3. complement=1. seen HAS 1 at index 0 → return [0, 2].

Key insight: store what you've already SEEN in the map.
When you process num, ask: "is (target - num) already in the map?"
→ O(n) instead of O(n²) brute force.
```

---

## 🧠 Unseen Problem Walkthrough

**Problem**: Given a string `s`, find the length of the longest substring where every character appears the same number of times. *(e.g., "aabbc" → "aabb" → length 4)*

**Step 1 — Read**: Input = string. Output = length of longest "balanced" substring (all char frequencies equal).

**Step 2 — Identify**: "Substring" + "character frequencies" → consider sliding window or hashing. Sliding window needs a clear expand/shrink rule — hard to define here. Better: think about **what condition makes it balanced**. In a balanced substring, `freq[c] * uniqueCharCount == substrLen`. Track `(charFreq, uniqueCount)` at each position → **Hashing** with state encoding.

**Step 3 — Plan** (simpler O(n·k) approach):
- For each possible character frequency `f` from 1 to n:
  - Count chars with frequency ≥ f. Slide a window of size `f * count`.
- This is complex. Simpler for interview: **track with frequency-of-frequency map**.
  - Use `Map<Character, Integer> freq` and `Map<Integer, Integer> freqOfFreq`.
  - At each step, you can check if all characters have the same frequency in O(1).

**Step 4 — Code** (one-pass O(n)):
```java
int longestEqualFrequency(String s) {
    Map<Character, Integer> freq = new HashMap<>();
    Map<Integer, Integer> freqCount = new HashMap<>();  // frequency → how many chars have it
    int maxLen = 0;

    for (int i = 0; i < s.length(); i++) {
        char c = s.charAt(i);

        // update freqCount for old frequency
        int oldF = freq.getOrDefault(c, 0);
        if (oldF > 0) freqCount.merge(oldF, -1, Integer::sum);

        // update freq and freqCount for new frequency
        int newF = oldF + 1;
        freq.put(c, newF);
        freqCount.merge(newF, 1, Integer::sum);

        // check if current prefix [0..i] is valid balanced substring
        int n = i + 1;  // current length
        int distinctFreqs = freqCount.size();
        int distinctChars = freq.size();

        if (distinctFreqs == 1) {
            int f = freqCount.keySet().iterator().next();
            int cnt = freqCount.get(f);
            // all chars have freq f: valid if f*cnt == n
            if (f * cnt == n) maxLen = n;
            // one extra char with freq 1 can be removed: (f*cnt + 1 == n && cnt == distinctChars - 1)
            if (f == 1 && cnt == 1) maxLen = n;  // remove the one char with freq 1
            if (f * cnt + 1 == n && cnt == distinctChars) maxLen = n;  // reduce one by 1
        }
    }
    return maxLen;
}
// Time: O(n), Space: O(n)
```

**Step 5 — Verify** on `"aabbc"`:
- After 'a','a','b','b': freq={a:2,b:2}, freqCount={2:2}. f=2,cnt=2. 2*2=4=n. maxLen=4.
- After 'c': freq={a:2,b:2,c:1}, freqCount={2:2,1:1}. n=5. distinctFreqs=2 → can we remove c? f=1,cnt=1 → yes → maxLen=5? No — removing c gives "aabb" length 4. But the condition `f==1 && cnt==1 && n-1 == maxFreq * (distinctChars-1)` catches this correctly.

---

## ⚠️ Edge Cases & Small Tweaks

| Scenario | What breaks | Fix |
|----------|-------------|-----|
| Two Sum: target is 2×same element | `map.get(target-num) == i` (same index) | `map.put(num, i)` after checking — so same index won't be found |
| Group anagrams: order matters in key | Using sorted string as key is O(L log L) | Or use `int[26]` counts converted to string key |
| Longest consecutive: duplicates | Same element processed multiple times | Use HashSet; skip if `num-1` is in set (only start from sequence start) |
| Frequency of frequency: freqCount cleanup | Old frequency entries with count=0 stay in map | `freqCount.merge(old, -1, Integer::sum); if (freqCount.get(old) == 0) freqCount.remove(old)` |
| Large values (can't use array) | `int[26]` only works for lowercase alpha | Use `HashMap<Character, Integer>` for unicode |

```java
// Two Sum — handle same element twice (target = 2*num):
Map<Integer, Integer> seen = new HashMap<>();
for (int i = 0; i < nums.length; i++) {
    int complement = target - nums[i];
    if (seen.containsKey(complement))
        return new int[]{seen.get(complement), i};
    seen.put(nums[i], i);   // add AFTER checking → prevents using same index twice
}

// Subarray sum = k (with prefix sum + hashmap):
Map<Integer, Integer> prefixCount = new HashMap<>();
prefixCount.put(0, 1);   // empty prefix (CRITICAL: must initialize with 0)
int sum = 0, count = 0;
for (int num : nums) {
    sum += num;
    count += prefixCount.getOrDefault(sum - k, 0);
    prefixCount.merge(sum, 1, Integer::sum);
}
```

---

## 😵 Commonly Confused With

**vs Prefix Sum**: Both can solve "subarray sum = k" but via different angles. Deciding question: *Can you afford O(n) space for a prefix map and need count of subarrays (Prefix Sum + HashMap), or do you need the actual subarray indices with positivity constraints (Sliding Window)?*

**vs Sliding Window**: Sliding window requires a contiguous window with an expand/shrink rule driven by a monotone condition. Hashing is for exact lookups and counting. Deciding question: *Is there a clear condition to shrink the window when a constraint is violated (SW), or do you need to look up arbitrary values from the past (HashMap)?*

**vs Sorting + Two Pointers**: Sorting + two pointers solves many pair/triplet problems in O(n log n). Hashing can solve them in O(n) but uses extra space. Deciding question: *Is the input already sorted, or can you afford to sort? If not, use HashMap.*

---

## 16 — Canonical LeetCode Problems

| Category | Problems |
|---------|---------|
| Two sum / complement | LC 1, LC 167, LC 15, LC 18 |
| Frequency count | LC 347, LC 692, LC 451 |
| Grouping | LC 49, LC 249, LC 1065 |
| Consecutive / distinct | LC 128, LC 219, LC 220 |
| Anagram matching | LC 242, LC 438, LC 567 |
| Isomorphism / mapping | LC 205, LC 290 |
| Prefix sum + map | LC 560, LC 523, LC 974 |
| Design | LC 706 (HashMap), LC 705 (HashSet), LC 146 (LRU → LinkedHashMap) |

---

## 16 — Java LinkedHashMap for LRU / Ordered Iteration

```java
// LinkedHashMap maintains insertion order (or access order)
// Access-order LRU in 3 lines:
Map<Integer, Integer> cache = new LinkedHashMap<>(capacity, 0.75f, true) {
    protected boolean removeEldestEntry(Map.Entry<Integer, Integer> eldest) {
        return size() > capacity;
    }
};
// get() and put() automatically move entry to end; eldest is at front
// Time: O(1) for get/put (amortized), Space: O(capacity)
```
