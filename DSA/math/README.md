# Math & Number Theory

> Mathematical patterns appear in "without extra space" constraints, modular arithmetic, prime generation, combinatorics, and digit manipulation. Know these cold — they appear as building blocks in harder problems.

---

## 1 — How to Recognize This Pattern

Ask yourself:
- [ ] Does the problem involve **prime numbers**, **GCD**, **LCM**, or **factors**?
- [ ] Does it need answers **modulo 10^9+7**?
- [ ] Does it involve **number of ways** to arrange/choose (combinatorics)?
- [ ] Does it operate on **digits** of a number?
- [ ] Is the input a **large number** that must be handled mathematically?

**Trigger phrases**: "count primes", "greatest common divisor", "ugly number", "happy number", "palindrome number", "reverse integer", "power function", "modular exponentiation", "number of combinations", "Fibonacci modulo", "Pascal's triangle"

---

## 2 — GCD and LCM

```java
// Euclidean algorithm — O(log(min(a,b)))
int gcd(int a, int b) {
    while (b != 0) { int t = b; b = a % b; a = t; }
    return a;
}

// Recursive version
int gcdRec(int a, int b) { return b == 0 ? a : gcdRec(b, a % b); }

// LCM — O(log(min(a,b)))
long lcm(long a, long b) { return a / gcd((int)a, (int)b) * b; }  // divide first to prevent overflow

// Java built-in (Java 9+)
// Math.gcd not available — use your own or: BigInteger.valueOf(a).gcd(BigInteger.valueOf(b))
```

**Applications**:
- Fraction simplification
- LC 1979 — Find Greatest Common Divisor of Array
- LC 2344 — Minimum Deletions to Make Array Divisible

---

## 3 — Sieve of Eratosthenes — Count Primes

```java
// Find all primes up to n in O(n log log n)
boolean[] sieve(int n) {
    boolean[] isComposite = new boolean[n + 1];
    isComposite[0] = isComposite[1] = true;

    for (int i = 2; (long)i * i <= n; i++) {
        if (!isComposite[i]) {
            for (int j = i * i; j <= n; j += i)   // start from i² (smaller multiples already marked)
                isComposite[j] = true;
        }
    }
    return isComposite;  // isComposite[i] == false means i is prime
}

// Count primes below n (LC 204)
int countPrimes(int n) {
    boolean[] isComposite = sieve(n - 1);
    int count = 0;
    for (int i = 2; i < n; i++) if (!isComposite[i]) count++;
    return count;
}
// Time: O(n log log n), Space: O(n)
```

---

## 4 — Modular Arithmetic

**Key rules** (all under mod M):
```
(a + b) % M = ((a % M) + (b % M)) % M
(a × b) % M = ((a % M) × (b % M)) % M
(a - b) % M = ((a % M) - (b % M) + M) % M    ← +M prevents negative result
a / b % M   = a × modInverse(b) % M            ← requires modular inverse
```

**Standard constant**: `MOD = 1_000_000_007` (prime, fits in int, a×b fits in long before mod)

```java
final int MOD = 1_000_000_007;

// Safe multiplication
long mulMod(long a, long b) { return (a % MOD) * (b % MOD) % MOD; }

// Safe addition
long addMod(long a, long b) { return (a % MOD + b % MOD) % MOD; }
```

---

## 5 — Fast Power / Modular Exponentiation (LC 50, LC 372)

Compute `base^exp % MOD` in O(log exp) using repeated squaring.

```java
// Regular power (LC 50 — Pow(x, n))
double myPow(double x, int n) {
    if (n < 0) { x = 1.0 / x; n = -n; }   // handle negative exponent
    // Use long because -Integer.MIN_VALUE overflows int
    return fastPow(x, (long) n);
}

double fastPow(double base, long exp) {
    if (exp == 0) return 1.0;
    double half = fastPow(base, exp / 2);
    if (exp % 2 == 0) return half * half;
    else              return half * half * base;
}
// Time: O(log n), Space: O(log n) stack

// Modular exponentiation (for large mod problems)
long modPow(long base, long exp, long mod) {
    long result = 1;
    base %= mod;
    while (exp > 0) {
        if ((exp & 1) == 1) result = result * base % mod;   // if exp is odd
        base = base * base % mod;
        exp >>= 1;
    }
    return result;
}
// Time: O(log exp), Space: O(1)
```

---

## 6 — Modular Inverse (Fermat's Little Theorem)

When `MOD` is prime: `a^(-1) ≡ a^(MOD-2) (mod MOD)`.

```java
long modInverse(long a, long mod) {
    return modPow(a, mod - 2, mod);   // Fermat's little theorem: a^(p-2) ≡ a^(-1) mod p
}
// Prerequisite: mod must be PRIME

// Example: 2/3 mod 7 = 2 × 3^(-1) mod 7 = 2 × 3^5 mod 7 = 2 × 243 mod 7 = 486 mod 7 = 3
```

---

## 7 — Combinatorics — nCr with Precomputed Factorials

```java
final int MOD = 1_000_000_007;
long[] fact, inv_fact;

void precompute(int maxN) {
    fact = new long[maxN + 1];
    inv_fact = new long[maxN + 1];
    fact[0] = 1;
    for (int i = 1; i <= maxN; i++) fact[i] = fact[i-1] * i % MOD;
    inv_fact[maxN] = modPow(fact[maxN], MOD - 2, MOD);
    for (int i = maxN - 1; i >= 0; i--) inv_fact[i] = inv_fact[i+1] * (i+1) % MOD;
}

// C(n, r) = n! / (r! × (n-r)!)
long nCr(int n, int r) {
    if (r < 0 || r > n) return 0;
    return fact[n] % MOD * inv_fact[r] % MOD * inv_fact[n-r] % MOD;
}
// precompute: O(n), nCr query: O(1)
```

---

## 8 — Pascal's Triangle (LC 118, LC 119)

```java
List<List<Integer>> generate(int numRows) {
    List<List<Integer>> result = new ArrayList<>();
    for (int r = 0; r < numRows; r++) {
        List<Integer> row = new ArrayList<>();
        row.add(1);
        List<Integer> prev = r > 0 ? result.get(r-1) : null;
        for (int c = 1; c < r; c++) row.add(prev.get(c-1) + prev.get(c));
        if (r > 0) row.add(1);
        result.add(row);
    }
    return result;
}
// Time: O(n²), Space: O(n²)

// Get only k-th row in O(k) space:
List<Integer> getRow(int k) {
    List<Integer> row = new ArrayList<>(Collections.nCopies(k + 1, 0));
    row.set(0, 1);
    for (int r = 1; r <= k; r++)
        for (int c = r; c >= 1; c--)   // go RIGHT TO LEFT to avoid using updated values
            row.set(c, row.get(c) + row.get(c-1));
    return row;
}
```

---

## 9 — Digit Manipulation

### Reverse Integer (LC 7)

```java
int reverse(int x) {
    int result = 0;
    while (x != 0) {
        int digit = x % 10;
        x /= 10;
        if (result > Integer.MAX_VALUE / 10 || result < Integer.MIN_VALUE / 10) return 0;  // overflow check
        result = result * 10 + digit;
    }
    return result;
}
// Time: O(log x), Space: O(1)
```

### Palindrome Number (LC 9)

```java
boolean isPalindrome(int x) {
    if (x < 0 || (x % 10 == 0 && x != 0)) return false;  // negatives and trailing zeros (except 0)
    int reversed = 0;
    while (x > reversed) {
        reversed = reversed * 10 + x % 10;
        x /= 10;
    }
    return x == reversed || x == reversed / 10;  // odd length: ignore middle digit
}
// Time: O(log x), Space: O(1)
```

### Number of Digits

```java
int numDigits(int n) { return n == 0 ? 1 : (int)Math.log10(Math.abs(n)) + 1; }
// Or: String.valueOf(n).length()
```

---

## 10 — Happy Number (LC 202)

Sum of squares of digits. Eventually reaches 1 (happy) or cycles.

```java
boolean isHappy(int n) {
    Set<Integer> seen = new HashSet<>();
    while (n != 1 && seen.add(n)) {
        int sum = 0;
        while (n > 0) { sum += (n % 10) * (n % 10); n /= 10; }
        n = sum;
    }
    return n == 1;
}

// Alternatively, use Floyd's cycle detection (slow/fast pointer on the sequence)
boolean isHappyFloyd(int n) {
    int slow = n, fast = sumOfSquares(n);
    while (fast != 1 && slow != fast) {
        slow = sumOfSquares(slow);
        fast = sumOfSquares(sumOfSquares(fast));
    }
    return fast == 1;
}

int sumOfSquares(int n) {
    int sum = 0;
    while (n > 0) { sum += (n%10)*(n%10); n /= 10; }
    return sum;
}
```

---

## 11 — Ugly Number (Multiples of 2, 3, 5)

```java
boolean isUgly(int n) {
    if (n <= 0) return false;
    for (int factor : new int[]{2, 3, 5})
        while (n % factor == 0) n /= factor;
    return n == 1;
}
// For n-th ugly number: see heap-priority-queue/README.md (DP approach)
```

---

## 12 — Integer Square Root (LC 69)

Binary search for the floor square root.

```java
int mySqrt(int x) {
    if (x < 2) return x;
    long left = 1, right = x / 2;
    while (left <= right) {
        long mid = left + (right - left) / 2;
        if (mid * mid == x) return (int) mid;
        else if (mid * mid < x) left  = mid + 1;
        else                     right = mid - 1;
    }
    return (int) right;  // floor square root
}
// Time: O(log x), Space: O(1)
```

---

## 13 — Excel Column Number / Title (LC 168, LC 171)

Base-26 system with no zero (A=1, Z=26, AA=27).

```java
// Number to title (LC 168)
String convertToTitle(int columnNumber) {
    StringBuilder sb = new StringBuilder();
    while (columnNumber > 0) {
        columnNumber--;                    // shift to 0-indexed: A=0, Z=25
        sb.append((char)('A' + columnNumber % 26));
        columnNumber /= 26;
    }
    return sb.reverse().toString();
}

// Title to number (LC 171)
int titleToNumber(String columnTitle) {
    int result = 0;
    for (char c : columnTitle.toCharArray())
        result = result * 26 + (c - 'A' + 1);
    return result;
}
```

---

## 14 — Fibonacci with Memoization / Golden Ratio

```java
// Fast Fibonacci with matrix exponentiation — O(log n)
long fibonacci(int n) {
    if (n <= 1) return n;
    long[][] mat = {{1, 1}, {1, 0}};
    long[][] result = matPow(mat, n - 1);
    return result[0][0];
}

long[][] matPow(long[][] mat, int p) {
    if (p == 1) return mat;
    long[][] half = matPow(mat, p / 2);
    long[][] sq = matMul(half, half);
    return p % 2 == 0 ? sq : matMul(sq, mat);
}

long[][] matMul(long[][] a, long[][] b) {
    return new long[][]{
        {a[0][0]*b[0][0] + a[0][1]*b[1][0], a[0][0]*b[0][1] + a[0][1]*b[1][1]},
        {a[1][0]*b[0][0] + a[1][1]*b[1][0], a[1][0]*b[0][1] + a[1][1]*b[1][1]}
    };
}
// O(log n) vs O(n) for iterative DP
```

---

## 15 — Visual: GCD (Euclidean) & Prime Sieve

```
GCD via Euclidean Algorithm — gcd(48, 18):
  48 mod 18 = 12  → gcd(18, 12)
  18 mod 12 =  6  → gcd(12, 6)
  12 mod  6 =  0  → gcd(6, 0) = 6

Why? gcd(a,b) = gcd(b, a%b). When b=0, the GCD is a.
O(log(min(a,b))) steps — very fast even for large numbers.

Sieve of Eratosthenes — primes up to 10:
  Start: [2, 3, 4, 5, 6, 7, 8, 9, 10]
  Mark multiples of 2: strike 4,6,8,10
  Mark multiples of 3: strike 9
  Mark multiples of 5: none ≤ 10 unmarked
  Primes: [2, 3, 5, 7]

Rule: only sieve up to √n (if a factor exists > √n, the other factor is < √n).
Space: O(n) boolean array. Time: O(n log log n).

MODULAR ARITHMETIC:
  (a + b) % m = ((a % m) + (b % m)) % m   ✓
  (a * b) % m = ((a % m) * (b % m)) % m   ✓
  (a - b) % m = ((a % m) - (b % m) + m) % m  ← +m to avoid negative!
  a^b % m     → use fast power (binary exponentiation): O(log b)
```

---

## 🧠 Unseen Problem Walkthrough

**Problem**: Given two integers `a` and `b`, compute `(a^b) % (10^9 + 7)` without overflow. *(Fast modular exponentiation — base for many combinatorics problems)*

**Step 1 — Read**: Input = base `a`, exponent `b`. Output = `a^b mod MOD` where MOD = 10⁹+7.

**Step 2 — Identify**: Direct multiplication `a*a*...*a` is O(b) — too slow for large b. Using the property `a^b = (a^(b/2))^2` → **binary exponentiation** reduces to O(log b) multiplications. This is a pure **math / fast power** technique.

**Step 3 — Plan**:
- If `b == 0` → return 1 (anything to the 0th power is 1).
- If `b` is even → `power(a, b) = power(a*a, b/2)`.
- If `b` is odd → `power(a, b) = a * power(a, b-1)` = `a * power(a*a, b/2)`.
- Apply mod at every multiplication to prevent overflow.

**Step 4 — Code**:
```java
long MOD = 1_000_000_007L;

long modPow(long base, long exp, long mod) {
    long result = 1;
    base %= mod;
    while (exp > 0) {
        if ((exp & 1) == 1)          // exp is odd: multiply result by base
            result = result * base % mod;
        base = base * base % mod;    // square the base
        exp >>= 1;                   // divide exp by 2
    }
    return result;
}
// Time: O(log exp), Space: O(1)
```

**Step 5 — Verify** on `modPow(2, 10, 1e9+7)`:
- exp=10 (binary 1010):
  - exp&1=0: base=4, exp=5.
  - exp&1=1: result=4. base=16, exp=2.
  - exp&1=0: base=256, exp=1.
  - exp&1=1: result=4*256=1024. exp=0.
- Return 1024. ✓ (2^10 = 1024)

---

## ⚠️ Edge Cases & Small Tweaks

| Scenario | What breaks | Fix |
|----------|-------------|-----|
| Modular subtraction | `(a - b) % m` can be negative in Java | Use `((a - b) % m + m) % m` |
| GCD with 0 | `gcd(0, n) = n` by convention | Base case: `if (b == 0) return a` |
| LCM overflow | `lcm(a,b) = a/gcd(a,b)*b` — divide FIRST to avoid overflow | `(long) a / gcd(a,b) * b` |
| Prime check of 1 | 1 is NOT prime | Check `n > 1` before sieve or trial division |
| Large combinations C(n,k) | Direct calculation overflows | Use Pascal's triangle or Lucas' theorem with modular inverse |
| Modular inverse | Need `a * inv(a) ≡ 1 (mod p)` for division under mod | `modPow(a, p-2, p)` when p is prime (Fermat's little theorem) |

```java
// GCD and LCM:
int gcd(int a, int b) { return b == 0 ? a : gcd(b, a % b); }
long lcm(long a, long b) { return a / gcd((int)a, (int)b) * b; }

// Modular inverse (when MOD is prime):
long modInverse(long a, long mod) { return modPow(a, mod - 2, mod); }

// Combination C(n, k) mod p (precompute factorials):
long[] fact = new long[n + 1], inv_fact = new long[n + 1];
fact[0] = 1;
for (int i = 1; i <= n; i++) fact[i] = fact[i-1] * i % MOD;
inv_fact[n] = modPow(fact[n], MOD - 2, MOD);
for (int i = n-1; i >= 0; i--) inv_fact[i] = inv_fact[i+1] * (i+1) % MOD;
// C(n,k) = fact[n] * inv_fact[k] % MOD * inv_fact[n-k] % MOD

// Sieve of Eratosthenes:
boolean[] notPrime = new boolean[n + 1];
notPrime[0] = notPrime[1] = true;
for (int i = 2; (long) i * i <= n; i++)
    if (!notPrime[i])
        for (int j = i * i; j <= n; j += i) notPrime[j] = true;
```

---

## 😵 Commonly Confused With

**vs Bit Manipulation for powers of 2**: `n & (n-1) == 0` checks power of 2 in O(1). General `a^b` needs fast power. Deciding question: *Is the base always 2 and you just need a check/shift (bit tricks), or is the base arbitrary requiring general exponentiation (math)?*

**vs DP for combinatorics**: Pascal's triangle is a DP approach to build combination values. Factorials + modular inverse is direct O(1)-per-query after O(n) precomputation. Deciding question: *Do you need C(n,k) for many different n,k values (precompute factorials), or just a few small values (Pascal's DP triangle)?*

**vs GCD in Union-Find**: Union-Find merges components; GCD finds the greatest common divisor. Deciding question: *Are you grouping elements that share a property (Union-Find), or computing the divisibility relationship between two numbers (GCD)?*

---

## 16 — Canonical LeetCode Problems

| Category | Problems |
|---------|---------|
| GCD/LCM | LC 1979, LC 2344, LC 365 (water jug — GCD insight) |
| Primes / sieve | LC 204, LC 279 (BFS / math), LC 1175 |
| Power / modular | LC 50, LC 372, LC 1498, LC 1922 |
| Combinatorics | LC 62 (unique paths), LC 119 (Pascal row), LC 1641 |
| Digit manipulation | LC 7, LC 9, LC 202, LC 263, LC 264 |
| Number theory | LC 168, LC 171, LC 69, LC 367 (perfect square) |

---

## 16 — Key Formulas Reference

```
Sum 1..n:             n*(n+1)/2
Sum of squares 1..n:  n*(n+1)*(2n+1)/6
Catalan numbers:      C(n) = C(2n,n)/(n+1)  — valid BSTs, balanced parens
Stirling numbers:     partition n elements into k non-empty subsets

Modular inverses work only when MOD is prime (use Fermat's little theorem).
For composite MOD: use extended Euclidean algorithm for modular inverse.
```
