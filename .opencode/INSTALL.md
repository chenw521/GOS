# Installing GOS

## Prerequisites

- Node.js ≥ 20 (per package.json engines)

## Install (all platforms, including Windows)

```bash
npm i -g github:chenw521/GOS
gos setup          # register skills for detected assistants
```

Restart your AI assistant, then verify: ask it to "list your gos skills".

## What `gos setup` does

| Platform | Action |
|:---|:---|
| OpenCode | Symlinks `skills/` → `~/.config/opencode/skills/gos` |
| Codex | Symlinks `skills/` → `~/.agents/skills/gos` |
| Claude Code | Symlinks each skill → `~/.claude/skills/gos-*` |

Windows uses junctions automatically when symlinks need elevation.

## OpenCode alternative: plugin mode (zero CLI)

Add to `opencode.json`:
```json
{ "plugin": ["gos@git+https://github.com/chenw521/GOS.git"] }
```
Plugin mode registers skills only. The `gos` CLI (gates/status/commits)
requires the npm install above — recommended for weak-model hard gates.

## Local development mode

```bash
git clone https://github.com/chenw521/GOS && cd GOS
gos setup --local            # symlink from CWD; edits apply instantly
```

## Update / Uninstall

```bash
npm update -g github:chenw521/GOS
# uninstall:
gos teardown && npm uninstall -g gos
```
