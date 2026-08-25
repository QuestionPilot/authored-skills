#!/usr/bin/env python3
"""
bundle.py — deterministic vault-bundle scaffolding + dedup key.

Owns the mechanical, non-judgement parts of a video ingest's vault side:

  * `key`      — resolve any YouTube/yt-dlp URL variant to the canonical dedup
                 key `extractor:video-id` (youtu.be, /shorts/, /embed/, watch?v=,
                 ?si= tracking params all collapse to one key).
  * `dedup`    — given a canonical key and a vault sources root, report whether
                 that video is already ingested — checking BOTH the sources
                 manifest AND existing bundle dirs (a partial run that wrote a
                 bundle dir but no manifest row is still detected → resume, not
                 duplicate). Matches the canonical key OR the bare video id as a
                 standalone token, so PRE-CONVENTION bundles that recorded only
                 the source URL are found too (tagged `legacy-url`).
  * `readme`   — emit a bundle README manifest carrying the canonical key, the
                 source/license line, and a file table.

The canonical key is stamped from deterministic `yt-dlp --dump-json` fields
(`extractor` + `id`), so it is stable across URL cosmetics. The model supplies
the metadata dict (from a prior `yt-dlp --dump-json`); this script never fetches.

Usage:
    bundle.py key   --url URL
    bundle.py key   --meta-json META.json          # from `yt-dlp --dump-json`
    bundle.py dedup --key KEY --sources-root DIR [--json]
    bundle.py readme --meta-json META.json --slug SLUG [--files f1,f2,...]

Exit codes:
    key/readme : 0 ok · 3 bad input
    dedup      : 0 NOT present (safe to create) · 1 ALREADY present (no-op/resume)
                 · 3 bad input / unscannable sources root (indeterminate)
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import date
from pathlib import Path
from urllib.parse import parse_qs, urlparse

# ---- canonical key ----------------------------------------------------------

# 11-char YouTube id charset.
_YT_ID = r"[0-9A-Za-z_-]{11}"


def youtube_id_from_url(url: str) -> str | None:
    """
    Resolve a YouTube URL variant to its 11-char video id, or None.

    Handles: watch?v=ID, youtu.be/ID, /shorts/ID, /embed/ID, /v/ID, /live/ID,
    with or without ?si= / &t= / other tracking params.
    """
    url = url.strip()
    if not re.match(r"^https?://", url, re.IGNORECASE):
        url = "https://" + url
    parsed = urlparse(url)
    host = (parsed.hostname or "").lower().removeprefix("www.")
    path = parsed.path or ""

    if host in ("youtu.be",):
        candidate = path.lstrip("/").split("/")[0]
        return candidate if re.fullmatch(_YT_ID, candidate) else None

    if host in ("youtube.com", "m.youtube.com", "music.youtube.com"):
        if path == "/watch":
            vals = parse_qs(parsed.query).get("v", [])
            if vals and re.fullmatch(_YT_ID, vals[0]):
                return vals[0]
            return None
        for prefix in ("/shorts/", "/embed/", "/v/", "/live/"):
            if path.startswith(prefix):
                candidate = path[len(prefix):].split("/")[0]
                return candidate if re.fullmatch(_YT_ID, candidate) else None
    return None


def canonical_key(*, url: str | None = None, meta: dict | None = None) -> str | None:
    """
    Canonical dedup key `extractor:video-id`.

    Prefer the deterministic yt-dlp metadata fields (`extractor_key`/`extractor`
    + `id`) when a metadata dict is supplied; otherwise parse a YouTube URL.
    """
    if meta:
        extractor = (
            meta.get("extractor_key")
            or meta.get("extractor")
            or "youtube"
        ).strip().lower()
        vid = (meta.get("id") or "").strip()
        if vid:
            return f"{extractor}:{vid}"
        return None
    if url:
        vid = youtube_id_from_url(url)
        if vid:
            return f"youtube:{vid}"
    return None


# ---- dedup check ------------------------------------------------------------


def video_id_from_key(key: str) -> str | None:
    """The bare video id inside a canonical `extractor:id` key, or None."""
    vid = key.split(":", 1)[1] if ":" in key else key
    vid = vid.strip()
    return vid or None


def _key_pattern(key: str) -> re.Pattern[str]:
    """
    Token-anchored pattern matching either the canonical key or the bare video
    id on its own.

    The bare-id alternative is what finds PRE-CONVENTION bundles: bundles
    captured before the canonical key existed stamp only the source URL, so a
    literal `extractor:id` search misses them entirely and the check fails OPEN
    (reports "safe to create" over an already-ingested video).

    Boundaries are hand-rolled rather than `\\b` because `-` and `_` are inside
    the id charset: the id must not be flanked by another id character, so a
    longer token that merely CONTAINS the id does not match.
    """
    vid = video_id_from_key(key)
    alts = [re.escape(key)]
    if vid and vid != key:
        alts.append(re.escape(vid))
    body = "|".join(alts)
    return re.compile(
        rf"(?<![0-9A-Za-z_-])(?:{body})(?![0-9A-Za-z_-])"
    )


def find_existing(key: str, sources_root: Path) -> dict:
    """
    Look for `key` in the vault sources area.

    Returns {"present": bool, "via": [...], "matches": [paths], "scanned": int}.
    Scans every `*.md` under sources_root for EITHER the canonical key or the
    bare video id as a standalone token:
      1. a manifest / README stamping the canonical key (current convention),
      2. a bundle dir whose own README carries the key (partial-run recovery:
         the dir exists but the top-level manifest row was never written),
      3. any bundle that records only the source URL (pre-convention capture) —
         matched on the bare video id and tagged `legacy-url`.

    Bias: this check errs toward PRESENT. A false positive costs one operator
    eyeball (every matching path is printed); a false negative silently
    duplicates an existing bundle, which is the failure this scanner exists to
    prevent.

    A missing sources_root raises FileNotFoundError — an unscannable root must
    fail CLOSED, never read as "safe to create".
    """
    if not sources_root.exists():
        raise FileNotFoundError(sources_root)

    pattern = _key_pattern(key)
    matches: list[str] = []
    via: list[str] = []
    scanned = 0

    for md in sorted(sources_root.rglob("*.md")):
        try:
            text = md.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        scanned += 1
        if not pattern.search(text):
            continue
        matches.append(str(md))
        if key in text:
            tag = "bundle-readme" if md.name.lower() == "readme.md" else "manifest"
        else:
            tag = "legacy-url"
        if tag not in via:
            via.append(tag)

    return {
        "present": bool(matches),
        "via": via,
        "matches": matches,
        "scanned": scanned,
    }


# ---- readme -----------------------------------------------------------------


def render_readme(meta: dict, slug: str, key: str, files: list[str]) -> str:
    title = meta.get("title", "").strip() or slug
    channel = meta.get("uploader") or meta.get("channel") or "unknown"
    upload = meta.get("upload_date") or ""
    if re.fullmatch(r"\d{8}", upload):
        upload = f"{upload[:4]}-{upload[4:6]}-{upload[6:]}"
    duration = meta.get("duration_string") or ""
    webpage = meta.get("webpage_url") or meta.get("original_url") or ""
    captured = date.today().isoformat()
    license_val = meta.get("license")
    # When the source declares no license, state it plainly without doubling.
    license_line = (
        f"Licensed: {license_val}."
        if license_val
        else "Source retains all rights (no license declared)."
    )

    rows = "\n".join(f"| `{f}` | |" for f in files) if files else "| | |"
    return f"""---
title: "{title} (source bundle)"
tags:
  - hendo-vault/raw
  - source/youtube
source: "{webpage}"
dedup_key: "{key}"
captured: {captured}
---

# {title} (source bundle)

Raw evidence bundle produced by the `video-ingest` skill.

## Provenance

- **Video:** {title} — {channel}{f", published {upload}" if upload else ""}{f", {duration}" if duration else ""}.
- **URL:** <{webpage}>
- **Canonical dedup key:** `{key}` (stable across youtu.be / /shorts/ / ?si= URL variants).
- **Captured:** {captured} via the `/watch` engine (yt-dlp native captions).

## Source / license

{license_line} Captured for private research and distillation only. The full
transcript lives here in Raw; the wiki note summarizes and quotes sparingly
(Fresh Start Policy).

## Contents

| File | What it is |
| --- | --- |
{rows}

Raw sources are evidence, not memory (see the Ingest Workflow).
"""


# ---- cli --------------------------------------------------------------------


def _load_meta(args) -> dict | None:
    if getattr(args, "meta_json", None):
        p = Path(args.meta_json)
        if not p.is_file():
            print(f"ERROR: meta-json not found: {p}", file=sys.stderr)
            return None
        return json.loads(p.read_text(encoding="utf-8"))
    return None


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="Vault-bundle scaffolding + dedup key.")
    sub = ap.add_subparsers(dest="cmd", required=True)

    k = sub.add_parser("key", help="resolve canonical dedup key")
    k.add_argument("--url")
    k.add_argument("--meta-json")

    d = sub.add_parser("dedup", help="check whether a key is already ingested")
    d.add_argument("--key", required=True)
    d.add_argument("--sources-root", required=True)
    d.add_argument("--json", action="store_true")

    r = sub.add_parser("readme", help="emit a bundle README manifest")
    r.add_argument("--meta-json", required=True)
    r.add_argument("--slug", required=True)
    r.add_argument("--files", default="")

    args = ap.parse_args(argv)

    if args.cmd == "key":
        meta = _load_meta(args)
        if meta is None and not args.url:
            print("ERROR: pass --url or --meta-json", file=sys.stderr)
            return 3
        key = canonical_key(url=args.url, meta=meta)
        if not key:
            print("ERROR: could not resolve a canonical key", file=sys.stderr)
            return 3
        print(key)
        return 0

    if args.cmd == "dedup":
        try:
            result = find_existing(args.key, Path(args.sources_root))
        except FileNotFoundError as exc:
            print(
                f"ERROR: sources root does not exist: {exc}\n"
                "       An unscannable root is INDETERMINATE, not 'safe to create'.",
                file=sys.stderr,
            )
            return 3
        if args.json:
            print(json.dumps(result, indent=2))
        else:
            if result["present"]:
                print(f"PRESENT via {','.join(result['via'])}:")
                for m in result["matches"]:
                    print(f"  {m}")
            else:
                print("NOT PRESENT (safe to create bundle)")
            # Print the denominator: a scan that compared nothing is not a clean
            # bill of health.
            print(f"  (scanned {result['scanned']} markdown file(s))")
        if not result["scanned"]:
            print(
                "NOTE: scanned 0 markdown files — verify the sources root is correct.",
                file=sys.stderr,
            )
        return 1 if result["present"] else 0

    if args.cmd == "readme":
        meta = _load_meta(args)
        if meta is None:
            return 3
        key = canonical_key(meta=meta)
        if not key:
            print("ERROR: metadata lacks an id; cannot stamp key", file=sys.stderr)
            return 3
        files = [f for f in args.files.split(",") if f.strip()]
        print(render_readme(meta, args.slug, key, files), end="")
        return 0

    return 3  # pragma: no cover


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
