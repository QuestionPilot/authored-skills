---
name: edgar-receipts
version: "1.0.0"
description: Verify that a company-name string names a specific organization using SEC EDGAR filings as machine-replayable public receipts — alias verification, controller/owner-string verification, "is this the same company" checks, any ledger where a name must be tied to a legal entity with a citable URL and a replayable quote window. Use whenever a data lane needs a receipt per company name before a registry write or a public label (MSHA controller strings, producer-list names, subsidiary spellings, former names), when company websites are rights-blocked or manual-observation-only, or when a phrase search returned hits that still need grading. Bundled script does the search → the company's own filings first → Unicode-word-boundary phrase replay → sha256 → grade (self_filing / third_party_context / third_party_name_only / phrase_not_found / no_hit) → ledger + actions slate; the model only presents and decides holds. NOT for ownership/subsidiary EDGES (that is a receipt_parent-class lane with its own evidence bar) and NOT a substitute for the operator's authorization before any registry write.
argument-hint: "<candidates.json> [--out rows.json] [--action verify_alias|merge_alias]"
allowed-tools: Bash, Read
user-invocable: true
---

# /edgar-receipts

**Goal.** Turn a list of `(string, organization, phrase)` candidates into a receipts
ledger where every ACCEPTED row carries a public SEC EDGAR URL, a normalized quote
window (NFC, lowercased, whitespace-collapsed, tags stripped — wide enough to hold the
identifying context, not a verbatim excerpt) replayed from that document, the
document's sha256, and a grade that says *why* the receipt identifies the company — so
a future session (or a critic) can re-run the proof without trusting the transcript.

**Done test.** `rows.json` exists with one row per candidate; every accepted row has
`grade ∈ {self_filing, third_party_context}`, a verdict that is absent or `same_entity`,
a `receipt_url` under `sec.gov`, a `doc_sha256`, and a `quote_context`; every other row
names its grade (held) and the slate contains only the accepted rows — one predicate
(`accepted()`) decides it, and a later `replay` that fails or loses the identifying
context revokes it. `python3 tests/run_fixtures.py` is green.

## Why the grade is the product

A receipt that merely *contains* the name does not verify an alias. On 2026-09-06
a bare phrase search accepted "Peppers and Rogers Group, Inc." (a consulting
firm) for an aggregates producer, a Portland auto-dealer "Rasmussen Group" for an Iowa
materials company, and "agrícolas S.A." as a substring hit for "Colas S.A."; the
critic then held five more rows whose only evidence was a director biography. The
consequence is asymmetric: a wrong verification publishes the organization's name on
every linked record with no further check, a missed one only withholds a label. So the
script grades, and the model never upgrades a grade by knowledge it cannot cite:

| grade | meaning | slate |
|---|---|---|
| `self_filing` | the company's own filing names it (cover, auditor consent, exhibit 21) | accepted |
| `third_party_context` | another filer names it AND a `context_words` hit sits within 400 chars (industry / location / merger sentence) | accepted |
| `third_party_name_only` | the phrase appears, nothing in the window identifies the company | **hold** — find a context-bearing filing or an operator overrule |
| `phrase_not_found` | boundary match failed (substring / namesake hits land here) | hold |
| `no_hit` / `error` | nothing to grade | hold |

A `group_entity` relation (an LLC inside a group) is not identity: give the candidate
`"verdict": "group_entity"` and the acceptance predicate holds it even with a perfect
receipt. A person-format string never enters the lane. Two honest limits of the
grades: `self_filing` trusts that `self_filer_token` (whole-word match on the filer's
EDGAR display name) names the right filer — pick a distinctive token, and read the
`filer` column; `third_party_context` proves that an identifying word sits within 400
characters of the name on a word boundary — proximity, which is why the ledger shows
the window and a human reads it before the slate is applied.

## Run

```bash
export EDGAR_UA="<project> research (<contact URL or email>)"   # SEC fair-access policy; the script refuses without it
python3 scripts/edgar_receipts.py discover candidates.json rows.json
python3 scripts/edgar_receipts.py ledger rows.json ledger.md slate.json --action verify_alias
# later, to re-prove a shipped ledger against the same URLs:
python3 scripts/edgar_receipts.py replay rows.json rows.replayed.json
```

Candidate shape and grade contract: the script's module docstring (`python3
scripts/edgar_receipts.py` with no args prints it). Set `self_filer_token` for a
company that files with the SEC (its own filings are the strongest receipt; the newest
of the search's returned hits is taken — EDGAR full-text search returns its top hits
by relevance, so `search_truncated` on a row means older filings were not examined);
set `context_words` for private companies that only appear in other filers' documents.
Every occurrence of the phrase in a document is graded and the best one kept, so a
table-of-contents mention cannot hide an identifying sentence. When a private
company's row comes back `third_party_name_only`, re-run that row with sharper
`context_words` (an industry noun, the HQ town, a merger counterparty) or a narrower
`forms` filter before holding it.

## Hard boundaries

- **Receipts come from `sec.gov` only.** Company websites are frequently blocked or
  manual-observation-only under a project's source policy; do not add a site fetch
  to this lane. If a site receipt is the only option, that is a separate, operator-cleared
  observation — record it by hand in the ledger, never through this script.
- **Never launder a hold.** The ledger prints every hold with its grade; the model may
  add a note, not change the grade. The slate is derived from grades, not edited.
- **Registry writes are separately authorized.** The slate is an input to an apply
  tool run under an operator decision recorded on the issue; the skill ends at the
  ledger + slate.
- **Rate and identity.** One request every ~0.35 s, a descriptive User-Agent that
  carries a contact (the script refuses one without an email or URL), `Retry-After`
  honored on 429/403, redirects refused, non-`sec.gov` URLs refused at the fetcher.

## Output the model presents

Counts re-derived from `rows.json` (accepted / held by grade), the ledger path, the
slate path and action kind, and — for every held row — one line: string, grade, and
what would recover it (a context word to try, a self-filing to look for, or an
operator overrule). Then stop: the registry write is the operator's call.

## Bundled

- `scripts/edgar_receipts.py` — discover / replay / ledger (stdlib only, Python 3.11+).
- `tests/run_fixtures.py` + `tests/fixtures/` — 36 offline structural assertions over
  the sentence shapes the first run met plus the acceptance predicate's negative cases
  (group_entity, non-SEC URL, missing sha, failed / degraded replay); a stub fetcher
  fails on any unexpected URL.
- `reference/lane-notes.md` — provenance of the flow, the first run's numbers, and
  the hold vocabulary as used on the originating ledger.
