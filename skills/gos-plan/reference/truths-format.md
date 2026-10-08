# Observable Truths Format

## Standard Format

```markdown
### T-01: [Observable behavior]
- **Expected**: [what should happen]
- **Verify**: [command or test to prove it]
```

## Truth Quality Checklist
- [ ] Observable from outside (user can see/trigger it)
- [ ] Has a concrete verify command (not "check the code")
- [ ] Maps to at least one spec goal
- [ ] Binary outcome (pass/fail, not "mostly works")

## Cold-Start Detection

Check if the implementation has:
- Server entry point (server.ts, app.ts) → add cold-start truth
- DB migrations → add migration truth
- Config files → add config-load truth

Example cold-start truth:
```markdown
### T-05: Server cold-starts cleanly
- **Expected**: `npm start` → server boots, health check returns 200
- **Verify**: kill port; npm start &; sleep 3; curl localhost:3000/health
```
