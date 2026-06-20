# 01 — Python Language Internals

**Calibration:** Principal Engineer bar — Google / Meta / Amazon  
**Focus:** CPython implementation details, memory model, data model protocols, descriptor protocol, MRO, metaclasses — the layer beneath idiomatic Python that principal-level interviews probe.

---

## 1. CPython and the GIL

### What the GIL Is

The **Global Interpreter Lock (GIL)** is a mutex in CPython that prevents multiple native threads from executing Python bytecode simultaneously. It is held for the duration of bytecode execution and released at I/O boundaries and every 5ms of CPU work (the "check interval" — `sys.getswitchinterval()`).

**Consequence:** CPU-bound Python code does not benefit from multiple threads. A 4-thread Python program doing pure computation is often slower than 1 thread due to GIL contention overhead.

**What the GIL protects:** CPython's reference counting. Every Python object has a `ob_refcnt` field. Without the GIL, two threads incrementing `ob_refcnt` simultaneously would corrupt it — the object would be freed while still in use.

### GIL Release Points

```python
import time, threading

def cpu_bound():
    # GIL held throughout — two threads run serially, not in parallel
    x = 0
    for _ in range(100_000_000):
        x += 1
    return x

def io_bound():
    # GIL released during time.sleep — two threads truly parallel
    time.sleep(1)
```

The GIL is released during:
- I/O syscalls (`read`, `write`, `select`, `recv`)
- `time.sleep`
- C extension calls that explicitly release it (`numpy`, `hashlib`, `re` on long strings)
- `ctypes` calls with `use_errno=True`

### GIL in Python 3.13+ (Free-Threaded CPython — PEP 703)

Python 3.13 introduces a **free-threaded build** (`python3.13t`) that removes the GIL. Status: opt-in, experimental. Fine-grained per-object locking replaces it. Performance overhead for single-threaded code: ~10–40% currently (being optimized).

**FAANG interview callout:** Python 3.13's no-GIL is still experimental; production systems at FAANG use the workarounds below.

### Working Around the GIL

| Scenario | Solution |
|----------|----------|
| CPU-bound parallelism | `multiprocessing.Pool` — separate processes, no GIL |
| CPU + NumPy/SciPy | NumPy releases GIL for C operations — threads work |
| I/O concurrency | `asyncio` or `threading` — GIL released at every I/O |
| Mixed CPU + I/O | `concurrent.futures.ProcessPoolExecutor` for CPU, async for I/O |

---

## 2. Memory Model — Reference Counting + Cyclic GC

CPython manages memory with **reference counting**. Every object tracks how many references point to it. When the count hits zero, the object is immediately freed.

```python
import sys

x = []
sys.getrefcount(x)   # 2: one for x, one for getrefcount's argument

y = x
sys.getrefcount(x)   # 3: x, y, getrefcount arg

del y
sys.getrefcount(x)   # 2 again

del x                # refcount = 0 → freed immediately (no GC pause)
```

**Why reference counting alone is insufficient:** Cycles.

```python
a = []
b = [a]
a.append(b)  # a → b → a: cycle

del a
del b
# Both objects still alive! refcount of a and b are both 1 (from each other)
# The cyclic GC (generation-based) will collect these
```

CPython runs a **cyclic garbage collector** (`gc` module) for cycle detection. It uses generational collection: 3 generations, objects promoted after surviving collections. The GC is rarely a performance problem but can cause pauses in latency-sensitive services.

```python
import gc

gc.disable()      # disable cyclic GC (reference counting still works)
gc.collect()      # force collection of all generations
gc.set_threshold(700, 10, 10)  # tune generation thresholds
```

### `__del__` and Weak References

`__del__` is a finalizer called when an object's refcount reaches zero. Unreliable:
- Not called during interpreter shutdown.
- Not called if the object is in a reference cycle (cyclic GC collects cycles but doesn't guarantee `__del__` call order).

```python
import weakref

class Resource:
    def cleanup(self):
        print("cleaned up")

resource = Resource()
weak = weakref.ref(resource)  # doesn't increment refcount

weak()    # returns resource if alive, None if collected
resource = None  # refcount → 0, resource freed
weak()    # None
```

Use `weakref` for caches — prevents the cache from keeping objects alive:

```python
import weakref

class ImageCache:
    def __init__(self):
        self._cache: dict[str, weakref.ref] = {}

    def get(self, path: str):
        ref = self._cache.get(path)
        if ref is not None:
            img = ref()
            if img is not None:
                return img
        img = load_image(path)
        self._cache[path] = weakref.ref(img)
        return img
```

### Object Interning

Small integers (`-5` to `256`) and short strings are **interned** — a single object is reused:

```python
a = 256; b = 256; a is b  # True  — interned
a = 257; b = 257; a is b  # False — new objects

s1 = "hello"; s2 = "hello"; s1 is s2   # True  — interned (identifier-like strings)
s1 = "hello world"; s2 = "hello world"; s1 is s2  # False in general
```

**Never use `is` for value equality** — use `==`. `is` tests object identity (same `id()`).

---

## 3. The Python Data Model — `__dunder__` Methods

Every Python operation maps to a dunder method call. Knowing this lets you design objects that integrate seamlessly with the language.

### Comparison and Hashing

```python
from functools import total_ordering

@total_ordering  # generates missing comparison methods from __eq__ and one of __lt__/__gt__
class Version:
    def __init__(self, major: int, minor: int, patch: int):
        self.major, self.minor, self.patch = major, minor, patch

    def __eq__(self, other):
        if not isinstance(other, Version):
            return NotImplemented  # signal "I don't know how to compare with this type"
        return (self.major, self.minor, self.patch) == (other.major, other.minor, other.patch)

    def __lt__(self, other):
        if not isinstance(other, Version):
            return NotImplemented
        return (self.major, self.minor, self.patch) < (other.major, other.minor, other.patch)

    def __hash__(self):
        return hash((self.major, self.minor, self.patch))

    def __repr__(self):
        return f"Version({self.major}, {self.minor}, {self.patch})"
```

**Critical rule:** If you define `__eq__`, Python sets `__hash__ = None` (making objects unhashable). You must explicitly define `__hash__` if you want the object to be usable in sets/dicts.

**`NotImplemented` vs `NotImplementedError`:**
- `return NotImplemented` from `__eq__`, `__lt__`, etc. → Python tries the reflected operation on the other operand.
- `raise NotImplementedError` → unimplemented abstract method.

### Container Protocol

```python
class RingBuffer:
    def __init__(self, capacity: int):
        self._buf = [None] * capacity
        self._head = 0
        self._size = 0
        self._cap = capacity

    def __len__(self) -> int:
        return self._size

    def __getitem__(self, index: int):
        if index >= self._size:
            raise IndexError(index)
        return self._buf[(self._head + index) % self._cap]

    def __iter__(self):
        for i in range(self._size):
            yield self[i]

    def __contains__(self, item) -> bool:  # overrides default O(n) iteration check
        return any(self[i] == item for i in range(self._size))

    def __bool__(self) -> bool:   # called by if ring_buffer:
        return self._size > 0
```

Key container dunders: `__len__`, `__getitem__`, `__setitem__`, `__delitem__`, `__iter__`, `__next__`, `__contains__`, `__reversed__`.

### `__slots__`

By default, Python objects store attributes in a `__dict__` (a regular dict). `__slots__` replaces this with a fixed-size C-level array:

```python
class Point:
    __slots__ = ('x', 'y')   # no __dict__, only x and y

    def __init__(self, x: float, y: float):
        self.x = x
        self.y = y

# Benefits:
# 1. ~3–5× less memory per instance (no dict overhead)
# 2. Faster attribute access (array index vs dict lookup)
# Costs:
# 1. Cannot add new attributes dynamically
# 2. Inheritance with __slots__ requires careful handling
# 3. __dict__ still exists for the class itself (just not per-instance)
```

**When `__slots__` matters:** Classes with millions of instances (event objects, coordinate points, graph nodes). Memory reduction from 200–300 bytes/instance to 50–80 bytes can be the difference between fitting in memory and not.

---

## 4. The Descriptor Protocol

Descriptors are the mechanism behind `property`, `classmethod`, `staticmethod`, functions-as-methods, and many ORM field definitions. Understanding descriptors is what separates principal from senior.

A **descriptor** is any object that implements `__get__`, `__set__`, or `__delete__`.

```python
class Validator:
    """Non-data descriptor: implements only __get__"""
    def __set_name__(self, owner, name):
        self.public_name = name
        self.private_name = f'_{name}'

    def __get__(self, obj, objtype=None):
        if obj is None:
            return self        # accessed on class, not instance — return descriptor itself
        return getattr(obj, self.private_name, None)

class PositiveValidator(Validator):
    """Data descriptor: implements __get__ and __set__"""
    def __set__(self, obj, value):
        if value <= 0:
            raise ValueError(f"{self.public_name} must be positive, got {value}")
        setattr(obj, self.private_name, value)

class Order:
    quantity = PositiveValidator()
    price = PositiveValidator()

    def __init__(self, quantity: int, price: float):
        self.quantity = quantity   # calls PositiveValidator.__set__
        self.price = price         # calls PositiveValidator.__set__

order = Order(10, 29.99)
order.quantity  # calls PositiveValidator.__get__ → 10
order.quantity = -1  # raises ValueError
```

**Lookup order for `obj.attr`:**

1. **Data descriptor** (`__get__` + `__set__` or `__delete__`) in class/MRO → wins over instance `__dict__`
2. Instance `__dict__`
3. **Non-data descriptor** (`__get__` only) or class attribute

`property` is a data descriptor (has both `__get__` and `__set__`). That's why `@property` works even though instance `__dict__` has no entry for it — the descriptor wins.

### How `@property` Is Implemented

```python
# property is roughly equivalent to this descriptor:
class property:
    def __init__(self, fget=None, fset=None, fdel=None):
        self.fget = fget
        self.fset = fset
        self.fdel = fdel

    def __get__(self, obj, objtype=None):
        if obj is None:
            return self
        return self.fget(obj)

    def __set__(self, obj, value):
        if self.fset is None:
            raise AttributeError("can't set attribute")
        self.fset(obj, value)

    def setter(self, fset):
        return type(self)(self.fget, fset, self.fdel)
```

### How Instance Methods Work

When you access `obj.method`, Python calls `Function.__get__(obj, type(obj))`, which returns a **bound method** — a closure that prepends `obj` as `self`.

```python
class MyClass:
    def greet(self): return "hello"

obj = MyClass()
obj.greet         # <bound method MyClass.greet of <MyClass object>>
MyClass.greet     # <function MyClass.greet at 0x...> — unbound
MyClass.greet(obj)  # equivalent to obj.greet()
```

---

## 5. Method Resolution Order (MRO) — C3 Linearization

Python uses **C3 linearization** to determine method lookup order in multiple inheritance. Understanding this is critical for framework code and complex class hierarchies.

```python
class A:
    def method(self): return "A"

class B(A):
    def method(self): return "B"

class C(A):
    def method(self): return "C"

class D(B, C):
    pass

D.__mro__  # (D, B, C, A, object)
D().method()  # "B" — B comes first in MRO
```

**C3 algorithm rule:** Left-to-right, depth-first, with the constraint that a class always appears after all its parents, and the order from each parent's perspective is preserved.

**The diamond problem resolved:**

```python
# Python resolves this correctly — A appears once at the end
# D → B → C → A → object  (not D → B → A → C → A)
```

**`super()` follows MRO:**

```python
class Base:
    def process(self):
        print("Base")

class Mixin:
    def process(self):
        print("Mixin")
        super().process()  # calls next in MRO, not necessarily Base

class Service(Mixin, Base):
    def process(self):
        print("Service")
        super().process()   # calls Mixin.process (next in MRO)

Service().process()
# Service → Mixin → Base
```

**Cooperative multiple inheritance with `super()`:** Every class in the chain should call `super()`, even the "base" classes. This ensures the full MRO chain is traversed.

---

## 6. Metaclasses

A metaclass is the class of a class. `type` is the default metaclass — it creates classes.

```python
# These are equivalent:
class MyClass:
    x = 42

MyClass = type('MyClass', (object,), {'x': 42})
```

### Writing a Metaclass

```python
class SingletonMeta(type):
    _instances: dict = {}

    def __call__(cls, *args, **kwargs):
        if cls not in cls._instances:
            cls._instances[cls] = super().__call__(*args, **kwargs)
        return cls._instances[cls]

class DatabasePool(metaclass=SingletonMeta):
    def __init__(self):
        self.connections = []

db1 = DatabasePool()
db2 = DatabasePool()
db1 is db2  # True — same instance
```

### `__init_subclass__` — Lighter Alternative to Metaclasses

For most use cases (auto-registration, validation of subclasses), `__init_subclass__` is sufficient and simpler:

```python
class PluginBase:
    _registry: dict[str, type] = {}

    def __init_subclass__(cls, name: str, **kwargs):
        super().__init_subclass__(**kwargs)
        PluginBase._registry[name] = cls
        print(f"Registered plugin: {name}")

class JsonPlugin(PluginBase, name="json"):
    def process(self, data): return json.dumps(data)

class CsvPlugin(PluginBase, name="csv"):
    def process(self, data): return to_csv(data)

PluginBase._registry  # {'json': JsonPlugin, 'csv': CsvPlugin}
```

### `__class_getitem__` — Supporting Generic Syntax

```python
class Stack:
    def __class_getitem__(cls, item):
        return f"Stack[{item}]"   # minimal: just return annotation string

# For actual runtime behavior (like Pydantic does):
class TypedStack:
    def __class_getitem__(cls, item):
        return type(f"TypedStack[{item.__name__}]", (cls,), {'_type': item})

IntStack = TypedStack[int]
IntStack._type  # <class 'int'>
```

---

## Interview Q&A

### Q1 `[Principal]` The GIL allows CPython to avoid most internal locking. What are the two scenarios where Python code can still have race conditions despite the GIL?

**Answer:**

The GIL ensures bytecode executes atomically at the bytecode level, but a single Python statement can compile to multiple bytecodes, and the GIL can be released between them.

**Scenario 1 — Compound operations (check-then-act):**

```python
# NOT thread-safe despite the GIL
if key not in cache:             # bytecode: LOAD, SUBSCR, ...
    cache[key] = compute(key)    # GIL can be released between these two lines

# Thread 1: checks key not in cache → True
# GIL switches to Thread 2
# Thread 2: checks key not in cache → True, computes and stores
# GIL switches to Thread 1
# Thread 1: computes and stores (overwrites Thread 2's result, or computes twice)
```

**Scenario 2 — Operations on mutable shared objects from C extensions that release the GIL:**

```python
import numpy as np

arr = np.zeros(1_000_000)

def worker():
    arr[:] += 1  # NumPy releases GIL during this C operation

# Two threads calling worker() simultaneously: data race inside NumPy
# The GIL is not held during the C-level += operation
```

**Fix:** Use `threading.Lock` for shared state, or design with immutable objects and message passing (Queue). For numpy, use per-thread arrays or process-level isolation.

---

### Q2 `[Principal]` Explain the descriptor lookup order. If both an instance `__dict__` entry and a class-level descriptor with `__set__` exist for the same attribute name, which wins?

**Answer:**

**Data descriptor wins over instance `__dict__`.**

The lookup order for `obj.attr`:
1. **Data descriptor** in `type(obj).__mro__` (any class with `__set__` or `__delete__`) — highest priority
2. Instance `__dict__` (the per-object attribute store)
3. **Non-data descriptor** (class attribute with only `__get__`, like a plain function) or class variable

`property` is a data descriptor (it defines both `__get__` and `__set__` even if the setter raises `AttributeError`). So:

```python
class Account:
    @property
    def balance(self) -> float:
        return self._balance

    @balance.setter
    def balance(self, value: float):
        if value < 0:
            raise ValueError
        self._balance = value

acc = Account()
acc.__dict__['balance'] = 999  # bypass the property — write directly to instance __dict__
acc.balance  # still calls the property getter — NOT 999
# Data descriptor wins over __dict__
```

This is why ORMs use data descriptors for field definitions — accessing `instance.field_name` always goes through the ORM descriptor regardless of what's in `__dict__`.

---

### Q3 `[Principal]` `__slots__` reduces memory. Describe the exact failure mode when you define `__slots__` in a subclass but not the parent.

**Answer:**

If a parent class does NOT define `__slots__`, it has a `__dict__`. The subclass defining `__slots__` still inherits the parent's `__dict__` — so every instance still has a `__dict__`, negating the memory saving from slots:

```python
class Base:
    # No __slots__ — has __dict__
    def __init__(self):
        self.x = 1

class Child(Base):
    __slots__ = ('y',)  # USELESS: Base has __dict__, Child inherits it

import sys
c = Child()
sys.getsizeof(c)  # same as without __slots__ — __dict__ is still there
hasattr(c, '__dict__')  # True — inherited from Base
```

**Full `__slots__` hierarchy requires every class in the chain to define `__slots__`:**

```python
class Base:
    __slots__ = ('x',)

class Child(Base):
    __slots__ = ('y',)  # only 'y' here; 'x' is already in Base.__slots__

c = Child()
c.x = 1  # works — inherited slot
c.y = 2  # works — own slot
c.z = 3  # AttributeError — no __dict__, no z slot
hasattr(c, '__dict__')  # False — memory savings achieved
```

**Second failure mode — multiple inheritance with slots:**

```python
class A:
    __slots__ = ('x',)

class B:
    __slots__ = ('y',)

class C(A, B):
    __slots__ = ()  # empty slots — inherits A and B slots

c = C()
c.x = 1  # works
c.y = 2  # works

# But if both A and B define the same slot name, C has the slot twice
# (CPython allows this but wastes memory and confuses descriptor lookup)
```

---

### Q4 `[Principal]` Design a thread-safe, lazily-initialized singleton in Python without using a metaclass. What are the two race conditions in the naive implementation and how do you fix them?

**Answer:**

```python
# Naive — two race conditions:
class Config:
    _instance = None

    @classmethod
    def get_instance(cls):
        if cls._instance is None:           # Race 1: two threads both see None
            cls._instance = cls()           # Race 2: assignment is not atomic
        return cls._instance
```

**Race 1 (check-then-act):** Two threads both evaluate `_instance is None` as `True` and both call `cls()`, creating two instances. One gets discarded — or worse, both are used.

**Race 2 (partial visibility):** In CPython, object creation (`cls()`) involves multiple steps. Another thread could see `_instance` as non-None but not fully initialized (less likely in CPython due to GIL, but a real concern with free-threaded builds).

**Fix — double-checked locking with a lock:**

```python
import threading

class Config:
    _instance = None
    _lock = threading.Lock()

    def __new__(cls):
        if cls._instance is None:          # First check (no lock — fast path)
            with cls._lock:
                if cls._instance is None:  # Second check (under lock — safe)
                    cls._instance = super().__new__(cls)
        return cls._instance

    def __init__(self):
        if not hasattr(self, '_initialized'):
            self.settings = load_settings()
            self._initialized = True
```

**Simpler Python idiom using module-level singleton:**

Python module import is thread-safe (the import lock). A module-level object is a singleton:

```python
# config.py
class _Config:
    def __init__(self):
        self.settings = load_settings()

config = _Config()  # created once at import time, thread-safe
```

```python
# usage
from config import config  # always the same instance
```

This is the idiomatic Python way — avoid over-engineering with metaclasses for the singleton pattern.

---

*See also:* [02-concurrency-and-asyncio.md](02-concurrency-and-asyncio.md) for GIL release in asyncio | [03-type-system.md](03-type-system.md) for `__class_getitem__` and generic types
