# safety-scoping — one-time hook install

The skill only enforces if these two **always-on, state-gated** PreToolUse hooks
are registered in `$CLAUDE_CONFIG_DIR/settings.json`. They no-op (one file-stat)
when no state file is present, so they're safe to leave installed permanently.
The scripts are exec'd directly (matching the existing session-agent hook), so the
absolute path with a space is fine — but the scripts must be executable:

```bash
chmod +x "$CLAUDE_CONFIG_DIR"/skills/safety-scoping/bin/check-careful.sh \
         "$CLAUDE_CONFIG_DIR"/skills/safety-scoping/bin/check-freeze.sh
```

## Additive `settings.json` block

Add these two entries to the existing `hooks.PreToolUse` array (do **not** replace
the session-agent entry already there):

```json
{
  "matcher": "Bash",
  "hooks": [
    {
      "type": "command",
      "command": "$CLAUDE_CONFIG_DIR/skills/safety-scoping/bin/check-careful.sh",
      "args": [],
      "timeout": 10
    }
  ]
},
{
  "matcher": "Write|Edit|NotebookEdit|MultiEdit",
  "hooks": [
    {
      "type": "command",
      "command": "$CLAUDE_CONFIG_DIR/skills/safety-scoping/bin/check-freeze.sh",
      "args": [],
      "timeout": 10
    }
  ]
}
```

## jq-merge install (idempotent)

Appends the two entries only if absent. Backs up first.

```bash
SET="$CLAUDE_CONFIG_DIR/settings.json"
cp "$SET" "$SET.safety-bak.$(date +%s)"
BIN="$CLAUDE_CONFIG_DIR/skills/safety-scoping/bin"
jq --arg careful "$BIN/check-careful.sh" --arg freeze "$BIN/check-freeze.sh" '
  .hooks.PreToolUse |= (
    (. // [])
    + (if any(.[]?; .matcher=="Bash" and (.hooks[]?.command==$careful)) then []
       else [{matcher:"Bash",hooks:[{type:"command",command:$careful,args:[],timeout:10}]}] end)
    + (if any(.[]?; .matcher=="Write|Edit|NotebookEdit|MultiEdit" and (.hooks[]?.command==$freeze)) then []
       else [{matcher:"Write|Edit|NotebookEdit|MultiEdit",hooks:[{type:"command",command:$freeze,args:[],timeout:10}]}] end)
  )
' "$SET" > "$SET.tmp" && mv "$SET.tmp" "$SET"
```

Claude Code hot-reloads `settings.json` — the hooks become active on the next
matching tool call, no restart needed.

## Uninstall

```bash
SET="$CLAUDE_CONFIG_DIR/settings.json"
jq '.hooks.PreToolUse |= map(select(
      (.hooks[]?.command | test("safety-scoping/bin/")) | not))' \
   "$SET" > "$SET.tmp" && mv "$SET.tmp" "$SET"
rm -rf "$CLAUDE_CONFIG_DIR/.state/safety-scoping"
```

## Caveat re: install.sh

`install.sh generate_settings()` re-renders `settings.json` from `settings.base.json`
(+ injected hooks). These skill hooks live in the operator's live `settings.json`, not
in the shipped base, so a re-install would drop them (operator-local hooks live outside the shipped base).
Re-run the jq-merge after any `install.sh`, or fold the registration into the operator
hook-injection path if this skill is kept long-term.
