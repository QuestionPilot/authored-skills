#!/usr/bin/env bash
# collect-toolkit-state.sh — deterministic installed-state collector for the
# manual toolkit sweep (QUE-589). Read-only: never installs, updates, or
# deletes. Network use is limited to package-registry staleness queries
# (brew/npm outdated); everything else is local. Emits a markdown report to
# stdout; every section prints its denominator so an empty section reads as
# "0 probed", never as "clean".
#
# Probes are bounded via perl alarm (macOS ships no `timeout`). Honest limit:
# the alarm kills the exec'd process, not descendants it may spawn — a probe
# that forks a child holding stdout can still stall the capture; stdin is
# closed on every probe to narrow that window. A probe that fails or times
# out is reported UNPROBED — never clean. Accepted residual: enumeration is
# newline-delimited, so a filename containing a literal newline would corrupt
# rows/denominators — no such name belongs in a skills root or bin dir.
set -u
LC_ALL=C; export LC_ALL

PROBE_SECS="${PROBE_SECS:-10}"
case "$PROBE_SECS" in (''|*[!0-9]*) PROBE_SECS=bad;; esac
if [ "$PROBE_SECS" = bad ] || [ "${#PROBE_SECS}" -gt 4 ] || [ "$PROBE_SECS" -le 0 ]; then
  echo "invalid PROBE_SECS (need positive integer 1-9999)" >&2; exit 2
fi
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
CANONICAL="${CANONICAL:-$HOME/Agentic OS/.claude/skills}"
PARITY_SCRIPT="${PARITY_SCRIPT:-$HOME/Agentic OS/scripts/operator-skill-parity-check.sh}"

bounded() { # bounded <seconds> <cmd...> — perl-alarm bound; SIGALRM surfaces as rc=142
  perl -e 'alarm shift; exec @ARGV' "$@" 2>&1
}

echo "# Toolkit sweep — installed-state collection"
echo
echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ) on $(hostname -s)"
echo

# ---------------------------------------------------------------- skills roots
echo "## Skill roots"
echo
if [ -d "$CANONICAL" ]; then
  skill_list=$(find "$CANONICAL" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
  n=$(printf '%s\n' "$skill_list" | grep -c . || true)
  echo "Canonical root: $CANONICAL — denominator: $n skill dir(s) enumerated:"
  echo
  if [ "$n" -eq 0 ]; then
    echo "0 skill dirs found — UNPROBED as a surface (an empty canonical root is a finding, not clean); verify by hand."
  else
    printf '%s\n' "$skill_list" | while IFS= read -r d; do echo "- $(basename "$d")"; done
  fi
else
  echo "UNPROBED: canonical skills root not found at $CANONICAL — denominator: 0 of expected ≥1 surface."
fi
echo

echo "## Mirror parity"
echo
if [ -f "$PARITY_SCRIPT" ]; then
  parity_out=$(bounded 120 bash "$PARITY_SCRIPT" </dev/null); parity_rc=$?
  echo '```'
  printf '%s\n' "$parity_out"
  echo '```'
  echo
  if [ "$parity_rc" -eq 142 ]; then
    echo "Parity gate: UNPROBED (timed out at 120s — rc=142)"
  else
    echo "Parity gate exit: $parity_rc ($([ "$parity_rc" -eq 0 ] && echo PASS || echo FAIL))"
  fi
else
  echo "UNPROBED: parity script not found at $PARITY_SCRIPT"
fi
echo

# ---------------------------------------------------------------- PATH bins
echo "## CLI binaries in $BIN_DIR"
echo
if [ -d "$BIN_DIR" ]; then
  bin_list=$(find "$BIN_DIR" -maxdepth 1 \( -type f -o -type l \) -perm +111 2>/dev/null | sort)
  total=$(printf '%s\n' "$bin_list" | grep -c . || true)
  echo "Denominator: $total executable(s) found; each probed with a bounded --version."
  echo
  if [ "$total" -eq 0 ]; then
    echo "0 executables found — UNPROBED as a surface (an empty bin dir is a finding, not clean); verify by hand."
  else
    echo '| binary | version probe (first line) | status |'
    echo '| --- | --- | --- |'
    probed=0; unprobed=0
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      b=$(basename "$p")
      raw=$(bounded "$PROBE_SECS" "$p" --version </dev/null); rc=$?
      out=$(printf '%s\n' "$raw" | head -1 | cut -c1-100 | tr '|' '/')
      if [ $rc -eq 0 ] && [ -n "$out" ]; then
        echo "| $b | $out | PROBED |"; probed=$((probed+1))
      elif [ $rc -eq 142 ]; then
        echo "| $b | TIMEOUT at ${PROBE_SECS}s (rc=142) | UNPROBED |"; unprobed=$((unprobed+1))
      else
        echo "| $b | rc=$rc ${out:-no output} | UNPROBED |"; unprobed=$((unprobed+1))
      fi
    done <<EOF_BINS
$bin_list
EOF_BINS
    echo
    echo "Probe summary: $probed PROBED, $unprobed UNPROBED of $total. UNPROBED means the"
    echo "probe did not produce a version — it is NOT clean; resolve or note each one."
  fi
else
  echo "UNPROBED: bin dir not found at $BIN_DIR — denominator: 0 of expected ≥1 surface."
fi
echo

# ------------------------------------------------- package managers (network)
echo "## Package-manager views (staleness raw material — registry queries)"
echo
if command -v brew >/dev/null 2>&1; then
  echo "### brew outdated"
  brew_out=$(bounded 120 brew outdated --verbose </dev/null); brew_rc=$?
  echo '```'
  printf '%s\n' "$brew_out"
  echo '```'
  if [ "$brew_rc" -eq 0 ]; then
    echo "(brew probe ran, rc=0 — an empty block above means nothing outdated)"
  else
    echo "UNPROBED: brew outdated failed or timed out (rc=$brew_rc) — the block above is NOT a clean result."
  fi
else
  echo "brew: not installed — 0 packages probed (UNPROBED as a surface)"
fi
echo
if command -v npm >/dev/null 2>&1; then
  echo "### npm -g outdated"
  npm_out=$(bounded 120 npm outdated -g </dev/null); npm_rc=$?
  echo '```'
  printf '%s\n' "$npm_out"
  echo '```'
  # npm outdated: rc=0 nothing outdated, rc=1 WITH table = outdated packages exist,
  # rc=1 with empty output or any other rc = a failed probe, not a clean result.
  if [ "$npm_rc" -eq 0 ]; then
    echo "(npm probe ran, rc=0 — nothing outdated)"
  elif [ "$npm_rc" -eq 1 ] && printf '%s\n' "$npm_out" | head -1 | grep -q '^Package'; then
    echo "(npm probe ran, rc=1 with a table — the packages above are outdated)"
  else
    echo "UNPROBED: npm outdated failed or timed out (rc=$npm_rc) — the block above is NOT a clean result."
  fi
else
  echo "npm: not installed — 0 packages probed (UNPROBED as a surface)"
fi
echo
echo "END OF COLLECTION — judgment (source compare, smoke, drift, re-vet) is the model's half."
