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
    # green includes a PASSing test title that CONTAINS the word FAIL mid-line —
    # the restraint fixture: only line-start FAILs may trip the log gate.
    green) printf 'gate: suite\nsuite: 38 PASS\n  PASS check-clean FAILS on a dirty tree\nVERIFY PASSED\n' > "$1" ;;
    redfail) printf 'gate: suite\n  FAIL tests/foo.sh: broke\nVERIFY PASSED\n' > "$1" ;;
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

# ---------------------------------------------------------------- renders-current
#
# The fixture repo carries a FAKE scripts/install.sh that prints a --dry-run
# report in install.sh's exact format, driven by scripts/.dryrun-state. That
# covers the PARSER and the verdict wiring only — that the gate reads stale/
# broken/missing correctly, names the first stale file, treats a non-zero exit
# as FAIL and an unconfigured home as SKIP. It says nothing about the REAL
# install.sh's output staying in that shape; the live post-merge run against the
# framework checkout is what covers that half, and must be re-run if
# classify_state's report format ever changes.
#
# The gate resolves homes from the ENVIRONMENT first (check-drift --auto's
# order), so every invocation below runs with the operator's real harness vars
# stripped — otherwise a developer's live $CLAUDE_CONFIG_DIR would hijack the
# fixture.
gates_noenv() {
  env -u CLAUDE_CONFIG_DIR -u CODEX_HOME -u HERMES_HOME -u CURSOR_CONFIG_DIR \
      -u AGENTS_DIR bash "$GATES" "$@"
}

# Fake install.sh: reproduces classify_state's report shape byte-for-byte for
# the lines the gate parses. `target` is echoed from the state file so the
# gate's target-agreement check sees what it expects.
write_fake_install() { # <repo>
  mkdir -p "$1/scripts"
  cat > "$1/scripts/install.sh" <<'FAKE'
#!/usr/bin/env bash
# FAKE install.sh — fixture double for scripts/install.sh --dry-run.
mode=insync; target=""; stale_file="skills/closeout/SKILL.md"
sf="$(cd "$(dirname "$0")" && pwd)/.dryrun-state"
[ -f "$sf" ] && . "$sf"
h=claude
while [ $# -gt 0 ]; do
  case "$1" in --harness) h="${2:-}"; shift 2 ;; *) shift ;; esac
done
if [ "$mode" = exit3 ]; then
  printf 'install.sh: simulated blow-up\n' >&2
  exit 3
fi
# nobanner: an in-sync report with the target line REMOVED — the gate must not
# read counts out of a report shape it cannot confirm belongs to this target.
if [ "$mode" != nobanner ]; then
  printf 'install.sh: dry-run state for %s at %s\n' "$h" "$target"
fi
if [ "$mode" = missing ]; then
  printf '  managed: 8  (present and current)\n'
  printf '  stale:   0  (an install would UPDATE — framework moved on)\n'
  printf '  broken:  0  (modified/corrupted on disk — an install would overwrite)\n'
  printf '  missing: 1  (absent — an install would create)\n'
  printf '    - hooks/stuck-detector.sh\n'
  printf '  custom:  2  (operator skills/plugins — PRESERVED, never clobbered)\n'
  printf 'install.sh: re-run without --dry-run to reconcile managed files (custom content is preserved).\n'
elif [ "$mode" = stale ]; then
  printf '  managed: 8  (present and current)\n'
  printf '  stale:   1  (an install would UPDATE — framework moved on)\n'
  printf '    - %s\n' "$stale_file"
  printf '  broken:  0  (modified/corrupted on disk — an install would overwrite)\n'
  printf '  missing: 0  (absent — an install would create)\n'
  printf '  custom:  2  (operator skills/plugins — PRESERVED, never clobbered)\n'
  printf 'install.sh: re-run without --dry-run to reconcile managed files (custom content is preserved).\n'
else
  printf '  managed: 9  (present and current)\n'
  printf '  stale:   0  (an install would UPDATE — framework moved on)\n'
  printf '  broken:  0  (modified/corrupted on disk — an install would overwrite)\n'
  printf '  missing: 0  (absent — an install would create)\n'
  printf '  custom:  2  (operator skills/plugins — PRESERVED, never clobbered)\n'
  printf 'install.sh: target is in sync with the current framework.\n'
fi
printf 'install.sh: no changes written (dry-run).\n'
FAKE
}

# Commit + push so worktree-clean and head-matches-origin stay green while the
# fixture flips state between cases.
sync_fixture() { # <repo> <message>
  (
    cd "$1" || exit 1
    git add -A
    git_c commit -q -m "$2"
    git push -q origin main
  )
}

echo "== fixture I: renders-current, home in sync =="
I=$(make_repo repo_i) || exit 1
I_HOME="$ROOT/home_i"
mkdir -p "$I_HOME"
printf '{"harness":"claude","generated":{}}\n' > "$I_HOME/.build-manifest.json"
write_fake_install "$I"
printf 'mode=insync\ntarget=%s\n' "$I_HOME" > "$I/scripts/.dryrun-state"
printf 'CLAUDE_CONFIG_DIR="%s"\n' "$I_HOME" >> "$I/local.env"
sync_fixture "$I" "fixture: fake install.sh + rendered home" || exit 1
OUT=$(gates_noenv --stage post-merge --repo "$I" --default-branch main \
  --local-env "$I/local.env" --no-fetch 2>&1)
RC=$?
assert_exit 0 $RC "I: in-sync render exits 0"
assert_gate "$OUT" renders-current PASS "I: renders-current PASS"
if printf '%s\n' "$OUT" | grep -q 'claude .*: in sync'; then
  pass "I: PASS line names the harness and 'in sync'"
else
  fail "I: PASS line names the harness and 'in sync' -- got:
$OUT"
fi
# Unconfigured homes are LOUD skips, never silently absent.
if [ "$(printf '%s\n' "$OUT" | grep -c '^GATE renders-current  *SKIP')" -eq 4 ]; then
  pass "I: 4 unset homes each emit their own SKIP line"
else
  fail "I: expected 4 SKIP lines for unset homes -- got:
$OUT"
fi

echo "== fixture J: renders-current, one stale file =="
printf 'mode=stale\ntarget=%s\n' "$I_HOME" > "$I/scripts/.dryrun-state"
sync_fixture "$I" "fixture: flip dry-run state to stale" || exit 1
OUT=$(gates_noenv --stage post-merge --repo "$I" --default-branch main \
  --local-env "$I/local.env" --no-fetch 2>&1)
RC=$?
assert_exit 1 $RC "J: stale render exits 1"
assert_gate "$OUT" renders-current FAIL "J: renders-current FAIL"
if printf '%s\n' "$OUT" | grep -q 'stale=1 broken=0 missing=0'; then
  pass "J: FAIL line carries the parsed counts"
else
  fail "J: FAIL line carries the parsed counts -- got:
$OUT"
fi
if printf '%s\n' "$OUT" | grep -q 'first stale: skills/closeout/SKILL.md'; then
  pass "J: FAIL line names the first stale file"
else
  fail "J: FAIL line names the first stale file -- got:
$OUT"
fi
if printf '%s\n' "$OUT" | grep -qE '^VERDICT: FAIL'; then pass "J: VERDICT FAIL line"; else fail "J: VERDICT FAIL line"; fi

echo "== fixture K: unconfigured home is SKIP, not PASS or FAIL =="
K=$(make_repo repo_k) || exit 1
write_fake_install "$K"
printf 'mode=insync\ntarget=/nonexistent\n' > "$K/scripts/.dryrun-state"
sync_fixture "$K" "fixture: fake install.sh, no harness vars in local.env" || exit 1
OUT=$(gates_noenv --stage post-merge --repo "$K" --default-branch main \
  --local-env "$K/local.env" --no-fetch 2>&1)
RC=$?
assert_exit 0 $RC "K: all-unset homes do not fail the verdict"
assert_gate "$OUT" renders-current SKIP "K: renders-current SKIP"
if printf '%s\n' "$OUT" | grep -q 'GATE renders-current  *PASS'; then
  fail "K: an unset home must not report PASS -- got:
$OUT"
else
  pass "K: no PASS line for an unset home"
fi

echo "== fixture L: a non-zero dry-run is FAIL, never a silent PASS =="
printf 'mode=exit3\ntarget=%s\n' "$I_HOME" > "$I/scripts/.dryrun-state"
sync_fixture "$I" "fixture: flip dry-run state to exit3" || exit 1
OUT=$(gates_noenv --stage post-merge --repo "$I" --default-branch main \
  --local-env "$I/local.env" --no-fetch 2>&1)
RC=$?
assert_exit 1 $RC "L: dry-run exiting 3 fails the verdict"
assert_gate "$OUT" renders-current FAIL "L: renders-current FAIL"
if printf '%s\n' "$OUT" | grep -q 'exited 3'; then
  pass "L: FAIL line names the exit code"
else
  fail "L: FAIL line names the exit code -- got:
$OUT"
fi

echo "== fixture N: a dry-run with no target banner is FAIL, not a pass =="
# The counts alone are not enough: with no "dry-run state for <h> at <target>"
# line the gate cannot confirm the report describes the home it resolved.
printf 'mode=nobanner\ntarget=%s\n' "$I_HOME" > "$I/scripts/.dryrun-state"
sync_fixture "$I" "fixture: flip dry-run state to nobanner" || exit 1
OUT=$(gates_noenv --stage post-merge --repo "$I" --default-branch main \
  --local-env "$I/local.env" --no-fetch 2>&1)
RC=$?
assert_exit 1 $RC "N: missing target banner fails the verdict"
assert_gate "$OUT" renders-current FAIL "N: renders-current FAIL"
if printf '%s\n' "$OUT" | grep -q "no 'dry-run state for' target line"; then
  pass "N: FAIL line names the absent banner"
else
  fail "N: FAIL line names the absent banner -- got:
$OUT"
fi

echo "== fixture O: stale=0 falls back to naming the first missing file =="
printf 'mode=missing\ntarget=%s\n' "$I_HOME" > "$I/scripts/.dryrun-state"
sync_fixture "$I" "fixture: flip dry-run state to missing" || exit 1
OUT=$(gates_noenv --stage post-merge --repo "$I" --default-branch main \
  --local-env "$I/local.env" --no-fetch 2>&1)
RC=$?
assert_exit 1 $RC "O: a missing managed file fails the verdict"
assert_gate "$OUT" renders-current FAIL "O: renders-current FAIL"
if printf '%s\n' "$OUT" | grep -q 'stale=0 broken=0 missing=1'; then
  pass "O: FAIL line carries the parsed counts"
else
  fail "O: FAIL line carries the parsed counts -- got:
$OUT"
fi
if printf '%s\n' "$OUT" | grep -q 'first missing: hooks/stuck-detector.sh'; then
  pass "O: FAIL line names the first missing file (stale-list fallback)"
else
  fail "O: FAIL line names the first missing file -- got:
$OUT"
fi

echo "== fixture M: a repo without scripts/install.sh SKIPs the gate =="
# Fixtures G/H are exactly this shape — the gate must not turn them red.
OUT=$(gates_noenv --stage post-merge --repo "$G" --default-branch main --no-fetch 2>&1)
RC=$?
assert_exit 0 $RC "M: no scripts/install.sh keeps the verdict PASS"
assert_gate "$OUT" renders-current SKIP "M: renders-current SKIP (not a framework checkout)"

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "ALL TESTS PASSED"
  exit 0
else
  echo "$FAILURES ASSERTION(S) FAILED"
  exit 1
fi
