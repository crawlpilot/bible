# Spring Messaging — Kafka, AMQP, JMS, and Event-Driven Architecture

Spring Messaging provides a unified abstraction over messaging systems. It makes event-driven architecture accessible through annotations and templates, while hiding broker-specific boilerplate. Understanding the threading model, error handling, and exactly-once semantics is critical at FAANG scale.

---

## Spring Messaging Landscape

```
                    Spring Messaging (core abstractions)
                              │
          ┌───────────────────┼───────────────────┐
          │                   │                   │
   Spring Kafka         Spring AMQP          Spring JMS
   (Apache Kafka)       (RabbitMQ)           (ActiveMQ, IBM MQ)
          │
   Spring Integration  ← Enterprise Integration Patterns
   (EIP: channel, transformer, router, aggregator, splitter)
```

---

## Spring Kafka

### Producer

```java
@Service
public class OrderEventPublisher {

    private final KafkaTemplate<String, OrderEvent> kafkaTemplate;

    public void publishOrderCreated(Order order) {
        OrderEvent event = new OrderEvent(order.getId(), "ORDER_CREATED", Instant.now());
        ListenableFuture<SendResult<String, OrderEvent>> future =
            kafkaTemplate.send("orders.created", order.getId().toString(), event);

        future.addCallback(
            result -> log.info("Published to partition={} offset={}",
                result.getRecordMetadata().partition(),
                result.getRecordMetadata().offset()),
            ex -> log.error("Failed to publish order event", ex)
        );
    }

    // Transactional producer — for exactly-once within Kafka
    @Transactional("kafkaTransactionManager")
    public void publishWithTransaction(Order order) {
        kafkaTemplate.send("orders.created", order.getId().toString(), toEvent(order));
        kafkaTemplate.send("audit.log", order.getId().toString(), toAuditEvent(order));
        // Both sent atomically — either both delivered or neither
    }
}
```

### Consumer

```java
@Component
public class OrderCreatedConsumer {

    @KafkaListener(
        topics = "orders.created",
        groupId = "fulfillment-service",
        containerFactory = "kafkaListenerContainerFactory",
        concurrency = "3"  // 3 consumer threads per instance — max = partition count
    )
    public void handleOrderCreated(
            @Payload OrderEvent event,
            @Header(KafkaHeaders.RECEIVED_PARTITION) int partition,
            @Header(KafkaHeaders.OFFSET) long offset,
            Acknowledgment ack) {

        try {
            fulfillmentService.processOrder(event.getOrderId());
            ack.acknowledge();  // manual commit after successful processing
        } catch (TransientException e) {
            // Don't ack — will be redelivered
            throw e;
        } catch (PermanentException e) {
            // Ack + send to DLT (Dead Letter Topic)
            deadLetterPublisher.publish(event, e);
            ack.acknowledge();
        }
    }

    // Batch consumer — processes multiple records at once
    @KafkaListener(topics = "orders.analytics", containerFactory = "batchFactory")
    public void handleBatch(List<ConsumerRecord<String, OrderEvent>> records) {
        List<OrderEvent> events = records.stream().map(ConsumerRecord::value).toList();
        analyticsService.processBatch(events);
    }
}
```

### Kafka Configuration

```java
@Configuration
public class KafkaConfig {

    @Bean
    public ProducerFactory<String, OrderEvent> producerFactory() {
        Map<String, Object> config = new HashMap<>();
        config.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, "kafka1:9092,kafka2:9092,kafka3:9092");
        config.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class);
        config.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, JsonSerializer.class);
        config.put(ProducerConfig.ACKS_CONFIG, "all");             // all ISR must ack
        config.put(ProducerConfig.RETRIES_CONFIG, 3);
        config.put(ProducerConfig.IDEMPOTENCE_ENABLE, true);        // exactly-once at producer
        config.put(ProducerConfig.COMPRESSION_TYPE_CONFIG, "snappy");
        config.put(ProducerConfig.BATCH_SIZE_CONFIG, 16384);         // 16KB batch
        config.put(ProducerConfig.LINGER_MS_CONFIG, 5);              // wait 5ms to fill batch
        return new DefaultKafkaProducerFactory<>(config);
    }

    @Bean
    public ConsumerFactory<String, OrderEvent> consumerFactory() {
        Map<String, Object> config = new HashMap<>();
        config.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, "kafka1:9092,kafka2:9092");
        config.put(ConsumerConfig.GROUP_ID_CONFIG, "fulfillment-service");
        config.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        config.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, false);   // manual commit
        config.put(ConsumerConfig.MAX_POLL_RECORDS_CONFIG, 100);
        config.put(ConsumerConfig.SESSION_TIMEOUT_MS_CONFIG, 30000);
        return new DefaultKafkaConsumerFactory<>(config, new StringDeserializer(),
            new JsonDeserializer<>(OrderEvent.class));
    }

    @Bean
    public ConcurrentKafkaListenerContainerFactory<String, OrderEvent> kafkaListenerContainerFactory() {
        ConcurrentKafkaListenerContainerFactory<String, OrderEvent> factory =
            new ConcurrentKafkaListenerContainerFactory<>();
        factory.setConsumerFactory(consumerFactory());
        factory.getContainerProperties().setAckMode(ContainerProperties.AckMode.MANUAL);
        factory.setCommonErrorHandler(new DefaultErrorHandler(
            new DeadLetterPublishingRecoverer(kafkaTemplate),
            new FixedBackOff(1000L, 3)));  // retry 3x, 1s apart, then DLT
        return factory;
    }
}
```

---

## Dead Letter Topic (DLT) Pattern

```java
// Spring Kafka's built-in DLT support
@RetryableTopic(
    attempts = "3",
    backoff = @Backoff(delay = 1000, multiplier = 2),
    dltStrategy = DltStrategy.FAIL_ON_ERROR,
    topicSuffixingStrategy = TopicSuffixingStrategy.SUFFIX_WITH_INDEX_VALUE
)
@KafkaListener(topics = "orders.created")
public void handleOrder(OrderEvent event) {
    // Retries on: orders.created-retry-0, orders.created-retry-1, orders.created-retry-2
    // Dead letters to: orders.created-dlt
    fulfillmentService.process(event);
}

@DltHandler
public void handleDlt(OrderEvent event, @Header(KafkaHeaders.RECEIVED_TOPIC) String topic) {
    log.error("Message in DLT from topic {}: {}", topic, event);
    alertService.sendAlert("Dead letter: " + event.getOrderId());
}
```

---

## Spring AMQP (RabbitMQ)

```java
@Configuration
public class RabbitConfig {

    @Bean
    public TopicExchange ordersExchange() {
        return new TopicExchange("orders.exchange", true, false);
    }

    @Bean
    public Queue fulfillmentQueue() {
        return QueueBuilder.durable("orders.fulfillment")
            .withArgument("x-dead-letter-exchange", "orders.dlx")
            .withArgument("x-dead-letter-routing-key", "orders.dead")
            .withArgument("x-message-ttl", 60000)  // 1 min TTL
            .build();
    }

    @Bean
    public Binding fulfillmentBinding(Queue fulfillmentQueue, TopicExchange ordersExchange) {
        return BindingBuilder.bind(fulfillmentQueue)
            .to(ordersExchange)
            .with("orders.created.#");  // wildcard routing
    }
}

@Service
public class RabbitOrderPublisher {
    @Autowired
    private RabbitTemplate rabbitTemplate;

    public void publishOrder(Order order) {
        rabbitTemplate.convertAndSend("orders.exchange", "orders.created.us-east",
            order,
            message -> {
                message.getMessageProperties().setContentType("application/json");
                message.getMessageProperties().setCorrelationId(order.getId().toString());
                message.getMessageProperties().setExpiration("30000");
                return message;
            });
    }
}

@Component
public class RabbitOrderConsumer {
    @RabbitListener(queues = "orders.fulfillment", concurrency = "2-8")
    public void handleOrder(Order order, Channel channel, @Header(AmqpHeaders.DELIVERY_TAG) long tag)
            throws IOException {
        try {
            fulfillmentService.process(order);
            channel.basicAck(tag, false);
        } catch (Exception e) {
            channel.basicNack(tag, false, false);  // false = don't requeue → goes to DLX
        }
    }
}
```

### RabbitMQ Exchange Types

| Exchange | Routing Logic | Use Case |
|----------|--------------|----------|
| **Direct** | Exact routing key match | Point-to-point (RPC) |
| **Topic** | Wildcard routing key (`*` = one word, `#` = zero or more) | Pub/sub by category |
| **Fanout** | Broadcasts to all bound queues (ignores routing key) | Broadcast to all consumers |
| **Headers** | Match on message headers | Complex routing by attributes |

---

## Spring Integration — Enterprise Integration Patterns

```java
@Configuration
@EnableIntegration
public class OrderIntegrationConfig {

    // Channel — message pipeline
    @Bean
    public MessageChannel orderInputChannel() {
        return new DirectChannel();
    }

    @Bean
    public MessageChannel processedOrderChannel() {
        return new QueueChannel(100);  // buffered
    }

    // Transformer — enriches message
    @Bean
    @Transformer(inputChannel = "orderInputChannel", outputChannel = "validatedOrderChannel")
    public MessageTransformingHandler orderEnricher() {
        return new MessageTransformingHandler(message -> {
            Order order = (Order) message.getPayload();
            order.setEnrichedAt(Instant.now());
            return order;
        });
    }

    // Router — conditional routing
    @Bean
    @Router(inputChannel = "validatedOrderChannel")
    public AbstractMessageRouter orderRouter() {
        return new AbstractMessageRouter() {
            @Override
            protected Collection<MessageChannel> determineTargetChannels(Message<?> message) {
                Order order = (Order) message.getPayload();
                return List.of(order.isExpedited()
                    ? channelResolver.resolveDestination("expeditedChannel")
                    : channelResolver.resolveDestination("standardChannel"));
            }
        };
    }

    // Aggregator — collect related messages
    @Bean
    @ServiceActivator(inputChannel = "orderPartsChannel")
    public MessageHandler aggregator() {
        AggregatingMessageHandler handler = new AggregatingMessageHandler(
            new DefaultAggregatingMessageGroupProcessor());
        handler.setCorrelationStrategy(message ->
            ((OrderPart) message.getPayload()).getOrderId());
        handler.setReleaseStrategy(new SimpleSequenceSizeReleaseStrategy());
        handler.setOutputChannel(assembledOrderChannel());
        return handler;
    }
}
```

---

## Design Patterns Used

| Pattern | Where in Spring Messaging |
|---------|--------------------------|
| **Publish-Subscribe** | Kafka topics, AMQP fanout exchange |
| **Message Channel** | Spring Integration — typed conduit for message passing |
| **Message Router** | Spring Integration — conditional dispatch |
| **Aggregator** | Spring Integration — collect and combine related messages |
| **Splitter** | Spring Integration — split one message into many |
| **Transformer** | Spring Integration — enrich or convert message payload |
| **Competing Consumer** | Kafka consumer group, RabbitMQ queue consumers |
| **Dead Letter Channel** | Kafka DLT, RabbitMQ DLX — isolate poison messages |

---

## Kafka vs RabbitMQ — Decision Table

| Dimension | Kafka | RabbitMQ |
|-----------|-------|----------|
| **Retention** | Days/weeks (replay supported) | Messages deleted after ack |
| **Throughput** | Millions/sec | Hundreds of thousands/sec |
| **Ordering** | Per-partition guaranteed | Per-queue guaranteed |
| **Consumer model** | Pull (consumer controls pace) | Push (broker pushes) |
| **Routing** | Topic + partition | Exchange routing (complex) |
| **Use case** | Event sourcing, log aggregation, stream processing | Task queues, RPC, complex routing |
| **At-least-once** | Yes (default) | Yes |
| **Exactly-once** | Yes (transactions + idempotent producer) | No |

---

## FAANG Interview Callout

1. **"How do you ensure exactly-once delivery in Kafka?"**
   - Producer: `enable.idempotence=true` + `transactional.id`
   - Consumer: `isolation.level=read_committed` + transactional consumer
   - In Spring: `@Transactional("kafkaTransactionManager")` on producer method

2. **"What happens when a Kafka consumer crashes mid-processing?"**
   - With manual ack + not committed: message redelivered to another consumer
   - With auto-commit: message may be lost (committed before processing)
   - Rule: **always use manual commit** (`AckMode.MANUAL`) in production

3. **"How do you handle poison pill messages?"**
   - Dead Letter Topic: configure `DefaultErrorHandler` with `DeadLetterPublishingRecoverer`
   - Or `@RetryableTopic` for automatic retry → DLT progression
   - Monitor DLT and alert; route to human review or replay pipeline

4. **"How do you scale Kafka consumers?"**
   - Max parallelism = partition count — design topic partition count for expected scale
   - `concurrency = "N"` in `@KafkaListener` — N threads per instance
   - Scale instances — rebalancing assigns partitions across all consumer group members

5. **"Kafka vs RabbitMQ — when do you choose each?"**
   - Kafka: event sourcing, audit log, stream processing, replay capability, high throughput
   - RabbitMQ: task queues, complex routing, RPC, when reply-to pattern is needed, short retention
