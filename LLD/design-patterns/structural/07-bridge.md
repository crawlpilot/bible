# 07. Bridge
**Category**: Structural  
**GoF**: Yes  
**Complexity**: High  
**Frequency in FAANG interviews**: Occasional

> Decouple an abstraction from its implementation so that the two can vary independently.

---

## Problem It Solves

A notification platform sends `OrderShipped`, `PaymentFailed`, and `PromotionAlert` notifications via `Email`, `Push`, and `SMS`. Without Bridge, you need a class for every combination: `OrderShippedEmail`, `OrderShippedPush`, `OrderShippedSMS`, `PaymentFailedEmail`... — 9 classes for 3 types × 3 channels, 18 for 6 types × 3 channels. Bridge decouples the *what* (notification type) from the *how* (delivery channel), so adding a 4th channel (WhatsApp) requires 1 new class, not 6.

## Structure (Participants)

```
   Abstraction (Notification)                Implementation (Channel)
  ┌──────────────────────────┐             ┌────────────────────────┐
  │ # channel: Channel       │────────────►│ «interface» Channel     │
  │ + send(recipient)        │             │ + deliver(msg, contact) │
  └──────────────────────────┘             └────────────────────────┘
              △                                       △
    ┌─────────┴──────────┐             ┌──────────────┼──────────────┐
    │                    │             │              │              │
OrderShippedNotif  PromoAlertNotif  EmailChannel  PushChannel   SMSChannel
PaymentFailedNotif                 (SMTP)        (FCM/APNs)    (Twilio)
```

Key participants:
- **Abstraction** (`Notification`): references the Implementation; defines high-level send logic
- **Refined Abstraction** (`OrderShippedNotification`, etc.): fills in the notification-type-specific content
- **Implementation** (`Channel`): low-level interface for delivering a raw message to a contact
- **Concrete Implementation** (`EmailChannel`, `PushChannel`, `SMSChannel`): channel-specific delivery

---

## Real-World Use Case: Notification Platform (Type × Channel Matrix)

An e-commerce platform sends 8 notification types (OrderPlaced, OrderShipped, Delivered, PaymentFailed, PromotionAlert, AbandonedCart, PriceAlert, ReturnApproved) across 4 channels (Email, Push, SMS, WhatsApp). Without Bridge: 32 classes. With Bridge: 8 notification classes + 4 channel classes = 12.

### Implementation

```java
// Implementation interface — the "how"
public interface NotificationChannel {
    void deliver(NotificationMessage message, ContactInfo contact);
    boolean supportsRichContent();   // emails support HTML; SMS does not
    int maxMessageLength();
}

// Concrete Implementations
public class EmailChannel implements NotificationChannel {
    private final EmailClient smtp;

    public EmailChannel(EmailClient smtp) { this.smtp = smtp; }

    @Override
    public void deliver(NotificationMessage message, ContactInfo contact) {
        Email email = Email.builder()
            .to(contact.email())
            .subject(message.subject())
            .htmlBody(message.richBody())
            .textBody(message.plainBody())
            .build();
        smtp.send(email);
    }

    @Override public boolean supportsRichContent() { return true; }
    @Override public int maxMessageLength() { return 100_000; }
}

public class PushChannel implements NotificationChannel {
    private final FCMClient fcm;
    private final APNsClient apns;

    @Override
    public void deliver(NotificationMessage message, ContactInfo contact) {
        if (contact.isAndroid()) {
            fcm.send(FCMMessage.of(contact.deviceToken(), message.title(), message.body()));
        } else {
            apns.send(APNsPayload.of(contact.deviceToken(), message.title(), message.body()));
        }
    }

    @Override public boolean supportsRichContent() { return false; }
    @Override public int maxMessageLength() { return 256; }
}

public class SMSChannel implements NotificationChannel {
    private final TwilioClient twilio;

    @Override
    public void deliver(NotificationMessage message, ContactInfo contact) {
        String text = message.plainBody().substring(0, Math.min(160, message.plainBody().length()));
        twilio.sendSMS(contact.phoneNumber(), text);
    }

    @Override public boolean supportsRichContent() { return false; }
    @Override public int maxMessageLength() { return 160; }
}

// Abstraction — the "what"
public abstract class Notification {
    protected final NotificationChannel channel;   // bridge to implementation

    protected Notification(NotificationChannel channel) {
        this.channel = channel;
    }

    // Template method — subclasses define content, base class handles delivery
    public final void send(User recipient) {
        NotificationMessage message = buildMessage(recipient);
        if (!channel.supportsRichContent()) {
            message = message.asPlainText();  // downgrade for SMS/Push
        }
        channel.deliver(message, recipient.contactInfo());
    }

    // Subclasses fill in type-specific content
    protected abstract NotificationMessage buildMessage(User recipient);
}

// Refined Abstractions — the notification types
public class OrderShippedNotification extends Notification {
    private final Order order;
    private final ShipmentTracking tracking;

    public OrderShippedNotification(NotificationChannel channel, Order order, ShipmentTracking tracking) {
        super(channel);
        this.order = order;
        this.tracking = tracking;
    }

    @Override
    protected NotificationMessage buildMessage(User recipient) {
        return NotificationMessage.builder()
            .subject("Your order #" + order.id() + " has shipped!")
            .title("Order Shipped")
            .richBody(renderTemplate("order-shipped.html", order, tracking))
            .plainBody("Your order #" + order.id() + " shipped. Track: " + tracking.url())
            .build();
    }
}

public class PaymentFailedNotification extends Notification {
    private final Order order;
    private final String failureReason;

    public PaymentFailedNotification(NotificationChannel channel, Order order, String reason) {
        super(channel);
        this.order = order;
        this.failureReason = reason;
    }

    @Override
    protected NotificationMessage buildMessage(User recipient) {
        return NotificationMessage.builder()
            .subject("Payment failed for order #" + order.id())
            .title("Payment Failed")
            .richBody(renderTemplate("payment-failed.html", order, failureReason))
            .plainBody("Your payment for order #" + order.id() + " failed: " + failureReason)
            .build();
    }
}

public class PromotionAlertNotification extends Notification {
    private final Promotion promo;

    public PromotionAlertNotification(NotificationChannel channel, Promotion promo) {
        super(channel);
        this.promo = promo;
    }

    @Override
    protected NotificationMessage buildMessage(User recipient) {
        return NotificationMessage.builder()
            .subject(promo.headline())
            .title(promo.headline())
            .richBody(renderTemplate("promo.html", promo, recipient))
            .plainBody(promo.shortDescription() + " Use code: " + promo.code())
            .build();
    }
}

// Client — notification dispatcher
public class NotificationDispatcher {
    private final Map<String, NotificationChannel> channels;

    public void dispatch(OrderShippedEvent event, User user) {
        NotificationChannel channel = channels.get(user.preferredChannel());
        new OrderShippedNotification(channel, event.order(), event.tracking()).send(user);
    }

    public void dispatchToAllChannels(PromotionAlertEvent event, User user) {
        // Bridge makes this trivial — same notification, different channels
        for (NotificationChannel ch : user.enabledChannels()) {
            new PromotionAlertNotification(ch, event.promo()).send(user);
        }
    }
}

// Adding WhatsApp — only 1 new class, zero changes to notification types
public class WhatsAppChannel implements NotificationChannel {
    private final WhatsAppBusinessClient client;

    @Override
    public void deliver(NotificationMessage message, ContactInfo contact) {
        client.sendMessage(contact.whatsAppNumber(), message.plainBody());
    }

    @Override public boolean supportsRichContent() { return false; }
    @Override public int maxMessageLength() { return 4096; }
}
```

### How It Works (walkthrough)

1. User's preference: `preferredChannel = "push"`
2. `NotificationDispatcher` fetches `PushChannel`, constructs `OrderShippedNotification(pushChannel, order, tracking)`
3. `notification.send(user)` → calls `buildMessage(user)` → builds rich content
4. `channel.supportsRichContent()` → `false` for Push → `message.asPlainText()` downgrade
5. `channel.deliver(message, user.contactInfo())` → FCM/APNs delivery
6. **Adding WhatsApp**: implement `WhatsAppChannel`, register it — zero changes to `OrderShippedNotification`

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | Notification builds content; Channel delivers it — separate concerns |
| Open/Closed | ✅ | Add new channel or new notification type independently — no existing classes change |
| Liskov Substitution | ✅ | All channels are substitutable; all notifications are substitutable |
| Interface Segregation | ✅ | `NotificationChannel` is focused on delivery; separate from content concerns |
| Dependency Inversion | ✅ | `Notification` depends on `NotificationChannel` interface, not `EmailChannel` |

---

## When to Use

- Two independent dimensions of variation must scale separately (type × channel, format × renderer)
- You want to avoid a class explosion from combining two hierarchies (M types × N channels = M×N classes → Bridge gives M+N)
- You want to switch implementations at runtime (user changes preferred channel)

## When NOT to Use

- There's only one dimension of variation — use simple inheritance or Strategy instead
- The two dimensions are not truly independent — forced separation adds complexity
- The abstractions are unlikely to change — over-engineering for a single notification type

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Eliminates M×N class explosion — M+N classes instead | More complex upfront — two hierarchies to understand |
| Add new types or channels independently (OCP on two axes) | Bridge reference introduces indirection — harder to follow the call chain |
| Runtime channel swapping — user changes preference without object replacement | Over-engineered if only 2×2 combinations exist |

---

**FAANG interview application**: "Bridge separates two orthogonal dimensions — in a notification system, the notification *type* (what to say) and the delivery *channel* (how to say it) are independent. Without Bridge, adding a 4th channel to 8 notification types means 8 new classes. With Bridge, it's 1 new channel class. The bridge is the channel reference inside the notification abstraction — the same notification object can be sent over any channel by changing what's injected at construction time."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Strategy](../behavioral/20-strategy.md) | Strategy changes the algorithm; Bridge changes the implementation hierarchy. Bridge is structural; Strategy is behavioral. |
| [Adapter](06-adapter.md) | Adapter makes incompatible interfaces work together after the fact; Bridge is designed upfront to separate two hierarchies |
| [Abstract Factory](../creational/03-abstract-factory.md) | Abstract Factory can create the correct Bridge implementation for a given context |
