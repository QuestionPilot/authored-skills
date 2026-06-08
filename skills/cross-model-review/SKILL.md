---
name: cross-model-review
description: Use when the user asks to check / review / verify / audit / sanity-check / proof / second-opinion / critique / tear apart / find what's wrong with work the driver (Claude) just produced. Also use when stuck or after 2× the same failure (rescue), when editing risky paths (auth/billing/secrets/infra — forced adversarial), or for video/audio/large PDF/whole-repo input (Gemini specialist lane). Never review your own output. One critic = Codex. Gemini = senses only.
---

# Cross-Model Review

The driver (Claude) never reviews its own output. When the user asks to check / review / verify / audit work Claude just produced, route to a different model architecture. **One critic = Codex.** Claude reviewing Claude has the same blind spots; the architectural-distance budget is already spent on Claude → Codex, and a third critic from Gemini adds noise to a code-review task it isn't optimized for. Gemini stays in lanes Codex literally can't cover.

## Triggers — MUST fire on driver's-own-work review verbs

"check your work", "review what you wrote", "is this right?", "tear this apart", "sanity check", "audit this", "second opinion", "proof this", "find what's wrong". When uncertain, fire — a missed self-review is the failure this skill exists to prevent.

**Exception:** content the user wrote (their email, their notes, their draft) is not the driver's output. Review that directly.

## Two modes — same CLI, different prompt

Confirmation review (default):

```bash
git diff | codex exec --skip-git-repo-check "Review this diff. For each finding: title, file:line, why-it-matters, and a confidence anchor — 0=false-positive/pre-existing, 25=can't verify from the diff, 50=real but advisory or unconfirmed, 75=concrete consequence a user/caller hits, 100=verifiable from the code AND frequent. Omit 0 and 25. Then Blocking risks / Missing tests. Be specific."
```

Adversarial review (on "tear this apart" / "stress test" / "prove it's broken" verbs, or forced by risk paths below):

```bash
git diff | codex exec --skip-git-repo-check "Adversarial review — construct failure scenarios, don't checklist. Run the four techniques scaled to diff size/risk (see taxonomy): (1) assumption violation, (2) composition failure across boundaries, (3) cascade construction, (4) abuse cases. Each finding: the scenario step-by-step (trigger → path → wrong outcome), file:line, confidence anchor (omit 0/25; 50=advisory or unconfirmed, 75=concrete consequence, 100=verifiable from the code AND frequent). Prove it's broken."
```

For untracked work, pipe the content: `cat <path> | codex exec ...`. Always integrate findings into the reply — never dump a raw review at the user.

**Always pipe content via stdin — never tell Codex to "go read these files."** A prompt that instructs `codex exec` to open files (esp. under `--dangerously-bypass-approvals-and-sandbox`) can hang indefinitely (alive, 0% CPU, no output) on tool-use/approval round-trips; the stdin-pipe form returns normally. This applies to design conferrals too, not just diff reviews. macOS has no `timeout`/`gtimeout`, so a hung `codex exec` must be killed by PID.

**Resume invariant — force read-only on every `codex exec resume`.** A fresh `codex exec` accepts `-s read-only`, but `codex exec resume` **rejects** `-s/--sandbox` (`error: unexpected argument '-s' found`) and silently inherits `~/.codex/config.toml`'s `sandbox_mode` — which may be `danger-full-access` (+ `approval_policy=never` for unattended runs), letting a resumed *critic* WRITE files mid-loop. `resume` does accept `-c`, so pin it there: `codex exec resume <thread-id> -c sandbox_mode="read-only" --skip-git-repo-check "<prompt>"`. A read-only critic must never escalate to write access on a resume turn.

## Outbound-content scan (pre-pipe)

Per the framework's `core/tool-use.md` Guardrails — before piping local
content (diffs, file contents, snippets) to Codex or Gemini (third-party
LLMs outside the operator's machine), scan the to-be-piped bytes for
credential-shaped strings. Same tripwire shape as the Two-modes invocations
above use; the scan is a hard gate, not advisory.

If the scan matches: the run blocks, an audit log entry is written to
`<run-dir>/exfil-block.md`, and the driver inspects + redacts + re-runs.
False positives tune the pattern (or are allowlisted at the call site);
real hits force the operator to rotate the leaked credential at source.

**Helper:** the bash function lives in a sibling file so tests can source it
directly. Source it once per session before the first reviewer pipe:

```bash
. "$CLAUDE_CONFIG_DIR/skills/cross-model-review/scan-outbound.sh"
```

Then wrap each pipe:

```bash
# Confirmation review with pre-pipe scan — fail closed on ANY non-zero.
rundir="${CROSS_MODEL_OUT_DIR:-$HOME/cross-model-out}/$(date -u +%Y-%m-%d)-<slug>"
mkdir -p "$rundir"
git diff > "$rundir/input-diff.patch"

if ! scan_outbound "$rundir/input-diff.patch" "$rundir"; then
  printf 'BLOCKED: outbound scan — see %s/exfil-block.md or stderr above\n' "$rundir" >&2
  exit 1
fi
cat "$rundir/input-diff.patch" | codex exec --skip-git-repo-check \
  "Review this diff. Per finding: title, file:line, why-it-matters, confidence anchor — 0=false-positive/pre-existing, 25=can't verify, 50=advisory/unconfirmed, 75=concrete consequence, 100=verifiable AND frequent (omit 0/25). Then Blocking risks / Missing tests." \
  > "$rundir/codex-review.txt"
```

Patterns scanned (cite-able list — runtime-constructed in the helper from
non-matching halves so this
SKILL.md itself does not self-trip when later piped through cross-model-
review):

- `<Claude-key-prefix><variant>[A-Za-z0-9_-]{40,}` — Claude API keys
- `xox<variant>[A-Za-z0-9-]{30,}` — Slack tokens
- `gh<variant>[A-Za-z0-9_]{36,}` — GitHub tokens
- `AKIA[0-9A-Z]{16}` — AWS access keys
- `[a-fA-F0-9]{40,}` — high-entropy hex (length-thresholded; tunable)

Helper contract:

- `scan_outbound <input-file> [<run-dir>]` —
  - return 0 = clean (proceed)
  - return 1 = at least one match (block; `exfil-block.md` written under
    `<run-dir>`, default `$(dirname <input-file>)`)
  - return 2 = error (missing args, missing/unreadable input, missing grep,
    or grep exited with an unexpected non-0/1 status). **Fail closed** —
    callers MUST treat 2 the same as 1 and NOT pipe.
- Audit log records ISO-8601 UTC timestamp, input path, pattern, and a
  redacted snippet (first 6 chars + `...xxx`). Never logs the full match.
- Uses `/usr/bin/grep -E` explicitly to bypass any shell ugrep overlay;
  POSIX-ERE only, no `\b` (BSD silently no-ops it).

**Caller pattern (treat return 1 and 2 identically — fail closed):**

```bash
if ! scan_outbound "$input" "$rundir"; then
  printf 'BLOCKED: outbound scan — see %s/exfil-block.md or stderr above\n' "$rundir" >&2
  exit 1
fi
# proceed with the pipe...
```

**Sentinel + negative tests:** self-test the helper by planting a runtime-
constructed `<Claude-key-prefix><variant>` sentinel in a temp file (must
trigger a block) plus a benign diff (must pass), then run your sentinel script:

```bash
bash <your-run-dir>/sentinel-test.sh
```

Expected: `PASS sentinel ... triggers exfil-block` and `PASS benign content passes scan`.

## Grading Codex findings — anchored rubric + suppression

Two-stage: Codex self-anchors each finding from the compact rubric inlined in the prompt above; the **driver re-grades** on the fuller rubric below and owns the final call — Codex's anchor is a proposal, not the verdict. The anchors are **behavioral** — pick the one whose claim is honestly true of the finding, never a value between them (a self-reported float like `0.72` is false precision the model can't calibrate). We keep the single-different-model design and lift only the rubric mechanics from CE `confidence-anchored-scoring.md`.

| Anchor | Meaning | Route |
|---|---|---|
| `0` | False positive, or pre-existing / not introduced by this diff | suppressed — Codex is told to omit these |
| `25` | Might be real, couldn't verify from the diff alone | suppressed — Codex is told to omit these |
| `50` | Real but advisory (nothing critical breaks), **or** a real concern Codex couldn't fully verify | soft bucket — note in one line, no forced decision |
| `75` | Double-checked; a user/caller/operator hits it in normal use; names a concrete consequence | actionable |
| `100` | Verifiable from the code itself **and** will happen frequently | actionable |

**Anchor (confidence) and severity are independent axes:** a P2 can be anchor `100`, and a P0 can be anchor `50` if it's an important concern Codex couldn't fully verify. The anchor gates *where* a finding surfaces (drop / soft bucket / actionable); severity orders the actionable tier.

**Threshold: `>= 75`** for code review — a P0 / blocking finding still surfaces at `50` (an unverified high-severity concern is worth raising; the cost of missing a real P0 outweighs the noise). This is threshold-by-economics, not a copied number: code review has a linter/CI backstop, is publicly visible (each surfaced finding becomes a PR comment), and code claims are ground-truth verifiable — so precision dominates and the bar is high. A senses-lane or strategy/premise review with no backstop and cheap dismissal would gate at `>= 50` instead. Tune to the economics; don't copy `75` blindly.

**Anchor `75` requires a concrete downstream consequence** — a wrong result, an unhandled path, a contract mismatch, a security exposure, missing coverage a real test would surface. "This could be cleaner" / "I'd write it differently" is anchor `50`, not `75`. The test: *will someone concretely encounter this, or is this an opinion about quality?*

**Suppress entirely — non-findings, don't even surface at 50:**

- Pre-existing issues the diff doesn't touch or newly expose.
- Style a linter/formatter already catches (semicolons, import order, unused-var).
- Code that looks wrong but is intentional — check comments / commit msg / surrounding code first.
- Generic "consider adding X" with no named failure mode.
- Code under an explicit lint-ignore for the rule being flagged.
- Quality opinions ("file is long", "too many params") not codified in CLAUDE.md / AGENTS.md.

**Sample grading** (Codex output on a real `scan-outbound.sh` review, graded by the driver):

| Codex finding | Anchor | Action |
|---|---|---|
| New high-stakes call site pipes the diff to Codex but skips the `scan_outbound` gate entirely → every review on that path bypasses the exfil check | `100` | actionable — verifiable in-diff, happens on every such run |
| The hex pattern *might* over-match a 40-char commit SHA in a diff and false-block, but no real case is confirmable from the diff alone | `50` | soft bucket — note the possible false-positive, no forced decision |
| "Consider adding a unit test for the CRLF case" — no failure named | `25` | drop |
| Missing `;;` style nit in the case block | `0` | drop — linter's job |

Net surfaced to the user: the gate-skip (`100`), with the possible hex false-positive noted in one line. Codex is told to omit `0`/`25`; the driver drops anything that slips through anyway.

## Adversarial taxonomy — the four techniques

The adversarial prompt constructs failure scenarios rather than checklisting. Scale depth to the diff (Codex self-calibrates from these cues):

- **Quick** (<50 changed lines, no risk signals): technique 1 only, ≤3 findings.
- **Standard** (50–199 lines, or minor risk): techniques 1, 2, 4.
- **Deep** (200+ lines, or auth / payments / data-mutation / migration signals): all four; trace multi-step chains.

1. **Assumption violation** — find what the code assumes about its environment (data shape, timing, ordering, value range) and construct the input or condition that breaks it; trace the consequence through the code.
2. **Composition failure across boundaries** — each component correct alone, the combination fails: contract mismatch, uncoordinated shared-state mutation, cross-boundary ordering, divergent error contracts.
3. **Cascade construction** — multi-step failure chains: resource exhaustion (timeout → retry → more load), state-corruption propagation, recovery-induced failure (retry duplicates, rollback orphans).
4. **Abuse cases** — legitimate-seeming use with bad outcomes (not security exploits): repetition abuse, timing abuse (during deploy / cache gap), concurrent mutation, boundary walking.

Demand scenario-oriented findings — "cascade: payment timeout triggers unbounded retry loop", not "missing timeout handling". (Ported from CE `ce-adversarial-reviewer.md`; same anchor scale as above.)

## Validator second-pass (high-stakes — optional)

For high-stakes reviews — risk-path forced adversarial, or anything being externalized (PR comments, autofix, downstream automation) — run an independent second Codex pass per surviving `>= 75` finding before acting on it. The validator **re-verifies, it does not re-reason** — a fresh second opinion, not a critic of the first pass. It answers three questions and nothing else:

1. Is the issue **real** in the code as written? (an existing guard, misread types, or an intentional pattern → no)
2. Is it **introduced by this diff**? (predates the PR and the diff doesn't newly expose it → no, drop)
3. Is it **not already handled elsewhere**? (caller guard, middleware, framework default, type constraint → no)

```bash
# Per surviving finding — fresh context, conservative bias. Diff via stdin, same as the review pipes;
# never command-substitute it into the prompt arg (breaks on space-paths and on large diffs).
cat "$rundir/input-diff.patch" | codex exec --skip-git-repo-check "Independent validation pass. The first Codex pass flagged the finding below; verify it under fresh inspection — no commitment to it, false positives are common. The diff is on stdin. Answer ONLY: {\"validated\": true|false, \"reason\": \"<one sentence>\"}. Validated only if the issue is real, introduced by THIS diff, AND not handled elsewhere. When in doubt, reject.

FINDING: <title / file:line / why-it-matters>"
```

**Drop any finding the validator rejects, times out on, or returns malformed for** — conservative by default; unverified findings don't externalize. Skip the pass for casual confirmation reviews (the user is the per-finding validator) and report-only runs (nothing is acted on). Budget-cap at ~15 findings per review. (Ported from CE `ce-code-review` Stage 5b — we run it through the same single-Codex critic rather than a separate persona pool.)

## Rescue — 2× same failure (hard rule)

A deterministic counter, not a vibe. After the driver attempts the same operation and fails twice (same test failure on the same code path, same error on the same command, same edit re-tried with no progress), MUST hand to Codex with full context:

```bash
cat <context-bundle> | codex exec --skip-git-repo-check "Rescue. Driver tried 2× and failed. Full context attached. Solve from scratch."
```

Reset only when the test/build passes, the goal changes, or the user says "keep trying."

## Risk-path forced adversarial (path-based, not keyword-based)

Active edits to these paths force adversarial review without the user asking. Announce it in one line BEFORE running so the user can interrupt:

```
src/auth/**          authentication
src/billing/**       payments
**/migrations/**     DB schema
**/deploy/**         deployment
**/.env*             env handling
**/secrets/**        credentials
**/policy/**         ACLs
infra/**             IaC
**/*stripe*  **/*plaid*    payments
**/*jwt*  **/*oauth*       tokens
```

Verb-agnostic: "refactor", "plan", "design" fires if the target is risky. The verb is irrelevant when the blast radius is. Keywords alone in casual chat do not fire — it must be an active edit on these paths.

## Gemini — senses only, not a code reviewer

Reserved for what Codex literally cannot see. The core rule here: the critic and the worker must come from different model families — Codex already provides that distance, so Gemini-as-second-critic is dead weight on code work. Where Gemini earns its slot:

```bash
# Video / audio — cap duration; demand timestamped findings
agy --dangerously-skip-permissions -p "Analyze. Findings as timestamped list: [MM:SS] event." @/path/clip.mp4

# Large PDF — cap pages; demand page-numbered findings
agy --dangerously-skip-permissions -p "Extract key claims, tables, charts. Page-numbered." @/path/doc.pdf

# Whole-repo / multi-dir scan
agy --dangerously-skip-permissions -p "Scan <abs path>. Return file:line list grouped by directory."

# Multi-image visual review (≥3 shots) — use --add-dir, NEVER @-attachment cram.
# Stage the shots in a SPACE-FREE dir, then let agy VIEW each via its own tools.
# Reliable + fast: 5–6 images (incl. multi-MB PNGs) in ~20–35s.
imgdir=/tmp/visrev                 # space-free: @-paths with a space silently send NO image
mkdir -p "$imgdir"; cp /path/to/shots/*.png "$imgdir"/    # or capture via playwright-cli
agy --dangerously-skip-permissions --add-dir "$imgdir" --print-timeout=120s \
  -p "VIEW each image in $imgdir with your tools. One line per file: <filename>: <finding>. Skip none. End with VERDICT: <which differs>." \
  < /dev/null
```

Always demand timestamps / page numbers / `file:line` citations — never accept a flat summary.

**agy image gotchas — the senses lane's sharpest edge:**

1. **Multi-image → `--add-dir`, never `@`-cram.** Inlining several images (especially multi-MB) as trailing `@file` args into one `-p` **hangs** — and the hang is in image-loading, *before* the print-wait, so `--print-timeout` does **not** bound it (agy is a Go binary; shell `timeout`/SIGALRM don't kill it either). `--add-dir <dir>` makes agy read each image with its own tools: no payload cram, returns cleanly. Verified — 6 images (2× 4.7 MB) in ~34s with correct per-file findings + verdict.
2. **A space in an `@`-path silently sends NO image.** If your repo or `cross-model-out/` lives under a path containing a space, stage inputs in a space-free dir (`/tmp/…`) and point `--add-dir` there.
3. **`--print-timeout` caps the model wait, not the upload; pipe `< /dev/null` for stdin.** Redirect stdin so headless agy doesn't block, and set `--print-timeout` generously. If you ever must use the fragile `@`-path, wrap it in an **external watchdog kill** — `--print-timeout` alone won't rescue a pre-print hang.

## "Ask all three" — explicit consensus only

Only when the user explicitly invokes ("ask all three", "before I commit", "cross-architecture consensus"). All three answer the SAME question with structured output:

```
Recommendation: <one line>
Blocking risks: <bullet list>
Assumptions: <bullet list>
Confidence: low | med | high
Tests to verify: <bullet list>
```

The driver diffs the answers — where they agree, where they disagree — and adjudicates by evidence, not by averaging.

## Startup self-check (once per session, before the first route)

```bash
codex --version 2>&1 | head -1   # expect codex-cli 0.125+
agy --version 2>&1 | head -1     # expect 1.0+
```

If a CLI is missing → announce once, continue gracefully, do not retry every turn. `agy` lives at `~/.local/bin/agy`; if the binary exists but `agy --version` fails, `~/.local/bin` isn't on `PATH`.

## Filing

```
$CROSS_MODEL_OUT_DIR/<YYYY-MM-DD>-<slug>/
  ├── input.txt        — what was sent to the reviewer
  ├── codex-review.md  — Codex output (or gemini-output.md for senses lane)
  └── reconciled.md    — driver synthesis
```

Append one line per run to `$CROSS_MODEL_OUT_DIR/log.md` — the compounding ledger.

## Announcement protocol

When the skill fires a route the user did NOT explicitly ask for (risk-path forced adversarial, failure-counter rescue), announce in one line BEFORE running so the user can interrupt. For routes the user explicitly asked for ("check this", "tear it apart"), just do it.

## Stay-asleep rules

- "Explain / what is / how does / walk me through" → driver direct
- "Write / draft / build / refactor" on non-risky paths → driver direct (but a later "check your work" re-triggers the no-self-review law)
- "Review my notes / review my draft email" — user's content, not driver's → driver direct
- Casual chat, status questions, file ops, git/bash/grep → driver direct

When uncertain on driver-output review verbs: **fire**. When uncertain on user-content review: **stay asleep**. Under-firing on user content is fine; over-firing breaks trust.

End cross-model replies with: `(Routed via cross-model-review → Codex.)` (or `→ Gemini.` / `→ all three.` for the other lanes).

---

**Origin:** a lean single-critic redesign of an earlier three-brain review skill — it replaces a dual-reviewer + tripwire + audit-checklist stack with single-critic-Codex plus a Gemini senses-only lane. Drop the skill folder into `$CLAUDE_CONFIG_DIR/skills/cross-model-review/` (no compile step).
