// ops/auto/limits — single shared constants home for the auto family:
// every constant below is defined exactly once here and consumed through
// sibling namespace requires; no other module declares a local copy.
'use strict';

// Captured-output ceiling for one spawned session (stdout and stderr each).
const SPAWN_MAX_BUFFER = 64 * 1024 * 1024;

// Default breaker limits: consecutive failed spawns (N), stage re-entries
// (K), cumulative spawned sessions (B).
const DEFAULT_LIMITS = { N: 3, K: 5, B: 30 };

// Default wall clock in seconds for one spawn or review round.
const DEFAULT_WALL_SEC = 60 * 60;

// Hard ceiling a runner-side use cap may never exceed.
const HARD_USE_CAP_CEILING = 64;

module.exports = {
  SPAWN_MAX_BUFFER,
  DEFAULT_LIMITS,
  DEFAULT_WALL_SEC,
  HARD_USE_CAP_CEILING,
};
