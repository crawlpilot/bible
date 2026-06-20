# Structural Patterns

Structural patterns describe how to compose classes and objects to form larger structures. They use inheritance and composition to form new functionality from existing code.

## When to Reach for a Structural Pattern

- Two incompatible interfaces must work together (Adapter)
- You need to add behaviour to objects without touching their class (Decorator)
- A subsystem is complex and clients need a simpler entry point (Facade)
- You want to control access to an object transparently (Proxy)
- You have a tree structure with uniform leaf/branch operations (Composite)
- You need to separate two dimensions of variation (Bridge)
- Memory is a concern with many similar fine-grained objects (Flyweight)

## Patterns in This Category

| Pattern | Intent | Complexity | Interview Frequency |
|---------|--------|-----------|---------------------|
| [Adapter](06-adapter.md) | Convert one interface to another | Low | Common |
| [Bridge](07-bridge.md) | Separate abstraction from implementation | High | Occasional |
| [Composite](08-composite.md) | Compose objects into tree structures | Medium | Common |
| [Decorator](09-decorator.md) | Add responsibilities to objects dynamically | Medium | Common |
| [Facade](10-facade.md) | Provide a simplified interface to a subsystem | Low | Common |
| [Flyweight](11-flyweight.md) | Share fine-grained objects efficiently | High | Occasional |
| [Proxy](12-proxy.md) | Control access to another object | Medium | Common |

## Key Distinction: Adapter vs Decorator vs Proxy

- **Adapter**: changes the *interface* (wraps to make incompatible interface fit)
- **Decorator**: keeps the *same interface*, adds *behaviour*
- **Proxy**: keeps the *same interface*, controls *access* (cache, auth, lazy load)
