# Secure-Ship Tooling & Framework Mappings

## Install-hardening note (read first)

Prefer tools already on PATH. When a tool is missing, install via the OS package manager or a
**pinned, checksum-verified** release — **do not** run `curl … | sh` / `wget … | bash` mid-review
(the upstream installers for grype/syft/cosign and others use this pattern; it executes remote code
unverified). Run all scanners **read-only** against the working tree; none of them need network
write access. This skill ships **no executable code** of its own.

## Active-testing authorization preflight (mandatory)

The §7 row lists **dual-use tools** (ZAP, Nuclei, ffuf, Kiterunner, Arjun, jwt_tool, Dalfox,
websocat) that send live traffic. Because this skill can drive `Bash`/`WebFetch`, treat any
*active* test as gated: before running one, confirm **(1)** the target is owned by us or has written
authorization, **(2)** it is a local/staging target (never production data, never a third party),
**(3)** scope is a specific host/path — no internet-wide or wildcard scanning, **(4)** rate limits
are set. If target ownership or authorization is ambiguous, **stop and ask** — do not scan. SAST/SCA/
IaC/secret/image scanners (all other rows) are static and read-only, so they need no preflight.

## OSS scanner matrix (free/OSS preferred)

| Domain | Primary OSS tools | Notes |
|---|---|---|
| §1 SAST / code review | **Semgrep** (`p/owasp-top-ten`, `p/cwe-top-25`, custom taint rules), **CodeQL** (free on public repos), **Bandit** (Python), ESLint security plugins | Emit SARIF; gate on High+. SARIF Viewer (VS Code) for local triage. |
| §2 Dependency / SCA / supply-chain | **OWASP Dependency-Check**, **pip-audit**, **npm audit**, **Trivy** (`fs`), **Snyk** (free tier); **syft** (SBOM gen), **grype** (SBOM scan), **OWASP Dependency-Track**; **cosign**/Rekor/Fulcio, **in-toto**, SLSA | Check transitive paths; CISA KEV + EPSS for prioritization; verify by digest. |
| §3 Secrets | **gitleaks** (pre-commit + CI + full history), **TruffleHog** (live verification), GitHub native secret scanning; **git-filter-repo** (history scrub) | Rotate before history rewrite. |
| §4 CI/CD | **actionlint**, **OpenSSF Scorecard**, **StepSecurity Harden-Runner**, **Dependabot** (actions ecosystem), **OpenSSF Allstar** | Pin actions to SHA; least-priv `GITHUB_TOKEN`; OIDC over secrets. |
| §5 Container / image | **Trivy** (vuln+misconfig+secret+SBOM), **Grype**+**Syft**, **Hadolint** (Dockerfile), **Dockle**, **docker-bench-security** (CIS), **Kubesec**, **Crane**/**Dive** (layer inspect), **Cosign** | Distroless/minimal base; non-root; pin by digest. |
| §6 IaC / cloud config | **Checkov**, **tfsec**, **Terrascan**, **KICS**, **Trivy** (`config`), **kubesec**, **Polaris**; **OPA/Rego + Conftest** (policy-as-code); AWS IAM Access Analyzer, AWS Config, `kubectl auth can-i`, `krew access-matrix` | Scan `terraform plan` JSON, not just `.tf`. |
| §7 API / web-app | **OWASP ZAP** (proxy + Access Control add-on), **Nuclei**, **ffuf**/Kiterunner (endpoint discovery), **Arjun** (param discovery), **jwt_tool**/PyJWT (JWT), **clairvoyance**/graphql-cop (GraphQL), **wscat**/websocat (WebSocket), **Dalfox** + CSP Evaluator (XSS/CSP) | Use only against systems you own/are authorized to test. |
| §8 Crypto / keys | Python **cryptography** (RSA-PSS/OAEP, PKCS#8), `hmac`/`hashlib`; **OpenSSL 3.5+** (native ML-KEM/ML-DSA) or 3.0–3.4 + oqs-provider; Open Quantum Safe; CycloneDX Crypto BOM (CBOM) | `openssl s_client -groups X25519MLKEM768` for hybrid TLS probe. |
| §9 Threat modeling | **OWASP Threat Dragon 2.x** (STRIDE/LINDDUN, CycloneDX TMBOM export), **MITRE ATT&CK Navigator**, CTID ATT&CK Workbench | Store the model in version control with the code. |

## Framework control mappings (NIST CSF 2.0 / OWASP / MITRE)

These are the control IDs that appeared in the source skills' frontmatter, grouped by domain.
Use them to label findings and to demonstrate coverage in compliance contexts.

| Domain | NIST CSF 2.0 | OWASP | MITRE / other |
|---|---|---|---|
| §1 SAST / code review | PR.PS-01, PR.PS-04, GV.SC-06/07, ID.IM-02/04, ID.AM-08, ID.RA-01/02/06, PR.DS-01/02/10, PR.IR-01, DE.CM-01 | OWASP Top 10 2021 (A01–A10), CWE Top 25 (body) | — |
| §2 Dependency / supply-chain | PR.PS-01/04, GV.SC-01/03/06/07, ID.IM-04, ID.AM-08, PR.IR-01, DE.CM-01, DE.AE-02, RS.MA-01, GV.OV-01 | — | MITRE ATLAS AML.T0010, AML.T0104; NIST AI RMF GOVERN-1.1/4.2/5.2, MAP-1.6, MANAGE-2.2; SLSA |
| §3 Secrets | PR.PS-01/04, GV.SC-06/07, ID.IM-04, ID.AM-08, PR.IR-01, PR.AA-01/02/05/06, DE.CM-01 | — | PCI-DSS Req 8, NIST 800-53 IA-5, SOC 2, EO 14028, EU CRA (body) |
| §4 CI/CD | PR.PS-01/04, GV.SC-07, ID.IM-04, ID.RA-01, PR.DS-10, DE.CM-01, DE.AE-02/06, RS.MA-01 | — | MITRE ATLAS AML.T0070/0066/0082; NIST AI RMF MEASURE-2.7, MAP-5.1, MANAGE-2.4 (fuzzing) |
| §5 Container / image | PR.PS-01/04, GV.SC-06/07, ID.IM-04, ID.AM-08, PR.IR-01, DE.CM-01 | — | CIS Docker Benchmark v1.8.0, CIS Kubernetes Benchmark, K8s Pod Security Standards (body) |
| §6 IaC / cloud config | PR.IR-01, PR.PS-01/04, ID.AM-08, ID.IM-04, GV.SC-06/07, DE.CM-01 | — | CIS Kubernetes Benchmark, OWASP K8s Security Cheat Sheet (body) |
| §7 API / web-app | ID.RA-01/06, PR.PS-01, PR.DS-10, DE.CM-01, DE.AE-07, GV.OV-02 | OWASP API Top 10 2023, OWASP Top 10 (body) | MITRE ATLAS AML.T0070/0066/0082, NIST AI RMF MEASURE-2.7/MAP-5.1/MANAGE-2.4 (api-key) |
| §8 Crypto / keys | PR.DS-01/02/10, PR.AA-01/02/05/06 | — | NIST 800-53 AC-3/IA-5/SC-23/AU-3/SC-13; FIPS 203 (ML-KEM), 204 (ML-DSA), 205 (SLH-DSA); NIST IR 8547 |
| §9 Threat modeling | PR.PS-01, GV.SC-07, ID.IM-04, PR.PS-04, DE.CM-01, DE.AE-02/06, RS.MA-01 | STRIDE / LINDDUN | MITRE ATT&CK (+Navigator), ATLAS AML.T0070/0066/0082, D3FEND, NIST AI RMF MEASURE-2.7/MAP-5.1/MANAGE-2.4 |

> Caveat: in the source catalog, OWASP/CWE references mostly live in prose, not the frontmatter
> `nist_csf` key — treat the OWASP column as the relevant standard to cite, not a verbatim metadata
> import. MITRE ATLAS / NIST AI RMF tags came from a few AI-security-flavored skills; include them
> only when the change actually involves an AI/ML system.
