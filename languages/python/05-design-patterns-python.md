# 05 — Design Patterns in Python

**Calibration:** Principal Engineer bar — Google / Meta / Amazon  
**Focus:** How Python's first-class functions, duck typing, and dynamic nature render classic GoF patterns different — sometimes trivial, sometimes irrelevant, sometimes more expressive.

---

## 1. Creational Patterns

### Singleton — The Right Python Way

```python
# Option 1: Module-level instance (idiomatic Python)
# database.py
class _Database:
    def __init__(self):
        self._pool = create_pool()

db = _Database()  # created once at import

# Consumers: from database import db
```

```python
# Option 2: Metaclass singleton (for class-based API)
class SingletonMeta(type):
    _instances: dict = {}

    def __call__(cls, *args, **kwargs):
        if cls not in cls._instances:
            cls._instances[cls] = super().__call__(*args, **kwargs)
        return cls._instances[cls]

class AppConfig(metaclass=SingletonMeta):
    def __init__(self):
        self.db_url = os.environ['DATABASE_URL']

# Option 3: __new__ override (no metaclass)
class Config:
    _instance = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance
```

### Factory Method — Functions Are First-Class

```python
from abc import ABC, abstractmethod
from typing import Callable

# Python factories don't need Factory classes — use callable objects or functions
def create_parser(format: str):
    parsers = {
        'json': JsonParser,
        'csv': CsvParser,
        'xml': XmlParser,
    }
    cls = parsers.get(format)
    if cls is None:
        raise ValueError(f"Unknown format: {format}")
    return cls()

# Or with a registry pattern:
_parsers: dict[str, type] = {}

def register_parser(format: str):
    def decorator(cls):
        _parsers[format] = cls
        return cls
    return decorator

@register_parser('json')
class JsonParser:
    def parse(self, data: str): return json.loads(data)

@register_parser('csv')
class CsvParser:
    def parse(self, data: str): ...

# Runtime lookup:
parser = _parsers['json']()
```

### Abstract Factory — Using `Protocol` and `ABC`

```python
from abc import ABC, abstractmethod

class Button(ABC):
    @abstractmethod
    def render(self) -> str: ...

class Dialog(ABC):
    @abstractmethod
    def create_button(self) -> Button: ...
    @abstractmethod
    def show(self) -> None: ...

class WindowsButton(Button):
    def render(self) -> str: return "<WinButton/>"

class WindowsDialog(Dialog):
    def create_button(self) -> Button:
        return WindowsButton()
    def show(self) -> None:
        btn = self.create_button()
        print(f"Windows dialog with {btn.render()}")

# Protocol alternative — no inheritance required:
from typing import Protocol

class ButtonProtocol(Protocol):
    def render(self) -> str: ...
```

---

## 2. Structural Patterns

### Decorator — Python's `@` Syntax IS the Decorator Pattern

```python
# The Decorator GoF pattern and Python's @decorator are the same concept:
# Both wrap an object/function to add behavior transparently

import functools

# Function decorator (behavioral addition):
def log_calls(func):
    @functools.wraps(func)
    def wrapper(*args, **kwargs):
        print(f"Calling {func.__name__} with {args}, {kwargs}")
        result = func(*args, **kwargs)
        print(f"{func.__name__} returned {result}")
        return result
    return wrapper

# Class-based decorator (for stateful decoration):
class Retry:
    def __init__(self, func, max_attempts: int = 3):
        functools.update_wrapper(self, func)
        self.func = func
        self.max_attempts = max_attempts

    def __call__(self, *args, **kwargs):
        for attempt in range(self.max_attempts):
            try:
                return self.func(*args, **kwargs)
            except Exception:
                if attempt == self.max_attempts - 1:
                    raise
```

### Proxy — `__getattr__` for Transparent Wrapping

```python
class LazyLoader:
    """Proxy that loads the real object on first access"""

    def __init__(self, loader_func):
        object.__setattr__(self, '_loader', loader_func)
        object.__setattr__(self, '_obj', None)

    def _load(self):
        obj = object.__getattribute__(self, '_obj')
        if obj is None:
            loader = object.__getattribute__(self, '_loader')
            obj = loader()
            object.__setattr__(self, '_obj', obj)
        return obj

    def __getattr__(self, name):
        return getattr(self._load(), name)

    def __setattr__(self, name, value):
        setattr(self._load(), name, value)

# Usage:
config = LazyLoader(lambda: ExpensiveConfig())
config.db_url   # triggers load on first access
```

### Composite — Recursive Data Structures

```python
from abc import ABC, abstractmethod

class FileSystemItem(ABC):
    @abstractmethod
    def size(self) -> int: ...
    @abstractmethod
    def name(self) -> str: ...

class File(FileSystemItem):
    def __init__(self, name: str, size_bytes: int):
        self._name = name
        self._size = size_bytes

    def size(self) -> int: return self._size
    def name(self) -> str: return self._name

class Directory(FileSystemItem):
    def __init__(self, name: str):
        self._name = name
        self._children: list[FileSystemItem] = []

    def add(self, item: FileSystemItem): self._children.append(item)
    def size(self) -> int: return sum(c.size() for c in self._children)
    def name(self) -> str: return self._name
```

### Adapter — Duck Typing Makes It Structural

```python
# Python's duck typing means adapters are often just wrapper functions:

class ThirdPartyLogger:
    def write_log(self, severity, message): ...

class OurAppLogger:
    def log(self, level: str, msg: str): ...

# Adapter:
class LoggerAdapter:
    def __init__(self, third_party: ThirdPartyLogger):
        self._tp = third_party

    def log(self, level: str, msg: str):
        self._tp.write_log(severity=level.upper(), message=msg)

# Or even simpler — use a closure:
def adapt_logger(third_party: ThirdPartyLogger):
    def log(level: str, msg: str):
        third_party.write_log(severity=level.upper(), message=msg)
    return log
```

---

## 3. Behavioral Patterns

### Strategy — Functions as First-Class Citizens

```python
from typing import Callable

# No Strategy interface class needed — functions ARE strategies
Sorter = Callable[[list], list]

def bubble_sort(items: list) -> list: ...
def merge_sort(items: list) -> list: ...
def timsort(items: list) -> list: return sorted(items)   # Python's built-in

class DataPipeline:
    def __init__(self, sort_strategy: Sorter = timsort):
        self._sort = sort_strategy

    def process(self, data: list) -> list:
        return self._sort(data)

# Switch strategies at runtime
pipeline = DataPipeline(sort_strategy=merge_sort)
pipeline._sort = timsort  # replace strategy
```

### Observer — Using Callbacks and `weakref`

```python
import weakref
from typing import Callable

class EventEmitter:
    def __init__(self):
        self._listeners: dict[str, list[weakref.ref]] = {}

    def on(self, event: str, callback: Callable) -> None:
        self._listeners.setdefault(event, []).append(weakref.ref(callback))

    def emit(self, event: str, *args, **kwargs) -> None:
        dead = []
        for ref in self._listeners.get(event, []):
            listener = ref()
            if listener is None:
                dead.append(ref)
            else:
                listener(*args, **kwargs)
        # Clean up dead references
        for ref in dead:
            self._listeners[event].remove(ref)

emitter = EventEmitter()
emitter.on('data', lambda x: print(f"received: {x}"))
emitter.emit('data', 42)
```

### Command Pattern — Dataclasses + Dispatch

```python
from dataclasses import dataclass
from typing import Protocol

class Command(Protocol):
    def execute(self) -> None: ...
    def undo(self) -> None: ...

@dataclass
class CreateFile:
    path: str
    content: str

    def execute(self):
        with open(self.path, 'w') as f:
            f.write(self.content)

    def undo(self):
        os.remove(self.path)

class CommandHistory:
    def __init__(self):
        self._history: list[Command] = []

    def execute(self, cmd: Command) -> None:
        cmd.execute()
        self._history.append(cmd)

    def undo_last(self) -> None:
        if self._history:
            self._history.pop().undo()
```

### Template Method — `ABC` or Functions

```python
from abc import ABC, abstractmethod

class DataExporter(ABC):
    def export(self, data: list[dict]) -> bytes:
        """Template method — defines the skeleton"""
        validated = self.validate(data)
        transformed = self.transform(validated)
        return self.serialize(transformed)

    def validate(self, data: list[dict]) -> list[dict]:
        return [d for d in data if d]  # default implementation

    @abstractmethod
    def transform(self, data: list[dict]) -> list[dict]: ...

    @abstractmethod
    def serialize(self, data: list[dict]) -> bytes: ...

class JsonExporter(DataExporter):
    def transform(self, data): return data   # no-op
    def serialize(self, data): return json.dumps(data).encode()

class CsvExporter(DataExporter):
    def transform(self, data): return [list(d.values()) for d in data]
    def serialize(self, data): return '\n'.join(','.join(map(str, row)) for row in data).encode()
```

### State Machine — `Enum` + `dict` Dispatch

```python
from enum import Enum, auto
from typing import Callable

class OrderStatus(Enum):
    PENDING = auto()
    CONFIRMED = auto()
    SHIPPED = auto()
    DELIVERED = auto()
    CANCELLED = auto()

class Order:
    def __init__(self):
        self.status = OrderStatus.PENDING
        self._transitions: dict[OrderStatus, set[OrderStatus]] = {
            OrderStatus.PENDING: {OrderStatus.CONFIRMED, OrderStatus.CANCELLED},
            OrderStatus.CONFIRMED: {OrderStatus.SHIPPED, OrderStatus.CANCELLED},
            OrderStatus.SHIPPED: {OrderStatus.DELIVERED},
            OrderStatus.DELIVERED: set(),
            OrderStatus.CANCELLED: set(),
        }

    def transition(self, new_status: OrderStatus) -> None:
        if new_status not in self._transitions[self.status]:
            raise ValueError(f"Cannot transition from {self.status} to {new_status}")
        self.status = new_status
```

---

## 4. Python-Specific Patterns

### Mixin Pattern

```python
class TimestampMixin:
    created_at: datetime
    updated_at: datetime

    def save(self):
        self.updated_at = datetime.utcnow()
        super().save()  # cooperative multiple inheritance

class AuditMixin:
    modified_by: str

    def save(self):
        self.modified_by = current_user()
        super().save()

class Order(TimestampMixin, AuditMixin, BaseModel):
    order_id: str
    items: list

# MRO: Order → TimestampMixin → AuditMixin → BaseModel → object
# Order().save() calls: TimestampMixin.save → AuditMixin.save → BaseModel.save
```

### Repository Pattern — Separating Domain from Persistence

```python
from abc import ABC, abstractmethod
from typing import Protocol

# Domain interface (in domain layer)
class UserRepository(Protocol):
    def find_by_id(self, user_id: int) -> 'User | None': ...
    def find_by_email(self, email: str) -> 'User | None': ...
    def save(self, user: 'User') -> None: ...
    def delete(self, user_id: int) -> None: ...

# Infrastructure implementation
class PostgresUserRepository:
    def __init__(self, session: Session):
        self._session = session

    def find_by_id(self, user_id: int) -> 'User | None':
        return self._session.query(UserModel).filter_by(id=user_id).first()

    def save(self, user: 'User') -> None:
        self._session.merge(to_model(user))
        self._session.commit()

# In-memory implementation for tests
class InMemoryUserRepository:
    def __init__(self):
        self._users: dict[int, User] = {}

    def find_by_id(self, user_id: int) -> 'User | None':
        return self._users.get(user_id)

    def save(self, user: 'User') -> None:
        self._users[user.id] = user
```

### Fluent Interface / Builder via Method Chaining

```python
class QueryBuilder:
    def __init__(self, table: str):
        self._table = table
        self._conditions: list[str] = []
        self._order_by: str | None = None
        self._limit: int | None = None

    def where(self, condition: str) -> 'QueryBuilder':
        self._conditions.append(condition)
        return self   # return self for chaining

    def order_by(self, column: str, ascending: bool = True) -> 'QueryBuilder':
        direction = "ASC" if ascending else "DESC"
        self._order_by = f"{column} {direction}"
        return self

    def limit(self, n: int) -> 'QueryBuilder':
        self._limit = n
        return self

    def build(self) -> str:
        sql = f"SELECT * FROM {self._table}"
        if self._conditions:
            sql += f" WHERE {' AND '.join(self._conditions)}"
        if self._order_by:
            sql += f" ORDER BY {self._order_by}"
        if self._limit:
            sql += f" LIMIT {self._limit}"
        return sql

query = (
    QueryBuilder("orders")
    .where("status = 'active'")
    .where("total > 100")
    .order_by("created_at", ascending=False)
    .limit(50)
    .build()
)
```

---

## 5. Anti-Patterns

### God Object / God Module

```python
# Bad: one class/module that does everything
class ApplicationManager:
    def send_email(self): ...
    def process_payment(self): ...
    def generate_report(self): ...
    def manage_users(self): ...
    def handle_inventory(self): ...

# Better: separate responsibilities into distinct classes with clear interfaces
```

### Mutable Default Arguments

```python
# Classic Python gotcha:
def append_to(item, target=[]):  # target is shared across ALL calls
    target.append(item)
    return target

append_to(1)   # [1]
append_to(2)   # [1, 2] — NOT [2]! The same list is reused

# Fix:
def append_to(item, target=None):
    if target is None:
        target = []
    target.append(item)
    return target
```

### Catching Bare `Exception`

```python
# Bad: swallows everything including KeyboardInterrupt, SystemExit
try:
    risky_operation()
except:  # catches BaseException!
    pass

# Also bad: too broad
try:
    risky_operation()
except Exception:  # catches everything
    pass

# Good: catch specific exceptions
try:
    risky_operation()
except (ConnectionError, TimeoutError) as e:
    logger.warning(f"Retrying after: {e}")
    retry()
except ValueError as e:
    logger.error(f"Invalid data: {e}")
    raise
```

### Using Class Where a Function Suffices

```python
# Over-engineered: class with only __init__ and __call__
class Multiplier:
    def __init__(self, factor):
        self.factor = factor
    def __call__(self, x):
        return x * self.factor

# Just use a closure:
def multiplier(factor):
    return lambda x: x * factor

triple = multiplier(3)
triple(10)  # 30

# Classes are justified when: you need multiple methods, state is complex,
# or you want inheritance. Not for a single operation.
```

---

## Interview Q&A

### Q1 `[Principal]` Python's duck typing means Protocols and ABCs serve different roles. Design a plugin system where third-party developers can add plugins without modifying your codebase. Which abstraction do you use and why?

**Answer:**

Use a **registry pattern with `Protocol` for the interface** and a **class decorator for registration**. This allows third-party plugins to satisfy the interface via duck typing (no import of your ABC needed) while the registry provides discoverability.

```python
# plugin_interface.py — published as part of your SDK
from typing import Protocol, runtime_checkable

@runtime_checkable
class DataPlugin(Protocol):
    name: str

    def process(self, data: dict) -> dict: ...
    def validate(self, data: dict) -> bool: ...

# plugin_registry.py
from typing import type_check_only
_plugins: dict[str, DataPlugin] = {}

def register(plugin_class):
    instance = plugin_class()
    if not isinstance(instance, DataPlugin):   # runtime protocol check
        missing = [m for m in ('process', 'validate') if not hasattr(instance, m)]
        raise TypeError(f"Plugin {plugin_class.__name__} missing: {missing}")
    _plugins[instance.name] = instance
    return plugin_class

def get_plugin(name: str) -> DataPlugin:
    return _plugins[name]

# Third-party plugin — no import of your ABC needed
# third_party_plugin.py
from your_sdk import register

@register
class JsonTransformPlugin:
    name = "json_transform"

    def process(self, data: dict) -> dict:
        return {k.lower(): v for k, v in data.items()}

    def validate(self, data: dict) -> bool:
        return isinstance(data, dict)
```

**Why Protocol over ABC here:**
- Third parties don't need to import your ABC — reduces coupling.
- Existing classes that happen to have `process()` and `validate()` can be registered without modification.
- `@runtime_checkable` gives you validation at registration time.

**Why still have a registry (not just duck typing anywhere):** Discoverability — you can enumerate all plugins, validate them at startup, and fail fast if a plugin is missing required methods.

---

### Q2 `[Principal]` Python's `__getattr__` and `__getattribute__` are both attribute access hooks. What is the difference, when is each called, and what are the two production bugs from misusing them?

**Answer:**

**`__getattribute__`:** Called on **every** attribute access — `instance.anything` triggers it. Override carefully.

**`__getattr__`:** Called only when the **normal lookup fails** (attribute not in `__dict__`, not in class, not in MRO). It's the fallback.

```python
class LoggedAccess:
    def __getattr__(self, name):
        # Only called when name is NOT found normally
        print(f"Attribute {name} not found")
        raise AttributeError(name)

class Proxy:
    def __init__(self, obj):
        object.__setattr__(self, '_obj', obj)  # MUST use object.__setattr__ to avoid infinite recursion

    def __getattribute__(self, name):
        # Called for EVERY access — including _obj itself!
        if name.startswith('_'):
            return object.__getattribute__(self, name)  # bypass custom logic for private
        obj = object.__getattribute__(self, '_obj')
        return getattr(obj, name)
```

**Production Bug 1 — Infinite recursion in `__getattribute__`:**

```python
class BadProxy:
    def __getattribute__(self, name):
        print(f"accessing {name}")
        return self._obj  # INFINITE RECURSION: self._obj calls __getattribute__ again!

# Fix: always use object.__getattribute__ to access own attributes:
def __getattribute__(self, name):
    print(f"accessing {name}")
    return object.__getattribute__(self, '_obj')
```

**Production Bug 2 — `__getattr__` masking typos:**

```python
class Config:
    def __init__(self):
        self.database_url = "postgres://..."

    def __getattr__(self, name):
        return None   # return None for missing attributes

config = Config()
url = config.databse_url   # typo! but returns None silently instead of AttributeError
# None is passed to connection pool — confusing downstream error
```

**Fix:** Only define `__getattr__` when dynamic attribute generation is genuinely needed. Document which attributes are dynamically generated and for what pattern.

---

### Q3 `[Principal]` Explain how Python's `__new__` differs from `__init__` and design a pattern where you need `__new__` but not just for singletons.

**Answer:**

`__new__` creates the object (allocates memory, returns the instance). `__init__` initializes it (sets attributes on the already-created instance).

`__new__` receives the class (`cls`) as the first argument; `__init__` receives the already-created instance (`self`).

**Pattern where `__new__` is essential — Value Object canonicalization:**

```python
class Currency(str):
    """Immutable, canonicalized currency code. str subclass."""
    _cache: dict[str, 'Currency'] = {}

    def __new__(cls, code: str):
        code = code.upper().strip()
        if code not in cls._cache:
            instance = super().__new__(cls, code)
            cls._cache[code] = instance
        return cls._cache[code]

    @property
    def symbol(self) -> str:
        return {'USD': '$', 'EUR': '€', 'GBP': '£'}.get(self, '?')

usd1 = Currency('usd')
usd2 = Currency('USD')
usd1 is usd2   # True — same object, canonicalized and cached
usd1 == 'USD'  # True — because Currency inherits from str
```

**Why `__new__` here:** `str` is immutable — you cannot modify it in `__init__`. The actual string value must be set in `__new__` when calling `super().__new__(cls, code)`. Returning a cached instance from `__new__` is what makes the flyweight pattern possible.

**Other `__new__` use cases:**
1. Subclassing immutable built-ins (`int`, `float`, `tuple`, `frozenset`).
2. Returning a different type than the class (factory behavior): `__new__` can return an instance of a completely different class.
3. Object pool pattern: return an existing pooled object instead of creating a new one.

---

*See also:* [01-language-internals.md](01-language-internals.md) for metaclasses and descriptors | [03-type-system.md](03-type-system.md) for `Protocol` and `ABC` type theory | [../java/06-design-patterns-java-idioms.md](../java/06-design-patterns-java-idioms.md) for Java comparison
