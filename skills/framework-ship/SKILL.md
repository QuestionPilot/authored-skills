---
name: framework-ship
description: "Execute an agentic-os-template (framework) issue end-to-end — throwaway clone, branch, twin-script fix, clean-clone `make verify`, cross-model panel, pinned-identity commit, check-clean, push, PR, CI, squash-merge, living-folder fast-forward, drift check, tracker close. Use when the user says 'ship this framework change', 'open a framework PR', 'execute QUE-NNN against the template', 'land this in agentic-os-template', or asks to fix/verify/merge anything in the framework repo. NOT for ordinary project repos."
---

# framework-ship

Ships one framework (`agentic-os-template`) change. This is a **git-workflow state
machine**: re-read git state at every transition — never carry an early
observation forward. `FS=<absolute path of the directory containing THIS
SKILL.md>` below.

## Hard invariants (these never bend)

- **Never `git push` from the living folder** `/Users/hendohome/Agentic OS`. It is
  a clone of the public template; all upstream writes go through a **throwaway
  clone**. Ref deletions included — no exemption. Pulling into the living folder
  is fine.
- **Push identity must be the noreply form** `<id>+QuestionPilot@users.noreply.github.com`.
  The account email trips GitHub **GH007** email-privacy rejection.
- **After any rebase or amend, re-check BOTH `%an/%ae` and `%cn/%ce`** — the
  committer resets to the machine default and only the author survives pinning.
- **`scripts/check-clean.sh` is the CI-boundary PII gate and is NOT part of
  `make verify`.** Run it separately, on a quiesced tree, before push.
- **Logs and scratch live OUTSIDE the clone.** Sync files by explicit path;
  never `git add -f -A` (that is how a `verify.log` contaminated a tree).

## Stage 0 — Scope

Read the tracker issue. Restate the change in one sentence and name the files it
will touch. **Done when:** the file list exists and every file is inside the
framework repo.

## Stage 1 — Throwaway clone + branch

```bash
CLONE=$(mktemp -d -t fwship-XXXXXX)/agentic-os-template
LOGS=$(mktemp -d -t fwship-logs-XXXXXX)   # OUTSIDE the clone
git clone <template-remote> "$CLONE"
cd "$CLONE" && git checkout -b <branch>
cp <living-folder>/local.env "$CLONE"/local.env   # gitignored; carries COMMIT_IDENTITY_ALLOWLIST
```

**Done when:** `git branch --show-current` prints the new branch and `$LOGS` is
outside `$CLONE`.

## Stage 2 — Fix + twin tests (judgment)

Write the change. Every touched `scripts/*.sh` gets its `.ps1` twin updated in
the same commit, and behavior changes mirror into the `tests/*.test.ps1` twins —
only the Windows CI lane runs those, so a one-sided change ships a guard that
holds on one platform. Run both sides locally where the runtime exists.
**Done when:** every changed shipped script has a co-changed twin, or a written
waiver reason exists.

## Stage 3 — Clean-clone verify

Run from the **clean clone**, not the living folder — in a Claude worktree the
copied `.claude/` produces env FAILs that are artifacts, not defects.

```bash
cd "$CLONE" && make verify > "$LOGS/verify.log" 2>&1; echo "rc=$?"
```

Never `make verify | tail` and trust the exit code — that reports `tail`. Gate on
`rc` or the PASS/FAIL lines. `make verify` is **fail-fast**: a red run shows only
its FIRST failure, so scope from one red run is a lower bound. Loop fix → re-run
until `rc=0`. **Done when:** `rc=0` and `$LOGS/verify.log` holds zero FAIL lines.

## Stage 4 — Cross-model panel (judgment)

Framework changes get the **full non-driver panel** as standing policy. Invoke
`cross-model-review`; give each critic its own isolated evidence dir under
`~/cross-model-out/<date>-<topic>/`. Fixture-test any cheaply-decidable claim
before grading it — critic agreement is not evidence. Round panel-accepted fixes
back through Stages 2–3. **Done when:** every finding is either fixed-and-
re-verified or explicitly rejected with a reason.

## Stage 5 — Commit with pinned identity

```bash
git -c user.name="<Published Name>" \
    -c user.email="<id>+QuestionPilot@users.noreply.github.com" \
    commit -m "<subject>"
git log --format='%h A:%an <%ae> C:%cn <%ce>' origin/main..HEAD   # both fields
```

**Done when:** every commit ahead of `origin/main` shows author AND committer on
the `COMMIT_IDENTITY_ALLOWLIST`.

## Stage 6 — Pre-push gate (deterministic)

Quiesce the tree first (nothing else writing into the clone), then:

```bash
set -a; . "$CLONE/local.env"; set +a   # check-clean reads COMMIT_IDENTITY_ALLOWLIST from env — without it the identity scan silently SKIPs
bash "$CLONE/scripts/check-clean.sh" > "$LOGS/check-clean.log" 2>&1; echo "rc=$?"
bash "$FS/bin/check-ship-gates.sh" --stage pre-push --repo "$CLONE" \
  --local-env "$CLONE/local.env" \
  --verify-log "$LOGS/verify.log" --check-clean-log "$LOGS/check-clean.log" \
  --verify-marker "PASS drift and portability checks" \
  --check-clean-marker "PASS check-clean"
```

The marker flags are load-bearing: the gate's default marker is the literal
`PASSED`, which matches NEITHER `make verify`'s output (its final gate prints
`PASS drift and portability checks`) nor check-clean's summary
(`PASS check-clean: …`) — omit them and both log gates FAIL on a green run
(first live run, QUE-562). If either summary line ever changes wording, update
the flag values here rather than the gate script.

The script checks branch-not-default, worktree-clean, commit-identity (author +
committer vs the allowlist), both logs, and twin parity; it prints one PASS/FAIL
line per gate and a VERDICT. **Done when:** it exits 0 and no gate reports FAIL.
A SKIP means the gate was not proven — supply the missing log rather than
accepting it.

## Stage 7 — Push + PR + CI

```bash
git push -u origin HEAD < /dev/null              # from $CLONE only
gh pr create --fill < /dev/null
gh pr checks --watch --interval 30 < /dev/null   # background it; it runs 10–20 min
```

Every git/gh step here runs with stdin closed and one step per tool call: in an
agent shell an open stdin makes `gh pr merge` / `git pull` block on a prompt
until the harness timeout, and a chained command then hides which step ran.
Bound anything that may wait (`perl -e 'alarm N; exec @ARGV' <cmd>` — macOS has
no `timeout`), and after ANY timed-out step re-read real state (PR state, HEAD)
before retrying. **Done when:** all 6 CI lanes are green. Red lane → fix in `$CLONE`, return to
Stage 3 (re-verify), then re-push.

## Stage 8 — Squash-merge + living-folder fast-forward

```bash
perl -e 'alarm 120; exec @ARGV' gh pr merge <N> --squash --delete-branch < /dev/null
# living folder — fetch + ff-merge, never `git pull` (it prompts), never push:
cd "<living-folder>" && git fetch origin main < /dev/null && git merge --ff-only origin/main < /dev/null
bash scripts/install.sh --harness claude --harness codex   # only if renders changed
bash scripts/check-drift.sh --auto < /dev/null
bash "$FS/bin/check-ship-gates.sh" --stage post-merge --repo "<living-folder>" < /dev/null
```

Run these as separate tool calls, not one `&&` chain — a chain that times out
leaves the PR merged but the living folder behind, with no line saying so.

**Done when:** drift is clean across every rendered harness home and the
post-merge gate exits 0.

## Stage 9 — Close

Set the tracker issue to Done with an evidence comment (PR link, verify rc,
panel outcome, drift result). If the session created/closed a project or a new
durable artifact directory, invoke `closeout` and write the **State Deltas**
during closeout, not deferred. **Done when:** the issue is Done and any State
Delta is written.

## Cleanup

`rm -rf "$CLONE" "$LOGS"` only after the PR is merged and the drift check passed.

Depth, provenance, and the delegated-execution variant: `reference/procedure-notes.md`.
