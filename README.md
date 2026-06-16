# Authored Claude Code Skills

A portable, restorable backup of locally-authored [Claude Code](https://docs.claude.com/en/docs/claude-code) skills. Each skill is self-contained: drop its folder into your skills directory and it works, with no machine-specific paths baked in.

## Skills

| Skill | What it does |
|---|---|
| **cross-model-review** | Routes "check / review / audit my work" to a different model family so the author never reviews its own output — two equal critics, GPT (via the Codex CLI) and Gemini (via the agy CLI); a single critic for code review, panel→judge→synthesis for open-ended consensus. Includes an outbound credential-scan gate before any external pipe. |
| **secure-ship** | Pre-deploy secure-development review of your own changes across 9 domains (SAST, deps, secrets, CI/CD, containers, IaC, API/web, crypto, threat modeling); emits a ship / fix-first / no-ship gate. |
| **frontend-taste** | Designs and iterates production-grade frontend interfaces — command system, register model, anti-slop mechanics, live browser iteration. A consolidation of upstream work; see [`skills/frontend-taste/NOTICE.md`](skills/frontend-taste/NOTICE.md). |
| **safety-scoping** | Session guardrails: `careful` (warn before destructive shell), `freeze` (restrict edits to a directory), `guard` (both). State-gated PreToolUse hooks. |
| **session-recall** | Searches prior coding-agent sessions (Claude Code + Codex) to answer "what was tried / decided before" — script-first, never loads raw transcripts into context. |
| **plan-pressure-test** | Pressure-tests a product idea / feature / plan before build effort: six forcing questions (demand-reality, status-quo, desperate-specificity, narrowest-wedge, observation, future-fit) → one of four scope modes; surfaces only genuine taste decisions to the operator. Adapts gstack's interrogation structure; see [`NOTICE.md`](NOTICE.md). |

## Restore

```bash
git clone <this-repo-url> authored-skills
cp -R authored-skills/skills/* "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/"
```

Then per skill:

- **safety-scoping** needs its two always-on hooks registered once in `settings.json` — see [`skills/safety-scoping/reference/install-hooks.md`](skills/safety-scoping/reference/install-hooks.md) for the idempotent `jq`-merge installer.
- **cross-model-review** expects the `codex` (GPT) and `agy` (Gemini) CLIs on `PATH` — two equal critic lanes; its run-output directory is configurable via `CROSS_MODEL_OUT_DIR`.
- **frontend-taste** scripts run under `node`; some commands use `npx`.
- **session-recall** scripts are Python 3 stdlib-only and bash 3.2 compatible.

## Provenance & licensing

- **frontend-taste** consolidates Anthropic's `frontend-design` skill (Apache-2.0), the `impeccable` skill (Apache-2.0), and `taste-skill` (MIT). Full attribution + license texts ship alongside it: [`NOTICE.md`](skills/frontend-taste/NOTICE.md), [`LICENSE-APACHE-2.0`](skills/frontend-taste/LICENSE-APACHE-2.0), [`LICENSE-MIT`](skills/frontend-taste/LICENSE-MIT).
- **session-recall** ports, and **cross-model-review** adapts the review rubric from, the MIT-licensed `compound-engineering-plugin` (© 2025 Every); **safety-scoping** adapts a guardrail pattern from `gstack` (MIT, © 2026 Garry Tan). Full attribution and license texts are in [`NOTICE.md`](NOTICE.md).

## Note on test fixtures

`session-recall` ships synthetic session fixtures under `skills/session-recall/tests/fixtures/` that include a deliberately-fake credential string (`sk-ant-FAKE…`). It is not a real key — the smoke test asserts that the redaction logic scrubs it.
