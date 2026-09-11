# edgar-receipts — lane notes

## Provenance (skill-authoring §11 step 1)

Promoted from a source-verification lane (2026-09-06): 40 MSHA controller strings
whose organizations were created from those very strings; the task was to verify each
string as an alias of its organization with a public receipt so the parent label could
return to the live map under the project privacy rule.

The flow ran three times in that session — a first discovery pass (26 replay_ok, two
namesakes and one substring hit slipped through), a tightened pass (Unicode word
boundary, newest self-filing first), and a pinned-receipt replay plus a
context-strengthening pass after an adversarial critic (Astra) held six rows. Final:
20 accepted / 20 held, applied to the registry under an operator decision, released and
live-verified (`owner_labelled` 1,250 → 2,267). Raw scripts and outputs of that run:
the operator's local cross-model run directory for 2026-09-06 (not shipped); ledger:
the project's `docs/org-alias-receipts-2026-09-06.md` (private repo).

## What the fixtures encode

| fixture | shape it preserves | expected grade |
|---|---|---|
| `doc_crh_10k.html` | registrant's own 10-K cover defining "CRH plc" | `self_filing` |
| `doc_ethan_allen_prec14a.html` | namesake — "Peppers and Rogers Group, Inc." | `third_party_name_only` |
| `doc_vectren_8k.html` | bare board biography naming the right company | `third_party_name_only` |
| `doc_fhlb_10k.html` | biography WITH an industry sentence ("supplier of materials to the construction industry") | `third_party_context` |
| `doc_cosan_20f.html` | substring false positive ("Agrícolas S.A." for "Colas S.A.") | `phrase_not_found` |
| empty efts result | private company with no EDGAR footprint | `no_hit` |

## Hold vocabulary used on the originating ledger

`same_entity` (spelling / legal form / SEC-recorded former name), `group_entity` (an
LLC inside the organization's group — held), `unverifiable` (no receipt in the sources
the lane may use), `excluded` (person-format string). Holding-company strings that
map to a differently named operator (e.g. "RR Holdco, Inc." → Rieth-Riley) need an
ownership receipt, not an alias — out of this skill's scope.

## Known limits

- Astra confirmation review 2026-09-06 (`~/cross-model-out/2026-09-06-edgar-receipts-skill/`) drove the hardening round: one acceptance predicate (grade + verdict + SEC URL + fields + replay), word-boundary context words, best-occurrence grading, re-grading replay, SEC-only fetcher with redirect refusal and Retry-After, strict `--action` parsing. Left as documented limits: filer-token identity is heuristic; context is proximity; combining marks outside NFC are not handled; efts hits are relevance-ranked and un-paginated.

- EDGAR full-text search covers 2001+ filings; a company that never touched an SEC
  filing (as filer or as a named party) yields `no_hit`.
- The efts JSON carries no snippet, so every candidate document is fetched in full;
  a 10-K can be several MB. `MAX_DOCS_PER_CANDIDATE` bounds it.
- `context_words` is a plain substring test inside a 400-char window — pick nouns
  that cannot appear by accident ("construction", "quarry", the HQ town), not "inc".
