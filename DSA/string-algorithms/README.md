# String Algorithms (Pattern Matching)

> When the problem asks "does pattern P occur in text T?" or "find all/first occurrence", brute force is O(n·m). KMP reduces to O(n+m) by never re-examining text characters. Rabin-Karp uses rolling hashes to match in O(n+m) average. Z-function solves both pattern matching and structural string problems (period, border) in O(n+m).

---

## 1 — How to Recognize This Pattern

Ask yourself:
- [ ] Does the problem need to find a **substring/pattern** inside a larger string?
- [ ] Does it ask if a string is a **rotation** of another?
- [ ] Does it ask for **shortest period**, **border** (prefix = suffix), or **KMP failure function**?
- [ ] Does it ask to count **distinct substrings** or **palindromic substrings** efficiently?
- [ ] Does it require matching with **wildcards** or **repeated patterns**?

**Trigger phrases**: "find first occurrence", "is a substring of", "repeated substring pattern", "shortest repeating unit", "string rotation", "anagram in string", "longest palindromic substring", "multiple pattern matching"

---

## 2 — Flavor Detection

| Flavor | Use | Time |
|--------|-----|------|
| Single pattern in text, exact match | KMP | O(n+m) |
| Multiple patterns in text | Aho-Corasick | O(n + ΣpatLen + matches) |
| Pattern matching with hash collision tolerance | Rabin-Karp | O(n+m) average |
| Structural analysis (period, border, rotation) | Z-function or KMP failure function | O(n) |
| Longest palindromic substring | Manacher's algorithm | O(n) |
| All palindromic substrings / count | Manacher's or expand-around-center | O(n) / O(n²) |
| Longest common subsequence | DP (see `advanced-dp/`) | O(n·m) |

---

## 3 — KMP (Knuth-Morris-Pratt)

### The Failure Function (lps array)

`lps[i]` = length of the **longest proper prefix of pattern[0..i] that is also a suffix**.

This is the key: when a mismatch occurs at pattern position `j`, instead of going back to the start of the pattern, we jump to `lps[j-1]`. We never recheck text characters.

```java
// Build lps (failure function) for pattern
int[] buildLPS(String pattern) {
    int m = pattern.length();
    int[] lps = new int[m];
    int len = 0;   // length of previous longest prefix-suffix
    int i = 1;

    while (i < m) {
        if (pattern.charAt(i) == pattern.charAt(len)) {
            lps[i++] = ++len;
        } else if (len > 0) {
            len = lps[len - 1];  // don't increment i — try shorter prefix
        } else {
            lps[i++] = 0;
        }
    }
    return lps;
}
```

### KMP Search — Find First Occurrence

```java
int kmpSearch(String text, String pattern) {
    int n = text.length(), m = pattern.length();
    int[] lps = buildLPS(pattern);
    int i = 0, j = 0;   // i = text pointer, j = pattern pointer

    while (i < n) {
        if (text.charAt(i) == pattern.charAt(j)) {
            i++; j++;
        }
        if (j == m) {
            return i - j;    // found at index (i - j)
            // for ALL occurrences: add to list, then j = lps[j - 1];
        } else if (i < n && text.charAt(i) != pattern.charAt(j)) {
            if (j > 0) j = lps[j - 1];  // jump back using lps
            else i++;
        }
    }
    return -1;   // not found
}
// Time: O(n+m), Space: O(m) for lps array
```

### All Occurrences

```java
List<Integer> kmpAllOccurrences(String text, String pattern) {
    int n = text.length(), m = pattern.length();
    int[] lps = buildLPS(pattern);
    List<Integer> result = new ArrayList<>();
    int i = 0, j = 0;

    while (i < n) {
        if (text.charAt(i) == pattern.charAt(j)) { i++; j++; }
        if (j == m) {
            result.add(i - j);
            j = lps[j - 1];          // continue searching after this match
        } else if (i < n && text.charAt(i) != pattern.charAt(j)) {
            if (j > 0) j = lps[j - 1];
            else i++;
        }
    }
    return result;
}
```

---

## 4 — Repeated Substring Pattern (LC 459) — KMP Trick

"Does string s consist of k repetitions of some substring?"

```java
boolean repeatedSubstringPattern(String s) {
    // Trick: if s is made of repetitions, (s + s) without first and last char contains s
    String doubled = (s + s).substring(1, 2 * s.length() - 1);
    return doubled.contains(s);   // use KMP for O(n) instead of O(n²)
}

// Equivalent KMP approach: if lps[n-1] != 0 AND n % (n - lps[n-1]) == 0
boolean repeatedSubstringKMP(String s) {
    int[] lps = buildLPS(s);
    int n = s.length();
    int period = n - lps[n - 1];
    return lps[n - 1] != 0 && n % period == 0;
}
// period = shortest repeating unit length
```

---

## 5 — Z-Function

`z[i]` = length of the longest substring starting at `s[i]` that **matches a prefix of s**.

- `z[0]` is undefined (usually set to 0 or n).
- If `z[i] = k`, then `s[i..i+k-1] == s[0..k-1]`.

```java
int[] zFunction(String s) {
    int n = s.length();
    int[] z = new int[n];
    int l = 0, r = 0;    // current Z-box [l, r]

    for (int i = 1; i < n; i++) {
        if (i < r) z[i] = Math.min(r - i, z[i - l]);
        while (i + z[i] < n && s.charAt(z[i]) == s.charAt(i + z[i]))
            z[i]++;
        if (i + z[i] > r) { l = i; r = i + z[i]; }
    }
    return z;
}
// Time: O(n), Space: O(n)
```

### Pattern Matching with Z-Function

```java
List<Integer> zSearch(String text, String pattern) {
    String combined = pattern + "$" + text;   // $ = separator not in alphabet
    int[] z = zFunction(combined);
    int m = pattern.length();
    List<Integer> result = new ArrayList<>();

    for (int i = m + 1; i < combined.length(); i++)
        if (z[i] == m) result.add(i - m - 1);   // match at text index (i - m - 1)
    return result;
}
```

### Shortest Period with Z-Function

```java
int shortestPeriod(String s) {
    int n = s.length();
    int[] z = zFunction(s);
    for (int len = 1; len < n; len++)
        if (n % len == 0 && z[len] == n - len)
            return len;
    return n;   // s itself is the shortest period
}
```

---

## 6 — Rabin-Karp (Rolling Hash)

Use a polynomial rolling hash to compare substrings in O(1) after O(n) preprocessing.

```java
// Rabin-Karp: find first occurrence of pattern in text
int rabinKarp(String text, String pattern) {
    int n = text.length(), m = pattern.length();
    if (m > n) return -1;

    long MOD = 1_000_000_007L, BASE = 31L;
    long patHash = 0, winHash = 0, power = 1;

    // Compute pattern hash and initial window hash
    for (int i = 0; i < m; i++) {
        patHash = (patHash * BASE + (pattern.charAt(i) - 'a' + 1)) % MOD;
        winHash = (winHash * BASE + (text.charAt(i)   - 'a' + 1)) % MOD;
        if (i > 0) power = power * BASE % MOD;
    }

    for (int i = 0; i <= n - m; i++) {
        if (winHash == patHash) {
            // Hash match → verify character by character (handle collision)
            if (text.substring(i, i + m).equals(pattern)) return i;
        }
        if (i < n - m) {
            // Roll the window: remove leftmost char, add new rightmost char
            winHash = (winHash - (text.charAt(i) - 'a' + 1) * power % MOD + MOD) % MOD;
            winHash = (winHash * BASE + (text.charAt(i + m) - 'a' + 1)) % MOD;
        }
    }
    return -1;
}
// Time: O(n+m) average (O(n·m) worst with many hash collisions)
```

**Double hashing** (two independent hashes) reduces collision probability to ~1/10¹⁸.

---

## 7 — Manacher's Algorithm (Longest Palindromic Substring — LC 5)

Finds all palindromic substrings centered at every position in O(n).

```java
String longestPalindrome(String s) {
    // Transform: "abc" → "#a#b#c#" to handle even/odd uniformly
    StringBuilder t = new StringBuilder("#");
    for (char c : s.toCharArray()) { t.append(c); t.append('#'); }
    String T = t.toString();
    int n = T.length();

    int[] p = new int[n];   // p[i] = radius of palindrome centered at T[i]
    int center = 0, right = 0;

    for (int i = 0; i < n; i++) {
        int mirror = 2 * center - i;
        if (i < right) p[i] = Math.min(right - i, p[mirror]);

        // Expand around center i
        while (i - p[i] - 1 >= 0 && i + p[i] + 1 < n
               && T.charAt(i - p[i] - 1) == T.charAt(i + p[i] + 1))
            p[i]++;

        if (i + p[i] > right) { center = i; right = i + p[i]; }
    }

    // Find the max radius
    int maxLen = 0, centerIdx = 0;
    for (int i = 0; i < n; i++) if (p[i] > maxLen) { maxLen = p[i]; centerIdx = i; }

    // Map back to original string
    int start = (centerIdx - maxLen) / 2;
    return s.substring(start, start + maxLen);
}
// Time: O(n), Space: O(n)
```

**Simpler O(n²) expand-around-center** (acceptable for interviews when n ≤ 10³):
```java
String longestPalindromeSimple(String s) {
    int start = 0, maxLen = 1;
    for (int i = 0; i < s.length(); i++) {
        // Odd length palindromes
        int lo = i, hi = i;
        while (lo >= 0 && hi < s.length() && s.charAt(lo) == s.charAt(hi)) { lo--; hi++; }
        if (hi - lo - 1 > maxLen) { maxLen = hi - lo - 1; start = lo + 1; }
        // Even length palindromes
        lo = i; hi = i + 1;
        while (lo >= 0 && hi < s.length() && s.charAt(lo) == s.charAt(hi)) { lo--; hi++; }
        if (hi - lo - 1 > maxLen) { maxLen = hi - lo - 1; start = lo + 1; }
    }
    return s.substring(start, start + maxLen);
}
```

---

## 8 — String Rotation Check

"Is t a rotation of s?" → check if `t` is a substring of `s + s`.

```java
boolean isRotation(String s, String t) {
    return s.length() == t.length() && (s + s).contains(t);
}
// Why: any rotation of s appears as a substring of s+s.
// "abcde" rotated by 2 = "cdeab". "cdeab" is in "abcdeabcde" ✓
```

---

## 9 — Complexity Reference

| Algorithm | Preprocessing | Search/Query | Space |
|-----------|--------------|--------------|-------|
| Brute force | O(1) | O(n·m) | O(1) |
| KMP | O(m) lps build | O(n) | O(m) |
| Z-function | O(n+m) | O(n+m) | O(n+m) |
| Rabin-Karp | O(m) | O(n) avg, O(nm) worst | O(1) |
| Manacher | O(n) | O(n) | O(n) |
| Aho-Corasick | O(Σ|patterns|) | O(n + matches) | O(Σ|patterns|) |

---

## 10 — FAANG Interview Moves

1. **KMP lps derivation**: Interviewers often ask you to derive the lps array. Walk through `"aabaab"` → `[0,1,0,1,2,3]` step by step, explaining why each value is set.
2. **The trick question**: "Check if string A is a rotation of B" → most people try O(n²); the O(n) trick (`(A+A).contains(B)`) or KMP is the expected answer.
3. **Period = n - lps[n-1]**: The shortest repeating period of a string can be read directly from the last lps value. `"abcabcabc"` → lps[8]=6, period=9-6=3 → "abc" is the unit. State this theorem explicitly.
4. **Double hash for Rabin-Karp**: Mention it to avoid spurious collisions — shows depth of knowledge.
5. **Know when to use expand-around-center**: For palindrome problems, O(n²) expand is acceptable in most interviews. Manacher's is the O(n) flex — mention it as a follow-up.

---

## 11 — Visual: KMP Failure Function & Mismatch Recovery

```
Pattern: "aabaabaaa"
Build lps:
  i=0: lps[0]=0 (by definition)
  i=1: s[1]='a'==s[0]='a' → lps[1]=1
  i=2: s[2]='b'≠s[1]='a'. len=1→try s[2]vs s[lps[0]]=s[0]='a'. 'b'≠'a'. lps[2]=0
  i=3: s[3]='a'==s[0]='a' → lps[3]=1
  i=4: s[4]='a'==s[1]='a' → lps[4]=2
  i=5: s[5]='b'==s[2]='b' → lps[5]=3
  i=6: s[6]='a'==s[3]='a' → lps[6]=4
  i=7: s[7]='a'==s[4]='a' → lps[7]=5
  i=8: s[8]='a'≠s[5]='b'. len=5→try lps[4]=2. s[8]='a'==s[2]? 'a'≠'b'. len=2→try lps[1]=1. s[8]='a'==s[1]='a'→lps[8]=2

lps = [0, 1, 0, 1, 2, 3, 4, 5, 2]

WHY THIS MATTERS:
  Text:    "aabaabaaaaabaabaaa"
  Pattern: "aabaabaaa"
  
  When a mismatch happens at text[i], pattern[j]:
  Instead of resetting j=0 (brute force), we set j = lps[j-1].
  This skips re-examining characters we KNOW must match because 
  lps tells us the longest prefix of the pattern that already lines up.
```

---

## 🧠 Unseen Problem Walkthrough

**Problem**: Given string `s`, check if it can be constructed by taking a substring and appending it multiple times. *(LC 459 — Repeated Substring Pattern)*

**Step 1 — Read**: Input = `s`. Output = boolean. "Repeated" means s = k repetitions of some t (k ≥ 2).

**Step 2 — Identify**: Structural string property — "period" of the string. This is exactly what the KMP failure function encodes: if `n % (n - lps[n-1]) == 0` and `lps[n-1] != 0`, then the string has a proper period.

**Step 3 — Plan**:
- Build lps for s.
- Check: `period = n - lps[n-1]`. If `n % period == 0` and `lps[n-1] != 0` → true.
- Alternative: check if s is in `(s+s)[1..2n-2]`.

**Step 4 — Code**:
```java
boolean repeatedSubstringPattern(String s) {
    int n = s.length();
    int[] lps = buildLPS(s);
    int period = n - lps[n - 1];
    return lps[n - 1] != 0 && n % period == 0;
}
// Time: O(n), Space: O(n) for lps
```

**Step 5 — Verify**:
- `s = "abcabcabc"` (n=9): lps[8]=6. period=9-6=3. 9%3=0. → true. ✓
- `s = "abab"` (n=4): lps[3]=2. period=4-2=2. 4%2=0. → true. ✓
- `s = "abac"` (n=4): lps[3]=1. period=4-1=3. 4%3≠0. → false. ✓

---

## ⚠️ Edge Cases & Small Tweaks

| Scenario | What breaks | Fix |
|----------|-------------|-----|
| Pattern longer than text | Can't match | Return -1 / false immediately: `if (m > n) return -1` |
| Empty pattern | Matches everywhere | Define: return index 0, or handle `m=0` as special case |
| All same characters "aaaa" | lps=n-1, period=1 | Correctly detected as repeated pattern |
| KMP on unicode / multibyte | `charAt` works on Java chars (UTF-16) | For full unicode, convert to `codePoints()` array |
| Rabin-Karp hash collision | Wrong match returned | Always verify with `equals()` after hash match |
| Manacher with even-length palindrome | Center is between characters | The `#`-insertion transform handles even/odd uniformly |

```java
// Safe KMP when text or pattern could be empty:
if (pattern.isEmpty()) return 0;       // empty pattern matches at position 0
if (text.isEmpty()) return -1;
if (pattern.length() > text.length()) return -1;

// Rabin-Karp with double hashing (reduce false positives):
long MOD1 = 1_000_000_007L, BASE1 = 31L;
long MOD2 = 998_244_353L,   BASE2 = 37L;
// Maintain two independent hashes; only verify on double hash match
```

---

## 😵 Commonly Confused With

**vs Sliding Window for substrings**: Sliding window works when you can maintain an aggregate (char count, sum) as the window moves. KMP/Z work for exact substring matching. Deciding question: *Are you matching a fixed pattern exactly (KMP/Z/RK), or checking a sliding window's property (count distinct, sum ≤ k)?*

**vs DP for string problems**: DP solves LCS, edit distance, palindrome partitioning — problems where you compare characters from two strings and build up an answer table. String algorithms (KMP/Z) solve matching/searching in a text. Deciding question: *Are you finding an exact substring (string matching algorithms), or constructing the best alignment/transformation between two strings (DP)?*

**vs Hashing for string comparison**: `String.equals()` is O(n). Rolling hash compares substrings in O(1) after O(n) build. Deciding question: *Single comparison (use equals), or many window comparisons in a sliding search (rolling hash)?*

---

## 12 — Canonical LeetCode Problems

| Problem | Algorithm |
|---------|-----------|
| LC 28 — Find the Index of the First Occurrence | KMP or Z-function |
| LC 459 — Repeated Substring Pattern | KMP failure function (period) |
| LC 214 — Shortest Palindrome | KMP on `s + "#" + reverse(s)` |
| LC 5 — Longest Palindromic Substring | Manacher O(n) or expand-around-center O(n²) |
| LC 647 — Palindromic Substrings (count) | Expand-around-center O(n²) |
| LC 686 — Repeated String Match | Rabin-Karp or contains on repeated s |
| LC 1392 — Longest Happy Prefix | KMP lps (answer = lps[n-1]) |
| LC 796 — Rotate String | Check if goal is in (s + s) |
