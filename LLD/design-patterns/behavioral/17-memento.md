# 17. Memento
**Category**: Behavioral  
**GoF**: Yes  
**Complexity**: Medium  
**Frequency in FAANG interviews**: Occasional

> Without violating encapsulation, capture and externalize an object's internal state so that the object can be restored to this state later.

---

## Problem It Solves

A user builds a cart as a guest, then logs in. The platform must merge the guest cart with the user's existing saved cart without losing either state. Also, a user wants to "undo" changes to their cart from earlier in the session. Without Memento, saving/restoring cart state requires exposing private fields or writing custom serialization everywhere. Memento captures the state as an opaque snapshot — the `Cart` knows how to create and restore from its memento; nothing else does.

## Structure (Participants)

```
       Originator                    Memento
         (Cart)                   (CartSnapshot)
  ┌──────────────────────┐   ┌─────────────────────────────┐
  │ - items: List        │   │ - items: List (deep copy)    │
  │ - appliedPromos: List│   │ - appliedPromos: List        │
  │ + save(): Snapshot   ├──►│ - shippingAddress: Address  │
  │ + restore(Snapshot)  │   │ - savedAt: Instant           │
  └──────────────────────┘   │ (package-private constructor)│
                             └─────────────────────────────┘
                                           △ stored by
                                      Caretaker
                                   (CartCaretaker)
                             ┌─────────────────────────────┐
                             │ - history: Deque<CartSnapshot│
                             │ + save(cart)                 │
                             │ + restore(cart)              │
                             │ + getMergeSnapshot()         │
                             └─────────────────────────────┘
```

Key participants:
- **Originator** (`Cart`): knows how to create a `CartSnapshot` from its state and restore from one
- **Memento** (`CartSnapshot`): immutable snapshot; contents accessible only to `Cart`
- **Caretaker** (`CartCaretaker`): stores snapshots; requests save/restore on the cart; never reads memento internals

---

## Real-World Use Case: Guest Cart → Login Merge

When a user logs in mid-session, the platform has: a guest cart (live in session) and a saved cart (from the user's last login). It must merge both, preferring the higher-quantity for duplicates. Memento lets the guest cart be saved as an opaque snapshot, and restored onto the merged cart atomically.

### Implementation

```java
// Memento — opaque snapshot of Cart state
public final class CartSnapshot {
    private final List<CartItem> items;          // deep copy
    private final List<String> appliedPromoCodes;
    private final Address shippingAddress;
    private final Instant savedAt;

    // Package-private: only Cart can create
    CartSnapshot(List<CartItem> items, List<String> promos, Address address) {
        this.items = List.copyOf(items);            // immutable deep copy
        this.appliedPromoCodes = List.copyOf(promos);
        this.shippingAddress = address;
        this.savedAt = Instant.now();
    }

    // Package-private accessors: only Cart can read
    List<CartItem> getItems()             { return items; }
    List<String> getAppliedPromoCodes()   { return appliedPromoCodes; }
    Address getShippingAddress()          { return shippingAddress; }

    // Public: caretaker can read metadata to display history
    public Instant getSavedAt() { return savedAt; }
    public int itemCount()      { return items.size(); }
}

// Originator — the cart itself
public class Cart {
    private List<CartItem> items = new ArrayList<>();
    private List<String> appliedPromoCodes = new ArrayList<>();
    private Address shippingAddress;

    // Operations
    public void addItem(CartItem item) { /* ... */ }
    public void removeItem(String sku) { /* ... */ }
    public void applyPromo(String code) { appliedPromoCodes.add(code); }
    public void setShippingAddress(Address addr) { this.shippingAddress = addr; }

    // Memento: save current state
    public CartSnapshot save() {
        return new CartSnapshot(items, appliedPromoCodes, shippingAddress);
    }

    // Memento: restore from snapshot
    public void restore(CartSnapshot snapshot) {
        this.items = new ArrayList<>(snapshot.getItems());
        this.appliedPromoCodes = new ArrayList<>(snapshot.getAppliedPromoCodes());
        this.shippingAddress = snapshot.getShippingAddress();
    }

    // Merge: incorporate another snapshot (guest cart merge)
    public void mergeFrom(CartSnapshot guestSnapshot) {
        for (CartItem guestItem : guestSnapshot.getItems()) {
            Optional<CartItem> existing = findBySku(guestItem.sku());
            if (existing.isPresent()) {
                // Take the higher quantity
                int mergedQty = Math.max(existing.get().quantity(), guestItem.quantity());
                existing.get().setQuantity(mergedQty);
            } else {
                items.add(guestItem.deepCopy());
            }
        }
        // Add any promo codes not already applied
        guestSnapshot.getAppliedPromoCodes().stream()
            .filter(code -> !appliedPromoCodes.contains(code))
            .forEach(appliedPromoCodes::add);
    }

    public Money calculateTotal() { /* ... */ }
}

// Caretaker — manages the snapshot history
public class CartCaretaker {
    private final Deque<CartSnapshot> history = new ArrayDeque<>();
    private final int maxHistory;

    public CartCaretaker(int maxHistory) { this.maxHistory = maxHistory; }

    public void save(Cart cart) {
        CartSnapshot snapshot = cart.save();
        history.push(snapshot);
        if (history.size() > maxHistory) history.pollLast();
    }

    public boolean undo(Cart cart) {
        if (history.size() < 2) return false;  // need at least 2: current + previous
        history.pop();  // discard current
        cart.restore(history.peek());
        return true;
    }

    public CartSnapshot getLatestSnapshot() {
        return history.isEmpty() ? null : history.peek();
    }

    public List<Instant> getHistoryTimestamps() {
        return history.stream().map(CartSnapshot::getSavedAt).collect(toList());
    }
}

// Login merge service
public class CartMergeService {
    public Cart mergeOnLogin(Cart guestCart, Cart savedCart, CartCaretaker savedCartCaretaker) {
        // Save pre-merge snapshot for rollback
        savedCartCaretaker.save(savedCart);

        // Get guest cart snapshot
        CartSnapshot guestSnapshot = guestCart.save();

        // Merge guest into saved
        savedCart.mergeFrom(guestSnapshot);

        // Save post-merge snapshot
        savedCartCaretaker.save(savedCart);

        return savedCart;
    }
}

// Usage
Cart guestCart = sessionStore.getGuestCart(sessionId);
Cart userSavedCart = cartRepository.load(userId);
CartCaretaker caretaker = new CartCaretaker(10);

Cart mergedCart = mergeService.mergeOnLogin(guestCart, userSavedCart, caretaker);

// User: "undo the merge, I want to start fresh"
caretaker.undo(mergedCart);  // reverts to pre-merge state
```

### How It Works (walkthrough)

1. Guest adds Laptop + Mouse to cart, applies promo "SAVE10"
2. User logs in → `CartMergeService.mergeOnLogin(guestCart, savedCart, caretaker)`
3. `savedCart.save()` → `CartSnapshot` with saved cart items; pushed to caretaker history
4. `guestSnapshot = guestCart.save()` → snapshot of guest items + promo
5. `savedCart.mergeFrom(guestSnapshot)` → merges items (higher qty wins), adds "SAVE10" promo
6. `caretaker.save(savedCart)` → post-merge snapshot pushed to history
7. User: "undo merge" → `caretaker.undo(mergedCart)` → pops post-merge, restores pre-merge snapshot

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | `Cart` handles cart logic; `CartCaretaker` handles snapshot lifecycle |
| Open/Closed | ✅ | Add new fields to `CartSnapshot` without changing `CartCaretaker` |
| Liskov Substitution | ✅ | N/A — Memento is not typically polymorphic |
| Interface Segregation | ✅ | Caretaker only accesses `savedAt` and `itemCount` — not the cart internals |
| Dependency Inversion | ✅ | Caretaker depends on `CartSnapshot` abstraction, not on Cart internals |

---

## When to Use

- Object state must be saved and restored without violating encapsulation
- Undo/redo requires saving full state snapshots (vs. Command which saves deltas)
- Snapshots should be opaque to the caretaker (internal structure is private)

## When NOT to Use

- Originator state is large — snapshots are memory-heavy (use Command/delta instead)
- Snapshots are needed across restarts — use serialization to a database or event log instead
- State can be reconstructed from a log of operations — Event Sourcing is more appropriate

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Encapsulation preserved — caretaker can't access internals | Memory: deep copies of large object graphs are expensive |
| Originator controls what's in the snapshot | Object graph must be fully deep-copied — shallow copies cause aliasing bugs |
| Clean undo/redo without delta tracking | Restoring from snapshot loses events between snapshots |

---

**FAANG interview application**: "Memento is the right pattern when you need to save and restore object state without leaking private fields. The key implementation detail: the snapshot must be a true deep copy — not a reference to the cart's internal list. I'd use Memento for guest→login cart merge: save the pre-merge state as a snapshot, perform the merge, save the post-merge state. If the merge is rejected, restore the pre-merge snapshot. For large carts, consider storing snapshots by serializing to JSON and storing in Redis with a TTL."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Command](14-command.md) | Command saves the delta (operation + undo data); Memento saves the full state. Often used together for undo systems. |
| [Event Sourcing](../modern/27-event-sourcing.md) | Event Sourcing is an alternative to Memento — current state is replayed from the event log, not saved as a snapshot |
