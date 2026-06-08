---
name: secure-ship
description: >-
  Pre-deploy secure-development review of YOUR OWN changes before they merge or ship. Walks a 9-domain methodology (SAST/secure code review, dependency & supply-chain integrity, secrets, CI/CD pipeline, container/image, IaC & cloud config, API & web-app security, crypto & key management, threat modeling), runs the matching OSS scanners, applies a risk-rated checklist, and emits a ship / fix-first / no-ship gate. Triggers: "is this safe to ship", "security review before merge/deploy", "secure code review", "check my changes for vulnerabilities", "did I leak a secret / misconfigure IAM / harden this container / validate this JWT", before shipping changes that touch auth, APIs, dependencies, secrets, crypto, containers, IaC, or cloud config. NOT for incident response, threat hunting, forensics, or offensive/pentest work.
allowed-tools: Read, Grep, Glob, Bash, WebFetch
---

# Secure-Ship — Pre-Deploy Secure-Development Review

A checklist-and-tooling methodology for reviewing **your own code/config before it ships**.
It answers one question: *is this change safe to merge and deploy?* It does **not** operate a
SOC, hunt threats, do forensics, or attack third parties.

Use it as a gate on risk-path changes: auth/authz, APIs, dependency bumps, secrets handling,
crypto, container images, IaC, and cloud config. It complements — does not replace — the
built-in `security-review` skill and the `cross-model-review` forced-adversarial lane; run
`secure-ship` for breadth-of-coverage, then escalate genuinely risky diffs to adversarial review.

## When to use vs. when not to

- **Use** before opening a PR or deploying, when the diff touches any of the 9 domains below;
  when asked "is this secure / safe to ship"; when you added a dependency, a secret path, an
  endpoint, an IAM policy, a Dockerfile, or crypto.
- **Don't use** for runtime incident response, log/threat hunting, malware analysis, or
  red-team/offensive tasks — that is a different domain and out of scope here.

## Operating procedure

1. **Scope the change.** `git diff --stat` (or read the change set). Map touched files to the
   domains in the router below — but the router is a *starting point*, not the boundary. Route by
   **behavior and data flow**, not just touched paths: a one-line change to an API handler, an
   authz check, a tenant boundary, a secret, or an outbound call pulls in §7/§8/§9 even if no
   "matching" file was edited. Expand scope whenever the change affects auth, multi-tenant
   isolation, secrets, external calls, logging of sensitive data, or privilege.
2. **Run the automated scanners** for the matched domains (see
   [tooling-and-mappings.md](references/tooling-and-mappings.md)). Prefer fast OSS tools already
   on PATH; never install via `curl|bash` mid-review (see Tooling notes). Capture findings. For the
   **secrets** domain, scan history **including deleted code** — `gitleaks detect --log-opts=--all`,
   or without gitleaks a `git log -p -S'<pattern>'` archaeology pass — because a secret removed from
   the working tree still lives in history and needs *rotation*, not just deletion.
3. **Walk the manual checklist** for each matched domain in
   [review-checklists.md](references/review-checklists.md). Automated scanners miss
   business-logic and authorization flaws — the checklist is where BOLA/IDOR, broken authz,
   and design issues get caught.
4. **Triage by risk.** First suppress known-noise with the **FP-exclusion list**
   ([fp-exclusions.md](references/fp-exclusions.md)) so the gate stays high-signal — but each
   exclusion is conditional, so confirm the condition holds (e.g. a placeholder secret really is
   non-functional) before suppressing. Then rate each surviving finding by OWASP Risk Rating
   (Likelihood × Impact) and dedupe by `title+file+line`. Tag each with a **verification state** —
   `confirmed` (reproduced, or a concrete exploit path traced), `suspected` (pattern matched, not yet
   reproduced), or `informational` — and never report a bare scanner hit as `confirmed`. Manually
   confirm injection/authz findings before reporting; cross-check CVEs against CISA KEV + EPSS for
   real-world exploitability.
5. **Emit the ship gate** (format below). Be honest: if a Critical/High is unmitigated, the
   verdict is **NO-SHIP**, not "ship with a note."

## Domain router — match the change to its checklist

| If the change touches… | Domain | Checklist section |
|---|---|---|
| App/source code, headers, error handling | SAST & secure code review | §1 |
| `package.json`/`requirements.txt`/`go.mod`/lockfiles, SBOM, image provenance | Dependency / supply-chain | §2 |
| `.env`, config, anything credential-shaped, git history | Secrets management | §3 |
| `.github/workflows/`, `.gitlab-ci.yml`, pipeline config | CI/CD pipeline security | §4 |
| `Dockerfile`, image build, registry, base images | Container & image security | §5 |
| `*.tf`, CloudFormation, Helm, K8s manifests, IAM policy | IaC & cloud-config security | §6 |
| REST/GraphQL/WebSocket endpoints, authz, JWT, OAuth, CORS | API & web-app security | §7 |
| Encryption, hashing, signing, key handling, TLS config | Crypto & key management | §8 |
| New feature/service, new trust boundary, new data flow | Threat modeling | §9 |

## Ship-gate output format

End every review with this block:

```
## Secure-Ship Gate: <SHIP | FIX-FIRST | NO-SHIP>

Scope: <domains reviewed> | Evidence: <scanners run + result, or "NONE — incomplete">
Findings: <n Critical / n High / n Medium / n Low>
Trend vs last run: <n new / n fixed / n regressed — or "first run">

- [CRITICAL] <title> — <file:line> — <confirmed|suspected|informational> — <exploit scenario / impact> → <fix>
- [HIGH]     ...
- [MEDIUM]   ...

Accepted risk: <each as: finding · owner · compensating control · expiry · tracking link  — or "none">
Verdict rationale: <one sentence>
```

Each finding carries its **verification state** (from step 4) and a concrete one-line exploit
scenario, not just a category — `suspected` findings still surface but are labelled so the reader
knows what is reproduced vs pattern-matched. For **trend tracking**, persist each run's findings (a
dated artifact, e.g. `secure-ship-<YYYY-MM-DD>.md` under the review-output dir) and diff against the
previous run for the same scope: report new / fixed / regressed counts so the gate shows direction
over time, not just a point-in-time snapshot. A regressed (reintroduced) finding is a stronger
signal than a first-time one.

Gate rules:
- Any **unmitigated Critical or High → NO-SHIP.**
- **Incomplete evidence → at least FIX-FIRST (NO-SHIP if the gap covers a risk path).** A required
  scanner that failed/was missing/ran unauthenticated, a matched domain left unreviewed, or an
  unreachable staging target is *not* a pass — "Evidence: none" never yields SHIP.
- Medium → FIX-FIRST unless explicitly risk-accepted; a risk acceptance is only valid with **owner +
  compensating control + expiry + tracking link** (a bare "accepted" is not).
- Low → ship, track as follow-up.

## References

- [review-checklists.md](references/review-checklists.md) — the 9-domain checklists + pitfalls (the core content).
- [tooling-and-mappings.md](references/tooling-and-mappings.md) — OSS scanner matrix per domain, install-hardening notes, and NIST CSF / OWASP / MITRE control mappings.
- [fp-exclusions.md](references/fp-exclusions.md) — curated, *conditional* known-safe patterns to suppress scanner noise before triage (step 4) — each with the condition under which it is safe to exclude.

## Provenance & security note

The domain checklists were **distilled** (knowledge only — no third-party code vendored) from the
community catalog `mukul975/Anthropic-Cybersecurity-Skills` (Apache-2.0; *not* an Anthropic
project), filtered to the 54 defensive secure-development skills out of 754 and de-duplicated.
Every source script drawn from was spot-checked: all were defensive (argv-list subprocess, no
`curl|bash`, no remote `eval`/`exec`, no exfiltration, no C2). Offensive payload snippets present
in the source were re-encoded here as **prevention/detection checks**, never copy-paste exploits.
Keep this skill knowledge-only; if you later add an orchestrator script, it must run only
already-installed tools with no network installs.
