# framework-ship — procedure notes

Conditional depth for `SKILL.md`. Load when the ship run hits one of the cases
below; the body carries everything that must fire on every run.

## 1. Provenance (trust-contract step 1)

The flow this skill encodes is not a synthesis — it is the operator's observed
procedure, run to a green end state **7+ times** before promotion:

| Session | Notes |
|---|---|
| QUE-360 | early run of the throwaway-clone → PR shape |
| QUE-362 | " |
| QUE-365 | " |
| QUE-366 | " |
| QUE-370 | " |
| QUE-371 | latest pair, shipped as **PR #87** |
| QUE-375 | latest pair, shipped as **PR #88** |

Repeatability, not a single lucky run, is what makes this promotable. A future
session that changes a stage should be able to name the run that motivated it.

## 2. Delegated-execution variant

The framework's preferred delegated-execution split applies to this flow:

- **Driver** (orchestrating model) owns Stages 0, 4, 6–9 and every verdict.
- **Executor lane** (an Opus subagent working in its own **worktree**) owns
  Stage 2 (the fix + twins) and the fix→re-run loop inside Stage 3.
- The driver **inspects the diff and re-runs the proofs itself** — an executor's
  report that verify passed is a claim, not evidence. Re-run `make verify` and
  `check-ship-gates.sh` in the driver's own shell.
- **Panel fixes round-trip to the same lane.** Send Stage-4 findings back to the
  executor that wrote the code rather than opening a second lane — a second lane
  re-derives context the first already holds and the two diverge on the same file.
  When the harness cannot resume a finished lane (no `SendMessage` — the desktop
  app is one such variant), open a fresh lane whose brief restates the facts the
  first lane verified and tells it to start from `git diff`, and note the
  deviation in `reconciled.md`; two or three phrase-level fixes may be applied by
  the driver directly, followed by the driver's own re-verify.
- Worktree isolation rules apply: branch work in a worktree, the shared checkout
  stays on the default branch, no mid-flight renders of the live harness homes,
  and re-read the memory index and tracker immediately before any write.

## 3. Trimmed detail

**Why the clean clone, not the living folder.** Inside a Claude Code worktree the
copied `.claude/` directory makes environment-shaped assertions fail. Those FAILs
are artifacts of the worktree, not defects in the change, and chasing them burns
a whole loop. The clean clone is also the shape CI runs, so it is the publish
gate; a green living-folder run proves less.

**Why WARN and not FAIL for a stale twin.** `check-ship-gates.sh` cannot tell a
deliberate bash-only change (a fix in shell-specific quoting, say) from a
forgotten mirror. Over-reporting gets a guard ignored, which is the same as
deleting it — so the twin-exists-but-not-co-changed case reports WARN and asks a
human to look. The genuinely missing-twin case is a FAIL, because no judgment
call produces it.

**The log markers are parameterized on purpose.** `--verify-marker` and
`--check-clean-marker` default to the literal string `PASSED`, and both gates
additionally require zero lines whose word is `FAIL`. If a gate's summary line
ever changes wording, pass the new marker rather than editing the script — the
default is a documented convention, not a discovered fact about the repo.

**Empty logs.** A supplied-but-empty log FAILs (no marker). An omitted log SKIPs.
SKIP is not PASS: it records that the gate was never proven. Treating a SKIP as
a pass is exactly the "null result without instrument proof" failure.

**Commit-identity base ref.** The gate walks `origin/<default>..HEAD` and falls
back to the local default branch when no remote-tracking ref exists. Zero
commits ahead is a FAIL, not a vacuous pass — there is nothing to push, so the
run is in the wrong state.

**Locale.** The script forces `LC_ALL=C`; its grep/awk word-boundary matching on
`FAIL` is byte-oriented and shifts semantics under a UTF-8 caller.

## 4. Related framework material

- `playbooks/github-housekeeping.md` — the branch/worktree/PR hygiene checklist
  this flow instantiates. Referenced, not duplicated.
- `playbooks/script-and-guard-authoring.md` — the portability, fail-loud, and
  print-the-denominator rules `bin/check-ship-gates.sh` follows.
- `CONTRIBUTING.md` — Bash 3.2 / PowerShell 7+ twin conventions Stage 2 enforces.
- `skills/skill-authoring.md` §10 — the state-machine discipline the body applies.
