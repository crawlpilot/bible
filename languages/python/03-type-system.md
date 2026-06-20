# 03 — Type System and Typing

**Calibration:** Principal Engineer bar — Google / Meta / Amazon  
**Focus:** Python's gradual type system, generics at runtime, `Protocol` for structural subtyping, and `dataclasses` vs alternatives. At principal level: design decisions around typing, not just annotation syntax.

---

## 1. Gradual Typing — The Mental Model

Python's type system is **gradual** — you opt into static type checking per module/file. `Any` is the escape hatch that disables checking.

```
Untyped <————————————————————————> Fully typed
def f(x):        def f(x: Any):       def f(x: int) -> str:
  return x + 1     return x + 1         return str(x + 1)
```

**`Any` is both a supertype and subtype of everything** — it's the "unknown" type. A function accepting `Any` can receive anything; a return value of `Any` can be used anywhere. This is how old unannotated code interoperates with annotated code without errors.

---

## 2. Core Annotation Types

```python
from typing import Optional, Union, Literal, Final, ClassVar
from collections.abc import Sequence, Mapping, Callable, Iterator, Generator

# Python 3.10+ union syntax — prefer over Union[X, Y]
def process(data: int | str | None) -> str | None:
    ...

# Python 3.9+ generic built-ins — prefer over typing.List, typing.Dict
def batch(items: list[int], size: int) -> list[list[int]]:
    ...

def lookup(mapping: dict[str, list[int]], key: str) -> list[int]:
    ...

# Callable — (argument types) -> return type
Processor = Callable[[str, int], bool]

# Final — cannot be reassigned
MAX_CONNECTIONS: Final = 100
MAX_CONNECTIONS = 200  # mypy error

# ClassVar — class-level variable (not instance)
class Config:
    instances: ClassVar[list['Config']] = []
    name: str
```

### Structural Subtyping — `Protocol`

`Protocol` implements **structural subtyping** (duck typing made explicit). An object satisfies a `Protocol` if it has the required attributes/methods — no inheritance needed.

```python
from typing import Protocol, runtime_checkable

@runtime_checkable
class Drawable(Protocol):
    def draw(self) -> None: ...
    def bounds(self) -> tuple[int, int, int, int]: ...

# Any class with draw() and bounds() satisfies Drawable — even third-party classes
class Circle:
    def draw(self) -> None: print("circle")
    def bounds(self): return (0, 0, 100, 100)

class Square:
    def draw(self) -> None: print("square")
    def bounds(self): return (10, 10, 50, 50)

def render_all(shapes: list[Drawable]) -> None:
    for shape in shapes:
        shape.draw()

# Both work without inheriting from Drawable
render_all([Circle(), Square()])

# @runtime_checkable enables isinstance checks:
isinstance(Circle(), Drawable)  # True
```

**`Protocol` vs `ABC`:**

| Aspect | `Protocol` | `ABC` |
|--------|-----------|-------|
| Subtyping style | Structural (implicit, duck typing) | Nominal (explicit inheritance) |
| Third-party types | Yes — they satisfy Protocol without changes | No — they must inherit from ABC |
| `isinstance` check | Only with `@runtime_checkable` (method presence only) | Full support |
| Abstract enforcement | At static type-check time only (without `@runtime_checkable`) | At instantiation time |
| Use case | Accepting any object that "looks like" a type | Defining a family of related classes |

---

## 3. Generics — `TypeVar`, `Generic`, `ParamSpec`

```python
from typing import TypeVar, Generic, ParamSpec, Concatenate
from collections.abc import Callable

T = TypeVar('T')
K = TypeVar('K')
V = TypeVar('V')

# Generic class
class Stack(Generic[T]):
    def __init__(self) -> None:
        self._items: list[T] = []

    def push(self, item: T) -> None:
        self._items.append(item)

    def pop(self) -> T:
        return self._items.pop()

    def peek(self) -> T:
        return self._items[-1]

int_stack: Stack[int] = Stack()
int_stack.push(42)
int_stack.push("string")  # mypy error — expected int
```

### Bounded TypeVar

```python
from typing import TypeVar
from numbers import Number

Numeric = TypeVar('Numeric', int, float, complex)  # restricted to these types

def add(a: Numeric, b: Numeric) -> Numeric:
    return a + b

# Or with bound (any subtype of Number):
N = TypeVar('N', bound=Number)
def scale(value: N, factor: float) -> N:
    return type(value)(value * factor)  # type: ignore
```

### `ParamSpec` — Typing Decorators That Preserve Signatures

```python
from typing import ParamSpec, TypeVar
from collections.abc import Callable
import functools

P = ParamSpec('P')
R = TypeVar('R')

def retry(max_attempts: int) -> Callable[[Callable[P, R]], Callable[P, R]]:
    def decorator(func: Callable[P, R]) -> Callable[P, R]:
        @functools.wraps(func)
        def wrapper(*args: P.args, **kwargs: P.kwargs) -> R:
            for attempt in range(max_attempts):
                try:
                    return func(*args, **kwargs)
                except Exception:
                    if attempt == max_attempts - 1:
                        raise
        return wrapper
    return decorator

@retry(max_attempts=3)
def fetch(url: str, timeout: int = 30) -> bytes:
    ...

# mypy knows fetch still has signature (url: str, timeout: int = 30) -> bytes
```

### `TypedDict` — Typed Dictionaries

```python
from typing import TypedDict, NotRequired, Required

class UserDict(TypedDict):
    id: int
    name: str
    email: str
    role: NotRequired[str]   # optional key (Python 3.11+: NotRequired)

class AdminDict(UserDict, total=False):  # total=False: all keys optional
    permissions: list[str]

def create_user(data: UserDict) -> None:
    user_id = data['id']   # typed — mypy knows it's int

# TypedDict vs dataclass:
# TypedDict: for dict-shaped data (API payloads, JSON, database rows)
# dataclass: for objects with methods and behavior
```

---

## 4. `dataclasses` — Python's First-Class Data Container

```python
from dataclasses import dataclass, field, KW_ONLY
from typing import ClassVar

@dataclass(order=True, frozen=True)  # frozen=True → immutable, hashable
class Point:
    x: float
    y: float

    def distance_to(self, other: 'Point') -> float:
        return ((self.x - other.x)**2 + (self.y - other.y)**2) ** 0.5

p1 = Point(1.0, 2.0)
p2 = Point(3.0, 4.0)
p1 < p2    # True — lexicographic comparison (order=True generates __lt__ etc.)
hash(p1)   # works — frozen=True makes it hashable
p1.x = 5.0  # FrozenInstanceError — immutable
```

### Field Options

```python
from dataclasses import dataclass, field

@dataclass
class Order:
    order_id: str
    items: list[str] = field(default_factory=list)  # mutable default — MUST use factory
    metadata: dict = field(default_factory=dict)
    _internal: str = field(default="", repr=False, compare=False, init=False)

    # KW_ONLY (Python 3.10+) — all following fields are keyword-only
    KW_ONLY
    priority: int = 1

    def __post_init__(self):
        # Runs after __init__ — for validation, derived fields
        if not self.order_id:
            raise ValueError("order_id cannot be empty")
        self._internal = f"order-{self.order_id}"

# Common pitfall:
@dataclass
class BadConfig:
    items: list = []  # WRONG — shared mutable default!
    # All BadConfig instances share the same list object
```

### `dataclass` vs Alternatives

| Feature | `dataclass` | `NamedTuple` | `TypedDict` | `attrs` | Pydantic |
|---------|------------|-------------|-------------|---------|---------|
| Mutability | Mutable by default (`frozen=True` for immutable) | Immutable | Mutable dict | Both | Both |
| Inheritance | Standard class inheritance | Limited (tuple) | Limited | Better | Better |
| Validation | In `__post_init__` only | None | None | `validators=` | Full validation |
| Serialization | Manual | `_asdict()` | Manual | Optional | Built-in |
| Runtime type checking | No | No | No | Optional | Yes |
| Performance | Fast | Tuple-fast | Dict | Fast | Slower (validation) |
| Use case | Domain objects, DTOs | Lightweight, hashable | API/JSON shapes | Complex domain objects | API serialization/validation |

---

## 5. Type Narrowing and Guards

```python
from typing import TypeGuard

def is_list_of_strings(val: list[object]) -> TypeGuard[list[str]]:
    return all(isinstance(x, str) for x in val)

def process(items: list[object]):
    if is_list_of_strings(items):
        # mypy knows items is list[str] here
        for item in items:
            print(item.upper())  # safe — mypy knows it's str
```

```python
from typing import assert_never

def handle(value: int | str | bool):
    match value:
        case int():
            process_int(value)
        case str():
            process_str(value)
        case bool():
            process_bool(value)
        case _ as unreachable:
            assert_never(unreachable)  # mypy error if there's an unhandled case
```

---

## 6. Runtime Type Information — `get_type_hints`, `__annotations__`

```python
import typing
from typing import get_type_hints

class User:
    id: int
    name: str
    email: str

# __annotations__ gives the raw annotation dict (strings if forward refs)
User.__annotations__   # {'id': <class 'int'>, 'name': <class 'str'>, 'email': <class 'str'>}

# get_type_hints resolves forward references, evaluates PEP 563 string annotations
get_type_hints(User)   # {'id': int, 'name': str, 'email': str}

# PEP 563 (from __future__ import annotations) makes all annotations strings:
from __future__ import annotations

class Node:
    def next(self) -> Node:  # 'Node' is a string at runtime — avoids NameError for forward refs
        ...

# PEP 649 (Python 3.14) — lazy evaluation replaces PEP 563
# Annotations only evaluated when accessed — no from __future__ needed
```

---

## 7. `typing.overload` — Multiple Signatures

```python
from typing import overload

@overload
def parse(data: str) -> dict: ...
@overload
def parse(data: bytes) -> dict: ...
@overload
def parse(data: list[str]) -> list[dict]: ...

def parse(data):
    if isinstance(data, str):
        return json.loads(data)
    elif isinstance(data, bytes):
        return json.loads(data.decode())
    else:
        return [json.loads(item) for item in data]

# Callers get type-specific return type inference:
result: dict = parse('{"key": "value"}')
results: list[dict] = parse(['{"a":1}', '{"b":2}'])
```

---

## Interview Q&A

### Q1 `[Principal]` `Protocol` uses structural subtyping. What are the two categories of bugs it can miss that nominal subtyping (ABC) catches, and when is each approach the right choice architecturally?

**Answer:**

**Bug 1 — Accidentally satisfied protocols:**

```python
class Saveable(Protocol):
    def save(self) -> None: ...

class HttpRequest:
    def save(self) -> None:
        print("saving request to log")

# HttpRequest accidentally satisfies Saveable — but it's not a domain entity!
def persist(entity: Saveable) -> None:
    entity.save()

persist(HttpRequest())  # Runs! No type error. But semantically wrong.
```

With ABC, `HttpRequest` would need to explicitly `class HttpRequest(Saveable)` — which forces the developer to think about whether the relationship is intended.

**Bug 2 — Silent interface drift:**

If `Saveable.save()` changes signature to `save(self, context: Context) -> None`, all existing implementations of `Saveable` silently stop satisfying the protocol. With ABC, they would fail at instantiation (abstract method not implemented) or in the IDE.

**When to use each:**

| Use `Protocol` | Use `ABC` |
|---------------|----------|
| Accepting third-party types you don't control | Defining a family you own and control |
| "Any object that can be iterated" | "All domain entities must implement save/load" |
| IO-like adapters: anything with read()/write() | Plugin system: all plugins must be registered and validated |
| Where explicit coupling would be over-engineering | Where explicit coupling documents intent |

---

### Q2 `[Principal]` `from __future__ import annotations` is deprecated in Python 3.14. Explain what it does, why it was introduced, and what replaces it.

**Answer:**

**What it does (PEP 563, Python 3.7+):** Changes all annotations from evaluated expressions to **strings** at runtime. `def f(x: User) -> None` becomes `def f(x: 'User') -> None` at the bytecode level. This enables:
1. Forward references: `def node(self) -> Node` works even before `Node` is defined.
2. Import time cost: no Python objects created for annotations at import.

```python
from __future__ import annotations

class Node:
    left: Node   # would fail without __future__ — Node not yet defined
    right: Node
```

**Why it was controversial:** Tools that inspect annotations at runtime (`dataclasses`, Pydantic, FastAPI, SQLAlchemy) had to call `get_type_hints(obj, localns=..., globalns=...)` to evaluate the strings — fragile with certain scoping patterns. Pydantic v2 had to add significant workarounds.

**Replacement — PEP 649 (Python 3.14):** **Lazy evaluation**. Annotations are stored as unevaluated code objects, evaluated only when accessed (via `typing.get_annotations()`). No string conversion — the original expression is preserved, evaluated on demand. Forward references work naturally. No breakage for runtime tools.

```python
# Python 3.14: no __future__ needed
class Node:
    left: Node    # works — evaluated lazily when Node is fully defined
```

---

### Q3 `[Principal]` Design a type-safe, serializable event system in Python using `dataclasses` and `Protocol`. Support at least 3 event types and a subscriber pattern where handlers are type-checked per event type.

**Answer:**

```python
from __future__ import annotations
from dataclasses import dataclass, asdict
from typing import Protocol, TypeVar, Generic, Callable
from collections import defaultdict
import json

# Base event marker
@dataclass
class Event:
    def to_json(self) -> str:
        return json.dumps(asdict(self))

# Concrete event types
@dataclass
class UserCreated(Event):
    user_id: int
    email: str

@dataclass
class OrderPlaced(Event):
    order_id: str
    user_id: int
    total: float

@dataclass
class PaymentFailed(Event):
    order_id: str
    reason: str

# Type-safe handler protocol
E = TypeVar('E', bound=Event)

class EventHandler(Protocol[E]):
    def handle(self, event: E) -> None: ...

# Type-safe event bus
class EventBus:
    def __init__(self):
        self._handlers: dict[type, list[Callable]] = defaultdict(list)

    def subscribe(self, event_type: type[E], handler: Callable[[E], None]) -> None:
        self._handlers[event_type].append(handler)

    def publish(self, event: Event) -> None:
        for handler in self._handlers.get(type(event), []):
            handler(event)

# Usage — type-checked by mypy
bus = EventBus()

def on_user_created(event: UserCreated) -> None:
    print(f"Welcome email to {event.email}")

def on_order_placed(event: OrderPlaced) -> None:
    print(f"Order {event.order_id} for user {event.user_id}, total: {event.total}")

bus.subscribe(UserCreated, on_user_created)
bus.subscribe(OrderPlaced, on_order_placed)

bus.publish(UserCreated(user_id=1, email="alice@example.com"))
bus.publish(OrderPlaced(order_id="ORD-001", user_id=1, total=99.99))

# Serialization built-in via dataclasses.asdict:
event = OrderPlaced(order_id="ORD-001", user_id=1, total=99.99)
json_str = event.to_json()  # {"order_id": "ORD-001", "user_id": 1, "total": 99.99}
```

**Principal-level extension:** Add a discriminated union for deserialization:

```python
EVENT_REGISTRY: dict[str, type[Event]] = {
    'UserCreated': UserCreated,
    'OrderPlaced': OrderPlaced,
    'PaymentFailed': PaymentFailed,
}

def deserialize_event(data: str) -> Event:
    payload = json.loads(data)
    event_type = payload.pop('__type__')
    cls = EVENT_REGISTRY[event_type]
    return cls(**payload)
```

---

*See also:* [01-language-internals.md](01-language-internals.md) for descriptor protocol (which properties and dataclass fields use) | [04-functional-patterns.md](04-functional-patterns.md) for decorators used with type annotations
