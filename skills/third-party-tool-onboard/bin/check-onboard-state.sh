#!/usr/bin/env bash
# check-onboard-state.sh — verify the END STATE of a third-party tool onboard.
#
# Complements the vault's bin/operator-skill-parity-check.sh (which sweeps ALL
# operator skills for mirror drift). This one is the per-onboard gate: it checks
# one tool's full end state — placement, mirror parity, overlay row, vendor red
# flags, vault guide, capability-map row — so a single onboard can be proven done
# without re-reading the whole catalog.
#
# Usage:
#   check-onboard-state.sh <tool-name> [options]        # skill onboard
#   check-onboard-state.sh <tool-name> --cli <binary>   # CLI-only onboard
#
# Options (all paths overridable so the checker is testable against fixtures):
#   --cli <binary>        CLI mode: check <binary> on PATH instead of skill roots
#   --canonical <path>    canonical skill root (default: operator .claude/skills)
#   --mirrors <a:b:c>     colon-separated mirror skill roots
#   --overlay <path>      operator skills overlay markdown
#   --vault <path>        vault root (Entities guide + Capability Map live under it)
#   --guide-name <substr> substring to match the vault guide / map row on
#                         (default: the tool name, and its hyphens-as-spaces form)
#   --skip-vault          skip the two vault checks (pre-vault-write dry run)
#
# Output: one `PASS|FAIL|WARN|SKIP  <check>  <detail>` line per check, then a
# verdict. Exit 0 only when every applicable check passed. WARN never fails the
# run on its own — it flags vendor-installer residue for a human read.
#
# Bash 3.2 compatible. No deps beyond coreutils/grep/diff.

set -uo pipefail

OPERATOR_HOME="${AI_CONFIG_DIR:-$HOME/Agentic OS}"
CURSOR_HOME="${CURSOR_CONFIG_DIR:-$HOME/.cursor}"

name=""
cli=""
canonical="$OPERATOR_HOME/.claude/skills"
mirrors="$OPERATOR_HOME/.codex/skills:$OPERATOR_HOME/.agents/skills:$CURSOR_HOME/skills"
overlay="$OPERATOR_HOME/local.skills-overlay.md"
vault="${OBSIDIAN_VAULT_PATH:-}"
guide_name=""
skip_vault=0

die() { printf 'usage: %s <tool-name> [--cli <binary>] [--canonical P] [--mirrors A:B] [--overlay P] [--vault P] [--guide-name S] [--skip-vault]\n' "$(basename "$0")" >&2; [ $# -gt 0 ] && printf 'error: %s\n' "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --cli)        cli="${2:-}"; shift 2 || die "--cli needs a value" ;;
    --canonical)  canonical="${2:-}"; shift 2 || die "--canonical needs a value" ;;
    --mirrors)    mirrors="${2:-}"; shift 2 || die "--mirrors needs a value" ;;
    --overlay)    overlay="${2:-}"; shift 2 || die "--overlay needs a value" ;;
    --vault)      vault="${2:-}"; shift 2 || die "--vault needs a value" ;;
    --guide-name) guide_name="${2:-}"; shift 2 || die "--guide-name needs a value" ;;
    --skip-vault) skip_vault=1; shift ;;
    -h|--help)    die ;;
    -*)           die "unknown option: $1" ;;
    *)            [ -n "$name" ] && die "unexpected argument: $1"; name="$1"; shift ;;
  esac
done
[ -n "$name" ] || die "tool name is required"
[ -n "$guide_name" ] || guide_name="$name"

passes=0; fails=0; warns=0; skips=0
ok()   { printf 'PASS  %-22s %s\n' "$1" "$2"; passes=$((passes+1)); }
bad()  { printf 'FAIL  %-22s %s\n' "$1" "$2"; fails=$((fails+1)); }
warn() { printf 'WARN  %-22s %s\n' "$1" "$2"; warns=$((warns+1)); }
skip() { printf 'SKIP  %-22s %s\n' "$1" "$2"; skips=$((skips+1)); }

# ---------------------------------------------------------------- skill mode --
if [ -z "$cli" ]; then
  placed="$canonical/$name"
  if [ -d "$placed" ]; then
    ok "canonical-placement" "$placed"
  else
    bad "canonical-placement" "skill dir missing: $placed"
  fi

  # Mirror parity — one line per mirror root. A missing root is a FAIL, not a
  # skip: the operator's four roots are all expected to carry the skill, and a
  # silently-skipped root is how a checker passes having compared nothing.
  OLD_IFS="$IFS"; IFS=':'; set -- $mirrors; IFS="$OLD_IFS"
  compared=0
  for root in "$@"; do
    [ -n "$root" ] || continue
    label="$(basename "$(dirname "$root")")/$(basename "$root")"
    if [ ! -d "$placed" ]; then
      skip "mirror-parity" "$label — nothing canonical to compare"
      continue
    fi
    compared=$((compared+1))
    if [ ! -d "$root/$name" ]; then
      bad "mirror-parity" "$label — not present at $root/$name"
      continue
    fi
    if diff -r -q --exclude='.DS_Store' --exclude='__pycache__' \
         "$placed" "$root/$name" >/dev/null 2>&1; then
      ok "mirror-parity" "$label — content-identical"
    else
      bad "mirror-parity" "$label — drifted from canonical"
    fi
  done
  if [ "$compared" -eq 0 ] && [ -d "$placed" ]; then
    bad "mirror-parity" "no mirror root given — compared nothing"
  fi

  # Overlay catalog row.
  if [ ! -f "$overlay" ]; then
    bad "overlay-row" "overlay file missing: $overlay"
  elif grep -F -- "$name" "$overlay" 2>/dev/null | grep -q '^[[:space:]]*|'; then
    ok "overlay-row" "row naming '$name' present in $(basename "$overlay")"
  else
    bad "overlay-row" "no catalog row names '$name' in $overlay"
  fi

  # Vendor-installer red flags inside the placed bundle (advisory).
  # Restraint: only executable lines of bundled SCRIPTS are scanned — prose in
  # .md files and comment lines legitimately name ~/.claude/~/.cursor (a first
  # cut over the real skill corpus flagged two such comments). Biasing to
  # under-reporting keeps the WARN worth reading.
  if [ -d "$placed" ]; then
    flags="$(find "$placed" -type f \
               \( -name '*.sh' -o -name '*.bash' -o -name '*.zsh' -o -name '*.py' \
                  -o -name '*.js' -o -name '*.mjs' -o -name '*.ts' -o -name '*.ps1' \) \
               -print 2>/dev/null \
             | while IFS= read -r f; do
                 grep -In -E '~/\.(claude|cursor)|curl[^|]*\|[[:space:]]*(ba)?sh' "$f" 2>/dev/null \
                   | grep -v -E '^[0-9]+:[[:space:]]*(#|//|\*|<#)' \
                   | sed "s|^|${f}:|"
               done | head -n 20)"
    if [ -n "$flags" ]; then
      warn "vendor-red-flags" "hardcoded harness path or curl-pipe-shell found:"
      printf '%s\n' "$flags" | sed 's/^/        /'
    else
      ok "vendor-red-flags" "no hardcoded ~/.claude|~/.cursor or curl|sh in bundled scripts"
    fi
  else
    skip "vendor-red-flags" "no placed bundle to scan"
  fi
else
# ------------------------------------------------------------------ cli mode --
  # `command -v` under Git Bash resolves `.exe` but NOT `.cmd`/`.bat`/`.ps1`, so
  # a Windows CLI that ships only shell-wrapper launchers reads as "not on PATH"
  # even though the documented extensionless invocation works everywhere else.
  # Fall back through the PATHEXT-style suffixes before failing; the resolved
  # launcher (with its extension) becomes the probe target so cli-responds
  # exercises the same file the OS would run. Unix path: first probe hits,
  # fallback never runs, no new dependency.
  cli_probe="$cli"
  bin_path="$(command -v "$cli" 2>/dev/null)"
  if [ -z "$bin_path" ]; then
    for _ext in .exe .cmd .bat .ps1; do
      bin_path="$(command -v "$cli$_ext" 2>/dev/null)"
      [ -n "$bin_path" ] && { cli_probe="$cli$_ext"; break; }
    done
  fi
  if [ -n "$bin_path" ]; then
    ok "cli-on-path" "$bin_path"
    cli="$cli_probe"
    if "$cli" --version >/dev/null 2>&1; then
      ok "cli-responds" "$cli --version exited 0"
    elif "$cli" --help >/dev/null 2>&1; then
      ok "cli-responds" "$cli --help exited 0"
    else
      bad "cli-responds" "neither --version nor --help exited 0"
    fi
  else
    bad "cli-on-path" "binary '$cli' not on PATH"
    skip "cli-responds" "binary not resolvable"
  fi
fi

# ------------------------------------------------------------ vault (either) --
if [ "$skip_vault" -eq 1 ]; then
  skip "vault-guide" "--skip-vault"
  skip "capability-map-row" "--skip-vault"
elif [ -z "$vault" ] || [ ! -d "$vault" ]; then
  bad "vault-guide" "vault root not found (pass --vault or set OBSIDIAN_VAULT_PATH)"
  bad "capability-map-row" "vault root not found"
else
  # Match the guide on the tool name, and on its hyphens-as-spaces form, so
  # `21st-cli-use` finds a guide titled "21st CLI — …". Use --guide-name when
  # the guide is titled something else entirely.
  alt="$(printf '%s' "$guide_name" | tr '-' ' ')"
  guide="$(ls "$vault/10-Wiki/Entities/" 2>/dev/null \
            | grep -i -F -e "$guide_name" -e "$alt" | head -n 1)"
  if [ -n "$guide" ]; then
    ok "vault-guide" "10-Wiki/Entities/$guide"
  else
    bad "vault-guide" "no Entities guide matching '$guide_name' under $vault/10-Wiki/Entities/"
  fi

  maprow=""
  for m in "$vault"/90-Indexes/Capability\ Map*; do
    [ -f "$m" ] || continue
    if grep -i -q -F -e "$guide_name" -e "$alt" "$m" 2>/dev/null; then
      maprow="$(basename "$m")"; break
    fi
  done
  if [ -n "$maprow" ]; then
    ok "capability-map-row" "$maprow mentions '$guide_name'"
  else
    bad "capability-map-row" "no Capability Map row mentions '$guide_name'"
  fi
fi

# ----------------------------------------------------------------- verdict ----
printf -- '---\n'
if [ "$fails" -eq 0 ]; then
  printf 'PASS  onboard state complete for %s — %d check(s) passed, %d warning(s), %d skipped\n' \
    "$name" "$passes" "$warns" "$skips"
  [ "$warns" -gt 0 ] && printf 'NOTE  warnings do not fail this gate; read them before calling the onboard done\n'
  exit 0
fi
printf 'FAIL  onboard incomplete for %s — %d check(s) failed, %d passed, %d warning(s), %d skipped\n' \
  "$name" "$fails" "$passes" "$warns" "$skips" >&2
exit 1
