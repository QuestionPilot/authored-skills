#!/usr/bin/env bash
# Fixture smoke test for the session-recall skill.
# Covers the Codex-flagged edge set: space-path Claude cwd, strict missing-cwd
# drop, path-component (not substring) cwd match, Codex date-nesting, empty
# discovery, bad --platform / set -u arg edge, scan-past-preamble, redaction.
#
# Run:  bash tests/smoke-test.sh      (exit 0 = all pass)
set -uo pipefail

SR="$(cd "$(dirname "$0")/.." && pwd)"
DISC="$SR/scripts/discover-sessions.sh"
META="$SR/scripts/extract-metadata.py"
SKEL="$SR/scripts/extract-skeleton.py"
ERRS="$SR/scripts/extract-errors.py"
FIX="$SR/tests/fixtures"

pass=0; fail=0
ok()   { pass=$((pass+1)); printf 'PASS  %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf 'FAIL  %s\n' "$1"; }
check(){ # check <desc> <expected-substr> <actual>
  case "$3" in *"$2"*) ok "$1" ;; *) bad "$1 (want '$2' in: $3)" ;; esac
}

TMP="$(mktemp -d -t session-recall-test-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# --- Build a fake relocated Claude config with a SPACE-encoded project dir ---
CFG="$TMP/Space Dir/claude-config"
SPACED="$CFG/projects/-Users-x-Space-Dir-projects-myrepo"
mkdir -p "$SPACED"
cat > "$SPACED/space.jsonl" <<'J'
{"type":"user","gitBranch":"main","cwd":"/Users/x/Space Dir/projects/myrepo","timestamp":"2026-06-03T10:00:00Z","sessionId":"spaced-1","message":{"role":"user","content":"work on the myrepo importer pipeline today"}}
J
# A second project dir whose cwd is a SUBSTRING-but-not-component of "myrepo"
SUBDIR="$CFG/projects/-Users-x-projects-my-myrepo-fork"
mkdir -p "$SUBDIR"
cat > "$SUBDIR/sub.jsonl" <<'J'
{"type":"user","gitBranch":"main","cwd":"/Users/x/projects/my-myrepo-fork","timestamp":"2026-06-03T11:00:00Z","sessionId":"subfork-1","message":{"role":"user","content":"unrelated fork work"}}
J
# A Claude session with NO cwd field (strict filter must drop it when scoping)
NOCWD="$CFG/projects/-Users-x-projects-nocwd"
mkdir -p "$NOCWD"
cat > "$NOCWD/nocwd.jsonl" <<'J'
{"type":"user","gitBranch":"main","timestamp":"2026-06-03T12:00:00Z","sessionId":"nocwd-1","message":{"role":"user","content":"session with no cwd recorded"}}
J

# 1. Discovery finds the space-encoded dir (scan-all beats dir-glob)
out="$(CLAUDE_CONFIG_DIR="$CFG" bash "$DISC" 3650 --platform claude --exclude-active-min 0)"
check "discovery finds space-path encoded dir" "space.jsonl" "$out"

# 2. extract-metadata --cwd-filter scopes by REAL cwd (space path) → keeps myrepo
meta="$(CLAUDE_CONFIG_DIR="$CFG" bash "$DISC" 3650 --platform claude --exclude-active-min 0 \
        | tr '\n' '\0' | xargs -0 python3 "$META" --cwd-filter myrepo)"
check "cwd-filter keeps space-path myrepo session" "spaced-1" "$meta"

# 3. path-component match: 'myrepo' must NOT match '/x/projects/my-myrepo-fork'
case "$meta" in *subfork-1*) bad "path-component: substring fork wrongly kept" ;; *) ok "path-component drops my-myrepo-fork (not a substring match)" ;; esac

# 4. strict missing-cwd: a no-cwd session is dropped when a filter is active
case "$meta" in *nocwd-1*) bad "strict missing-cwd: no-cwd session wrongly kept" ;; *) ok "strict missing-cwd: no-cwd session dropped when scoping" ;; esac

# 5. ...but with NO --cwd-filter (all-repos), the no-cwd session IS returned
allmeta="$(CLAUDE_CONFIG_DIR="$CFG" bash "$DISC" 3650 --platform claude --exclude-active-min 0 \
           | tr '\n' '\0' | xargs -0 python3 "$META")"
check "all-repos scan returns no-cwd session" "nocwd-1" "$allmeta"

# 6. Codex date-nesting: a sessions/YYYY/MM/DD/ tree is discovered
CODEXBASE="$TMP/home/.codex/sessions/2026/06/03"
mkdir -p "$CODEXBASE"
cp "$FIX/codex-session.jsonl" "$CODEXBASE/rollout-test.jsonl"
cout="$(HOME="$TMP/home" bash "$DISC" 3650 --platform codex --exclude-active-min 0)"
check "discovery recurses Codex date-nesting" "rollout-test.jsonl" "$cout"

# 7. empty discovery → no sessions emitted. NOTE: BSD xargs (macOS) does NOT run
#    the command on empty input (GNU does), so the pipeline yields empty output
#    rather than a files_processed:0 line — both mean "no sessions".
empty="$(CLAUDE_CONFIG_DIR="$TMP/none" HOME="$TMP/none" bash "$DISC" 3650 \
         | tr '\n' '\0' | xargs -0 python3 "$META")"
case "$empty" in *'"platform"'*) bad "empty discovery wrongly emitted a session: $empty" ;; *) ok "empty discovery yields no sessions (BSD xargs no-run-on-empty safe)" ;; esac

# 7b. extract-metadata's empty-stdin branch (direct, GNU-xargs / single-file path)
estdin="$(printf '' | python3 "$META")"
check "empty-stdin extract-metadata emits files_processed:0" '"files_processed": 0' "$estdin"

# 8. bad --platform → exit 2
if CLAUDE_CONFIG_DIR="$CFG" bash "$DISC" 7 --platform bogus >/dev/null 2>&1; then
  bad "bad --platform should exit non-zero"
else
  ok "bad --platform exits non-zero"
fi

# 9. set -u edge: bare --platform with no value → exit 2 (not an unbound crash)
if CLAUDE_CONFIG_DIR="$CFG" bash "$DISC" 7 --platform >/dev/null 2>&1; then
  bad "bare --platform should exit non-zero"
else
  ok "bare --platform exits non-zero (no set -u crash)"
fi

# 10. missing days arg → exit 2
if bash "$DISC" >/dev/null 2>&1; then bad "missing days should exit non-zero"; else ok "missing days exits non-zero"; fi

# 11. scan-past-preamble: 40 noise lines before the user metadata line
BIG="$TMP/big.jsonl"
i=0; while [ $i -lt 40 ]; do printf '{"type":"queue-operation","operation":"noise","n":%d}\n' "$i" >> "$BIG"; i=$((i+1)); done
printf '{"type":"user","gitBranch":"feat/x","cwd":"/Users/x/projects/deep","timestamp":"2026-06-04T10:00:00Z","sessionId":"deep-1","message":{"role":"user","content":"deep preamble session"}}\n' >> "$BIG"
big="$(python3 "$META" "$BIG")"
check "scan-past-preamble detects user line beyond 25" "deep-1" "$big"

# 12. redaction: the fake key in the claude fixture is scrubbed from the skeleton
sk="$(python3 "$SKEL" < "$FIX/claude-session.jsonl")"
case "$sk" in *FAKEFAKEFAKE*) bad "redaction: fake key leaked into skeleton" ;; *) ok "redaction: fake key scrubbed from skeleton" ;; esac
check "redaction marker present" "[REDACTED]" "$sk"

# 13. skeleton extracts user + assistant content from both platforms
check "claude skeleton has assistant text" "clock-skew" "$sk"
ck="$(python3 "$SKEL" < "$FIX/codex-session.jsonl")"
check "codex skeleton has user text" "make build" "$ck"

# 14. errors extractor surfaces the codex non-zero exit
ce="$(python3 "$ERRS" < "$FIX/codex-session.jsonl")"
check "codex errors extractor finds exit code 2" "exit=2" "$ce"

# 15. redaction covers the extra credential shapes Codex flagged (impl review #1)
REDFX="$TMP/red.jsonl"
cat > "$REDFX" <<'J'
{"type":"user","gitBranch":"main","cwd":"/x/repo","timestamp":"2026-06-05T10:00:00Z","sessionId":"red-1","message":{"role":"user","content":"creds dump: github_pat_ABCDEFGHIJ1234567890KLMN and Authorization: Bearer ABCDEFGHIJKLMNOPQRSTUVWX and OPENAI_API_KEY=\"sk-proj-ZZZZZZZZZZZZ9999\" and AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMIabcdefGHIJKLMNOP1234567890"}}
J
red="$(python3 "$SKEL" < "$REDFX")"
for leak in "github_pat_ABCDEF" "Bearer ABCDEFGH" "sk-proj-ZZZ" "wJalrXUtnFEMI"; do
  case "$red" in *"$leak"*) bad "redaction leaked: $leak" ;; *) ok "redaction scrubs: $leak" ;; esac
done

# 16. >10-line preamble: skeleton must still detect Claude + emit content (impl #4)
PRE="$TMP/preamble.jsonl"
i=0; while [ $i -lt 14 ]; do printf '{"type":"queue-operation","operation":"noise","n":%d}\n' "$i" >> "$PRE"; i=$((i+1)); done
printf '{"type":"user","gitBranch":"main","cwd":"/x/repo","timestamp":"2026-06-05T10:00:00Z","sessionId":"pre-1","message":{"role":"user","content":"this user line sits past the first ten records"}}\n' >> "$PRE"
pre="$(python3 "$SKEL" < "$PRE")"
check "skeleton detects Claude past a >10-line preamble" "sits past the first ten" "$pre"

echo "-----------------------------------------"
printf 'session-recall smoke: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
