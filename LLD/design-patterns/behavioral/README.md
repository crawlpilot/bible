# Behavioral Patterns

Behavioral patterns are concerned with algorithms and the assignment of responsibilities between objects. They characterize how objects interact and distribute responsibilities.

## When to Reach for a Behavioral Pattern

- You have a chain of handlers where only one should process a request (Chain of Responsibility)
- You want to encapsulate a request as an object for queuing or undo (Command)
- You need to traverse a collection without exposing its internals (Iterator)
- Many objects need to notify many others without tight coupling (Observer)
- An object's behaviour depends on its state (State)
- You need to swap algorithms at runtime (Strategy)
- You want to add operations to objects without changing their class (Visitor)

## Patterns in This Category

| Pattern | Intent | Complexity | Interview Frequency |
|---------|--------|-----------|---------------------|
| [Chain of Responsibility](13-chain-of-responsibility.md) | Pass request along a chain of handlers | Medium | Common |
| [Command](14-command.md) | Encapsulate a request as an object | Medium | Common |
| [Iterator](15-iterator.md) | Access elements without exposing internals | Low | Occasional |
| [Mediator](16-mediator.md) | Define how objects interact via a mediator | Medium | Occasional |
| [Memento](17-memento.md) | Capture and restore object state | Medium | Occasional |
| [Observer](18-observer.md) | One-to-many dependency notification | Low | Common |
| [State](19-state.md) | Alter behaviour as internal state changes | Medium | Common |
| [Strategy](20-strategy.md) | Define a family of algorithms; make them interchangeable | Low | Common |
| [Template Method](21-template-method.md) | Define skeleton of an algorithm; defer steps to subclasses | Low | Common |
| [Visitor](22-visitor.md) | Add operations to objects without modifying them | High | Occasional |
| [Interpreter](23-interpreter.md) | Define a grammar and interpret sentences in the language | High | Rare |

## Key Distinction: Strategy vs State vs Template Method

- **Strategy**: client *chooses* the algorithm; swapped from outside
- **State**: object *itself* transitions between states; client doesn't control which
- **Template Method**: fixed algorithm skeleton; subclasses fill in specific steps (inheritance-based Strategy)
