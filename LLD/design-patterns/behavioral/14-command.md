# 14. Command
**Category**: Behavioral  
**GoF**: Yes  
**Complexity**: Medium  
**Frequency in FAANG interviews**: Common

> Encapsulate a request as an object, thereby letting you parameterize clients with different requests, queue or log requests, and support undoable operations.

---

## Problem It Solves

A cart has operations: add item, remove item, apply promo, change quantity. Each is triggered by different UI interactions. Undo/redo requires reverting operations in order. Without Command, each operation is a method call — undoable operations require complex rollback logic scattered everywhere. Command turns each operation into an object with `execute()` and `undo()` — the history stack holds the last N commands, and undo pops and calls `undo()`.

## Structure (Participants)

```
     «interface»
    CartCommand
┌──────────────────┐
│ + execute()      │
│ + undo()         │
│ + describe(): str│
└──────────────────┘
        △
┌───────┴──────────────────────┐
│               │              │
AddItemCommand RemoveItem  ApplyPromo
               Command    Command
```

Key participants:
- **Command** (`CartCommand`): interface with `execute()` and `undo()`
- **Concrete Commands**: each encapsulates one operation and knows how to undo it
- **Receiver** (`Cart`): the object that actually performs the operation
- **Invoker** (`CartCommandHistory`): executes commands and maintains the history stack
- **Client**: creates concrete commands and submits to invoker

---

## Real-World Use Case: Cart Operations with Undo / Guest-Login Merge

A user builds a cart as a guest (add 3 items, apply promo), then logs in. The system must merge the guest cart with the existing logged-in cart — replaying the guest commands on the merged state. Undo lets users reverse the last N cart actions ("I didn't mean to add that").

### Implementation

```java
// Command interface
public interface CartCommand {
    void execute();
    void undo();
    String describe();
}

// Concrete Commands
public class AddItemCommand implements CartCommand {
    private final Cart cart;
    private final CartItem item;
    private boolean wasAdded = false;

    public AddItemCommand(Cart cart, CartItem item) {
        this.cart = cart;
        this.item = item;
    }

    @Override public void execute() { cart.addItem(item); wasAdded = true; }
    @Override public void undo()    { if (wasAdded) cart.removeItem(item); }
    @Override public String describe() { return "Add " + item.quantity() + "× " + item.name(); }
}

public class RemoveItemCommand implements CartCommand {
    private final Cart cart;
    private final CartItem item;
    private boolean wasRemoved = false;

    @Override public void execute() { cart.removeItem(item); wasRemoved = true; }
    @Override public void undo()    { if (wasRemoved) cart.addItem(item); }
    @Override public String describe() { return "Remove " + item.name(); }
}

public class ChangeQuantityCommand implements CartCommand {
    private final Cart cart;
    private final String sku;
    private final int newQuantity;
    private int previousQuantity;

    @Override
    public void execute() {
        previousQuantity = cart.getQuantity(sku);
        cart.setQuantity(sku, newQuantity);
    }

    @Override
    public void undo() {
        cart.setQuantity(sku, previousQuantity);
    }

    @Override public String describe() { return "Set " + sku + " qty to " + newQuantity; }
}

public class ApplyPromoCommand implements CartCommand {
    private final Cart cart;
    private final PromoService promoService;
    private final String promoCode;
    private PromoResult appliedResult;

    @Override
    public void execute() {
        appliedResult = promoService.apply(promoCode, cart);
        cart.applyPromo(appliedResult);
    }

    @Override
    public void undo() {
        if (appliedResult != null) {
            cart.removePromo(appliedResult.promoId());
            appliedResult = null;
        }
    }

    @Override public String describe() { return "Apply promo code: " + promoCode; }
}

// Invoker — command history with undo/redo
public class CartCommandHistory {
    private final Deque<CartCommand> undoStack = new ArrayDeque<>();
    private final Deque<CartCommand> redoStack = new ArrayDeque<>();
    private final int maxHistory;

    public CartCommandHistory(int maxHistory) {
        this.maxHistory = maxHistory;
    }

    public void execute(CartCommand command) {
        command.execute();
        undoStack.push(command);
        redoStack.clear();  // new command clears redo branch

        if (undoStack.size() > maxHistory) {
            undoStack.pollLast();  // drop oldest
        }
    }

    public boolean undo() {
        if (undoStack.isEmpty()) return false;
        CartCommand command = undoStack.pop();
        command.undo();
        redoStack.push(command);
        return true;
    }

    public boolean redo() {
        if (redoStack.isEmpty()) return false;
        CartCommand command = redoStack.pop();
        command.execute();
        undoStack.push(command);
        return true;
    }

    public List<String> getHistory() {
        return undoStack.stream().map(CartCommand::describe).collect(toList());
    }
}

// Guest → login cart merge: replay commands
public class CartMergeService {
    public Cart merge(Cart guestCart, Cart loggedInCart, List<CartCommand> guestCommands) {
        // Strategy: replay guest commands on top of logged-in cart
        CartCommandHistory mergeHistory = new CartCommandHistory(50);
        for (CartCommand cmd : guestCommands) {
            // Rebind command to logged-in cart
            CartCommand reboundCmd = rebind(cmd, loggedInCart);
            mergeHistory.execute(reboundCmd);
        }
        return loggedInCart;
    }
}

// Client
CartCommandHistory history = new CartCommandHistory(20);
Cart cart = new Cart();

history.execute(new AddItemCommand(cart, new CartItem("SKU-100", "Laptop", 1, Money.of(1299))));
history.execute(new AddItemCommand(cart, new CartItem("SKU-101", "Mouse", 2, Money.of(29.99))));
history.execute(new ApplyPromoCommand(cart, promoService, "SAVE20"));

// User: "undo that promo"
history.undo();   // removes promo

// User: "actually, keep the promo"
history.redo();   // re-applies promo
```

### How It Works (walkthrough)

1. User adds Laptop → `AddItemCommand.execute()` → cart has 1 item; pushed to undoStack
2. User adds Mouse → `AddItemCommand.execute()` → cart has 2 items; pushed to undoStack
3. User applies SAVE20 → `ApplyPromoCommand.execute()` → cart has promo; pushed to undoStack
4. User clicks Undo → `ApplyPromoCommand.undo()` → promo removed; moved to redoStack
5. User clicks Redo → `ApplyPromoCommand.execute()` again → promo re-applied

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | Each command owns one operation and its inverse |
| Open/Closed | ✅ | Add `GiftWrapCommand` — no changes to `CartCommandHistory` |
| Liskov Substitution | ✅ | All commands substitutable through `CartCommand` |
| Interface Segregation | ✅ | `execute()`, `undo()`, `describe()` — focused interface |
| Dependency Inversion | ✅ | `CartCommandHistory` depends on `CartCommand`, not concrete commands |

---

## When to Use

- Operations must be undoable / redoable
- Operations must be queued, logged, or replayed (event sourcing)
- You want to parameterize objects with operations (pass a command as a callback)
- Audit logging: serialize commands for compliance/debugging

## When NOT to Use

- Simple one-off operations with no undo requirement — `command.execute()` is just a method call with extra steps
- The undo logic is too complex to implement reliably (e.g., database side effects)

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Undo/redo with no special-case logic in clients | Undo logic can be complex — especially for operations with side effects (DB writes) |
| Commands are serializable — persist, audit, replay | Class explosion: one class per operation type |
| Decouples invoker from operation implementation | State management: commands must capture enough state to undo correctly |

---

**FAANG interview application**: "Command is the right pattern when operations need to be tracked, undone, or replayed. The key design decision is what state the command captures at `execute()` time to enable `undo()` — for `ChangeQuantityCommand`, you capture the previous quantity before changing it. For distributed systems, Command objects become messages on a queue; the history log becomes an event store — this is the basis of Event Sourcing."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Memento](17-memento.md) | Memento saves full object state; Command saves the delta (operation + undo data). Often used together. |
| [Event Sourcing](../modern/27-event-sourcing.md) | Event Sourcing is Command pattern applied at scale — commands become immutable events stored in a log |
| [Chain of Responsibility](13-chain-of-responsibility.md) | Commands can flow through a CoR pipeline for authorization before execution |
