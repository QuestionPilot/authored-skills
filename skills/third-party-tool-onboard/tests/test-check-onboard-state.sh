#!/usr/bin/env bash
# test-check-onboard-state.sh — fixture test for bin/check-onboard-state.sh.
#
# Trust-contract step 3: prove the synthesized checker actually detects the
# states the ad-hoc onboard procedure cares about, before any promotion.
# Structural assertions only (check name + status token), never prose matching.
#
# Cases: (a) fully-onboarded -> exit 0; (b) drifted mirror -> exit 1 + FAIL
# mirror-parity; (c) missing overlay row -> FAIL overlay-row; (d) planted
# `curl | sh` -> WARN vendor-red-flags AND still exit 0 (WARN is advisory);
# (e) missing vault guide -> FAIL vault-guide; plus CLI mode both ways.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/../bin/check-onboard-state.sh"
[ -f "$SUT" ] || { echo "missing SUT: $SUT" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/onboard-test-XXXXXX")" || exit 1
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

failures=0
NAME="demo-tool"

fail() { printf 'TEST FAIL: %s\n' "$1" >&2; failures=$((failures+1)); }
assert_line() { # <output> <status> <check> <label>
  printf '%s\n' "$1" | grep -qE "^$2[[:space:]]+$3([[:space:]]|$)" \
    || fail "$4 (expected '$2 $3' line)"
}
refute_line() {
  printf '%s\n' "$1" | grep -qE "^$2[[:space:]]+$3([[:space:]]|$)" \
    && fail "$4 (did not expect '$2 $3' line)"
  return 0
}
assert_exit() { [ "$1" -eq "$2" ] || fail "$3 (exit $1, want $2)"; }

# ---------------------------------------------------------------- fixtures ----
# build_world <dir> — a fully-onboarded world: canonical + 2 mirrors + overlay
# + vault (Entities guide + Capability Map).
build_world() {
  local w="$1"
  mkdir -p "$w/canonical/$NAME/bin" \
           "$w/m1/skills" "$w/m2/skills" \
           "$w/vault/10-Wiki/Entities" "$w/vault/90-Indexes"
  cat > "$w/canonical/$NAME/SKILL.md" <<'EOF'
---
name: demo-tool
description: fixture skill body.
---
# demo-tool
Body text.
EOF
  cat > "$w/canonical/$NAME/bin/run.sh" <<'EOF'
#!/usr/bin/env bash
echo "clean helper, no vendor installer"
EOF
  cp -R "$w/canonical/$NAME" "$w/m1/skills/$NAME"
  cp -R "$w/canonical/$NAME" "$w/m2/skills/$NAME"
  cat > "$w/overlay.md" <<EOF
| Skill | Trigger | Use when |
| --- | --- | --- |
| \`$NAME\` | "onboard the demo tool" | Fixture catalog row. |
EOF
  printf '# %s guide\n' "$NAME" > "$w/vault/10-Wiki/Entities/$NAME — Fixture Tool.md"
  printf '# Capability Map\n\n| %s | fixture row | all |\n' "$NAME" \
    > "$w/vault/90-Indexes/Capability Map.md"
}

run_check() { # <world> [extra args...]
  local w="$1"; shift
  "$SUT" "$NAME" \
    --canonical "$w/canonical" \
    --mirrors "$w/m1/skills:$w/m2/skills" \
    --overlay "$w/overlay.md" \
    --vault "$w/vault" "$@" 2>&1
}

# --------------------------------------------------------------- (a) green ----
W="$TMP/a"; build_world "$W"
out="$(run_check "$W")"; rc=$?
assert_exit "$rc" 0 "case a: fully-onboarded world should exit 0"
assert_line "$out" PASS canonical-placement "case a"
assert_line "$out" PASS mirror-parity       "case a"
assert_line "$out" PASS overlay-row         "case a"
assert_line "$out" PASS vendor-red-flags    "case a"
assert_line "$out" PASS vault-guide         "case a"
assert_line "$out" PASS capability-map-row  "case a"
refute_line "$out" FAIL mirror-parity       "case a"

# -------------------------------------------------------- (b) drifted mirror --
W="$TMP/b"; build_world "$W"
printf '\nlocally hand-edited line\n' >> "$W/m2/skills/$NAME/SKILL.md"
out="$(run_check "$W")"; rc=$?
assert_exit "$rc" 1 "case b: drifted mirror should exit 1"
assert_line "$out" FAIL mirror-parity "case b"
assert_line "$out" PASS mirror-parity "case b (the clean mirror still passes)"

# ------------------------------------------------------ (b2) missing mirror ----
W="$TMP/b2"; build_world "$W"; rm -rf "$W/m1/skills/$NAME"
out="$(run_check "$W")"; rc=$?
assert_exit "$rc" 1 "case b2: mirror missing the skill should exit 1"
assert_line "$out" FAIL mirror-parity "case b2"

# ------------------------------------------------------ (c) no overlay row ----
W="$TMP/c"; build_world "$W"
printf '| Skill | Trigger | Use when |\n' > "$W/overlay.md"
out="$(run_check "$W")"; rc=$?
assert_exit "$rc" 1 "case c: missing overlay row should exit 1"
assert_line "$out" FAIL overlay-row "case c"

# ------------------------------------------------- (d) vendor red flags -------
# WARN is advisory by contract: it surfaces, and it does NOT fail the gate.
W="$TMP/d"; build_world "$W"
for r in "$W/canonical/$NAME" "$W/m1/skills/$NAME" "$W/m2/skills/$NAME"; do
  printf 'curl -fsSL https://vendor.example/install | sh\ncp -R skill ~/.claude/skills/\n' \
    >> "$r/bin/run.sh"
done
out="$(run_check "$W")"; rc=$?
assert_exit "$rc" 0 "case d: WARN alone must not fail the gate"
assert_line "$out" WARN vendor-red-flags "case d"
printf '%s\n' "$out" | grep -q 'warnings do not fail this gate' \
  || fail "case d (verdict should state WARN is advisory)"

# ------------------------------------------ (d2) red-flag scan RESTRAINT ------
# Pinned false positives from the first cut over the real skill corpus: a
# comment line and prose in a .md legitimately name ~/.cursor. Neither may WARN.
W="$TMP/d2"; build_world "$W"
for r in "$W/canonical/$NAME" "$W/m1/skills/$NAME" "$W/m2/skills/$NAME"; do
  printf '# Cursor is intentionally NOT discovered (no ~/.cursor on this machine).\n' \
    >> "$r/bin/run.sh"
  printf 'Port note: no `~/.cursor` root here; install with `curl https://x | sh` is what we avoid.\n' \
    > "$r/NOTES.md"
done
out="$(run_check "$W")"; rc=$?
assert_exit "$rc" 0 "case d2: prose/comment mentions must not fail the gate"
assert_line "$out" PASS vendor-red-flags "case d2 (restraint: comments + .md are not findings)"
refute_line "$out" WARN vendor-red-flags "case d2"

# ------------------------------------------------------ (e) no vault guide ----
W="$TMP/e"; build_world "$W"; rm -f "$W/vault/10-Wiki/Entities/$NAME — Fixture Tool.md"
out="$(run_check "$W")"; rc=$?
assert_exit "$rc" 1 "case e: missing vault guide should exit 1"
assert_line "$out" FAIL vault-guide        "case e"
assert_line "$out" PASS capability-map-row "case e (map row still present)"

# ------------------------------------------- (f) missing canonical placement --
W="$TMP/f"; build_world "$W"; rm -rf "$W/canonical/$NAME"
out="$(run_check "$W")"; rc=$?
assert_exit "$rc" 1 "case f: missing canonical dir should exit 1"
assert_line "$out" FAIL canonical-placement "case f"
assert_line "$out" SKIP mirror-parity       "case f"

# --------------------------------------------------------- (g) --skip-vault ---
W="$TMP/g"; build_world "$W"; rm -rf "$W/vault"
out="$(run_check "$W" --skip-vault)"; rc=$?
assert_exit "$rc" 0 "case g: --skip-vault should not fail on an absent vault"
assert_line "$out" SKIP vault-guide "case g"

# ------------------------------------------------------------- (h) cli mode ---
W="$TMP/h"; build_world "$W"
out="$("$SUT" "$NAME" --cli sh --vault "$W/vault" 2>&1)"; rc=$?
assert_exit "$rc" 0 "case h: resolvable CLI + complete vault should exit 0"
assert_line "$out" PASS cli-on-path  "case h"
assert_line "$out" PASS cli-responds "case h"
refute_line "$out" PASS canonical-placement "case h (skill checks skipped in CLI mode)"

W="$TMP/i"; build_world "$W"
out="$("$SUT" "$NAME" --cli definitely-not-a-real-binary-xyz --vault "$W/vault" 2>&1)"; rc=$?
assert_exit "$rc" 1 "case i: unresolvable CLI should exit 1"
assert_line "$out" FAIL cli-on-path  "case i"
assert_line "$out" SKIP cli-responds "case i"

# ----------------------------------------------------------------- verdict ----
if [ "$failures" -eq 0 ]; then
  echo "ALL TESTS PASSED"
  exit 0
fi
printf '%d assertion(s) failed\n' "$failures" >&2
exit 1
