---
name: cross-model-review
description: Use when the user asks to check / review / verify / audit / sanity-check / proof / second-opinion / critique / tear apart / find what's wrong with work Claude just produced. Also use when stuck or after 2× the same failure (rescue), when editing risky paths (auth/billing/secrets/infra — forced adversarial), or for video/audio/large-PDF/whole-repo input (specialist lane). Never review your own output — route to a different model family. The two critics are GPT (via the Codex CLI) and Gemini (via the agy CLI), equal first-class peers. Single critic for code review; panel→judge→synthesis for open-ended consensus.
---

# Cross-Model Review

The driver (Claude) never reviews its own output. When the user asks to check /
review / verify / audit / sanity-check / tear-apart work Claude just produced,
route to a **different model family** — a model reviewing its own family inherits
the same blind spots, and that architectural distance is the whole point.

The two critic families are **equal first-class peers**: **GPT** (the `codex` CLI)
and **Gemini** (the `agy` CLI). There is **no capability hierarchy in either
direction** — no "senses-only" family, no "stronger coder" family. Selection is by
**role** (Claude is the driver, so it routes to the other two families) and by
**lane** (what the task needs), never by a cross-family ranking.

## Roles, eligibility, and count

- **Driver** — Claude (this session). Never a critic or panelist of its own output.
- **Critics** — the two non-Claude families: GPT (Codex) and Gemini (agy).
- **Judge / synthesizer** — Claude, for multi-critic lanes. **The driver judges; it
  is never a panelist of its own question** — that is the no-self-review boundary
  restated for the panel case.

**Eligibility (who *may* critique) is separate from count (how many *do*).**
Eligibility is fixed here: critics = {GPT, Gemini}. **Count is decided by the
lane** — a verifiable-artifact review (code, diffs) fires **one** critic; an
open-ended consensus question fires the **panel** (both). Single critic by default;
the panel only when the economics justify it.

## Triggers — MUST fire on Claude's-own-work review verbs

"check your work", "review what you wrote", "is this right?", "tear this apart",
"sanity check", "audit this", "second opinion", "proof this", "find what's wrong".
When uncertain on a driver-output review verb, **fire** — a missed self-review is
the failure this skill exists to prevent.

**Exception:** content the *user* wrote (their email, notes, draft) is not Claude's
output. Review that directly; do not route it.

## The two critique lanes — one critic, different prompt

A code/diff review fires **one** critic — default to **GPT (Codex)**; use Gemini
(agy) when the input is in its specialist lane (below). Always pipe content via
stdin; **never** tell a critic to "go read these files" (it can hang on
approval round-trips). Source the scan gate first (see next section), then:

**Confirmation review (default):**

```bash
cat "$rundir/input-diff.patch" | codex exec --skip-git-repo-check -s read-only \
  "<no-go preamble: core + critique clause> Review this diff. For each finding: title, file:line, why-it-matters, and a confidence anchor — 0=false-positive/pre-existing, 25=can't verify, 50=real but advisory/unconfirmed, 75=concrete consequence a user/caller hits, 100=verifiable AND frequent. Omit 0 and 25. Then Blocking risks / Missing tests. Be specific." \
  > "$rundir/codex-review.md"
```

**Adversarial review** (on "tear this apart" / "stress test" / "prove it's broken",
or forced by the risk paths below):

```bash
cat "$rundir/input-diff.patch" | codex exec --skip-git-repo-check -s read-only \
  "<no-go preamble> Adversarial review — construct failure scenarios, don't checklist. Run the four techniques scaled to diff size/risk (see taxonomy): (1) assumption violation, (2) composition failure across boundaries, (3) cascade construction, (4) abuse cases. Each finding: the scenario step-by-step (trigger → path → wrong outcome), file:line, confidence anchor (omit 0/25; 50=advisory, 75=concrete consequence, 100=verifiable AND frequent). Prove it's broken." \
  > "$rundir/codex-review.md"
```

**Resume invariant — force read-only on every `codex exec resume`.** A fresh
`codex exec` accepts `-s read-only`, but `codex exec resume` **rejects** `-s` and
silently inherits `~/.codex/config.toml`'s `sandbox_mode` (which may be
`danger-full-access`). `resume` accepts `-c`, so pin it there:
`codex exec resume <thread-id> -c sandbox_mode="read-only" --skip-git-repo-check "<prompt>"`.
A read-only critic must never escalate to write access on a resume turn. (macOS has
no `timeout`; kill a hung `codex exec` by PID.)

Integrate findings into the reply — never dump a raw critic transcript at the user.

## Outbound-content scan (pre-pipe) — a hard gate

Before piping any local content (diffs, file contents, snippets) to a critic — a
third-party model **outside the operator's machine** — scan the to-be-piped bytes
for credential-shaped strings. The scan is a **hard gate, not advisory**: it fails
closed. The helper ships beside this skill:

```bash
. "$CLAUDE_CONFIG_DIR/skills/cross-model-review/scan-outbound.sh"

rundir="${CROSS_MODEL_OUT_DIR:-$HOME/cross-model-out}/$(date -u +%Y-%m-%d)-<slug>"
mkdir -p "$rundir"
git diff > "$rundir/input-diff.patch"

# Fail closed on ANY non-zero (1 = match, 2 = error — treat identically).
if ! scan_outbound "$rundir/input-diff.patch" "$rundir"; then
  printf 'BLOCKED: outbound scan — see %s/exfil-block.md or stderr above\n' "$rundir" >&2
  exit 1
fi
# ...only now pipe "$rundir/input-diff.patch" to the critic.
```

**Helper contract** — `scan_outbound <input-file> [<run-dir>]`: return `0` clean
(proceed), `1` at least one match (`<run-dir>/exfil-block.md` written with a
redacted snippet; do NOT pipe), `2` error (missing args/input/grep) — **fail
closed**, treat `2` like `1`. Patterns (assembled at runtime from non-matching
halves so this file doesn't self-trip): provider API-key prefixes + a long tail
(`sk-…`, catches Anthropic + OpenAI keys), chat-platform tokens, version-control
tokens, cloud access keys, length-thresholded high-entropy hex. Tunable; false
positives allowlisted at the call site, real hits force a credential rotation.

**Self-test** by planting a runtime-constructed credential sentinel (must block) +
a benign diff (must pass). **The scan is a credential tripwire only** — not
proprietary-source/customer-data DLP; the operator owns what gets piped, and a
panel widens the blast radius (content reaches two external models, not one).

## Per-lane tool policy

The critic *is* a cloud model, so **provider-API network is always on** — "no web"
never means "no network."

| Lane | Provider network | Web-research tools | Writes/deletes | Local roam |
| --- | --- | --- | --- | --- |
| **Critique** (code/diff review) | on | **off** | off | off — content piped + scanned |
| **Research** (web-grounded question) | on | **on** | off | off |

**Critique lane:** content piped + scanned; no web tools, no writes, no roam.
**Research lane:** web tools on, but **never pipe sensitive local context to a
web-enabled critic** (it can exfil piped context through its live web tool; the
static scan checks the input, not runtime HTTP). A critic needing local context
runs web-off. Never combine local-read and network-egress tools in one critic.

## Guardrail split + honest sandbox limits

- **ENFORCE** writes/deletes via a **read-only sandbox** (`codex -s read-only`;
  `agy --sandbox`) — free, a reviewer never writes.
- **INSTRUCT** disclosure / secrets / account-actions via the **no-go preamble** —
  it covers content the critic fetches itself, which the input scan can't see.

**Read-only is necessary, not sufficient** — it blocks writes, not reads. The real
read-side guard is the combination: **stdin-only packet + scoped/zero extra-dir
access + no web tools in critique.**

### No-go preamble (prepend to every critic invocation)

Universal core always; append the active lane's clause.

> **Universal core (all lanes).** You are a read-only reviewer. Do not write, edit,
> or delete files; do not run state-mutating commands or take account actions; do not
> disclose, transmit, or store the reviewed content anywhere outside this response.
> Return findings only.
>
> **Critique lane adds:** review only the content provided to you (piped on stdin or
> attached as a file) — do not fetch additional files and make no network requests
> beyond your own model provider.
>
> **Research lane adds:** web-research tools are permitted (that is the task), but do
> not exfiltrate any piped local context through them, and still make no writes or
> account actions.
>
> **Specialist lane adds:** read only the provided media/attachment — no other file
> or directory roam.

## No behavior-affecting global writes (invariant)

Pass **ephemeral per-call flags only**. Never mutate behavior-affecting global
config — model, sandbox mode, or permission policy — to run a review (the resume
`-c sandbox_mode` pin above is the danger case). Critic CLIs still write benign
caches/auth-refresh/logs; that's fine — what matters is config *semantics*.

## Model policy — current flagship tier, no lock-in

**No version literals, no cross-family ranking.** Each family resolves to its own
current flagship tier: **Codex** defers to its configured model but **warn if it
resolves below the GPT flagship tier**; **agy** resolves the current flagship-tier
Gemini (verify via `agy models`; a within-Gemini newer-flagship-over-older choice
is fine — not a cross-family claim). The resolution *mechanism* differs per CLI;
the *intent* (each lands on its own flagship) does not. Surface the resolved model
per family in the self-check; warn rather than silently degrade.

## Grading critic findings — anchored rubric + suppression

The critic self-anchors each finding from the compact rubric in the prompt; **Claude
re-grades** on the fuller rubric and owns the final call. Anchors are behavioral —
pick the one honestly true, never a value between them.

| Anchor | Meaning | Route |
| --- | --- | --- |
| `0` | False positive, or pre-existing / not introduced by this diff | suppressed |
| `25` | Might be real, couldn't verify from the diff alone | suppressed |
| `50` | Real but advisory, **or** a real concern the critic couldn't fully verify | soft bucket — one line |
| `75` | Double-checked; a user/caller hits it in normal use; concrete consequence | actionable |
| `100` | Verifiable from the code itself **and** frequent | actionable |

**Anchor and severity are independent** — a P2 can be `100`, a P0 can be `50` if
unverified. **Threshold `>= 75` for code review** (it has a linter/CI backstop, is
often publicly visible, claims are ground-truth verifiable → precision dominates); a
**senses/premise review with no backstop** gates at `>= 50`. **`75` requires a
concrete downstream consequence** — "this could be cleaner" is `50`. **Suppress
entirely:** pre-existing issues; style a linter catches; intentional code (check
comments/commit first); generic "consider adding X"; lint-ignored code; quality
opinions not codified in the project's instruction files.

## Adversarial taxonomy — the four techniques

Scale depth to the diff (the critic self-calibrates): **Quick** (<50 lines, no risk)
= technique 1, ≤3 findings; **Standard** (50-199, minor risk) = 1, 2, 4; **Deep**
(200+, or auth/payments/data-mutation/migration) = all four, trace chains.

1. **Assumption violation** — find what the code assumes (data shape, timing,
   ordering, range) and construct the input that breaks it; trace the consequence.
2. **Composition failure across boundaries** — each component correct alone, the
   combination fails: contract mismatch, shared-state mutation, ordering, divergent
   error contracts.
3. **Cascade construction** — multi-step chains: resource exhaustion (timeout →
   retry → more load), state-corruption propagation, recovery-induced failure.
4. **Abuse cases** — legitimate-seeming use, bad outcome (not exploits): repetition
   abuse, timing abuse (deploy/cache gap), concurrent mutation, boundary walking.

Demand scenario-oriented findings — "cascade: payment timeout triggers unbounded
retry loop", not "missing timeout handling".

## Validator second-pass (high-stakes — optional)

For risk-path forced adversarial or anything externalized (PR comments, autofix),
run an independent second Codex pass per surviving `>= 75` finding. It **re-verifies,
doesn't re-reason** — answers only: (1) Is it **real** in the code as written? (2)
Is it **introduced by this diff**? (3) Is it **not already handled elsewhere**? Pipe
the same diff via stdin; prompt for `{"validated": true|false, "reason": "<one sentence>"}`;
validated only if all three hold; when in doubt, reject. **Drop any finding the
validator rejects, times out on, or returns malformed for.** Skip for casual
confirmation reviews and report-only runs. Budget-cap ~15 findings.

## Rescue — 2× same failure (hard rule)

A deterministic counter, not a vibe. After Claude attempts the same operation and
fails twice (same test failure on the same path, same error on the same command,
same edit re-tried with no progress), MUST hand to a critic with full context:

```bash
cat <context-bundle> | codex exec --skip-git-repo-check -s read-only "Rescue. Driver tried 2× and failed. Full context attached. Solve from scratch."
```

Reset only when the test/build passes, the goal changes, or the user says "keep trying."

## Risk-path forced adversarial (path-based, not keyword-based)

Active edits to these paths force an adversarial review without the user asking.
Announce in one line BEFORE running so the user can interrupt:

```
**/auth/**           authentication
**/billing/**        payments
**/migrations/**     DB schema
**/deploy/**         deployment
**/.env*             env handling
**/secrets/**        credentials
**/policy/**         ACLs
infra/**             IaC
**/*payment*  **/*checkout*   payment flows
**/*jwt*  **/*oauth*          tokens
```

Verb-agnostic: "refactor", "plan", "design" fires if the target is risky. Keywords
alone in casual chat do not fire — it must be an active edit on these paths.

## Specialist lane — Gemini (agy), where its tooling fits the input

Some inputs Gemini's tooling handles best today (native video/audio/PDF ingestion,
large multimodal context, whole-repo scans). This is a **tooling fact, not a
capability ranking** — route by what the input needs and demand cited findings:

```bash
# Video / audio — cap duration; timestamped findings
agy --sandbox -p "<no-go preamble: specialist clause> Analyze. Timestamped list: [MM:SS] event." @/path/clip.mp4 < /dev/null

# Large PDF — cap pages; page-numbered findings
agy --sandbox -p "<preamble> Key claims, tables, charts. Page-numbered." @/path/doc.pdf < /dev/null

# Whole-repo / multi-dir scan
agy --sandbox -p "<preamble> Scan <abs path>. file:line list grouped by directory." < /dev/null

# Text critique via Gemini — ATTACH the scanned packet (agy reads the @-file, not stdin);
# the packet must live in a SPACE-FREE dir (a space in an @-path silently sends NO content).
agy --sandbox --print-timeout=120s -p "<preamble> <prompt>" @"$rundir/input-diff.patch" < /dev/null

# Multi-image (≥3 shots) — --add-dir a SPACE-FREE staging dir, NEVER @-cram.
imgdir=/tmp/visrev; mkdir -p "$imgdir"; cp /path/shots/*.png "$imgdir"/
agy --sandbox --add-dir "$imgdir" --print-timeout=120s \
  -p "<preamble> VIEW each image in $imgdir. One line per file: <filename>: <finding>. End with VERDICT." < /dev/null
```

**agy gotchas (the specialist lane's sharpest edges):**
1. **Multi-image → `--add-dir`, never `@`-cram.** Inlining several (esp. multi-MB)
   images as trailing `@file` args **hangs** in image-loading, *before* the
   print-wait — `--print-timeout` doesn't bound it, and shell `timeout` can't kill a
   Go binary. `--add-dir <dir>` makes agy read each image with its own tools.
2. **A space in an `@`-path silently sends NO content.** Stage in a space-free dir
   (`/tmp/…`, or the run dir under `$CROSS_MODEL_OUT_DIR`) — the operator repo lives
   under a path with a space, so this bites.
3. **`--print-timeout` caps the model wait, not the upload;** pipe `< /dev/null` for
   stdin on headless runs.

Guardrail split: `--sandbox` ENFORCEs (terminal/write restrictions); the no-go
preamble INSTRUCTs (disclosure / no-roam). If `--sandbox` ever blocks an attachment
read on this agy version, fall back to `--dangerously-skip-permissions` **with the
no-go preamble still prepended** — never drop the INSTRUCT guard.

Always demand timestamps / page numbers / `file:line` citations — never a flat summary.

## Panel → judge → synthesis — explicit consensus only

Only when the user explicitly invokes it ("ask all three", "before I commit",
"cross-architecture consensus"). This is the panel lane — **diversity-dominated**
(open-ended question, no CI backstop, the opposite economics from code review).

- **Panelists** = GPT (Codex) + Gemini (agy). Each answers the **same** question
  independently with structured output:

  ```
  Recommendation: <one line>
  Blocking risks: <bullet list>
  Assumptions: <bullet list>
  Confidence: low | med | high
  Tests to verify: <bullet list>
  ```

- **Judge / synthesizer** = **Claude** (never a panelist of its own question). Diff
  the answers — where they agree, where they disagree — and adjudicate **by
  evidence, not by averaging** (a wrong-but-confident panelist doesn't pull the
  mean). Verify any checkable panelist claim against the primary source before
  accepting it. Gate the synthesis at `>= 50`.

## Startup self-check (once per session, before the first route)

```bash
codex --version 2>&1 | head -1   # GPT critic CLI
agy --version 2>&1 | head -1     # Gemini critic CLI
```

Surface the resolved flagship-tier model per family alongside the versions. A
missing CLI → announce once, continue gracefully (the eligible set shrinks to the
present critics), do not retry every turn. `agy` lives at `~/.local/bin/agy`; if the
binary exists but `agy --version` fails, `~/.local/bin` isn't on `PATH`.

## Filing

```
$CROSS_MODEL_OUT_DIR/<YYYY-MM-DD>-<slug>/
  ├── input-diff.patch — the scanned packet sent to the critic (post-scan; same file the scan gate validated)
  ├── <critic>-review.md — critic output (codex-review.md / gemini-review.md)
  └── reconciled.md    — Claude's synthesis
```

Append one line per run to `$CROSS_MODEL_OUT_DIR/log.md` — the compounding ledger.
`CROSS_MODEL_OUT_DIR` defaults to `$HOME/cross-model-out`.

## Announcement protocol

When this skill fires a route the user did NOT explicitly ask for (risk-path forced
adversarial, failure-counter rescue), announce in one line BEFORE running so the
user can interrupt. For routes the user explicitly asked for ("check this", "tear it
apart"), just do it. End cross-model replies with a one-line route trailer:
`(Routed via cross-model-review → GPT.)`, `→ Gemini.`, or `→ panel.`.

## Stay-asleep rules

- "Explain / what is / how does / walk me through" → driver direct.
- "Write / draft / build / refactor" on non-risky paths → driver direct (a later
  "check your work" re-triggers the no-self-review law).
- "Review my notes / review my draft email" — user's content, not Claude's → driver direct.
- Casual chat, status questions, file ops, git/bash/grep → driver direct.

When uncertain on a driver-output review verb: **fire**. When uncertain on
user-content review: **stay asleep**. Under-firing on user content is fine;
over-firing breaks trust.

---

**Origin:** a single-critic review skill upgraded with cross-architecture-consensus
discipline (OpenRouter Fusion-informed). The load-bearing design decision is
single-critic-for-verifiable-artifacts (code, with a CI backstop) vs
panel-for-open-ended-consensus (diversity-dominated); everything else (scan gate,
rubric, taxonomy, validator, rescue, risk paths) is supporting machinery. Operator-
local skill — drop the folder into `$CLAUDE_CONFIG_DIR/skills/cross-model-review/`
(no compile step).
