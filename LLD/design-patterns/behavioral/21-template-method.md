# 21. Template Method
**Category**: Behavioral  
**GoF**: Yes  
**Complexity**: Low  
**Frequency in FAANG interviews**: Common

> Define the skeleton of an algorithm in an operation, deferring some steps to subclasses. Template Method lets subclasses redefine certain steps of an algorithm without changing the algorithm's structure.

---

## Problem It Solves

Every payment gateway follows the same flow: validate input → check for fraud → authorize with the provider → capture the funds → notify the user → write an audit log. But each step varies by provider: Stripe uses its SDK for auth/capture, PayPal has a two-step redirect flow, crypto payments use a blockchain confirmation wait. Without Template Method, each gateway reimplements the full 6-step flow — duplicating the order, error handling, and audit logic.

## Structure (Participants)

```
         «abstract»
       PaymentProcessor
  ┌────────────────────────────────────────┐
  │ + process(request): Receipt            │ ← template method (final)
  │                                         │
  │   validate() [hook — can override]      │
  │   checkFraud() [hook — can override]    │
  │   authorize()* [abstract — must impl]   │
  │   capture()* [abstract — must impl]     │
  │   notify() [concrete — shared]          │
  │   auditLog() [concrete — shared]        │
  └────────────────────────────────────────┘
                    △
        ┌──────────┼──────────┐
        │          │          │
   Stripe      PayPal    CryptoPayment
   Processor   Processor  Processor
```

Key participants:
- **Abstract Class** (`PaymentProcessor`): defines the template method `process()` — the invariant skeleton
- **Template Method** (`process()`): calls steps in order; `final` — subclasses cannot reorder steps
- **Abstract Operations**: steps that **must** be overridden by each gateway (marked `*`)
- **Hook Operations**: steps with a default implementation that subclasses **may** override
- **Concrete Subclasses**: override only the varying steps

---

## Real-World Use Case: Multi-Gateway Payment Processing

Three payment gateways (Stripe, PayPal, Crypto) all follow the same 6-step process. The abstract class locks in the order and shared logic; each gateway only implements the 2–3 steps that differ.

### Implementation

```java
// Abstract class — template method pattern
public abstract class PaymentProcessor {
    private final FraudDetectionService fraudService;
    private final AuditLogService auditLog;
    private final NotificationService notification;

    protected PaymentProcessor(FraudDetectionService fraud, AuditLogService audit, NotificationService notif) {
        this.fraudService = fraud;
        this.auditLog = audit;
        this.notification = notif;
    }

    // Template method — defines the algorithm skeleton. FINAL: subclasses cannot reorder.
    public final Receipt process(PaymentRequest request) {
        validate(request);              // step 1: validate input
        checkFraud(request);            // step 2: fraud check
        AuthResult auth = authorize(request);    // step 3: provider-specific auth
        CaptureResult capture = capture(request, auth);  // step 4: provider-specific capture
        notifyUser(request, capture);   // step 5: shared notification
        writeAuditLog(request, capture); // step 6: shared audit
        return buildReceipt(request, capture);
    }

    // Hook — default validation; subclasses may add provider-specific checks
    protected void validate(PaymentRequest request) {
        if (request.amount().isNegativeOrZero()) throw new InvalidAmountException();
        if (request.paymentMethod() == null) throw new MissingPaymentMethodException();
    }

    // Hook — uses shared fraud service; subclasses may enrich the fraud context
    protected void checkFraud(PaymentRequest request) {
        FraudCheckResult result = fraudService.check(request);
        if (result.isHighRisk()) throw new FraudDetectedException(result.reason());
    }

    // Abstract steps — must be implemented by each gateway
    protected abstract AuthResult authorize(PaymentRequest request);
    protected abstract CaptureResult capture(PaymentRequest request, AuthResult auth);

    // Concrete steps — shared across all gateways (not overridable without calling super)
    private void notifyUser(PaymentRequest request, CaptureResult capture) {
        notification.sendPaymentConfirmation(request.userId(), capture.amount(), capture.transactionId());
    }

    private void writeAuditLog(PaymentRequest request, CaptureResult capture) {
        auditLog.log(AuditEntry.builder()
            .userId(request.userId()).orderId(request.orderId())
            .amount(capture.amount()).transactionId(capture.transactionId())
            .gateway(getGatewayName()).build());
    }

    protected abstract String getGatewayName();

    private Receipt buildReceipt(PaymentRequest request, CaptureResult capture) {
        return new Receipt(capture.transactionId(), capture.amount(), Instant.now());
    }
}

// Concrete subclass: Stripe
public class StripePaymentProcessor extends PaymentProcessor {
    private final StripeClient stripe;

    public StripePaymentProcessor(StripeClient stripe, FraudDetectionService fraud,
                                   AuditLogService audit, NotificationService notif) {
        super(fraud, audit, notif);
        this.stripe = stripe;
    }

    @Override
    protected void validate(PaymentRequest request) {
        super.validate(request);  // base validation
        // Stripe-specific: card must have CVC if not saved
        if (request.paymentMethod().isNewCard() && !request.paymentMethod().hasCvc()) {
            throw new InvalidCardException("CVC required for new cards");
        }
    }

    @Override
    protected AuthResult authorize(PaymentRequest request) {
        StripePaymentIntent intent = stripe.createPaymentIntent(
            StripeParams.of(request.amount(), request.paymentMethod().stripeToken())
        );
        return AuthResult.of(intent.getId(), intent.getStatus());
    }

    @Override
    protected CaptureResult capture(PaymentRequest request, AuthResult auth) {
        StripePaymentIntent captured = stripe.capturePaymentIntent(auth.authorizationId());
        return CaptureResult.of(captured.getId(), request.amount());
    }

    @Override protected String getGatewayName() { return "STRIPE"; }
}

// Concrete subclass: PayPal (two-step redirect flow)
public class PayPalPaymentProcessor extends PaymentProcessor {
    private final PayPalClient paypal;

    @Override
    protected AuthResult authorize(PaymentRequest request) {
        // PayPal creates an order first; user must approve via redirect
        PayPalOrder order = paypal.createOrder(request.amount().toString(), "USD");
        // Wait for webhook confirmation that user approved
        ApprovalEvent approval = paypal.waitForApproval(order.getId(), Duration.ofMinutes(10));
        if (!approval.isApproved()) throw new PaymentDeclinedException("PayPal order not approved");
        return AuthResult.of(order.getId(), "APPROVED");
    }

    @Override
    protected CaptureResult capture(PaymentRequest request, AuthResult auth) {
        PayPalCapture capture = paypal.captureOrder(auth.authorizationId());
        return CaptureResult.of(capture.getId(), request.amount());
    }

    @Override protected String getGatewayName() { return "PAYPAL"; }
}

// Concrete subclass: Crypto (blockchain confirmation)
public class CryptoPaymentProcessor extends PaymentProcessor {
    private final BlockchainClient blockchain;

    @Override
    protected void checkFraud(PaymentRequest request) {
        // Crypto: no fraud check needed (blockchain self-verifying)
        // Override to skip
    }

    @Override
    protected AuthResult authorize(PaymentRequest request) {
        // Crypto: generate payment address, wait for on-chain tx
        CryptoPaymentAddress address = blockchain.generatePaymentAddress(request.amount());
        blockchain.waitForConfirmation(address, minConfirmations: 3);
        return AuthResult.of(address.txHash(), "CONFIRMED");
    }

    @Override
    protected CaptureResult capture(PaymentRequest request, AuthResult auth) {
        // Crypto: no separate capture step — confirmation = capture
        return CaptureResult.of(auth.authorizationId(), request.amount());
    }

    @Override protected String getGatewayName() { return "CRYPTO"; }
}

// Client
PaymentProcessor stripe = new StripePaymentProcessor(stripeClient, fraud, audit, notif);
Receipt receipt = stripe.process(request);
// Stripe handles step 3 and 4; shared code handles 1, 2, 5, 6
```

### How It Works (walkthrough)

1. `stripe.process(request)` → enters `PaymentProcessor.process()` (final template)
2. Step 1: `validate(request)` → `StripePaymentProcessor.validate()` (calls super + adds CVC check)
3. Step 2: `checkFraud(request)` → `PaymentProcessor.checkFraud()` (shared, not overridden for Stripe)
4. Step 3: `authorize(request)` → `StripePaymentProcessor.authorize()` → creates Stripe PaymentIntent
5. Step 4: `capture(request, auth)` → `StripePaymentProcessor.capture()` → captures the intent
6. Step 5: `notifyUser()` → shared (private, not overridable)
7. Step 6: `writeAuditLog()` → shared (private, not overridable)

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | Each subclass handles gateway-specific auth/capture; template handles the flow |
| Open/Closed | ✅ | Add `ApplePayProcessor` without changing the template or other gateways |
| Liskov Substitution | ✅ | All processors substitutable through `PaymentProcessor` |
| Interface Segregation | ✅ | Subclasses only implement `authorize()`, `capture()` — no unused methods |
| Dependency Inversion | ✅ | Clients depend on `PaymentProcessor` abstraction |

---

## When to Use

- Multiple classes share the same algorithm structure but differ in specific steps
- Duplicated code across subclasses can be factored into a shared template
- You want to control which steps can and cannot be overridden (final template + abstract/hook steps)

## When NOT to Use

- The algorithm steps vary in too many ways — use Strategy (composition over inheritance)
- No shared invariant structure — subclasses need completely different flows
- The template locks in too many steps — subclasses end up calling `super` in complex ways

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Eliminates duplicated flow code — each subclass implements only what varies | Inheritance — harder to test (must subclass or use reflection to test abstract class) |
| Invariant steps cannot be skipped or reordered (final) | Template changes affect all subclasses (fragile base class problem) |
| Easy to add new variations (new payment gateway) | Hard to reuse logic without inheriting — composition (Strategy) often preferred in modern code |

---

**FAANG interview application**: "Template Method is the right pattern when multiple implementations share the same algorithm skeleton but vary in specific steps. For payment processing, the 6-step flow (validate → fraud → authorize → capture → notify → audit) is invariant across all gateways — only authorize and capture are provider-specific. Making the template method `final` ensures no gateway can skip the fraud check or audit log. At FAANG scale, I'd prefer Strategy + composition for new code — Template Method's inheritance is harder to test in isolation."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Strategy](20-strategy.md) | Template Method uses inheritance; Strategy uses composition. Template Method sets the structure in the base class; Strategy delegates the entire algorithm to an injected object. |
| [Factory Method](../creational/02-factory-method.md) | Factory Method is often a hook in a Template Method — subclasses override the factory step |
