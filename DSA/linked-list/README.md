# Linked List

> A linked list is a chain of nodes where each node holds a value and a pointer to the next node. The key operations — reverse, detect cycle, merge, find middle — all follow pointer manipulation patterns that must be done in-place.

---

## 1 — How to Recognize This Pattern

Ask yourself:
- [ ] Is the input explicitly a **linked list** (`ListNode` with `.val` and `.next`)?
- [ ] Does the problem require **in-place** manipulation (O(1) space)?
- [ ] Are you looking for a **cycle**, the **middle**, or a **specific position**?
- [ ] Does it involve **merging or reversing** pointer chains?

**Trigger phrases**: "reverse linked list", "detect cycle", "find middle", "merge two sorted lists", "remove n-th from end", "reorder list", "palindrome linked list", "LRU cache", "copy list with random pointer"

---

## 2 — Flavor Detection

| Flavor | Signal | Technique |
|--------|--------|-----------|
| **Reverse** | Reverse full list or sublist | Three-pointer: prev / curr / next |
| **Fast-Slow (Floyd's)** | Detect cycle; find middle; palindrome check | `slow += 1`, `fast += 2` |
| **Find n-th from end** | Remove or find k-th from tail | Two-pointer with gap of n |
| **Merge sorted lists** | Combine ordered lists | Compare heads; advance smaller |
| **Reorder / partition** | Even/odd nodes; partition around value | Build separate chains, then link |
| **Clone with random** | Deep copy with `random` pointer | HashMap node→clone or interleave trick |
| **LRU Cache** | O(1) get + O(1) put with eviction | Doubly linked list + HashMap |

---

## 3 — Node Definition

```java
class ListNode {
    int val;
    ListNode next;
    ListNode(int val) { this.val = val; }
}
```

---

## 4 — Reverse Linked List

### Full Reverse (LC 206)

```java
ListNode reverseList(ListNode head) {
    ListNode prev = null, curr = head;
    while (curr != null) {
        ListNode next = curr.next;   // save next
        curr.next = prev;            // reverse pointer
        prev = curr;                 // advance prev
        curr = next;                 // advance curr
    }
    return prev;   // prev is the new head
}
// Time: O(n), Space: O(1)
```

**Recursive version** (understand both):
```java
ListNode reverseListRec(ListNode head) {
    if (head == null || head.next == null) return head;
    ListNode newHead = reverseListRec(head.next);  // reverse rest
    head.next.next = head;   // point next node back to current
    head.next = null;         // break forward link
    return newHead;
}
// Time: O(n), Space: O(n) stack
```

### Reverse Sublist [left, right] (LC 92)

```java
ListNode reverseBetween(ListNode head, int left, int right) {
    ListNode dummy = new ListNode(0);
    dummy.next = head;
    ListNode prev = dummy;

    // Step 1: advance prev to node just before 'left'
    for (int i = 1; i < left; i++) prev = prev.next;

    // Step 2: reverse [left..right] using insertion at front
    ListNode curr = prev.next;
    for (int i = 0; i < right - left; i++) {
        ListNode next = curr.next;
        curr.next = next.next;
        next.next = prev.next;
        prev.next = next;
    }
    return dummy.next;
}
// Time: O(n), Space: O(1)
```

### Reverse in K-Groups (LC 25)

```java
ListNode reverseKGroup(ListNode head, int k) {
    ListNode check = head;
    for (int i = 0; i < k; i++) {
        if (check == null) return head;   // less than k nodes left — don't reverse
        check = check.next;
    }

    // Reverse k nodes
    ListNode prev = null, curr = head;
    for (int i = 0; i < k; i++) {
        ListNode next = curr.next;
        curr.next = prev;
        prev = curr;
        curr = next;
    }
    head.next = reverseKGroup(curr, k);   // recursively handle rest
    return prev;   // new head of this group
}
// Time: O(n), Space: O(n/k) recursion stack
```

---

## 5 — Fast-Slow Pointers (Floyd's Cycle Detection)

### Detect Cycle (LC 141)

```java
boolean hasCycle(ListNode head) {
    ListNode slow = head, fast = head;
    while (fast != null && fast.next != null) {
        slow = slow.next;
        fast = fast.next.next;
        if (slow == fast) return true;   // cycle detected
    }
    return false;
}
// Time: O(n), Space: O(1)
```

### Find Cycle Start (LC 142)

**Key insight**: when slow and fast meet, reset one pointer to head. Both now move one step at a time. They meet at the cycle entry.

```java
ListNode detectCycle(ListNode head) {
    ListNode slow = head, fast = head;
    while (fast != null && fast.next != null) {
        slow = slow.next;
        fast = fast.next.next;
        if (slow == fast) {
            ListNode entry = head;
            while (entry != slow) {
                entry = entry.next;
                slow  = slow.next;
            }
            return entry;
        }
    }
    return null;
}
// Time: O(n), Space: O(1)
```

**Why does this work?** If the cycle starts at position `F` from head, and has length `C`, slow walks `F + a` steps to meet point; fast walks `2(F + a)` steps = `F + a + n*C`. So `F + a = n*C`, meaning from the meet point, walking `F` more steps brings you back to cycle start — same distance as head to cycle start.

### Find Middle of Linked List (LC 876)

```java
ListNode middleNode(ListNode head) {
    ListNode slow = head, fast = head;
    while (fast != null && fast.next != null) {
        slow = slow.next;
        fast = fast.next.next;
    }
    return slow;   // for even length: returns SECOND middle (use this for palindrome check)
}
// Time: O(n), Space: O(1)
```

### Palindrome Linked List (LC 234)

```java
boolean isPalindrome(ListNode head) {
    // Step 1: find middle
    ListNode slow = head, fast = head;
    while (fast != null && fast.next != null) {
        slow = slow.next;
        fast = fast.next.next;
    }

    // Step 2: reverse second half
    ListNode prev = null, curr = slow;
    while (curr != null) {
        ListNode next = curr.next;
        curr.next = prev;
        prev = curr;
        curr = next;
    }

    // Step 3: compare both halves
    ListNode left = head, right = prev;
    while (right != null) {
        if (left.val != right.val) return false;
        left  = left.next;
        right = right.next;
    }
    return true;
}
// Time: O(n), Space: O(1)
```

---

## 6 — Remove N-th From End (LC 19)

**Two-pointer with gap**: advance fast pointer n steps ahead, then move both together. When fast reaches end, slow is at the node before the target.

```java
ListNode removeNthFromEnd(ListNode head, int n) {
    ListNode dummy = new ListNode(0);
    dummy.next = head;
    ListNode slow = dummy, fast = dummy;

    // Advance fast by n+1 steps (so slow lands on node BEFORE the target)
    for (int i = 0; i <= n; i++) fast = fast.next;

    while (fast != null) {
        slow = slow.next;
        fast = fast.next;
    }

    slow.next = slow.next.next;   // skip the target node
    return dummy.next;
}
// Time: O(n), Space: O(1)
```

---

## 7 — Merge Two Sorted Lists (LC 21)

```java
ListNode mergeTwoLists(ListNode l1, ListNode l2) {
    ListNode dummy = new ListNode(0), curr = dummy;
    while (l1 != null && l2 != null) {
        if (l1.val <= l2.val) { curr.next = l1; l1 = l1.next; }
        else                  { curr.next = l2; l2 = l2.next; }
        curr = curr.next;
    }
    curr.next = (l1 != null) ? l1 : l2;   // attach remaining
    return dummy.next;
}
// Time: O(m+n), Space: O(1)
```

---

## 8 — Reorder List (LC 143)

Rearrange: L0 → Ln → L1 → Ln-1 → L2 → ...

```java
void reorderList(ListNode head) {
    if (head == null || head.next == null) return;

    // Step 1: find middle
    ListNode slow = head, fast = head;
    while (fast.next != null && fast.next.next != null) {
        slow = slow.next;
        fast = fast.next.next;
    }

    // Step 2: reverse second half
    ListNode secondHalf = reverseList(slow.next);
    slow.next = null;   // cut the list

    // Step 3: merge two halves
    ListNode first = head, second = secondHalf;
    while (second != null) {
        ListNode tmp1 = first.next, tmp2 = second.next;
        first.next  = second;
        second.next = tmp1;
        first  = tmp1;
        second = tmp2;
    }
}
// Time: O(n), Space: O(1)
```

---

## 9 — Copy List with Random Pointer (LC 138)

Each node has `.next` and `.random` (can point to any node or null).

```java
// Approach 1: HashMap — O(n) space
Node copyRandomList(Node head) {
    Map<Node, Node> map = new HashMap<>();

    // Pass 1: create all clones
    Node curr = head;
    while (curr != null) {
        map.put(curr, new Node(curr.val));
        curr = curr.next;
    }

    // Pass 2: wire next and random
    curr = head;
    while (curr != null) {
        map.get(curr).next   = map.get(curr.next);
        map.get(curr).random = map.get(curr.random);
        curr = curr.next;
    }
    return map.get(head);
}
// Time: O(n), Space: O(n)
```

**O(1) space trick — interleave clones:**
```java
Node copyRandomListO1(Node head) {
    if (head == null) return null;
    // Pass 1: insert clones after each original
    Node curr = head;
    while (curr != null) {
        Node clone = new Node(curr.val);
        clone.next = curr.next;
        curr.next  = clone;
        curr = clone.next;
    }
    // Pass 2: set random pointers
    curr = head;
    while (curr != null) {
        if (curr.random != null)
            curr.next.random = curr.random.next;   // clone's random = original.random's clone
        curr = curr.next.next;
    }
    // Pass 3: extract clone list
    Node dummy = new Node(0), cloneCurr = dummy;
    curr = head;
    while (curr != null) {
        cloneCurr.next = curr.next;
        curr.next = curr.next.next;   // restore original
        cloneCurr = cloneCurr.next;
        curr = curr.next;
    }
    return dummy.next;
}
// Time: O(n), Space: O(1)
```

---

## 10 — LRU Cache (LC 146)

**O(1) get + O(1) put**: Doubly linked list (maintains order) + HashMap (O(1) lookup by key).

```java
class LRUCache {
    private final int capacity;
    private final Map<Integer, Node> map;
    private final Node head, tail;   // dummy sentinels

    class Node {
        int key, val;
        Node prev, next;
        Node(int k, int v) { key = k; val = v; }
    }

    LRUCache(int capacity) {
        this.capacity = capacity;
        map = new HashMap<>();
        head = new Node(0, 0);   // most recently used end
        tail = new Node(0, 0);   // least recently used end
        head.next = tail;
        tail.prev = head;
    }

    int get(int key) {
        if (!map.containsKey(key)) return -1;
        Node node = map.get(key);
        moveToFront(node);
        return node.val;
    }

    void put(int key, int value) {
        if (map.containsKey(key)) {
            Node node = map.get(key);
            node.val = value;
            moveToFront(node);
        } else {
            if (map.size() == capacity) {
                Node lru = tail.prev;   // least recently used
                remove(lru);
                map.remove(lru.key);
            }
            Node node = new Node(key, value);
            insertFront(node);
            map.put(key, node);
        }
    }

    private void remove(Node node) {
        node.prev.next = node.next;
        node.next.prev = node.prev;
    }

    private void insertFront(Node node) {
        node.next = head.next;
        node.prev = head;
        head.next.prev = node;
        head.next = node;
    }

    private void moveToFront(Node node) {
        remove(node);
        insertFront(node);
    }
}
// get: O(1), put: O(1), Space: O(capacity)
```

---

## 11 — Sort List (LC 148) — Merge Sort on Linked List

```java
ListNode sortList(ListNode head) {
    if (head == null || head.next == null) return head;

    // Split into two halves
    ListNode mid = getMid(head);
    ListNode right = mid.next;
    mid.next = null;

    ListNode left = sortList(head);
    ListNode rightSorted = sortList(right);

    return merge(left, rightSorted);
}

private ListNode getMid(ListNode head) {
    ListNode slow = head, fast = head.next;  // fast starts at next to get LEFT middle
    while (fast != null && fast.next != null) {
        slow = slow.next;
        fast = fast.next.next;
    }
    return slow;
}

private ListNode merge(ListNode l1, ListNode l2) {
    ListNode dummy = new ListNode(0), curr = dummy;
    while (l1 != null && l2 != null) {
        if (l1.val <= l2.val) { curr.next = l1; l1 = l1.next; }
        else                  { curr.next = l2; l2 = l2.next; }
        curr = curr.next;
    }
    curr.next = l1 != null ? l1 : l2;
    return dummy.next;
}
// Time: O(n log n), Space: O(log n) recursion stack
```

---

## 12 — Common Mistakes

```
□ Not using a dummy head node
  → Simplifies edge cases where head itself changes (reverse, remove)

□ Losing the next pointer before reassigning
  ListNode next = curr.next;   ← ALWAYS save before changing curr.next
  curr.next = prev;

□ Off-by-one in "remove n-th from end"
  → Advance fast n+1 times (not n) so slow lands BEFORE the target

□ Forgetting to set slow.next = null when splitting a list
  → The left half will still be connected to the right half

□ Cycle detection: starting fast at head.next instead of head
  → Breaks when list has only 1 node
```

---

## 13 — Visual: Pointer Manipulation

```
REVERSE a linked list:  1 → 2 → 3 → 4 → null
                       prev curr next

Step 1: prev=null, curr=1
  save next=2; curr.next=prev(null); prev=1; curr=2
  null ← 1   2 → 3 → 4

Step 2: prev=1, curr=2
  save next=3; curr.next=prev(1); prev=2; curr=3
  null ← 1 ← 2   3 → 4

Step 3: prev=2, curr=3
  save next=4; curr.next=prev(2); prev=3; curr=4
  null ← 1 ← 2 ← 3   4

Step 4: prev=3, curr=4
  save next=null; curr.next=prev(3); prev=4; curr=null
  null ← 1 ← 2 ← 3 ← 4

curr==null → return prev(4) as new head.

FAST/SLOW (cycle detection):
  slow=head, fast=head
  Each step: slow moves 1, fast moves 2.
  If they ever meet → cycle exists.
  Why? In a cycle of length L, fast gains 1 step per round → meets in ≤ L rounds.
```

---

## 🧠 Unseen Problem Walkthrough

**Problem**: Given the head of a linked list, return the node where a cycle begins. If there's no cycle, return null. *(LC 142 — Linked List Cycle II)*

**Step 1 — Read**: Input = linked list (may have cycle). Output = node where cycle starts (or null).

**Step 2 — Identify**: "Cycle" in linked list → **Floyd's cycle detection (fast/slow pointers)**. Two-phase algorithm: (1) detect the cycle, (2) find the entry point.

**Step 3 — Plan**:
- Phase 1: fast/slow both start at head. Move slow 1 step, fast 2 steps. If they meet → cycle.
- Phase 2: keep one pointer at the meeting point, reset the other to head. Move both 1 step. Where they meet = cycle entry.
- **Why phase 2 works**: if meeting point is `k` steps into the cycle and cycle has length `L`, then `head → entry` = `meeting_point → entry` in number of steps (mathematical property of Floyd's algorithm).

**Step 4 — Code**:
```java
ListNode detectCycle(ListNode head) {
    ListNode slow = head, fast = head;

    // Phase 1: find meeting point
    while (fast != null && fast.next != null) {
        slow = slow.next;
        fast = fast.next.next;
        if (slow == fast) break;       // cycle detected
    }
    if (fast == null || fast.next == null) return null;  // no cycle

    // Phase 2: find entry
    slow = head;
    while (slow != fast) {
        slow = slow.next;
        fast = fast.next;             // both move 1 step now
    }
    return slow;  // cycle entry node
}
// Time: O(n), Space: O(1)
```

**Step 5 — Verify** on `1 → 2 → 3 → 4 → 5 → (back to 3)`:
- Phase 1: slow/fast start at 1. They meet inside the cycle (at some node).
- Phase 2: reset slow=1, fast=meeting node. Both step 1. They converge at node 3 (cycle entry). ✓

---

## ⚠️ Edge Cases & Small Tweaks

| Scenario | What breaks | Fix |
|----------|-------------|-----|
| Empty list (head=null) | NPE on head.next | Check `if (head == null) return null` first |
| Single node, no cycle | fast.next=null immediately | Loop exits → return null |
| Single node, self-loop | fast==slow after first step | Detected correctly by `slow==fast` check |
| k-group reverse, n not divisible | Last group < k left unchanged | Count k nodes ahead before reversing; if count < k, return head |
| LRU cache: move to front | Forgetting to remove from current position first | Remove node from doubly-linked list THEN add to front |
| Merge sort on list: midpoint | Using fast/slow: slow must stop at midpoint, not midpoint+1 | `while (fast.next != null && fast.next.next != null)` (advance fast one extra check) |

```java
// Safe null-check template for fast/slow:
while (fast != null && fast.next != null) {
    slow = slow.next;
    fast = fast.next.next;
}
// After loop: fast==null → even length, fast.next==null → odd length
// slow is now at the midpoint (or just before it for even-length lists)

// K-group reverse: check k nodes exist before reversing
ListNode check = head;
int count = 0;
while (check != null && count < k) { check = check.next; count++; }
if (count < k) return head;  // don't reverse last group
```

---

## 😵 Commonly Confused With

**vs Array Two Pointers**: Both use a slow/fast or left/right pointer concept. Deciding question: *Is the data in an array (use index arithmetic) or a linked list (must follow `.next` pointers)?* In linked lists you can't go backwards without extra structure.

**vs Stack for reversal**: You can reverse a linked list by pushing to a stack and rebuilding. But in-place reversal with prev/curr/next uses O(1) space. Deciding question: *Is O(n) space acceptable or must you reverse in-place?*

**vs Floyd's for arrays**: Floyd's cycle detection also finds duplicates in arrays (LC 287, Find the Duplicate Number, where the array values form implicit pointer links). Deciding question: *Is it a literal linked list structure, or an array where indices act like next pointers?*

---

## 14 — Canonical LeetCode Problems

| Flavor | Problems |
|--------|---------|
| Reverse | LC 206, LC 92 (sublist), LC 25 (k-groups) |
| Fast-slow | LC 141 (cycle), LC 142 (cycle start), LC 876 (middle), LC 234 (palindrome) |
| Two-pointer gap | LC 19 (remove n-th from end) |
| Merge | LC 21, LC 23 (K lists — use heap) |
| Reorder | LC 143, LC 328 (odd-even) |
| Deep copy | LC 138 |
| Design | LC 146 (LRU), LC 460 (LFU) |
| Sort | LC 148 |
