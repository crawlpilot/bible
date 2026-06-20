# Spring Security — Authentication, Authorization, OAuth2, and JWT

Spring Security is the most complex Spring module. At FAANG scale, it protects APIs handling billions of requests. Getting it wrong exposes user data or creates denial-of-service vulnerabilities. Understanding the filter chain internals is non-negotiable.

---

## Core Architecture — SecurityFilterChain

```
  HTTP Request
       │
       ▼
  DelegatingFilterProxy (Servlet Filter)
       │ delegates to
       ▼
  FilterChainProxy
       │
       ├── SecurityFilterChain[0]  (e.g., /api/admin/**)
       │       ├── SecurityContextPersistenceFilter
       │       ├── UsernamePasswordAuthenticationFilter
       │       ├── BearerTokenAuthenticationFilter (OAuth2/JWT)
       │       ├── ExceptionTranslationFilter
       │       │       └── AuthenticationEntryPoint (401)
       │       │       └── AccessDeniedHandler (403)
       │       └── FilterSecurityInterceptor (authorization)
       │
       └── SecurityFilterChain[1]  (e.g., /public/**)
               └── (permitAll, no auth filters)
```

**Key insight**: There is NO Spring MVC involved until the request passes through all security filters. Security happens at the servlet layer, before `DispatcherServlet`.

---

## SecurityFilterChain Configuration (Spring Security 6)

```java
@Configuration
@EnableWebSecurity
@EnableMethodSecurity  // enables @PreAuthorize, @PostAuthorize
public class SecurityConfig {

    @Bean
    public SecurityFilterChain apiFilterChain(HttpSecurity http) throws Exception {
        http
            .securityMatcher("/api/**")
            .csrf(AbstractHttpConfigurer::disable)     // stateless REST API — no CSRF needed
            .sessionManagement(sm ->
                sm.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/api/health", "/api/docs/**").permitAll()
                .requestMatchers(HttpMethod.GET, "/api/products/**").hasAnyRole("USER", "ADMIN")
                .requestMatchers("/api/admin/**").hasRole("ADMIN")
                .anyRequest().authenticated())
            .oauth2ResourceServer(oauth2 ->
                oauth2.jwt(jwt -> jwt.jwtAuthenticationConverter(jwtAuthConverter())));
        return http.build();
    }

    @Bean
    public SecurityFilterChain publicFilterChain(HttpSecurity http) throws Exception {
        http
            .securityMatcher("/public/**", "/actuator/health")
            .authorizeHttpRequests(auth -> auth.anyRequest().permitAll());
        return http.build();
    }
}
```

---

## Authentication Architecture

```
  Request
    │
    ▼
  AuthenticationFilter
    │ extracts credentials
    ▼
  AuthenticationManager (ProviderManager)
    │ iterates providers
    ├──► DaoAuthenticationProvider
    │        │ loads user
    │        ▼
    │    UserDetailsService.loadUserByUsername()
    │        │ returns UserDetails
    │        ▼
    │    PasswordEncoder.matches()
    │
    ├──► JwtAuthenticationProvider
    ├──► OAuth2LoginAuthenticationProvider
    └──► LdapAuthenticationProvider
    │
    ▼
  Authentication (success) → stored in SecurityContext
  AuthenticationException (failure) → AuthenticationEntryPoint → 401
```

```java
@Service
public class UserDetailsServiceImpl implements UserDetailsService {
    @Override
    public UserDetails loadUserByUsername(String email) {
        User user = userRepository.findByEmail(email)
            .orElseThrow(() -> new UsernameNotFoundException("User not found: " + email));
        return org.springframework.security.core.userdetails.User.builder()
            .username(user.getEmail())
            .password(user.getPasswordHash())  // already BCrypt-encoded
            .roles(user.getRole().name())
            .accountExpired(!user.isActive())
            .build();
    }
}
```

---

## Password Encoding

```java
@Bean
public PasswordEncoder passwordEncoder() {
    // BCrypt: adaptive cost factor, built-in salt — never use MD5, SHA, plain text
    return new BCryptPasswordEncoder(12);  // cost factor 12 = ~300ms on modern hardware
    // Or: Argon2PasswordEncoder — more memory-hard, better against GPU attacks
}

// DelegatingPasswordEncoder — supports multiple encoders for migration
@Bean
public PasswordEncoder passwordEncoder() {
    Map<String, PasswordEncoder> encoders = Map.of(
        "bcrypt", new BCryptPasswordEncoder(12),
        "argon2", new Argon2PasswordEncoder(...)
    );
    return new DelegatingPasswordEncoder("bcrypt", encoders);
    // Stores: {bcrypt}$2a$12$...  → identifies which encoder to use on verify
}
```

---

## JWT (JSON Web Token) — Resource Server

```java
// application.yml
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          jwks-uri: https://auth.example.com/.well-known/jwks.json  // public keys for verification
          issuer-uri: https://auth.example.com

// Custom JWT converter — map claims to Spring Security roles
@Component
public class JwtAuthConverter implements Converter<Jwt, AbstractAuthenticationToken> {
    @Override
    public AbstractAuthenticationToken convert(Jwt jwt) {
        Collection<GrantedAuthority> authorities = extractAuthorities(jwt);
        return new JwtAuthenticationToken(jwt, authorities, jwt.getClaimAsString("sub"));
    }

    private Collection<GrantedAuthority> extractAuthorities(Jwt jwt) {
        List<String> roles = jwt.getClaimAsStringList("roles");
        return roles.stream()
            .map(r -> new SimpleGrantedAuthority("ROLE_" + r.toUpperCase()))
            .collect(toList());
    }
}
```

### JWT Pitfalls

| Pitfall | Impact | Fix |
|---------|--------|-----|
| No expiry validation | Stolen tokens valid forever | Always validate `exp` claim (Spring does this automatically) |
| `none` algorithm accepted | Token forgery | Whitelist allowed algorithms: `RS256`, `ES256` |
| Storing JWT in localStorage | XSS can steal token | Use `httpOnly` cookie or BFF pattern |
| No token rotation | Refresh token abuse | Short-lived access token (15min) + refresh token rotation |
| Large JWT payload | Bandwidth overhead | Keep claims minimal; use opaque tokens if claims are large |

---

## OAuth2 Flows — When to Use Which

```
Client Types:
┌─────────────────────────────────────────────────────────┐
│                                                         │
│  Browser SPA / Mobile   →   Authorization Code + PKCE  │
│                                                         │
│  Server-to-Server       →   Client Credentials          │
│                                                         │
│  Legacy Web (server-    →   Authorization Code          │
│  rendered)                  (with secret)               │
│                                                         │
│  CLI / Device           →   Device Authorization Flow   │
│                                                         │
│  NEVER use Implicit     →   Deprecated (RFC 6749)       │
│  NEVER use Password     →   Deprecated (RFC 6749)       │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## Method Security

```java
@Service
public class OrderService {

    @PreAuthorize("hasRole('ADMIN') or #userId == authentication.name")
    public List<Order> getOrders(String userId) { ... }

    @PostAuthorize("returnObject.ownerId == authentication.name")
    public Order getOrder(UUID id) { ... }  // checks after method returns

    @PreFilter("filterObject.ownerId == authentication.name")
    public List<Order> processOrders(List<Order> orders) { ... }  // filters input list

    @PostFilter("filterObject.ownerId == authentication.name")
    public List<Order> listOrders() { ... }  // filters return list

    @Secured("ROLE_ADMIN")  // simpler but less flexible than @PreAuthorize
    public void deleteOrder(UUID id) { ... }
}
```

---

## CSRF Protection

**When to enable**: Session-based web apps (cookie auth). **When to disable**: Stateless REST APIs using JWT/OAuth2 Bearer tokens — no session means no CSRF vulnerability.

```java
// For stateful web apps — CSRF token sent as hidden form field
http.csrf(csrf -> csrf
    .csrfTokenRepository(CookieCsrfTokenRepository.withHttpOnlyFalse())
    // Cookie is readable by JS — Angular/React read it and send as header
);

// For REST APIs — disable CSRF (stateless, no session)
http.csrf(AbstractHttpConfigurer::disable)
    .sessionManagement(sm -> sm.sessionCreationPolicy(STATELESS));
```

---

## CORS Configuration

```java
@Bean
public CorsConfigurationSource corsConfigurationSource() {
    CorsConfiguration config = new CorsConfiguration();
    config.setAllowedOrigins(List.of("https://app.example.com")); // never "*" in prod
    config.setAllowedMethods(List.of("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"));
    config.setAllowedHeaders(List.of("Authorization", "Content-Type", "X-Correlation-ID"));
    config.setAllowCredentials(true);
    config.setMaxAge(3600L);

    UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
    source.registerCorsConfiguration("/api/**", config);
    return source;
}
```

---

## Security Context Propagation (Async)

```java
// PROBLEM: SecurityContext is ThreadLocal — lost when switching threads
@Async
public void asyncMethod() {
    Authentication auth = SecurityContextHolder.getContext().getAuthentication();
    // auth is NULL — wrong thread
}

// FIX: Use DelegatingSecurityContextExecutor
@Bean
public Executor taskExecutor() {
    ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
    executor.initialize();
    return new DelegatingSecurityContextExecutorService(executor.getThreadPoolExecutor());
}
```

---

## Design Patterns Used

| Pattern | Where in Spring Security |
|---------|--------------------------|
| **Chain of Responsibility** | `SecurityFilterChain` — each filter processes then passes |
| **Strategy** | `AuthenticationProvider`, `PasswordEncoder`, `AccessDecisionManager` |
| **Template Method** | `AbstractAuthenticationProcessingFilter` — defines flow, subclass implements extraction |
| **Decorator** | `DelegatingSecurityContextExecutor` — wraps Executor to propagate context |
| **Proxy** | `DelegatingFilterProxy` — Spring bean proxied into Servlet filter chain |
| **Context Object** | `SecurityContextHolder` — thread-local store for Authentication |

---

## Trade-offs

| Approach | Use When | Trade-off |
|----------|----------|-----------|
| Session-based auth | Server-rendered web app | Sticky sessions or distributed session store needed at scale |
| JWT (stateless) | Microservices, REST APIs | Can't revoke individual tokens; short TTL required |
| OAuth2 Resource Server | Public APIs, third-party access | Token introspection adds latency |
| API Key | Server-to-server, simple auth | No expiry, harder to rotate |
| mTLS | Internal service mesh | High operational complexity |

---

## FAANG Interview Callout

1. **"How does Spring Security filter chain work?"**
   - `DelegatingFilterProxy` bridges Servlet to Spring; `FilterChainProxy` routes to matching `SecurityFilterChain`; each chain is a list of filters evaluated in order

2. **"How do you secure a REST API with JWT?"**
   - `spring-boot-starter-oauth2-resource-server`, configure JWKS URI, implement JWT converter to map claims to authorities, disable session and CSRF

3. **"How do you prevent unauthorized data access within the same role?"**
   - `@PostAuthorize("returnObject.ownerId == authentication.name")` — row-level security
   - Or Spring Security ACL module for fine-grained object permissions

4. **"How do you handle security in an async or reactive context?"**
   - Async: `DelegatingSecurityContextExecutor` propagates context across threads
   - Reactive: `ReactiveSecurityContextHolder` with `Mono.contextWrite`

5. **"What's the difference between authentication and authorization?"**
   - Authentication: who are you? (credentials verified by `AuthenticationManager`)
   - Authorization: what can you do? (enforced by `FilterSecurityInterceptor` or method security)
