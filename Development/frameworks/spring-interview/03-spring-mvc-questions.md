# Spring MVC — Interview Questions

---

## Fundamentals (L3–L4)

**Q1. What is the role of `DispatcherServlet`?**
`DispatcherServlet` is the Front Controller for Spring MVC. It receives all HTTP requests and delegates to specialized strategy beans: `HandlerMapping` (find controller), `HandlerAdapter` (invoke it), `ViewResolver` (render response). It is a standard Servlet registered with the Servlet container (Tomcat).

**Q2. What is the difference between `@Controller` and `@RestController`?**
`@RestController` = `@Controller` + `@ResponseBody` applied to every method. `@ResponseBody` tells Spring to write the return value directly to the HTTP response body (via `MessageConverter`) instead of resolving a view name. Use `@Controller` when you return view names (Thymeleaf/JSP); use `@RestController` for REST APIs.

**Q3. What does `@RequestMapping` do, and what are its shortcut annotations?**
`@RequestMapping` maps a URL pattern + HTTP method to a controller method. Shortcuts: `@GetMapping`, `@PostMapping`, `@PutMapping`, `@PatchMapping`, `@DeleteMapping`. The shortcuts make code more readable and explicit.

**Q4. How do you bind path variables, query params, headers, and request body?**
```java
@GetMapping("/orders/{id}")
public Order getOrder(
    @PathVariable UUID id,                            // /orders/123
    @RequestParam(defaultValue = "false") boolean v2, // ?v2=true
    @RequestHeader("X-Tenant-ID") String tenantId,    // header
    @RequestBody CreateOrderRequest body              // JSON body
) { }
```

**Q5. How do you return different HTTP status codes?**
- `@ResponseStatus(HttpStatus.CREATED)` on the method
- Return `ResponseEntity<T>` and set status: `ResponseEntity.status(201).body(result)`
- Throw exception annotated with `@ResponseStatus`

---

## Advanced (L5 Senior)

**Q6. Walk through the full request lifecycle in Spring MVC.**
1. Browser → HTTP request → Tomcat → `DelegatingFilterProxy` → Servlet filters
2. `DispatcherServlet` receives request
3. `HandlerMapping.getHandler()` → finds matching controller method + interceptors
4. `HandlerInterceptor.preHandle()` for each interceptor (return false = stop)
5. `HandlerAdapter.handle()` → argument resolvers bind params → controller method invoked
6. Return value processed: `@ResponseBody` → `MessageConverter` serializes to JSON
7. `HandlerInterceptor.postHandle()` (after controller, before response commit)
8. `HandlerInterceptor.afterCompletion()` (always — cleanup)
9. Response written → TCP socket → client

**Q7. What is the difference between Filter and HandlerInterceptor?**

| | Filter | HandlerInterceptor |
|-|--------|--------------------|
| Level | Servlet API (before DispatcherServlet) | Spring MVC (inside DispatcherServlet) |
| Spring awareness | No (manual context lookup) | Yes (full DI) |
| Access to handler | No | Yes (`Object handler` param) |
| Exception handling | Manual | Handled by `@ControllerAdvice` |
| Use for | Security, CORS, logging, rate limiting | Audit with controller info, locale, auth checks |
| Short-circuit | `chain.doFilter()` not called | Return `false` from `preHandle()` |

**Q8. How does content negotiation work in Spring MVC?**
`ContentNegotiatingViewResolver` selects the response format based on the `Accept` header (or `?format=json` if configured). Spring picks the appropriate `HttpMessageConverter`: Jackson for `application/json`, JAXB for `application/xml`. You control what's produced: `@GetMapping(produces = {APPLICATION_JSON_VALUE, APPLICATION_XML_VALUE})`.

**Q9. How do you handle validation errors globally?**
```java
@RestControllerAdvice
public class GlobalExceptionHandler extends ResponseEntityExceptionHandler {

    @ExceptionHandler(MethodArgumentNotValidException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public ProblemDetail handleValidation(MethodArgumentNotValidException ex) {
        ProblemDetail pd = ProblemDetail.forStatus(HttpStatus.BAD_REQUEST);
        pd.setProperty("errors", ex.getBindingResult().getFieldErrors().stream()
            .map(e -> e.getField() + ": " + e.getDefaultMessage()).toList());
        return pd;
    }
}
```
`ResponseEntityExceptionHandler` already handles Spring MVC's standard exceptions. Extend it and override for custom behavior.

**Q10. What is `@ControllerAdvice` vs `@RestControllerAdvice`?**
`@RestControllerAdvice` = `@ControllerAdvice` + `@ResponseBody`. Both intercept exceptions from controllers; the difference is whether the exception handler return value is written to the response body (REST) or resolved as a view name (MVC).

---

## Principal Engineer Level

**Q11. How would you design rate limiting in Spring MVC at 100M requests/day?**
- **Layer 1 — API Gateway**: Nginx/AWS API Gateway with token bucket per client IP or API key — cheapest, before Spring
- **Layer 2 — Spring Filter**: `OncePerRequestFilter` with Redis-backed rate limiter (`RateLimiter` in Resilience4j or Bucket4j):
  ```java
  @Component
  public class RateLimitFilter extends OncePerRequestFilter {
      private final RateLimiter rateLimiter;  // Bucket4j with Redis backend
      @Override
      protected void doFilterInternal(HttpServletRequest req, ...) {
          String key = apiKeyResolver.resolve(req);  // per API key, not per IP
          if (!rateLimiter.tryAcquire(key)) {
              response.setStatus(429);
              response.setHeader("Retry-After", "1");
              return;
          }
          chain.doFilter(req, response);
      }
  }
  ```
- Return `429 Too Many Requests` with `Retry-After` header

**Q12. How do you design a multi-tenant REST API in Spring MVC?**
- Tenant resolution: HTTP header (`X-Tenant-ID`), subdomain, JWT claim, or path prefix
- `TenantContext` (ThreadLocal) populated in a filter before any service code runs
- Data isolation: per-tenant database schema (Hibernate multi-tenancy) or discriminator column
- Config isolation: tenant-aware `@ConfigurationProperties` or Config Server
- Security: verify authenticated user belongs to the claimed tenant (prevent cross-tenant access)

**Q13. How do you implement idempotent POST endpoints?**
POST creates resources — retries without idempotency double-create. Solution:
```java
@PostMapping("/orders")
public ResponseEntity<Order> createOrder(
        @RequestHeader("Idempotency-Key") String idempotencyKey,
        @RequestBody @Valid CreateOrderRequest req) {

    return idempotencyStore.get(idempotencyKey)
        .map(cached -> ResponseEntity.ok(cached))  // return cached result
        .orElseGet(() -> {
            Order order = orderService.create(req);
            idempotencyStore.put(idempotencyKey, order, Duration.ofHours(24));
            return ResponseEntity.status(201).body(order);
        });
}
```
`idempotencyStore` backed by Redis with TTL. Key = client-generated UUID; server stores result for 24h.

---

## Code Walkthroughs

**Q14. What is wrong with this exception handler?**
```java
@ExceptionHandler(Exception.class)
public String handleGeneric(Exception ex) {
    return ex.getMessage();  // returns a String
}
// This method is in a @Controller class (not @RestControllerAdvice)
```
**Answer**: Two problems. (1) It's only scoped to this single controller — use `@RestControllerAdvice` for global handling. (2) It returns a `String` — in a `@Controller`, Spring interprets this as a view name and tries to resolve it as a template (returning the exception message as a Thymeleaf path). Use `ResponseEntity<>` or add `@ResponseBody`.

**Q15. Why does this filter not apply to actuator endpoints?**
```java
@Component
@Order(1)
public class AuditFilter extends OncePerRequestFilter {
    @Override
    protected boolean shouldNotFilter(HttpServletRequest req) {
        return req.getRequestURI().startsWith("/actuator");  // explicitly skipped
    }
}
```
**Answer**: This is correct behavior. `shouldNotFilter()` returning true skips the filter for actuator. If this is unintended, remove or invert the condition. Actuator endpoints on a separate management port (`management.server.port`) have entirely separate Servlet context — filters registered on the main port don't reach them at all.

---

## Common Mistakes

| Mistake | Problem | Fix |
|---------|---------|-----|
| `@Transactional` on controller method | No use; transaction scope wrong | Only on service/repository layer |
| Catching and swallowing exceptions in controller | Client gets 200 with empty body | Let `@ControllerAdvice` handle; never swallow |
| Returning `null` from `@GetMapping` | `NullPointerException` or empty 200 | Return `ResponseEntity.notFound().build()` or throw exception |
| Not setting `produces` on endpoints | Unexpected content negotiation | Always specify `produces` on APIs with specific contract |
| Using `HttpSession` in stateless REST API | Breaks horizontal scaling | Use JWT; don't rely on session state |
