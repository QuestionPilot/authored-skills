#!/usr/bin/env bash
# Unit tests for safety-check.py — freeze boundary, careful patterns, guard
# Bash-write bypass closure, path canonicalization edge cases. Pure python3 +
# bash 3.2; no Claude Code required (drives the enforcement core directly).
set -u

BIN="$(cd "$(dirname "$0")/../bin" && pwd)"
PY="$BIN/safety-check.py"
PASS=0
FAIL=0

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
STATE_DIR="$ROOT/state"; mkdir -p "$STATE_DIR"
SANDBOX="$ROOT/sandbox"; mkdir -p "$SANDBOX"
OUTSIDE="$ROOT/outside"; mkdir -p "$OUTSIDE"
mkdir -p "$ROOT/src" "$ROOT/src-old"
ln -s "$OUTSIDE/secret.txt" "$SANDBOX/sneaky"   # symlink inside -> outside

careful_on(){ : > "$STATE_DIR/careful-on"; }
careful_off(){ rm -f "$STATE_DIR/careful-on"; }
freeze_to(){ printf '%s\n' "$1" > "$STATE_DIR/freeze-dir.txt"; }
freeze_off(){ rm -f "$STATE_DIR/freeze-dir.txt"; }
reset_state(){ careful_off; freeze_off; }

# assert_decision MODE EVENT_JSON EXPECT(deny|ask|allow) LABEL
assert_decision(){
  local mode="$1" event="$2" expect="$3" label="$4" out got
  out="$(printf '%s' "$event" | SAFETY_STATE_DIR="$STATE_DIR" python3 "$PY" "$mode" 2>/dev/null)"
  got="allow"
  case "$out" in
    *'"permissionDecision":"deny"'*) got="deny" ;;
    *'"permissionDecision":"ask"'*) got="ask" ;;
  esac
  if [ "$got" = "$expect" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); printf 'FAIL: %s\n  expected=%s got=%s\n  out=%s\n' "$label" "$expect" "$got" "$out"
  fi
}
edit(){ printf '{"tool_input":{"file_path":"%s"}}' "$1"; }
bash_ev(){ printf '{"tool_input":{"command":"%s"}}' "$1"; }

# ---------- FREEZE (edit mode) ----------
reset_state; freeze_to "$SANDBOX"
assert_decision edit "$(edit "$SANDBOX/a.txt")"        allow "freeze: edit inside boundary"
assert_decision edit "$(edit "$OUTSIDE/a.txt")"        deny  "freeze: edit outside boundary"
assert_decision edit "$(edit "$SANDBOX/sub/deep.txt")" allow "freeze: edit nested inside"
assert_decision edit "$(edit "$SANDBOX/sneaky")"       deny  "freeze: symlink inside->outside resolved & denied"
assert_decision edit '{"tool_input":{"edits":[{"file_path":"'"$SANDBOX/x"'"},{"file_path":"'"$OUTSIDE/y"'"}]}}' deny "freeze: MultiEdit one-outside denied"
assert_decision edit '{"tool_input":{}}'               deny  "freeze: unreadable edit target fails closed"
# path with a space inside boundary
assert_decision edit "$(edit "$SANDBOX/a b.txt")"      allow "freeze: space in path inside boundary"

reset_state; freeze_to "$ROOT/src"
assert_decision edit "$(edit "$ROOT/src-old/x")"       deny  "freeze: /src vs /src-old trailing-slash guard"
assert_decision edit "$(edit "$ROOT/src/x")"           allow "freeze: /src own file allowed"

reset_state   # no freeze
assert_decision edit "$(edit "$OUTSIDE/a.txt")"        allow "freeze: inactive -> allow"

# ---------- CAREFUL (bash mode) ----------
reset_state; careful_on
assert_decision bash "$(bash_ev "rm -rf /tmp/whatever")"          ask   "careful: rm -rf -> ask"
assert_decision bash "$(bash_ev "rm -rf node_modules")"           allow "careful: rm -rf node_modules safe-exception"
assert_decision bash "$(bash_ev "rm -rf node_modules ../secret")" ask   "careful: rm safe+traversal -> ask"
assert_decision bash "$(bash_ev "git push --force origin main")"  ask   "careful: git force-push -> ask"
assert_decision bash "$(bash_ev "git push origin main")"          allow "careful: normal git push allowed"
assert_decision bash "$(bash_ev "git reset --hard HEAD~2")"       ask   "careful: git reset --hard -> ask"
assert_decision bash "$(bash_ev "DROP TABLE users;")"             ask   "careful: SQL DROP -> ask"
assert_decision bash "$(bash_ev "kubectl delete pod x")"          ask   "careful: kubectl delete -> ask"
assert_decision bash "$(bash_ev "echo hello world")"              allow "careful: benign echo allowed"
assert_decision bash "$(bash_ev "ls -la")"                        allow "careful: ls allowed"

reset_state   # careful off
assert_decision bash "$(bash_ev "rm -rf /tmp/whatever")"          allow "careful: inactive -> allow"

# ---------- GUARD (bash writes vs boundary) ----------
reset_state; careful_on; freeze_to "$SANDBOX"
assert_decision bash "$(bash_ev "echo x > $OUTSIDE/o.txt")"       deny  "guard: > redirect outside -> deny"
assert_decision bash "$(bash_ev "echo x > $SANDBOX/o.txt")"       allow "guard: > redirect inside -> allow"
assert_decision bash "$(bash_ev "echo x >$OUTSIDE/o.txt")"        deny  "guard: >file (no space) outside -> deny"
assert_decision bash "$(bash_ev "cmd 2>&1")"                      allow "guard: 2>&1 fd-dup not a write"
assert_decision bash "$(bash_ev "sed -i s/a/b/ $OUTSIDE/f.txt")"  deny  "guard: sed -i outside -> deny"
assert_decision bash "$(bash_ev "cp a.txt $OUTSIDE/b.txt")"       deny  "guard: cp dest outside -> deny"
assert_decision bash "$(bash_ev "tee $OUTSIDE/log.txt")"          deny  "guard: tee outside -> deny"
assert_decision bash "$(bash_ev "touch $SANDBOX/new")"            allow "guard: touch inside -> allow"
assert_decision bash "$(bash_ev "cat foo > \$OUT")"               ask   "guard: variable redirect target -> ask"
assert_decision bash "$(bash_ev "ls -la $OUTSIDE")"               allow "guard: read-only outside -> allow"

# ---------- GUARD: command composition (Codex impl MUST-FIX #1) ----------
reset_state; careful_on; freeze_to "$SANDBOX"
assert_decision bash "$(bash_ev "true; touch $OUTSIDE/a")"        deny  "guard: ;-chained write outside -> deny"
assert_decision bash "$(bash_ev "FOO=bar touch $OUTSIDE/a")"      deny  "guard: assignment-prefixed write outside -> deny"
assert_decision bash "$(bash_ev "( touch $OUTSIDE/a )")"          deny  "guard: subshell write outside -> deny"
assert_decision bash "$(bash_ev "{ touch $OUTSIDE/a; }")"         deny  "guard: brace-group write outside -> deny"
assert_decision bash "$(bash_ev "printf x | tee $OUTSIDE/a")"     deny  "guard: piped tee outside -> deny"
assert_decision bash "$(bash_ev "true; rm $OUTSIDE/a")"           deny  "guard: ;-chained rm outside -> deny"
assert_decision bash "$(bash_ev "sudo rm -rf $OUTSIDE/x")"        deny  "guard: sudo-wrapped rm outside -> deny"
assert_decision bash "$(bash_ev "cd $SANDBOX && touch $SANDBOX/a")" allow "guard: &&-chained writes all inside -> allow"
# mv source deletion (MUST-FIX #2)
assert_decision bash "$(bash_ev "mv $OUTSIDE/f $SANDBOX/f")"      deny  "guard: mv source outside (delete) -> deny"
assert_decision bash "$(bash_ev "mv $SANDBOX/f $SANDBOX/g")"      allow "guard: mv both inside -> allow"
# /dev allow-list + fd-dup (SHOULD #6)
assert_decision bash "$(bash_ev "echo x >/dev/null")"            allow "guard: >/dev/null -> allow"
assert_decision bash "$(bash_ev "cmd 2>/dev/null")"              allow "guard: 2>/dev/null -> allow"
# find/xargs literal mutator payload -> ask
assert_decision bash "$(bash_ev "find . -exec touch $OUTSIDE/a ;")" ask "guard: find -exec mutator -> ask"

# ---------- CAREFUL: option-tolerant + composition (MUST-FIX #3,#4) ----------
reset_state; careful_on
assert_decision bash "$(bash_ev "rm -R /tmp/x")"                          ask   "careful: rm -R (capital) -> ask"
assert_decision bash "$(bash_ev "rm -Rf /tmp/x")"                         ask   "careful: rm -Rf -> ask"
assert_decision bash "$(bash_ev "git -C repo reset --hard HEAD")"         ask   "careful: git -C reset --hard -> ask"
assert_decision bash "$(bash_ev "kubectl --context prod delete pod x")"   ask   "careful: kubectl global-flag delete -> ask"
assert_decision bash "$(bash_ev "docker container rm -f x")"              ask   "careful: docker container rm -f -> ask"
assert_decision bash "$(bash_ev "git push --force-with-lease origin m")"  ask   "careful: git push --force-with-lease -> ask"
assert_decision bash "$(bash_ev "sudo rm -rf /tmp/x")"                    ask   "careful: sudo rm -rf -> ask"
assert_decision bash "$(bash_ev "cd /tmp && rm -rf /tmp/x")"              ask   "careful: &&-chained rm -rf -> ask"
assert_decision bash "$(bash_ev "git -C repo status")"                    allow "careful: git -C status (benign) -> allow"

# ---------- PARSER edge cases (rewrite self-probe: heredoc/here-string/quoting) ----------
reset_state; careful_on; freeze_to "$SANDBOX"
assert_decision bash "$(bash_ev "cat <<EOF > $OUTSIDE/f")"        deny  "guard: heredoc with redirect outside -> deny"
assert_decision bash "$(bash_ev "cmd <<< data > $OUTSIDE/f")"     deny  "guard: here-string with redirect outside -> deny"
assert_decision bash "$(bash_ev "echo 'x; rm $OUTSIDE/f'")"       allow "guard: quoted ;/rm is a string, not a command -> allow"
assert_decision bash "$(bash_ev "echo 'a && touch $OUTSIDE/f'")"  allow "guard: quoted && is a string -> allow"

# ---------- FAIL-CLOSED: malformed freeze state (MUST-FIX #5) ----------
reset_state; : > "$STATE_DIR/freeze-dir.txt"   # present but EMPTY
assert_decision edit "$(edit "$OUTSIDE/a.txt")"  deny "freeze: empty boundary file fails closed (edit)"
assert_decision bash "$(bash_ev "touch $OUTSIDE/x")" ask "guard: empty boundary file -> ask (bash)"

echo "----"
echo "safety-check.py: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
