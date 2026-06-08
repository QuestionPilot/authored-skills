---
name: safety-scoping
description: >-
  Session safety guardrails — warn before destructive shell commands and/or
  restrict file edits to a chosen directory. Use when the user says "be careful",
  "safety mode", "prod mode", "freeze edits to <dir>", "lock editing scope",
  "restrict edits to this folder", "guard mode", "full safety", "lock it down",
  "unfreeze", "unlock edits", or "safety off". Activates persistent PreToolUse
  guardrails for the rest of the session via a state file the always-on hooks read.
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
---

# safety-scoping — careful / freeze / guard

Local operator skill (ported pattern from gstack `careful`/`freeze`/`guard`).
It toggles three guardrails by writing small **state files** that two always-on
PreToolUse hooks read on every tool call:

- **careful** — warns (permission `ask`, you can override) before destructive Bash:
  `rm -rf`, SQL `DROP`/`TRUNCATE`, `git push --force`, `git reset --hard`,
  `git checkout/restore .`, `kubectl delete`, `docker rm -f`/`system prune`. A
  hardcoded safe-exception list allows `rm -rf` of `node_modules`/`dist`/`.next`/
  `__pycache__`/`.cache`/`build`/`.turbo`/`coverage`.
- **freeze** — hard-blocks (permission `deny`) any `Write`/`Edit`/`NotebookEdit`/
  `MultiEdit` outside a chosen directory boundary.
- **guard** — both at once. In guard mode the Bash hook **also** blocks shell
  *writes* (`>`, `>>`, `tee`, `sed -i`, `cp`/`mv`/`install`/`rsync`, `touch`, …)
  whose target resolves outside the boundary, closing the `sed`/`>` bypass that
  Edit/Write-only freezing leaves open.

> **Not a security boundary.** This is a convenience guardrail against accidental
> damage. It cannot stop `eval`, command substitution, variable-computed paths,
> custom scripts, or language-runtime writes — those are surfaced as `ask` when
> detectable, allowed otherwise. Don't rely on it against an adversary.

> **Concurrency caveat.** Claude Code does not expose the session id to skill-body
> Bash, so state is **shared across concurrent sessions** under one config dir. If
> you `/freeze` in one session, another live session sees the same boundary. There
> is no auto-reset — teardown is explicit (`/unfreeze`, "safety off").

## State location

```bash
STATE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.state/safety-scoping"
mkdir -p "$STATE_DIR"
```

Files: `careful-on` (marker) and `freeze-dir.txt` (one line: the canonical boundary,
no trailing slash). The hooks compute the same `$STATE_DIR` from their own location,
so they stay in sync.

## Activating

### careful / "safety mode"
```bash
: > "$STATE_DIR/careful-on"
```
Tell the user: destructive-command warnings are on for the session; run "safety off" to clear.

### freeze / "restrict edits to <dir>"
1. Get the directory. If the user named one, use it; otherwise ask:
   - `AskUserQuestion` (free-text): "Which directory should edits be restricted to? Files outside it will be blocked."
2. Resolve to an **existing** absolute directory and write atomically:
```bash
FREEZE_DIR="$(cd "<user-path>" 2>/dev/null && pwd -P)" || { echo "Path must be an existing directory."; }
printf '%s\n' "$FREEZE_DIR" > "$STATE_DIR/freeze-dir.txt.$$" && mv "$STATE_DIR/freeze-dir.txt.$$" "$STATE_DIR/freeze-dir.txt"
echo "Freeze boundary set: $FREEZE_DIR/"
```
Tell the user edits are now restricted to that path; `/unfreeze` lifts it.

### guard / "full safety"
Do **both** of the above (write `careful-on` AND `freeze-dir.txt`).

## Deactivating

### unfreeze / "unlock edits" — clears the boundary ONLY (careful stays on)
```bash
rm -f "$STATE_DIR/freeze-dir.txt" && echo "Freeze boundary cleared. Edits allowed everywhere."
```

### "safety off" — clears everything
```bash
rm -f "$STATE_DIR/careful-on" "$STATE_DIR/freeze-dir.txt" && echo "All safety guardrails cleared."
```

### status
```bash
[ -f "$STATE_DIR/careful-on" ] && echo "careful: ON" || echo "careful: off"
[ -f "$STATE_DIR/freeze-dir.txt" ] && echo "freeze: $(cat "$STATE_DIR/freeze-dir.txt")" || echo "freeze: off"
```

## One-time hook install (operator)

The guardrails only fire if the two always-on PreToolUse hooks are registered in
`$CLAUDE_CONFIG_DIR/settings.json`. They no-op cheaply (a file-existence check)
when no state file is present, so they're safe to leave installed permanently.
See `reference/install-hooks.md` for the exact additive `settings.json` block and
a `jq`-merge install snippet. (This step touches live settings; apply deliberately.)

## How it works
- `bin/check-careful.sh` → PreToolUse `Bash`. `bin/check-freeze.sh` → PreToolUse
  `Write|Edit|NotebookEdit|MultiEdit`. Both shell wrappers do the fast no-op, then
  hand the event JSON to `bin/safety-check.py` (python-primary parsing + canonical
  path resolution). Decisions use the current `hookSpecificOutput.permissionDecision`
  contract; most-restrictive-wins composes correctly with the session-agent gate.
- Fail-closed: while a freeze boundary is active, an unparseable edit is denied; an
  unparseable Bash command is `ask`.
