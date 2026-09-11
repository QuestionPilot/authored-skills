# Authored Claude Code Skills

A portable, restorable backup of locally-authored [Claude Code](https://docs.claude.com/en/docs/claude-code) skills. Each skill is self-contained: drop its folder into your skills directory and it works. Machine-specific locations are expressed as environment variables (`$AI_CONFIG_DIR`, `$CLAUDE_CONFIG_DIR`, `$OBSIDIAN_VAULT_PATH`, …) or `<placeholders>`, never as literal paths.

## Skills

| Skill | What it does |
|---|---|
| **cross-model-review** | Routes "check / review / audit my work" to a different model family so the author never reviews its own output — three equal critics, GPT (via the Codex CLI), Gemini (via the agy CLI), and GLM (via the ollama CLI / Ollama Cloud); a single critic for code review, panel→judge→synthesis for open-ended consensus. Includes an outbound credential-scan gate before any external pipe. |
| **secure-ship** | Pre-deploy secure-development review of your own changes across 9 domains (SAST, deps, secrets, CI/CD, containers, IaC, API/web, crypto, threat modeling); emits a ship / fix-first / no-ship gate. |
| **frontend-taste** | Designs and iterates production-grade frontend interfaces — command system, register model, anti-slop mechanics, live browser iteration. A consolidation of upstream work; see [`skills/frontend-taste/NOTICE.md`](skills/frontend-taste/NOTICE.md). |
| **safety-scoping** | Session guardrails: `careful` (warn before destructive shell), `freeze` (restrict edits to a directory), `guard` (both). State-gated PreToolUse hooks. |
| **session-recall** | Searches prior coding-agent sessions (Claude Code + Codex) to answer "what was tried / decided before" — script-first, never loads raw transcripts into context. |
| **plan-pressure-test** | Pressure-tests a product idea / feature / plan before build effort: six forcing questions (demand-reality, status-quo, desperate-specificity, narrowest-wedge, observation, future-fit) → one of four scope modes; surfaces only genuine taste decisions to the operator. Adapts gstack's interrogation structure; see [`NOTICE.md`](NOTICE.md). |
| **video-ingest** | Ingests a video (usually YouTube) into an Obsidian-format vault as durable knowledge — clean timestamped transcript bundle, distilled review note, and receipts-backed improvement recommendations gated by a mandatory cross-model panel. Orchestrates the `watch` skill as its video engine; idempotent per canonical video id across URL variants. |
| **codebase-memory** | Queries a persistent local code knowledge graph via the `codebase-memory-mcp` CLI (no MCP server registered — token-light): call graphs, "what calls X", impact tracing, structural search, openCypher queries over indexed repos. |
| **framework-ship** | Ships one change to the public framework repo end-to-end as a git-workflow state machine — throwaway clone, branch, fix, clean-clone verify, cross-model panel, pinned noreply identity, `check-clean`, push, PR, CI, squash-merge, living-folder fast-forward, drift check. Ships a `check-ship-gates.sh` gate runner with fixtures. |
| **third-party-tool-onboard** | Installs and adopts a third-party CLI or SKILL.md bundle end to end — source review, intake vet, install, catalog row, mirror parity, vault guide, smoke test. Ships `check-onboard-state.sh` to verify the end state deterministically. |
| **toolkit-sweep** | Manual-fire update + re-vet sweep across the installed third-party toolkit (skills roots, operator bin dir, brew/npm globals, vault Capability Map): installed vs current version, harmless smoke, instruction-file drift, per-tool re-vet verdict. Read-only; never auto-updates. |
| **edgar-receipts** | Verifies that a company-name string names a specific organization using SEC EDGAR filings as machine-replayable receipts: full-text search → newest self-filing → Unicode-word-boundary phrase replay + sha256 → grade (`self_filing` / `third_party_context` / `third_party_name_only` / `phrase_not_found` / `no_hit`) → ledger + actions slate. Only self-filings and context-bearing third-party sentences are accepted; namesakes and name-only mentions are held. |

## Restore

```bash
git clone <this-repo-url> authored-skills
cp -R authored-skills/skills/* "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/"
```

Then per skill:

- **safety-scoping** needs its two always-on hooks registered once in `settings.json` — see [`skills/safety-scoping/reference/install-hooks.md`](skills/safety-scoping/reference/install-hooks.md) for the idempotent `jq`-merge installer.
- **cross-model-review** expects the `codex` (GPT), `agy` (Gemini), and `ollama` (GLM via Ollama Cloud) CLIs on `PATH` — three equal critic lanes that degrade gracefully to whichever are installed; its run-output directory is configurable via `CROSS_MODEL_OUT_DIR`.
- **frontend-taste** scripts run under `node`; some commands use `npx`.
- **session-recall** scripts are Python 3 stdlib-only and bash 3.2 compatible.
- **video-ingest** depends on the third-party `watch` skill (bradautomates/claude-video — install and vet it separately; it is not authored here and not bundled) plus `yt-dlp` and `ffmpeg` on `PATH`, and writes into an Obsidian-format vault (folder conventions documented in the SKILL.md).
- **codebase-memory** expects the `codebase-memory-mcp` binary on `PATH`; bound indexing with `CBM_ALLOWED_ROOT` (least privilege) and index each repo once before querying.
- **framework-ship**, **third-party-tool-onboard** and **toolkit-sweep** are operator-workflow skills for a machine running the [agentic-os-template](https://github.com/QuestionPilot/agentic-os-template) framework; they read `AI_CONFIG_DIR` (framework checkout) and `OBSIDIAN_VAULT_PATH` (vault root) from the environment or the framework's `local.env`. Their gate scripts are bash 3.2 compatible and ship with fixture tests.
- **video-ingest** raw-bundle tags use the `VIDEO_INGEST_TAG_PREFIX` namespace (default `vault`).
- **edgar-receipts** is Python 3 stdlib-only; set `EDGAR_UA` to a descriptive User-Agent with a contact (SEC fair-access policy) — the script refuses to fetch without it. Receipts come from `sec.gov` only by design.

## Provenance & licensing

- **frontend-taste** consolidates Anthropic's `frontend-design` skill (Apache-2.0), the `impeccable` skill (Apache-2.0), and `taste-skill` (MIT). Full attribution + license texts ship alongside it: [`NOTICE.md`](skills/frontend-taste/NOTICE.md), [`LICENSE-APACHE-2.0`](skills/frontend-taste/LICENSE-APACHE-2.0), [`LICENSE-MIT`](skills/frontend-taste/LICENSE-MIT).
- **session-recall** ports, and **cross-model-review** adapts the review rubric from, the MIT-licensed `compound-engineering-plugin` (© 2025 Every); **safety-scoping** adapts a guardrail pattern from `gstack` (MIT, © 2026 Garry Tan). Full attribution and license texts are in [`NOTICE.md`](NOTICE.md).

## Note on test fixtures

`session-recall` ships synthetic session fixtures under `skills/session-recall/tests/fixtures/` that include a deliberately-fake credential string (`sk-ant-FAKE…`). It is not a real key — the smoke test asserts that the redaction logic scrubs it.
