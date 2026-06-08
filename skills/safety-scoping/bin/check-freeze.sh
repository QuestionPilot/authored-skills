#!/usr/bin/env bash
# check-freeze.sh — PreToolUse(Write|Edit|NotebookEdit|MultiEdit) hook for the
# safety-scoping skill. Fast no-op when no freeze boundary is set; otherwise
# delegate to safety-check.py. FAIL CLOSED: if past the fast path the boundary
# IS active, so an empty/failed check denies rather than allows. Always exits 0.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_DIR="$(cd "$SCRIPT_DIR/../../.." 2>/dev/null && pwd)/.state/safety-scoping"

# Fast path: no boundary -> allow without spawning python.
if [ ! -f "$STATE_DIR/freeze-dir.txt" ]; then
  printf '{}'
  exit 0
fi

INPUT="$(cat)"
DENY='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"[safety-scoping/freeze] safety check could not complete; blocked because a freeze boundary is active. Run /unfreeze to lift it."}}'

if command -v python3 >/dev/null 2>&1; then
  OUT="$(printf '%s' "$INPUT" | SAFETY_STATE_DIR="$STATE_DIR" python3 "$SCRIPT_DIR/safety-check.py" edit 2>/dev/null)"
  if [ -n "$OUT" ]; then
    printf '%s' "$OUT"
  else
    printf '%s' "$DENY"
  fi
else
  printf '%s' "$DENY"
fi
exit 0
