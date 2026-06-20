# Python — Code Review Checklist

> Python-specific items for every Python PR. Applies to Python 3.9+. Items specific to 3.10+ or 3.12+ are called out explicitly.

---

## Quick Checklist

```
Type Safety
  ☐ Type hints on all public function signatures (params + return type)
  ☐ Optional[T] used for nullable returns, not T | None (pre-3.10) or T | None (3.10+)
  ☐ TypeVar or Protocol used where generics are needed
  ☐ mypy / pyright runs clean on changed files

Mutable Defaults
  ☐ No mutable default arguments (list, dict, set as default param values)
  ☐ Class-level mutable attributes initialised in __init__, not at class level

Classes and Data
  ☐ @dataclass or Pydantic model used for data-carrying classes
  ☐ __eq__ and __hash__ consistent (if __eq__ overridden, __hash__ set correctly)
  ☐ __repr__ returns a useful developer-facing string
  ☐ Properties used for computed values, not method-per-attribute patterns

Resource Management
  ☐ File handles, DB connections, network sockets use with (context manager)
  ☐ contextlib.contextmanager or __enter__/__exit__ for custom resources

Async
  ☐ No blocking calls inside async def (requests, time.sleep, open() without aiofiles)
  ☐ asyncio.gather() used for concurrent async work
  ☐ async for and async with used for async iterators and context managers

Error Handling
  ☐ bare except: not used
  ☐ except Exception as e: only catches what can be handled
  ☐ Exception message includes context (not just raise ValueError("error"))

Code Style
  ☐ PEP 8 compliance (enforced by ruff/flake8 in CI — not a manual review item)
  ☐ List/dict/set comprehensions preferred over equivalent map/filter + lambda
  ☐ f-strings used for string interpolation (not % formatting or .format())
  ☐ walrus operator (:=) used where it simplifies flow (Python 3.8+)
```

---

## Mutable Default Arguments

The most common Python gotcha. Default argument values are evaluated **once** at function definition time, not per call.

```python
# [BLOCK] Mutable default argument — shared state across calls
def add_line(order_id: str, lines: list = []) -> list:
    lines.append(order_id)
    return lines

add_line("ord_1")   # ['ord_1']
add_line("ord_2")   # ['ord_1', 'ord_2'] — same list from previous call!

# CORRECT: use None as sentinel, create inside the function
def add_line(order_id: str, lines: list | None = None) -> list:
    if lines is None:
        lines = []
    lines.append(order_id)
    return lines

# [BLOCK] Same issue with dict and set defaults
def process(options: dict = {}):   # WRONG
def process(options: dict | None = None):   # CORRECT
    options = options or {}

# [BLOCK] Mutable class attribute — shared across all instances
class OrderProcessor:
    pending_orders = []   # class attribute — shared by ALL instances

    def add(self, order):
        self.pending_orders.append(order)   # mutates class-level list

# CORRECT: initialise in __init__
class OrderProcessor:
    def __init__(self):
        self.pending_orders: list[Order] = []   # instance attribute
```

---

## Type Hints

```python
# [WARN] Missing type hints on public functions
def process_order(order_id, customer_id, amount):
    ...
# CORRECT:
def process_order(
    order_id: str,
    customer_id: str,
    amount: Decimal
) -> OrderResult:
    ...

# [WARN] Using Any to avoid thinking about types
from typing import Any

def get_metadata(key: str) -> Any:
    ...
# CORRECT: use Union, TypeVar, or Protocol to express the actual type
from typing import Union
def get_metadata(key: str) -> str | int | None:
    ...

# [WARN] Optional not used for nullable return
def find_order(order_id: str) -> Order:  # implies never None
    return self.db.get(order_id)          # but actually returns None if not found
# CORRECT:
def find_order(order_id: str) -> Order | None:
    return self.db.get(order_id)

# [NIT] Python 3.10+ union syntax preferred over Optional
from typing import Optional
def find(id: str) -> Optional[Order]:   # pre-3.10 style
def find(id: str) -> Order | None:      # 3.10+ — preferred

# [SUGGESTION] TypeAlias for complex types (Python 3.10+)
from typing import TypeAlias
OrderId: TypeAlias = str
CustomerId: TypeAlias = str
# Distinguishes domain types even though both are str at runtime

# [SUGGESTION] TypedDict for dict with known structure
from typing import TypedDict
class OrderSummary(TypedDict):
    order_id: str
    status: str
    total: Decimal

def get_summary(order_id: str) -> OrderSummary:
    ...
```

---

## Classes and Data Containers

```python
# [WARN] Plain class as data carrier — verbose, error-prone
class Order:
    def __init__(self, order_id: str, status: str, total: Decimal):
        self.order_id = order_id
        self.status = status
        self.total = total
    # Missing: __eq__, __repr__, __hash__

# CORRECT: use dataclass
from dataclasses import dataclass, field
from decimal import Decimal

@dataclass(frozen=True)   # frozen=True makes it immutable + hashable
class Order:
    order_id: str
    status: str
    total: Decimal
    lines: tuple[OrderLine, ...] = field(default_factory=tuple)  # immutable collection

# Or use Pydantic for validation at the boundary (external input)
from pydantic import BaseModel, validator

class CreateOrderRequest(BaseModel):
    customer_id: str
    lines: list[OrderLineRequest]
    currency: str = "USD"

    @validator("currency")
    def currency_must_be_valid(cls, v):
        if v not in SUPPORTED_CURRENCIES:
            raise ValueError(f"Unsupported currency: {v}")
        return v

# [BLOCK] __eq__ overridden without __hash__ — object becomes unhashable
class Order:
    def __eq__(self, other):
        return isinstance(other, Order) and self.order_id == other.order_id
    # MISSING: __hash__ — object can no longer be used in sets or as dict key
# CORRECT: define both, or use @dataclass(eq=True, frozen=True)
    def __hash__(self):
        return hash(self.order_id)
```

---

## Resource Management

```python
# [BLOCK] File/connection not closed in all code paths
f = open("orders.csv")
data = f.read()
process(data)
f.close()   # not called if process() raises an exception

# CORRECT: context manager guarantees cleanup
with open("orders.csv") as f:
    data = f.read()
process(data)

# [BLOCK] DB connection not returned to pool
conn = pool.get_connection()
cursor = conn.cursor()
cursor.execute(sql)
result = cursor.fetchall()
# MISSING: conn.close() — connection leak

# CORRECT:
with pool.get_connection() as conn:
    with conn.cursor() as cursor:
        cursor.execute(sql)
        result = cursor.fetchall()
# Both automatically released on exit

# [WARN] Custom resource without context manager
class TempFile:
    def __init__(self, path):
        self.path = path
        self.file = open(path, 'w')

    def cleanup(self):
        self.file.close()
        os.remove(self.path)
    # Caller must remember to call cleanup() — easy to forget

# CORRECT: implement context manager protocol
class TempFile:
    def __init__(self, path: str):
        self.path = path

    def __enter__(self):
        self.file = open(self.path, 'w')
        return self.file

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.file.close()
        os.remove(self.path)
        return False  # don't suppress exceptions

# Or use contextlib for generator-based context managers
from contextlib import contextmanager

@contextmanager
def temp_file(path: str):
    f = open(path, 'w')
    try:
        yield f
    finally:
        f.close()
        os.remove(path)
```

---

## Async / Await

```python
# [BLOCK] Blocking I/O inside async function — blocks the event loop
async def get_order(order_id: str) -> Order:
    response = requests.get(f"/orders/{order_id}")   # BLOCKING — freezes event loop
    return response.json()

# CORRECT: use async-native library
import httpx

async def get_order(order_id: str) -> Order:
    async with httpx.AsyncClient() as client:
        response = await client.get(f"/orders/{order_id}")
        return response.json()

# [BLOCK] time.sleep inside async function
async def process():
    time.sleep(5)   # blocks event loop for 5 seconds
# CORRECT:
async def process():
    await asyncio.sleep(5)   # yields control to event loop

# [WARN] Sequential awaits where concurrent execution is possible
async def get_order_summary(order_id: str):
    order = await get_order(order_id)        # waits before starting next
    customer = await get_customer(order.customer_id)  # waits here too
    # Total time = get_order_time + get_customer_time

# CORRECT: concurrent with asyncio.gather
async def get_order_summary(order_id: str):
    order, customer = await asyncio.gather(
        get_order(order_id),
        get_customer_from_order(order_id)
    )
    # Total time = max(get_order_time, get_customer_time)

# [WARN] Creating tasks without awaiting them
async def process():
    asyncio.create_task(background_job())   # fire and forget — exception is lost
# CORRECT: store task reference and await it, or add exception handler
task = asyncio.create_task(background_job())
task.add_done_callback(lambda t: log.error("bg job failed", exc_info=t.exception())
                       if t.exception() else None)
```

---

## Error Handling

```python
# [BLOCK] Bare except — catches SystemExit, KeyboardInterrupt, everything
try:
    process_order(order)
except:
    log.error("something failed")

# [BLOCK] Catching Exception but not re-raising or logging with traceback
try:
    process_order(order)
except Exception:
    log.error("Order processing failed")   # no traceback; root cause lost
# CORRECT:
try:
    process_order(order)
except OrderValidationError as e:
    log.warning("order.validation.failed", extra={"order_id": order.id, "error": str(e)})
    raise
except Exception:
    log.exception("order.processing.failed", extra={"order_id": order.id})  # includes traceback
    raise

# [WARN] Raising generic Exception
raise Exception("Something went wrong")
# CORRECT: use specific built-in or custom exception
raise ValueError(f"Invalid order status: {status!r}")
raise OrderNotFoundException(f"Order {order_id!r} not found")

# [WARN] Exception message without context
raise ValueError("Invalid quantity")
# CORRECT:
raise ValueError(
    f"Invalid quantity {quantity!r} for product {product_id!r}: "
    f"must be between 1 and {MAX_QUANTITY}"
)

# [NIT] Exception chaining for wrapping
try:
    db_result = execute_query(sql)
except psycopg2.Error as e:
    raise OrderPersistenceError(f"Failed to save order {order_id}") from e
# `from e` preserves the original cause in __cause__; shown in tracebacks
```

---

## Comprehensions and Functional Style

```python
# [WARN] map/filter with lambda when comprehension is clearer
submitted = list(filter(lambda o: o.status == "SUBMITTED", orders))
totals = list(map(lambda o: o.total, submitted))

# CORRECT: list comprehension — more Pythonic, often faster
submitted = [o for o in orders if o.status == "SUBMITTED"]
totals = [o.total for o in submitted]

# Or combined:
totals = [o.total for o in orders if o.status == "SUBMITTED"]

# [WARN] Nested comprehension that's hard to read
result = [[cell for cell in row if cell > 0] for row in matrix if any(c > 0 for c in row)]
# CORRECT: extract inner logic to a named function
def positive_cells(row: list[int]) -> list[int]:
    return [cell for cell in row if cell > 0]

result = [positive_cells(row) for row in matrix if any(c > 0 for c in row)]

# [NIT] Generator expression vs list comprehension in function calls
# When the function only iterates once, use a generator (no intermediate list)
total = sum(o.total for o in orders)            # generator — no list allocated
max_total = max(o.total for o in orders)        # generator

# Only use list comprehension when you need random access or multiple passes
totals = [o.total for o in orders]              # list — needed if you'll iterate twice
```

---

## Imports

```python
# [WARN] Wildcard import — pollutes namespace, hides what's used
from orders.models import *

# CORRECT: explicit imports
from orders.models import Order, OrderLine, OrderStatus

# [BLOCK] Circular imports — symptom of design coupling
# services/order_service.py: from models.customer import Customer
# models/customer.py: from services.order_service import OrderService
# → ImportError or inconsistent state
# CORRECT: move shared types to a separate module; use dependency injection

# [NIT] Import order (PEP 8; enforced by isort in CI):
# 1. Standard library
# 2. Third-party
# 3. Local application
import os                          # stdlib
import json

import httpx                       # third-party
from pydantic import BaseModel

from orders.models import Order    # local
from orders.service import OrderService
```

---

## Python-Specific Security Concerns

```python
# [BLOCK] eval() or exec() with any input — arbitrary code execution
def evaluate(expression: str) -> float:
    return eval(expression)   # attacker sends: "os.system('rm -rf /')"

# [BLOCK] pickle.loads on untrusted data — RCE
import pickle
data = pickle.loads(request.body)   # RCE if body is a malicious pickle

# [BLOCK] subprocess with shell=True and user input
subprocess.run(f"convert {user_filename}", shell=True)
# CORRECT:
subprocess.run(["convert", user_filename], shell=False)

# [BLOCK] Path traversal via os.path.join with user input
def get_file(filename: str):
    return open(os.path.join("/safe/dir", filename))
    # filename = "../../../etc/passwd" → path traversal
# CORRECT: validate filename and resolve path
safe_dir = Path("/safe/dir")
target = (safe_dir / filename).resolve()
if not str(target).startswith(str(safe_dir)):
    raise ValueError("Invalid filename")
```

---

## Reviewer Severity Summary

| Issue | Severity |
|---|---|
| Mutable default argument (list/dict/set) | `[BLOCK]` |
| eval()/exec() with any dynamic input | `[BLOCK]` |
| pickle.loads on external data | `[BLOCK]` |
| subprocess shell=True with user input | `[BLOCK]` |
| Path traversal via os.path.join | `[BLOCK]` |
| Bare except: clause | `[BLOCK]` |
| Blocking I/O inside async def | `[BLOCK]` |
| Resource not in context manager (file, connection) | `[BLOCK]` |
| __eq__ without __hash__ | `[BLOCK]` |
| Missing type hints on public functions | `[WARN]` |
| Sequential awaits that could be concurrent | `[WARN]` |
| Mutable class-level attribute | `[WARN]` |
| Generic Exception raised instead of specific type | `[WARN]` |
| Exception message without context | `[WARN]` |
| Missing `from e` in exception re-wrapping | `[WARN]` |
| map/filter with lambda instead of comprehension | `[NIT]` |
| Optional[T] instead of T \| None (Python 3.10+) | `[NIT]` |
| Wildcard import | `[NIT]` |
