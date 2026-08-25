#!/usr/bin/env python3
"""
run_fixtures.py — structural fixture tests for the video-ingest skill.

Runs the two NON-OPTIONAL trust-contract fixtures plus the dedup-key and
partial-run-recovery checks the QUE-440 acceptance criteria name. All assertions
are STRUCTURAL (counts, monotonicity, membership) not byte-exact prose matches
(skill-authoring principle 4), so benign caption regeneration by YouTube does not
break the suite — the invariants the pipeline promises are what is asserted.

Run:   python3 tests/run_fixtures.py
Exit:  0 all green · 1 any failure.
"""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPTS = HERE.parent / "scripts"
FIXTURES = HERE / "fixtures"
CLEAN = SCRIPTS / "transcript_clean.py"
BUNDLE = SCRIPTS / "bundle.py"

_fails: list[str] = []
_passes: list[str] = []


def check(name: str, cond: bool, detail: str = "") -> None:
    if cond:
        _passes.append(name)
        print(f"  PASS  {name}" + (f"  ({detail})" if detail else ""))
    else:
        _fails.append(name)
        print(f"  FAIL  {name}" + (f"  ({detail})" if detail else ""))


def run(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, *args], capture_output=True, text=True
    )


# --- Fixture 1: provenance (QUE-436 rolling auto-captions) --------------------


def fixture1_provenance() -> None:
    print("\nFixture 1 — provenance (QUE-436 rolling auto-captions)")
    vtt = next(FIXTURES.glob("fixture1_rolling_autocaptions_*.vtt"))
    proc = run(str(CLEAN), "--stats", str(vtt))
    check("f1: clean script exits 0", proc.returncode == 0, proc.stderr.strip())
    stats = json.loads(proc.stdout)

    # The provenance run observed ~345 rolling segments -> 20 clean paragraphs.
    # Assert the STRUCTURAL properties, with a tolerance band around the segment
    # count (YouTube may regenerate captions; the brief anticipates this).
    check(
        "f1: raw rolling segments in ~345 band [330,360]",
        330 <= stats["deduped_lines"] <= 360,
        f"deduped_lines={stats['deduped_lines']}",
    )
    check(
        "f1: dedup collapses rolling overlap (raw_text_lines > 2x deduped)",
        stats["raw_text_lines"] >= 2 * stats["deduped_lines"],
        f"raw_text_lines={stats['raw_text_lines']} deduped={stats['deduped_lines']}",
    )
    check(
        "f1: paragraph count in sane band around 20 [18,22]",
        18 <= stats["paragraphs"] <= 22,
        f"paragraphs={stats['paragraphs']}",
    )

    # Full markdown render: timestamps must be present, ordered, and ~30s spaced.
    md = run(str(CLEAN), str(vtt))
    check("f1: markdown render exits 0", md.returncode == 0)
    import re

    stamps = re.findall(r"^\*\*\[([0-9:]+)\]\*\*", md.stdout, re.MULTILINE)
    check(
        "f1: every paragraph carries a [MM:SS] stamp",
        len(stamps) == stats["paragraphs"] and len(stamps) > 0,
        f"{len(stamps)} stamps",
    )

    def to_sec(s: str) -> int:
        parts = [int(x) for x in s.split(":")]
        return parts[0] * 60 + parts[1] if len(parts) == 2 else parts[0] * 3600 + parts[1] * 60 + parts[2]

    secs = [to_sec(s) for s in stamps]
    check("f1: timestamps strictly increasing", all(b > a for a, b in zip(secs, secs[1:])))
    gaps = [b - a for a, b in zip(secs, secs[1:])]
    check(
        "f1: paragraph windows ~30s (median gap in [25,35])",
        gaps and 25 <= sorted(gaps)[len(gaps) // 2] <= 35,
        f"median_gap={sorted(gaps)[len(gaps)//2] if gaps else 'n/a'}s",
    )
    # Content sanity: known phrase from the video survives dedup.
    check(
        "f1: known content phrase preserved",
        "the model isn't really the moat" in md.stdout,
    )


# --- Fixture 2: authored captions pass through unchanged ----------------------


def fixture2_authored() -> None:
    print("\nFixture 2 — authored captions (non-duplicated) pass through unchanged")
    vtt = FIXTURES / "fixture2_authored_captions.vtt"
    proc = run(str(CLEAN), "--stats", str(vtt))
    check("f2: clean script exits 0", proc.returncode == 0, proc.stderr.strip())
    stats = json.loads(proc.stdout)
    # The core property: dedup drops NOTHING when there is no rolling duplication.
    check(
        "f2: no line dropped (deduped_lines == raw_text_lines)",
        stats["deduped_lines"] == stats["raw_text_lines"],
        f"deduped={stats['deduped_lines']} raw={stats['raw_text_lines']}",
    )
    check("f2: all 7 authored lines survive", stats["deduped_lines"] == 7, str(stats["deduped_lines"]))
    md = run(str(CLEAN), str(vtt)).stdout
    for line in [
        "Welcome to this short authored walkthrough.",
        "These captions were written by a human editor.",
        "It should land in its own paragraph bucket.",
    ]:
        check(f"f2: authored line preserved verbatim: '{line[:32]}...'", line in md)
    # Two 30s windows -> two paragraphs.
    check("f2: two paragraph buckets", stats["paragraphs"] == 2, str(stats["paragraphs"]))


# --- Dedup key: URL variants collapse to one key -----------------------------


def dedup_key_variants() -> None:
    print("\nDedup key — URL variants collapse to extractor:video-id")
    variants = [
        "https://www.youtube.com/watch?v=XTBWVVcF3Pk",
        "https://youtu.be/XTBWVVcF3Pk?si=abc123XYZ",
        "https://youtube.com/shorts/XTBWVVcF3Pk",
        "https://www.youtube.com/embed/XTBWVVcF3Pk",
        "https://m.youtube.com/watch?v=XTBWVVcF3Pk&t=42s&si=track",
    ]
    keys = set()
    for u in variants:
        p = run(str(BUNDLE), "key", "--url", u)
        keys.add(p.stdout.strip())
    check(
        "key: all URL variants collapse to one canonical key",
        keys == {"youtube:XTBWVVcF3Pk"},
        f"keys={sorted(keys)}",
    )
    # metadata path (yt-dlp --dump-json fields) yields the same key.
    with tempfile.TemporaryDirectory() as td:
        meta = Path(td) / "m.json"
        meta.write_text(json.dumps({"extractor": "youtube", "id": "XTBWVVcF3Pk"}))
        p = run(str(BUNDLE), "key", "--meta-json", str(meta))
        check("key: metadata path yields same key", p.stdout.strip() == "youtube:XTBWVVcF3Pk", p.stdout.strip())


# --- Partial-run recovery: bundle dir without manifest row is detected --------


def partial_run_recovery() -> None:
    print("\nPartial-run recovery — bundle dir without manifest row is detected")
    key = "youtube:XTBWVVcF3Pk"
    with tempfile.TemporaryDirectory() as td:
        root = Path(td) / "sources"
        # Case A: nothing there -> NOT present (exit 0).
        root.mkdir(parents=True)
        p = run(str(BUNDLE), "dedup", "--key", key, "--sources-root", str(root))
        check("dedup: empty root -> NOT present (exit 0)", p.returncode == 0, p.stdout.strip())

        # Case B: a bundle dir with a README stamping the key, but NO top-level
        # manifest row -> must still be detected (partial-run recovery).
        bdir = root / "some-slug"
        bdir.mkdir()
        (bdir / "README.md").write_text(
            f"---\ndedup_key: \"{key}\"\n---\n# bundle\n"
        )
        p = run(str(BUNDLE), "dedup", "--key", key, "--sources-root", str(root))
        check(
            "dedup: bundle-README-only (no manifest row) -> PRESENT (exit 1)",
            p.returncode == 1,
            p.stdout.strip().replace("\n", " "),
        )

        # Case C: a different key is still NOT present (no false positive).
        p = run(str(BUNDLE), "dedup", "--key", "youtube:zzzzzzzzzzz", "--sources-root", str(root))
        check("dedup: unrelated key -> NOT present (exit 0)", p.returncode == 0)


# --- Pre-convention (URL-only) bundles + boundary restraint -------------------


def legacy_url_bundles() -> None:
    """
    Detection half: a bundle captured BEFORE the canonical-key convention stamps
    only the source URL. The scanner must still find it, or an ingest silently
    duplicates it (real miss: 7 of 12 bundles in the live vault, 2026-08-24).

    Restraint half: the bare video id must match only as a STANDALONE token.
    Every restraint case ships alongside a true positive so it cannot pass
    vacuously on empty output.
    """
    print("\nPre-convention URL-only bundles + boundary restraint")
    key = "youtube:XTBWVVcF3Pk"

    with tempfile.TemporaryDirectory() as td:
        root = Path(td) / "sources"

        # Fail CLOSED on an unscannable root: indeterminate, not "safe to create".
        p = run(str(BUNDLE), "dedup", "--key", key, "--sources-root", str(root))
        check("legacy: missing sources root -> exit 3 (indeterminate)", p.returncode == 3, p.stderr.strip())

        root.mkdir(parents=True)

        # Detection: URL only, no canonical key anywhere in the file.
        bdir = root / "nate-herk-fable-method"
        bdir.mkdir()
        (bdir / "README.md").write_text(
            "---\n"
            'source: "https://www.youtube.com/watch?v=XTBWVVcF3Pk"\n'
            "---\n# pre-convention bundle (no dedup_key stamped)\n"
        )
        p = run(str(BUNDLE), "dedup", "--key", key, "--sources-root", str(root))
        check(
            "legacy: URL-only bundle -> PRESENT (exit 1)",
            p.returncode == 1,
            p.stdout.strip().replace("\n", " "),
        )
        check(
            "legacy: match is tagged legacy-url",
            "legacy-url" in p.stdout,
            p.stdout.strip().replace("\n", " "),
        )
        check(
            "legacy: scanned denominator is printed and non-zero",
            "scanned 1 markdown file" in p.stdout,
            p.stdout.strip().replace("\n", " "),
        )

        # Restraint: a longer token merely CONTAINING the id is not a match.
        # `-` and `_` are inside the id charset, so both flanks are exercised.
        near = root / "near-misses"
        near.mkdir()
        (near / "README.md").write_text(
            "aaXTBWVVcF3Pk https://youtu.be/XTBWVVcF3Pk9 XTBWVVcF3Pk-extra _XTBWVVcF3Pk\n"
        )
        p = run(str(BUNDLE), "dedup", "--key", key, "--sources-root", str(root))
        matched = [ln.strip() for ln in p.stdout.splitlines() if ln.startswith("  /")]
        check(
            "restraint: id-containing supersets do not match (only the real bundle does)",
            p.returncode == 1 and len(matched) == 1 and "nate-herk-fable-method" in matched[0],
            f"matched={matched}",
        )

        # Restraint: a different 11-char id in the same corpus stays clean.
        p = run(str(BUNDLE), "dedup", "--key", "youtube:zzzzzzzzzzz", "--sources-root", str(root))
        check(
            "restraint: unrelated id -> NOT present even with 2 files scanned",
            p.returncode == 0 and "scanned 2 markdown file" in p.stdout,
            p.stdout.strip().replace("\n", " "),
        )


def main() -> int:
    print("=" * 68)
    print("video-ingest fixture suite (structural assertions)")
    print("=" * 68)
    fixture1_provenance()
    fixture2_authored()
    dedup_key_variants()
    partial_run_recovery()
    legacy_url_bundles()
    print("\n" + "=" * 68)
    print(f"RESULT: {len(_passes)} passed, {len(_fails)} failed")
    if _fails:
        for f in _fails:
            print(f"  FAILED: {f}")
        return 1
    print("ALL GREEN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
