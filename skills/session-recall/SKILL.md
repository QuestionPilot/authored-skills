---
name: session-recall
description: "Search and answer questions about PRIOR coding-agent sessions (Claude Code + Codex) — what was worked on, what was tried before, how a problem was investigated, what was decided or learned, or what happened recently. Use when the user references past sessions, previous attempts, earlier investigations, or 'have we hit this before' / 'what did we try last time' / 'did a past session touch X' — even without saying 'sessions'. Script-first: bundled scripts discover + extract; the model only presents. Does NOT analyze the current session (already in context) and never loads raw transcripts."
---

# session-recall

Answer "what was tried / decided / learned before" across prior **Claude Code +
Codex** sessions, without reading raw transcripts into context. Bundled scripts do
all discovery, parsing, filtering, and extraction (script-first architecture — see
`reference/port-notes.md`); the model selects, dispatches a synthesis subagent, and
presents. Ported from the CE `ce-sessions` skill.

`SR=$CLAUDE_CONFIG_DIR/skills/session-recall` in the commands below.

## Guardrails (always)

- **Never read entire session files into context.** They can be 1–7 MB. Always run
  the extraction scripts to filter first, then reason over the filtered output.
- **Never analyze the current session** — its history is already in context. The
  discovery step excludes live sessions automatically (`--exclude-active-min`).
- **Never reproduce tool inputs/outputs verbatim**; summarize. **Never** surface
  thinking/reasoning content.
- **Surface technical content, not personal content.** Sessions contain credentials,
  frustration, half-formed opinions — use judgment. Scripts redact obvious secrets
  as a backstop; judgment is still required.
- **Fail fast on access errors.** If discovery fails on permissions, report it; do
  not retry with other tools.

## Execution

If no question/topic was given, ask what the user wants to know with
`AskUserQuestion` (load it via `ToolSearch select:AskUserQuestion` if its schema
isn't loaded). Don't silently skip the question.

### Step 1 — Scan window

Infer a day range from the question; start narrow, widen only if a narrow scan
finds nothing.

| Signal | Window (days) |
|---|---|
| "today", "this morning" | 1 |
| "recently", "this week", or no time signal | 7 |
| "this month", "last few weeks" | 30 |
| "last few months", broad history | 90 |

### Step 2 — Discover + extract metadata

Decide scoping from the question:
- **Specific repo/project** → pass `--cwd-filter <repo>` (a bare repo name like
  `myrepo`, or an absolute path). Matching is strict + path-component aware.
- **"Across everything" / no repo named** → omit `--cwd-filter` (all repos).

```bash
bash "$SR/scripts/discover-sessions.sh" <days> \
  | tr '\n' '\0' | xargs -0 python3 "$SR/scripts/extract-metadata.py" [--cwd-filter <repo>]
```

Each line is a JSON object (`platform`, `file`, `size`, `ts`, `session`, plus
`branch`/`cwd` when present). The final `_meta` line carries `files_processed`,
`parse_errors`, and `filtered_by_cwd`/`files_matched` when those filters ran.

- **Empty output** (no JSON at all) or a `_meta` line with `files_processed: 0`
  → return `no relevant prior sessions` and stop. (Both happen: BSD `xargs` on
  macOS does not invoke the extractor when discovery found nothing, so the
  pipeline emits nothing; GNU `xargs` emits the `files_processed: 0` line.)
- `parse_errors > 0` → note partial coverage and proceed.
- Restrict platform with `--platform claude` or `--platform codex` on
  `discover-sessions.sh` (default: both). Live sessions are excluded by default
  (`--exclude-active-min 2`); raise it if even just-finished sessions should drop.

### Step 3 — Filter and rank

1. **Branch/keyword filter.** For a Claude session, prefer exact `branch` match or a
   branch name containing a topic keyword. `cwd`/`branch` are captured at the FIRST
   user message only — a session that began on `main` then switched branches reads
   as `main`, so a zero-result branch filter is NOT conclusive.
2. **If branch match is empty (or for Codex):** derive 2–4 keywords from the topic
   and re-run extract-metadata with `--keyword K1,K2,...`. Rank by `match_count`.
   If `files_matched: 0`, return `no relevant prior sessions` and stop.
3. Drop sessions outside the window (use `last_ts`, fall back to `ts`).
4. **Cap: at most 5 sessions total.** Narrow by branch/keyword match → `match_count`
   → size > 30 KB → recency. Proceed only if ≥1 remains.

### Step 4 — Scratch space

```bash
SCRATCH=$(mktemp -d -t session-recall-XXXXXX)
```

### Step 5 — Extract per-session content (file-mediated)

For each selected session, write the skeleton straight to scratch — bytes never
round-trip through the orchestrator's tool results:

```bash
python3 "$SR/scripts/extract-skeleton.py" --output "$SCRATCH/<id>.skeleton.txt" < <session-file>
```

Stdout is a one-line JSON status (`wrote`, `bytes`, `parse_errors`, `redactions`).
For sessions where investigation dead-ends matter, also extract errors:

```bash
python3 "$SR/scripts/extract-errors.py" --output "$SCRATCH/<id>.errors.txt" < <session-file>
```

### Step 6 — Dispatch the synthesis subagent

Dispatch a general-purpose `Agent` (model `sonnet` — synthesis needs no frontier
reasoning) whose prompt is **the full contract in `reference/historian-contract.md`,
pasted verbatim**, followed by `problem_topic`, `scratch_dir`, and the `sessions`
array (one entry per extracted session: `path`, optional `errors_path`, `platform`,
`branch`/`cwd`, `ts`/`last_ts`, `match_count`/`keyword_matches`). Pass the caller's
`output_schema` through verbatim when one was supplied. The subagent reads only the
scratch paths and returns prose — bulk content stays in its context, not the
orchestrator's.

### Step 7 — Return

Return the synthesizer's text verbatim. When no `output_schema` was supplied, prefix:

```
**Sessions searched**: [count] ([N] Claude Code, [N] Codex) | [date range]
```

If discovery or keyword filtering returned zero sessions, return the literal
`no relevant prior sessions`. Optionally `rm -rf "$SCRATCH"` (the OS cleans it up).

## Time budget

Stop as soon as a complete answer exists. A confident `no relevant prior sessions`
in seconds is complete — don't widen to fill time. The ≤5-session cap (Step 3) and
file-mediated extraction (Step 5) bound runtime by construction.

## Error handling

If discovery fails (unreadable dir, permissions), surface the error — do not
substitute `git log` or file listings; this skill's contract is session metadata +
synthesis. If an `--output` write fails, surface it and do not dispatch with partial
paths.
