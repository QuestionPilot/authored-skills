---
name: cross-model-review
description: Use when the user asks to check / review / verify / audit / sanity-check / proof / second-opinion / critique / tear apart / find what's wrong with work Claude just produced. Also use when stuck or after 2× the same failure (rescue), when editing risky paths (auth/billing/secrets/infra — forced adversarial), or for huge-packet / whole-repo / image / video / audio / large-PDF input (specialist lanes). Never review your own output — route to a different model family. The three critics are GPT Sol (via the Codex CLI), Grok (via the Cursor agent CLI), and GLM 5.3 Flash (via Ollama Cloud), equal first-class peers; Gemini (via the agy CLI) serves the video/audio/large-PDF media lane only, never the panel. Single critic for code review; panel→judge→synthesis for open-ended consensus.
---

# Cross-Model Review

The driver (Claude) never reviews its own output. When the user asks to check /
review / verify / audit / sanity-check / tear-apart work Claude just produced,
route to a **different model family** — a model reviewing its own family inherits
the same blind spots, and that architectural distance is the whole point.

The three critic families are **equal first-class peers**: **GPT Sol** (the
`codex` CLI), **Grok** (the `cursor-agent` CLI), and **GLM** (`glm-5.3-flash:cloud`
via the `ollama` CLI / Ollama Cloud). There is **no capability hierarchy in any
direction** — no "senses-only" family, no "stronger coder" family. Selection is
by **role** (Claude is the driver, so it routes to the other families) and by
**lane** (what the task needs), never by a cross-family ranking.

> **Panel v4 (2026-08-27, QUE-580).** Kimi K3 (kimi-k3:cloud) is retired from
> the critic set — operator decision; GLM returns as **GLM 5.3 Flash**
> (`glm-5.3-flash:cloud` via Ollama Cloud: 1M-token context, vision, thinking —
> verified via `ollama show` at adoption). Kimi's v3 lanes were these GLM lanes
> with `kimi-k3:cloud` in place of the GLM tag — swap the tag back if it returns.
> Gemini stays the media specialist (video/audio/large-PDF) only — never a
> panelist and never a code critic. Images route to GLM (vision) or Gemini.

## Roles, eligibility, and count

- **Driver** — Claude (this session). Never a critic or panelist of its own output.
- **Critics** — the non-Claude families: GPT Sol (Codex), Grok (Cursor), GLM (Ollama Cloud).
  Gemini (agy) is a **specialist, not a critic**: it reviews media inputs
  (video/audio/large-PDF) only and never joins the panel or the code lanes.
- **Judge / synthesizer** — Claude, for multi-critic lanes. **The driver judges; it
  is never a panelist of its own question** — that is the no-self-review boundary
  restated for the panel case.

**Eligibility (who *may* critique) is separate from count (how many *do*).**
Eligibility is fixed here: critics = {Sol, Grok, GLM}. **Count is decided by the
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

A code/diff review fires **one** critic. **Sol (Codex)** is the default code
critic for standard diffs; **GLM (Ollama)** when the packet is large (its
1M-token context takes whole-repo text packets); **Grok (Cursor)** when the
review benefits from agentic repo reading (see its lane below). Always pipe
content via stdin where the CLI supports it; **never** tell a critic to "go read
these files" outside a deliberately granted workspace (it can hang on approval
round-trips). Source the scan gate first (see next section), then:

**Confirmation review (default):**

```bash
cat "$rundir/input-diff.patch" | codex exec --skip-git-repo-check -s read-only \
  -m gpt-5.6-sol -c model_reasoning_effort="high" \
  "<no-go preamble: core + critique clause> Review this diff. For each finding: title, file:line, why-it-matters, and a confidence anchor — 0=false-positive/pre-existing, 25=can't verify, 50=real but advisory/unconfirmed, 75=concrete consequence a user/caller hits, 100=verifiable AND frequent. Omit 0 and 25. Then Blocking risks / Missing tests. Be specific." \
  > "$rundir/sol-review.md"
```

**Adversarial review** (on "tear this apart" / "stress test" / "prove it's broken",
or forced by the risk paths below):

```bash
cat "$rundir/input-diff.patch" | codex exec --skip-git-repo-check -s read-only \
  -m gpt-5.6-sol -c model_reasoning_effort="high" \
  "<no-go preamble> Adversarial review — construct failure scenarios, don't checklist. Run the four techniques scaled to diff size/risk (see taxonomy): (1) assumption violation, (2) composition failure across boundaries, (3) cascade construction, (4) abuse cases. Each finding: the scenario step-by-step (trigger → path → wrong outcome), file:line, confidence anchor (omit 0/25; 50=advisory, 75=concrete consequence, 100=verifiable AND frequent). Prove it's broken." \
  > "$rundir/sol-review.md"
```

**GLM equivalents (confirmation or adversarial — same prompts, different pipe).**
stdin carries preamble + prompt + packet in one stream; this lane has **no file,
dir, web, or shell access at all** — the packet is the critic's entire world:

```bash
{ printf '%s\n\n' "<no-go preamble + the same review prompt as above>"; \
  cat "$rundir/input-diff.patch"; } | \
  ollama run glm-5.3-flash:cloud --think high --hidethinking > "$rundir/glm-review.md"
# Clean-capture alternative (no TTY spinner noise in the output): POST the same
# combined prompt to localhost:11434/api/generate with "stream":false,"think":"high" —
# the .response JSON field is the review (reasoning arrives in a separate
# .thinking field, so the capture stays clean WITHOUT downgrading think level).
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
hits force a credential rotation. Known call-site false positives: **lockfiles**
(uv.lock, package-lock.json, Cargo.lock, poetry.lock) — their package sha256
hashes match the hex pattern; rebuild the packet excluding the lockfile
(`git diff -- . ':(exclude)<lockfile>'`) and note the exclusion in the ledger —
the manifest diff carries the dependency intent. Same class: **pinned content
digests** (a snapshot sha256 pinned into a ship-authorization constant) — mask
the digest literals in the packet copy (`<SHA256-DIGEST-MASKED>`), tell the
critic they are masked, and note it in the ledger (observed live 2026-08-20,
QUE-534 ship-pin review). Do not widen the scanner.

**Self-test** by planting a runtime-constructed credential sentinel (must block) +
a benign diff (must pass). **The scan is a credential tripwire only** — not
proprietary-source/customer-data DLP; the operator owns what gets piped, and a
panel widens the blast radius (content reaches multiple external models, not one).

## Per-lane tool policy

The critic *is* a cloud model, so **provider-API network is always on** — "no web"
never means "no network."

| Lane | Provider network | Web-research tools | Writes/deletes | Local roam |
| --- | --- | --- | --- | --- |
| **Critique** (code/diff review) | on | **off** | off | off — content piped + scanned, or a single granted packet workspace |
| **Research** (web-grounded question) | on | **on** | off | off |

**Critique lane:** content piped + scanned; no web tools, no writes, no roam.
**Research lane:** web tools on, but **never pipe sensitive local context to a
web-enabled critic** (it can exfil piped context through its live web tool; the
static scan checks the input, not runtime HTTP). A critic needing local context
runs web-off. Never combine local-read and network-egress tools in one critic.
**GLM packet lane is structurally isolated:** `ollama run` has no tools of any
kind — the ENFORCE column is satisfied by construction; only the no-go preamble
(INSTRUCT) rides along. **Grok's lane is agentic:** `cursor-agent -p` ships with
ALL tools on — write and shell included — so its read-only guarantee comes from
`--mode ask` (read-only Q&A mode) plus workspace scoping; never run a critic with
`--force`/`--yolo`, and never grant it the repo working tree as its workspace on
a critique run (stage a packet dir).

## Guardrail split + honest sandbox limits

- **ENFORCE** writes/deletes via a **read-only mode** (`codex -s read-only`;
  `cursor-agent --mode ask`) — a reviewer never writes.
- **INSTRUCT** disclosure / secrets / account-actions via the **no-go preamble** —
  it covers content the critic fetches itself, which the input scan can't see.

**Read-only is necessary, not sufficient** — it blocks writes, not reads. The real
read-side guard is the combination: **stdin-only packet (Sol, GLM) or a single
staged packet workspace (Grok) + no web tools in critique.**

### No-go preamble (prepend to every critic invocation)

Universal core always; append the active lane's clause.

> **Universal core (all lanes).** You are a read-only reviewer. Do not write, edit,
> or delete files; do not run state-mutating commands or take account actions; do not
> disclose, transmit, or store the reviewed content anywhere outside this response.
> Return findings only.
>
> **Critique lane adds:** review only the content provided to you (piped on stdin or
> present in the workspace you were given) — do not fetch additional files and make
> no network requests beyond your own model provider.
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
`cursor-agent --trust` trusts a directory for that invocation's workspace — point
it ONLY at the staged packet dir, never blanket-trust the repo.

## Model policy — operator-pinned roster, resolve successors on failure

The roster below is the **operator's explicit pick (2026-08-24, QUE-577)** — pin
these tags per call; do not silently substitute:

| Family | CLI | Pinned invocation |
| --- | --- | --- |
| GPT Sol | `codex` | `-m gpt-5.6-sol -c model_reasoning_effort="high"` |
| Grok | `cursor-agent` | `--model cursor-grok-4.6-high-fast` |
| GLM | `ollama` | `glm-5.3-flash:cloud --think high` |

When a pinned tag stops resolving (Ollama retires cloud tags on a schedule;
Cursor and Codex rotate model lists), **check the CLI's live model list**
(`ollama show`, `cursor-agent models`, the Codex 400 error names it) and move to
the named successor at the same or higher tier — warn the user, never silently
degrade. No version literal here outranks a live model list. Note: the Codex CLI
(ChatGPT account) has **no fast Sol tag** — `gpt-5.6-sol-fast` is rejected; the
fast variant exists only as Cursor's `gpt-5.6-sol-high-fast` transport, usable if
a run explicitly wants it (family distance lives in the model, not the CLI).

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
run an independent second Sol pass per surviving `>= 75` finding. It **re-verifies,
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
cat <context-bundle> | codex exec --skip-git-repo-check -s read-only \
  -m gpt-5.6-sol -c model_reasoning_effort="high" \
  "Rescue. Driver tried 2× and failed. Full context attached. Solve from scratch."
# Any eligible family works — GLM takes the same bundle:
#   cat <context-bundle> | ollama run glm-5.3-flash:cloud --think high --hidethinking
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

## Agentic lane — Grok (Cursor agent CLI), workspace-scoped repo review

Grok's lane is **agentic**: `cursor-agent` reads files itself inside a granted
workspace. That kills the diff-only-blindness class (confident "X is never
defined" strikes refuted by one grep) without giving up read-only. Verified live
2026-08-24 (`cursor-agent` 2026.08.11).

```bash
# Text/diff critique — stage a packet dir, grant ONLY it as the workspace:
pktdir="$rundir"                      # panel: pktdir="$rundir/grok"
cursor-agent -p --output-format text --mode ask --trust \
  --workspace "$pktdir" --model cursor-grok-4.6-high-fast \
  "<no-go preamble: critique clause> Review the diff in input-diff.patch in this workspace. For each finding: title, file:line, why-it-matters, confidence anchor (omit 0/25; 50=advisory, 75=concrete consequence, 100=verifiable AND frequent). Then Blocking risks / Missing tests." \
  > "$rundir/grok-review.md" 2> "$rundir/grok-stderr.txt"

# Agentic repo review — Grok reads the REPO itself, not just the diff. Grant the
# packet dir AS the workspace plus a detached checkout of the reviewed ref via
# --add-dir (worktree/clone under /tmp, never the live working tree):
repodir=/tmp/review-repo   # git worktree add --detach /tmp/review-repo <ref>
# The repo grant is DELIBERATE shared static input — it does not pass the
# outbound scan (operator-owned source; the scan gates the packet). <ref> must
# be the ref the diff applies to, or "undefined X" checks hit the wrong tree.
# Remove the worktree after the run (git worktree remove /tmp/review-repo).
cursor-agent -p --output-format text --mode ask --trust \
  --workspace "$pktdir" --add-dir "$repodir" --model cursor-grok-4.6-high-fast \
  "<preamble> Review the diff in input-diff.patch. The repository at the reviewed ref is also available: before claiming anything is undefined, unused, missing, or inconsistent, READ the surrounding files to verify. Cite file:line." \
  > "$rundir/grok-review.md" 2> "$rundir/grok-stderr.txt"
```

**Grok/Cursor gotchas (this lane's sharpest edges):**
1. **`-p` has ALL tools on by default — write and shell included.** `--mode ask`
   is the read-only ENFORCE; it is mandatory on every critique invocation. Never
   pass `--force`/`--yolo` on a review, and never rely on the preamble alone.
   Honest limit: `--mode ask` restricts writes/edits, not web access — the no-go
   preamble is the web guard on this lane, so never stage sensitive content for
   Grok that the preamble alone must protect from a web tool.
2. **Untrusted workspaces block headless runs** — without `--trust` the run exits
   with a "Run 'agent' interactively to decide" notice and NO review. `--trust`
   is per-invocation and scoped to the workspace you point it at; point it at the
   staged packet dir only.
3. **Workspace defaults to the CWD.** Always pass `--workspace "$pktdir"` — a
   forgotten flag runs the critic inside whatever directory the driver happens to
   be in (the live repo, a shared run dir).
4. **Byte-count the capture before trusting it** (`wc -c`) and read stderr on an
   empty one — an empty file is a failed run to diagnose, never "no findings".
5. **Model tag pinned** (`cursor-grok-4.6-high-fast`); on a tag error re-check
   `cursor-agent models` and pick the successor Grok tag at the top tier.

## Long-context + vision lane — GLM (Ollama), where the packet outsizes the others

GLM 5.3 Flash's **1M-token context** takes whole-repo text packets that would choke the
other lanes — a **tooling fact, not a ranking**. It is also the roster's
**vision-capable** critic (image inputs); video/audio/large-PDF route to the
Gemini media lane below.

```bash
# Whole-repo / huge-packet text review — stage, scan, pipe the whole packet:
{ printf '%s\n\n' "<no-go preamble: critique clause> <prompt — file:line findings grouped by directory>"; \
  cat "$rundir/input-repo-packet.txt"; } | \
  ollama run glm-5.3-flash:cloud --think high --hidethinking > "$rundir/glm-review.md"

# Image review — stage the image into the run dir first (scan gate applies to
# staged packets; never point the critic at a live path outside the run dir):
cp /path/shot.png "$rundir/input-shot.png"
ollama run glm-5.3-flash:cloud --think high --hidethinking \
  "<no-go preamble: specialist clause> Describe and critique the UI in $rundir/input-shot.png — one finding per line, end with VERDICT." \
  > "$rundir/glm-review.md"
```

**GLM gotchas (this lane's sharpest edges):**
1. **Thinking is default-ON** — always pass `--hidethinking` (CLI) or `"think":false`
   (API), or the reasoning preamble lands in the captured review.
2. **TTY spinner ANSI noise** pollutes CLI captures — `grep -a` when reading back,
   or capture via `localhost:11434/api/generate` for clean JSON.
3. **Cloud tags get retired on a schedule** — self-check probes
   `ollama show glm-5.3-flash:cloud`; on failure consult the deprecations table
   (docs.ollama.com/cloud.md) for the named successor.
4. The packet lane is **structurally tool-free** (nothing to sandbox); if a run
   ever needs GLM agentic, use the Codex harness with an Ollama provider pin —
   every codex invariant applies unchanged.

## Media specialist lane — Gemini (agy), video / audio / large-PDF only

Gemini is retained for the inputs its tooling handles natively (video, audio,
large PDFs, multi-image sweeps) — a **tooling fact, not a ranking**. Specialist
only: it never reviews code/diffs and never sits on the panel in v4.

```bash
# Video / audio — cap duration; timestamped findings
agy --sandbox -p "<no-go preamble: specialist clause> Analyze. Timestamped list: [MM:SS] event." @/path/clip.mp4 < /dev/null

# Large PDF — cap pages; page-numbered findings
agy --sandbox -p "<preamble> Key claims, tables, charts. Page-numbered." @/path/doc.pdf < /dev/null

# Multi-image (≥3 shots) — --add-dir a SPACE-FREE staging dir, NEVER @-cram
imgdir=/tmp/visrev; mkdir -p "$imgdir"; cp /path/shots/*.png "$imgdir"/
agy --sandbox --add-dir "$imgdir" --print-timeout=120s \
  -p "<preamble> VIEW each image in $imgdir. One line per file: <filename>: <finding>. End with VERDICT." < /dev/null
```

**agy gotchas (all load-bearing — each cost a lost run before it was learned):**
1. **Headless runs REQUIRE `< /dev/null`** — an open stdin blocks before any
   content is read and masquerades as a sandbox hang.
2. **A space in an `@`-path silently sends NO content** — stage in a space-free
   dir (the operator repo path has a space).
3. **Empty response ≠ no findings.** Headless `--sandbox` AUTO-DENIES any tool
   needing the `command` permission and returns `status: SUCCESS` with an empty
   response. Add `--output-format json`, capture stderr, byte-count the output
   (`wc -c`), and include a "use ONLY your file-reading tool — no shell/terminal
   commands" clause where file reads are involved. An empty `.response` is a
   permission failure to diagnose from stderr, never "no findings".
4. **Multi-image → `--add-dir`, never trailing `@file` args** (image loading can
   hang before the print-wait; `--print-timeout` can't bound it).
5. **`--print-timeout` caps the model wait, not the upload** — 120s for images,
   ≥300s for anything text-heavy.
6. Model: resolve the current flagship via
   `agy models < /dev/null | head -1 | cut -f1` (first FIELD only — the raw
   line is tab-separated and an uncut value makes `--model` fail).
7. Escalation to `--dangerously-skip-permissions` drops the ENFORCE layer —
   last resort only, no-go preamble always kept.

Guardrail split: `--sandbox` ENFORCEs; the no-go preamble INSTRUCTs (specialist
clause: read only the provided media, no other roam). Always demand timestamps /
page numbers / filenames — never a flat summary.

## Panel → judge → synthesis — explicit consensus only

Only when the user explicitly invokes it ("ask all three", "before I commit",
"cross-architecture consensus"). This is the panel lane — **diversity-dominated**
(open-ended question, no CI backstop, the opposite economics from code review).

- **Panelists** = all available non-driver families: Sol (Codex) + Grok (Cursor) +
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
  in-flight review (observed live 2026-07-06: a critic granted the shared root
  read another's review mid-write — the independence premise broken). Stage a
  private packet dir per critic and grant ONLY that dir:

  ```bash
  for critic in sol grok glm; do
    mkdir -p "$rundir/$critic"; cp "$rundir"/input-* "$rundir/$critic/"
  done
  # Sol panelist: pipe "$rundir/sol/<packet>" on stdin — no dir grant at all.
  # Grok panelist: --workspace "$rundir/grok" — NEVER the shared "$rundir".
  # GLM panelist: pipe "$rundir/glm/<packet>" on stdin — structurally isolated
  # (ollama run has no file access; a dir grant is not even possible).
  ```

  Review files still land in the shared root via driver-side redirects
  (`> "$rundir/sol-review.md"`, `> "$rundir/grok-review.md"`) — the judge
  reads the root; no critic can. Critics can also read their own cwd, so never
  invoke one with its working directory inside the shared run dir — on panel
  runs launch Sol with its cwd set to its own packet dir
  (`cd "$rundir/sol" && cat input-* | codex exec …`). Record the
  evidence in `reconciled.md`: per-critic dirs staged, and the Grok transcript
  shows no listing/read of the other critics' files.

- **Judge / synthesizer** = **Claude** (never a panelist of its own question). Diff
  the answers — where they agree, where they disagree — and adjudicate **by
  evidence, not by averaging** (a wrong-but-confident panelist doesn't pull the
  mean). Verify any checkable panelist claim against the primary source before
  accepting it. Gate the synthesis at `>= 50`.

## Startup self-check (once per session, before the first route)

```bash
codex --version 2>&1 | head -1         # Sol critic CLI
cursor-agent --version 2>&1 | head -1  # Grok critic CLI (auth: cursor-agent status)
ollama --version 2>&1 | head -1        # GLM critic CLI
ollama show glm-5.3-flash:cloud >/dev/null 2>&1 || \
  echo "GLM cloud tag missing/retired — check docs.ollama.com/cloud.md deprecations"
agy --version 2>&1 | head -1           # Gemini media-specialist CLI (lane-only)
```

Surface the resolved model per family alongside the versions. A missing CLI →
announce once, continue gracefully (the eligible set shrinks to the present
critics), do not retry every turn. `cursor-agent` lives at `~/.local/bin/`; if a
binary exists but `--version` fails, `~/.local/bin` isn't on `PATH`.

## Filing

```
$CROSS_MODEL_OUT_DIR/<YYYY-MM-DD>-<slug>/
  ├── input-diff.patch — the scanned packet sent to the critic (post-scan; same file the scan gate validated)
  ├── <critic>/ — panel runs: per-critic packet dir (own copy of input-*); the ONLY dir granted to that critic
  ├── <critic>-review.md — critic output (sol-review.md / grok-review.md / glm-review.md)
  └── reconciled.md    — Claude's synthesis
```

Append one line per run to `${CROSS_MODEL_OUT_DIR:-$HOME/cross-model-out}/log.md`
— the compounding ledger (use the defaulted form; a bare `$CROSS_MODEL_OUT_DIR`
resolves to `/log.md` when unset).

**Reading back the captured output — two traps that masquerade as "empty result".**
- **`grep -a`, always.** Critic transcripts and any captured PowerShell logs carry
  ANSI colour escapes; plain `grep`/`rg` treats such a file as **binary** and
  silently suppresses matches (you see nothing and wrongly conclude the run failed).
  Use `grep -a` — or strip ANSI first — on every `*-review.md` and PS log. GLM
  CLI captures carry spinner ANSI noise (or capture via the local API for clean
  JSON).
- **Codex findings live at the TAIL.** `codex exec` streams its reasoning trace,
  SessionStart-hook lines, and an occasional `failed to load skill …` warning *before*
  the answer; the real **Findings / Blocking risks / Missing tests** are at the END
  (after the final `codex` marker). Extract the tail (`tail -n`), don't parse the
  whole transcript. `cursor-agent -p --output-format text` returns the final
  answer only — nothing to strip, but byte-count it (gotcha 4 above).

## Announcement protocol

When this skill fires a route the user did NOT explicitly ask for (risk-path forced
adversarial, failure-counter rescue), announce in one line BEFORE running so the
user can interrupt. For routes the user explicitly asked for ("check this", "tear it
apart"), just do it. End cross-model replies with a one-line route trailer:
`(Routed via cross-model-review → Sol.)`, `→ Grok.`, `→ GLM.`,
`→ Gemini (media).`, or `→ panel.`.

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
critic family (QUE-427). 2026-08-24 (QUE-577): **panel v3** — GLM retired for
now; roster is Sol (Codex CLI) + Grok 4.6 (Cursor agent CLI) + Kimi K3 (Ollama
Cloud), all three lanes smoke-verified headless and read-only at adoption.
Gemini (agy) left the panel the same day but was retained as the
video/audio/large-PDF media specialist (operator decision, same session). 2026-08-27 (QUE-580): **panel v4** — Kimi K3
retired; GLM returns as GLM 5.3 Flash (`glm-5.3-flash:cloud`, 1M context +
vision), headless pipe smoke-verified at adoption.
