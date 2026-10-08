# Coding Standards — Python

> Anchored: PEP 8 — Style Guide for Python Code (PSF License) — https://peps.python.org/pep-0008/ ·
> PEP 257 — Docstring Conventions (PSF License) — https://peps.python.org/pep-0257/
> License: PSF License — https://docs.python.org/3/license.html
> Precedence: where this book conflicts with the anchors, this book wins (see `00-general.md`).

## Part 1 — Anchored baseline (PEP 8 + PEP 257)

### 1.1 Naming

| Element | Convention | Example |
|:---|:---|:---|
| functions, methods, variables | `snake_case` | `parse_config()`, `retry_count` |
| classes, exceptions | `PascalCase` | `HttpClient`, `ParseError` |
| constants (module-level, true constants) | `UPPER_SNAKE_CASE` | `MAX_RETRIES = 3` |
| internal module/class members | `_leading_underscore` | `_cache_dir`, `_normalize()` |
| dunder names | reserved, never invented | `__init__`, `__enter__` — don't coin `__magic__` |

✅

```python
MAX_RETRIES = 3

class TaskRunner:
    def parse_task_id(self, raw: str) -> tuple[str, int] | None:
        ...

def has_pending_work(queue) -> bool:
    ...
```

❌

```python
def ParseTaskId(raw): ...        # PascalCase function
max_retries = 3                  # a true constant in camelCase
class task_runner: ...           # lowercase class
def __validate__(x): ...         # invented dunder
```

### 1.2 Import grouping

One group per source, separated by a blank line, alphabetized inside the
group. The order is fixed: standard library → third-party → local.

✅

```python
import os
import sys

import requests

from myapp import config
from myapp import utils
```

❌

```python
import sys, os                    # multiple imports on one line
import requests, myapp.config     # third-party mixed with local, no grouping
```

Wildcard imports (`from x import *`) are banned outright — they make name
origins untraceable.

### 1.3 Docstrings (PEP 257)

- **One-line summary first.** It fits on one line (≤ 79 chars), ends with a
  period, and states what the object does — as a command, not a description
  of the implementation.
- **Document every public object.** Module, class, public function/method:
  each gets a docstring. Private helpers may go without.
- **Multi-line docstrings: summary line, then a blank line, then the body.**
  The summary must stand alone — tools like `help()` and doc indexers show it
  alone.

✅

```python
def parse_task_id(raw: str) -> tuple[str, int] | None:
    """Parse a task ID string ("p12-t03") into (phase, number).

    Returns None when raw is not a task ID; never raises on bad input —
    callers branch on the None return.
    """
```

❌

```python
def parse_task_id(raw):
    """
    this function takes a raw string and parses it
    into a tuple, note that it may return None
    """                             # no one-line summary; starts with blank line
```

```python
def parse_task_id(raw):
    # parses task ids        # comment used where a docstring belongs
    ...                      # → help() and tooling see nothing
```

### 1.4 Baseline odds and ends from PEP 8

- Indent 4 spaces; never tabs.
- Comparison to `None`: `is None` / `is not None` — never `== None`.
- `isinstance(x, T)` over `type(x) == T`.
- Don't compare booleans to `True`/`False` (`if ok:`, not `if ok == True:`).

## Part 2 — House layer (applies on top of the anchors)

### 2.1 Comments: same discipline as docstrings, minus the ceremony

PEP 257 governs docstrings; the house layer governs every other `#` comment.
The judgment test from `00-general.md` applies: delete the comment — what does
the reader lose? Nothing → delete it.

❌

```python
# iterate over the tasks
for t in tasks:
    ...
# return the result
return result
```

❌ — history and process talk:

```python
# v2 switched to a LRU cache (v1 recomputed every call)
# per option B we retry twice
# T-123: added the None guard
```

✅ — constraint the code cannot express:

```python
# Retry cap is 2: the API rate-limits at 3 failures/min.
# Must return None rather than raise — callers branch on None.
```

### 2.2 Docstrings state contracts, not narration

A docstring body covers: args that are not obvious from names/types, return
shape, raising behavior, and side effects. It does not tell the story of the
implementation or its revisions.

❌

```python
"""Load the config.

This function used to read YAML but now reads JSON. We changed it
because the YAML dependency was removed in the last refactor.
"""
```

✅

```python
"""Load the JSON config at path; exits(1) on a malformed file."""
```

### 2.3 No commented-out code, no ownerless TODOs

Same rules as `00-general.md`: dead code in comments rots — delete it and let
git keep history. Every `TODO` names an owner and an actionable next step
(`# TODO(alice): switch to pooled clients once auth lands`).

### 2.4 No AI-trace phrasing

Docstrings and comments are read by humans first. Assistant-style phrasing
("It is worth noting", "As per the requirement", "Let's"), decision-narration
("per option B"), and ticket anchors (`[REVIEW M1]`, `T-123`) are all banned —
full list and rationale in `00-general.md`.
