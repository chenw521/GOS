# Installing GOS for Claude Code

## Install

```bash
npm i -g github:chenw521/GOS
gos setup          # detects Claude Code, symlinks 8 skills to ~/.claude/skills/
```

Restart Claude Code, then ask: "list your gos skills".

## Tool mapping

| GOS/OpenCode | Claude Code |
|:---|:---|
| todowrite | TodoWrite |
| skill | Skill |
| read/write/edit | Read/Write/Edit |
| bash | Bash |

## Update / Uninstall

```bash
npm update -g github:chenw521/GOS
gos teardown && npm uninstall -g gos
```
