// core/sanitize.cjs — spawn-text sanitizer: strips terminal escape
// sequences and control bytes from spawn-originated text, then labels the
// result with the spawn-output marker so render surfaces can distinguish
// worker output from CLI-authored prose. Pure functions, zero dependencies,
// no I/O. API:
//   SPAWN_OUTPUT_MARKER  label prepended by markSpawnOutput ('[spawn]')
//   sanitizeSpawnText(t) strip every escape/control byte; keeps visible
//                        text plus the layout-safe controls TAB and LF
//   markSpawnOutput(t)   prepend the spawn-output marker + one space
//   renderSpawnOutput(t) combined form: markSpawnOutput(sanitizeSpawnText(t))
//                        — the single entry point render surfaces call
'use strict';


const SPAWN_OUTPUT_MARKER = '[spawn]';

// OSC: ESC ] payload (no BEL/ESC inside) closed by BEL or ST (ESC \); a
// trailing unterminated OSC is cut too (chunk-boundary leftovers).
// eslint-disable-next-line no-control-regex
const OSC_RE = /\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b\][^\x07\x1b]*$/g;
// CSI: ESC [ parameter bytes (0x30-0x3f), intermediate bytes (0x20-0x2f),
// final byte (0x40-0x7e) — SGR colors, cursor moves, erase runs.
// eslint-disable-next-line no-control-regex
const CSI_RE = /\x1b\[[\x30-\x3f]*[\x20-\x2f]*[\x40-\x7e]/g;
// Remaining ESC escapes: optional intermediates then one final byte (covers
// Fe forms like ESC 7 / ESC M and nF forms like charset selection ESC ( B).
// Must run AFTER OSC_RE/CSI_RE or their lead bytes get eaten as finals.
// eslint-disable-next-line no-control-regex
const ESC_RE = /\x1b[\x20-\x2f]*[\x30-\x7e]/g;
// Residual controls: every C0 except TAB (0x09) and LF (0x0a) — CR and BEL
// included, they enable overwrite/spoof tricks — plus DEL and C1 bytes.
// eslint-disable-next-line no-control-regex
const CTRL_RE = /[\x00-\x08\x0b-\x1f\x7f\x80-\x9f]/g;

function sanitizeSpawnText(text) {
  return String(text == null ? '' : text)
    .replace(OSC_RE, '')
    .replace(CSI_RE, '')
    .replace(ESC_RE, '')
    .replace(CTRL_RE, '');
}

function markSpawnOutput(text) {
  return `${SPAWN_OUTPUT_MARKER} ${String(text == null ? '' : text)}`;
}

function renderSpawnOutput(text) {
  return markSpawnOutput(sanitizeSpawnText(text));
}

module.exports = {
  SPAWN_OUTPUT_MARKER,
  sanitizeSpawnText,
  markSpawnOutput,
  renderSpawnOutput,
};
