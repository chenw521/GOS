// nav/registry-consts — registry data surface (const tables co-located here)
'use strict';

const SUBCLASS_OVERRIDES = {
  'lessons.list': 'read',     // B-19: lessons list = read-class
  'concerns.add': 'write',    // metadata-only (dispatch stays read; internal lock)
  'concerns.prune': 'write',  // metadata-only (dispatch stays read; internal lock)
  'changelog.add': 'write',   // metadata-only (dispatch stays read; dedicated lock)
};

// read-class dispatch for `changelog`: `add` mutates CHANGELOG.md + state.json
// under its own .gos/cache/changelog.lock (wait-retry, concurrent adds
// serialize) — the shared .gos/.lock is die-on-contention and must not gate
// concurrent adds (concerns-family pattern).
// Same read-class dispatch for `push`: it mutates only the git remote (one
// aggregate commit), never local .gos state, and git itself serializes
// remote updates — the shared die-on-contention .gos/.lock must not gate it.
const KNOWN_CASES = ['', 'next', 'instructions', 'status', 'init', 'resume', 'stage', 'context', 'checkpoint', 'commit', 'archive', 'setup', 'teardown', 'doctor', '_contract', 'paths', 'gate', 'section', 'resolve-model', 'config', 'trace', 'decision', 'requirement', 'phase', 'anchor', 'render', 'auto', 'approve', 'lessons', 'truth', 'logs', 'gap', 'map', 'concerns', 'changelog', 'feedback', 'push', 'track', 'brownfield', 'help', '--help', '-h', '--version', '-v'];

const WRITE_CMDS = new Set(['init', 'commit', 'archive', 'approve', 'checkpoint', 'config', 'auto', 'stage', 'requirement', 'decision', 'render', 'phase', 'anchor', 'lessons', 'truth', 'gap', 'paths', 'feedback', 'track']);

const READ_CMDS = new Set(['', 'next', 'instructions', 'status', 'resume', 'context', 'trace', 'resolve-model', 'map', 'concerns', 'changelog', 'push', 'logs']);

const EXEC_CMDS = new Set(['gate', 'section']);

// `brownfield` is GLOBAL (not write/exec): like `setup --commitlint` it mutates
// repo files, but guardCwd's .gos/.lock is reserved for task-state commands —
// a brownfield repo has no .gos yet, and the die-on-contention lock would
// break lock-free semantics ( , ).
const GLOBAL_CMDS = new Set(['setup', 'teardown', 'doctor', 'help', '--help', '-h', '--version', '-v', '_contract', 'brownfield']);

module.exports = { SUBCLASS_OVERRIDES, KNOWN_CASES, WRITE_CMDS, READ_CMDS, EXEC_CMDS, GLOBAL_CMDS };
