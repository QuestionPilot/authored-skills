# session-recall — maintainer port notes (never loaded at runtime)

Port of CE `ce-sessions` (EveryInc/compound-engineering-plugin, MIT) into a local
operator skill. Design conferred with Codex. This file is for
maintainers — the runtime path is SKILL.md + scripts/ only.

## Why a port, not an install

Installing CE would duplicate/conflict with `closeout`, `code-review`, `simplify`,
`frontend-taste` and add ~82 `ce-*` router entries. We mine the one genuinely-new capability:
cross-session recall via script-first architecture (scripts process; model presents).

## What changed vs CE source

| Area | CE original | Here | Why |
|---|---|---|---|
| Claude transcript path | hardcoded `$HOME/.claude/projects` | `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects` | operator config is relocated; `$HOME/.claude` is absent |
| Codex session roots | hardcoded `$HOME/.codex/sessions` (no `.agents`) | honor `$CODEX_HOME` / `$AGENTS_DIR` env, then the framework `local.env` (located via `$AI_CONFIG_DIR`, the parent of `$CLAUDE_CONFIG_DIR`, or the script's own render-home parent), then `~/.codex` + `~/.agents` defaults; roots deduped | operator co-locates `CODEX_HOME` at `<repo>/.codex` via `local.env`, so a `$HOME`-hardcoded scan silently returned zero Codex sessions and the skill wrongly reported "no relevant prior sessions" |
| Claude repo scoping | dir-name glob `*<repo>*` | scan ALL dirs; scope via `--cwd-filter` on the transcript `cwd` field | encoded dir names mangle spaces (`Space Dir` → `-...-Space-Dir`) so glob never matches |
| `--cwd-filter` semantics | substring; missing-`cwd` records pass | strict + path-component; missing-`cwd` records DROPPED | Codex anchor-100: scan-all amplifies the leak into cross-repo noise |
| metadata head scan | fixed first 25 lines | scan to 200 lines / 256 KB | resumed/compacted sessions open with queue-operation/attachment preamble |
| `--platform` arg-parse | `set -u` crash on bare `--platform`; dead `${4:-all}` | validated (`[ $# -ge 2 ]`); positional repo-name dropped | Codex anchor-100 |
| current-session exclusion | orchestration prose only (unimplemented in scripts) | `--exclude-active-min N` (drops files modified in last N min) + `--exclude PATH` | Codex anchor-100; recency-of-newest is unsafe under concurrent sessions |
| Cursor | discovered + parsed | not discovered; parser retained but inert; stripped from SKILL contract/counts | no `~/.cursor`; Cursor is out of scope here |
| redaction | none (presentation guardrails only) | narrow credential-shape scrub in skeleton + errors | Codex Q F defense-in-depth; deliberately narrow to preserve technical context |
| synthesis agent | named `ce-session-historian` | general-purpose `Agent` + `reference/historian-contract.md` inlined | no `agents/` registry here; keeps the load-bearing guardrails versioned |
| harness | Claude/Codex/Gemini/Pi orchestration branches | Claude Code only (Codex/Cursor are search *targets*, not runtimes) | this skill runs under Claude Code |

## Known limitations (documented, not bugs)

- **`cwd` = session launch directory, not "where work happened."** A session that
  started in a parent/monorepo dir, or `cd`'d into the repo mid-session, is scoped
  by its launch dir. CE had the same limitation via `gitBranch`-at-first-message.
  The keyword-filter fallback is the mitigation; don't claim repo-activity detection.
- **`--exclude-active-min` window.** Default 2 min. A session that ended <2 min ago
  is excluded as if live. Widen only if recall of just-finished work is needed.
- **BSD vs GNU `xargs` on empty input.** macOS BSD `xargs` does NOT run the command
  when stdin is empty (GNU runs it once). So on an empty discovery the
  `discover | xargs extract-metadata` pipeline emits nothing, while on GNU it emits
  a `files_processed: 0` line. SKILL.md treats BOTH as "no relevant prior sessions".
  extract-metadata's empty-stdin branch still matters for the GNU path + single-file use.

## Verification

- `tests/smoke-test.sh` — fixture-based; covers space-path Claude `cwd`,
  missing-`cwd` drop, Codex date-nesting, relocated `$CODEX_HOME` (space path),
  root dedup, `local.env` fallback, empty discovery, bad `--platform`,
  scan-past-preamble, strict cwd path-component match, redaction. Every
  discovery invocation must pin `CODEX_HOME`/`AGENTS_DIR` — the script honors
  them (and can find the real `local.env` on its own), so an unpinned run
  leaks the operator's live sessions into the fixture assertions.
- Live dogfood: run the skill against a known prior session + a keyword query.
- macOS bash 3.2 is the substrate; Python scripts are stdlib-only.

## Provenance

CE source re-cloned read-only to `/tmp` and `.claude/` stripped during the build;
that clone is removed at session close. Skill stays **local** — keep it private rather than sharing it widely, since it
reads your local session transcripts.
