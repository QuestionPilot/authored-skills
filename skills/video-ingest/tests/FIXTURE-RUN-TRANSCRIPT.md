# video-ingest — fixture run transcript

Date: 2026-07-11T18:30:45Z
Runner: python3 Python 3.9.6

## Command
```
python3 video-ingest/tests/run_fixtures.py
```

## Output
```
====================================================================
video-ingest fixture suite (structural assertions)
====================================================================

Fixture 1 — provenance (QUE-436 rolling auto-captions)
  PASS  f1: clean script exits 0
  PASS  f1: raw rolling segments in ~345 band [330,360]  (deduped_lines=346)
  PASS  f1: dedup collapses rolling overlap (raw_text_lines > 2x deduped)  (raw_text_lines=1035 deduped=346)
  PASS  f1: paragraph count in sane band around 20 [18,22]  (paragraphs=20)
  PASS  f1: markdown render exits 0
  PASS  f1: every paragraph carries a [MM:SS] stamp  (20 stamps)
  PASS  f1: timestamps strictly increasing
  PASS  f1: paragraph windows ~30s (median gap in [25,35])  (median_gap=30s)
  PASS  f1: known content phrase preserved

Fixture 2 — authored captions (non-duplicated) pass through unchanged
  PASS  f2: clean script exits 0
  PASS  f2: no line dropped (deduped_lines == raw_text_lines)  (deduped=7 raw=7)
  PASS  f2: all 7 authored lines survive  (7)
  PASS  f2: authored line preserved verbatim: 'Welcome to this short authored w...'
  PASS  f2: authored line preserved verbatim: 'These captions were written by a...'
  PASS  f2: authored line preserved verbatim: 'It should land in its own paragr...'
  PASS  f2: two paragraph buckets  (2)

Dedup key — URL variants collapse to extractor:video-id
  PASS  key: all URL variants collapse to one canonical key  (keys=['youtube:XTBWVVcF3Pk'])
  PASS  key: metadata path yields same key  (youtube:XTBWVVcF3Pk)

Partial-run recovery — bundle dir without manifest row is detected
  PASS  dedup: empty root -> NOT present (exit 0)  (NOT PRESENT (safe to create bundle))
  PASS  dedup: bundle-README-only (no manifest row) -> PRESENT (exit 1)  (PRESENT via bundle-readme:   /var/folders/yy/pwxlhhln55n_4gzxf23n7f1c0000gn/T/tmpd2qqlz8k/sources/some-slug/README.md)
  PASS  dedup: unrelated key -> NOT present (exit 0)

====================================================================
RESULT: 21 passed, 0 failed
ALL GREEN
```
