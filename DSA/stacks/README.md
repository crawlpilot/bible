# Stacks & Monotone Stack

> A stack gives you O(1) access to the most recently seen element. A **monotone stack** maintains a sorted invariant on that history, giving you O(n) "nearest greater/smaller" queries.

---

## 1 — How to Recognize This Pattern

Ask yourself:
- [ ] Do you need the **most recently seen** element that satisfies a condition?
- [ ] Does the problem ask for the **nearest greater, nearest smaller** element to the left or right?
- [ ] Is there **matching / nesting** involved (brackets, HTML tags, function calls)?
- [ ] Does the problem involve evaluating **expressions** with operator precedence?
- [ ] Does each element need to "wait" until its **future pair** is found?

**Trigger phrases**: "next greater element", "daily temperatures", "largest rectangle in histogram", "valid parentheses", "evaluate expression", "stock span", "trapping rain water with stack", "remove k digits"

---

## 2 — Flavor Detection

| Flavor | Signal | Stack Contains |
|--------|--------|---------------|
| **Matching / nesting** | Opening/closing pairs (brackets, tags) | Unmatched opening elements |
| **Monotone decreasing** | Next greater element, stock span, histogram | Indices with **decreasing** values (top = smallest seen) |
| **Monotone increasing** | Next smaller element, buildings blocking view | Indices with **increasing** values (top = largest seen) |
| **Expression evaluation** | Operators + operands, precedence | Operands stack + operators stack |
| **Min stack / max stack** | O(1) min/max at any time | Main stack + auxiliary min/max stack in sync |
| **Largest rectangle / maximal square** | "Max area under histogram" | Monotone increasing heights stack |

---

## 3 — Bracket Matching Template (LC 20)

**Rule**: When you see an opener, push it. When you see a closer, pop and verify.

```java
boolean isValid(String s) {
    Deque<Character> stack = new ArrayDeque<>();
    for (char c : s.toCharArray()) {
        if (c == '(' || c == '[' || c == '{') {
            stack.push(c);
        } else {
            if (stack.isEmpty()) return false;
            char top = stack.pop();
            if (c == ')' && top != '(') return false;
            if (c == ']' && top != '[') return false;
            if (c == '}' && top != '{') return false;
        }
    }
    return stack.isEmpty();
}
```

**Canonical problems**: LC 20 (valid parentheses), LC 1249 (minimum remove to make valid), LC 32 (longest valid parentheses).

---

## 4 — Monotone Decreasing Stack — Next Greater Element

**Goal**: For each element, find the first element to its RIGHT that is strictly greater.

**Invariant**: Stack contains indices of elements for which we haven't found the "next greater" yet, in **decreasing** order of value (so the top is always the smallest pending element).

```
For each element arr[i]:
  While stack is NOT empty AND arr[stack.top()] < arr[i]:
      idx = stack.pop()
      result[idx] = arr[i]        // arr[i] is the next greater for arr[idx]
  Push i onto stack

After loop: remaining stack elements have no next greater → result[idx] = -1
```

**Java template (LC 496 — Next Greater Element I)**:
```java
int[] nextGreaterElement(int[] nums1, int[] nums2) {
    // Precompute next greater for every element in nums2
    Map<Integer, Integer> nextGreater = new HashMap<>();
    Deque<Integer> stack = new ArrayDeque<>();  // stores VALUES (monotone decreasing)

    for (int num : nums2) {
        while (!stack.isEmpty() && stack.peek() < num) {
            nextGreater.put(stack.pop(), num);   // num is next greater for popped element
        }
        stack.push(num);
    }

    int[] res = new int[nums1.length];
    for (int i = 0; i < nums1.length; i++)
        res[i] = nextGreater.getOrDefault(nums1[i], -1);
    return res;
}
```

**Daily Temperatures (LC 739) — next greater INDEX distance**:
```java
int[] dailyTemperatures(int[] temperatures) {
    int n = temperatures.length;
    int[] result = new int[n];
    Deque<Integer> stack = new ArrayDeque<>();  // stores INDICES

    for (int i = 0; i < n; i++) {
        while (!stack.isEmpty() && temperatures[stack.peek()] < temperatures[i]) {
            int idx = stack.pop();
            result[idx] = i - idx;              // days to wait
        }
        stack.push(i);
    }
    return result;  // remaining in stack stay 0
}
```

---

## 5 — Monotone Increasing Stack — Next Smaller Element / Stock Span

**Goal**: Find the first element to the LEFT that is smaller (or the span of consecutive days ≤ current).

**Invariant**: Stack contains indices in **increasing** order of value (top = largest pending = first to be "blocked").

**Stock Span (LC 901)**:
```java
class StockSpanner {
    Deque<int[]> stack = new ArrayDeque<>();  // [price, span]

    public int next(int price) {
        int span = 1;
        while (!stack.isEmpty() && stack.peek()[0] <= price) {
            span += stack.pop()[1];   // accumulate spans of smaller/equal days
        }
        stack.push(new int[]{price, span});
        return span;
    }
}
```

---

## 6 — Largest Rectangle in Histogram (LC 84)

**Key insight**: The rectangle for bar `i` extends left/right as long as bars are ≥ `height[i]`. Use monotone increasing stack — when a shorter bar arrives, pop and compute the rectangle for the popped bar.

```java
int largestRectangleArea(int[] heights) {
    int n = heights.length;
    int[] h = Arrays.copyOf(heights, n + 1);  // append sentinel 0 to flush stack
    Deque<Integer> stack = new ArrayDeque<>();  // monotone increasing indices
    int maxArea = 0;

    for (int i = 0; i <= n; i++) {
        while (!stack.isEmpty() && h[stack.peek()] > h[i]) {
            int height = h[stack.pop()];
            int width  = stack.isEmpty() ? i : i - stack.peek() - 1;
            maxArea = Math.max(maxArea, height * width);
        }
        stack.push(i);
    }
    return maxArea;
}
```

**Why width = `i - stack.peek() - 1`?**  
After popping the bar, `stack.peek()` is the last bar that is SHORTER than the popped bar — so the rectangle can extend from `stack.peek() + 1` to `i - 1`.

**Maximal Rectangle in 2D matrix (LC 85)**: Reduce each row to a histogram (running height = 0 if `matrix[i][j] == '0'`, else `height[j]++`), then apply the histogram algorithm on each row.

```java
int maximalRectangle(char[][] matrix) {
    if (matrix.length == 0) return 0;
    int n = matrix[0].length;
    int[] heights = new int[n];
    int maxArea = 0;

    for (char[] row : matrix) {
        for (int j = 0; j < n; j++)
            heights[j] = (row[j] == '1') ? heights[j] + 1 : 0;
        maxArea = Math.max(maxArea, largestRectangleArea(heights));
    }
    return maxArea;
}
```

---

## 7 — Min Stack (LC 155)

**Design a stack with O(1) push, pop, top, AND getMin.**

**Two-stack approach**: main stack + auxiliary min-stack in sync.

```java
class MinStack {
    Deque<Integer> stack    = new ArrayDeque<>();
    Deque<Integer> minStack = new ArrayDeque<>();

    public void push(int val) {
        stack.push(val);
        int currentMin = minStack.isEmpty() ? val : Math.min(val, minStack.peek());
        minStack.push(currentMin);          // push current minimum (not just when val < min)
    }

    public void pop() {
        stack.pop();
        minStack.pop();
    }

    public int top()    { return stack.peek(); }
    public int getMin() { return minStack.peek(); }
}
```

**Single-stack trick** (encode previous min): push a sentinel value when a new min is found so you can recover on pop — but the two-stack approach is cleaner and always preferred in interviews.

---

## 8 — Expression Evaluation (LC 224 / LC 227)

**Basic calculator with `+`, `-`, `(`, `)`**:

```java
int calculate(String s) {
    Deque<Integer> stack = new ArrayDeque<>();
    int result = 0, num = 0, sign = 1;

    for (int i = 0; i < s.length(); i++) {
        char c = s.charAt(i);
        if (Character.isDigit(c)) {
            num = num * 10 + (c - '0');
        } else if (c == '+') {
            result += sign * num;
            num = 0; sign = 1;
        } else if (c == '-') {
            result += sign * num;
            num = 0; sign = -1;
        } else if (c == '(') {
            stack.push(result);   // save current result
            stack.push(sign);     // save sign before '('
            result = 0; sign = 1;
        } else if (c == ')') {
            result += sign * num;
            num = 0;
            result *= stack.pop();   // multiply by sign before '('
            result += stack.pop();   // add saved result before '('
        }
    }
    return result + sign * num;
}
```

**Calculator II (LC 227) with `*`, `/`, `+`, `-` (no parentheses)**: Use stack to defer addition/subtraction while eagerly evaluating `*` and `/`.

```java
int calculate2(String s) {
    Deque<Integer> stack = new ArrayDeque<>();
    int num = 0;
    char op = '+';

    for (int i = 0; i < s.length(); i++) {
        char c = s.charAt(i);
        if (Character.isDigit(c)) num = num * 10 + (c - '0');

        if (!Character.isDigit(c) && c != ' ' || i == s.length() - 1) {
            if      (op == '+') stack.push(num);
            else if (op == '-') stack.push(-num);
            else if (op == '*') stack.push(stack.pop() * num);
            else if (op == '/') stack.push(stack.pop() / num);
            op = c; num = 0;
        }
    }

    int result = 0;
    while (!stack.isEmpty()) result += stack.pop();
    return result;
}
```

---

## 9 — Remove K Digits to Make Smallest Number (LC 402)

**Greedy + monotone increasing stack**: maintain digits in increasing order; pop when a smaller digit arrives (greedy: a larger digit on the left always makes the number bigger).

```java
String removeKdigits(String num, int k) {
    Deque<Character> stack = new ArrayDeque<>();

    for (char c : num.toCharArray()) {
        while (k > 0 && !stack.isEmpty() && stack.peek() > c) {
            stack.pop();
            k--;
        }
        stack.push(c);
    }

    while (k-- > 0) stack.pop();   // if k still > 0, remove from the end

    StringBuilder sb = new StringBuilder();
    boolean leadingZero = true;
    for (char c : stack) {
        if (leadingZero && c == '0') continue;
        leadingZero = false;
        sb.append(c);
    }
    return sb.isEmpty() ? "0" : sb.toString();
}
```

---

## 10 — Complexity Reference

| Problem | Time | Space |
|---------|------|-------|
| Valid parentheses | O(n) | O(n) |
| Next greater element | O(n) | O(n) |
| Largest rectangle histogram | O(n) | O(n) |
| Min stack ops | O(1) each | O(n) |
| Basic calculator | O(n) | O(n) |
| Remove K digits | O(n) | O(n) |

Every element is pushed and popped at most once → amortised O(n) for monotone stack problems.

---

## 11 — FAANG Interview Moves

1. **State the monotone invariant**: "I maintain a decreasing stack — every element waiting in the stack hasn't found its next greater element yet."
2. **Index vs value in stack**: For distance or width calculations (daily temperatures, histogram), store **indices** not values so you can compute spans.
3. **Sentinel trick**: Append `0` to the heights array in histogram problems to flush the stack at the end — cleaner than a post-loop drain.
4. **Min stack = always push current min**: Push `min(val, current_min)` on the aux stack every time (not just when a new minimum arrives) — makes pop trivial.
5. **Expression evaluation**: Walk through operator precedence explicitly: parentheses suspend the current result, `*`/`/` are evaluated immediately by peeking the stack.

---

## 12 — Visual: Monotone Stack in Action

**Next Greater Element** — processing `[2, 1, 5, 3, 4]`:
```
Process 2: stack=[]      → push 2.   stack=[2]
Process 1: stack=[2]     → 1 < 2, push 1.  stack=[2,1]
Process 5: stack=[2,1]   → 5 > 1: pop 1, ans[1]=5; 5 > 2: pop 2, ans[0]=5; push 5. stack=[5]
Process 3: stack=[5]     → 3 < 5, push 3.  stack=[5,3]
Process 4: stack=[5,3]   → 4 > 3: pop 3, ans[3]=4; 4 < 5, push 4.  stack=[5,4]
End: remaining [5,4] → no next greater → ans=-1

Result: [5, 5, -1, 4, -1]

Stack invariant: always DECREASING from bottom to top
  → The top is the "smallest waiting for a bigger element"
  → When we see something bigger, it's the answer for everything smaller in the stack
```

---

## 🧠 Unseen Problem Walkthrough

**Problem**: Given an array of integers, for each element, find the number of consecutive elements to its right that are less than or equal to it (its "span"). *(Stock Span problem — slightly different framing.)*

**Step 1 — Read**: Input = int[] prices, output = int[] spans where `span[i]` = how many consecutive days (including today) where price was ≤ price[i].

**Step 2 — Identify**: For each element, we're looking for the **nearest previous greater** element. Everything between that element and the current index is within the span. "Nearest previous greater" → **Monotone Decreasing Stack**.

**Step 3 — Plan**:
- Stack stores (index, price) of elements without a span-ending element yet.
- For each price[i]: pop all stack elements with price ≤ price[i] (their span is over).
- `span[i] = i - index of top of stack` (or `i + 1` if stack empty).
- Push (i, price[i]) onto stack.

**Step 4 — Code**:
```java
int[] stockSpan(int[] prices) {
    int[] span = new int[prices.length];
    Deque<Integer> stack = new ArrayDeque<>();  // stores indices

    for (int i = 0; i < prices.length; i++) {
        while (!stack.isEmpty() && prices[stack.peek()] <= prices[i])
            stack.pop();                                // pop smaller prices
        span[i] = stack.isEmpty() ? i + 1 : i - stack.peek();
        stack.push(i);                                  // push current index
    }
    return span;
}
// Time: O(n) amortized, Space: O(n)
```

**Step 5 — Verify** on `[100, 80, 60, 70, 60, 75, 85]`:
- i=0: stack empty → span=1; push 0. stack=[0]
- i=1: prices[0]=100 > 80 → span=1; push 1. stack=[0,1]
- i=2: prices[1]=80 > 60 → span=1; push 2. stack=[0,1,2]
- i=3: pop 2 (60≤70); prices[1]=80>70 → span=3-1=2; push 3. stack=[0,1,3]
- i=5: pop 3 (70≤75), pop 2(already gone)... span = i-top
- Result: [1,1,1,2,1,4,6] ✓

---

## ⚠️ Edge Cases & Small Tweaks

| Scenario | What breaks | Fix |
|----------|-------------|-----|
| Empty array | Loop doesn't execute | Return empty array — fine |
| All elements equal | Monotone stack empties for each | Depends on `<` vs `<=` in pop condition |
| All increasing `[1,2,3,4]` | Stack grows to size n | Correct — each element's NGE is the next one |
| All decreasing `[4,3,2,1]` | Stack never pops | Correct — no NGE for any element |
| Histogram, last bar never popped | Stack has elements after loop | Append `0` to heights as sentinel, or drain stack after loop |

```java
// < vs <= in pop condition:
// "next STRICTLY greater" → pop while stack.peek() <= current
// "next greater or equal" → pop while stack.peek() < current

// Drain stack after loop (sentinel alternative):
while (!stack.isEmpty()) {
    int idx = stack.pop();
    result[idx] = /* use n (length) as the right boundary */;
}
// OR: add Integer.MIN_VALUE at the end of the array to trigger all pops
```

---

## 😵 Commonly Confused With

**vs Queue / Deque**: A stack is LIFO (last in, first out). A queue is FIFO (first in, first out). A monotone deque is used when you need BOTH ends — sliding window maximum. Deciding question: *Do you only need the most recent element, or elements from both ends?*

**vs Recursive DFS**: The system call stack IS a stack. Iterative DFS with an explicit stack is equivalent to recursive DFS but avoids StackOverflow on large inputs. Deciding question: *Will the recursion depth exceed ~10,000?* If yes, convert to iterative with explicit stack.

**vs Priority Queue**: A priority queue gives the global min/max. A monotone stack gives the NEAREST greater/smaller. Deciding question: *Do you need the nearest element satisfying a condition (local), or the overall best element (global)?*
