---
name: cross-model-review
description: Use when the user asks to check / review / verify / audit / sanity-check / proof / second-opinion / critique / tear apart / find what's wrong with work Claude just produced. Also use when stuck or after 2× the same failure (rescue), when editing risky paths (auth/billing/secrets/infra — forced adversarial), or for huge-packet / whole-repo / image / video / audio / large-PDF input (specialist lanes). Never review your own output — route to a different model family. The three critics are GPT Sol (via the Codex CLI), Grok (via the Cursor agent CLI), and GLM 5.3 Flash (via Ollama Cloud), equal first-class peers; Gemini (via the agy CLI) serves the video/audio/large-PDF media lane only, never the panel. Single critic for code review; panel→judge→synthesis for open-ended consensus.
---

# Cross-Model Review

The driver (Claude) never reviews its own output: on any check / review / verify / audit /
sanity-check / tear-apart of work Claude just produced, route to a **different model family**.
Same-family review inherits the same blind spots — architectural distance is the point.

The three critic families are **equal first-class peers**, **no capability hierarchy in any
direction**: **GPT Sol** (the `codex` CLI), **Grok** (the `cursor-agent` CLI), and
**GLM 5.3 Flash** (`glm-5.3-flash:cloud` via the `ollama` CLI / Ollama Cloud — 1M-token
context, vision). Select by **role** (Claude drives, so it routes elsewhere) and **lane** (what
the task needs), never by ranking. Gemini (`agy`) is the media specialist — video/audio/large-PDF
only, never a panelist and never a code critic. Images route to GLM (vision) or Gemini.

## Roles, eligibility, and count

- **Driver** — Claude (this session); never a critic or panelist of its own output.
- **Critics** — the non-Claude families: GPT Sol (Codex), Grok (Cursor), GLM (Ollama).
- **Judge / synthesizer** — Claude, for multi-critic lanes. **The driver judges and is never
  a panelist of its own question.**

**Eligibility (who *may* critique) is separate from count (how many *do*).** Eligibility is
fixed here: critics = {Sol, Grok, GLM}. **Count is decided by the lane** — a verifiable
artifact (code, diffs) fires **one** critic, the default; an open-ended consensus question
fires the **panel** (all available critics), only when the economics justify it.

## Triggers — MUST fire on Claude's-own-work review verbs

"check your work", "review what you wrote", "is this right?", "tear this apart", "sanity
check", "audit this", "second opinion", "proof this", "find what's wrong". When uncertain
on a driver-output review verb, **fire** — a missed self-review is the failure this skill
exists to prevent.

**Exception:** content the *user* wrote (email, notes, draft) is not Claude's output — review it
directly, do not route it.

## The two critique lanes — one critic, different prompt

A code/diff review fires **one** critic: **Sol (Codex)** for standard diffs, **GLM (Ollama)**
for a large packet, **Grok (Cursor)** when agentic repo reading earns its keep (lanes below).
Always pipe content via stdin where the CLI supports it; **never** tell a critic to "go read
these files" outside a deliberately granted workspace (it hangs on approval round-trips).
Source the scan gate first, then:

`<anchors>` below expands to: *confidence anchor — 0=false-positive/pre-existing, 25=can't verify,
50=advisory/unconfirmed, 75=concrete consequence a user/caller hits, 100=verifiable AND frequent.
Omit 0 and 25.*

**Confirmation review (default):**

```bash
cat "$rundir/input-diff.patch" | codex exec --skip-git-repo-check -s read-only \
  -m gpt-5.6-sol -c model_reasoning_effort="high" \
  "<no-go preamble: core + critique clause> Review this diff. For each finding: title, file:line, why-it-matters, and a <anchors>. Then Blocking risks / Missing tests. Be specific." \
  > "$rundir/sol-review.md"
```

**Adversarial review** (on "tear this apart" / "stress test" / "prove it's broken", or
forced by the risk paths below) — same invocation, this prompt instead:

```bash
  "<no-go preamble> Adversarial review — construct failure scenarios, don't checklist. Run the four techniques scaled to diff size/risk (see taxonomy): (1) assumption violation, (2) composition failure across boundaries, (3) cascade construction, (4) abuse cases. Each finding: the scenario step-by-step (trigger → path → wrong outcome), file:line, <anchors>. Prove it's broken." \
```

**GLM takes either prompt unchanged** — pipe preamble + prompt + packet as one stream (recipe
in its lane below).

**Resume invariant — force read-only on every `codex exec resume`.** A fresh `codex exec`
accepts `-s read-only`, but `codex exec resume` **rejects** `-s` and silently inherits
`~/.codex/config.toml`'s `sandbox_mode` (which may be `danger-full-access`). `resume`
accepts `-c`, so pin it there:
`codex exec resume <thread-id> -c sandbox_mode="read-only" --skip-git-repo-check "<prompt>"`.
A read-only critic must never escalate to write access on a resume turn. (macOS has no
`timeout`; kill a hung `codex exec` by PID.)

Integrate findings into the reply — never dump a raw critic transcript at the user.

## Outbound-content scan (pre-pipe) — a hard gate

Scan every packet for credential-shaped strings before it leaves for a critic — a third-party
model **outside the operator's machine**. **Hard gate, not advisory: it fails closed.** Helper:

```bash
. "$CLAUDE_CONFIG_DIR/skills/cross-model-review/scan-outbound.sh"

rundir="${CROSS_MODEL_OUT_DIR:-$HOME/cross-model-out}/$(date -u +%Y-%m-%d)-<slug>"
mkdir -p "$rundir"
git diff > "$rundir/input-diff.patch"

if ! scan_outbound "$rundir/input-diff.patch" "$rundir"; then
  printf 'BLOCKED: outbound scan — see %s/exfil-block.md or stderr above\n' "$rundir" >&2
  exit 1
fi
# ...only now pipe "$rundir/input-diff.patch" to the critic.
```

**Helper contract** — `scan_outbound <input-file> [<run-dir>]`: `0` clean (proceed), `1` a
match (`<run-dir>/exfil-block.md` gets a redacted snippet; do NOT pipe), `2` error (missing
args/input/grep) — **fail closed**, treat `2` like `1`. The pattern set lives in the script
(API-key prefixes such as `sk-…`, chat / version-control / cloud tokens, high-entropy hex);
read it there. Two limits it won't state: full-line git patch headers are excluded from the hex
pattern, so git show / diff / format-patch packets pass unstripped and a hex secret shaped
exactly like such a header is an accepted residual; and this is a **credential tripwire, not
DLP** — proprietary source and customer data stay out of scope, the operator owns what gets
piped, and a panel widens the blast radius to several external models. Real hits force a
credential rotation.

Cure the two known false positives **at the packet, never by widening the scanner**:
**lockfiles** (uv.lock, package-lock.json, Cargo.lock, poetry.lock — sha256 package hashes) →
rebuild excluding it (`git diff -- . ':(exclude)<lockfile>'`), since the manifest diff carries the
dependency intent;
**pinned content digests** (a snapshot sha256 in a ship-authorization constant) → mask the
literals in the packet copy (`<SHA256-DIGEST-MASKED>`) and say so to the critic. Note either in
the ledger. **Self-test** with a runtime-constructed credential sentinel (must block) plus a
benign diff (must pass).

## Per-lane tool policy

The critic *is* a cloud model, so **provider-API network is always on** — "no web" never
means "no network."

| Lane | Provider network | Web-research tools | Writes/deletes | Local roam |
| --- | --- | --- | --- | --- |
| **Critique** (code/diff review) | on | **off** | off | off — content piped + scanned, or a single granted packet workspace |
| **Research** (web-grounded question) | on | **on** | off | off |

**Research lane:** web tools on, but **never pipe sensitive local context to a web-enabled
critic** — it can exfil that context through its live web tool, and the static scan checks the
input, not runtime HTTP. A critic needing local context runs web-off — never local-read and
network-egress in one critic. **GLM's packet lane is structurally isolated:** `ollama run` has
no tools of any kind, so ENFORCE holds by construction and only the no-go preamble (INSTRUCT)
rides along. **Grok's lane is agentic** — `cursor-agent -p`
ships with all tools on, so its read-only guarantee is `--mode ask` plus a staged packet
workspace, never the repo working tree (lane invariants below).

## Guardrail split + honest sandbox limits

- **ENFORCE** writes/deletes via a **read-only mode** (`codex -s read-only`;
  `cursor-agent --mode ask`) — a reviewer never writes.
- **INSTRUCT** disclosure / secrets / account-actions via the **no-go preamble** — it
  covers content the critic fetches itself, which the input scan can't see.

**Read-only is necessary, not sufficient** — it blocks writes, not reads. The read-side guard
is the combination: **stdin-only packet (Sol, GLM) or one staged packet workspace (Grok), plus
no web tools in critique.**

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

Pass **ephemeral per-call flags only**; never mutate behavior-affecting global config —
model, sandbox mode, permission policy — to run a review (the resume `-c sandbox_mode` pin
above is the danger case). Benign CLI writes (caches, auth refresh, logs) are fine — what
matters is config *semantics*. `cursor-agent --trust` trusts a directory for that
invocation's workspace — point it ONLY at the staged packet dir, never blanket-trust the repo.

## Model policy — operator-pinned roster, resolve successors on failure

Pin these operator-picked tags per call; never silently substitute:

| Family | CLI | Pinned invocation |
| --- | --- | --- |
| GPT Sol | `codex` | `-m gpt-5.6-sol -c model_reasoning_effort="high"` |
| Grok | `cursor-agent` | `--model cursor-grok-4.6-high-fast` |
| GLM | `ollama` | `glm-5.3-flash:cloud --think=high` |

When a pinned tag stops resolving (Ollama retires cloud tags on a schedule; Cursor and Codex
rotate model lists), **read the CLI's live model list** (`ollama show`, `cursor-agent models`,
the Codex 400 error names it) and move to the named successor at the same or higher tier — warn
the user, never silently degrade. The Codex CLI
(ChatGPT account) has **no fast Sol tag**: `gpt-5.6-sol-fast` is rejected, and the fast variant
exists only as Cursor's `gpt-5.6-sol-high-fast` transport, usable if a run explicitly wants it
(family distance lives in the model, not the CLI).

## Grading critic findings — anchored rubric + suppression

The critic self-anchors from its prompt's compact rubric; **Claude re-grades** here and owns the
call. Pick the anchor honestly true, never a value between.

| Anchor | Meaning | Route |
| --- | --- | --- |
| `0` | False positive, or pre-existing / not introduced by this diff | suppressed |
| `25` | Might be real, couldn't verify from the diff alone | suppressed |
| `50` | Real but advisory, **or** a real concern the critic couldn't fully verify | soft bucket — one line |
| `75` | Double-checked; a user/caller hits it in normal use; concrete consequence | actionable |
| `100` | Verifiable from the code itself **and** frequent | actionable |

**Anchor and severity are independent** — a P2 can be `100`, a P0 `50` if unverified.
**Threshold `>= 75` for code review** (linter/CI backstop, often publicly visible, claims
ground-truth verifiable → precision dominates); a **senses/premise review with no backstop**
gates at `>= 50`. **`75` requires a concrete downstream consequence** — "this could be cleaner"
is `50`. **Suppress entirely:** pre-existing issues; style a linter catches; intentional code
(check comments/commit first); generic "consider adding X"; lint-ignored code; quality opinions
not codified in the project's instruction files.

## Adversarial taxonomy — the four techniques

Scale depth to the diff (the critic self-calibrates): **Quick** (<50 lines, no risk) = technique
1, ≤3 findings; **Standard** (50-199, minor risk) = 1, 2, 4; **Deep** (200+, or
auth/payments/data-mutation/migration) = all four, trace chains.

1. **Assumption violation** — construct the input that breaks what the code assumes (data shape,
   timing, ordering, range); trace the consequence.
2. **Composition failure across boundaries** — components correct alone, the combination fails:
   contract mismatch, shared-state mutation, ordering, divergent error contracts.
3. **Cascade construction** — multi-step chains: resource exhaustion (timeout → retry → more
   load), state-corruption propagation, recovery-induced failure.
4. **Abuse cases** — legitimate-seeming use, bad outcome (not exploits): repetition abuse,
   timing abuse (deploy/cache gap), concurrent mutation, boundary walking.

Demand scenario-oriented findings — "cascade: payment timeout triggers unbounded retry
loop", not "missing timeout handling".

## Validator second-pass (high-stakes — optional)

For risk-path forced adversarial or anything externalized (PR comments, autofix), run an
independent second Sol pass per surviving `>= 75` finding. It **re-verifies, doesn't
re-reason** — answering only: real in the code as written? introduced by this diff? not
already handled elsewhere? Pipe the same diff via stdin; prompt for
`{"validated": true|false, "reason": "<one sentence>"}`; validate only if all three hold, and
reject when in doubt. **Drop any finding the validator rejects, times out on, or returns
malformed for.** Skip casual confirmation and report-only runs. Budget-cap ~15 findings.

## Rescue — 2× same failure (hard rule)

A deterministic counter, not a vibe. After Claude fails the same operation twice (same test
failure on the same path, same error on the same command, same edit re-tried with no progress),
MUST hand to a critic with full context:

```bash
cat <context-bundle> | codex exec --skip-git-repo-check -s read-only \
  -m gpt-5.6-sol -c model_reasoning_effort="high" \
  "Rescue. Driver tried 2× and failed. Full context attached. Solve from scratch."
# Any eligible family works — GLM takes the same bundle:
#   cat <context-bundle> | ollama run glm-5.3-flash:cloud --think=high --hidethinking
```

Reset only when the test/build passes, the goal changes, or the user says "keep trying."

## Risk-path forced adversarial (path-based, not keyword-based)

Active edits to these paths force an adversarial review without the user asking. Announce
in one line BEFORE running so the user can interrupt:

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

Verb-agnostic: "refactor", "plan", "design" fires if the target is risky; keywords alone in casual
chat do not — it must be an active edit on these paths.

## Agentic lane — Grok (Cursor agent CLI), workspace-scoped review

Grok reads files itself inside a granted workspace, killing the diff-only-blindness class without
giving up read-only.

```bash
# Text/diff critique — stage a packet dir, grant ONLY it as the workspace:
pktdir="$rundir"                      # panel: pktdir="$rundir/grok"
cursor-agent -p --output-format text --mode ask --trust \
  --workspace "$pktdir" --model cursor-grok-4.6-high-fast \
  "<no-go preamble: critique clause> Review the diff in input-diff.patch in this workspace. For each finding: title, file:line, why-it-matters, <anchors>. Then Blocking risks / Missing tests." \
  > "$rundir/grok-review.md" 2> "$rundir/grok-stderr.txt"

# Agentic repo review — packet dir AS workspace, plus a detached checkout of the reviewed
# ref via --add-dir (worktree/clone under /tmp, never the live tree; remove it after).
# That repo grant is DELIBERATE static input outside the outbound scan, which gates only
# the packet. <ref> must be the ref the diff applies to, or "undefined X" hits a wrong tree.
repodir=/tmp/review-repo   # git worktree add --detach /tmp/review-repo <ref>
cursor-agent -p --output-format text --mode ask --trust \
  --workspace "$pktdir" --add-dir "$repodir" --model cursor-grok-4.6-high-fast \
  "<preamble> Review the diff in input-diff.patch. The repository at the reviewed ref is also available: before claiming anything is undefined, unused, missing, or inconsistent, READ the surrounding files to verify. Cite file:line." \
  > "$rundir/grok-review.md" 2> "$rundir/grok-stderr.txt"
```

**Grok/Cursor gotchas — this lane's sharpest edges:**
1. **`-p` has ALL tools on by default — write and shell included.** `--mode ask` is the
   read-only ENFORCE, mandatory on every critique invocation; never pass `--force`/`--yolo`.
   Honest limit: it restricts writes/edits, not web access, so the preamble is this lane's
   only web guard — stage for Grok only content the preamble alone can safely protect.
2. **`--trust` is required for headless runs** — without it the run exits with a "Run 'agent'
   interactively to decide" notice and NO review. It is per-invocation, scoped to the dir you
   point it at: the staged packet dir.
3. **Pass `--workspace "$pktdir"` every time** — the default is the CWD, so a forgotten flag runs
   the critic inside whatever directory the driver is in.
4. **Byte-count the capture** (`wc -c`) and read stderr on an empty one — an empty file is a
   failed run to diagnose, never "no findings".
5. Tag pinned (`cursor-grok-4.6-high-fast`); on a tag error re-check `cursor-agent models`
   and take the successor Grok tag at the top tier.

## Long-context + vision lane — GLM (Ollama)

The **1M-token context** takes whole-repo text packets that would choke the other lanes, and this
is the roster's vision lane for images — a **tooling fact, not a ranking**.

```bash
# Whole-repo / huge-packet text review — stage, scan, pipe the whole packet:
{ printf '%s\n\n' "<no-go preamble: critique clause> <prompt — file:line findings grouped by directory>"; \
  cat "$rundir/input-repo-packet.txt"; } | \
  ollama run glm-5.3-flash:cloud --think=high --hidethinking > "$rundir/glm-review.md"

# Image review — stage the image into the run dir first; never point the critic at a
# live path outside it (the scan gate applies to staged packets):
cp /path/shot.png "$rundir/input-shot.png"
ollama run glm-5.3-flash:cloud --think=high --hidethinking \
  "<no-go preamble: specialist clause> Describe and critique the UI in $rundir/input-shot.png — one finding per line, end with VERDICT." \
  > "$rundir/glm-review.md"
```

**GLM gotchas:**
1. **Thinking is default-ON** — always pass `--hidethinking` (CLI) or `"think":false`
   (API), or the reasoning preamble lands in the captured review.
2. **TTY spinner ANSI noise** pollutes CLI captures — `grep -a` when reading back, or POST the same
   combined prompt to `localhost:11434/api/generate` with `"stream":false,"think":"high"`: `.response`
   is the review, reasoning goes to `.thinking`, so the capture stays clean WITHOUT downgrading think
   level.
3. **Cloud tags get retired on a schedule** — the self-check probes
   `ollama show glm-5.3-flash:cloud`; on failure take the named successor from the
   deprecations table (docs.ollama.com/cloud.md).
4. A run needing GLM **agentic** uses the Codex harness with an Ollama provider pin — every codex
   invariant applies unchanged.
5. **`--think=high` with the equals sign.** `--think` declares a no-opt default
   (`string[="true"]`), so space-form `--think high` leaves the level at default and injects
   the literal word `high` into the PROMPT. Same for `--think=false`.
6. **Empty `glm-review.md` + HTTP 200 in `~/.ollama/logs/server.log` = all thinking, no final
   answer** — the run spent its output budget inside the hidden block (stderr shows only
   spinner frames). Not quota, not a dead tag: re-run once WITHOUT `--hidethinking`, then strip
   the `<think>` block by hand.

## Media lane — Gemini (agy): video / audio / large-PDF only

Video, audio, large PDFs and multi-image sweeps — the inputs its tooling handles natively, a
**tooling fact, not a ranking**.

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

**agy gotchas — all load-bearing, each cost a lost run:**
1. **Headless runs REQUIRE `< /dev/null`** — an open stdin blocks before any content is read
   and masquerades as a sandbox hang.
2. **A space in an `@`-path silently sends NO content** — stage in a space-free dir (the
   operator repo path has a space).
3. **Empty response ≠ no findings.** Headless `--sandbox` AUTO-DENIES any tool needing the
   `command` permission and returns `status: SUCCESS` with an empty response. Add
   `--output-format json`, capture stderr, byte-count the output (`wc -c`), and for file reads
   add a "use ONLY your file-reading tool — no shell/terminal commands" clause. An empty
   `.response` is a permission failure to read from stderr, never "no findings".
4. **Multi-image → `--add-dir`, never trailing `@file` args** (image loading can hang before
   the print-wait; `--print-timeout` can't bound it).
5. **`--print-timeout` caps the model wait, not the upload** — 120s for images, ≥300s for
   anything text-heavy.
6. Resolve the current flagship via `agy models < /dev/null | head -1 | cut -f1` — first FIELD
   only, since the raw tab-separated line makes `--model` fail uncut.
7. `--dangerously-skip-permissions` drops ENFORCE — last resort only, no-go preamble kept.

`--sandbox` ENFORCEs, the no-go preamble INSTRUCTs (specialist clause: read only the provided
media). Always demand timestamps / page numbers / filenames — never a flat summary.

## Panel → judge → synthesis — explicit consensus only

Only when the user explicitly invokes it ("ask all three", "before I commit", "cross-architecture
consensus"). This lane is **diversity-dominated** — open-ended question, no CI backstop.

- **Panelists** = all available non-driver families: Sol + Grok + GLM. Each answers the **same**
  question independently with structured output:

  ```
  Recommendation: <one line>
  Blocking risks: <bullet list>
  Assumptions: <bullet list>
  Confidence: low | med | high
  Tests to verify: <bullet list>
  ```

- **Per-critic packet isolation (hard staging rule).** Panelists run concurrently, and a critic
  granted the shared run dir can list it and read another's in-flight review, breaking the
  independence premise. Stage a private packet dir per critic, grant only it:

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
  (`> "$rundir/sol-review.md"`, `> "$rundir/grok-review.md"`) — the judge reads the root, no
  critic can. Critics also read their own cwd, so never invoke one with its working directory
  inside the shared run dir: launch Sol with cwd set to its own packet dir
  (`cd "$rundir/sol" && cat input-* | codex exec …`). Record in `reconciled.md`: per-critic
  dirs staged, and the Grok transcript shows no listing/read of the other critics' files.

- **Judge / synthesizer** = **Claude**. Diff the answers — where they agree, where they
  disagree — and adjudicate **by evidence, not by averaging** (a wrong-but-confident panelist
  doesn't pull the mean). Verify any checkable claim against the primary source. Gate the synthesis
  at `>= 50`.

## Startup self-check (once per session, before the first route)

```bash
codex --version 2>&1 | head -1         # Sol critic CLI
cursor-agent --version 2>&1 | head -1  # Grok critic CLI (auth: cursor-agent status)
ollama --version 2>&1 | head -1        # GLM critic CLI
ollama show glm-5.3-flash:cloud >/dev/null 2>&1 || \
  echo "GLM cloud tag missing/retired — check docs.ollama.com/cloud.md deprecations"
agy --version 2>&1 | head -1           # Gemini media-specialist CLI (lane-only)
```

Surface the resolved model per family alongside the versions. A missing CLI → announce once and
continue with a smaller eligible set; do not retry every turn. `cursor-agent` lives at
`~/.local/bin/`; a binary that exists while `--version` fails means `~/.local/bin` isn't on `PATH`.

## Filing

```
$CROSS_MODEL_OUT_DIR/<YYYY-MM-DD>-<slug>/
  ├── input-diff.patch — the scanned packet sent to the critic
  ├── <critic>/ — panel runs: per-critic packet dir (copy of input-*), the ONLY dir it is granted
  ├── <critic>-review.md — critic output: sol-review.md / grok-review.md / glm-review.md
  └── reconciled.md — Claude's synthesis
```

Append one line per run to `${CROSS_MODEL_OUT_DIR:-$HOME/cross-model-out}/log.md` — the
compounding ledger. Use the defaulted form: a bare `$CROSS_MODEL_OUT_DIR` resolves to
`/log.md` when unset.

**Reading back the capture — two traps that look like an empty result.**
- **`grep -a`, always.** Critic transcripts and captured PowerShell logs carry ANSI colour
  escapes; plain `grep`/`rg` calls such a file **binary** and silently suppresses matches — you
  see nothing and wrongly conclude the run failed. Use `grep -a`, or strip ANSI first, on every
  `*-review.md` and PS log.
- **Codex findings live at the TAIL.** `codex exec` streams its reasoning trace,
  SessionStart-hook lines, and an occasional `failed to load skill …` warning *before* the
  answer; the real **Findings / Blocking risks / Missing tests** come at the END, after the
  final `codex` marker — extract the tail (`tail -n`), don't parse the whole transcript.
  `cursor-agent -p --output-format text` returns the final answer only: nothing to strip, but
  byte-count it (gotcha 4 above).

## Announcement protocol

Announce an unasked-for route (risk-path forced adversarial, failure-counter rescue) in one line
BEFORE running so the user can interrupt; a route the user asked for just runs. End cross-model
replies with a one-line route trailer:
`(Routed via cross-model-review → Sol.)`, `→ Grok.`, `→ GLM.`, `→ Gemini (media).`, or
`→ panel.`.

## Stay-asleep rules

- "Explain / what is / how does / walk me through" → driver direct.
- "Write / draft / build / refactor" on non-risky paths → driver direct (a later "check your
  work" re-triggers the no-self-review law).
- "Review my notes / review my draft email" — user's content, not Claude's → driver direct.
- Casual chat, status questions, file ops, git/bash/grep → driver direct.

When uncertain on user-content review, **stay asleep** — under-firing on user content is fine,
over-firing breaks trust.

---

**Origin:** the load-bearing design decision is single-critic-for-verifiable-artifacts (code,
with a CI backstop) vs panel-for-open-ended-consensus (diversity-dominated); everything else is
supporting machinery. Operator-local skill — drop the folder into
`$CLAUDE_CONFIG_DIR/skills/cross-model-review/` (no compile step); every lane in the current
roster was smoke-verified headless and read-only at adoption.
