#!/usr/bin/env bash
# Fixture test for bin/check-ship-gates.sh (promotion trust contract, step 3).
# Builds throwaway git repos under mktemp -d, exercises each gate's positive and
# negative control, asserts STRUCTURE (gate name + status token), never prose.
set -uo pipefail
export LC_ALL=C

HERE=$(cd "$(dirname "$0")" && pwd -P)
GATES="$HERE/../bin/check-ship-gates.sh"
[ -f "$GATES" ] || { echo "missing script: $GATES" >&2; exit 1; }

ROOT=$(mktemp -d -t framework-ship-tests-XXXXXX) || exit 1
cleanup() { rm -rf "$ROOT"; }
trap cleanup EXIT INT TERM

GOOD_ID_NAME="Ship Bot"
GOOD_ID_EMAIL="1234567+QuestionPilot@users.noreply.github.com"
GOOD_ID="$GOOD_ID_NAME <$GOOD_ID_EMAIL>"

FAILURES=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAILED  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

assert_exit() { # <expected> <actual> <label>
  if [ "$1" -eq "$2" ]; then pass "$3 (exit $2)"; else fail "$3 (expected exit $1, got $2)"; fi
}
assert_gate() { # <output> <gate-name> <status> <label>
  if printf '%s\n' "$1" | grep -qE "^GATE ${2}[[:space:]]+${3}([[:space:]]|$)"; then
    pass "$4"
  else
    fail "$4 -- no line 'GATE $2 ... $3' in output:
$1"
  fi
}

git_c() { git -c "user.name=$GOOD_ID_NAME" -c "user.email=$GOOD_ID_EMAIL" "$@"; }

# Build <origin bare> + <clone on main with one base commit + scripts twins>.
make_repo() { # <name> -> echoes clone path
  _n="$1"
  _origin="$ROOT/$_n.git"
  _clone="$ROOT/$_n"
  git init --bare -q "$_origin"
  git init -q "$_clone"
  (
    cd "$_clone" || exit 1
    git remote add origin "$_origin"
    git checkout -q -b main
    mkdir -p scripts
    printf 'echo base\n' > scripts/thing.sh
    printf 'Write-Output base\n' > scripts/thing.ps1
    printf 'COMMIT_IDENTITY_ALLOWLIST=%s\n' "$GOOD_ID" > local.env
    git add -A
    git_c commit -q -m "base"
    git push -q origin main
  ) || return 1
  printf '%s\n' "$_clone"
}

write_log() { # <path> <content-kind>
  case "$2" in
    green) printf 'gate: suite\nsuite: 38 PASS\nVERIFY PASSED\n' > "$1" ;;
    redfail) printf 'gate: suite\ntests/foo.sh FAIL\nVERIFY PASSED\n' > "$1" ;;
  esac
}

echo "== fixture A: all-green pre-push =="
A=$(make_repo repo_a) || { echo "fixture build failed" >&2; exit 1; }
(
  cd "$A" || exit 1
  git checkout -q -b feat/ship
  printf 'echo changed\n' >> scripts/thing.sh
  printf 'Write-Output changed\n' >> scripts/thing.ps1
  git add -A
  git_c commit -q -m "change both twins"
)
write_log "$ROOT/verify-a.log" green
write_log "$ROOT/checkclean-a.log" green
OUT=$(bash "$GATES" --stage pre-push --repo "$A" --default-branch main \
  --local-env "$A/local.env" \
  --verify-log "$ROOT/verify-a.log" --check-clean-log "$ROOT/checkclean-a.log" 2>&1)
RC=$?
assert_exit 0 $RC "A: all-green pre-push exits 0"
assert_gate "$OUT" branch-not-default PASS "A: branch-not-default PASS"
assert_gate "$OUT" worktree-clean     PASS "A: worktree-clean PASS"
assert_gate "$OUT" commit-identity    PASS "A: commit-identity PASS"
assert_gate "$OUT" verify-log         PASS "A: verify-log PASS"
assert_gate "$OUT" check-clean-log    PASS "A: check-clean-log PASS"
assert_gate "$OUT" twin-parity        PASS "A: twin-parity PASS"
if printf '%s\n' "$OUT" | grep -qE '^VERDICT: PASS'; then pass "A: VERDICT PASS line"; else fail "A: VERDICT PASS line"; fi

echo "== fixture B: bad committer identity =="
B=$(make_repo repo_b) || exit 1
(
  cd "$B" || exit 1
  git checkout -q -b feat/ship
  printf 'x\n' >> README.md
  git add -A
  git -c user.name="Local Machine" -c user.email="laptop@local" \
    commit -q -m "amended-style bad committer" --author="$GOOD_ID"
)
write_log "$ROOT/verify-b.log" green
OUT=$(bash "$GATES" --stage pre-push --repo "$B" --default-branch main \
  --local-env "$B/local.env" \
  --verify-log "$ROOT/verify-b.log" --check-clean-log "$ROOT/verify-b.log" 2>&1)
RC=$?
assert_exit 1 $RC "B: bad committer exits 1"
assert_gate "$OUT" commit-identity FAIL "B: commit-identity FAIL"
assert_gate "$OUT" worktree-clean  PASS "B: worktree-clean still PASS (gates independent)"
if printf '%s\n' "$OUT" | grep -qE '^VERDICT: FAIL'; then pass "B: VERDICT FAIL line"; else fail "B: VERDICT FAIL line"; fi

echo "== fixture C: dirty working tree =="
C=$(make_repo repo_c) || exit 1
(
  cd "$C" || exit 1
  git checkout -q -b feat/ship
  printf 'y\n' >> README.md
  git add -A
  git_c commit -q -m "committed change"
  printf 'scratch\n' > untracked-scratch.log
)
write_log "$ROOT/verify-c.log" green
OUT=$(bash "$GATES" --stage pre-push --repo "$C" --default-branch main \
  --local-env "$C/local.env" \
  --verify-log "$ROOT/verify-c.log" --check-clean-log "$ROOT/verify-c.log" 2>&1)
RC=$?
assert_exit 1 $RC "C: dirty tree exits 1"
assert_gate "$OUT" worktree-clean FAIL "C: worktree-clean FAIL (untracked counts)"

echo "== fixture D: verify log containing a FAIL line =="
D=$(make_repo repo_d) || exit 1
(
  cd "$D" || exit 1
  git checkout -q -b feat/ship
  printf 'z\n' >> README.md
  git add -A
  git_c commit -q -m "change"
)
write_log "$ROOT/verify-d.log" redfail
write_log "$ROOT/checkclean-d.log" green
OUT=$(bash "$GATES" --stage pre-push --repo "$D" --default-branch main \
  --local-env "$D/local.env" \
  --verify-log "$ROOT/verify-d.log" --check-clean-log "$ROOT/checkclean-d.log" 2>&1)
RC=$?
assert_exit 1 $RC "D: red verify log exits 1"
assert_gate "$OUT" verify-log      FAIL "D: verify-log FAIL"
assert_gate "$OUT" check-clean-log PASS "D: check-clean-log PASS"

echo "== fixture E: missing log is SKIP, not PASS =="
OUT=$(bash "$GATES" --stage pre-push --repo "$D" --default-branch main \
  --local-env "$D/local.env" --check-clean-log "$ROOT/checkclean-d.log" 2>&1)
RC=$?
assert_exit 0 $RC "E: omitted verify log does not FAIL the verdict"
assert_gate "$OUT" verify-log SKIP "E: verify-log SKIP when no log supplied"

echo "== fixture F: changed .sh with existing but un-co-changed twin => WARN =="
F=$(make_repo repo_f) || exit 1
(
  cd "$F" || exit 1
  git checkout -q -b feat/ship
  printf 'echo only-bash\n' >> scripts/thing.sh
  git add -A
  git_c commit -q -m "bash side only"
)
write_log "$ROOT/verify-f.log" green
OUT=$(bash "$GATES" --stage pre-push --repo "$F" --default-branch main \
  --local-env "$F/local.env" \
  --verify-log "$ROOT/verify-f.log" --check-clean-log "$ROOT/verify-f.log" 2>&1)
RC=$?
assert_exit 0 $RC "F: twin-exists-only is WARN, verdict still PASS"
assert_gate "$OUT" twin-parity WARN "F: twin-parity WARN"

echo "== fixture G: post-merge green =="
G=$(make_repo repo_g) || exit 1
OUT=$(bash "$GATES" --stage post-merge --repo "$G" --default-branch main 2>&1)
RC=$?
assert_exit 0 $RC "G: post-merge green exits 0"
assert_gate "$OUT" on-default-branch   PASS "G: on-default-branch PASS"
assert_gate "$OUT" worktree-clean      PASS "G: worktree-clean PASS"
assert_gate "$OUT" head-matches-origin PASS "G: head-matches-origin PASS"

echo "== fixture H: post-merge behind origin =="
H=$(make_repo repo_h) || exit 1
(
  cd "$H" || exit 1
  printf 'ahead\n' >> README.md
  git add -A
  git_c commit -q -m "local commit not on origin"
)
OUT=$(bash "$GATES" --stage post-merge --repo "$H" --default-branch main 2>&1)
RC=$?
assert_exit 1 $RC "H: HEAD diverged from origin exits 1"
assert_gate "$OUT" head-matches-origin FAIL "H: head-matches-origin FAIL"

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "ALL TESTS PASSED"
  exit 0
else
  echo "$FAILURES ASSERTION(S) FAILED"
  exit 1
fi
