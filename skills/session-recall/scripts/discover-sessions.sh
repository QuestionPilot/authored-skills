#!/usr/bin/env bash
# Discover prior coding-agent session files across Claude Code + Codex.
#
# Usage:
#   discover-sessions.sh <days> [--platform claude|codex|all]
#                               [--exclude-active-min N] [--exclude PATH]...
#
# Outputs one absolute session-file path per line, for files modified within the
# last <days>. Pipe to extract-metadata.py for parsing/filtering:
#   discover-sessions.sh 7 | tr '\n' '\0' | xargs -0 python3 extract-metadata.py --cwd-filter <repo>
#
# PORT NOTES (vs the CE ce-sessions original — see reference/port-notes.md):
#   - Claude transcripts live under "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
#     (this operator's config is relocated; $HOME/.claude does not exist).
#   - Codex/.agents session roots honor $CODEX_HOME / $AGENTS_DIR (this
#     operator co-locates them at <repo>/.codex and <repo>/.agents via
#     local.env), with a local.env fallback for env-less shells; ~/.codex and
#     ~/.agents remain the stock defaults. Roots are deduped.
#   - Repo scoping is NOT done here by directory-name globbing (the encoded dir
#     names replace spaces with '-', so a path like "Space Dir" never
#     substring-matches its encoded dir "-Users-...-Space-Dir"). Instead we
#     scan ALL project dirs and let extract-metadata.py --cwd-filter scope on the
#     transcript's real `cwd` field. Omit --cwd-filter downstream for "all repos".
#   - Cursor is intentionally NOT discovered (no ~/.cursor on this machine).
#   - --exclude-active-min N drops files modified within the last N minutes, i.e.
#     the current session AND any concurrent live session (their transcripts are
#     incomplete and the current one is already in the caller's context).
#   - bash 3.2 safe: no declare -A / mapfile / negative indexing; guarded globs.

set -euo pipefail

usage() {
    echo "Usage: discover-sessions.sh <days> [--platform claude|codex|all] [--exclude-active-min N] [--exclude PATH]..." >&2
    exit 2
}

[ $# -ge 1 ] || usage
DAYS="$1"; shift
case "$DAYS" in ''|*[!0-9]*) echo "days must be a non-negative integer" >&2; usage ;; esac

PLATFORM="all"
EXCLUDE_ACTIVE_MIN="2"
EXCLUDES=""   # newline-separated absolute paths to drop verbatim

while [ $# -gt 0 ]; do
    case "$1" in
        --platform)
            [ $# -ge 2 ] || { echo "--platform requires a value" >&2; usage; }
            PLATFORM="$2"; shift 2 ;;
        --exclude-active-min)
            [ $# -ge 2 ] || { echo "--exclude-active-min requires a value" >&2; usage; }
            EXCLUDE_ACTIVE_MIN="$2"; shift 2 ;;
        --exclude)
            [ $# -ge 2 ] || { echo "--exclude requires a value" >&2; usage; }
            EXCLUDES="${EXCLUDES}${2}
"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; usage ;;
    esac
done

case "$PLATFORM" in claude|codex|all) ;; *) echo "Unknown platform: $PLATFORM" >&2; usage ;; esac
case "$EXCLUDE_ACTIVE_MIN" in ''|*[!0-9]*) echo "--exclude-active-min must be a non-negative integer" >&2; usage ;; esac

# Build the shared find predicate. When EXCLUDE_ACTIVE_MIN > 0 we add
# "! -mmin -N" so files touched within the last N minutes (live sessions) are
# skipped. macOS/BSD and GNU find both support -mtime/-mmin.
find_jsonl() {
    # $1 = base dir
    if [ "$EXCLUDE_ACTIVE_MIN" -gt 0 ]; then
        find "$1" -type f -name '*.jsonl' -mtime "-${DAYS}" ! -mmin "-${EXCLUDE_ACTIVE_MIN}" 2>/dev/null
    else
        find "$1" -type f -name '*.jsonl' -mtime "-${DAYS}" 2>/dev/null
    fi
}

discover_claude() {
    local base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
    [ -d "$base" ] || return 0
    find_jsonl "$base"
}

discover_codex() {
    # Codex-style session roots (Codex + the .agents co-render). The stock
    # homes are ~/.codex and ~/.agents, but this operator relocates them via
    # local.env (CODEX_HOME / AGENTS_DIR) — a $HOME-hardcoded scan silently
    # finds zero Codex sessions here. Resolution order per home: the env var,
    # the framework local.env (located via $AI_CONFIG_DIR, the parent of
    # $CLAUDE_CONFIG_DIR, or this render's own parent dir — co-located homes
    # sit at <repo>/.<harness>), then the $HOME default. Roots are deduped so
    # a stock CODEX_HOME=~/.codex does not double-emit.
    local codex_home="${CODEX_HOME:-}" agents_dir="${AGENTS_DIR:-}"
    local US
    US="$(printf '\037')"
    if [ -z "$codex_home" ] || [ -z "$agents_dir" ]; then
        local script_dir env_file="" cand vals
        script_dir="$(cd "$(dirname "$0")" && pwd)"
        for cand in "${AI_CONFIG_DIR:-}" \
                    "${CLAUDE_CONFIG_DIR:+$(cd "${CLAUDE_CONFIG_DIR}/.." 2>/dev/null && pwd)}" \
                    "$(cd "$script_dir/../../../.." 2>/dev/null && pwd)"; do
            [ -n "$cand" ] && [ -f "$cand/local.env" ] && { env_file="$cand/local.env"; break; }
        done
        if [ -n "$env_file" ]; then
            # Source in a throwaway subshell — local.env is the operator's own
            # trusted config (install.sh sources it too). \037-delimited pair.
            vals="$( (set +eu; . "$env_file" >/dev/null 2>&1; printf '%s%s%s' "${CODEX_HOME:-}" "$US" "${AGENTS_DIR:-}") 2>/dev/null || true)"
            case "$vals" in
                *"$US"*)
                    [ -n "$codex_home" ] || codex_home="${vals%%"$US"*}"
                    [ -n "$agents_dir" ] || agents_dir="${vals#*"$US"}"
                    ;;
            esac
        fi
    fi
    local base seen="$US"
    for base in "${codex_home:-$HOME/.codex}/sessions" "$HOME/.codex/sessions" \
                "${agents_dir:-$HOME/.agents}/sessions" "$HOME/.agents/sessions"; do
        case "$seen" in *"${US}${base}${US}"*) continue ;; esac
        seen="${seen}${base}${US}"
        [ -d "$base" ] || continue
        # Codex nests by date (sessions/YYYY/MM/DD/rollout-*.jsonl); find recurses.
        find_jsonl "$base"
    done
}

emit() {
    case "$PLATFORM" in
        claude) discover_claude ;;
        codex)  discover_codex ;;
        all)    discover_claude; discover_codex ;;
    esac
}

if [ -n "$EXCLUDES" ]; then
    exfile="$(mktemp -t session-recall-excl-XXXXXX)"
    printf '%s' "$EXCLUDES" > "$exfile"
    # -x whole-line, -F fixed-string, -v invert: drop exact-path matches.
    emit | grep -vxF -f "$exfile" || true
    rm -f "$exfile"
else
    emit
fi
