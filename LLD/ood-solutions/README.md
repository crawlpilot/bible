# Grokking OOD — Complete Solution Set

All 16 problems from *Grokking the Object Oriented Design Interview* solved at principal engineer depth.

Each solution includes: class diagram (Mermaid), design patterns, Java implementation, SOLID analysis, extensibility discussion, and FAANG interview tips.

---

## Problem Index

| # | Problem | Key Patterns | Difficulty |
|---|---------|-------------|------------|
| 01 | [Parking Lot](01-parking-lot.md) | Strategy, Factory, Singleton, Observer | Medium |
| 02 | [Library Management System](02-library-management.md) | Factory, Observer, Template Method | Medium |
| 03 | [Online Shopping System (Amazon)](03-online-shopping-amazon.md) | Strategy, Decorator, Observer, Chain of Responsibility | Hard |
| 04 | [Stack Overflow](04-stack-overflow.md) | Decorator, Observer, Strategy | Medium |
| 05 | [Movie Ticket Booking](05-movie-ticket-booking.md) | State, Strategy, Factory | Medium |
| 06 | [ATM](06-atm.md) | State, Command, Singleton | Hard |
| 07 | [Airline Management System](07-airline-management.md) | Strategy, Observer, Factory | Hard |
| 08 | [Blackjack / Deck of Cards](08-blackjack.md) | Composite, Strategy, Factory | Medium |
| 09 | [Hotel Management System](09-hotel-management.md) | Strategy, Observer, Factory | Medium |
| 10 | [Restaurant Management System](10-restaurant-management.md) | Observer, Command, Strategy | Medium |
| 11 | [Chess](11-chess.md) | Strategy, Command, Memento | Hard |
| 12 | [Online Stock Brokerage](12-stock-brokerage.md) | Observer, Strategy, Command | Hard |
| 13 | [Car Rental System](13-car-rental.md) | Strategy, Factory, Decorator | Medium |
| 14 | [LinkedIn](14-linkedin.md) | Observer, Strategy, Composite | Hard |
| 15 | [Cricinfo](15-cricinfo.md) | Observer, Composite, Strategy | Medium |
| 16 | [Facebook / Social Network](16-facebook-social-network.md) | Observer, Composite, Strategy, Proxy | Hard |

---

## How to Use This Material

### Interview Framework (apply to every problem)

1. **Clarify scope** — ask about actors, primary use cases, and what to NOT design
2. **Identify nouns** → classes/entities; **verbs** → methods/behaviors
3. **Spot patterns early** — state machines → State, hierarchies → Composite, variations → Strategy
4. **Draw class diagram first**, then code the hot path
5. **SOLID-check before submitting** — SRP violations are the most common failure mode

### Scoring Rubric at FAANG

| Dimension | What Interviewers Look For |
|-----------|---------------------------|
| Requirements | Did you ask the right clarifying questions? |
| Modeling | Are entities clean, minimal, and non-overlapping? |
| Patterns | Correct pattern application, not forced pattern use |
| Code Quality | Clean interfaces, proper encapsulation, no god objects |
| Extensibility | Can you add a new feature without breaking existing code? |
| SOLID | Single Responsibility and Open/Closed are most scrutinized |

---

## Common Pitfalls

- **God class**: One class (e.g., `ParkingLot`, `Library`) doing everything — split responsibilities
- **Primitive obsession**: Using `String` for status instead of enums or state objects
- **Missing interfaces**: Coupling to concrete classes instead of abstractions
- **Overengineering**: Adding patterns the problem doesn't warrant
- **Skipping enums**: Every "type" or "status" field should be an enum
- **Mutable shared state**: Not protecting concurrent access in booking/reservation systems
