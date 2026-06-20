# Spring MVC — Web Layer, Request Lifecycle, and REST APIs

Spring MVC implements the **Model-View-Controller** pattern for HTTP request processing. At FAANG scale it powers REST APIs handling millions of requests per second. Understanding the full request lifecycle — from socket to controller and back — is essential for debugging production issues.

---

## Core Architecture — Request Lifecycle

```
  HTTP Request
       │
       ▼
  ┌─────────────────────────────────────────────────────┐
  │              Servlet Container (Tomcat)              │
  └─────────────────────────┬───────────────────────────┘
                            │
                            ▼
  ┌─────────────────────────────────────────────────────┐
  │               Filter Chain (Servlet API)             │
  │  SecurityFilter → CorsFilter → LoggingFilter → ...  │
  └─────────────────────────┬───────────────────────────┘
                            │
                            ▼
  ┌─────────────────────────────────────────────────────┐
  │              DispatcherServlet (Front Controller)    │
  │                                                      │
  │  1. HandlerMapping → find handler for this URL       │
  │  2. HandlerAdapter → invoke the handler              │
  │     ├── HandlerInterceptor.preHandle()               │
  │     ├── Controller method execution                  │
  │     └── HandlerInterceptor.postHandle()              │
  │  3. ViewResolver → resolve view (or @ResponseBody)   │
  │  4. HandlerInterceptor.afterCompletion()             │
  └─────────────────────────────────────────────────────┘
                            │
                            ▼
  HTTP Response
```

---

## DispatcherServlet Internals

The `DispatcherServlet` is a single `HttpServlet` that delegates to specialized strategy objects:

| Strategy Interface | Default Implementation | Role |
|-------------------|----------------------|------|
| `HandlerMapping` | `RequestMappingHandlerMapping` | Maps URL + method to controller |
| `HandlerAdapter` | `RequestMappingHandlerAdapter` | Invokes the controller method |
| `HandlerExceptionResolver` | `ExceptionHandlerExceptionResolver` | Handles exceptions |
| `ViewResolver` | `ContentNegotiatingViewResolver` | Resolves view by content type |
| `MessageConverter` | `MappingJackson2HttpMessageConverter` | Serializes/deserializes body |

---

## Controller Layer

```java
@RestController  // = @Controller + @ResponseBody on all methods
@RequestMapping("/api/v1/orders")
public class OrderController {

    @GetMapping("/{id}")
    public ResponseEntity<OrderDto> getOrder(
            @PathVariable UUID id,
            @RequestParam(defaultValue = "false") boolean includeItems,
            @RequestHeader("X-Correlation-ID") String correlationId) {

        Order order = orderService.findById(id);
        return ResponseEntity.ok(mapper.toDto(order));
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public OrderDto createOrder(
            @RequestBody @Valid CreateOrderRequest request,
            @AuthenticationPrincipal UserDetails user) {
        return orderService.create(request, user.getUsername());
    }

    @PutMapping("/{id}/cancel")
    public ResponseEntity<Void> cancelOrder(@PathVariable UUID id) {
        orderService.cancel(id);
        return ResponseEntity.noContent().build();
    }
}
```

---

## Validation

```java
// Request DTO
public record CreateOrderRequest(
    @NotBlank String productId,
    @Min(1) @Max(100) int quantity,
    @NotNull @Valid ShippingAddress address
) {}

// Custom validator
@Constraint(validatedBy = ValidCurrencyValidator.class)
@Target(ElementType.FIELD)
@Retention(RetentionPolicy.RUNTIME)
public @interface ValidCurrency {
    String message() default "Invalid currency code";
    Class<?>[] groups() default {};
    Class<? extends Payload>[] payload() default {};
}

// Global validation error handler
@RestControllerAdvice
public class ValidationExceptionHandler {
    @ExceptionHandler(MethodArgumentNotValidException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public ProblemDetail handleValidation(MethodArgumentNotValidException ex) {
        ProblemDetail pd = ProblemDetail.forStatus(HttpStatus.BAD_REQUEST);
        pd.setTitle("Validation Failed");
        pd.setProperty("errors", ex.getBindingResult().getFieldErrors().stream()
            .map(e -> Map.of("field", e.getField(), "message", e.getDefaultMessage()))
            .toList());
        return pd;
    }
}
```

---

## Exception Handling

```java
@RestControllerAdvice  // applies to all @RestController classes
public class GlobalExceptionHandler {

    @ExceptionHandler(OrderNotFoundException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public ProblemDetail handleNotFound(OrderNotFoundException ex) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, ex.getMessage());
    }

    @ExceptionHandler(OptimisticLockingFailureException.class)
    @ResponseStatus(HttpStatus.CONFLICT)
    public ProblemDetail handleConflict(OptimisticLockingFailureException ex) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.CONFLICT, "Concurrent modification — retry");
    }

    @ExceptionHandler(Exception.class)  // catch-all — last resort
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    public ProblemDetail handleGeneric(Exception ex) {
        log.error("Unhandled exception", ex);
        // Never expose internal details to clients
        return ProblemDetail.forStatusAndDetail(HttpStatus.INTERNAL_SERVER_ERROR, "Internal error");
    }
}
```

**`ProblemDetail`** (RFC 7807) is the Spring 6 / Boot 3 standard — use it instead of custom error POJOs.

---

## Filters vs Interceptors

| | Filter (Servlet API) | HandlerInterceptor (Spring MVC) |
|-|---------------------|-------------------------------|
| Level | Servlet container | DispatcherServlet |
| Access to Spring beans | Via manual lookup | Full DI |
| When it runs | Before DispatcherServlet | Inside DispatcherServlet |
| Can short-circuit | Yes (`chain.doFilter` not called) | Yes (return `false` from `preHandle`) |
| Use for | Security, CORS, rate limiting, logging | Business interceptors, auth checks |
| Exception handling | Must handle manually | `@ControllerAdvice` catches |
| Order | `@Order` / `FilterRegistrationBean.setOrder()` | `addInterceptors()` order |

```java
// Filter — runs before DispatcherServlet
@Component
@Order(1)
public class CorrelationIdFilter extends OncePerRequestFilter {
    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res,
                                     FilterChain chain) throws IOException, ServletException {
        String correlationId = Optional.ofNullable(req.getHeader("X-Correlation-ID"))
            .orElse(UUID.randomUUID().toString());
        MDC.put("correlationId", correlationId);
        res.setHeader("X-Correlation-ID", correlationId);
        try {
            chain.doFilter(req, res);
        } finally {
            MDC.clear();
        }
    }
}

// Interceptor — runs inside DispatcherServlet, after handler is resolved
@Component
public class LatencyInterceptor implements HandlerInterceptor {
    @Override
    public boolean preHandle(HttpServletRequest req, HttpServletResponse res, Object handler) {
        req.setAttribute("startTime", System.currentTimeMillis());
        return true;
    }

    @Override
    public void afterCompletion(HttpServletRequest req, HttpServletResponse res,
                                Object handler, Exception ex) {
        long elapsed = System.currentTimeMillis() - (long) req.getAttribute("startTime");
        metrics.recordRequestDuration(elapsed, req.getRequestURI());
    }
}
```

---

## Content Negotiation

Spring MVC picks a `MessageConverter` based on `Accept` header and response type:

```java
@GetMapping(value = "/report", produces = {
    MediaType.APPLICATION_JSON_VALUE,
    MediaType.APPLICATION_XML_VALUE,
    "text/csv"
})
public Report getReport() { ... }
// Content-Type selected based on Accept header from client
```

Built-in converters:
- `MappingJackson2HttpMessageConverter` → JSON
- `Jaxb2RootElementHttpMessageConverter` → XML
- `StringHttpMessageConverter` → plain text
- `ByteArrayHttpMessageConverter` → binary

---

## REST API Best Practices (Principal Level)

```java
// Versioning — prefer URI versioning for public APIs
@RequestMapping("/api/v2/orders")

// Idempotency key for POST (payment, order creation)
@PostMapping
public ResponseEntity<Order> createOrder(
    @RequestHeader("Idempotency-Key") String idempotencyKey,
    @RequestBody @Valid CreateOrderRequest req) {
    return orderService.createIdempotent(idempotencyKey, req);
}

// Pagination — cursor-based for large datasets
@GetMapping
public Page<OrderSummary> listOrders(
    @RequestParam(defaultValue = "0") int page,
    @RequestParam(defaultValue = "20") int size,
    @RequestParam(required = false) String cursor) { ... }

// Partial update with PATCH
@PatchMapping("/{id}")
public Order partialUpdate(@PathVariable UUID id,
                           @RequestBody JsonMergePatch patch) { ... }
```

---

## Async Controllers

For long-running operations — releases the HTTP thread while work continues:

```java
@GetMapping("/report/large")
public DeferredResult<ResponseEntity<Report>> getLargeReport() {
    DeferredResult<ResponseEntity<Report>> result = new DeferredResult<>(30_000L);
    reportService.generateAsync()
        .thenAccept(report -> result.setResult(ResponseEntity.ok(report)))
        .exceptionally(ex -> {
            result.setErrorResult(ex);
            return null;
        });
    return result;
}

// Simpler with CompletableFuture return type
@GetMapping("/async")
public CompletableFuture<List<Order>> getOrdersAsync() {
    return CompletableFuture.supplyAsync(() -> orderService.findAll());
}
```

---

## Design Patterns Used

| Pattern | Where in Spring MVC |
|---------|---------------------|
| **Front Controller** | `DispatcherServlet` — single entry point for all requests |
| **Chain of Responsibility** | Filter chain + interceptor chain — each processes then passes |
| **Strategy** | `HandlerMapping`, `ViewResolver`, `MessageConverter` — pluggable algorithms |
| **Template Method** | `DispatcherServlet.doDispatch()` — defines algorithm, subclasses customize steps |
| **Adapter** | `HandlerAdapter` — adapts diverse handler types (controllers, HttpRequestHandler) to uniform interface |
| **Observer** | `ApplicationEventPublisher` used in request lifecycle events |

---

## Trade-offs

| Trade-off | Spring MVC | Spring WebFlux |
|-----------|-----------|---------------|
| Thread model | One thread per request (blocking) | Event loop, non-blocking |
| Concurrency | Limited by thread pool (default 200) | Thousands of concurrent connections |
| Latency | Low for short requests | Low for high-concurrency |
| Debugging | Simple stack traces | Complex reactive chains |
| Library compat | All blocking libraries work | Must use reactive-compatible libraries |
| Team learning curve | Low | High |

---

## FAANG Interview Callout

1. **"Walk me through a request from HTTP to controller and back."**
   - Socket → Tomcat → Filter chain → `DispatcherServlet` → `HandlerMapping` → `HandlerInterceptor.preHandle` → controller method → body serialized by `MessageConverter` → response → `HandlerInterceptor.afterCompletion`

2. **"What's the difference between `@Controller` and `@RestController`?"**
   - `@RestController` = `@Controller` + `@ResponseBody` on every method
   - `@ResponseBody` tells Spring to write return value to HTTP body via `MessageConverter` instead of resolving a view

3. **"When would you use a Filter vs an Interceptor?"**
   - Filter: cross-cutting at servlet level — security, CORS, rate limiting — runs before DispatcherServlet
   - Interceptor: Spring-aware, can access handler info — logging with controller name, audit trail

4. **"How do you handle exceptions globally in Spring MVC?"**
   - `@RestControllerAdvice` + `@ExceptionHandler` — catches from all controllers
   - `ResponseEntityExceptionHandler` — base class with handlers for standard Spring MVC exceptions

5. **"How does `@Transactional` interact with Spring MVC?"**
   - Service layer is transactional; controller layer is not
   - Transaction begins when controller calls service method, commits when service method returns
   - Never put `@Transactional` on controllers — no reason and breaks the layered model
