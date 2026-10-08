# Tool Mapping (shared reference)

Platform tool equivalents for GOS skills. Skills use generic names;
translate per your host.

| GOS Concept | OpenCode | Claude Code | Codex |
|:---|:---|:---|:---|
| Task tracking | todowrite | TodoWrite | Manual list in response |
| Subagent | @mention / Task | Task tool | Manual |
| Skill loading | skill tool | Skill tool | Read SKILL.md directly |
| File read | read | Read | Native |
| File write | write | Write | Native |
| File edit | edit | Edit | Native |
| Shell | bash | Bash | Native |
| Search | grep / glob | Grep / Glob | Native |
| User choice UI | question tool | AskUserQuestion | Plain-text options |

## Subagent Dispatch Note

When a prompt template says "if resolve-model returns inherit, OMIT the
model parameter": in OpenCode's Task tool this means simply not passing
`model:`; in Claude Code's Task tool, not setting the model field. Never
pass the literal string "inherit" as a model name.
