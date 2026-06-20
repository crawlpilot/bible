# Security — Code Review Checklist

> Security issues found in code review cost nothing to fix. Security issues found in production cost careers. Every reviewer is a security reviewer. Items marked `[BLOCK]` must be fixed before merge, no exceptions.

---

## Quick Checklist

```
Input Validation
  ☐ All external inputs validated before use (HTTP params, headers, body, file uploads)
  ☐ Validation happens at the boundary — not deep in business logic
  ☐ Reject-then-sanitise: validate first, then sanitise for output
  ☐ No trusting client-supplied values for security decisions (roles, IDs of other users)

Injection
  ☐ No string concatenation to build SQL queries
  ☐ ORM/prepared statements used for all DB access
  ☐ No dynamic shell command construction from user input
  ☐ Template engines auto-escape output (HTML, XML)
  ☐ No eval() or equivalent with user-supplied data

Authentication & Authorisation
  ☐ Every endpoint has an auth check (no accidentally public endpoints)
  ☐ Authorisation checks that the acting user OWNS the resource (not just is logged in)
  ☐ No auth logic in client-side code
  ☐ Tokens validated for signature + expiry on every request

Secrets & Credentials
  ☐ No hardcoded secrets, passwords, API keys in code
  ☐ No secrets in config files committed to git
  ☐ Secrets loaded from environment variables or a secrets manager (Vault, AWS SSM)
  ☐ No secrets in log output (see logging checklist)

Cryptography
  ☐ No MD5 or SHA-1 for security purposes
  ☐ No custom crypto (use battle-tested libraries)
  ☐ Passwords hashed with bcrypt / argon2 / scrypt (not SHA-256)
  ☐ Encryption keys are not hardcoded

Data Exposure
  ☐ API responses don't include fields the caller isn't authorised to see
  ☐ Error responses don't leak stack traces or internal paths to clients
  ☐ Database error messages are not forwarded to HTTP clients

Dependencies
  ☐ No known CVEs in new or updated dependencies (run dependency scanner in CI)
  ☐ No pinning to a vulnerable version
```

---

## OWASP Top 10 — Review Items

### A01: Broken Access Control

The most common and impactful vulnerability. An authenticated user accessing another user's data.

```java
// [BLOCK] Missing resource-level authorisation
@GetMapping("/orders/{orderId}")
public Order getOrder(@PathVariable String orderId) {
    return orderRepository.findById(orderId)
        .orElseThrow(NotFoundException::new);
    // MISSING: does the authenticated user OWN this order?
}

// CORRECT: always assert ownership
@GetMapping("/orders/{orderId}")
public Order getOrder(@PathVariable String orderId, Authentication auth) {
    Order order = orderRepository.findById(orderId)
        .orElseThrow(NotFoundException::new);
    if (!order.getCustomerId().equals(auth.getCustomerId())) {
        throw new ForbiddenException("Order does not belong to authenticated user");
    }
    return order;
}

// [BLOCK] Trusting client-supplied user ID for data scoping
@GetMapping("/orders")
public List<Order> getOrders(@RequestParam String customerId) {
    // Client sends any customerId — can enumerate other users' orders
    return orderRepository.findByCustomerId(customerId);
}
// CORRECT: always derive user identity from the authenticated token
@GetMapping("/orders")
public List<Order> getOrders(Authentication auth) {
    return orderRepository.findByCustomerId(auth.getCustomerId());
}

// [BLOCK] Privilege escalation via mass assignment
@PutMapping("/users/{id}")
public User updateUser(@PathVariable String id, @RequestBody User user) {
    // If User has a 'role' field, client can elevate their own role
    return userRepository.save(user);
}
// CORRECT: use a DTO that only exposes updateable fields; set role server-side
```

### A02: Cryptographic Failures

```java
// [BLOCK] Weak hash for passwords
String hashed = DigestUtils.md5Hex(password);     // MD5 — not a password hash
String hashed = DigestUtils.sha256Hex(password);  // SHA-256 — not a password hash

// CORRECT: bcrypt (cost factor 12+), argon2id, or scrypt
BCryptPasswordEncoder encoder = new BCryptPasswordEncoder(12);
String hashed = encoder.encode(password);

// [BLOCK] Hardcoded encryption key
private static final String AES_KEY = "0123456789abcdef";  // never hardcode
// CORRECT: load from AWS KMS, HashiCorp Vault, or environment variable

// [BLOCK] ECB mode for symmetric encryption
Cipher cipher = Cipher.getInstance("AES/ECB/PKCS5Padding");
// ECB produces identical ciphertext for identical plaintext blocks — patterns are visible
// CORRECT:
Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");  // authenticated encryption

// [WARN] Generating random tokens with java.util.Random
String token = String.valueOf(new Random().nextLong());  // predictable
// CORRECT:
String token = UUID.randomUUID().toString();             // cryptographically random
// Or:
byte[] bytes = new byte[32];
new SecureRandom().nextBytes(bytes);
String token = Base64.getUrlEncoder().encodeToString(bytes);
```

### A03: Injection

```java
// [BLOCK] SQL injection via string concatenation
String query = "SELECT * FROM orders WHERE customer_id = '" + customerId + "'";
jdbcTemplate.query(query, ...);
// Attacker sends: customerId = "'; DROP TABLE orders; --"

// CORRECT: parameterised query
jdbcTemplate.query(
    "SELECT * FROM orders WHERE customer_id = ?",
    new Object[]{customerId},
    ...
);

// [BLOCK] JPQL injection
String jpql = "FROM Order WHERE customerId = '" + customerId + "'";
em.createQuery(jpql).getResultList();
// CORRECT:
em.createQuery("FROM Order WHERE customerId = :customerId")
  .setParameter("customerId", customerId)
  .getResultList();

// [BLOCK] Shell injection
Runtime.getRuntime().exec("convert " + userFilename);
// Attacker sends: "; rm -rf /"
// CORRECT: use ProcessBuilder with separate args (no shell interpolation)
new ProcessBuilder("convert", userFilename).start();
// Better: validate filename against a whitelist before use

// [BLOCK] Log injection — newlines in log fields can fake log entries
log.info("User action: " + userInput);
// Attacker sends: "login\n2024-01 ERROR fake.log.entry"
// CORRECT: sanitise newlines, or structured logging prevents this inherently
log.info("user.action", kv("action", userInput.replaceAll("[\r\n]", "_")));
```

### A04: Insecure Design

```java
// [BLOCK] Security decision based on user-supplied role
@PostMapping("/admin/delete-user")
public void deleteUser(@RequestParam String role, @PathVariable String userId) {
    if ("admin".equals(role)) {  // role comes from client — trivially spoofed
        userService.delete(userId);
    }
}
// CORRECT: derive role from server-side JWT or session

// [BLOCK] Rate limiting not applied to sensitive operations
@PostMapping("/auth/login")
public TokenResponse login(@RequestBody LoginRequest req) {
    // No rate limit — allows brute-force password attacks
    return authService.login(req);
}
// CORRECT: rate limit by IP and by account on auth endpoints

// [WARN] Predictable resource IDs
Long orderId = orderRepository.count() + 1;  // sequential, enumerable
// CORRECT: use UUID or opaque token as public ID
```

### A05: Security Misconfiguration

```java
// [BLOCK] CORS wildcard on APIs with authentication
@CrossOrigin(origins = "*")  // allows any origin to call authenticated endpoints
// CORRECT: restrict to known origins
@CrossOrigin(origins = {"https://app.example.com", "https://admin.example.com"})

// [BLOCK] Debug endpoints exposed in production
@GetMapping("/debug/env")
public Map<String, String> getEnv() {
    return System.getenv();  // exposes all environment variables including secrets
}
// CORRECT: disable debug endpoints with profile annotation
@Profile("!production")
@GetMapping("/debug/env")

// [WARN] Default credentials not changed
spring.datasource.username=root
spring.datasource.password=root
```

### A07: Identification and Authentication Failures

```java
// [BLOCK] JWT not validated on every request
@GetMapping("/orders")
public List<Order> getOrders(@RequestHeader("X-User-Id") String userId) {
    // Trusts the header — anyone can set any userId
    return orderService.getOrders(userId);
}
// CORRECT: validate JWT signature + expiry; extract userId from verified claims

// [BLOCK] Password reset token not expiring
String resetToken = UUID.randomUUID().toString();
tokenStore.save(resetToken, userId);  // no TTL — token valid forever
// CORRECT: store with TTL (15–60 minutes)
tokenStore.saveWithTtl(resetToken, userId, Duration.ofMinutes(30));

// [WARN] JWT secret too short
String jwtSecret = "secret";    // trivially brute-forced
// CORRECT: use HS256 with 256-bit (32 byte) key, or RS256 with 2048-bit RSA key
```

### A08: Software and Data Integrity Failures

```java
// [BLOCK] Deserialising untrusted data without type restrictions
ObjectInputStream ois = new ObjectInputStream(request.getInputStream());
Object obj = ois.readObject();  // Java deserialization RCE vulnerability
// CORRECT: never deserialise Java objects from external sources
// Use JSON/Protobuf with explicit type mapping instead

// [WARN] Dependency with no version pin
// pom.xml:
<dependency>
    <groupId>org.example</groupId>
    <artifactId>somelib</artifactId>
    <version>LATEST</version>  <!-- unpredictable; supply chain risk -->
</dependency>
// CORRECT: pin to explicit version; use Dependabot for updates
```

### A09: Security Logging and Monitoring Failures

```java
// [BLOCK] No logging of security-sensitive events
public TokenResponse login(String username, String password) {
    boolean success = authService.verify(username, password);
    return success ? generateToken(username) : throw new UnauthorizedException();
    // MISSING: no log of login success or failure — cannot detect brute-force
}
// CORRECT:
if (success) {
    log.info("user.login.success", kv("user_id", userId), kv("ip_region", region));
} else {
    log.warn("user.login.failed", kv("username_hash", hash(username)), kv("ip", ip));
    // Note: hash the username — raw username may be considered PII
}

// [WARN] No audit log for privileged operations
public void deleteUser(String userId) {
    userRepository.delete(userId);
    // MISSING: no audit log of who deleted whom and when
}
// CORRECT:
auditLog.record("user.deleted",
    kv("deleted_user_id", userId),
    kv("acted_by", authenticatedUserId),
    kv("reason", reason)
);
```

---

## Secrets Review — Hard Rules

```
[BLOCK] Any of the following in the diff:
  - Passwords in source code or config files
  - API keys (AWS_SECRET_ACCESS_KEY, STRIPE_SECRET_KEY, etc.)
  - Private keys or certificates (-----BEGIN PRIVATE KEY-----)
  - Database connection strings with embedded credentials
  - OAuth client secrets

Detection: scan the diff for these patterns:
  - password =
  - secret =
  - api_key =
  - -----BEGIN
  - AWS_ACCESS_KEY_ID
  - Any base64 string longer than 40 chars in a config value
```

If secrets are found in a PR, the action is not just to fix the PR — the secret must be rotated immediately, as it may have already been exposed in git history.

---

## Reviewer Severity Summary

| Issue | Severity |
|---|---|
| Missing authorisation check (IDOR) | `[BLOCK]` |
| SQL/JPQL/shell injection | `[BLOCK]` |
| Hardcoded secret or credential | `[BLOCK]` |
| Weak password hashing (MD5, SHA-256) | `[BLOCK]` |
| Java deserialization of untrusted input | `[BLOCK]` |
| JWT not validated | `[BLOCK]` |
| CORS wildcard on authenticated endpoint | `[BLOCK]` |
| Missing auth on endpoint | `[BLOCK]` |
| No rate limit on auth/sensitive endpoints | `[WARN]` |
| No audit log for privileged operation | `[WARN]` |
| No login failure logging (brute-force blind) | `[WARN]` |
| ECB encryption mode | `[WARN]` |
| Predictable/sequential resource IDs | `[WARN]` |
| Debug endpoint not profile-gated | `[WARN]` |
| Dependency with known CVE | `[WARN]` |
| Unpinned dependency version | `[NIT]` |
