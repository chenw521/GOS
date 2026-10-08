#!/bin/bash
# GOS custom gate example — teaching template, safe to run anywhere.
#
# Semantics: `gos gate all` executes this file. exit 0 = pass; ANY non-zero
# exit BLOCKS the stage (the gate reports FAILED). Scripts run with your full
# user permissions and the project root as working directory — review any
# gate script before trusting it (`gos gate trust check.sh`).
#
# Tip: print WHY the check failed before exiting non-zero — the gate output
# shows the last lines of the script's stdout+stderr.

# --- Check 1 (ACTIVE): block accidentally staged private key material ---
# Scans only files currently staged in the git index (git diff --cached).
# Nothing staged, or no key headers found -> this check passes.
found=""
while IFS= read -r -d '' f; do
  if grep -q -E -- 'BEGIN (RSA |DSA |EC |OPENSSH )?PRIVATE KEY' "$f" 2>/dev/null; then
    found="$found
    $f"
  fi
done < <(git diff --cached --name-only -z 2>/dev/null)
if [ -n "$found" ]; then
  echo "✗ private key material is staged:$found" >&2
  echo "  unstage it (git restore --staged <file>) and ROTATE the key if it was ever pushed" >&2
  exit 1
fi

# --- Check 2 (COMMENTED example): require a green test suite on every gate ---
# Uncomment to make `gos gate all` run your tests and block on failure:
# npm test --silent || { echo "✗ npm test failed"; exit 1; }

exit 0
