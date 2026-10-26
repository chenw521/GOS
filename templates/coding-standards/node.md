# Coding Standards — Node.js / JavaScript

> Anchored: Airbnb JavaScript Style Guide (MIT) — https://github.com/airbnb/javascript ·
> Google JavaScript Style Guide (CC-BY 4.0) — https://google.github.io/styleguide/jsguide.html ·
> JSDoc (Apache-2.0) — https://jsdoc.app/
> Precedence: where this book conflicts with the anchors, this book wins (see `00-general.md`).

## Part 1 — Anchored baseline (Airbnb + Google JS + JSDoc)

### 1.1 Naming

| Element | Case | Example |
|:---|:---|:---|
| variables, functions | `camelCase` | `retryCount`, `parseConfig()` |
| classes, constructors, React components | `PascalCase` | `HttpClient`, `TaskRunner` |
| true constants (bound once, never reassigned) | `UPPER_SNAKE_CASE` | `const MAX_RETRIES = 3;` |
| non-exported module-level helpers | `camelCase` | `function sha16() {}` |

`UPPER_SNAKE_CASE` is reserved for *true constants* — a value fixed for the
whole program run. A variable that merely happens not to change yet stays
`camelCase`.

✅

```js
const MAX_RETRIES = 3;
let attemptsLeft = MAX_RETRIES;
function fetchWithRetry(url) { ... }
class HttpClient { ... }
```

❌

```js
const Attempts_left = 3;      // mixed case, not a recognized convention
const Data = loadConfig();    // PascalCase for a non-constructor
let max_retries = 3;          // snake_case in JS
```

### 1.2 Booleans read as questions

Boolean variables and boolean-returning functions start with `is`, `has`,
`can`, or an equally question-shaped prefix. Call sites then read like prose.

✅

```js
const isValid = isValidUrl(raw);
if (hasPendingWork(queue)) { ... }
function canRetry(err) { ... }
```

❌

```js
const valid = check();        // `if (valid)` reads fine; `valid` alone does not
const flag = process(x);      // flag of what?
function status(d) { ... }    // returns a boolean? a string? a number?
```

### 1.3 Forbidden name suffixes

`data`, `info`, `tmp`, `manager` are banned as name suffixes (and as whole
names). Each one hides the actual meaning behind a generic wrapper.

❌ → ✅

```js
const userData      → const user            // or: userRecord, userFields
const requestInfo   → const requestMeta     // or: requestHeaders
const tmp           → const stagedFile
const fileManager   → const fileStore       // or: fsOps, diskCache
```

### 1.4 JSDoc: contract comments only where the code is non-obvious

JSDoc is a tool for stating *contracts* — parameter and return shapes, thrown
errors, side effects — not a transcription of the signature. If the signature
plus the names already say it, no comment. When it doesn't, be complete.

✅ — the return shape is not derivable from the code:

```js
/**
 * Parse a task ID string ("p12-t03") into its parts.
 * @param {string} raw
 * @returns {{ phase: string, task: string } | null} null when raw is not a task ID.
 */
function parseTaskId(raw) { ... }
```

❌ — pure signature echo:

```js
/**
 * Parse a task id.
 * @param {string} raw - the raw string.
 * @returns {object} the object.
 */
function parseTaskId(raw) { ... }
```

## Part 2 — House layer (applies on top of the anchors)

### 2.1 Comment density: file header ≤ 5 lines, WHY not WHAT

A file header states the module's purpose in at most 5 lines. No changelog, no
author list, no feature narration — git carries all of that.

✅

```js
// map/scan — walk source files and extract fn-level anchors into deps.json.
// Read-only over the work-tree; all output goes through writeAtomicJson.
```

❌

```js
// This file contains various utility functions for the map subsystem.
// It was created in March and extended in April. In this file we will
// find helpers, utils, and some legacy code from the first version...
```

Every other comment in the body must answer *why*, never *what*:

❌

```js
// loop over the files
for (const f of files) { ... }
// return the result
return out;
```

### 2.2 No commented-out code

Delete it. `git log` and the reflog keep every line you will ever need back.
Commented-out code drifts out of sync with the code around it and becomes
unreadable within weeks.

### 2.3 No ownerless TODOs

✅ `// TODO(alice): drop the fallback once api v3 is fully rolled out`
❌ `// TODO fix this`
❌ `// FIXME` (ownerless and vague)

### 2.4 No AI-trace phrasing in comments

Comments are part of the product. The judgment test from `00-general.md`
applies with full force: delete the comment — what does the reader lose?

❌

```js
// It is worth noting that the empty-array case needs handling here
// As per the requirement, we now sort before dedup
// Let's cache the parsed result for performance
// v2 switched to async iterators
// [REVIEW Mn] narrowed the type here
// T-nnn: added the guard clause
// this phase adds a retry guard around the upload
```

✅

```js
// Sort before dedup: dedup only drops adjacent duplicates.
// Parsed ASTs are cached because parse is 40x the cost of the cache hit.
// Uploads retry once: the endpoint drops idle connections mid-transfer.
```

### 2.5 Error messages name the operation

Throw errors that a reader can act on without opening a debugger: what was
being done, with what input, and why it failed.

✅

```js
throw new Error(`parseTaskId: not a task ID (got: ${JSON.stringify(raw)})`);
```

❌

```js
throw new Error('invalid input');   // which input? which operation?
```
