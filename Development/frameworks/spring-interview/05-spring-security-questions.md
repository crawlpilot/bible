# Spring Security — Interview Questions

---

## Fundamentals (L3–L4)

**Q1. What is the Spring Security filter chain?**
A chain of servlet filters that process every incoming request before reaching the controller. Each filter either handles the request (authenticates, rejects with 401/403) or passes it to the next filter. `DelegatingFilterProxy` bridges the Servlet container to Spring's `FilterChainProxy`, which routes to the matching `SecurityFilterChain`.

**Q2. What is the difference between authentication and authorization?**
- **Authentication**: verifying identity — "Who are you?" (username + password, JWT, API key)
- **Authorization**: verifying permission — "What can you do?" (roles, permissions, ACLs)
Spring processes authentication first (via `AuthenticationManager`), then authorization (via `FilterSecurityInterceptor` or method security).

**Q3. What does `@PreAuthorize` do?**
Method-level security annotation. Checks the expression before the method runs. Requires `@EnableMethodSecurity` on a config class:
```java
@PreAuthorize("hasRole('ADMIN') or #userId == authentication.name")
public void deleteUser(String userId) { ... }
```
`@PostAuthorize`: checks after method returns (can inspect `returnObject`). `@PreFilter`/`@PostFilter`: filters collections.

**Q4. When should you disable CSRF protection?**
CSRF protection is needed for browser-based apps using cookie/session authentication — a malicious site can make cross-site requests with the victim's session cookie. For stateless REST APIs using JWT/OAuth2 Bearer tokens (not cookies), CSRF is irrelevant — disable it:
```java
http.csrf(AbstractHttpConfigurer::disable)
    .sessionManagement(sm -> sm.sessionCreationPolicy(STATELESS));
```

**Q5. What is `UserDetailsService` and `UserDetails`?**
`UserDetailsService.loadUserByUsername(username)` is the contract Spring calls during form/basic auth to load user data from your store. It returns `UserDetails` containing: username, encoded password, authorities (roles), account status (expired, locked). Spring then calls `PasswordEncoder.matches()` to verify.

---

## Advanced (L5 Senior)

**Q6. How do you secure a REST API with JWT in Spring Security?**
```yaml
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          jwks-uri: https://auth.example.com/.well-known/jwks.json
```
Spring Boot auto-configures `JwtDecoder` and `BearerTokenAuthenticationFilter`. Every request with `Authorization: Bearer <token>` is validated: signature verified against JWK, `exp` checked, claims extracted. Map claims to `GrantedAuthority` via a custom `JwtAuthenticationConverter`.

**Q7. What is the difference between `@MockBean UserDetailsService` and `@WithMockUser` in tests?**
- `@MockBean`: replaces the real `UserDetailsService` with a Mockito mock — need to stub `loadUserByUsername()`
- `@WithMockUser(roles = "ADMIN")`: injects a pre-built `Authentication` into `SecurityContext` — skips authentication entirely, just sets up the authorization context. Simpler for testing authorization rules.

**Q8. How does Spring Security handle concurrent session control?**
```java
http.sessionManagement(sm -> sm
    .maximumSessions(1)
    .maxSessionsPreventsLogin(false)  // false = old session expires; true = new login rejected
    .sessionRegistry(sessionRegistry()));
```
`SessionRegistry` tracks active sessions per user. On new login: if max reached, either expire the oldest session or reject the new login. Requires a distributed session store (Redis) at scale — HTTP sessions are not sticky otherwise.

**Q9. Explain the OAuth2 Authorization Code + PKCE flow.**
1. Client generates `code_verifier` (random string) and `code_challenge` (SHA-256 of verifier)
2. Redirect user to auth server with `code_challenge`
3. User authenticates; auth server returns `authorization_code`
4. Client exchanges `code + code_verifier` for access token
5. Auth server verifies `SHA-256(code_verifier) == code_challenge`

PKCE prevents authorization code interception attacks — even if code is stolen, attacker can't exchange it without the verifier. Required for all public clients (SPAs, mobile).

**Q10. How do you implement role hierarchy in Spring Security?**
```java
@Bean
public RoleHierarchy roleHierarchy() {
    RoleHierarchyImpl hierarchy = new RoleHierarchyImpl();
    hierarchy.setHierarchy("""
        ROLE_ADMIN > ROLE_MANAGER
        ROLE_MANAGER > ROLE_USER
        ROLE_USER > ROLE_GUEST
        """);
    return hierarchy;
}
```
`ROLE_ADMIN` implicitly has all MANAGER, USER, and GUEST permissions. Without this, each role is independent — admin would need to be granted every role explicitly.

---

## Principal Engineer Level

**Q11. How do you design security for a multi-service microservices architecture?**

Three-layer model:
1. **Perimeter** (API Gateway): authenticate external tokens (JWT), rate limit, block known bad actors
2. **Service mesh** (mTLS via Istio/Linkerd): mutual TLS between services — no shared secret, certificate-based identity
3. **Application** (Spring Security per service): authorization (does this service have permission to call this endpoint?); validate service identity from mTLS cert or internal token

Internal token pattern: Gateway validates user JWT → issues a short-lived internal JWT with user claims → downstream services trust this internal token only (signed with internal key, not user-facing key).

**Q12. How do you implement fine-grained authorization (row-level security)?**

Options:
1. **`@PostAuthorize`**: `"returnObject.ownerId == authentication.name"` — loads then checks; wasteful if often denied
2. **`@PreAuthorize` with SpEL**: `"@permissionEvaluator.hasPermission(authentication, #id, 'ORDER', 'READ')"` — calls a Spring bean for complex logic
3. **Spring Security ACL**: object-level permission tables (ACL_OBJECT_IDENTITY, ACL_ENTRY) — flexible but operationally complex
4. **Row-level security in DB**: PostgreSQL RLS policies set per-tenant — enforced at DB level regardless of application bugs

Principal choice: ACL module for complex object permissions; PostgreSQL RLS for tenant isolation where the DB guarantee is stronger than application guarantees.

**Q13. How do you handle security in an async/reactive context?**

Async (Spring MVC with `@Async`):
```java
@Bean
public Executor asyncExecutor() {
    return new DelegatingSecurityContextExecutorService(
        new ThreadPoolTaskExecutor()
    );
}
```
`DelegatingSecurityContextExecutorService` copies `SecurityContext` to async threads.

Reactive (WebFlux):
```java
// Access from reactive chain via context
ReactiveSecurityContextHolder.getContext()
    .map(SecurityContext::getAuthentication)
    .map(auth -> auth.getName());
// Context propagated automatically through Reactor's context API
```

---

## Code Walkthroughs

**Q14. Why does this endpoint return 403 even for an ADMIN user?**
```java
http.authorizeHttpRequests(auth -> auth
    .requestMatchers("/admin/**").hasRole("ADMIN")
    .requestMatchers("/api/**").hasRole("USER")
    .anyRequest().authenticated()
);
// User has authorities: ["ROLE_ADMIN"]
// Calling GET /api/admin/users → 403
```
**Answer**: `/api/admin/users` matches `/api/**` first (Spring evaluates matchers in order). `/api/**` requires `ROLE_USER`, which ADMIN doesn't explicitly have (unless role hierarchy is configured). Fix: reorder — put more specific patterns first, or use role hierarchy so ADMIN > USER.

**Q15. What's wrong with this password encoding?**
```java
@Bean
public PasswordEncoder passwordEncoder() {
    return new MessageDigestPasswordEncoder("SHA-256");  // deprecated
}
```
**Answer**: SHA-256 is fast — attackers can brute-force billions of hashes per second with GPUs. Use `BCryptPasswordEncoder(12)` (slow by design, adaptive cost) or `Argon2PasswordEncoder` (memory-hard). `MessageDigestPasswordEncoder` is deprecated in Spring Security 5.8.

---

## Common Mistakes

| Mistake | Problem | Fix |
|---------|---------|-----|
| Storing JWT in localStorage | XSS can steal token | `httpOnly` cookie or BFF pattern |
| Not setting JWT expiry | Stolen tokens valid forever | Short TTL (15 min access, 7d refresh with rotation) |
| `permitAll()` after `authenticated()` in chain | Wrong order — authenticated() catches first | Always put `permitAll()` matchers before `authenticated()` |
| `anyRequest().denyAll()` not as final rule | Unexpected behavior | Put `anyRequest()` always last |
| Ignoring `@EnableMethodSecurity` | `@PreAuthorize` silently ignored | Required on a `@Configuration` class |
