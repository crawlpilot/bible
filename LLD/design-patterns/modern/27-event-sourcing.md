# 27. Event Sourcing
**Category**: Modern / Enterprise  
**GoF**: No (Fowler 2005, DDD community)  
**Complexity**: High  
**Frequency in FAANG interviews**: Common

---

## The One-Line Summary

> **Instead of storing the current value, store every change that ever happened.** The current value is computed by replaying the history.

---

## Part 1 — The Problem (Read This First)

### The Bank Statement Analogy

Your bank does NOT store "your balance is $1,200".

Your bank stores:
```
Jan 1:  Opening balance         +$0
Jan 5:  Salary deposited        +$3,000
Jan 8:  Rent paid               -$1,200
Jan 12: Groceries               -$200
Jan 15: Netflix subscription    -$15
Jan 20: Coffee                  -$5
Jan 25: Freelance payment       -$620 (a joke — this is income)

Current balance = sum of all transactions = $1,200
```

This is Event Sourcing. The **events** (deposits, withdrawals) are stored, not the final balance. The balance is computed *from* the events.

**Why?** Because someone calls you and says: "My balance was $2,000 last Tuesday, why is it $800 now?" You can answer that question by replaying events up to last Tuesday. If you only stored the current balance, you'd have no idea.

---

### The Software Problem: State Without History

The traditional approach stores only current state:

```java
// ❌ BEFORE — Traditional approach: store current state only
@Entity
public class LoyaltyAccount {
    private String accountId;
    private int balance;     // ← this is ALL we store
}

// What happens:
// User earns 100 points → balance = 100
// User earns 50 more   → balance = 150
// User redeems 80      → balance = 70
// 30 points expire     → balance = 40

// Now a user calls customer support: "Why do I only have 40 points? I thought I had 150!"
// Answer: "I have no idea. The database just says 40."
// ← This is the problem. The history is gone.
```

**Five problems this creates:**

```
Problem 1 — No audit trail
  "Who gave this account 500 bonus points? Was it authorized?"
  → Impossible to answer. The transaction table is empty; only the balance exists.

Problem 2 — No point-in-time queries
  "What was this account's balance on Black Friday for our promotion audit?"
  → Impossible. We only have today's balance.

Problem 3 — Lost update bugs under concurrency
  Thread A reads balance = 100
  Thread B reads balance = 100
  Thread A writes balance = 100 + 50 = 150
  Thread B writes balance = 100 + 30 = 130  ← Thread A's update is LOST
  Actual balance should be 180, but it's 130.

Problem 4 — Debugging is impossible
  Something went wrong with an account. When? What caused it? No idea.

Problem 5 — Can't feed CQRS read projections
  CQRS needs events to update read models. If you only store state, there are no events.
```

---

## Part 2 — The Solution

### The Core Idea

Instead of this:
```
Table: loyalty_accounts
| account_id | balance |
| USER123    |   40    |   ← only current state, history gone
```

Store this:
```
Table: account_events (append-only, never updated or deleted)
| event_id | account_id | event_type    | data                            | occurred_at         |
|----------|------------|---------------|---------------------------------|---------------------|
| 1        | USER123    | PointsEarned  | {points:100, orderId:"ORD-1"}   | 2024-01-05 10:00:00 |
| 2        | USER123    | PointsEarned  | {points:50,  orderId:"ORD-2"}   | 2024-01-08 14:30:00 |
| 3        | USER123    | PointsRedeemed| {points:80,  promoId:"P1"}      | 2024-01-12 09:15:00 |
| 4        | USER123    | PointsExpired | {points:30}                     | 2024-01-01 00:00:00 |

Current balance = 100 + 50 - 80 - 30 = 40  ← computed, not stored
Balance on Jan 10 = 100 + 50 = 150           ← replay events up to Jan 10
```

The events are the **source of truth**. Everything else is derived from them.

---

### The Four Core Concepts

```
┌─────────────────────────────────────────────────────────────────────┐
│                     EVENT SOURCING CONCEPTS                          │
│                                                                       │
│  1. EVENT                    2. EVENT STORE                          │
│  "Something that happened"   "The append-only log of events"         │
│  PointsEarned{100, ORD-1}    Like Kafka, but queryable per entity    │
│  Immutable, past tense       Never update or delete — append only    │
│                                                                       │
│  3. AGGREGATE                4. SNAPSHOT                             │
│  "The domain object"         "A shortcut to avoid replaying 10K      │
│  Reconstructed by            events from scratch"                    │
│  replaying events            Periodic saved state checkpoint         │
│  LoyaltyAccount.balance=40                                           │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 3 — Full Java Implementation

```java
// ════════════════════════════════════════════════════════════
// STEP 1 — Events
//
// Events describe something that HAPPENED (past tense).
// They are immutable — you never change a historical fact.
// "Points were earned" — always true, even if account closed later.
//
// Naming convention: past tense verbs
// PointsEarned ✅   EarnPoints ❌ (that's a command)
// ════════════════════════════════════════════════════════════

// Sealed interface: compiler enforces you handle ALL event types
public sealed interface AccountEvent permits
    PointsEarned, PointsRedeemed, PointsExpired, PointsAdjusted {}

public record PointsEarned(
    String eventId,     // globally unique ID for this event
    String accountId,   // which account this belongs to
    int points,         // how many points were earned
    String orderId,     // what triggered this (for audit trail)
    String source,      // "purchase", "referral", "bonus"
    Instant occurredAt  // WHEN this happened (immutable fact)
) implements AccountEvent {}

public record PointsRedeemed(
    String eventId,
    String accountId,
    int points,
    String promoId,     // which promotion was used
    Instant occurredAt
) implements AccountEvent {}

public record PointsExpired(
    String eventId,
    String accountId,
    int points,
    Instant occurredAt
) implements AccountEvent {}

public record PointsAdjusted(
    String eventId,
    String accountId,
    int delta,          // positive = bonus, negative = correction
    String reason,      // "customer-service-correction", "system-error-fix"
    String adjustedBy,  // which employee/system made this adjustment
    Instant occurredAt
) implements AccountEvent {}

// ════════════════════════════════════════════════════════════
// STEP 2 — The Aggregate
//
// The aggregate is the domain object (LoyaltyAccount).
// It does NOT store data in a database directly.
// It is RECONSTRUCTED by replaying events.
//
// Two types of method:
//   Business methods (earnPoints, redeemPoints):
//     - Validate business rules
//     - Produce new events (don't mutate state directly)
//   Apply methods:
//     - Mutate state based on an event
//     - Called both when processing new events AND when replaying history
// ════════════════════════════════════════════════════════════

public class LoyaltyAccount {

    // Current state — derived from event replay
    private String accountId;
    private int balance;
    private int lifetimeEarned;
    private int lifetimeRedeemed;
    private long version;  // how many events have been applied (= optimistic lock version)

    // Uncommitted events: events produced this session, not yet saved to DB
    private final List<AccountEvent> uncommittedEvents = new ArrayList<>();

    // ── Constructor for new account ──────────────────────────────────────
    public LoyaltyAccount(String accountId) {
        this.accountId = accountId;
        this.balance = 0;
        this.version = 0;
    }

    // ── Reconstruct from event history (replaying past events) ───────────
    // This is called when loading an account from the event store
    public static LoyaltyAccount fromHistory(List<AccountEvent> events) {
        LoyaltyAccount account = new LoyaltyAccount(/* derive from first event */);
        // Each event is "applied" to rebuild state
        for (AccountEvent event : events) {
            account.applyFromHistory(event);
        }
        return account;
    }

    // ── Business operations (produce events, don't mutate directly) ───────
    // These methods validate rules and PRODUCE events.
    // They do NOT call the database. They do NOT call other services.
    // That's a key principle: aggregates are pure business logic.

    public void earnPoints(int points, String orderId, String source) {
        // Validate: points must be positive
        if (points <= 0) throw new InvalidPointsAmountException("Points must be positive, got: " + points);

        // Produce the event (don't update balance directly yet)
        PointsEarned event = new PointsEarned(
            UUID.randomUUID().toString(),
            this.accountId,
            points,
            orderId,
            source,
            Instant.now()
        );

        // Apply: this updates the balance AND adds to uncommittedEvents
        apply(event);
    }

    public void redeemPoints(int points, String promoId) {
        // Validate: can't redeem more than you have
        if (points > this.balance)
            throw new InsufficientPointsException(
                "Requested: " + points + ", Available: " + this.balance
            );

        PointsRedeemed event = new PointsRedeemed(
            UUID.randomUUID().toString(), this.accountId, points, promoId, Instant.now()
        );
        apply(event);
    }

    public void expirePoints(int pointsToExpire) {
        // Can only expire points that exist
        int expirable = Math.min(pointsToExpire, this.balance);
        if (expirable <= 0) return; // nothing to expire

        PointsExpired event = new PointsExpired(
            UUID.randomUUID().toString(), this.accountId, expirable, Instant.now()
        );
        apply(event);
    }

    // Customer service manual adjustment
    public void adjustPoints(int delta, String reason, String adjustedBy) {
        if (delta < 0 && Math.abs(delta) > this.balance)
            throw new InsufficientPointsException("Adjustment would result in negative balance");

        PointsAdjusted event = new PointsAdjusted(
            UUID.randomUUID().toString(), this.accountId, delta, reason, adjustedBy, Instant.now()
        );
        apply(event);
    }

    // ── Apply methods (pure state mutation based on event) ──────────────
    // This is called in TWO situations:
    //   1. When a new event is produced (above methods call it)
    //   2. When replaying history to reconstruct state
    // It must be DETERMINISTIC: same event → same state change, every time

    private void apply(AccountEvent event) {
        applyFromHistory(event);            // mutate state
        uncommittedEvents.add(event);       // mark as needing persistence
    }

    // Called during history replay (does NOT add to uncommittedEvents)
    public void applyFromHistory(AccountEvent event) {
        switch (event) {
            case PointsEarned e -> {
                this.balance += e.points();
                this.lifetimeEarned += e.points();
            }
            case PointsRedeemed e -> {
                this.balance -= e.points();
                this.lifetimeRedeemed += e.points();
            }
            case PointsExpired e -> {
                this.balance -= e.points();
                // Note: lifetimeEarned is NOT reduced — expired points were still earned
            }
            case PointsAdjusted e -> {
                this.balance += e.delta();
                // adjustments don't count as "earned" or "redeemed"
            }
        }
        this.version++;
    }

    // Getters
    public String getAccountId()                     { return accountId; }
    public int getBalance()                          { return balance; }
    public int getLifetimeEarned()                   { return lifetimeEarned; }
    public long getVersion()                         { return version; }
    public List<AccountEvent> getUncommittedEvents() { return Collections.unmodifiableList(uncommittedEvents); }
    public void markEventsCommitted()                { uncommittedEvents.clear(); }
}

// ════════════════════════════════════════════════════════════
// STEP 3 — Event Store Interface
//
// The event store is an append-only log.
// Think of it like a Kafka topic for one entity, but queryable.
// You can read events for a specific account in order.
// You NEVER update or delete events — history is immutable.
// ════════════════════════════════════════════════════════════

public interface EventStore {

    // Append new events for a stream (stream = one account's history)
    // expectedVersion: used to detect concurrent modifications
    // (if two requests try to modify the same account simultaneously,
    //  one will fail because the version has already changed)
    void appendEvents(String streamId, List<AccountEvent> events, long expectedVersion);

    // Read ALL events for this stream, in chronological order
    List<AccountEvent> readEvents(String streamId);

    // Read events in a version range (useful for incremental projection updates)
    List<AccountEvent> readEvents(String streamId, long fromVersion, long toVersion);

    // Snapshots: pre-computed state to avoid replaying 10,000 events from scratch
    Optional<AccountSnapshot> readSnapshot(String streamId);
    void writeSnapshot(AccountSnapshot snapshot);
}

// ════════════════════════════════════════════════════════════
// STEP 4 — PostgreSQL Event Store Implementation
//
// Schema:
// CREATE TABLE account_events (
//   stream_id    VARCHAR(36) NOT NULL,
//   event_type   VARCHAR(100) NOT NULL,
//   data         JSONB NOT NULL,
//   version      BIGINT NOT NULL,
//   occurred_at  TIMESTAMPTZ NOT NULL,
//   PRIMARY KEY (stream_id, version)  -- prevents duplicate versions
// );
// ════════════════════════════════════════════════════════════

@Repository
public class PostgresEventStore implements EventStore {

    private final JdbcTemplate jdbc;
    private final ObjectMapper json;

    @Override
    @Transactional
    public void appendEvents(String streamId, List<AccountEvent> events, long expectedVersion) {
        // Optimistic concurrency check: is the current version what we expect?
        Long currentVersion = jdbc.queryForObject(
            "SELECT COALESCE(MAX(version), 0) FROM account_events WHERE stream_id = ?",
            Long.class, streamId
        );

        if (currentVersion == null) currentVersion = 0L;

        if (!currentVersion.equals(expectedVersion)) {
            // Someone else modified this account between our load and save
            throw new OptimisticConcurrencyException(
                "Expected version " + expectedVersion + " but found " + currentVersion +
                " for stream " + streamId
            );
        }

        // Append each new event at the next version
        for (int i = 0; i < events.size(); i++) {
            AccountEvent event = events.get(i);
            jdbc.update(
                "INSERT INTO account_events (stream_id, event_type, data, version, occurred_at) " +
                "VALUES (?, ?, ?::jsonb, ?, ?)",
                streamId,
                event.getClass().getSimpleName(),    // "PointsEarned", "PointsRedeemed", etc.
                json.writeValueAsString(event),      // serialise to JSON
                expectedVersion + i + 1,             // version = expectedVersion + 1, +2, ...
                Instant.now()
            );
        }
    }

    @Override
    public List<AccountEvent> readEvents(String streamId) {
        return jdbc.query(
            "SELECT event_type, data FROM account_events " +
            "WHERE stream_id = ? ORDER BY version ASC",
            (rs, rowNum) -> deserialise(rs.getString("event_type"), rs.getString("data")),
            streamId
        );
    }

    @Override
    public List<AccountEvent> readEvents(String streamId, long fromVersion, long toVersion) {
        return jdbc.query(
            "SELECT event_type, data FROM account_events " +
            "WHERE stream_id = ? AND version BETWEEN ? AND ? ORDER BY version ASC",
            (rs, rowNum) -> deserialise(rs.getString("event_type"), rs.getString("data")),
            streamId, fromVersion, toVersion
        );
    }

    private AccountEvent deserialise(String type, String data) {
        try {
            Class<? extends AccountEvent> clazz = switch (type) {
                case "PointsEarned"   -> PointsEarned.class;
                case "PointsRedeemed" -> PointsRedeemed.class;
                case "PointsExpired"  -> PointsExpired.class;
                case "PointsAdjusted" -> PointsAdjusted.class;
                default -> throw new UnknownEventTypeException(type);
            };
            return json.readValue(data, clazz);
        } catch (Exception e) {
            throw new EventDeserializationException(type, e);
        }
    }
}

// ════════════════════════════════════════════════════════════
// STEP 5 — Snapshots (performance optimisation)
//
// Problem: after 10,000 events, replaying all of them on every
// read takes too long (maybe 500ms).
//
// Solution: every 100 events, save a "snapshot" — the current
// state at that point. On the next load, start from the snapshot
// and only replay events after it.
//
// Snapshot every 100 events:
//   Load: read snapshot (version 500) + 27 new events = replay 27, not 527
// ════════════════════════════════════════════════════════════

public record AccountSnapshot(
    String accountId,
    int balance,
    int lifetimeEarned,
    int lifetimeRedeemed,
    long version,           // which version of events this snapshot covers
    Instant takenAt
) {
    // Reconstruct the aggregate from snapshot
    public LoyaltyAccount toAggregate() {
        LoyaltyAccount account = new LoyaltyAccount(accountId);
        account.restoreFromSnapshot(this);
        return account;
    }
}

// ════════════════════════════════════════════════════════════
// STEP 6 — Repository (hides event store from callers)
//
// The application service uses the repository, not the event store directly.
// Repository handles: load (with snapshot), save (with snapshot trigger)
// ════════════════════════════════════════════════════════════

@Repository
public class LoyaltyAccountRepository {

    private final EventStore eventStore;
    private static final int SNAPSHOT_INTERVAL = 100; // snapshot every 100 events

    public LoyaltyAccount load(String accountId) {
        // 1. Try to load a snapshot first
        Optional<AccountSnapshot> snapshot = eventStore.readSnapshot(accountId);

        LoyaltyAccount account;
        long fromVersion;

        if (snapshot.isPresent()) {
            // Snapshot found: reconstruct from snapshot, then apply only newer events
            account = snapshot.get().toAggregate();
            fromVersion = snapshot.get().version() + 1;
        } else {
            // No snapshot: start from scratch (version 0)
            account = new LoyaltyAccount(accountId);
            fromVersion = 0;
        }

        // 2. Replay only events after the snapshot
        List<AccountEvent> events = eventStore.readEvents(accountId, fromVersion, Long.MAX_VALUE);
        for (AccountEvent event : events) {
            account.applyFromHistory(event); // rebuild state
        }

        return account;
    }

    @Transactional
    public void save(LoyaltyAccount account) {
        List<AccountEvent> newEvents = account.getUncommittedEvents();
        if (newEvents.isEmpty()) return; // nothing changed

        // Append new events; expectedVersion = version before the new events
        long versionBeforeSave = account.getVersion() - newEvents.size();
        eventStore.appendEvents(account.getAccountId(), newEvents, versionBeforeSave);
        account.markEventsCommitted();

        // Take a snapshot every SNAPSHOT_INTERVAL events
        if (account.getVersion() % SNAPSHOT_INTERVAL == 0) {
            eventStore.writeSnapshot(AccountSnapshot.of(account));
        }
    }
}

// ════════════════════════════════════════════════════════════
// STEP 7 — Application Service (the entry point for business operations)
// ════════════════════════════════════════════════════════════

@Service
public class LoyaltyAccountService {

    private final LoyaltyAccountRepository repository;
    private final EventBus eventBus; // for publishing to CQRS read side

    public void earnPoints(String accountId, int points, String orderId, String source) {
        LoyaltyAccount account = repository.load(accountId);
        account.earnPoints(points, orderId, source); // business logic + produces event
        repository.save(account);                    // persists the event to event store
        // Publish the event so CQRS read projections can update
        account.getUncommittedEvents().forEach(eventBus::publish);
        // Wait — uncommittedEvents was cleared by save()... use domain events instead
    }

    public void redeemPoints(String accountId, int points, String promoId) {
        LoyaltyAccount account = repository.load(accountId);
        account.redeemPoints(points, promoId);
        repository.save(account);
    }
}

// ════════════════════════════════════════════════════════════
// STEP 8 — Time Travel Queries (the killer feature)
//
// "What was this account's balance on Black Friday?"
// "Show me every change this account had in December"
// These are FREE in event sourcing — no special instrumentation needed.
// ════════════════════════════════════════════════════════════

@Service
public class LoyaltyAuditService {

    private final EventStore eventStore;

    // "What was the balance at this point in time?"
    public int getBalanceAt(String accountId, Instant asOf) {
        // Load ALL events for this account
        List<AccountEvent> allEvents = eventStore.readEvents(accountId);

        // Filter: only events that occurred AT OR BEFORE the requested time
        List<AccountEvent> eventsUpToTime = allEvents.stream()
            .filter(e -> !e.occurredAt().isAfter(asOf))
            .collect(Collectors.toList());

        // Replay those filtered events to get the balance at that point in time
        LoyaltyAccount accountAtTime = LoyaltyAccount.fromHistory(eventsUpToTime);
        return accountAtTime.getBalance();
    }

    // "Show me everything that happened to this account in a date range"
    public List<AccountEvent> getAuditTrail(String accountId, Instant from, Instant to) {
        return eventStore.readEvents(accountId).stream()
            .filter(e -> !e.occurredAt().isBefore(from) && !e.occurredAt().isAfter(to))
            .sorted(Comparator.comparing(e -> switch (e) {
                case PointsEarned pe   -> pe.occurredAt();
                case PointsRedeemed pr -> pr.occurredAt();
                case PointsExpired pe  -> pe.occurredAt();
                case PointsAdjusted pa -> pa.occurredAt();
            }))
            .collect(Collectors.toList());
    }

    // "Why is the balance what it is?" — dispute resolution
    public String explainBalance(String accountId) {
        List<AccountEvent> events = eventStore.readEvents(accountId);
        StringBuilder sb = new StringBuilder("Balance history for " + accountId + ":\n");
        int running = 0;
        for (AccountEvent event : events) {
            switch (event) {
                case PointsEarned e -> {
                    running += e.points();
                    sb.append(String.format("  [%s] Earned  +%d (order: %s) → balance: %d%n",
                        e.occurredAt(), e.points(), e.orderId(), running));
                }
                case PointsRedeemed e -> {
                    running -= e.points();
                    sb.append(String.format("  [%s] Redeemed -%d (promo: %s) → balance: %d%n",
                        e.occurredAt(), e.points(), e.promoId(), running));
                }
                case PointsExpired e -> {
                    running -= e.points();
                    sb.append(String.format("  [%s] Expired  -%d → balance: %d%n",
                        e.occurredAt(), e.points(), running));
                }
                case PointsAdjusted e -> {
                    running += e.delta();
                    sb.append(String.format("  [%s] Adjusted %+d (%s by %s) → balance: %d%n",
                        e.occurredAt(), e.delta(), e.reason(), e.adjustedBy(), running));
                }
            }
        }
        return sb.toString();
    }
}
```

---

## Part 4 — The Full Picture: Event Sourcing + CQRS Together

```
These two patterns are natural partners:

EVENT SOURCING (write side)            CQRS (read side)
─────────────────────────              ────────────────
Event Store (append-only)  ──────────► Projection Handlers update Read Models
  account-USER123:
    PointsEarned{100}          Kafka    BalanceView  → Redis  {balance: 40}
    PointsEarned{50}     ────────────►  HistoryView  → DynamoDB [{+100, date}, ...]
    PointsRedeemed{80}         topic    AuditView    → Elasticsearch [all events]
    PointsExpired{30}

Write path:
  1. Load account → replay events (or from snapshot)
  2. Apply business logic → produce new event
  3. Append event to event store
  4. Publish event to Kafka

Read path:
  5. Kafka consumer receives PointsEarned event
  6. Updates Redis BalanceView: balance += points
  7. Updates DynamoDB HistoryView: appends new row
  8. GET /accounts/USER123/balance → reads from Redis → <5ms
```

---

## Part 5 — Schema Evolution (a Hard Problem)

Events are immutable, but business requirements change. What do you do?

```
Problem: PointsEarned originally had no "source" field.
         After launch, you need to track where points came from.

Old event:  PointsEarned{eventId, accountId, points, orderId, occurredAt}
New event:  PointsEarned{eventId, accountId, points, orderId, source, occurredAt}

Old events in the store don't have "source". If you replay them, source = null.
```

**Solutions:**

```
Option 1 — Upcasting (recommended):
  When you deserialise an old PointsEarned, run it through an "upcaster"
  that fills in the missing field with a sensible default.

  public AccountEvent upcast(String type, JsonNode data) {
      if (type.equals("PointsEarned") && !data.has("source")) {
          // Old event: default source to "purchase" (most common historical reason)
          return new PointsEarned(..., "purchase", ...);
      }
      return deserialise(type, data);
  }

Option 2 — Versioned event types:
  PointsEarned_V1{...}  ← old events stay as V1
  PointsEarned_V2{..., source}  ← new events use V2
  apply() handles both:
    case PointsEarned_V1 e -> { balance += e.points(); /* source unknown */ }
    case PointsEarned_V2 e -> { balance += e.points(); track(e.source()); }

Option 3 — Event migration (expensive, risky):
  Rewrite old events in the store.
  Generally discouraged — events are supposed to be immutable facts.
```

---

## Part 6 — What Event Sourcing Is NOT

**Common misconceptions:**

```
❌ "Event Sourcing = Kafka"
   Kafka is a message broker — it delivers events. Event Sourcing is about
   storing state AS events. You can implement Event Sourcing with PostgreSQL (no Kafka).
   Kafka is often used alongside Event Sourcing to publish events for CQRS,
   but they are separate concepts.

❌ "Event Sourcing = storing logs"
   Application logs are for observability. Event Sourcing events are the
   authoritative source of truth for business state. They have different
   schemas, retention policies, and consumers.

❌ "Event Sourcing means no current state anywhere"
   You WILL have current state in read models (via CQRS). Event Sourcing
   just means you DON'T store current state as the PRIMARY source of truth.

❌ "Every app should use Event Sourcing"
   A CRUD blog doesn't need Event Sourcing. The complexity is only worth it
   when you need audit trails, time-travel queries, or event-driven projections.
```

---

## SOLID Analysis

| Principle | Satisfied? | Why |
|---|---|---|
| Single Responsibility | ✅ | Events = facts; Aggregate = business rules; Event Store = persistence; Projections = read views |
| Open/Closed | ✅ | Add a new event type (`PointsTransferred`) without changing existing apply() cases |
| Liskov Substitution | ✅ | All events substitutable through the `AccountEvent` sealed interface |
| Interface Segregation | ✅ | `EventStore` exposes only the operations callers need |
| Dependency Inversion | ✅ | Repository depends on `EventStore` interface, not a specific DB |

---

## When to Use vs When NOT to Use

| ✅ Use Event Sourcing when... | ❌ Do NOT use when... |
|---|---|
| Full audit trail required (finance, healthcare, legal) | Simple CRUD with no audit requirements |
| "Point-in-time" queries are required | High update frequency (millions/sec per entity) — event store becomes a bottleneck |
| Events feed other systems (CQRS, analytics, other services) | Team is new to the pattern — subtle bugs in apply() are hard to find |
| Business logic is complex with many state transitions | Snapshots are complex due to frequent schema changes |
| Concurrent update conflicts are a real problem | Operational complexity of event store is not justified |

---

## Trade-offs Table

| What You Gain | What You Pay |
|---|---|
| Complete audit trail — every change recorded, forever | Replaying 10K+ events is slow — requires snapshot strategy |
| Time-travel queries — "balance at any past moment" | Schema evolution is hard — old events don't have new fields |
| Optimistic concurrency built-in — version check prevents lost updates | Complex to implement correctly — apply() must be deterministic |
| Events feed CQRS read projections, analytics, other systems | Event store technology choice matters — EventStoreDB, PostgreSQL, Kafka all have trade-offs |
| "What happened?" is always answerable | Eventual consistency between event store and read projections |

---

## The Key FAANG Interview Answer

> "Event Sourcing stores *what happened* (events) rather than *what is* (current state). For a loyalty account, the balance isn't stored — it's computed by replaying `PointsEarned`, `PointsRedeemed`, and `PointsExpired` events.
>
> The killer advantage is **audit trail and time-travel**: 'what was the balance last Tuesday?' is a free query — replay events up to that timestamp. This is impossible with traditional state storage without extra instrumentation.
>
> The main challenge is **snapshot management**: after 10,000 events, replaying all of them on every load is too slow (maybe 2 seconds). Solution: snapshot every 100 events, replay only from the snapshot. The second challenge is **schema evolution**: when you add a field to PointsEarned, old events in the store don't have it. Solution: upcasters that fill in defaults when deserialising old events.
>
> Event Sourcing pairs naturally with CQRS: the events in the event store are published to Kafka, where projection handlers subscribe and build read models (Redis for balance, DynamoDB for history, Elasticsearch for analytics)."

---

## Related Patterns

| Pattern | Relationship |
|---|---|
| [CQRS](25-cqrs.md) | Natural partner — events feed CQRS read projections; ES provides the events, CQRS uses them |
| [Command (GoF)](../behavioral/14-command.md) | ES at scale — commands produce immutable events |
| [Memento (GoF)](../behavioral/17-memento.md) | Both capture state for restoration; Memento = in-memory undo; ES = durable append-only log |
| [Outbox Pattern](28-outbox-pattern.md) | After appending to event store, use Outbox to reliably publish events to Kafka |
| [Saga](26-saga.md) | Saga state can be stored as an event stream; saga steps produce events in the same store |
