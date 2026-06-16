#!/usr/bin/env bash
# scan-outbound.sh — outbound-content exfil scan helper.
#
# Sourced by the cross-model-review capability before each critic pipe
# (codex / agy / claude exec). Harness-neutral: the native-compile asset-copy
# path packages this file into each harness's installed skill directory
# (<config-dir>/skills/cross-model-review/scan-outbound.sh). The realization
# names the concrete per-harness source path.
#
# Contract:
#   scan_outbound <input-file> [<run-dir>]
#     return 0  — clean (no credential-shape match); caller proceeds with pipe
#     return 1  — at least one match; <run-dir>/exfil-block.md written;
#                 caller must NOT pipe to the external model
#     return 2  — error (missing/invalid args, missing input, missing grep,
#                 grep exited with an unexpected non-0/1 status). FAIL CLOSED:
#                 callers MUST treat 2 the same as 1 — do not pipe.
#
# All patterns are runtime-constructed from non-matching halves so this
# very file does not self-trip the scan when piped through cross-model-review.

scan_outbound() {
  # Argument-count guard BEFORE reading $1 — under `set -u`, reading $1 with no
  # args would abort the calling script with an unbound-variable error rather
  # than returning the documented contract code.
  if [ "$#" -lt 1 ]; then
    printf 'scan_outbound: usage: scan_outbound <input-file> [<run-dir>]\n' >&2
    return 2
  fi

  local input="$1"
  local rundir="${2:-$(dirname "$input")}"

  # Input must exist AND be readable. Either failure = fail closed.
  if [ ! -f "$input" ]; then
    printf 'scan_outbound: input file not found: %s\n' "$input" >&2
    return 2
  fi
  if [ ! -r "$input" ]; then
    printf 'scan_outbound: input file not readable: %s\n' "$input" >&2
    return 2
  fi

  mkdir -p "$rundir" || {
    printf 'scan_outbound: cannot create rundir: %s\n' "$rundir" >&2
    return 2
  }
  local block_log="$rundir/exfil-block.md"

  # Build pattern strings from non-matching halves at runtime. None of these
  # literal source lines, on their own, match the assembled patterns.
  local sk_a="sk-"
  local xox_a="xox"; local xox_b='[bap]-'
  local gh_a="gh"; local gh_b='[pousr]_'
  local aws_a="AKIA"

  local patterns=(
    "${sk_a}[A-Za-z0-9_-]{32,}"             # provider API keys (sk-ant-, sk-proj-, sk-...)
    "${xox_a}${xox_b}[A-Za-z0-9-]{30,}"     # chat-platform tokens
    "${gh_a}${gh_b}[A-Za-z0-9_]{36,}"       # version-control tokens
    "${aws_a}[0-9A-Z]{16}"                  # cloud access keys
    "[a-fA-F0-9]{40,}"                      # high-entropy hex (tunable)
  )

  # /usr/bin/grep explicitly — bypass any shell ugrep overlay. -E for POSIX-ERE; no \b (BSD silently no-ops it).
  local grep_bin="/usr/bin/grep"
  [ -x "$grep_bin" ] || grep_bin="$(command -v grep)"

  # If grep is missing entirely, fail closed — we cannot prove the input clean.
  if [ -z "$grep_bin" ] || [ ! -x "$grep_bin" ]; then
    printf 'scan_outbound: grep not available — failing closed\n' >&2
    return 2
  fi

  local hit=0
  local p match grep_rc
  for p in "${patterns[@]}"; do
    # Capture grep's exit code explicitly. grep -E returns:
    #   0 — at least one match (treat as hit)
    #   1 — no match (treat as clean for this pattern)
    #   2 — error (binary problem, file unreadable mid-run, ...) → fail closed
    "$grep_bin" -oE "$p" "$input" >/dev/null 2>&1
    grep_rc=$?
    case "$grep_rc" in
      0)  # Match — record it.
        hit=1
        match="$("$grep_bin" -oE "$p" "$input" | head -1)"
        {
          printf '## Outbound exfil block — %s\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
          printf -- '- input: `%s`\n' "$input"
          printf -- '- pattern: `%s`\n' "$p"
          # Redact: log first 6 chars of match only, then `...xxx`.
          printf -- '- match (redacted): `%s...xxx`\n\n' "${match:0:6}"
        } >> "$block_log"
        ;;
      1)  # No match — clean for this pattern.
        ;;
      *)  # Unexpected grep failure — fail closed (do NOT return 0).
        printf 'scan_outbound: grep exited %s on pattern %s — failing closed\n' \
          "$grep_rc" "$p" >&2
        return 2
        ;;
    esac
  done

  return "$hit"
}

# When invoked directly (not sourced), run on "$@" with exit-code passthrough.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  scan_outbound "$@"
  exit $?
fi
