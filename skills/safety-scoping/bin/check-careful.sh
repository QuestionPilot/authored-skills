#!/usr/bin/env bash
# check-careful.sh — PreToolUse(Bash) hook for the safety-scoping skill.
# Fast no-op when safety mode is off (no python spawn); otherwise delegate to
# safety-check.py (python-primary parsing/resolution). Always exits 0 — a
# blocking decision is carried in the hookSpecificOutput JSON, never the exit
# code (a non-zero exit is treated by Claude Code as a hook ERROR, not a block).
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_DIR="$(cd "$SCRIPT_DIR/../../.." 2>/dev/null && pwd)/.state/safety-scoping"

# Fast path: nothing active -> allow without reading stdin or spawning python.
if [ ! -f "$STATE_DIR/careful-on" ] && [ ! -f "$STATE_DIR/freeze-dir.txt" ]; then
  printf '{}'
  exit 0
fi

INPUT="$(cat)"

if command -v python3 >/dev/null 2>&1; then
  OUT="$(printf '%s' "$INPUT" | SAFETY_STATE_DIR="$STATE_DIR" python3 "$SCRIPT_DIR/safety-check.py" bash 2>/dev/null)"
  if [ -n "$OUT" ]; then
    printf '%s' "$OUT"
  else
    # python failed while a mode is active -> ask rather than silently allow.
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"[safety-scoping] safety check could not complete; proceed?"}}'
  fi
else
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"[safety-scoping] python3 unavailable; cannot verify command safety. Proceed?"}}'
fi
exit 0
