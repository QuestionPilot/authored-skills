#!/usr/bin/env python3
"""
edgar_receipts.py — SEC EDGAR receipt discovery, replay, and grading for
company-name / alias verification. Python 3 stdlib only.

Modes
  discover  <candidates.json> <rows.json>   search EDGAR full text per candidate,
                                            fetch the best document, replay the
                                            phrase, grade the receipt
  replay    <rows.json> <out.json>          re-fetch each row's pinned receipt_url
                                            and re-check its phrase (audit / re-proof)
  ledger    <rows.json> <ledger.md> [slate.json] [--action verify_alias|merge_alias]
                                            render the markdown table and the
                                            actions slate for the ACCEPTED rows

Candidate shape (one object per row):
  {"raw_name": "CRH PLC",            # the string being verified (as the source spells it)
   "org_name": "CRH",                # the organization it is claimed to name
   "phrase": "CRH plc",              # the exact phrase the receipt must contain
   "forms": "10-K",                  # optional: EDGAR form filter, comma-separated
   "self_filer_token": "crh",        # optional: substring of the filer's EDGAR display
                                     #   name; when set, only that company's own
                                     #   filings are accepted (strongest receipt class)
   "context_words": ["aggregate"],   # optional: words that must appear within
                                     #   CONTEXT_WINDOW chars of the phrase for a
                                     #   third-party filing to count as identifying
   "verdict": "same_entity",         # optional: same_entity | group_entity | ...
   "note": "..."}                    # optional: free text carried to the ledger

Grades (the load-bearing output — the model presents, it does not re-grade):
  self_filing           the company's own filing names it (cover, consent, exhibit)
  third_party_context   another filer's document names it AND a context word sits
                        within the window (industry / location / merger sentence)
  third_party_name_only the phrase appears but nothing in the window identifies the
                        company — a namesake can pass; HOLD unless a human adds a receipt
  phrase_not_found      the fetched document does not contain the phrase on a word
                        boundary (substring hits such as "agrícolas S.A." for
                        "Colas S.A." land here on purpose)
  no_hit                EDGAR full-text search returned nothing
  error                 network / parse failure (the message is in `error`)

A row is ACCEPTED into the slate only when ALL hold: grade in {self_filing,
third_party_context}; verdict absent or "same_entity" (a group_entity /
unverifiable / excluded verdict is a hold by construction); receipt_url on
sec.gov; doc_sha256 + quote_context present; and, after `replay`, replay ==
"replay_ok" (a replay that fails, or that finds the phrase but not the
identifying context, revokes acceptance). `quote_context` is a NORMALIZED
window (NFC, lowercase, whitespace-collapsed, tags stripped) wide enough to
hold the context evidence — not a verbatim quote.

Network: EDGAR's fair-access policy requires a descriptive User-Agent with a
contact. Set EDGAR_UA (e.g. "MyProject research (https://example.com)"); the
script refuses to make a request without it. Requests are paced at
REQUEST_INTERVAL seconds (SEC allows 10/s; we use ~3/s).
"""
from __future__ import annotations

import hashlib
import html
import json
import re
import sys
import time
import unicodedata
import urllib.parse
import urllib.request
from datetime import datetime, timezone

EFTS = "https://efts.sec.gov/LATEST/search-index"
ARCHIVES = "https://www.sec.gov/Archives/edgar/data"
REQUEST_INTERVAL = 0.35
CONTEXT_WINDOW = 400
MAX_DOCS_PER_CANDIDATE = 10  # the identifying sentence for a private company is often in an older filing
ACCEPTED_GRADES = {"self_filing", "third_party_context"}
ACCEPTED_VERDICTS = {None, "", "same_entity"}  # group_entity / unverifiable / excluded rows never enter the slate
SEC_HOSTS = ("https://www.sec.gov/", "https://efts.sec.gov/", "https://data.sec.gov/")
VALID_ACTIONS = {"verify_alias", "merge_alias"}


# ----------------------------------------------------------------------------
# pure helpers (fixture-tested)
# ----------------------------------------------------------------------------
def norm(text: str) -> str:
    """NFC + whitespace-collapse + lowercase; the only normalization applied to both sides."""
    return re.sub(r"\s+", " ", unicodedata.normalize("NFC", text)).strip().lower()


def is_sec_url(url: str | None) -> bool:
    return bool(url) and url.startswith(SEC_HOSTS)


def accepted(row: dict) -> bool:
    """The ONE acceptance predicate — grade, verdict, SEC provenance, replay state, receipt fields."""
    if row.get("grade") not in ACCEPTED_GRADES:
        return False
    if row.get("verdict") not in ACCEPTED_VERDICTS:
        return False
    if not is_sec_url(row.get("receipt_url")) or not row.get("doc_sha256") or not row.get("quote_context"):
        return False
    if "replay" in row and row["replay"] != "replay_ok":
        return False
    return True


def strip_html(body: bytes) -> str:
    return html.unescape(re.sub(r"<[^>]+>", " ", body.decode("utf-8", "replace")))


def phrase_pattern(phrase: str) -> re.Pattern:
    """Unicode-word-boundary pattern: 'colas s.a.' must NOT match 'agrícolas s.a.'."""
    p = re.escape(norm(phrase)).replace(r"\ ", r"\s+")
    return re.compile(r"(?<!\w)" + p + r"(?!\w)")


def find_phrase(text_norm: str, phrase: str):
    return phrase_pattern(phrase).search(text_norm)


def usable_context_words(context_words, phrase: str) -> list[str]:
    """Drop empty words and words already contained in the phrase (they prove nothing)."""
    out = []
    for w in context_words or []:
        w = norm(w)
        if w and w not in norm(phrase):
            out.append(w)
    return out


def grade(match, text_norm: str, self_filer: bool, context_words: list[str] | None, phrase: str = "") -> tuple[str, list[str]]:
    """Grade one matched occurrence. Returns (grade, context_words_hit).
    Context words match on a word boundary ("construction" never fires on "reconstruction")."""
    if match is None:
        return "phrase_not_found", []
    if self_filer:
        return "self_filing", []
    window = text_norm[max(0, match.start() - CONTEXT_WINDOW): match.end() + CONTEXT_WINDOW]
    hit = [w for w in usable_context_words(context_words, phrase) if phrase_pattern(w).search(window)]
    return ("third_party_context" if hit else "third_party_name_only"), hit


GRADE_RANK = {"self_filing": 3, "third_party_context": 2, "third_party_name_only": 1}


def best_occurrence(text_norm: str, phrase: str, self_filer: bool, context_words) -> tuple[str, list[str], object]:
    """Grade EVERY occurrence of the phrase and keep the best one (a table-of-contents
    mention early in a filing must not hide an identifying sentence later)."""
    best = ("phrase_not_found", [], None)
    for m in phrase_pattern(phrase).finditer(text_norm):
        g, hit = grade(m, text_norm, self_filer, context_words, phrase)
        if GRADE_RANK.get(g, 0) > GRADE_RANK.get(best[0], 0):
            best = (g, hit, m)
        if g == "self_filing" or g == "third_party_context":
            break
    return best


def doc_url(hit: dict) -> str:
    adsh, fname = hit["_id"].split(":")
    cik = hit["_source"]["ciks"][0].lstrip("0")
    return f"{ARCHIVES}/{cik}/{adsh.replace('-', '')}/{fname}"


def order_hits(hits: list[dict], self_filer_token: str | None) -> tuple[list[dict], bool]:
    """Newest first; when a self-filer token is given keep only that filer's docs."""
    if self_filer_token:
        # whole-word match on the filer's display name; a bare substring ("crh")
        # could select a namesake or an unrelated group company
        tok = phrase_pattern(self_filer_token)
        own = [h for h in hits if tok.search(norm(" ".join(h["_source"]["display_names"])))]
        own.sort(key=lambda h: h["_source"]["file_date"], reverse=True)
        return own, True
    hits = sorted(hits, key=lambda h: h["_source"]["file_date"], reverse=True)
    return hits, False


def search_url(phrase: str, forms: str | None) -> str:
    q = urllib.parse.quote(f'"{phrase}"')
    return f"{EFTS}?q={q}" + (f"&forms={urllib.parse.quote(forms)}" if forms else "")


# ----------------------------------------------------------------------------
# network (injectable — tests pass a stub fetcher)
# ----------------------------------------------------------------------------
class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise urllib.error.HTTPError(req.full_url, code, f"redirect to {newurl} refused (receipts are fetched from sec.gov only)", headers, fp)


class Fetcher:
    def __init__(self, user_agent: str | None):
        ua = (user_agent or "").strip()
        if not ua or not ("@" in ua or "http" in ua):
            raise SystemExit("EDGAR_UA must be a descriptive User-Agent WITH a contact (an email or a URL) — SEC fair-access policy; refusing to fetch")
        self.ua = ua
        self._last = 0.0
        self._opener = urllib.request.build_opener(_NoRedirect())

    def get(self, url: str, timeout: int = 90, tries: int = 3) -> tuple[int, bytes]:
        if not is_sec_url(url):
            raise SystemExit(f"refusing to fetch a non-sec.gov URL: {url}")
        import urllib.error
        for k in range(tries):
            wait = REQUEST_INTERVAL - (time.monotonic() - self._last)
            if wait > 0:
                time.sleep(wait)
            try:
                req = urllib.request.Request(url, headers={"User-Agent": self.ua, "Accept-Encoding": "identity"})
                with self._opener.open(req, timeout=timeout) as r:
                    self._last = time.monotonic()
                    return r.status, r.read()
            except urllib.error.HTTPError as e:
                self._last = time.monotonic()
                if e.code in (429, 403) and k < tries - 1:
                    ra = e.headers.get("Retry-After") if e.headers else None
                    time.sleep(float(ra) if ra and ra.isdigit() else 10.0)
                    continue
                if k == tries - 1:
                    raise
                time.sleep(2 * (k + 1))
            except Exception:
                self._last = time.monotonic()
                if k == tries - 1:
                    raise
                time.sleep(2 * (k + 1))
        raise RuntimeError("unreachable")


# ----------------------------------------------------------------------------
# core flows
# ----------------------------------------------------------------------------
def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def discover_one(cand: dict, fetch) -> dict:
    row = {k: cand.get(k) for k in ("raw_name", "org_name", "phrase", "verdict", "note", "self_filer_token", "context_words")}
    row["fetched_at"] = _now()
    url = search_url(cand["phrase"], cand.get("forms"))
    row["search_url"] = url
    try:
        st, body = fetch(url)
        payload = json.loads(body)
        hits = payload["hits"]["hits"]
        row["hits_total"] = payload["hits"]["total"]["value"]
        ordered, self_filer = order_hits(hits, cand.get("self_filer_token"))
        if not ordered:
            row["grade"] = "no_hit"
            return row
        best = None
        examined = 0
        doc_errors = []
        for hit in ordered[:MAX_DOCS_PER_CANDIDATE]:
            url_doc = doc_url(hit)
            try:
                st, body = fetch(url_doc)
            except Exception as e:  # one bad document never aborts the candidate
                doc_errors.append(f"{url_doc}: {e}")
                continue
            examined += 1
            text = norm(strip_html(body))
            g, ctx_hit, m = best_occurrence(text, cand["phrase"], self_filer, cand.get("context_words"))
            if m is None:
                continue
            candidate = {
                "receipt_url": url_doc, "form": hit["_source"]["form"], "file_date": hit["_source"]["file_date"],
                "filer": hit["_source"]["display_names"][0], "http_status": st,
                "doc_sha256": hashlib.sha256(body).hexdigest(),
                # normalized (NFC, lowercased, whitespace-collapsed, tags stripped) window
                # wide enough to hold the context evidence — not a verbatim quote
                "quote_context": text[max(0, m.start() - CONTEXT_WINDOW): m.end() + CONTEXT_WINDOW],
                "grade": g, "context_words_hit": ctx_hit,
            }
            if best is None or GRADE_RANK.get(g, 0) > GRADE_RANK.get(best["grade"], 0):
                best = candidate
            if g in ACCEPTED_GRADES:
                break  # a name-only doc is kept only if nothing better follows
        row["docs_examined"] = examined
        row["search_truncated"] = len(ordered) > MAX_DOCS_PER_CANDIDATE
        if doc_errors:
            row["doc_errors"] = doc_errors
        if best is None:
            row["grade"] = "phrase_not_found"
        else:
            row.update(best)
    except Exception as e:  # network / parse
        row["grade"] = "error"
        row["error"] = str(e)
    return row


def replay_one(row: dict, fetch) -> dict:
    """Re-fetch the pinned receipt and RE-GRADE it with the stored token / context words.
    A replay that fails, or a document whose identifying context is gone, revokes the
    row's acceptance (the ledger filters on `replay`)."""
    out = dict(row)
    out["replayed_at"] = _now()
    if not is_sec_url(row.get("receipt_url")):
        out["replay"] = "non_sec_receipt"
        return out
    try:
        st, body = fetch(row["receipt_url"])
        text = norm(strip_html(body))
        out["http_status"] = st
        out["doc_sha256_replay"] = hashlib.sha256(body).hexdigest()
        out["sha_unchanged"] = (out["doc_sha256_replay"] == row.get("doc_sha256"))
        self_filer = bool(row.get("self_filer_token"))
        g, ctx_hit, m = best_occurrence(text, row["phrase"], self_filer, row.get("context_words"))
        out["grade_replay"] = g
        if m is None:
            out["replay"] = "phrase_not_found"
        elif GRADE_RANK.get(g, 0) < GRADE_RANK.get(row.get("grade"), 0):
            out["replay"] = "grade_dropped"  # phrase still there, identifying context gone
        else:
            out["replay"] = "replay_ok"
            out["quote_context"] = text[max(0, m.start() - CONTEXT_WINDOW): m.end() + CONTEXT_WINDOW]
    except Exception as e:
        out["replay"] = "error"
        out["error"] = str(e)
    return out


def render_ledger(rows: list[dict], action_kind: str) -> tuple[str, list[dict]]:
    def esc(s):
        return (s or "").replace("|", "\\|").replace("\n", " ")
    acc = [r for r in rows if accepted(r)]
    held = [r for r in rows if not accepted(r)]
    lines = [
        f"Rows: {len(rows)} · accepted: {len(acc)} · held/not-receipted: {len(held)} · "
        f"grades: {json.dumps({g: sum(1 for r in rows if r.get('grade') == g) for g in sorted({r.get('grade') or '' for r in rows})})}",
        "",
        "| id | string → organization | grade | receipt | phrase | filer / form / date | sha256 (doc) | note |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for i, r in enumerate(rows, 1):
        rec = f"<{r['receipt_url']}>" if r.get("receipt_url") else "—"
        fil = " / ".join(str(r.get(k) or "") for k in ("filer", "form", "file_date")).strip(" /")
        lines.append(
            f"| r-{i:02d} | {esc(r.get('raw_name'))} → {esc(r.get('org_name'))} | {r.get('grade')}{'' if accepted(r) else ' (held)'}{(' · replay=' + r['replay']) if r.get('replay') else ''} | {rec} | "
            f"{esc(r.get('phrase'))} | {esc(fil)} | {(r.get('doc_sha256') or '')[:16]} | {esc(r.get('note'))} |"
        )
    slate = [
        {"action": action_kind, "raw_name": r["raw_name"], "target_name": r["org_name"],
         "source": r["receipt_url"], "note": f"{r.get('verdict') or 'same_entity'}: {r.get('grade')} — {r.get('note') or ''}".strip(" —")}
        for r in acc
    ]
    return "\n".join(lines) + "\n", slate


# ----------------------------------------------------------------------------
# CLI
# ----------------------------------------------------------------------------
def main(argv: list[str]) -> int:
    import os
    if not argv or argv[0] not in {"discover", "replay", "ledger"}:
        print(__doc__)
        return 2
    mode = argv[0]
    if mode == "ledger":
        rest = list(argv[1:])
        action = "verify_alias"
        if "--action" in rest:
            i = rest.index("--action")
            action = rest[i + 1] if i + 1 < len(rest) else ""
            del rest[i:i + 2]
        if action not in VALID_ACTIONS:
            raise SystemExit(f"--action must be one of {sorted(VALID_ACTIONS)}, got {action!r}")
        args = rest
        if len(args) < 2:
            raise SystemExit("usage: ledger <rows.json> <ledger.md> [slate.json] [--action verify_alias|merge_alias]")
        rows = json.load(open(args[0]))
        md, slate = render_ledger(rows, action)
        open(args[1], "w").write(md)
        if len(args) > 2:
            json.dump(slate, open(args[2], "w"), indent=1, ensure_ascii=False)
        print(f"ledger: {len(rows)} rows, {len(slate)} accepted → {args[1]}" + (f", slate → {args[2]}" if len(args) > 2 else ""))
        return 0
    fetch = Fetcher(os.environ.get("EDGAR_UA")).get
    src, dst = argv[1], argv[2]
    items = json.load(open(src))
    out = []
    for it in items:
        r = discover_one(it, fetch) if mode == "discover" else replay_one(it, fetch)
        key = r.get("grade") if mode == "discover" else r.get("replay")
        print(f"{key:22s} {r.get('raw_name')!r:40} {r.get('form') or '':8} {r.get('file_date') or ''} {(r.get('filer') or '')[:40]}")
        out.append(r)
    json.dump(out, open(dst, "w"), indent=1, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
