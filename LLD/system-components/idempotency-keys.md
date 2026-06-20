# System Component: Idempotency Keys

**Category**: LLD · System Components · API Design  
**Pattern**: Idempotent API, Exactly-Once Semantics  
**Real-world implementations**: Stripe API, Twilio, PayPal, AWS SQS FIFO, Temporal

---

## Problem Statement

In distributed systems, network failures cause retries. Without idempotency, a retry of a failed payment request might charge the customer twice. Idempotency keys allow clients to safely retry requests: if the server has already processed a request with a given key, it returns the cached result instead of re-executing.

**Failure scenarios requiring idempotency:**
1. Client sends request, network fails before response arrives → client doesn't know if server processed it
2. Server processed request but crashed before responding → client retries
3. Client times out waiting for response → client retries

In all cases, the retry should produce the same result as the original, not execute the operation twice.

---

## Interface Contract

```python
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Any, Optional
from enum import Enum

class IdempotencyStatus(Enum):
    PENDING    = "PENDING"    # request is being processed
    COMPLETED  = "COMPLETED"  # request completed, result stored
    FAILED     = "FAILED"     # request failed permanently

@dataclass
class IdempotencyRecord:
    key: str
    status: IdempotencyStatus
    request_hash: str          # hash of request body; detect different payloads with same key
    response: Optional[Any]    # cached response (None while PENDING)
    error: Optional[str]       # stored error (if FAILED)
    created_at: float
    completed_at: Optional[float]
    ttl_s: int                 # how long to retain this record

class IdempotencyStore(ABC):
    @abstractmethod
    def get(self, key: str) -> Optional[IdempotencyRecord]:
        """Retrieve an existing idempotency record."""
        pass

    @abstractmethod
    def create(self, record: IdempotencyRecord) -> bool:
        """
        Atomically create the record if no record with this key exists.
        Returns True if created, False if already existed.
        This must be atomic (use Redis SET NX or DB upsert with conflict handling).
        """
        pass

    @abstractmethod
    def complete(self, key: str, response: Any) -> bool:
        """Mark the record as COMPLETED with the given response."""
        pass

    @abstractmethod
    def fail(self, key: str, error: str) -> bool:
        """Mark the record as FAILED with the given error message."""
        pass
```

---

## Implementation

### In-Memory Store (testing / single-node)

```python
import threading
import time
import hashlib
import json

class InMemoryIdempotencyStore(IdempotencyStore):
    def __init__(self):
        self._store: dict[str, IdempotencyRecord] = {}
        self._lock = threading.Lock()

    def get(self, key: str) -> Optional[IdempotencyRecord]:
        with self._lock:
            return self._store.get(key)

    def create(self, record: IdempotencyRecord) -> bool:
        with self._lock:
            if record.key in self._store:
                return False   # already exists
            self._store[record.key] = record
            return True

    def complete(self, key: str, response: Any) -> bool:
        with self._lock:
            rec = self._store.get(key)
            if rec is None:
                return False
            rec.status = IdempotencyStatus.COMPLETED
            rec.response = response
            rec.completed_at = time.monotonic()
            return True

    def fail(self, key: str, error: str) -> bool:
        with self._lock:
            rec = self._store.get(key)
            if rec is None:
                return False
            rec.status = IdempotencyStatus.FAILED
            rec.error = error
            rec.completed_at = time.monotonic()
            return True
```

### Redis-Backed Store (production, distributed)

```python
# Pseudocode — requires redis-py in practice

class RedisIdempotencyStore(IdempotencyStore):
    def __init__(self, redis_client, key_prefix="idempotency"):
        self._redis = redis_client
        self._prefix = key_prefix

    def _redis_key(self, key: str) -> str:
        return f"{self._prefix}:{key}"

    def get(self, key: str) -> Optional[IdempotencyRecord]:
        data = self._redis.get(self._redis_key(key))
        if data is None:
            return None
        return self._deserialize(data)

    def create(self, record: IdempotencyRecord) -> bool:
        """
        Atomic SET NX (set if not exists) with TTL.
        Returns True if key was newly set, False if already existed.
        """
        serialized = self._serialize(record)
        result = self._redis.set(
            self._redis_key(record.key),
            serialized,
            nx=True,              # only set if key doesn't exist
            ex=record.ttl_s       # auto-expire after TTL
        )
        return result is not None   # None means key already existed

    def complete(self, key: str, response: Any) -> bool:
        """
        Use a Lua script for atomic read-modify-write:
        """
        lua_script = """
        local data = redis.call('GET', KEYS[1])
        if not data then return 0 end
        local rec = cjson.decode(data)
        rec.status = 'COMPLETED'
        rec.response = cjson.decode(ARGV[1])
        rec.completed_at = tonumber(ARGV[2])
        local ttl = redis.call('TTL', KEYS[1])
        redis.call('SET', KEYS[1], cjson.encode(rec), 'EX', ttl)
        return 1
        """
        result = self._redis.eval(
            lua_script, 1,
            self._redis_key(key),
            json.dumps(response),
            str(time.time())
        )
        return result == 1
```

---

## Idempotency Middleware

The middleware wraps any handler and applies idempotency semantics:

```python
class IdempotencyMiddleware:
    """
    Wraps an API handler with idempotency semantics.

    Flow:
        1. Extract idempotency key from request header
        2. If no key: pass through (non-idempotent endpoint)
        3. Compute request hash (detect key reuse with different payload)
        4. Look up key in store
           a. Not found → create PENDING record → execute handler → store result
           b. PENDING   → return 409 (request in flight) or wait/poll
           c. COMPLETED → return cached response immediately
           d. FAILED    → return cached error (client should not retry)
    """

    def __init__(self, store: IdempotencyStore, ttl_s: int = 86400):
        self._store = store
        self._ttl = ttl_s

    def _request_hash(self, body: Any, endpoint: str) -> str:
        payload = json.dumps({"endpoint": endpoint, "body": body}, sort_keys=True)
        return hashlib.sha256(payload.encode()).hexdigest()[:16]

    def handle(self, idempotency_key: Optional[str], endpoint: str,
               body: Any, handler) -> dict:
        """
        Execute handler with idempotency protection.
        Returns: {"status": int, "body": Any}
        """
        if not idempotency_key:
            # No idempotency key → execute directly
            return handler(body)

        req_hash = self._request_hash(body, endpoint)

        # Check existing record
        existing = self._store.get(idempotency_key)
        if existing:
            if existing.request_hash != req_hash:
                # Same key, different payload → bad request
                return {"status": 422,
                        "body": {"error": "Idempotency key reused with different request"}}
            if existing.status == IdempotencyStatus.COMPLETED:
                return {"status": 200, "body": existing.response}
            if existing.status == IdempotencyStatus.FAILED:
                return {"status": 400, "body": {"error": existing.error}}
            if existing.status == IdempotencyStatus.PENDING:
                return {"status": 409,
                        "body": {"error": "Request already in flight with this key"}}

        # Create PENDING record atomically
        record = IdempotencyRecord(
            key=idempotency_key,
            status=IdempotencyStatus.PENDING,
            request_hash=req_hash,
            response=None,
            error=None,
            created_at=time.monotonic(),
            completed_at=None,
            ttl_s=self._ttl,
        )
        created = self._store.create(record)
        if not created:
            # Race condition: another process created the record between our get and create
            existing = self._store.get(idempotency_key)
            if existing and existing.status == IdempotencyStatus.COMPLETED:
                return {"status": 200, "body": existing.response}
            return {"status": 409, "body": {"error": "Concurrent request with same key"}}

        # Execute the handler
        try:
            result = handler(body)
            self._store.complete(idempotency_key, result)
            return {"status": 200, "body": result}
        except Exception as e:
            error_msg = str(e)
            self._store.fail(idempotency_key, error_msg)
            return {"status": 500, "body": {"error": error_msg}}
```

---

## Idempotency Key Design Guidelines

### Client-Generated Keys (Stripe's approach)
```
POST /v1/charges
Idempotency-Key: a4e8f2c1-9b3d-4a72-88f0-d1e2c3f4a5b6

Requirement: UUID v4 (random, not predictable)
Scope:       Per user + per operation (not global)
TTL:         24 hours (Stripe's standard)
Retry:       Client retries with the SAME key → idempotent
```

**Why client-generated?** The client is the one who knows whether they're retrying. Server-generated keys would require a two-phase protocol (get key, then use key) which has its own atomicity problems.

### Key Scoping
- Scope the key to the requesting party: `user_id:operation:UUID`
- Prevents one user's key from colliding with another user's
- Makes abuse (intentional key reuse) containable

---

## Production Considerations

### TTL Selection
- Too short: legitimate retries (minutes/hours later) get treated as new requests
- Too long: database bloat; Stripe uses 24 hours
- Recommendation: match the use case's retry window. For payments: 24 hours. For order placement: 24 hours. For notifications: 1 hour.

### At-Least-Once vs Exactly-Once
- Idempotency keys give **effectively-once** semantics: the operation executes at most once, and the client can retry until they get the result
- True exactly-once requires both idempotency at the API layer AND idempotent downstream operations (database upserts, not inserts)

### Database-Level Idempotency
Even with idempotency middleware, the database operation must be idempotent:
```sql
-- Bad: INSERT will fail on retry (duplicate primary key)
INSERT INTO payments (id, amount, user_id) VALUES (?, ?, ?);

-- Good: INSERT OR IGNORE / INSERT ... ON CONFLICT DO NOTHING
INSERT INTO payments (id, amount, user_id)
VALUES (?, ?, ?)
ON CONFLICT (id) DO NOTHING;

-- For "upsert" semantics:
INSERT INTO payments (id, amount, user_id, status)
VALUES (?, ?, ?, 'pending')
ON CONFLICT (id) DO UPDATE SET status = EXCLUDED.status
WHERE payments.status = 'pending';
```

---

## FAANG Interview Callouts

**Where idempotency keys come up:**
- Payment processing: "How do you prevent double charges on retry?"
- Order placement: "What happens if the checkout request is retried?"
- Message delivery: "How does your notification service avoid sending duplicate emails?"
- Distributed transactions (Saga): each step in a Saga should be idempotent

**Key insight to communicate:**
Idempotency is not just a server concern — it requires client cooperation (sending the same key on retry) and database cooperation (idempotent writes). The middleware is the glue, but all three layers must be designed together.

**The `PENDING` state is load-bearing**: without it, two concurrent identical requests would both pass the "does key exist?" check and both execute the handler. The PENDING state (created atomically with `SET NX`) prevents this race condition. This is why the atomic create-if-not-exists operation is critical.
