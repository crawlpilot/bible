# 02 — Concurrency and asyncio

**Calibration:** Principal Engineer bar — Google / Meta / Amazon  
**Focus:** When to use threading vs. multiprocessing vs. asyncio, event loop internals, async/await under the hood, and production patterns for high-throughput Python services.

---

## 1. The Three Concurrency Models

| Model | Module | Parallelism | Best For |
|-------|--------|-------------|----------|
| Threading | `threading` | Concurrent (GIL), not parallel for CPU | I/O-bound with blocking calls |
| Multiprocessing | `multiprocessing` | True parallel (separate processes) | CPU-bound computation |
| Asyncio | `asyncio` | Concurrent via event loop (single thread) | High I/O concurrency (thousands of connections) |

**Decision rule:**
- Thousands of simultaneous network/db connections → **asyncio**
- Blocking I/O you can't make async (legacy libs) → **threading**
- Heavy CPU work (ML inference, image processing, serialization) → **multiprocessing**
- CPU + async I/O → **ProcessPoolExecutor** with `loop.run_in_executor`

---

## 2. threading — What the GIL Means in Practice

```python
import threading
import time

def io_task(url):
    # GIL released during socket I/O
    response = requests.get(url)  # blocking but GIL is released here
    return response.status_code

# Threading works well for blocking I/O:
urls = ["https://example.com"] * 20
with threading.ThreadPoolExecutor(max_workers=10) as pool:
    results = list(pool.map(io_task, urls))
    # 10 threads make I/O calls concurrently — GIL is released during each socket call

# Threading does NOT help for CPU:
def cpu_task(n):
    return sum(range(n))  # pure Python — GIL held

# These run serially despite appearing parallel
t1 = threading.Thread(target=cpu_task, args=(10_000_000,))
t2 = threading.Thread(target=cpu_task, args=(10_000_000,))
t1.start(); t2.start()
t1.join(); t2.join()
# Wall time ≈ same as running t1 then t2 sequentially
```

### Thread Safety Primitives

```python
import threading

# Lock — mutual exclusion
lock = threading.Lock()
with lock:
    shared_state += 1  # thread-safe

# RLock — reentrant (same thread can acquire multiple times)
rlock = threading.RLock()

# Condition — wait/notify
condition = threading.Condition(lock)
with condition:
    while not data_ready:
        condition.wait()        # releases lock and suspends
    process_data()
condition.notify_all()          # wake all waiting threads

# Semaphore — limit concurrent access
semaphore = threading.Semaphore(5)  # at most 5 concurrent
with semaphore:
    call_rate_limited_api()

# Event — simple signal
event = threading.Event()
event.set()      # signal
event.wait()     # block until set
event.clear()    # reset

# Queue — thread-safe producer/consumer
from queue import Queue
q = Queue(maxsize=100)
q.put(item)        # blocks if full
q.get()            # blocks if empty
q.task_done()      # signal item processed
q.join()           # wait for all items to be processed
```

---

## 3. multiprocessing — True CPU Parallelism

```python
import multiprocessing
from multiprocessing import Pool, Queue, Manager

def cpu_intensive(data: list[int]) -> int:
    return sum(x ** 2 for x in data)

# Pool: distribute work across N processes
with Pool(processes=multiprocessing.cpu_count()) as pool:
    chunks = [list(range(i, i+1000)) for i in range(0, 100_000, 1000)]
    results = pool.map(cpu_intensive, chunks)  # parallel, true CPU utilization

# Process-safe queue for IPC
def producer(q: Queue):
    for i in range(100):
        q.put(i)
    q.put(None)  # sentinel

def consumer(q: Queue):
    while True:
        item = q.get()
        if item is None:
            break
        process(item)

q = multiprocessing.Queue()
p1 = multiprocessing.Process(target=producer, args=(q,))
p2 = multiprocessing.Process(target=consumer, args=(q,))
```

### The Pickling Requirement

`multiprocessing` sends data between processes via serialization (pickle). Functions and objects must be **picklable**:

```python
# FAILS — lambda is not picklable
pool.map(lambda x: x**2, range(100))

# FAILS — instance method without __reduce__ is not picklable in Python < 3.5
class Transformer:
    def transform(self, x): return x * 2
# pool.map(t.transform, data)  ← may fail depending on version

# WORKS — top-level function
def square(x): return x ** 2
pool.map(square, range(100))

# WORKS — use functools.partial for parameterized functions
from functools import partial
def power(base, exponent): return base ** exponent
pool.map(partial(power, exponent=2), range(100))
```

### Shared Memory (Python 3.8+)

```python
from multiprocessing import shared_memory
import numpy as np

# Create shared memory block
shm = shared_memory.SharedMemory(create=True, size=1024 * 1024)  # 1MB

# Create numpy array backed by shared memory
arr = np.ndarray((1000,), dtype=np.float64, buffer=shm.buf)
arr[:] = np.random.random(1000)

# In worker processes, attach to the same memory by name:
def worker(shm_name, size):
    existing_shm = shared_memory.SharedMemory(name=shm_name)
    arr = np.ndarray((size,), dtype=np.float64, buffer=existing_shm.buf)
    result = arr.sum()
    existing_shm.close()
    return result

with Pool(4) as pool:
    results = pool.starmap(worker, [(shm.name, 1000)] * 4)

shm.close()
shm.unlink()  # must explicitly free
```

---

## 4. asyncio — Event Loop Internals

### What `async/await` Actually Is

Python's `async/await` is built on generators. `async def` creates a **coroutine function**; calling it returns a **coroutine object** (not the result). The event loop drives execution.

```python
# async def is syntactic sugar for a generator-based coroutine
async def fetch(url: str) -> str:
    async with aiohttp.ClientSession() as session:
        async with session.get(url) as response:
            return await response.text()

# Under the hood (simplified):
# 1. fetch(url) returns a coroutine object — no code runs yet
# 2. asyncio.run() creates an event loop and drives the coroutine
# 3. When 'await response.text()' suspends, control returns to the event loop
# 4. Event loop polls the I/O selector; when the socket is readable, resumes the coroutine
```

### Event Loop Architecture

```
Event Loop
├── Ready queue: coroutines ready to run (no waiting needed)
├── I/O selector (epoll/kqueue): monitors file descriptors
├── Timers heap: call_later(), call_at() callbacks
└── Scheduled callbacks: call_soon()

Loop iteration:
1. Run all ready callbacks
2. Poll I/O selector (with timeout = next timer deadline)
3. Schedule callbacks for completed I/O and expired timers
4. Repeat
```

The event loop is **single-threaded**. No GIL contention, but also: **blocking the event loop blocks everything**.

```python
import asyncio, time

async def bad_handler():
    time.sleep(5)        # BLOCKS the entire event loop for 5 seconds!
    # Every other coroutine is frozen while time.sleep runs

async def good_handler():
    await asyncio.sleep(5)  # suspends this coroutine, event loop runs others
```

### Core asyncio Patterns

```python
import asyncio
import aiohttp

# 1. Gather: run multiple coroutines concurrently, wait for all
async def fetch_all(urls: list[str]) -> list[str]:
    async with aiohttp.ClientSession() as session:
        tasks = [fetch_one(session, url) for url in urls]
        results = await asyncio.gather(*tasks)  # all run concurrently
        return results

# 2. gather with return_exceptions — don't cancel everything if one fails
results = await asyncio.gather(*tasks, return_exceptions=True)
for result in results:
    if isinstance(result, Exception):
        handle_error(result)
    else:
        handle_success(result)

# 3. TaskGroup (Python 3.11+) — structured concurrency
async def load_dashboard(user_id: int):
    async with asyncio.TaskGroup() as tg:
        user_task = tg.create_task(fetch_user(user_id))
        orders_task = tg.create_task(fetch_orders(user_id))
        # If any task raises, all others are cancelled and exception re-raised
    return Dashboard(user_task.result(), orders_task.result())

# 4. Timeout
async def fetch_with_timeout(url: str) -> str:
    async with asyncio.timeout(5.0):  # Python 3.11+
        return await fetch(url)
    # asyncio.TimeoutError raised if not completed in 5s

# 5. Semaphore — rate limiting
semaphore = asyncio.Semaphore(10)  # max 10 concurrent requests

async def rate_limited_fetch(session, url):
    async with semaphore:
        return await session.get(url)
```

### Running CPU Work Without Blocking

```python
import asyncio
from concurrent.futures import ProcessPoolExecutor

executor = ProcessPoolExecutor(max_workers=4)

async def process_image(image_bytes: bytes) -> bytes:
    loop = asyncio.get_event_loop()
    # Run CPU-bound work in a process pool without blocking the event loop
    result = await loop.run_in_executor(executor, compress_image, image_bytes)
    return result

# For thread-pool (I/O-bound blocking lib without async version):
from concurrent.futures import ThreadPoolExecutor
thread_executor = ThreadPoolExecutor(max_workers=20)

async def call_blocking_lib(data):
    loop = asyncio.get_event_loop()
    result = await loop.run_in_executor(thread_executor, blocking_third_party_call, data)
    return result
```

---

## 5. Async Generators and Context Managers

```python
# Async generator — yields values asynchronously
async def paginate(url: str, page_size: int = 100):
    page = 1
    while True:
        data = await fetch_page(url, page=page, size=page_size)
        if not data:
            break
        for item in data:
            yield item
        page += 1

# Usage:
async def process_all():
    async for item in paginate("https://api.example.com/items"):
        await process(item)

# Async context manager
class DatabaseTransaction:
    async def __aenter__(self):
        self.conn = await get_connection()
        await self.conn.begin()
        return self.conn

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        if exc_type:
            await self.conn.rollback()
        else:
            await self.conn.commit()
        await self.conn.close()
        return False  # don't suppress exceptions

# contextlib.asynccontextmanager
from contextlib import asynccontextmanager

@asynccontextmanager
async def db_transaction(pool):
    conn = await pool.acquire()
    try:
        await conn.begin()
        yield conn
        await conn.commit()
    except Exception:
        await conn.rollback()
        raise
    finally:
        await pool.release(conn)
```

---

## 6. concurrent.futures — The Unified Interface

```python
from concurrent.futures import ThreadPoolExecutor, ProcessPoolExecutor, as_completed

# ThreadPoolExecutor for I/O-bound
with ThreadPoolExecutor(max_workers=20) as executor:
    futures = {executor.submit(fetch_url, url): url for url in urls}
    for future in as_completed(futures):
        url = futures[future]
        try:
            result = future.result()
        except Exception as e:
            print(f"{url} failed: {e}")

# ProcessPoolExecutor for CPU-bound
with ProcessPoolExecutor(max_workers=4) as executor:
    futures = [executor.submit(heavy_compute, chunk) for chunk in data_chunks]
    results = [f.result() for f in futures]  # blocks until all done

# map() — simpler but blocks until ALL complete (no partial results)
with ProcessPoolExecutor() as executor:
    results = list(executor.map(process, items, timeout=30))
```

---

## 7. asyncio Patterns for Production Services

### Connection Pool Pattern

```python
import asyncio
from asyncpg import create_pool

class DatabaseService:
    def __init__(self):
        self._pool = None

    async def startup(self):
        self._pool = await create_pool(
            dsn="postgresql://user:pass@localhost/db",
            min_size=5,
            max_size=20,
            command_timeout=10
        )

    async def shutdown(self):
        await self._pool.close()

    async def fetch_user(self, user_id: int):
        async with self._pool.acquire() as conn:
            return await conn.fetchrow("SELECT * FROM users WHERE id = $1", user_id)
```

### Background Task Pattern

```python
class BackgroundWorker:
    def __init__(self):
        self._queue: asyncio.Queue = asyncio.Queue(maxsize=1000)
        self._task: asyncio.Task | None = None

    async def start(self):
        self._task = asyncio.create_task(self._worker())

    async def stop(self):
        await self._queue.join()    # wait for all items to be processed
        self._task.cancel()
        try:
            await self._task
        except asyncio.CancelledError:
            pass

    async def enqueue(self, item):
        await self._queue.put(item)

    async def _worker(self):
        while True:
            item = await self._queue.get()
            try:
                await process(item)
            except Exception as e:
                logger.error(f"Worker error: {e}")
            finally:
                self._queue.task_done()
```

---

## Interview Q&A

### Q1 `[Principal]` An asyncio service handles 10,000 concurrent connections but has high latency spikes every 30 seconds. What is the most likely cause and how do you diagnose it?

**Answer:**

Most likely cause: **blocking the event loop** — either from:
1. A synchronous I/O call (DB driver without async support, `requests` instead of `aiohttp`)
2. CPU-intensive work in a handler (JSON parsing of large payloads, encryption)
3. Garbage collection pause (cyclic GC collecting a generation)

**Diagnosis:**

```python
# 1. Instrument the event loop lag
import asyncio, time

async def monitor_loop_lag():
    while True:
        start = time.monotonic()
        await asyncio.sleep(0)    # yield to event loop
        lag = time.monotonic() - start
        if lag > 0.01:            # >10ms lag → something blocked the loop
            logger.warning(f"Event loop lag: {lag*1000:.1f}ms")
        await asyncio.sleep(1)

# 2. Use asyncio debug mode
asyncio.run(main(), debug=True)
# Logs any coroutine that takes >100ms to yield

# 3. Profile with py-spy or yappi (asyncio-aware profiler)
# py-spy top --pid <pid>  — shows which code runs most
```

**Fix:** Move blocking calls to `run_in_executor`, use async DB drivers (`asyncpg`, `motor`, `aioredis`), cap payload sizes to avoid long CPU bursts.

---

### Q2 `[Principal]` Explain the difference between `asyncio.gather()` and `asyncio.TaskGroup`. When does one cancel siblings and the other doesn't?

**Answer:**

**`asyncio.gather(*tasks, return_exceptions=False)` (default):**
- If any task raises an exception, the exception propagates immediately.
- Other tasks are NOT automatically cancelled — they continue running as orphaned tasks.
- If you want cancellation, you must explicitly cancel the remaining futures.

```python
# Silently leaks tasks on failure:
results = await asyncio.gather(task1(), task2(), task3())
# If task2 raises: results[1] raises, but task1 and task3 keep running
```

**`asyncio.TaskGroup` (Python 3.11+):**
- If any child task raises, ALL other children are immediately cancelled.
- The `async with` block re-raises the exception after all cancellations are done.
- Structured concurrency — no orphaned tasks.

```python
async with asyncio.TaskGroup() as tg:
    t1 = tg.create_task(task1())
    t2 = tg.create_task(task2())
    t3 = tg.create_task(task3())
# If t2 raises: t1 and t3 are cancelled, then the exception re-raises here
```

**When to use which:**
- `gather(return_exceptions=True)`: fan-out where you want all results (some may be errors) — e.g., loading multiple dashboard widgets independently.
- `TaskGroup`: fan-out where all tasks are part of a unit — one failure invalidates the whole operation (e.g., a distributed transaction's sub-operations).
- `gather(return_exceptions=False)`: legacy; prefer `TaskGroup` for new code.

---

### Q3 `[Principal]` You have a Python web service on 8 cores. Design the process/thread/coroutine model for maximum throughput for a service that does: 70% PostgreSQL queries, 20% Redis cache lookups, 10% CPU (JSON serialization of large payloads).

**Answer:**

**Process model:** Run `N` worker processes (typically `2 * cpu_count + 1` = 17 for 8 cores, but tuned empirically). Each worker has its own event loop. Use `gunicorn` + `uvicorn` workers:

```
gunicorn main:app -k uvicorn.workers.UvicornWorker -w 17 --worker-connections 1000
```

**Within each worker process:**

```python
# Async event loop handles all I/O concurrently:
# - PostgreSQL: asyncpg connection pool (async, releases event loop during query)
# - Redis: aioredis (async)
# - JSON serialization: run_in_executor(thread_pool) for payloads >1MB

class App:
    async def startup(self):
        self.db_pool = await asyncpg.create_pool(dsn, min_size=5, max_size=20)
        self.redis = await aioredis.create_redis_pool(redis_url)
        self.thread_pool = ThreadPoolExecutor(max_workers=4)

    async def handle_request(self, request):
        # Check Redis cache
        cached = await self.redis.get(request.cache_key)
        if cached:
            return cached

        # Query PostgreSQL — 70% of requests
        data = await self.db_pool.fetchrow(query, *params)

        # Serialize — offload to thread pool if large
        if len(data) > 10_000:
            result = await asyncio.get_event_loop().run_in_executor(
                self.thread_pool, json.dumps, data
            )
        else:
            result = json.dumps(data)  # small enough, OK on event loop

        await self.redis.set(request.cache_key, result, expire=300)
        return result
```

**Why this model:**
- Separate processes → GIL not a factor, full CPU utilization across cores.
- Async within each process → 1000s of concurrent I/O operations per worker with a single thread.
- Thread pool for JSON → avoids blocking the event loop on CPU-bound work.
- asyncpg/aioredis → no GIL-holding blocking I/O; event loop yields during all I/O.

---

*See also:* [01-language-internals.md](01-language-internals.md) for GIL mechanics | [../java/03-concurrency-and-loom.md](../java/03-concurrency-and-loom.md) for Java virtual threads comparison | [../../HLD/designs/](../../HLD/designs/) for system designs that use async Python services
