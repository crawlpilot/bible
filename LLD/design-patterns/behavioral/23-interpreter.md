# 23. Interpreter
**Category**: Behavioral  
**GoF**: Yes  
**Complexity**: High  
**Frequency in FAANG interviews**: Occasional

> Given a language, define a representation for its grammar along with an interpreter that uses the representation to interpret sentences in the language.

---

## Problem It Solves

A promo rule engine needs to express complex business rules as configurable strings that merchants enter in a UI — not hardcoded Java. Rules like: "BUY 2 GET 1 FREE ON category:electronics BETWEEN 2024-11-24 AND 2024-11-30" or "10% OFF WHEN cart:total > 100 AND user:tier = GOLD". Without Interpreter, each new rule type requires a code deployment. With Interpreter, rules are parsed into an expression tree — new rule types are new expression classes.

## Structure (Participants)

```
      «interface»
   PromoExpression
┌──────────────────────┐
│ + interpret(ctx):    │
│     ExpressionResult │
└──────────────────────┘
          △
    ┌─────┴──────────────────────────────────────┐
    │              │              │               │
TerminalExpr  BuyXGetY    CategoryFilter  DateRange
(leaf)        Expression  Expression      Expression
              │              │               │
         CompositeExpr: AND, OR, NOT
```

Key participants:
- **Expression** (`PromoExpression`): interface with `interpret(context)` method
- **Terminal Expressions** (leaves): check a single condition (category match, date range, cart total)
- **Non-Terminal Expressions** (composites): combine expressions (`AND`, `OR`, `NOT`)
- **Context** (`PromoContext`): holds the current cart, user, timestamp — read by expressions
- **Client**: builds the expression tree by parsing the rule string

---

## Real-World Use Case: Promo Rule DSL

Merchants configure promotions via a UI that generates rule strings. The rule engine parses these into expression trees and evaluates them at checkout. Merchants can express any combination of: category filters, quantity requirements, date ranges, user tier requirements, cart total thresholds, and BOGO variants.

### Implementation

```java
// Context — passed to every expression during evaluation
public record PromoInterpretContext(
    Cart cart,
    User user,
    Instant evaluatedAt,
    Map<String, String> metadata
) {}

public record ExpressionResult(boolean matches, Money discountAmount, String description) {
    public static ExpressionResult match(Money discount, String desc) {
        return new ExpressionResult(true, discount, desc);
    }
    public static ExpressionResult noMatch(String desc) {
        return new ExpressionResult(false, Money.ZERO, desc);
    }
}

// Expression interface
public interface PromoExpression {
    ExpressionResult interpret(PromoInterpretContext ctx);
}

// Terminal: Category filter
public class CategoryFilterExpression implements PromoExpression {
    private final String category;

    public CategoryFilterExpression(String category) { this.category = category; }

    @Override
    public ExpressionResult interpret(PromoInterpretContext ctx) {
        List<CartItem> matching = ctx.cart().getItemsByCategory(category);
        boolean hasItems = !matching.isEmpty();
        return hasItems
            ? ExpressionResult.match(Money.ZERO, "Category " + category + ": " + matching.size() + " items")
            : ExpressionResult.noMatch("No items in category: " + category);
    }
}

// Terminal: Date range
public class DateRangeExpression implements PromoExpression {
    private final LocalDate startDate;
    private final LocalDate endDate;

    @Override
    public ExpressionResult interpret(PromoInterpretContext ctx) {
        LocalDate today = ctx.evaluatedAt().atZone(ZoneId.systemDefault()).toLocalDate();
        boolean inRange = !today.isBefore(startDate) && !today.isAfter(endDate);
        return inRange
            ? ExpressionResult.match(Money.ZERO, "Date in range " + startDate + " to " + endDate)
            : ExpressionResult.noMatch("Outside date range " + startDate + " to " + endDate);
    }
}

// Terminal: User tier check
public class UserTierExpression implements PromoExpression {
    private final String requiredTier;

    @Override
    public ExpressionResult interpret(PromoInterpretContext ctx) {
        String userTier = ctx.user().loyaltyTier();
        boolean matches = userTier.equals(requiredTier);
        return matches
            ? ExpressionResult.match(Money.ZERO, "User tier: " + userTier)
            : ExpressionResult.noMatch("User tier " + userTier + " != " + requiredTier);
    }
}

// Terminal: Cart total threshold
public class CartTotalExpression implements PromoExpression {
    private final Money threshold;
    private final String operator;  // ">", ">=", "<", "<="

    @Override
    public ExpressionResult interpret(PromoInterpretContext ctx) {
        Money total = ctx.cart().subtotal();
        boolean matches = switch (operator) {
            case ">"  -> total.isGreaterThan(threshold);
            case ">=" -> total.isGreaterThanOrEqualTo(threshold);
            case "<"  -> total.isLessThan(threshold);
            default   -> total.isLessThanOrEqualTo(threshold);
        };
        return matches
            ? ExpressionResult.match(Money.ZERO, "Cart total " + total + " " + operator + " " + threshold)
            : ExpressionResult.noMatch("Cart total " + total + " does not satisfy " + operator + " " + threshold);
    }
}

// Terminal: BuyXGetY discount action
public class BuyXGetYExpression implements PromoExpression {
    private final String category;
    private final int buyQty;
    private final int getQty;

    @Override
    public ExpressionResult interpret(PromoInterpretContext ctx) {
        List<CartItem> items = ctx.cart().getItemsByCategory(category);
        int totalQty = items.stream().mapToInt(CartItem::quantity).sum();

        if (totalQty < buyQty) {
            return ExpressionResult.noMatch("Need " + buyQty + " items in " + category + ", have " + totalQty);
        }

        // Cheapest items in the category are free
        items.sort(Comparator.comparing(item -> item.getUnitPrice()));
        int freeCount = (totalQty / (buyQty + getQty)) * getQty;
        Money discount = Money.ZERO;
        int remaining = freeCount;
        for (CartItem item : items) {
            if (remaining <= 0) break;
            int freeFromThis = Math.min(remaining, item.quantity());
            discount = discount.add(item.getUnitPrice().multiply(freeFromThis));
            remaining -= freeFromThis;
        }

        return ExpressionResult.match(discount, "Buy " + buyQty + " Get " + getQty + " Free on " + category);
    }
}

// Non-terminal: AND
public class AndExpression implements PromoExpression {
    private final PromoExpression left;
    private final PromoExpression right;

    @Override
    public ExpressionResult interpret(PromoInterpretContext ctx) {
        ExpressionResult leftResult = left.interpret(ctx);
        if (!leftResult.matches()) return leftResult;  // short-circuit
        return right.interpret(ctx);
    }
}

// Non-terminal: OR
public class OrExpression implements PromoExpression {
    private final PromoExpression left;
    private final PromoExpression right;

    @Override
    public ExpressionResult interpret(PromoInterpretContext ctx) {
        ExpressionResult leftResult = left.interpret(ctx);
        if (leftResult.matches()) return leftResult;
        return right.interpret(ctx);
    }
}

// Non-terminal: NOT
public class NotExpression implements PromoExpression {
    private final PromoExpression inner;

    @Override
    public ExpressionResult interpret(PromoInterpretContext ctx) {
        ExpressionResult result = inner.interpret(ctx);
        return result.matches()
            ? ExpressionResult.noMatch("NOT: " + result.description())
            : ExpressionResult.match(Money.ZERO, "NOT: " + result.description());
    }
}

// Parser — builds expression tree from rule string
public class PromoRuleParser {
    // Rule: "BUY 2 GET 1 FREE ON category:electronics BETWEEN 2024-11-24 AND 2024-11-30"
    public PromoExpression parse(String rule) {
        // Tokenize and build expression tree
        // Simplified: real implementation uses ANTLR or hand-rolled recursive descent parser
        PromoExpression buyXGetY = new BuyXGetYExpression("electronics", 2, 1);
        PromoExpression dateRange = new DateRangeExpression(
            LocalDate.of(2024, 11, 24), LocalDate.of(2024, 11, 30)
        );
        return new AndExpression(buyXGetY, dateRange);
    }

    // Rule: "10% OFF WHEN cart:total >= 100 AND user:tier = GOLD"
    public PromoExpression parseComplexRule(String rule) {
        PromoExpression cartTotal = new CartTotalExpression(Money.of(100), ">=");
        PromoExpression userTier = new UserTierExpression("GOLD");
        return new AndExpression(cartTotal, userTier);
        // The discount application is a separate expression wrapping this condition
    }
}

// Client
PromoRuleParser parser = new PromoRuleParser();
PromoExpression rule = parser.parse("BUY 2 GET 1 FREE ON category:electronics BETWEEN 2024-11-24 AND 2024-11-30");

PromoInterpretContext ctx = new PromoInterpretContext(cart, user, Instant.now(), Map.of());
ExpressionResult result = rule.interpret(ctx);

if (result.matches()) {
    cart.applyDiscount(result.discountAmount(), result.description());
}
```

### How It Works (walkthrough)

1. Rule: "BUY 2 GET 1 FREE ON category:electronics BETWEEN 2024-11-24 AND 2024-11-30"
2. Parser builds: `AndExpression(BuyXGetYExpression("electronics", 2, 1), DateRangeExpression(...))`
3. `rule.interpret(ctx)` → `AndExpression.interpret()` → `BuyXGetYExpression.interpret()`
4. Cart has 3 electronics items → 3 ≥ 2 → discount = cheapest item price → `ExpressionResult.match($199, "...")`
5. `AndExpression`: left matched → `DateRangeExpression.interpret()` → today is within range → match
6. Final: `ExpressionResult(true, $199, "Buy 2 Get 1 Free on electronics")` → discount applied

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | Each expression class handles one grammar rule |
| Open/Closed | ✅ | Add `UserAgeExpression` — new class; parser updated; existing expressions untouched |
| Liskov Substitution | ✅ | All expressions substitutable through `PromoExpression` |
| Interface Segregation | ✅ | Single `interpret()` method |
| Dependency Inversion | ✅ | Client depends on `PromoExpression` interface |

---

## When to Use

- A grammar for a domain-specific language can be expressed as a tree of expression classes
- The grammar is simple enough that a full parser generator (ANTLR) would be over-engineering
- Expressions need to be composable (AND, OR, NOT)
- Business rules must be configurable at runtime without code deployments

## When NOT to Use

- Grammar is complex (many production rules, operator precedence) — use ANTLR or a proper parser
- Performance is critical — tree traversal per request adds latency; pre-compile rules to bytecode
- Grammar changes frequently — Interpreter's class-per-rule approach makes large grammars hard to maintain

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Business rules configurable without code deployment | Complex grammars lead to class explosion |
| Expressions are composable — AND, OR, NOT for free | Parser implementation can be complex |
| Each expression independently unit-testable | Performance: tree evaluation is slower than compiled code |

---

**FAANG interview application**: "Interpreter is the right pattern for a promo rule DSL where merchants configure rules like 'BUY 2 GET 1 FREE ON category:electronics'. Each grammar construct — BuyXGetY, CategoryFilter, DateRange, AND, OR — is a class implementing `interpret()`. The parser builds the expression tree from the rule string; the tree is evaluated at checkout for each cart. For production, I'd pre-parse rules on save (not on every request), cache the expression tree, and use ANTLR for complex grammars."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Composite](../structural/08-composite.md) | Interpreter's expression tree is a Composite — AND/OR are composites, terminals are leaves |
| [Visitor](22-visitor.md) | Visitor can traverse the expression tree for operations like pretty-printing or optimization |
| [Strategy](20-strategy.md) | Strategy can be used to select different parsing/evaluation strategies for different rule types |
