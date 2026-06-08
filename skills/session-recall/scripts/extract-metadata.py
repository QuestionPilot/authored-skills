#!/usr/bin/env python3
"""Extract session metadata from Claude Code + Codex JSONL files.

Batch mode (preferred — one invocation for all files):
  python3 extract-metadata.py /path/to/dir/*.jsonl
  python3 extract-metadata.py file1.jsonl file2.jsonl

Single-file mode (stdin):
  head -200 <session.jsonl> | python3 extract-metadata.py

Auto-detects platform from the JSONL structure. Outputs one JSON object per
file, one per line, then a final _meta line with processing stats.

PORT NOTES (vs CE ce-sessions — see reference/port-notes.md):
  - try_claude now also captures the transcript `cwd` (the original captured only
    branch/ts/session). This lets --cwd-filter scope Claude sessions by their real
    working directory instead of by encoded directory name (which mangles spaces).
  - --cwd-filter is now STRICT and path-component aware: a record whose `cwd` is
    missing OR does not match the filter as a path component / path-suffix is
    DROPPED. The CE original let missing-`cwd` records pass, which over-matched
    once discovery scans all project dirs. Omit --cwd-filter for an all-repos scan.
  - Metadata is read by scanning up to CAP_LINES / CAP_BYTES from the head rather
    than a fixed 25-line window — resumed/compacted sessions can open with a
    queue-operation / attachment preamble that pushes the first user line down.
  - Cursor parsing is intentionally absent (this skill discovers Claude + Codex).
"""
import sys
import json
import os

CAP_LINES = 200          # scan this many head lines looking for the metadata object
CAP_BYTES = 262144       # ...or this many bytes, whichever comes first
TAIL_BYTES = 16384       # read last 16KB to find the final timestamp


def try_claude(lines):
    for line in lines:
        try:
            obj = json.loads(line.strip())
            if obj.get("type") == "user" and "gitBranch" in obj:
                return {
                    "platform": "claude",
                    "branch": obj.get("gitBranch", ""),
                    "cwd": obj.get("cwd", ""),
                    "ts": obj.get("timestamp", ""),
                    "session": obj.get("sessionId", ""),
                }
        except (json.JSONDecodeError, KeyError):
            pass
    return None


def try_codex(lines):
    meta = {}
    for line in lines:
        try:
            obj = json.loads(line.strip())
            if obj.get("type") == "session_meta":
                p = obj.get("payload", {})
                meta["platform"] = "codex"
                meta["cwd"] = p.get("cwd", "")
                meta["session"] = p.get("id", "")
                meta["ts"] = p.get("timestamp", obj.get("timestamp", ""))
                meta["source"] = p.get("source", "")
                meta["cli_version"] = p.get("cli_version", "")
            elif obj.get("type") == "turn_context":
                p = obj.get("payload", {})
                meta["model"] = p.get("model", meta.get("model", ""))
                meta["cwd"] = meta.get("cwd") or p.get("cwd", "")
        except (json.JSONDecodeError, KeyError):
            pass
    return meta if meta else None


def extract_from_lines(lines):
    return try_claude(lines) or try_codex(lines)


def get_last_timestamp(filepath, size):
    """Read the tail of a file to find the last message with a timestamp."""
    try:
        with open(filepath, "rb") as f:
            f.seek(max(0, size - TAIL_BYTES))
            tail = f.read().decode("utf-8", errors="ignore")
            lines = tail.strip().split("\n")
        for line in reversed(lines):
            try:
                obj = json.loads(line.strip())
                if "timestamp" in obj:
                    return obj["timestamp"]
            except (json.JSONDecodeError, KeyError):
                pass
    except (OSError, IOError):
        pass
    return None


def read_head(filepath):
    """Read up to CAP_LINES / CAP_BYTES from the head so the metadata object is
    found even behind a queue-operation / attachment preamble."""
    lines = []
    nbytes = 0
    with open(filepath, "r", errors="replace") as f:
        for i, line in enumerate(f):
            lines.append(line)
            nbytes += len(line)
            if i + 1 >= CAP_LINES or nbytes >= CAP_BYTES:
                break
    return lines


def cwd_matches(cwd, filt):
    """Strict, path-component-aware match. Returns True only when `cwd` is
    non-empty AND `filt` matches it as a full path, a path-suffix, or a single
    path component. A bare repo name ("myrepo") matches
    "/Users/x/projects/myrepo"; it does NOT match "/x/my-myrepo-fork"
    (that is a substring, not a component) — fixing CE's substring over-match.
    Case-insensitive (macOS paths are typically case-insensitive). NOTE: matching
    any path component means an overly-generic filter ("projects", "src", a
    username) over-includes — the SKILL instructs passing a repo LEAF name and
    leans on the keyword filter for precision; component match is what lets a
    session run from a repo SUBDIR/worktree still scope to the repo."""
    if not cwd:
        return False
    cwd_n = cwd.rstrip("/").lower()
    filt_n = filt.rstrip("/").lower()
    if not filt_n:
        return True
    if cwd_n == filt_n or cwd_n.endswith("/" + filt_n):
        return True
    return filt_n in cwd_n.split("/")


def _extract_user_assistant_text(filepath):
    """Concatenated user + assistant text only (no JSONL metadata, tool calls,
    tool outputs, or thinking/reasoning). Without this filtering, common topic
    words like "session" would match every file via the sessionId field."""
    chunks = []
    try:
        with open(filepath, "r", errors="replace") as f:
            for line in f:
                try:
                    obj = json.loads(line.strip())
                except (json.JSONDecodeError, ValueError):
                    continue

                t = obj.get("type")
                if t == "user":
                    msg = obj.get("message", {})
                    content = msg.get("content")
                    if isinstance(content, str):
                        chunks.append(content)
                    elif isinstance(content, list):
                        for block in content:
                            if isinstance(block, dict) and block.get("type") == "text":
                                chunks.append(block.get("text", ""))
                    continue
                if t == "assistant":
                    msg = obj.get("message", {})
                    content = msg.get("content", [])
                    if isinstance(content, list):
                        for block in content:
                            if isinstance(block, dict) and block.get("type") == "text":
                                chunks.append(block.get("text", ""))
                    continue

                if t == "event_msg":
                    p = obj.get("payload", {})
                    if p.get("type") == "user_message":
                        msg = p.get("message", "")
                        if isinstance(msg, str):
                            parts = msg.split("</system_instruction>")
                            chunks.append(parts[-1] if parts else msg)
                    continue
                if t == "response_item":
                    p = obj.get("payload", {})
                    if p.get("type") == "message" and p.get("role") == "assistant":
                        for block in p.get("content", []):
                            if isinstance(block, dict) and block.get("type") == "output_text":
                                chunks.append(block.get("text", ""))
                    continue
    except (OSError, IOError):
        pass
    return "\n".join(chunks)


def count_keyword_matches(filepath, keywords):
    text_lower = _extract_user_assistant_text(filepath).lower()
    return {kw: text_lower.count(kw.lower()) for kw in keywords}


def process_file(filepath):
    try:
        size = os.path.getsize(filepath)
        result = extract_from_lines(read_head(filepath))
        if result:
            result["file"] = filepath
            result["size"] = size
            last_ts = get_last_timestamp(filepath, size)
            if last_ts:
                result["last_ts"] = last_ts
            return result, None
        return None, filepath
    except (OSError, IOError):
        return None, filepath


# Parse arguments: files and optional --cwd-filter / --keyword
files = []
cwd_filter = None
keywords = None
args = sys.argv[1:]
i = 0
while i < len(args):
    if args[i] == "--cwd-filter" and i + 1 < len(args):
        cwd_filter = args[i + 1]
        i += 2
    elif args[i] == "--keyword" and i + 1 < len(args):
        keywords = [k for k in args[i + 1].split(",") if k]
        i += 2
    elif not args[i].startswith("-"):
        files.append(args[i])
        i += 1
    else:
        i += 1

if files:
    processed = 0
    parse_errors = 0
    filtered = 0
    matched = 0
    for filepath in files:
        if not filepath.endswith(".jsonl"):
            continue
        result, error = process_file(filepath)
        processed += 1
        if result:
            # Strict cwd scoping: drop records that don't match (incl. missing cwd)
            # — cheap metadata check before paying the full-file keyword scan.
            if cwd_filter and not cwd_matches(result.get("cwd", ""), cwd_filter):
                filtered += 1
                continue
            if keywords:
                matches = count_keyword_matches(filepath, keywords)
                result["keyword_matches"] = matches
                result["match_count"] = sum(matches.values())
                if result["match_count"] == 0:
                    continue
                matched += 1
            print(json.dumps(result))
        elif error:
            parse_errors += 1

    meta = {"_meta": True, "files_processed": processed, "parse_errors": parse_errors}
    if cwd_filter:
        meta["filtered_by_cwd"] = filtered
    if keywords:
        meta["files_matched"] = matched
    print(json.dumps(meta))
else:
    # No file args: single-file stdin mode, or an empty xargs invocation
    # (discover found no files) — emit a clean zero-file result.
    lines = [] if sys.stdin.isatty() else list(sys.stdin)
    if not lines:
        meta = {"_meta": True, "files_processed": 0, "parse_errors": 0}
        if keywords:
            meta["files_matched"] = 0
        print(json.dumps(meta))
    else:
        result = extract_from_lines(lines)
        if result:
            print(json.dumps(result))
        print(json.dumps({"_meta": True, "files_processed": 1, "parse_errors": 0 if result else 1}))
