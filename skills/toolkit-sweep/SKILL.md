---
name: toolkit-sweep
description: >-
  Manual-fire toolkit update + re-vet sweep across the installed third-party
  toolkit — the operator skills roots, operator bin dir, brew/npm globals, and
  the vault Capability Map roster: installed version vs current source,
  harmless smoke, instruction-file drift, re-vet-needed verdict per tool.
  Tools outside those surfaces are out of the sweep's deterministic reach and
  are reported as such, not silently covered. Use when the user says "sweep the toolkit", "are my tools stale",
  "toolkit health check", "re-vet sweep", or after a long gap between sessions.
  NOT for checking ONE tool at point of use — that is the per-tool
  tool-freshness gate; NOT for installing/onboarding a new tool — that is
  third-party-tool-onboard. Never scheduled, never auto-updates.
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
  - WebFetch
---

# toolkit-sweep

One operator-invoked ritual that walks the whole installed toolkit and reports,
per tool: version state, smoke result, instruction drift, and whether a re-vet
is owed. `TS=<absolute path of the directory containing THIS SKILL.md>`.

## Invariants

- **Manual-fire only.** Never install a scheduler, daemon, cron entry, or
  launchagent to run this — that violates the standing consent rules. If asked
  to automate it, decline and point at this clause.
- **Read-only sweep.** The sweep itself never updates, reinstalls, or deletes
  anything. Every fix is a proposal for the operator; an approved update to a
  tool with a re-vet-on-bump policy routes through `third-party-tool-onboard`.
- **Honest nulls.** A tool whose probe did not run, timed out, or would cost
  money is reported **UNPROBED — never clean**. The report states its
  denominator (tools enumerated vs tools probed).
- **Metered surfaces:** smoke via the tool's free surface only; ask before any
  call that burns credits, and mark the tool UNPROBED(cost) if declined.

## Procedure

**1. Collect installed state (deterministic).**

```bash
mkdir -p "$HOME/toolkit-sweep-out" \
  && bash "$TS/bin/collect-toolkit-state.sh" > "$HOME/toolkit-sweep-out/$(date -u +%Y-%m-%dT%H%M)-state.md"
```

The collector enumerates the canonical skills root, runs the mirror-parity
gate, probes every `~/.local/bin` executable with a bounded `--version`, and
captures `brew outdated` + `npm -g outdated`. Output lands OUTSIDE any repo.
*Done when:* the state file exists and its probe summary line is read — every
UNPROBED row is carried forward, not dropped.

**2. Build the tool roster (judgment).** Open the vault Capability Map
(`90-Indexes/Capability Map`) and reconcile it against step 1's enumeration
both ways: a Map row with no installed artifact, and an installed CLI/skill
with no Map row, are both findings. Third-party skills in the skills root
(vendored bundles, marketplace installs) join the roster; spine/native and
locally-authored skills are out of scope (they have their own gates). *Done
when:* every roster entry names its source of truth (vault Entities guide,
GitHub repo, npm/brew package) or is marked SOURCE-UNKNOWN.

**3. Per-tool freshness (judgment, bounded).** For each roster tool, apply
`verification/tool-freshness.md`: compare installed version against current
source (`gh api repos/<o>/<r>/releases/latest`, `npm view <pkg> version`,
`brew info`), run the cheapest real smoke (a free read/search subcommand —
`--version` alone is not a smoke), and check the tool's vault guide for stale
version claims. For a vendored/patched skill, re-hash the installed body and
compare against the hash recorded in its guide. *Done when:* each roster tool
has all four cells filled or an explicit UNPROBED with a reason.

**4. Re-vet verdicts.** A tool is **RE-VET** when its version changed since
the last vet AND its guide records a re-vet-on-bump policy (Deep-tier vets
always do); **PATCH-CHECK** when a recorded hash no longer matches; otherwise
OK / STALE / UNPROBED. Re-vets execute later via `third-party-tool-onboard`,
one tool at a time — never inside the sweep. *Done when:* every tool carries
exactly one verdict.

**5. Report.** One table — `tool | installed | current | smoke | drift |
verdict` — plus the denominator line ("N enumerated, M probed, K UNPROBED")
and a proposed-actions list for the operator. Nothing executes without the
operator picking it. *Done when:* the report is delivered and the state file
path is named in it.

## Escape hatches

- A tool's source is unreachable (rate limit, VPN blocking the registry):
  mark UNPROBED(source-unreachable) and move on — never guess a version.
- The sweep grows past ~20 tools: batch by risk tier (Deep-vet tools first),
  and say which tiers were deferred rather than silently truncating.
