# Sweep ledger audit receipt

Terminal state after six harness batches (bin core/task/knowledge,
bin ops/map/nav/render + cli entry, test support tree, section suite,
docs/hooks/scripts/skills, remedial fragment pass).

- ledger records: 222 across batches {'batch-1': 22, 'batch-2': 22, 'batch-3': 7, 'batch-4': 102, 'batch-5': 32, 'batch-6': 37}
- distinct paths ledgered: 186
- deleted anchor ids reconciled: 1625
- every record validates as ndjson JSON with the {batch, ts, path, ids[]} key set
- every batch carries one validator-clean [Unreleased] changelog entry
  (changelog lint green, 47 entries validated)
- terminal whitelist: permanent categories only
  {'drift-ledger': 1, 'frozen-string': 80, 'lint-fixture': 3, 'meta-doc-quoting': 3}
- full section suite: 3127 passed, 0 failed (final run on this tree)
- shrink guard vs base: first-landing pass (zero baseline)

## Review repair (2026-10-27)

The ledger extractor recorded prefix characters instead of bare W/T tokens
(capturing-group defect), leaving 795 single-character noise ids and losing
the real tokens. The regex was fixed (non-capturing prefix, token group) and
every record's ids were rebuilt from git history per batch window
(endpoint diff per path, fixed token grammar): 222 records preserved with
their {batch, ts, path} keys, 1611 ids total, zero noise, 786 real tokens
recovered. Anchors swept then restored inside one window (plan-format
fixtures pinned back at batch four and the fragment pass) are absent by
design — the ledger records endpoint truth, matching the current tree.
Full suite after the repair: 3127 passed, 0 failed.
