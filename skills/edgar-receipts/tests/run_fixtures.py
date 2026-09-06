#!/usr/bin/env python3
"""
run_fixtures.py — structural fixture tests for the edgar-receipts skill (offline).

The fixtures are the sentence shapes the 2026-09-06 QUE-632 run actually met:
a registrant's own 10-K cover, a namesake consulting firm, a name-only board
biography, an industry-identifying biography, a substring false positive, and
a zero-hit search. A stub fetcher serves them; any URL outside the fixture map
raises, so the test proves the script makes no unexpected request.

Assertions are STRUCTURAL (grade per row, accepted-set membership, slate
shape), never byte-exact prose (skill-authoring principle 4).

Run:   python3 tests/run_fixtures.py        Exit: 0 all green · 1 any failure
"""
from __future__ import annotations
import json, sys, tempfile, urllib.parse
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "scripts"))
import edgar_receipts as er  # noqa: E402

FX = HERE / "fixtures"
EFTS = json.loads((FX / "efts.json").read_text())
DOCS = {
    "https://www.sec.gov/Archives/edgar/data/849395/000084939526000010/crh-20251231.htm": "doc_crh_10k.html",
    "https://www.sec.gov/Archives/edgar/data/1234567/000123456725000001/other.htm": "doc_cosan_20f.html",
    "https://www.sec.gov/Archives/edgar/data/896156/000089615626000030/prec14a.htm": "doc_ethan_allen_prec14a.html",
    "https://www.sec.gov/Archives/edgar/data/1096385/000109638510000021/ex99_1.htm": "doc_vectren_8k.html",
    "https://www.sec.gov/Archives/edgar/data/1325878/000132587822000058/fhlbt-20211231.htm": "doc_fhlb_10k.html",
    "https://www.sec.gov/Archives/edgar/data/1430162/000143016226000040/cosan-20f.htm": "doc_cosan_20f.html",
    "https://www.sec.gov/Archives/edgar/data/999/000000099926000001/acme.htm": "doc_two_mentions.html",
}
CALLS: list[str] = []


def stub_fetch(url: str, timeout: int = 0, tries: int = 0):
    CALLS.append(url)
    if url.startswith(er.EFTS):
        q = urllib.parse.parse_qs(urllib.parse.urlparse(url).query)["q"][0].strip('"')
        return 200, json.dumps(EFTS[q]).encode()
    if url in DOCS:
        return 200, (FX / DOCS[url]).read_bytes()
    raise AssertionError(f"unexpected network request: {url}")


fails, passes = [], []


def check(name, cond, detail=""):
    (passes if cond else fails).append(f"{name}{' — ' + detail if detail and not cond else ''}")


# --- pure helpers ------------------------------------------------------------
check("boundary: 'colas s.a.' does not match inside 'agrícolas s.a.'",
      er.find_phrase(er.norm("Terra do Sol Propriedades Agrícolas S.A. 637,782"), "Colas S.A.") is None)
check("boundary: phrase matches across a line break / whitespace run INSIDE the phrase",
      er.find_phrase(er.norm("… the registrant CRH\n   plc had the following …"), "CRH plc") is not None)
check("NFC: composed and decomposed accents compare equal",
      er.find_phrase(er.norm("Propriedades Agr\u0069\u0301colas"), "Agrícolas") is not None)
check("context word 'construction' does NOT fire on 'reconstruction' (word boundary)",
      er.grade(er.find_phrase("nebco, inc. led the reconstruction effort", "NEBCO, Inc."),
               "nebco, inc. led the reconstruction effort", False, ["construction"], "NEBCO, Inc.")[0] == "third_party_name_only")
check("context words contained in the phrase itself are ignored",
      er.usable_context_words(["inc", "", "Construction"], "Rieth-Riley Construction Co., Inc.") == [])
check("best_occurrence: an identifying sentence later in the document beats an early bare mention",
      er.best_occurrence(er.norm(open(FX / "doc_two_mentions.html").read().replace("<p>", " ").replace("</p>", " ")), "Acme Aggregates LLC", False, ["crushed stone"])[0] == "third_party_context")
check("grade: self-filer wins regardless of context",
      er.grade(er.find_phrase("x crh plc y", "CRH plc"), "x crh plc y", True, ["never"])[0] == "self_filing")
check("grade: third party without context words is name-only",
      er.grade(er.find_phrase("chairman of the board of rogers group, inc.", "Rogers Group, Inc."),
               "chairman of the board of rogers group, inc.", False, ["aggregate"])[0] == "third_party_name_only")

# --- discover over the fixture candidates ------------------------------------
cands = json.loads((FX / "candidates.json").read_text())
rows = [er.discover_one(c, stub_fetch) for c in cands]
by = {r["raw_name"]: r for r in rows}
check("CRH PLC → self_filing (own 10-K; the newer non-CRH hit is skipped by the self-filer token)",
      by["CRH PLC"]["grade"] == "self_filing" and by["CRH PLC"]["filer"].startswith("CRH"), json.dumps(by["CRH PLC"], default=str)[:200])
check("CRH PLC carries receipt_url + sha256 + quote", all(by["CRH PLC"].get(k) for k in ("receipt_url", "doc_sha256", "quote_context")))
check("Rogers Group → third_party_name_only (namesake 'Peppers and Rogers Group' and a bare board bio both fail identification)",
      by["Rogers Group Inc"]["grade"] == "third_party_name_only", by["Rogers Group Inc"].get("grade"))
check("Rogers Group: both candidate docs were examined before settling on name-only",
      sum(1 for u in CALLS if u.endswith("prec14a.htm") or u.endswith("ex99_1.htm")) == 2)
check("NEBCO → third_party_context on 'supplier of materials to the construction industry'",
      by["Nebco Inc"]["grade"] == "third_party_context" and "construction" in by["Nebco Inc"]["context_words_hit"], by["Nebco Inc"].get("grade"))
check("Colas S.A. → phrase_not_found (substring hit rejected)", by["Colas S A"]["grade"] == "phrase_not_found", by["Colas S A"].get("grade"))
check("Mathy → no_hit on an empty search", by["Mathy Construction Company"]["grade"] == "no_hit")
check("every row has search_url + fetched_at", all(r.get("search_url") and r.get("fetched_at") for r in rows))
check("every searched row records docs_examined (a hold is auditable)", all("docs_examined" in r for r in rows if r.get("grade") not in ("no_hit", "error")))

# --- ledger + slate ----------------------------------------------------------
md, slate = er.render_ledger(rows, "verify_alias")
check("ledger renders one table row per candidate", md.count("\n| r-") == len(rows), str(md.count("\n| r-")))
check("slate holds exactly the accepted rows (CRH, NEBCO)", sorted(a["raw_name"] for a in slate) == ["CRH PLC", "Nebco Inc"], json.dumps(slate)[:200])
# acceptance predicate — the dangerous direction
ge = dict(by["CRH PLC"]); ge["verdict"] = "group_entity"
check("a group_entity verdict is held even with a self_filing receipt", not er.accepted(ge))
ext = dict(by["CRH PLC"]); ext["receipt_url"] = "https://www.crh.com/investors"
check("a non-sec.gov receipt is held even with an accepted grade", not er.accepted(ext))
inc = dict(by["CRH PLC"]); inc.pop("doc_sha256")
check("a row missing doc_sha256 is held", not er.accepted(inc))
check("slate actions carry action/raw_name/target_name/source(url)/note",
      all(a["action"] == "verify_alias" and a["source"].startswith("https://www.sec.gov/") and a["target_name"] and a["note"] for a in slate))
check("held rows never enter the slate", not any(a["raw_name"] in ("Rogers Group Inc", "Colas S A", "Mathy Construction Company") for a in slate))

# --- replay ------------------------------------------------------------------
rep = er.replay_one(by["CRH PLC"], stub_fetch)
check("replay of a pinned receipt → replay_ok with unchanged sha", rep["replay"] == "replay_ok" and rep["sha_unchanged"] is True)
tampered = dict(by["CRH PLC"]); tampered["phrase"] = "CRH plc of Mars"
rt = er.replay_one(tampered, stub_fetch)
check("replay with a phrase the doc lacks → phrase_not_found AND the row is no longer accepted",
      rt["replay"] == "phrase_not_found" and not er.accepted(rt))
lost = dict(by["Nebco Inc"]); lost["context_words"] = ["quarry"]  # context that is not in the document any more
rl = er.replay_one(lost, stub_fetch)
check("replay whose identifying context is gone → grade_dropped, acceptance revoked",
      rl["replay"] == "grade_dropped" and not er.accepted(rl), rl.get("replay"))
_, slate_after = er.render_ledger([rt, rl, er.replay_one(by["CRH PLC"], stub_fetch)], "verify_alias")
check("ledger after replay keeps only replay_ok rows", [a["raw_name"] for a in slate_after] == ["CRH PLC"])

# --- CLI round trip (ledger mode, no network) ---------------------------------
with tempfile.TemporaryDirectory() as td:
    p = Path(td); (p / "rows.json").write_text(json.dumps(rows))
    rc = er.main(["ledger", str(p / "rows.json"), str(p / "ledger.md"), str(p / "slate.json"), "--action", "merge_alias"])
    check("CLI ledger mode exits 0 and writes both files", rc == 0 and (p / "ledger.md").exists() and (p / "slate.json").exists())
    sl = json.loads((p / "slate.json").read_text())
    check("CLI --action is honored on a NON-EMPTY slate", len(sl) == 2 and all(a["action"] == "merge_alias" for a in sl))
    try:
        er.main(["ledger", str(p / "rows.json"), str(p / "ledger.md"), "--action", "delete_everything"]); check("CLI rejects an unknown --action", False)
    except SystemExit:
        check("CLI rejects an unknown --action", True)

# --- guards ------------------------------------------------------------------
for ua in (None, "   ", "just-a-name"):
    try:
        er.Fetcher(ua); check(f"Fetcher refuses EDGAR_UA={ua!r} (no contact)", False)
    except SystemExit:
        check(f"Fetcher refuses EDGAR_UA={ua!r} (no contact)", True)
try:
    er.Fetcher("skill test (https://example.org)").get("https://www.crh.com/investors"); check("Fetcher refuses a non-sec.gov URL", False)
except SystemExit:
    check("Fetcher refuses a non-sec.gov URL", True)
check("no request left the fixture map", all((u.startswith(er.EFTS + "?q=") and "&" not in u.split("?q=")[1].split("&forms=")[0]) or u in DOCS for u in CALLS))

for p_ in passes: print("PASS", p_)
for f_ in fails: print("FAIL", f_)
print(f"\n{len(passes)} passed, {len(fails)} failed")
sys.exit(1 if fails else 0)
