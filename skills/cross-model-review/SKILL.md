---
name: cross-model-review
description: Use when the user asks to check / review / verify / audit / sanity-check / proof / second-opinion / critique / tear apart / find what's wrong with work Claude just produced. Also use when stuck or after 2× the same failure (rescue), when editing risky paths (auth/billing/secrets/infra — forced adversarial), or for video/audio/large-PDF/whole-repo input (specialist lanes). Never review your own output — route to a different model family. The three critics are GPT (via the Codex CLI), Gemini (via the agy CLI), and GLM (via Ollama Cloud), equal first-class peers. Single critic for code review; panel→judge→synthesis for open-ended consensus.
---

# Cross-Model Review

The driver (Claude) never reviews its own output. When the user asks to check /
review / verify / audit / sanity-check / tear-apart work Claude just produced,
route to a **different model family** — a model reviewing its own family inherits
the same blind spots, and that architectural distance is the whole point.

The three critic families are **equal first-class peers**: **GPT** (the `codex`
CLI), **Gemini** (the `agy` CLI), and **GLM** (`glm-5.2:cloud` via the `ollama`
CLI / Ollama Cloud). There is **no capability hierarchy in any direction** — no
"senses-only" family, no "stronger coder" family. Selection is by **role** (Claude
is the driver, so it routes to the other families) and by **lane** (what the task
needs), never by a cross-family ranking. GLM transport + model guide (verified
recipes, deprecation watch): vault wiki `10-Wiki/Entities/Ollama Cloud + GLM-5.2 —
CLI & API Guide`.

## Roles, eligibility, and count

- **Driver** — Claude (this session). Never a critic or panelist of its own output.
- **Critics** — the non-Claude families: GPT (Codex), Gemini (agy), GLM (Ollama Cloud).
- **Judge / synthesizer** — Claude, for multi-critic lanes. **The driver judges; it
  is never a panelist of its own question** — that is the no-self-review boundary
  restated for the panel case.

**Eligibility (who *may* critique) is separate from count (how many *do*).**
Eligibility is fixed here: critics = {GPT, Gemini, GLM}. **Count is decided by the
lane** — a verifiable-artifact review (code, diffs) fires **one** critic; an
open-ended consensus question fires the **panel** (all available critics). Single
critic by default; the panel only when the economics justify it.

## Triggers — MUST fire on Claude's-own-work review verbs

"check your work", "review what you wrote", "is this right?", "tear this apart",
"sanity check", "audit this", "second opinion", "proof this", "find what's wrong".
When uncertain on a driver-output review verb, **fire** — a missed self-review is
the failure this skill exists to prevent.

**Exception:** content the *user* wrote (their email, notes, draft) is not Claude's
output. Review that directly; do not route it.

## The two critique lanes — one critic, different prompt

A code/diff review fires **one** critic. **GPT (Codex)** and **GLM (Ollama)** are
both first-choice code critics: GPT for standard diffs, GLM when the packet is
large (its 1M-token context takes whole-repo text packets no other lane can);
use Gemini (agy) when the input is in its media specialist lane (below). Always
pipe content via stdin; **never** tell a critic to "go read these files" (it can
hang on approval round-trips). Source the scan gate first (see next section), then:

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

**GLM equivalents (confirmation or adversarial — same prompts, different pipe).**
stdin carries preamble + prompt + packet in one stream; this lane has **no file,
dir, web, or shell access at all** — the packet is the critic's entire world:

```bash
{ printf '%s\n\n' "<no-go preamble + the same review prompt as above>"; \
  cat "$rundir/input-diff.patch"; } | \
  ollama run glm-5.2:cloud --think high --hidethinking > "$rundir/glm-review.md"
# Clean-capture alternative (no TTY spinner noise in the output): POST the same
# combined prompt to localhost:11434/api/generate with "stream":false,"think":false —
# the .response JSON field is the review.
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
tokens, cloud access keys, length-thresholded high-entropy hex. Full-line-anchored
git patch-header shapes (commit/index/From/Merge) are excluded from the hex pattern
only, so git show / diff / format-patch packets pass unstripped; a hex secret
formatted exactly as such a header line is an accepted residual — this is a
tripwire, not DLP. Tunable; false positives allowlisted at the call site, real
hits force a credential rotation.

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
**GLM packet lane is structurally isolated:** `ollama run` has no tools of any
kind — the ENFORCE column is satisfied by construction; only the no-go preamble
(INSTRUCT) rides along. GLM's *agentic* lane is codex's sandbox with a different
brain — every codex invariant applies unchanged.

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
is fine — not a cross-family claim); **GLM** resolves to the newest `glm-*:cloud`
tag on Ollama Cloud (currently `glm-5.2:cloud`) — Ollama **retires cloud models on
a schedule**, so a failing `ollama show glm-5.2:cloud` means "check the deprecations
table at docs.ollama.com/cloud.md and move to the named successor," not an outage.
The resolution *mechanism* differs per CLI; the *intent* (each lands on its own
flagship) does not. Surface the resolved model per family in the self-check; warn
rather than silently degrade.

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
# Any eligible family works — GLM takes the same bundle:
#   cat <context-bundle> | ollama run glm-5.2:cloud --think high --hidethinking
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

# Text critique via Gemini — the RELIABLE recipe (root-caused 2026-08-06).
# Three load-bearing pieces, all mandatory:
#   1. SPACE-FREE dir granted via --add-dir; NAME the file in the prompt (the bare
#      @-attach form times out under --sandbox and sends NOTHING if the path has a
#      space — kept below only to name the trap).
#   2. "File-reading tool ONLY, no shell commands" clause in the prompt. Under
#      headless --sandbox, agy AUTO-DENIES any tool needing the `command`
#      permission (it cannot prompt) — the model shells out to grep/read, gets
#      silently denied, and returns status SUCCESS with an EMPTY response. This
#      was the real cause of every "Gemini returned nothing" panel run.
#   3. --output-format json + resolve the current flagship explicitly. Parse
#      .response; an EMPTY .response with status SUCCESS = tool auto-denial (the
#      named diagnostic is on stderr), NEVER "no findings".
# pktdir: single-critic runs may use "$rundir"; PANEL runs MUST use the
# per-critic dir ("$rundir/gemini") — a concurrent panelist's review is readable
# in the shared root (see panel lane).
pktdir="$rundir"                      # panel: pktdir="$rundir/gemini"
gem_model="$(agy models < /dev/null | head -1)"  # newest flagship-highest-effort tag lists first
case "$gem_model" in gemini-*) ;; *) echo "agy models gave '$gem_model' — resolve manually" >&2; exit 1;; esac
agy --sandbox --model "$gem_model" --add-dir "$pktdir" --print-timeout=300s \
  --output-format json \
  -p "<preamble> Use ONLY your file-reading tool — do NOT run any shell or terminal command. <prompt> The diff is the file input-diff.patch in the directory you have been given — read that one file and review it." \
  < /dev/null > "$rundir/gemini-review.json" 2> "$rundir/gemini-stderr.txt"
# Gate before trusting — ALL of: exit 0, valid JSON, .status == SUCCESS,
# .response non-empty AND not a refusal ("I cannot access…"). On an empty
# .response, read gemini-stderr.txt (it names the denied permission), retry once
# with the file-reading-tool clause intact, then — and only then — escalate.
# Escalation DROPS the ENFORCE layer entirely (only the INSTRUCT preamble
# remains — never drop it too), so it is last resort, not step two:
#   agy --dangerously-skip-permissions --model "$gem_model" --add-dir "$pktdir" \
#     --print-timeout=400s --output-format json -p "<same prompt>" \
#     < /dev/null > "$rundir/gemini-review.json" 2> "$rundir/gemini-stderr.txt"
# Legacy / unreliable (kept only to name the trap): agy --sandbox -p "…" @"$rundir/input-diff.patch" < /dev/null

# Agentic repo review — Gemini reads the REPO itself, not just the diff. Kills
# the diff-only-blindness class (confident "X is never defined" 100s refuted by
# one grep — twice in past panels). Same three-piece gate as the text recipe;
# grant the packet dir AND a SPACE-FREE repo checkout (the living folder has a
# space — use a worktree/clone under /tmp, detached at the reviewed ref;
# --add-dir is repeatable). Read-only is preserved: --sandbox + read-tool clause
# — the critic reads files, it cannot run git or shell.
repodir=/tmp/review-repo   # git worktree add --detach /tmp/review-repo <ref>
agy --sandbox --model "$gem_model" --add-dir "$pktdir" --add-dir "$repodir" \
  --print-timeout=300s --output-format json \
  -p "<preamble> Use ONLY your file-reading tool — do NOT run any shell or terminal command. Review the diff in input-diff.patch (first directory). The full repository at the reviewed ref is in the second directory: before claiming anything is undefined, unused, missing, or inconsistent, READ the surrounding files to verify. Cite file:line." \
  < /dev/null > "$rundir/gemini-review.json" 2> "$rundir/gemini-stderr.txt"
# Same gate as above; panel runs still stage per-critic packet dirs, and reviews
# land via driver-side redirects — the repo grant is shared static INPUT, which
# is fine; never let reviews land inside a granted dir.

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
   stdin on headless runs. For a TEXT diff review use **≥300s** — text reasons far
   longer than the 120s an image needs, and a too-short cap reads as a "timeout".
4. **Empty response ≠ no findings — it is silent tool auto-denial (the packet-size
   theory is REFUTED).** Headless `--sandbox` cannot prompt, so any tool needing
   the `command` permission is auto-denied and agy returns `status: SUCCESS` with
   an empty `response` — text output mode throws the stderr diagnostic away, which
   is why this masqueraded first as a "sandbox hang", then as a ">50KB packet cap"
   (two 2026-08-06 panel runs). Fixture-refuted same day on agy 1.1.10: a 122KB
   packet reviewed correctly in ~2s under BOTH `--sandbox` (with the
   file-reading-tool-only clause) and the escalated form. Do not slim packets for
   Gemini; do use the three-piece reliable recipe above, and treat any empty
   `.response` as a permission failure to diagnose from stderr — never report it
   as "Gemini found nothing".
5. **Text-packet review → `--add-dir` + NAME the file, never `@`-attach.** Both
   `@"…/input-diff.patch"` and `--add-dir` *under `--sandbox`* have **timed out**
   ("Error: timed out waiting for response") on a plain text diff (confirmed twice —
   this run + a prior eval run). Those timeouts are most plausibly gotcha 4's
   auto-denial surfacing as a wait rather than an empty result — same cure:
   the file-reading-tool-only clause + JSON gating. Reliable path: `--add-dir
   <space-free dir>` + a prompt that names the file to read + `--print-timeout=300s`;
   if it STILL times out, escalate to `--dangerously-skip-permissions` (no-go
   preamble still prepended). Treat the bare `@`-attach as a trap, not the default.
6. **Every headless agy recipe in this lane — media included — gets the same
   three-piece gate.** The video/PDF/whole-repo/multi-image recipes above predate
   the root cause; when running any of them headless, add `--output-format json`,
   capture stderr, and (except whole-repo scans, which legitimately roam) the
   file-reading-tool-only clause — an empty `.response` in ANY recipe is a
   permission failure, not an empty finding set.

Guardrail split: `--sandbox` ENFORCEs (terminal/write restrictions); the no-go
preamble INSTRUCTs (disclosure / no-roam). If `--sandbox` ever blocks an attachment
read on this agy version, fall back to `--dangerously-skip-permissions` **with the
no-go preamble still prepended** — never drop the INSTRUCT guard.

Always demand timestamps / page numbers / `file:line` citations — never a flat summary.

## Long-context lane — GLM (Ollama), where the packet outsizes the others

GLM-5.2's **1M-token context** takes whole-repo text packets that would choke the
other lanes — a **tooling fact, not a ranking**. Text only: GLM has **no vision
through Ollama**, so media stays with Gemini above.

```bash
# Whole-repo / huge-packet text review — stage, scan, pipe the whole packet:
{ printf '%s\n\n' "<no-go preamble: critique clause> <prompt — file:line findings grouped by directory>"; \
  cat "$rundir/input-repo-packet.txt"; } | \
  ollama run glm-5.2:cloud --think high --hidethinking > "$rundir/glm-review.md"

# Agentic repo exploration — GLM brain in the codex harness (codex's built-in
# `ollama` provider); ALL codex sandbox rules apply unchanged (-s read-only,
# resume pin, no behavior-affecting global writes):
codex exec --skip-git-repo-check -s read-only \
  -c model_provider=ollama -c model="glm-5.2:cloud" \
  "<no-go preamble> <review prompt — cite file:line>" > "$rundir/glm-review.md"
```

**GLM gotchas (this lane's sharpest edges):**
1. **Thinking is default-ON** — always pass `--hidethinking` (CLI) or `"think":false`
   (API), or the reasoning preamble lands in the captured review.
2. **TTY spinner ANSI noise** pollutes CLI captures — `grep -a` when reading back,
   or capture via `localhost:11434/api/generate` for clean JSON.
3. **Cloud tags get retired on a schedule** — self-check probes
   `ollama show glm-5.2:cloud`; on failure consult the deprecations table
   (docs.ollama.com/cloud.md) for the named successor.
4. The packet lane is **structurally tool-free** (nothing to sandbox); the agentic
   lane is codex's sandbox with a different brain — same invariants, same tail-parse
   rule for output.

## Panel → judge → synthesis — explicit consensus only

Only when the user explicitly invokes it ("ask all three", "before I commit",
"cross-architecture consensus"). This is the panel lane — **diversity-dominated**
(open-ended question, no CI backstop, the opposite economics from code review).

- **Panelists** = all available non-driver families: GPT (Codex) + Gemini (agy) +
  GLM (Ollama). Each answers the **same** question independently with structured
  output:

  ```
  Recommendation: <one line>
  Blocking risks: <bullet list>
  Assumptions: <bullet list>
  Confidence: low | med | high
  Tests to verify: <bullet list>
  ```

- **Per-critic packet isolation (hard staging rule).** Panelists run concurrently,
  and a critic granted the shared run dir can list it and read the other's
  in-flight review (observed live 2026-07-06: agy, granted `--add-dir "$rundir"`,
  read `codex-review.md` mid-write — the independence premise broken). Stage a
  private packet dir per critic and grant ONLY that dir:

  ```bash
  for critic in codex gemini glm; do
    mkdir -p "$rundir/$critic"; cp "$rundir"/input-* "$rundir/$critic/"
  done
  # GPT panelist: pipe "$rundir/codex/<packet>" on stdin — no dir grant at all.
  # Gemini panelist: --add-dir "$rundir/gemini" — NEVER the shared "$rundir".
  # GLM panelist: pipe "$rundir/glm/<packet>" on stdin — structurally isolated
  # (ollama run has no file access; a dir grant is not even possible).
  ```

  Review files still land in the shared root via driver-side redirects
  (`> "$rundir/codex-review.md"`, `> "$rundir/gemini-review.md"`) — the judge
  reads the root; no critic can. The shared-root `--add-dir "$rundir"` in the
  specialist text recipe is safe only for single-critic runs. Critics can also
  read their own cwd, so never invoke one with its working directory inside the
  shared run dir. Record the evidence in `reconciled.md`: per-critic dirs staged,
  and the agy transcript shows no listing/read of the other critic's file.

- **Judge / synthesizer** = **Claude** (never a panelist of its own question). Diff
  the answers — where they agree, where they disagree — and adjudicate **by
  evidence, not by averaging** (a wrong-but-confident panelist doesn't pull the
  mean). Verify any checkable panelist claim against the primary source before
  accepting it. Gate the synthesis at `>= 50`.

## Startup self-check (once per session, before the first route)

```bash
codex --version 2>&1 | head -1   # GPT critic CLI
agy --version 2>&1 | head -1     # Gemini critic CLI
ollama --version 2>&1 | head -1  # GLM critic CLI
ollama show glm-5.2:cloud >/dev/null 2>&1 || \
  echo "GLM cloud tag missing/retired — check docs.ollama.com/cloud.md deprecations"
```

Surface the resolved flagship-tier model per family alongside the versions. A
missing CLI → announce once, continue gracefully (the eligible set shrinks to the
present critics), do not retry every turn. `agy` lives at `~/.local/bin/agy`; if the
binary exists but `agy --version` fails, `~/.local/bin` isn't on `PATH`.

## Filing

```
$CROSS_MODEL_OUT_DIR/<YYYY-MM-DD>-<slug>/
  ├── input-diff.patch — the scanned packet sent to the critic (post-scan; same file the scan gate validated)
  ├── <critic>/ — panel runs: per-critic packet dir (own copy of input-*); the ONLY dir granted to that critic
  ├── <critic>-review.md — critic output (codex-review.md / gemini-review.md / glm-review.md)
  └── reconciled.md    — Claude's synthesis
```

Append one line per run to `$CROSS_MODEL_OUT_DIR/log.md` — the compounding ledger.
`CROSS_MODEL_OUT_DIR` defaults to `$HOME/cross-model-out`.

**Reading back the captured output — two traps that masquerade as "empty result".**
- **`grep -a`, always.** Critic transcripts and any captured PowerShell logs carry
  ANSI colour escapes; plain `grep`/`rg` treats such a file as **binary** and
  silently suppresses matches (you see nothing and wrongly conclude the run failed).
  Use `grep -a` — or strip ANSI first — on every `*-review.md` and PS log.
- **Codex findings live at the TAIL.** `codex exec` streams its reasoning trace,
  SessionStart-hook lines, and an occasional `failed to load skill …` warning *before*
  the answer; the real **Findings / Blocking risks / Missing tests** are at the END
  (after the final `codex` marker). Extract the tail (`tail -n`), don't parse the
  whole transcript — this applies equally to codex-hosted GLM agentic runs. agy
  returns clean markdown — nothing to strip. GLM CLI captures carry spinner ANSI
  noise (use `grep -a`, or capture via the local API for clean JSON).

## Announcement protocol

When this skill fires a route the user did NOT explicitly ask for (risk-path forced
adversarial, failure-counter rescue), announce in one line BEFORE running so the
user can interrupt. For routes the user explicitly asked for ("check this", "tear it
apart"), just do it. End cross-model replies with a one-line route trailer:
`(Routed via cross-model-review → GPT.)`, `→ Gemini.`, `→ GLM.`, or `→ panel.`.

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
(no compile step). 2026-07-10: GLM-5.2 (Ollama Cloud) added as the third equal
critic family (QUE-427) — packet + long-context + agentic lanes verified live;
transport guide in the vault wiki.
