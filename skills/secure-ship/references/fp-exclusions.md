# Secure-Ship FP-Exclusion List

A curated list of **known-safe patterns** to suppress scanner noise *before* triage (operating
procedure step 4), so the ship-gate stays high-signal. Borrowed in spirit from the gstack
`/cso` exclusion list, re-derived for this skill.

**Every exclusion is conditional.** Suppress a finding only when its stated condition is *verified*
true for the specific hit — an exclusion is a reason to look closer, not a blanket mute. When in
doubt, do **not** exclude: a surfaced false positive costs a minute; a suppressed true positive
ships a vuln. Never exclude a finding on a risk path (auth, secrets, payment, tenant boundary,
crypto) without reproducing why it is safe.

## Secrets / credentials

- **Documented placeholder secrets** — AWS's published `AKIA…EXAMPLE` example key (written here with
  an ellipsis so it does not itself read as a live key), `your-api-key-here`,
  `xxxx`/`<redacted>`/`changeme`, RFC example keys. Safe **only if** the value is non-functional
  (test it is rejected by the real service, or is the vendor's published example).
- **`.env.example` / `.env.sample` / `.env.template`** — exclude from **secret-value** detection
  only, and **only if** the file holds no real credentials and the real `.env` is gitignored. Still
  **review it for insecure defaults** (`DEBUG=true`, `JWT_SECRET=changeme`, default/weak creds,
  permissive CORS): sample files get copied into deploys and bootstrap scripts, so a weak default
  there is a real finding, not noise.
- **Test/fixture credentials** under `test/`, `tests/`, `__fixtures__/`, `spec/` — dummy tokens for
  unit tests. Safe **only if** the credential cannot authenticate against any real environment.
- **High-entropy strings that are not secrets** — content hashes, UUIDs, lockfile integrity hashes,
  base64 test data, git SHAs. Safe **only if** the string is not a credential for any system.

## Dependencies / SCA

- **Dev-only dependency CVEs** (`devDependencies`, build-time tools) — safe **only if** the package
  is not shipped to production AND has no build-time exploit path: not run on untrusted input in CI,
  and not reachable via a bundler/codegen/test-runner on attacker-controlled PR content. Build-time
  RCE in a dev dependency is still a real finding.
- **Unreachable-path CVEs** — a CVE in a transitive dep whose vulnerable function is never called.
  Safe **only if** reachability is actually confirmed (call-graph or manual trace), not assumed.
- **Lockfile-only advisories with no fix + no exploit path** — track, do not block, **only if**
  there is no reachable sink and the advisory is not in CISA KEV.

## Code / SAST

- **Generated build artifacts** — `dist/`, `build/`, minified bundles, protobuf/codegen output.
  Review the *source*, not the build output. Safe **only if** the artifact is reproducibly built from
  reviewed source. **Not** `vendor/` or `node_modules/` — vendored/third-party code is the source of
  record that actually ships; scan it via the dependency/SCA domain (§2), never blanket-exclude it.
- **Documentation / code-fence examples** — payload-shaped strings inside Markdown fences or doc
  comments illustrating an attack. Safe **only if** the string is illustrative, not executed.
- **Intentional patterns with an inline suppression** — a finding under an explicit, justified
  `# nosec` / `// lgtm` / lint-ignore with a written reason. Safe **only if** the justification is
  present and still valid.

## Network / config

- **`localhost` / `127.0.0.1` in dev or test config** — safe **only if** the binding is verified
  unreachable in *every* deployed environment (production **and** preview/staging/CI, which often
  inherit dev config). **`0.0.0.0` is not on this list** — binding all interfaces is itself a finding
  to review, not an exclusion.
- **Self-signed / test certificates** under test dirs — safe **only if** they are never loaded by a
  production trust store.
- **Permissive CORS / debug flags guarded by an environment check** — safe **only if** the guard is
  verified to be off in production (not just intended to be).

## How to apply

1. Run scanners (step 2). 2. For each raw finding, check this list. 3. If a pattern matches AND its
condition is verified true, drop it from the report (optionally note the count of suppressed hits so
the suppression itself is auditable). 4. Everything else proceeds to risk triage with a verification
state. Keep this list short and conditional — an exclusion list that grows into a blanket mute is how
real findings get lost.
