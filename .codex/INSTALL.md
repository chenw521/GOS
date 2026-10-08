# Installing GOS for Codex

## Install

```bash
npm i -g github:chenw521/GOS
gos setup          # detects Codex, symlinks skills to ~/.agents/skills/gos
```

Restart Codex, then ask: "list your gos skills".

## Update / Uninstall

```bash
npm update -g github:chenw521/GOS
gos teardown && npm uninstall -g gos
```

## Tool mapping

- `todowrite` → manual task list in your response
- `skill` → read SKILL.md from ~/.agents/skills/gos/
- `gos` CLI commands (gate/status/commit) → run via shell; same hard gates
