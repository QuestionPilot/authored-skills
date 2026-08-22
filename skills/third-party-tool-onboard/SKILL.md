---
name: third-party-tool-onboard
description: >-
  Install and adopt a third-party CLI or SKILL.md bundle end to end — source
  review, intake vet, install, catalog row, mirror parity, vault guide, smoke
  test. Use when the user says "install this tool/CLI/skill", "onboard X", "add
  this skill from GitHub", "adopt this bundle", "set up <tool> for me", or hands
  over a repo/marketplace/plugin URL for anything that would land in a skills
  dir or on PATH. Also fires on re-vetting a tool after a version bump and on
  patching a vendored skill broken by a host-dependency upgrade.
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
  - WebFetch
  - AskUserQuestion
---

# third-party-tool-onboard

Adopt a new operator CLI or third-party skill without trusting the vendor's
installer. Proven on the 21st.dev CLI adoption and the ~13-tool toolkit
workstream — see `reference/procedure-notes.md` for provenance and the risk-tier
table.

`TT=<absolute path of the directory containing THIS SKILL.md>` in the commands
below, so they work from any harness's skill root.

## Invariants (these fire on every onboard)

- **Read the code before it touches disk.** Review the repo/bundle source first
  — every script, in every language — then vet, then install. Never the reverse.
- **Never run a vendor auto-installer** (`<tool> install-skill`, `init --all`,
  `curl … | sh`). They hardcode `~/.claude` / `~/.cursor`, fight relocated
  config dirs, and install unvetted bundles wholesale. Place files by hand.
- **Install FULL functionality, no silent skips.** Discuss before dropping any
  attribute of a tool. Only auto-skippable case: an MCP surface when an
  equivalent CLI exists (CLI over MCP — fewer tokens).
- **Never install launchagents, cron entries, lifecycle hooks, or new
  dotfolders without asking first.** Plugin-format bundles: take the
  `skills/<name>` subtree only; drop the marketplace manifest and its hooks.
- **Vet BEFORE placing**, and record the verdict in the tool's vault guide. For
  a body fetched from a live URL with no version tag, pin its content hash in
  that guide; re-vet on every bump for tools carrying a re-vet-on-bump policy.
- **Host-dependency upgrade broke a vendored skill?** Check upstream at BOTH
  the latest release and the default branch first (a fix on `main` means
  re-fetch, not patch). Reproduce RED, prove GREEN on the same repro, then
  patch **every root found by globbing the filesystem** — never from the
  install record, which drifts. Record the diff, a one-line re-apply command,
  the roots patched, and the new hash in the vault guide.

## Procedure

**0. File the issue.** Multi-step work goes into the tracker before execution,
with acceptance criteria naming the end state (installed + cataloged + mirrored
+ vault + smoke-tested). *Done when:* the issue exists and its AC list is the
checklist below, not a restatement of "install the tool".

**1. Review the source.** Clone or fetch to a scratch dir and read the actual
code that will run — every script, every language. Judge agent-fitness against
the 7-point agent-CLI rubric in `skills/skill-authoring.md` §9 (non-interactive,
`--json`, progressive `--help`, actionable failures, safe retries, composable
shape, bounded output); a tool failing several is a wrap-or-decline candidate,
not an automatic install. *Done when:* every executable file in the bundle has
been read, and the fitness call is written down with reasons.

**2. Intake vet (judgment — yours).** Work the evidence taxonomy in the vault
note `10-Wiki/Concepts/Third-Party Skill Intake Checklist`, tiered by risk:

| Tier | When | Depth |
| --- | --- | --- |
| Quick | pure prompt/markdown, no scripts | provenance + prompt-layer integrity |
| Standard | ships scripts, or requests tool/file access | + executable behavior, data flow, supply chain |
| Deep | touches secrets/vault/network, declares MCP, auth-adjacent, or high install count | all of the above + MCP category, and **re-vet on every update** |

Findings are evidence, not a verdict: weigh them holistically to **SAFE /
CAUTION (with named constraints) / DECLINE**, and write the reasoning down. No
scanner score decides. Record what you skipped and why. *Done when:* every
applicable category has a `file:line` finding or an explicit "no signal", and a
verdict with reasoning is drafted for the vault guide.

**3. Install.** CLI → the operator's normal global channel (`brew`, `npm` on the
right prefix, `uv tool`). Skill bundle → copy the reviewed files **verbatim**
into the canonical skills root by hand:

```bash
cp -R "<vetted-source>/<name>" "/Users/hendohome/Agentic OS/.claude/skills/<name>"
```

Modify only where step 2 said to (trim, fix stale paths, scope the trigger) —
and record each deviation. *Done when:* the files are placed and the placement
command is reproducible from the vault guide.

**4. Catalog.** Add the row to the operator overlay — never the rendered
`SKILLS.md`:

```bash
$EDITOR "/Users/hendohome/Agentic OS/local.skills-overlay.md"   # name | trigger | use when
cd "/Users/hendohome/Agentic OS" && bash scripts/install.sh --harness claude --harness codex
bash scripts/check-drift.sh --auto
```

*Done when:* the overlay row exists, the re-render finished, and `check-drift.sh
--auto` PASSES.

**5. Mirror.** Copy the placed skill, content-identical, to every operator skill
root — canonical `.claude/skills/`, mirrors `.codex/skills/`, `.agents/skills/`,
`~/.cursor/skills/`. Hermes is deliberately out of scope. *Done when:* the vault
gate `bash "$OBSIDIAN_VAULT_PATH/bin/operator-skill-parity-check.sh"` PASSES.

**6. Vault.** Write or update the tool's guide in `10-Wiki/Entities/` (what it
is, install command, auth, the vet verdict + tier, version/hash anchor, any
deviation from upstream), add the Capability Map row in `90-Indexes/`, then from
the vault root:

```bash
node bin/generate-harness-index.js && node bin/hendo-vault-audit.js
```

*Done when:* the guide carries the vet verdict, the map row names the tool, and
the audit is green.

**7. Smoke test.** Invoke the tool for real — the cheapest call that proves the
installed thing works end to end (`--version` is not a smoke test; a free
read/search subcommand usually is). Avoid burning metered credits: prefer the
tool's free surface, and ask before any paid call. *Done when:* a real
invocation produced correct output, quoted in the issue.

**8. Final gate.** Run the bundled end-state checker:

```bash
bash "$TT/bin/check-onboard-state.sh" <name>                 # skill onboard
bash "$TT/bin/check-onboard-state.sh" <name> --cli <binary>  # CLI-only onboard
```

It prints one `PASS|FAIL|WARN|SKIP` line per check (placement, mirror parity per
root, overlay row, vendor red flags, vault guide, capability-map row) and exits
0 only when everything applicable passed. `--guide-name <substr>` when the vault
guide is titled differently; `--vault/--canonical/--mirrors/--overlay` override
paths. **WARN does not fail the gate** — read each flagged line before calling
the onboard done. *Done when:* the checker exits 0 and every WARN is explained
in the issue or the vault guide. A red gate is a stop, not a note.

## When it stops

Any of these halts the onboard and goes back to the user: a DECLINE verdict; a
vendor bundle that only installs through its own installer; a tool needing a
launchagent/cron/hook; a mirror root you cannot write; a smoke test that would
cost real money. Report the blocker; do not route around it.
