# Coding Standards — Shell (Bash)

> Anchored: Google Shell Style Guide (CC-BY 4.0) — https://google.github.io/styleguide/shellguide.html
> License: CC-BY 4.0 — https://creativecommons.org/licenses/by/4.0/
> Precedence: where this book conflicts with the anchor, this book wins (see `00-general.md`).

## Part 1 — Anchored baseline (Google Shell Style Guide)

### 1.1 Strict mode: `set -euo pipefail`

Every script starts with the shebang and strict mode. A script without them
silently swallows failures and processes garbage.

✅

```bash
#!/usr/bin/env bash
set -euo pipefail
```

❌

```bash
#!/bin/bash
# no strict mode — unset vars expand to "", failed commands don't stop the run
```

`pipefail` matters most: without it, `false | true` exits 0 and the failure
vanishes down the pipe.

### 1.2 Functions over loose script body

Put all logic in named functions; call `main "$@"` at the bottom. Named
functions are testable, traceable in stack traces, and read like a table of
contents.

✅

```bash
main() {
  local input="$1"
  validate "$input"
  process "$input"
}

main "$@"
```

### 1.3 Function comment blocks

Every function of more than a couple of lines gets a block comment stating its
contract: purpose, args, output, and side effects. Use `#` at column 0 above
the function — not inline noise.

✅

```bash
# Usage: deploy_artifact <bucket> <file>
# Uploads <file> to <bucket> and prints the final object URL.
# Exits non-zero if the upload fails; leaves no partial objects.
deploy_artifact() {
  ...
}
```

Keep the comment to the contract. History of changes and task IDs do not
belong here (see `00-general.md`).

### 1.4 Quoting discipline: always `${var}` in double quotes

Bare `$var` breaks on spaces, globs on wildcards, and empties into nothing.
Use `"${var}"` — braces plus double quotes — everywhere, including inside
strings. The only unquoted expansions are those you *want* word-split.

✅

```bash
rm -rf "${build_dir}"
printf '%s\n' "deploying ${env_name} to ${region}"
cp "${src}" "${dst}"
```

❌

```bash
rm -rf $build_dir          # dies when the path contains a space
echo deploying $env_name   # word-splits, no braces
```

Same rule for arrays: `"${items[@]}"`, and for command substitution:
`"$(basename "${f}")"`.

### 1.5 `case` indentation

Indent `case` body two spaces; patterns on their own lines, indented one level;
each clause ends with `;;` on its own line at the statement level.

✅

```bash
case "${lang}" in
  shell)
    lint_shell
    ;;
  node)
    lint_node
    ;;
  *)
    die "unknown language: ${lang}"
    ;;
esac
```

❌

```bash
case $lang in
  shell) lint_shell;;    # patterns and actions jammed onto one line
  node) lint_node;;
esac                     # no default branch either
```

### 1.6 Baseline odds and ends from the anchor

- Local variables: declare with `local` inside functions — never pollute globals.
- `[[ ]]` over `[ ]` for bash conditionals; POSIX sh scripts are the exception.
- Check every external command you depend on; fail loudly with a clear message
  when one is missing.

## Part 2 — House layer (applies on top of the anchor)

### 2.1 No historical or process comments

The anchor's rules for *code* apply; the house adds rules for *comments*.
Before writing any comment in a shell script, apply the judgment test from
`00-general.md`: delete this comment — what does the reader lose?

❌

```bash
# Added the -f flag because the release job kept failing (see incident nn)
# v2: we now rsync instead of cp
# [REVIEW Mn] quieted the shellcheck warning here
# this <task> adds the stale-lock cleanup for the nightly job
rm -rf "${build_dir}"
```

✅

```bash
# Must not fail on a missing dir: the clean step runs before the first build.
# Stale locks are removed up front: a lock outliving its process is garbage.
rm -rf "${build_dir}"
```

### 2.2 Fail with a message, not a mystery

`set -e` stops the run, but a bare exit leaves no clue. Wrap the failure with
one line that names the operation:

✅

```bash
aws s3 cp "${f}" "s3://${bucket}/" || die "upload failed: ${f} -> ${bucket}"
```

### 2.3 No echo-tracing narrated step by step

A script does not narrate itself. Progress output is fine when a human runs
it (`==> building…`); per-line commentary that duplicates what the commands
already print is not.
