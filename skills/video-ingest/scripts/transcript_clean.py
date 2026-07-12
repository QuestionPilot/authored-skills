#!/usr/bin/env python3
"""
transcript_clean.py — deterministic caption dedup + paragraphing.

The `watch-transcript-clean` engine. Takes a raw caption file (WebVTT or SRT,
including YouTube rolling auto-captions) and collapses it into clean,
timestamped ~30s paragraphs — the shape a vault transcript note wants.

YouTube auto-captions arrive in a "rolling" format: each spoken line is emitted
first as a new line being typed (with inline `<c>` word-level timing tags), then
repeated on the next cue as a settled line above the following new line, plus a
10ms "settle" cue that re-shows the just-completed line. Naively concatenating
the cues triples every line. This script:

  1. Parses cues (start time + text lines), stripping `<c>...</c>` word tags and
     inline `<00:00:00.000>` timestamp markers.
  2. Deduplicates the rolling overlap by emitting each text line exactly once, at
     the timestamp of its FIRST appearance, skipping any line identical to the
     line last emitted (handles the roll-up repetition deterministically).
  3. Buckets the deduplicated lines into fixed ~30s windows and joins each window
     into one paragraph prefixed with a `[MM:SS]` (or `[H:MM:SS]`) timestamp.

Authored (human) captions that carry no rolling duplication pass through the
dedup step unchanged — step 2 only drops a line when it equals the immediately
preceding emitted line, which authored captions never do.

Output is deterministic and structural: given the same input it always produces
the same paragraphs. The model only presents the result; no judgement here.

Usage:
    transcript_clean.py CAPTION_FILE [--bucket SECONDS] [--json]
    transcript_clean.py --stats CAPTION_FILE          # structural counts only

Exit codes: 0 ok · 2 no cues parsed · 3 file not found / unreadable.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# ---- timestamp helpers ------------------------------------------------------

# WebVTT / SRT cue timing line, e.g. "00:00:01.880 --> 00:00:03.430 align:start"
_CUE_RE = re.compile(
    r"^\s*(\d{1,2}:\d{2}:\d{2}[.,]\d{3}|\d{1,2}:\d{2}[.,]\d{3})\s*-->\s*"
    r"(\d{1,2}:\d{2}:\d{2}[.,]\d{3}|\d{1,2}:\d{2}[.,]\d{3})"
)
# Inline word-timestamp markers <00:00:00.280> and <c> ... </c> word wrappers.
_INLINE_TS_RE = re.compile(r"<\d{1,2}:\d{2}:\d{2}[.,]\d{3}>")
_TAG_RE = re.compile(r"</?c[^>]*>")
_ANY_TAG_RE = re.compile(r"<[^>]+>")


def _parse_ts(text: str) -> float:
    """'00:01:03.430' or '01:03.430' -> seconds (float)."""
    text = text.strip().replace(",", ".")
    parts = text.split(":")
    parts = [float(p) for p in parts]
    if len(parts) == 3:
        h, m, s = parts
    elif len(parts) == 2:
        h, m, s = 0.0, parts[0], parts[1]
    else:
        h, m, s = 0.0, 0.0, parts[0]
    return h * 3600 + m * 60 + s


def _fmt_ts(seconds: float) -> str:
    """seconds -> '[MM:SS]' or '[H:MM:SS]' for >= 1h."""
    total = int(round(seconds))
    h, rem = divmod(total, 3600)
    m, s = divmod(rem, 60)
    if h:
        return f"{h}:{m:02d}:{s:02d}"
    return f"{m:02d}:{s:02d}"


def _strip_tags(line: str) -> str:
    line = _INLINE_TS_RE.sub("", line)
    line = _TAG_RE.sub("", line)
    line = _ANY_TAG_RE.sub("", line)  # defensive: any stray markup
    # collapse internal whitespace runs
    return " ".join(line.split()).strip()


# ---- parsing ----------------------------------------------------------------


def parse_cues(raw: str) -> list[tuple[float, list[str]]]:
    """Return [(start_seconds, [text_line, ...]), ...] in file order."""
    cues: list[tuple[float, list[str]]] = []
    lines = raw.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    i = 0
    n = len(lines)
    while i < n:
        m = _CUE_RE.match(lines[i])
        if not m:
            i += 1
            continue
        start = _parse_ts(m.group(1))
        i += 1
        text_lines: list[str] = []
        while i < n and lines[i].strip() != "" and not _CUE_RE.match(lines[i]):
            cleaned = _strip_tags(lines[i])
            if cleaned:
                text_lines.append(cleaned)
            i += 1
        cues.append((start, text_lines))
    return cues


# ---- dedup ------------------------------------------------------------------


def dedup_lines(cues: list[tuple[float, list[str]]]) -> list[tuple[float, str]]:
    """
    Collapse rolling-caption overlap.

    Emit each distinct text line exactly once, keyed to the timestamp of its
    first appearance. A line is skipped only when it is identical to the line
    most recently emitted (the roll-up repetition). Authored captions, whose
    successive lines are always distinct, pass through unchanged.
    """
    emitted: list[tuple[float, str]] = []
    last: str | None = None
    for start, text_lines in cues:
        for line in text_lines:
            if line == last:
                continue
            emitted.append((start, line))
            last = line
    return emitted


# ---- paragraphing -----------------------------------------------------------


def paragraph_bucket(
    emitted: list[tuple[float, str]], bucket_seconds: float = 30.0
) -> list[tuple[float, str]]:
    """
    Group deduplicated lines into fixed time windows.

    Bucket index = floor(start / bucket_seconds). Each bucket becomes one
    paragraph whose timestamp is the start of the first line that fell into it.
    Empty buckets are skipped, so paragraph count tracks content density, not
    a fixed grid.
    """
    buckets: dict[int, list[str]] = {}
    bucket_start: dict[int, float] = {}
    order: list[int] = []
    for start, line in emitted:
        idx = int(start // bucket_seconds)
        if idx not in buckets:
            buckets[idx] = []
            bucket_start[idx] = start
            order.append(idx)
        buckets[idx].append(line)
    paragraphs: list[tuple[float, str]] = []
    for idx in order:
        text = " ".join(buckets[idx]).strip()
        if text:
            paragraphs.append((bucket_start[idx], text))
    return paragraphs


# ---- rendering --------------------------------------------------------------


def render_markdown(paragraphs: list[tuple[float, str]]) -> str:
    out = []
    for start, text in paragraphs:
        out.append(f"**[{_fmt_ts(start)}]** {text}")
    return "\n\n".join(out) + "\n"


def build_stats(
    cues: list[tuple[float, list[str]]],
    emitted: list[tuple[float, str]],
    paragraphs: list[tuple[float, str]],
) -> dict:
    return {
        "raw_cues": len(cues),
        "raw_text_lines": sum(len(t) for _, t in cues),
        "deduped_lines": len(emitted),
        "paragraphs": len(paragraphs),
        "first_ts": _fmt_ts(paragraphs[0][0]) if paragraphs else None,
        "last_ts": _fmt_ts(paragraphs[-1][0]) if paragraphs else None,
    }


# ---- cli --------------------------------------------------------------------


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="Dedup + paragraph a caption file.")
    ap.add_argument("caption_file", help="WebVTT (.vtt) or SRT (.srt) file")
    ap.add_argument(
        "--bucket",
        type=float,
        default=30.0,
        help="paragraph window in seconds (default 30)",
    )
    ap.add_argument("--json", action="store_true", help="emit JSON not markdown")
    ap.add_argument(
        "--stats", action="store_true", help="emit only structural counts (JSON)"
    )
    args = ap.parse_args(argv)

    path = Path(args.caption_file)
    if not path.is_file():
        print(f"ERROR: caption file not found: {path}", file=sys.stderr)
        return 3
    try:
        raw = path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:  # pragma: no cover - unreadable file
        print(f"ERROR: cannot read {path}: {exc}", file=sys.stderr)
        return 3

    cues = parse_cues(raw)
    if not cues:
        print("ERROR: no cues parsed (unrecognized caption format)", file=sys.stderr)
        return 2
    emitted = dedup_lines(cues)
    paragraphs = paragraph_bucket(emitted, args.bucket)
    stats = build_stats(cues, emitted, paragraphs)

    if args.stats:
        print(json.dumps(stats, indent=2))
        return 0
    if args.json:
        print(
            json.dumps(
                {
                    "stats": stats,
                    "paragraphs": [
                        {"ts": _fmt_ts(s), "seconds": round(s, 3), "text": t}
                        for s, t in paragraphs
                    ],
                },
                indent=2,
            )
        )
        return 0
    print(render_markdown(paragraphs), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
