# 04 — Functional Patterns, Generators, and Decorators

**Calibration:** Principal Engineer bar — Google / Meta / Amazon  
**Focus:** Generator internals, decorator mechanics, context managers, `itertools`/`functools` for production code, and where Python's functional idioms map to real system design decisions.

---

## 1. Generators — Lazy Iteration

A **generator function** contains `yield`. Calling it returns a generator object — a lazy iterator that produces values on demand.

```python
def count_up(start: int, step: int = 1):
    n = start
    while True:
        yield n          # suspends here, returns n to caller
        n += step        # resumes here when next() is called

gen = count_up(0)
next(gen)   # 0
next(gen)   # 1
next(gen)   # 2

# Generators are memory-efficient: infinite sequences in O(1) space
def fibonacci():
    a, b = 0, 1
    while True:
        yield a
        a, b = b, a + b

# Take first N without materializing the sequence
from itertools import islice
first_20 = list(islice(fibonacci(), 20))
```

### Generator Protocol

A generator implements `__iter__` (returns itself) and `__next__` (advances to next `yield`). When the function returns or `StopIteration` is raised, the generator is exhausted.

```python
def producer():
    print("start")
    value = yield "first"    # can also receive values via send()
    print(f"received: {value}")
    yield "second"
    print("done")

gen = producer()
next(gen)                    # "start", returns "first"
gen.send("hello")            # resumes with value="hello", prints "received: hello", returns "second"
next(gen)                    # "done", then raises StopIteration
```

### `yield from` — Delegation and Coroutine Chaining

```python
def flatten(nested):
    for item in nested:
        if isinstance(item, list):
            yield from flatten(item)   # delegate to sub-generator
        else:
            yield item

list(flatten([1, [2, [3, 4]], 5]))   # [1, 2, 3, 4, 5]

# yield from also transparently passes send() and throw() to sub-generator:
def pipeline():
    yield from source()    # send() calls propagate into source()
    yield from transform()
```

### Generator Expressions vs List Comprehensions

```python
# List comprehension — eager, entire result in memory
squares = [x**2 for x in range(1_000_000)]   # allocates list of 1M ints

# Generator expression — lazy, O(1) memory
squares_gen = (x**2 for x in range(1_000_000))  # no allocation yet

# Composing generator expressions — pipeline without intermediate lists:
data = read_large_file()   # returns generator of lines
processed = (
    parse_line(line)
    for line in data
    if not line.startswith('#')
)
result = sum(item.value for item in processed if item.value > 0)
# Entire pipeline processes one line at a time — O(1) memory regardless of file size
```

---

## 2. Decorators — Mechanics and Patterns

A **decorator** is a callable that takes a function and returns a function (or any callable).

### Function Decorators

```python
import functools, time

def timer(func):
    @functools.wraps(func)   # preserves __name__, __doc__, __annotations__
    def wrapper(*args, **kwargs):
        start = time.perf_counter()
        result = func(*args, **kwargs)
        elapsed = time.perf_counter() - start
        print(f"{func.__name__} took {elapsed:.3f}s")
        return result
    return wrapper

@timer
def slow_function(n):
    time.sleep(n)

# @timer is syntactic sugar for: slow_function = timer(slow_function)
```

### Decorator with Arguments — The Three-Layer Pattern

```python
def retry(max_attempts: int = 3, exceptions: tuple = (Exception,)):
    def decorator(func):
        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            last_exc = None
            for attempt in range(max_attempts):
                try:
                    return func(*args, **kwargs)
                except exceptions as e:
                    last_exc = e
                    if attempt < max_attempts - 1:
                        time.sleep(2 ** attempt)  # exponential backoff
            raise last_exc
        return wrapper
    return decorator

@retry(max_attempts=3, exceptions=(ConnectionError, TimeoutError))
def call_external_api(url: str) -> dict:
    ...
```

### Class Decorators

```python
def singleton(cls):
    instances = {}
    @functools.wraps(cls, updated=[])
    def get_instance(*args, **kwargs):
        if cls not in instances:
            instances[cls] = cls(*args, **kwargs)
        return instances[cls]
    return get_instance

@singleton
class Config:
    def __init__(self):
        self.settings = load_settings()
```

### Stacking Decorators — Order Matters

```python
@timer           # applied second (outer)
@retry(3)        # applied first (inner)
def fetch(url):
    ...

# Equivalent to: fetch = timer(retry(3)(fetch))
# Execution order: timer's wrapper → retry's wrapper → actual fetch
```

**`functools.wraps`:** Without it, the wrapper function loses the original function's metadata:

```python
def bad_decorator(func):
    def wrapper(*args, **kwargs):
        return func(*args, **kwargs)
    return wrapper

@bad_decorator
def my_func():
    """My docstring"""
    pass

my_func.__name__   # "wrapper" — NOT "my_func"
my_func.__doc__    # None — docstring lost

# With functools.wraps:
def good_decorator(func):
    @functools.wraps(func)
    def wrapper(*args, **kwargs):
        return func(*args, **kwargs)
    return wrapper
```

### Async Decorators

```python
import asyncio, functools

def async_retry(max_attempts: int = 3):
    def decorator(func):
        @functools.wraps(func)
        async def wrapper(*args, **kwargs):
            for attempt in range(max_attempts):
                try:
                    return await func(*args, **kwargs)
                except Exception as e:
                    if attempt == max_attempts - 1:
                        raise
                    await asyncio.sleep(2 ** attempt)
        return wrapper
    return decorator

@async_retry(max_attempts=3)
async def fetch(url: str) -> dict:
    ...
```

---

## 3. Context Managers

Context managers wrap `with` statements — guaranteed `__exit__` regardless of exceptions.

### `__enter__` / `__exit__` Protocol

```python
class ManagedConnection:
    def __init__(self, dsn: str):
        self.dsn = dsn
        self.conn = None

    def __enter__(self):
        self.conn = connect(self.dsn)
        return self.conn

    def __exit__(self, exc_type, exc_val, exc_tb):
        if exc_type:
            self.conn.rollback()
        else:
            self.conn.commit()
        self.conn.close()
        return False   # don't suppress the exception (return True to suppress)

with ManagedConnection("postgres://localhost/db") as conn:
    conn.execute("INSERT INTO users VALUES (...)")
# __exit__ called here — commit or rollback, always close
```

### `contextlib.contextmanager` — Generator-Based

```python
from contextlib import contextmanager, asynccontextmanager, suppress

@contextmanager
def timer(label: str):
    start = time.perf_counter()
    try:
        yield                                   # body of 'with' runs here
    finally:
        elapsed = time.perf_counter() - start
        print(f"{label}: {elapsed:.3f}s")

with timer("database query"):
    results = db.execute(query)

# suppress — context manager that swallows specific exceptions
with suppress(FileNotFoundError):
    os.remove(temp_file)   # no error if file doesn't exist

# ExitStack — dynamically compose context managers
from contextlib import ExitStack

resources = ['file1.txt', 'file2.txt', 'file3.txt']
with ExitStack() as stack:
    files = [stack.enter_context(open(f)) for f in resources]
    # all files opened; all closed when ExitStack exits
    process_files(files)
```

---

## 4. `functools` — Production Utilities

```python
import functools

# lru_cache — memoization with bounded cache
@functools.lru_cache(maxsize=1024)
def expensive_calculation(n: int) -> int:
    if n < 2:
        return n
    return expensive_calculation(n-1) + expensive_calculation(n-2)

# cache (Python 3.9+) — unbounded memoization
@functools.cache
def parse_regex(pattern: str):
    return re.compile(pattern)

# Inspect cache:
expensive_calculation.cache_info()   # CacheInfo(hits=..., misses=..., maxsize=1024, currsize=...)
expensive_calculation.cache_clear()  # clear the cache

# partial — fix arguments
from functools import partial

def power(base, exponent):
    return base ** exponent

square = partial(power, exponent=2)
cube = partial(power, exponent=3)
square(5)   # 25
cube(3)     # 27

# reduce — left fold
from functools import reduce
product = reduce(lambda acc, x: acc * x, [1, 2, 3, 4, 5], 1)  # 120

# total_ordering — generate comparison methods
from functools import total_ordering

@total_ordering
class Card:
    def __init__(self, value: int):
        self.value = value

    def __eq__(self, other): return self.value == other.value
    def __lt__(self, other): return self.value < other.value
    # total_ordering generates __le__, __gt__, __ge__
```

---

## 5. `itertools` — Algorithmic Building Blocks

```python
import itertools

# chain — concatenate iterables without copying
all_items = itertools.chain(list1, list2, list3)

# islice — lazy slicing of any iterator
first_100 = list(itertools.islice(infinite_generator(), 100))

# groupby — consecutive equal elements
data = sorted([('a', 1), ('a', 2), ('b', 3)], key=lambda x: x[0])
for key, group in itertools.groupby(data, key=lambda x: x[0]):
    print(key, list(group))

# product — cartesian product (replaces nested loops)
for a, b, c in itertools.product([0, 1], repeat=3):
    print(a, b, c)  # all 3-bit combinations

# combinations / permutations
list(itertools.combinations([1, 2, 3], 2))   # [(1,2), (1,3), (2,3)]
list(itertools.permutations([1, 2, 3], 2))   # [(1,2), (1,3), (2,1), (2,3), (3,1), (3,2)]

# accumulate — running totals, running max, etc.
import operator
list(itertools.accumulate([1, 2, 3, 4, 5]))                    # [1, 3, 6, 10, 15]
list(itertools.accumulate([1, 2, 3, 4, 5], operator.mul))      # [1, 2, 6, 24, 120]
list(itertools.accumulate([3, 1, 4, 1, 5, 9, 2], max))         # [3, 3, 4, 4, 5, 9, 9]

# batched (Python 3.12) — split into fixed-size chunks
list(itertools.batched([1,2,3,4,5,6,7], 3))  # [(1,2,3), (4,5,6), (7,)]

# pairwise (Python 3.10) — consecutive pairs
list(itertools.pairwise([1, 2, 3, 4]))  # [(1,2), (2,3), (3,4)]
```

---

## 6. Comprehensions — Performance and Scope

```python
# List, dict, set, generator comprehensions
squares = [x**2 for x in range(10)]
square_map = {x: x**2 for x in range(10)}
unique_lengths = {len(word) for word in words}
lazy_squares = (x**2 for x in range(10))

# Nested comprehension — think of loops from left to right
matrix = [[1,2,3], [4,5,6], [7,8,9]]
flat = [x for row in matrix for x in row]   # [1,2,3,4,5,6,7,8,9]

# Conditional comprehension
evens = [x for x in range(20) if x % 2 == 0]
classified = ['even' if x % 2 == 0 else 'odd' for x in range(10)]
```

### Comprehension Variable Scope (Python 3+)

```python
x = 10
result = [x for x in range(5)]  # x in comprehension is SCOPED — doesn't affect outer x
print(x)  # 10 — outer x unchanged (Python 3 behavior)

# Python 2 leaked comprehension variables — this was a bug source
```

### When to Use vs. Avoid Comprehensions

```python
# USE: simple transformations and filters
clean = [item.strip() for item in raw if item.strip()]

# AVOID: complex logic — use regular loops for readability
# Bad:
result = [
    transform(item)
    for item in data
    if predicate(item)
    if other_predicate(item)
    for sub in item.children
    if sub.is_valid()
]

# Better:
result = []
for item in data:
    if not (predicate(item) and other_predicate(item)):
        continue
    for sub in item.children:
        if sub.is_valid():
            result.append(transform(item))
```

---

## Interview Q&A

### Q1 `[Principal]` A generator function that uses `yield from` to delegate to a sub-generator. What happens to `send()` calls and `throw()` calls made to the outer generator?

**Answer:**

`yield from` is a **transparent delegation** mechanism. Any `send()` call to the outer generator is forwarded directly to the sub-generator's `send()`. Any `throw()` to the outer is forwarded to the sub-generator's `throw()`. `StopIteration` from the sub-generator is caught by `yield from` and its value becomes the result of the `yield from` expression.

```python
def inner():
    value = yield "from inner"
    print(f"inner received: {value}")
    return "inner result"

def outer():
    result = yield from inner()  # transparent proxy
    print(f"inner returned: {result}")
    yield "from outer"

gen = outer()
next(gen)                  # "from inner" — reaches inner's yield
gen.send("hello")          # inner receives "hello", inner returns, outer resumes
                           # prints "inner received: hello"
                           # prints "inner returned: inner result"
                           # returns "from outer"
```

**Practical implication:** This is how asyncio's original `@asyncio.coroutine` / `yield from` syntax worked before `async/await`. `yield from` enabled coroutine composition before Python 3.5. The `async/await` syntax desugars to the same mechanism internally.

**`throw()` propagation:**

```python
def inner():
    try:
        yield 1
    except ValueError as e:
        print(f"inner caught: {e}")
        yield 2

def outer():
    yield from inner()

gen = outer()
next(gen)                      # 1
gen.throw(ValueError("oops"))  # forwarded to inner: "inner caught: oops", returns 2
```

---

### Q2 `[Principal]` Design a production-grade rate limiter using a decorator and a generator. It should support per-key rate limiting with a sliding window.

**Answer:**

```python
import time
import collections
import functools
import threading
from typing import Callable, TypeVar, ParamSpec

P = ParamSpec('P')
R = TypeVar('R')

class SlidingWindowRateLimiter:
    def __init__(self, max_calls: int, window_seconds: float):
        self.max_calls = max_calls
        self.window = window_seconds
        self._timestamps: dict[str, collections.deque] = collections.defaultdict(collections.deque)
        self._lock = threading.Lock()

    def is_allowed(self, key: str) -> bool:
        now = time.monotonic()
        cutoff = now - self.window
        with self._lock:
            dq = self._timestamps[key]
            # Remove timestamps outside the window
            while dq and dq[0] < cutoff:
                dq.popleft()
            if len(dq) >= self.max_calls:
                return False
            dq.append(now)
            return True

    def limit(self, key_func: Callable[P, str] | None = None):
        """Decorator factory — key_func extracts rate limit key from args"""
        def decorator(func: Callable[P, R]) -> Callable[P, R]:
            @functools.wraps(func)
            def wrapper(*args: P.args, **kwargs: P.kwargs) -> R:
                key = key_func(*args, **kwargs) if key_func else func.__name__
                if not self.is_allowed(key):
                    raise RateLimitExceeded(f"Rate limit exceeded for key: {key}")
                return func(*args, **kwargs)
            return wrapper
        return decorator

class RateLimitExceeded(Exception): pass

# Usage:
limiter = SlidingWindowRateLimiter(max_calls=100, window_seconds=60.0)

@limiter.limit(key_func=lambda user_id, *args, **kwargs: f"api:{user_id}")
def api_call(user_id: int, endpoint: str) -> dict:
    return fetch(endpoint)

# Per-endpoint + per-user:
api_limiter = SlidingWindowRateLimiter(max_calls=10, window_seconds=1.0)

@api_limiter.limit(key_func=lambda req: f"{req.user_id}:{req.endpoint}")
def handle_request(req):
    return process(req)
```

**Production additions:** Replace `threading.Lock` with `asyncio.Lock` for async services; use Redis with sorted sets for distributed rate limiting across multiple processes.

---

### Q3 `[Principal]` `functools.lru_cache` can cause memory leaks in production. Describe two scenarios and the fix for each.

**Answer:**

**Scenario 1 — Cached functions on instance methods:**

```python
class DataLoader:
    @functools.lru_cache(maxsize=None)
    def load(self, key: str) -> dict:
        return expensive_db_call(key)

# lru_cache stores (self, key) as the cache key
# self is kept alive by the cache → DataLoader instances never garbage-collected
# Even after all other references are gone, the cache holds a reference

loader = DataLoader()
loader.load("key1")
del loader
# DataLoader instance is NOT freed — cache holds a reference to self
```

**Fix:** Use `methodtools.lru_cache` (which uses `weakref`), or cache at the class/module level with explicit key:

```python
from functools import lru_cache

_cache: dict = {}

def get_loader_data(loader_id: str, key: str) -> dict:
    cache_key = (loader_id, key)
    if cache_key not in _cache:
        _cache[cache_key] = expensive_db_call(key)
    return _cache[cache_key]
```

**Scenario 2 — Unbounded cache with high-cardinality keys:**

```python
@functools.lru_cache(maxsize=None)   # unbounded
def parse_user_query(query: str) -> AST:
    return parser.parse(query)

# In a search service with 1M unique user queries:
# cache stores 1M AST objects — potential OOM
```

**Fix:** Set `maxsize` to a bounded value. Rule of thumb: `maxsize` = maximum working set of unique inputs you expect in a time window. Use `cache_info()` to measure hit rate and tune.

```python
@functools.lru_cache(maxsize=10_000)  # evicts LRU entries when full
def parse_user_query(query: str) -> AST:
    return parser.parse(query)
```

---

*See also:* [01-language-internals.md](01-language-internals.md) for descriptor protocol (which `@property` and `lru_cache` use) | [02-concurrency-and-asyncio.md](02-concurrency-and-asyncio.md) for async generators and async context managers
