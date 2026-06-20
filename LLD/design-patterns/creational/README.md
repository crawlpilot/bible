# Creational Patterns

Creational patterns abstract the object creation process. They make the system independent of how its objects are created, composed, and represented.

## When to Reach for a Creational Pattern

- The creation logic is complex, conditional, or likely to change
- You need to control the number of instances (Singleton) or the type of instance (Factory)
- Object construction involves many optional steps (Builder)
- You need copies of existing objects rather than new ones (Prototype)

## Patterns in This Category

| Pattern | Intent | Complexity | Interview Frequency |
|---------|--------|-----------|---------------------|
| [Singleton](01-singleton.md) | Ensure one instance; provide global access point | Low | Common |
| [Factory Method](02-factory-method.md) | Subclasses decide which class to instantiate | Medium | Common |
| [Abstract Factory](03-abstract-factory.md) | Create families of related objects without specifying concrete classes | Medium | Occasional |
| [Builder](04-builder.md) | Separate complex object construction from its representation | Medium | Common |
| [Prototype](05-prototype.md) | Create objects by cloning an existing instance | Low | Occasional |

## Key Distinction: Factory Method vs Abstract Factory

- **Factory Method**: one product, subclass decides the type → `PaymentGatewayFactory.createGateway("stripe")`
- **Abstract Factory**: a *family* of related products, entire factory swapped together → `CloudResourceFactory.createCompute()` + `.createStorage()` + `.createDatabase()`
