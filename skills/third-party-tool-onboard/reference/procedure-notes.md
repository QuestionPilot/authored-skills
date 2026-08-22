# third-party-tool-onboard — provenance and depth

Reference depth for the skill body. Nothing here is load-bearing: every
must-fire rule lives inline in `SKILL.md` (skill-authoring §3).

## Provenance (trust-contract step 1)

The procedure is not synthesized — it is the transcript of runs that already
worked:

- **21st.dev CLI adoption, 2026-07-06 (QUE-377 session).** The full shape ran
  once end to end: source review → intake vet → manual placement of the skill
  bundles → overlay row + re-render → mirrors → vault guide + Capability Map →
  live smoke test. It is also the run that produced the standard's sharpest
  addendum: the vet *nearly did not fire*, because the policy lived in the vault
  and nothing at the harness layer surfaced it during an install-shaped task.
  The vet only ran because an unrelated guide mentioned it — and by then the
  files were already placed. This skill exists to make that recall automatic.
- **Operator toolkit workstream, 2026-06-21/22 (QUE-322).** The same shape at
  volume — roughly 13 tools onboarded in one arc, which is where the repeatable
  ordering (review → vault guide → install, never install-first) and the
  "install full functionality, no silent skips" rule were settled.
- **Earlier precedent, 2026-05-19.** kepano/obsidian-skills (5 skills) and a
  silver-platter data-mapping skill: reviewed in full, selectively installed,
  both modified before install, skips recorded with reasons. The origin of the
  standing "never install wholesale" policy.

Repeatability: three independent arcs, ~20 tools, same ordering, same failure
modes. That clears the provenance bar — a single lucky run would not.

## Risk tiers (distilled from the vault intake checklist)

The canonical taxonomy is
`10-Wiki/Concepts/Third-Party Skill Intake Checklist` (16 threat categories in
six groups A–F). Tier the depth to the risk:

| Tier | Trigger | Categories worked | Re-vet |
| --- | --- | --- | --- |
| **Quick** | pure prompt/markdown skill, no executable scripts | A provenance & maintenance, B prompt-layer integrity | on major rewrite |
| **Standard** | ships scripts, or requests tool/file access | A, B + C executable behavior, D data flow & exfiltration, E supply chain | on version bump |
| **Deep** | touches secrets / vault path / network, declares MCP, auth-adjacent, or high install-and-usage count | A–E + F MCP least-privilege & tool-poisoning; optional pinned SkillSpector Docker scan (advisory only) | **every update** |

Category shorthand:

- **A. Provenance & maintenance** — author reputation, activity vs age, license,
  squashed/mirror repo (audit opacity). Pin a commit or tag, never track `main`.
- **B. Prompt-layer integrity** — instruction-override phrasing, hidden text
  (zero-width chars, HTML comments, `data:` base64), over-broad triggers that
  shadow built-ins, "persist across sessions" / memory-rewrite directives.
- **C. Executable behavior** — for every script in every language:
  `exec`/`eval`, `subprocess`/`shell=True`, `sudo`, `curl … | bash`,
  obfuscation, runtime self-modification, cron/startup persistence. Note that
  AST-based scanners are Python-only; bash/PowerShell/JS is manual-read
  territory.
- **D. Data flow & exfiltration** — env vars, secrets, SSH keys, `.env`,
  filesystem enumeration, external webhooks, context transmission, high-impact
  actions with no human in the loop. Anything that could reach the vault path
  or credential files gets the closest read.
- **E. Supply chain** — unpinned deps, remote fetch at install, known CVEs
  (cross-check OSV.dev), typosquats, abandoned packages.
- **F. MCP-specific** — declared vs used capabilities, wildcard permissions,
  tool descriptions that do not match behavior.

**Findings ≠ verdict.** Gather evidence with `file:line` citations; a human (or
the model, explicitly) weighs them into SAFE / CAUTION / DECLINE with written
reasoning. No scanner score auto-decides — the scanners that do sum severities
and over-flag, and they are noisiest on exactly the two cases we hit most:
bash/PowerShell code, and skills whose *prose* is security-themed.

## Adopt-as-is vs modify vs build

- High quality + close fit + clean security → take as-is, description tweaks only.
- Good content, structural problems (too long, stale data, wrong paths) → modify
  before installing, and record every deviation.
- Poor fit or low quality → build our own; keep the third-party bundle as
  reference material only.

## Plugin-format bundles

A bundle shipped as a plugin (`.claude-plugin` / `.codex-plugin` / `.agents` +
a marketplace manifest) gets a narrower adopt: **install the `skills/<name>`
subtree only, drop the marketplace and any bundled lifecycle hook.** Two
reasons — the marketplace path targets `~/.claude` (the installer footgun), and
a bundled `SessionStart` hook adds a second lifecycle surface next to the
spine's own. Read the hook (it may be benign), then leave it out.

## Why the checker checks what it checks

`bin/check-onboard-state.sh` verifies END STATE, not process, because that is
where the observed failures landed: a placed skill that never got its overlay
row, mirrors that drifted from canonical, a tool with no vault guide, and
install-root records that disagreed with the filesystem. It complements the
vault's `bin/operator-skill-parity-check.sh` — that one sweeps *all* operator
skills for mirror drift across the catalog; this one proves *one* onboard is
complete across all six dimensions, including the ones parity never sees
(overlay row, vault guide, capability-map row, vendor residue).

Two deliberate design calls:

- **A missing mirror root is a FAIL, not a SKIP.** The parity script's own
  header records the bug where split roots silently "skipped" and the check
  printed PASS having compared nothing. Fail loud, never open.
- **The vendor-red-flag scan is restrained to bundled scripts, executable lines
  only.** A first cut over the real skill corpus flagged two legitimate prose
  mentions of `~/.cursor` (a shell comment and a port-notes table). Both are
  pinned as restraint fixtures in the test. The check biases to under-reporting
  so its WARNs stay worth reading, and WARN never fails the gate on its own.

## Trimmed depth (deliberately not in the body)

Not inlined, because it is either environment-cheap to look up or fires rarely:
per-tool install channels (read the tool's own README), the SkillSpector Docker
invocation (operator-local, advisory, documented in its vault guide), the exact
overlay row format (copy the shape of the adjacent rows), and the harness-index
regeneration internals (the vault's own scripts own that contract).
