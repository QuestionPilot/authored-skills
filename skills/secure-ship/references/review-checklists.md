# Secure-Ship Review Checklists

Nine domains. Walk only the sections matched by the change (see the router in `SKILL.md`).
Each section: **Checks** (verify in your own code/config) and **Pitfalls** (what reviewers miss).
Tooling and control-ID mappings live in `tooling-and-mappings.md`.

---

## §1 — SAST & secure code review

### Checks
- Run Semgrep (`--config auto` + `p/owasp-top-ten`, `p/cwe-top-25`) and/or CodeQL
  (`security-extended`) on the diff; emit SARIF; gate on ERROR/Critical/High.
- For custom rules: YAML with `metavariable-regex`, `pattern-not` exclusions, and `mode: taint`
  (sources/sinks/sanitizers) for SQLi/XSS/SSRF dataflow; tag with `cwe`/`owasp`; validate via
  `semgrep --test` using `# ruleid:` / `# ok:` annotations.
- Flag deprecated crypto in source: MD5/SHA-1, DES/3DES/RC4/Blowfish, ECB mode, RSA <2048,
  **RSA PKCS#1 v1.5 *encryption*/key-transport** (Bleichenbacher — use OAEP), non-CS RNG
  (`random.random`, `Math.random`). Note: RSASSA-PKCS1-v1_5 *signatures* (`RS256`) are legacy but
  still standards-acceptable at ≥2048-bit — prefer PSS (`PS256`) for new work, don't hard-block.
  (Deep-dive in §8.)
- Detect hardcoded keys/secrets/tokens in source and serverless env vars; require a secrets
  manager / env-var loading instead. (Deep-dive in §3.)
- Flag disabled TLS verification (`verify=False`, `CERT_NONE`) and deprecated protocols
  (SSLv3, TLS 1.0/1.1).
- Audit unsafe deserialization (`pickle.loads`, `yaml.load` with unsafe Loader) and JWT misuse
  (`alg=none`, `verify_signature: False`).
- Serverless review: enumerate functions; flag wildcard/admin execution roles, unauthenticated
  Function URLs / `ALLOW_ALL` ingress, deprecated runtimes; scan code with Bandit/ESLint-SDL.
- HTTP security headers: HSTS (roll out staged — start with a low `max-age`, inventory subdomains,
  then add `includeSubDomains`/`preload` only after validation; `preload` is hard to reverse and can
  brick subdomains), CSP (flag `unsafe-inline`/`unsafe-eval`/wildcards; prefer nonce/hash),
  `X-Frame-Options: DENY` or CSP `frame-ancestors`, `X-Content-Type-Options: nosniff`,
  `Referrer-Policy`, `Permissions-Policy`. (Stripping `Server`/`X-Powered-By` is Low/informational —
  never gate ship on it unless it leaks a precise vulnerable version.)
- Cookies: `Secure` + `HttpOnly` + `SameSite`; `__Host-`/`__Secure-` prefixes; `Cache-Control:
  no-store` on sensitive responses.
- **Sensitive-data-in-logs (cross-cutting):** confirm secrets, tokens, JWTs, `Authorization`
  headers, passwords, PII, and payment/card data are **never** written to logs, traces, error
  messages, or analytics. Require redaction/masking in the logging layer; check new log/print/error
  statements added by the diff; verify error responses don't echo internals (stack traces, SQL).
- Triage via OWASP Risk Rating; dedupe by title+file+param; map CWE→OWASP Top 10; manually
  validate injection findings before filing.

### Pitfalls
- Over-suppressing rules to cut noise → blind spots. Validate suppressions against OWASP Top 10 /
  CWE Top 25; target FP rate <15%.
- Running CodeQL on all languages every PR balloons CI — use path filters.
- Header/cookie "missing" findings are often informational — context-rate, don't auto-critical.
- Tightening a serverless execution role can break the function — test in staging first.

---

## §2 — Dependency / SCA / supply-chain integrity

### Checks
- Scan manifests + lockfiles (`package.json`, `requirements.txt`, `pom.xml`, `go.mod`, `Gemfile`)
  for known-vulnerable deps. **Gate on unmitigated Critical/High regardless of whether a fix
  exists** — do NOT use Snyk's `--fail-on=upgradable` as the gate (it silently passes a Critical
  with no patched version, exactly the case you most need to catch). A no-fix-available Critical
  becomes a tracked exception (reachability analysis + compensating control + owner + expiry), not
  an auto-pass.
- Trace **transitive** dependency paths — a CVE 4 levels down is still in scope. Check exploit
  maturity (Mature/PoC) and CISA KEV before triage.
- Parse SBOMs (CycloneDX ≥1.4, SPDX ≥2.3); correlate components to NVD CVEs by CPE/PURL;
  risk-rank by blast radius (in-degree), shortest-path-to-root, betweenness centrality.
- Verify image provenance: signature + Fulcio cert + Rekor transparency-log inclusion; sign and
  verify by **digest, not tag**; enforce at admission (Sigstore policy-controller / Kyverno
  `verifyImages`).
- Verify build integrity with in-toto: all required steps ran, each signed by an authorized
  functionary, artifact hashes chain across steps; map to SLSA levels.
- Audit CI/CD config for supply-chain vectors: unpinned actions (`@main` vs `@sha`), script
  injection via `${{ github.event.* }}`, over-permissive `GITHUB_TOKEN`, dependency confusion
  (public/private name collision). (Deep-dive in §4.)
- License compliance: flag copyleft (GPL-3.0, AGPL-3.0) against an approved-license policy.

### Pitfalls
- Dismissing transitive CVEs as "we don't call that function" — attackers chain across boundaries;
  version overrides can break API compat.
- Vendor SBOMs are often incomplete (shaded/bundled JARs hide log4j); CPE names may not match NVD
  exactly (needs fuzzy matching); NVD rate-limits (5 req/30s without an API key).
- Signing by mutable tag instead of digest; verifying a signature without checking cert identity
  **and** Rekor inclusion.

---

## §3 — Secrets management & secret scanning

### Checks
- Scan the **full git history** (not just the working tree) for committed secrets; gate CI with
  `--exit-code 1` and a baseline so only *new* findings block.
- Pre-commit gate (`gitleaks protect --staged`) to stop secrets before they enter history.
- Author org-specific rules (internal tokens, DB connection strings, JWT secrets) with entropy
  thresholds + keyword anchors; allowlist test/fixture/vendor paths and placeholder regexes.
- On detection, in order: **(1) rotate/revoke** the credential at the provider, **(2)** scrub
  history with `git-filter-repo`, **(3)** force-push with team coordination. Rotation BEFORE
  history rewrite — never assume a historical secret is inactive.
- Vault hardening: AppRole `secret_id_num_uses=0` (unlimited) is a finding; root credential
  rotated post-setup; audit logging on all nodes; dynamic-secret TTLs < 24h; flag KV secrets
  unused 90+ days.

### Pitfalls
- Baselining without triage = silently accepting risk on unrotated secrets.
- `git-filter-repo` on a shared repo without coordination breaks everyone's history.
- Vault: not rotating original static creds after migration leaves them valid; TTLs too short
  expire creds mid-deploy; missing revocation statements orphan DB users; non-HA Vault = single
  point of failure for all auth.

---

## §4 — CI/CD pipeline security

### Checks
- Pin every third-party action to a full 40-char commit SHA (`^[a-f0-9]{40}$`), not a mutable tag.
  Add Dependabot (`package-ecosystem: "github-actions"`) so pinned SHAs still get updates.
- Default `GITHUB_TOKEN` to `permissions: {}` at workflow level; grant the minimum per job
  (`contents: read`; `id-token: write` only where OIDC is used). Flag any workflow with no explicit
  `permissions` block or `write-all`.
- Use OIDC federation instead of long-lived cloud secrets stored in repo/org settings.
- Prevent script injection: never interpolate untrusted input (`github.event.pull_request.title/
  body`, branch names, commit messages) directly into `run:`. Pass via `env:` and reference
  `"${VAR}"`, or use `actions/github-script` with `context.payload`.
- Avoid `pull_request_target`; if unavoidable, gate on a trusted label and **never** check out the
  PR head SHA (that runs fork code with base-repo secrets).
- Enforce branch protection: required status checks (each scan job + a final gate), require
  up-to-date branches, require approval for first-time/outside contributors.
- Add a final `security-gate` job (`needs: [all scans]`, `if: always()`) that `exit 1`s on any
  upstream failure, so the merge is actually blocked.
- Require CODEOWNERS review for `.github/workflows/` and `.github/actions/`. Disable "Allow GitHub
  Actions to create and approve PRs."
- Run scanners with non-zero exit + severity threshold (`CRITICAL,HIGH`) so findings break the
  build. Use `actions/checkout` `fetch-depth: 0` for history secret scanning; never echo secrets — prefer
  stdin or masked/secret-aware action inputs (process substitution is shell-specific and can still
  expose data via the process table or runner FS).

### Pitfalls
- SHA-pinning without Dependabot strands actions on stale, vulnerable versions.
- `pull_request_target` label-gating still leaks secrets if the job ever checks out PR code.
- Over-tight `permissions` breaks legitimate jobs — scope per-job, not blanket-deny.
- Automated SAST/DAST/SCA ≠ substitute for manual business-logic review. DAST needs a deployed,
  reachable staging target. Dedupe fuzzer crashes (`afl-collect`) before failing CI.

---

## §5 — Container & image security

### Checks
- Set a non-root `USER` (e.g. `USER 65534:65534` or distroless `:nonroot`); verify
  `runAsNonRoot: true` in the K8s securityContext.
- Build on a minimal/distroless or scratch base (`gcr.io/distroless/*`, `-slim`, Alpine); strip the
  shell and package manager from the final layer. Keep runtime contents minimal-but-justified — CA
  certs, tzdata, and the language runtime are legitimate; document any exception rather than
  mandating bare `scratch` for every image.
- Multi-stage builds: compile in a fat builder, copy only artifacts into the runtime stage; strip
  pip/setuptools/apt/dpkg from production.
- Pin the base image by digest (`FROM image@sha256:...`), never `latest`.
- Reject secrets baked into layers (`trivy --scanners secret`); keep creds out of build args/ENV.
- Enforce read-only root filesystem (`readOnlyRootFilesystem: true`) with tmpfs/emptyDir for
  writable paths (`/tmp` as `noexec,nosuid`).
- Drop all capabilities (`--cap-drop ALL` / `capabilities.drop: ["ALL"]`), add back only what's
  needed (e.g. `NET_BIND_SERVICE`).
- Set `no-new-privileges` / `allowPrivilegeEscalation: false`; apply seccomp `RuntimeDefault` and
  AppArmor/SELinux profiles.
- Apply resource limits (`--memory`, `--cpus`, `--pids-limit` / K8s CPU+memory limits).
- Gate CI on image scans: fail on CRITICAL/HIGH (`trivy --exit-code 1`, `grype --fail-on critical`);
  upload SARIF. Generate + attach an SBOM per image.
- Sign images and verify at deploy (Cosign keyed or keyless); enforce via admission control or GCP
  Binary Authorization (`REQUIRE_ATTESTATION` + `ENFORCED_BLOCK_AND_AUDIT_LOG`).
- Lock down the registry: scan-on-push, tag immutability, lifecycle policies to expire untagged
  images. Rescan deployed images continuously (a clean image rots as CVE DBs update).

### Pitfalls
- Alpine/musl breaks numpy/pandas and other glibc-linked packages — test before switching.
- Distroless has no shell: use `:debug` variants or ephemeral debug containers, not in prod.
- Build-time scan pass ≠ safe forever. Signing keys in CI env vars are a leak — use KMS/Vault.
- Binary Authorization `ALWAYS_ALLOW` default rule or `DRYRUN_AUDIT_LOG_ONLY` = no real gate.
- Mutable `latest` defeats reproducibility and tag-immutability.

---

## §6 — IaC & cloud-config security

### Checks
- Run static IaC scanners on every Terraform/CloudFormation/K8s/Helm change before apply; gate CI
  on CRITICAL/HIGH via SARIF.
- Scan the rendered `terraform plan` JSON (`--framework terraform_plan`), not just `.tf` source, so
  interpolated/dynamic values are evaluated.
- **Flag** (don't blanket-reject) IAM wildcards (`Action: "*"`, `Resource: "*"`) for review — some
  list/describe APIs legitimately require `Resource: "*"`. Require a justification, scope to specific
  ARNs where possible, add conditions (MFA / source-IP / time-window) and permission boundaries, and
  validate with IAM Access Analyzer. Treat `Action: "*"` / admin-equivalent as High by default.
- Replace long-lived access keys with short-lived assumed roles; enforce permission boundaries;
  review IAM Access Analyzer for externally-shared resources and unused permissions.
- Lambda: least-privilege execution role per function; KMS-encrypt env vars; pull secrets from a
  manager, never hardcode; scan function deps; require auth on Function URLs / API Gateway.
- S3: enable Block Public Access at **both** account and bucket level (all four settings); set
  `BucketOwnerEnforced`; audit policies/ACLs for `Principal: "*"` and `AllUsers`/`AuthenticatedUsers`
  grants; enforce SSE-KMS/AES256 + deny non-TLS transport; enable access logging.
- Block public (`0.0.0.0/0` and `::/0`) ingress to admin ports, databases, and control planes
  (SSH/RDP/3306/5432/6379/etc.) by default. Public `80`/`443` to an internet-facing load balancer is
  normal — context-rate it (expected entry point, TLS, WAF/rate-limit, logging, downstream auth),
  don't auto-reject.
- **Terraform/OpenTofu state security:** state routinely contains secrets and resource IDs — require
  an encrypted remote backend, state locking, tight access control on the backend, and never commit
  `.tfstate`/`.tfvars` with secrets. Flag local/committed state as High.
- Pod securityContext: `runAsNonRoot`, `allowPrivilegeEscalation:false`, `readOnlyRootFilesystem`,
  `drop:[ALL]`, seccomp profile; forbid privileged / hostNetwork / hostPID / hostPath.
- K8s RBAC least-privilege: prefer namespaced Role/RoleBinding over ClusterRole; eliminate
  `cluster-admin` sprawl; forbid wildcard verbs/resources and `escalate`/`bind`/`impersonate`; set
  `automountServiceAccountToken:false`; avoid the default service account.
- Validate Helm chart provenance (`helm pull --verify`, GPG keyring); `helm lint --strict`; encrypt
  Helm secrets. Use documented inline suppressions with justification, not global disables.

### Pitfalls
- Onboarding scanners onto a legacy repo floods findings — start CRITICAL-only, expand gradually.
- Enabling Block Public Access without warning owners breaks legit workflows; analyze access logs
  BEFORE remediation or you destroy exposure evidence.
- Scanning `.tf` source instead of plan JSON misses dynamic misconfigurations.
- Self-escalation RBAC verbs (`create`/`update` on clusterroles, `bind`, `escalate`) silently grant
  cluster-admin.

---

## §7 — API & web-app security (review / prevention side)

> Framed as *what to verify in our own code*. Map to OWASP API Top 10 (2023) + OWASP Top 10.

### Checks
- **BOLA / IDOR (API1):** enforce per-object authorization at the data layer
  (`WHERE owner_id = current_user.id`), not just authentication. Verify every endpoint taking an
  object ID (path, query, body, batch arrays, nested paths) rejects another tenant's ID across
  GET/PUT/PATCH/DELETE. UUIDs are defense-in-depth, not a fix. **Cross-tenant probing safety:** only
  exercise this against a local/staging env with synthetic tenants, read-only first, rate-limited,
  with rollback/backups — never swap real tenant IDs against production data.
- **Multi-tenant DB isolation:** enforce the tenant predicate in every query/repository (or
  Postgres Row-Level Security); confirm migrations/admin consoles/read-replicas/backups don't bypass
  it; reject queries that can return cross-tenant rows. This is the data-layer backstop for BOLA.
- **Broken auth (API2):** reject `alg:none` (all casings) and RS256→HS256 confusion; pin an explicit
  server-side algorithm allowlist. Rate-limit login/reset/OTP. Invalidate tokens on logout and
  password change — but a stateless access JWT can't truly be revoked: this requires short access
  TTL + refresh-token rotation + a server-side token-version/session-ID (or introspection), not just
  "we revoke on logout." Don't accept the goal without the mechanism.
- **BOPLA (API3):** explicit response field allowlists per role (never blanket `to_json()`); never
  return `password_hash`, SSN, card data, `role`, internal notes. Block mass assignment with a
  writable-field allowlist + `additionalProperties:false` (reject injected `role`/`is_admin`/
  `balance`/`is_verified`).
- **Function-level auth (BFLA / API5):** restrict admin routes/methods against low-priv tokens; test
  HTTP method switching (GET blocked but PUT/PATCH allowed).
- **Unrestricted resource consumption (API4/API6):** pagination caps, request-size limits, and
  **per-credential** (not per-IP) rate limits on sensitive flows (OTP/SMS/email).
- **JWT validation:** verify signature against pinned alg; validate `exp`/`nbf`/`iss`/`aud`; HMAC
  secrets ≥256-bit and non-dictionary; sanitize/parameterize `kid` (no path traversal / SQLi);
  reject attacker-controlled `jku`/`x5u`; implement revocation (blocklist or short TTL + refresh
  rotation).
- **OAuth2/OIDC:** exact-string `redirect_uri` matching (no prefix/wildcard/path-traversal/`@`-tricks);
  enforce PKCE S256 (reject missing/`plain`/wrong verifier); validate `state` in the callback;
  single-use short-TTL codes; validate token `aud`/client binding; disable implicit flow.
- **GraphQL:** disable introspection + GraphiQL/Playground in prod; depth (≤7-10) and complexity/cost
  limits; field-level authz; disable or rate-limit batching/aliasing; parameterize resolver queries.
- **WebSocket:** validate `Origin` against an allowlist (prevents CSWSH); re-validate auth
  per-message, not just at handshake; never accept token in URL query; cap message size/rate; don't
  leak internal IDs/IP/email in frames.
- **Injection / XSS:** parameterize all queries (incl. NoSQL operator injection `{$ne:""}` in JSON/
  GraphQL bodies); context-aware output encoding; sanitize stored HTML (DOMPurify); strict
  nonce-based CSP; audit DOM sinks (`innerHTML`, `document.write`, `eval`) fed by sources
  (`location.hash`, `postMessage`, `window.name`).
- **SSRF (API7):** allowlisting one metadata IP + loopback is bypassable — defend in depth.
  Allowlist destinations by canonical host; after DNS resolution (and again after every redirect)
  block loopback, RFC1918/private, link-local incl. **IPv6** (`fe80::`, `::1`, `fc00::/7`), and
  reserved ranges; reject decimal/octal/hex/IPv4-mapped-IPv6 encodings; disable or constrain
  redirect-following; egress-proxy outbound calls; require IMDSv2 (hop-limit 1) on the metadata
  endpoint. Applies to webhooks, imports, avatar/URL fetchers, and any user-supplied URL.
- **CSRF:** for any cookie-authenticated, state-changing request, require `SameSite=Lax/Strict`
  **and** an anti-CSRF token or strict `Origin`/`Referer` check (SameSite alone is not sufficient
  across all browsers/flows). Pure `Authorization: Bearer` header APIs with no cookie auth are
  generally CSRF-exempt — confirm the auth model before waiving.
- **Misconfig (API8) / inventory (API9):** strip `Server`/`X-Powered-By`; no verbose stack traces;
  lock CORS (no permissive `Origin` reflection); retire deprecated/shadow API versions (old `/v1`
  often lacks new controls).
- **Gateway:** treat as defense-in-depth — the backend must still enforce authz/input validation;
  rate-limit per credential; mTLS gateway↔backend.

### Pitfalls
- Testing only GET (missing write-side BOLA) and only documented Swagger endpoints (missing
  shadow/deprecated versions).
- Per-IP rate limiting only (bypassed by IP rotation / GraphQL batching).
- Trusting UUIDs to prevent BOLA; assuming PKCE/`state` are enforced because the *server* supports
  them (the client must send + the server must validate).
- Handshake-only WebSocket auth; blanket serializers leaking sensitive fields; verbose gateway
  errors exposing architecture; API keys in plaintext or URL query params; no key prefix (defeats
  leak scanning).

---

## §8 — Crypto implementation & key management

### Checks
- Reject `alg=none`; pin the JWT algorithm against an explicit allowlist; never treat the
  `alg`/`jwk`/`kid` header as authoritative. Block RS256↔HS256 confusion (don't feed an RSA public
  key into an HMAC verify path).
- Pick a JWT algorithm by its correct JOSE name: `HS256` (HMAC), `ES256`/`EdDSA`, or `PS256`
  (RSA-PSS). Note `RS256` = RSASSA-**PKCS#1 v1.5** (legacy/compat-OK, not "PSS"); there is no
  "RS256-PSS". Prefer `PS256`/`EdDSA` for new asymmetric signing. Use short JWT lifetimes (access
  5-15 min); enforce `exp`/`nbf`/`aud`/`iss`; refresh + JWK-Set key rotation; constant-time
  comparison (`hmac.compare_digest`).
- Password hashing: argon2 / bcrypt / scrypt — never fast hashes (MD5/SHA-x) for passwords.
- Symmetric: authenticated encryption (AES-GCM); correct IV/nonce handling (never reuse a nonce);
  no ECB.
- RSA: 2048-bit is the floor for legacy/compat today (~112-bit strength); prefer **≥3072-bit or
  Ed25519/ECDSA-P256** for new keys and plan post-2030 migration. Use RSA-PSS for signatures and
  RSA-OAEP for encryption — never PKCS#1 v1.5 **encryption**.
- Prefer **KMS/HSM-backed, non-exportable keys** for production signing/encryption. Only when keys
  must live on disk: encrypt with a passphrase (AES-256), `0600`, audited. Rotation must be **staged
  with an overlap window** (publish the new key, accept both, then retire the old) so JWT/signature
  verification never breaks; define revocation + emergency-rotation triggers, not just "annually."
- Keep secrets/keys out of source (Vault/KMS/env), never `localStorage`.
- Enforce TLS 1.2+ (prefer 1.3); validate certs and signature algorithms.
- PQC readiness: inventory quantum-vulnerable algos (RSA, ECDH, ECDSA, DH, DSA); pilot hybrid TLS
  1.3 `X25519MLKEM768`; validate ML-KEM-768 / ML-DSA-65; plan for "harvest-now-decrypt-later" on
  long-lived secrets; confirm HSM/KMS handles larger PQC keys.

### Pitfalls
- Tokens in `localStorage` (XSS-exfiltratable) instead of httpOnly cookies.
- Wildcard redirect URIs (open-redirect/code theft); missing `state`; no refresh-token rotation.
- PKCS#1 v1.5 on new systems; assuming 2048-bit RSA is safe past 2030.
- Over-reacting on PQC: AES-128/SHA-256 are only Grover-weakened — AES-256 mitigates and SHA-256 is
  still adequate; only the asymmetric primitives are Shor-broken.

---

## §9 — Threat modeling (new feature / new trust boundary)

### Checks
- Build a data-flow diagram (processes, data stores, external entities, flows) and draw explicit
  trust boundaries.
- Apply STRIDE per element; add LINDDUN for privacy-sensitive flows; capture abuse/misuse cases.
- Map plausible adversary TTPs to MITRE ATT&CK technique IDs; profile actors targeting your sector.
- Run gap analysis (threat profile vs. detection coverage); prioritize by kill-chain phase + risk.
- Track every open threat to a mitigation with owner, priority, and closure status; treat the model
  as a living doc updated as attack surface changes.
- Store the threat-model artifact in version control alongside the code; do it in the design phase,
  not after ship.
- **Auditability (pre-deploy slice, not runtime SOC):** for changes touching auth, money, or
  sensitive data, confirm the change emits an audit-log event for security-relevant actions, that
  authz-failure/abuse conditions are alertable, and that deps/images have a rescan cadence so a clean
  ship doesn't rot. (Live monitoring, anomaly detection, and IR are out of this skill's scope — hand
  those to the runtime/SOC track.)

### Pitfalls
- Treating threat modeling as one-time rather than continuous.
- Modeling only delegated permissions, ignoring higher-risk application permissions / multi-tenant
  publisher mismatches.
- No post-remediation monitoring for new unauthorized grants or new trust-boundary crossings.
