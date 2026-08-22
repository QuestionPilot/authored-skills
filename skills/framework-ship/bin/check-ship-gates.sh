#!/usr/bin/env bash
# check-ship-gates.sh — deterministic ship-gate STATE checker for framework
# (agentic-os-template) changes. Run from inside the THROWAWAY clone.
#
# Prints one line per gate (`GATE <name>  PASS|FAIL|WARN|SKIP  <detail>`) plus a
# final VERDICT line and the denominator. Exit 0 only when no gate FAILed.
#
# Assumptions pinned here: Bash 3.2 (macOS default), LC_ALL=C for byte-stable
# text handling, git + grep + awk only. `set -uo pipefail` deliberately WITHOUT
# `-e` so every gate reports before the verdict (a fail-fast gate would hide all
# but the first failure).
#
# Kill switch: this script has no bypass flag by design. To ship without a gate,
# drop the flag that selects it (e.g. omit --verify-log) — it then reports SKIP
# and the verdict says so, which is visible in the log.
#
# No PowerShell twin: this is an operator-local skill script, not a shipped
# framework `scripts/*.sh` gate.

set -uo pipefail
export LC_ALL=C

STAGE=""
REPO="."
LOCAL_ENV="${LOCAL_ENV:-}"
VERIFY_LOG=""
CHECK_CLEAN_LOG=""
VERIFY_MARKER="${VERIFY_MARKER:-PASSED}"
CHECK_CLEAN_MARKER="${CHECK_CLEAN_MARKER:-PASSED}"
DEFAULT_BRANCH=""
TWIN_WAIVER=""
DO_FETCH=1

usage() {
  cat <<'EOF'
Usage: check-ship-gates.sh --stage <pre-push|post-merge> [options]

Options:
  --repo <path>               Repo to inspect (default: current directory)
  --local-env <path>          File holding COMMIT_IDENTITY_ALLOWLIST
                              (default: $LOCAL_ENV, else <repo>/local.env)
  --verify-log <path>         Log of the clean-clone `make verify` run
  --check-clean-log <path>    Log of the `scripts/check-clean.sh` run
  --verify-marker <string>    Passing marker expected in the verify log
                              (default: "PASSED")
  --check-clean-marker <str>  Passing marker expected in the check-clean log
                              (default: "PASSED")
  --default-branch <name>     Default branch (default: origin/HEAD, else "main")
  --twin-waiver <reason>      Documented reason a changed scripts/*.sh has no
                              co-changed .ps1 twin (downgrades FAIL -> WARN)
  --no-fetch                  Skip `git fetch` in the post-merge stage
  -h, --help                  This text

Log contract (both logs): the file must exist, contain a line matching the
marker, and contain NO line whose word is FAIL. Pass the FULL captured output —
never `make verify | tail`, whose exit code reports tail, not verify.

Gates, pre-push:   branch-not-default, worktree-clean, commit-identity,
                   verify-log, check-clean-log, twin-parity
Gates, post-merge: on-default-branch, worktree-clean, head-matches-origin

Exit 0 only when no gate FAILed. WARN and SKIP do not fail the verdict.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --stage) STAGE="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    --local-env) LOCAL_ENV="${2:-}"; shift 2 ;;
    --verify-log) VERIFY_LOG="${2:-}"; shift 2 ;;
    --check-clean-log) CHECK_CLEAN_LOG="${2:-}"; shift 2 ;;
    --verify-marker) VERIFY_MARKER="${2:-}"; shift 2 ;;
    --check-clean-marker) CHECK_CLEAN_MARKER="${2:-}"; shift 2 ;;
    --default-branch) DEFAULT_BRANCH="${2:-}"; shift 2 ;;
    --twin-waiver) TWIN_WAIVER="${2:-}"; shift 2 ;;
    --no-fetch) DO_FETCH=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "check-ship-gates: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$STAGE" in
  pre-push|post-merge) ;;
  *) echo "check-ship-gates: --stage must be pre-push or post-merge" >&2; exit 2 ;;
esac

cd "$REPO" 2>/dev/null || { echo "check-ship-gates: cannot cd to repo: $REPO" >&2; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "check-ship-gates: not a git repository: $REPO" >&2; exit 2; }

N_PASS=0; N_FAIL=0; N_WARN=0; N_SKIP=0

emit() {
  # emit <STATUS> <gate-name> <detail...>
  _st="$1"; _name="$2"; shift 2
  printf 'GATE %-20s %-4s  %s\n' "$_name" "$_st" "$*"
  case "$_st" in
    PASS) N_PASS=$((N_PASS + 1)) ;;
    FAIL) N_FAIL=$((N_FAIL + 1)) ;;
    WARN) N_WARN=$((N_WARN + 1)) ;;
    SKIP) N_SKIP=$((N_SKIP + 1)) ;;
  esac
}

resolve_default_branch() {
  if [ -n "$DEFAULT_BRANCH" ]; then printf '%s\n' "$DEFAULT_BRANCH"; return; fi
  _ref=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)
  if [ -n "$_ref" ]; then printf '%s\n' "${_ref##*/}"; return; fi
  printf 'main\n'
}
DEF_BRANCH=$(resolve_default_branch)

base_ref() {
  # Prefer the remote-tracking default branch; fall back to the local one.
  if git rev-parse --verify --quiet "refs/remotes/origin/$DEF_BRANCH" >/dev/null 2>&1; then
    printf 'origin/%s\n' "$DEF_BRANCH"
  elif git rev-parse --verify --quiet "refs/heads/$DEF_BRANCH" >/dev/null 2>&1; then
    printf '%s\n' "$DEF_BRANCH"
  else
    printf '\n'
  fi
}

# ---------------------------------------------------------------- gate bodies

gate_worktree_clean() {
  _dirty=$(git status --porcelain 2>/dev/null)
  if [ -z "$_dirty" ]; then
    emit PASS worktree-clean "git status --porcelain empty"
  else
    _n=$(printf '%s\n' "$_dirty" | grep -c . )
    emit FAIL worktree-clean "$_n uncommitted/untracked path(s); quiesce the tree before this gate"
  fi
}

gate_branch_not_default() {
  _cur=$(git branch --show-current 2>/dev/null)
  if [ -z "$_cur" ]; then
    emit FAIL branch-not-default "detached HEAD — push -u origin HEAD is invalid from here"
  elif [ "$_cur" = "$DEF_BRANCH" ]; then
    emit FAIL branch-not-default "on default branch '$DEF_BRANCH' — branch first"
  else
    emit PASS branch-not-default "on '$_cur' (default: $DEF_BRANCH)"
  fi
}

gate_on_default_branch() {
  _cur=$(git branch --show-current 2>/dev/null)
  if [ "$_cur" = "$DEF_BRANCH" ]; then
    emit PASS on-default-branch "on '$DEF_BRANCH'"
  else
    emit FAIL on-default-branch "on '${_cur:-<detached>}', expected '$DEF_BRANCH'"
  fi
}

gate_head_matches_origin() {
  if [ "$DO_FETCH" -eq 1 ]; then git fetch --quiet origin >/dev/null 2>&1; fi
  _remote=$(git rev-parse --verify --quiet "refs/remotes/origin/$DEF_BRANCH" 2>/dev/null)
  _head=$(git rev-parse --verify --quiet HEAD 2>/dev/null)
  if [ -z "$_remote" ]; then
    emit FAIL head-matches-origin "no origin/$DEF_BRANCH ref after fetch"
  elif [ "$_remote" = "$_head" ]; then
    emit PASS head-matches-origin "HEAD == origin/$DEF_BRANCH ($(printf '%s' "$_head" | cut -c1-8))"
  else
    emit FAIL head-matches-origin "HEAD $(printf '%s' "$_head" | cut -c1-8) != origin/$DEF_BRANCH $(printf '%s' "$_remote" | cut -c1-8) — fast-forward the living folder"
  fi
}

read_allowlist() {
  # Echo one allowlist entry per line, or nothing.
  _f="$1"
  [ -f "$_f" ] || return 1
  _raw=$(grep -E '^[[:space:]]*(export[[:space:]]+)?COMMIT_IDENTITY_ALLOWLIST[[:space:]]*=' "$_f" 2>/dev/null | tail -n 1)
  [ -n "$_raw" ] || return 2
  _raw=${_raw#*=}
  # strip surrounding quotes
  _raw=$(printf '%s' "$_raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
                                   -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
  printf '%s' "$_raw" | tr ',' '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$'
}

gate_commit_identity() {
  _env="$LOCAL_ENV"
  [ -n "$_env" ] || _env="local.env"
  _list=$(read_allowlist "$_env"); _rc=$?
  if [ $_rc -eq 1 ]; then
    emit FAIL commit-identity "local.env not found at '$_env' (--local-env / \$LOCAL_ENV)"
    return
  elif [ $_rc -eq 2 ] || [ -z "$_list" ]; then
    emit FAIL commit-identity "COMMIT_IDENTITY_ALLOWLIST empty or absent in '$_env'"
    return
  fi

  _base=$(base_ref)
  if [ -z "$_base" ]; then
    emit FAIL commit-identity "cannot resolve base ref for '$DEF_BRANCH'"
    return
  fi
  _commits=$(git rev-list "$_base..HEAD" 2>/dev/null)
  if [ -z "$_commits" ]; then
    emit FAIL commit-identity "no commits ahead of $_base — nothing to push"
    return
  fi

  _n=0; _bad=""
  for _c in $_commits; do
    _n=$((_n + 1))
    _a=$(git log -1 --format='%an <%ae>' "$_c")
    _k=$(git log -1 --format='%cn <%ce>' "$_c")
    for _who in author:"$_a" committer:"$_k"; do
      _role=${_who%%:*}; _id=${_who#*:}
      _hit=0
      # Bash 3.2: no associative arrays — linear scan of the allowlist.
      while IFS= read -r _entry; do
        [ "$_entry" = "$_id" ] && _hit=1
      done <<EOF
$_list
EOF
      if [ $_hit -eq 0 ]; then
        _bad="$_bad $(printf '%s' "$_c" | cut -c1-8)/$_role=[$_id]"
      fi
    done
  done

  if [ -n "$_bad" ]; then
    emit FAIL commit-identity "$_n commit(s) vs $_base; off-allowlist:$_bad"
  else
    emit PASS commit-identity "$_n commit(s) vs $_base, author+committer both on allowlist"
  fi
}

check_log() {
  # check_log <gate-name> <path> <marker>
  _gate="$1"; _path="$2"; _marker="$3"
  if [ -z "$_path" ]; then
    emit SKIP "$_gate" "no log supplied — gate not proven, do not treat as passed"
    return
  fi
  if [ ! -f "$_path" ]; then
    emit FAIL "$_gate" "log not found: $_path"
    return
  fi
  _fails=$(grep -c -E '(^|[^A-Za-z])FAIL([^A-Za-z]|$)' "$_path" 2>/dev/null)
  [ -n "$_fails" ] || _fails=0
  _marks=$(grep -c -F -- "$_marker" "$_path" 2>/dev/null)
  [ -n "$_marks" ] || _marks=0
  _lines=$(grep -c '' "$_path" 2>/dev/null)
  if [ "$_fails" -gt 0 ]; then
    emit FAIL "$_gate" "$_fails FAIL line(s) in $_path ($_lines lines scanned)"
  elif [ "$_marks" -lt 1 ]; then
    emit FAIL "$_gate" "marker '$_marker' absent from $_path ($_lines lines scanned)"
  else
    emit PASS "$_gate" "marker '$_marker' present, 0 FAIL lines ($_lines lines scanned)"
  fi
}

gate_twin_parity() {
  _base=$(base_ref)
  if [ -z "$_base" ]; then
    emit FAIL twin-parity "cannot resolve base ref for '$DEF_BRANCH'"
    return
  fi
  _changed=$(git diff --name-only "$_base"...HEAD 2>/dev/null)
  _shs=$(printf '%s\n' "$_changed" | grep -E '^scripts/.*\.sh$')
  if [ -z "$_shs" ]; then
    emit PASS twin-parity "no changed scripts/*.sh — twin rule inapplicable"
    return
  fi
  _n=0; _missing=""; _stale=""
  while IFS= read -r _sh; do
    [ -n "$_sh" ] || continue
    _n=$((_n + 1))
    _twin="${_sh%.sh}.ps1"
    if printf '%s\n' "$_changed" | grep -qx -- "$_twin"; then
      continue
    elif [ -f "$_twin" ]; then
      _stale="$_stale $_twin"
    else
      _missing="$_missing $_twin"
    fi
  done <<EOF
$_shs
EOF

  if [ -n "$_missing" ]; then
    if [ -n "$TWIN_WAIVER" ]; then
      emit WARN twin-parity "$_n changed .sh; twin absent:$_missing; waived: $TWIN_WAIVER"
    else
      emit FAIL twin-parity "$_n changed .sh; no .ps1 twin exists:$_missing"
    fi
  elif [ -n "$_stale" ]; then
    emit WARN twin-parity "$_n changed .sh; twin exists but NOT co-changed:$_stale${TWIN_WAIVER:+; waived: $TWIN_WAIVER}"
  else
    emit PASS twin-parity "$_n changed .sh, each with a co-changed .ps1 twin"
  fi
}

# ---------------------------------------------------------------------- drive

printf 'check-ship-gates: stage=%s repo=%s default-branch=%s\n' \
  "$STAGE" "$(pwd -P)" "$DEF_BRANCH"

if [ "$STAGE" = "pre-push" ]; then
  gate_branch_not_default
  gate_worktree_clean
  gate_commit_identity
  check_log verify-log "$VERIFY_LOG" "$VERIFY_MARKER"
  check_log check-clean-log "$CHECK_CLEAN_LOG" "$CHECK_CLEAN_MARKER"
  gate_twin_parity
else
  gate_on_default_branch
  gate_worktree_clean
  gate_head_matches_origin
fi

N_TOTAL=$((N_PASS + N_FAIL + N_WARN + N_SKIP))
if [ "$N_FAIL" -eq 0 ]; then
  printf 'VERDICT: PASS  gates=%d pass=%d warn=%d skip=%d fail=0\n' \
    "$N_TOTAL" "$N_PASS" "$N_WARN" "$N_SKIP"
  exit 0
else
  printf 'VERDICT: FAIL  gates=%d pass=%d warn=%d skip=%d fail=%d\n' \
    "$N_TOTAL" "$N_PASS" "$N_WARN" "$N_SKIP" "$N_FAIL"
  exit 1
fi
