#!/usr/bin/env python3
"""Extract error signals from a Claude Code or Codex JSONL session file.

Usage:
  cat <session.jsonl> | python3 extract-errors.py
  cat <session.jsonl> | python3 extract-errors.py --output PATH

Auto-detects platform. Finds failed tool calls / commands and outputs them with
timestamps. With --output PATH the error log is written to PATH and stdout
receives only a one-line JSON status.

PORT NOTES (vs CE ce-sessions — see reference/port-notes.md):
  - Error summaries pass through the same narrow credential redaction as the
    skeleton extractor (command output can carry secrets).
  - The Cursor path is a no-op (Cursor transcripts don't log tool results, and
    this skill discovers Claude + Codex anyway).
"""
import argparse
import io
import os
import sys
import json
import re

parser = argparse.ArgumentParser(add_help=True)
parser.add_argument("--output", metavar="PATH",
                    help="Write errors to PATH; stdout receives a one-line _meta status.")
args = parser.parse_args()

_original_stdout = sys.stdout
if args.output:
    sys.stdout = io.StringIO()

stats = {"lines": 0, "parse_errors": 0, "errors_found": 0, "redactions": 0}

_REDACT = [
    re.compile(r"sk-" + r"ant-[A-Za-z0-9_\-]{20,}"),
    re.compile(r"xox" + r"[baprs]-[A-Za-z0-9-]{10,}"),
    re.compile(r"gh" + r"[pousr]_[A-Za-z0-9]{20,}"),
    re.compile(r"github" + r"_pat_[A-Za-z0-9_]{20,}"),
    re.compile(r"AKIA" + r"[0-9A-Z]{16}"),
    re.compile(r"(?i)bearer\s+[A-Za-z0-9._\-]{20,}"),
    re.compile(r"(?i)[\w-]*(?:secret|token|passw(?:or)?d|api[_-]?key|access[_-]?key)[\w-]*\s*[:=]\s*[\"']?[^\s\"']{6,}"),
]


def redact(text):
    for rx in _REDACT:
        text, n = rx.subn("[REDACTED]", text)
        if n:
            stats["redactions"] += n
    return text


def summarize_error(raw):
    text = str(raw).strip()
    for line in text.split("\n"):
        line = line.strip()
        if line:
            return redact(line[:200])
    return redact(text[:200])


def handle_claude(obj):
    if obj.get("type") == "user":
        content = obj.get("message", {}).get("content", [])
        if isinstance(content, list):
            for block in content:
                if block.get("type") == "tool_result" and block.get("is_error"):
                    ts = obj.get("timestamp", "")[:19]
                    summary = summarize_error(block.get("content", ""))
                    print(f"[{ts}] [error] {summary}")
                    print("---")
                    stats["errors_found"] += 1


def handle_codex(obj):
    if obj.get("type") == "event_msg":
        p = obj.get("payload", {})
        if p.get("type") == "exec_command_end":
            output = p.get("aggregated_output", "")
            stderr = p.get("stderr", "")
            command = p.get("command", [])
            cmd_str = command[-1] if command else ""
            exit_match = None
            if "Process exited with code " in output:
                try:
                    code_str = output.split("Process exited with code ")[1].split("\n")[0]
                    exit_code = int(code_str)
                    if exit_code != 0:
                        exit_match = exit_code
                except (IndexError, ValueError):
                    pass
            if exit_match is not None or stderr:
                ts = obj.get("timestamp", "")[:19]
                error_summary = summarize_error(stderr if stderr else output)
                print(f"[{ts}] [error] exit={exit_match} cmd={redact(cmd_str[:120])}: {error_summary}")
                print("---")
                stats["errors_found"] += 1


def handle_noop(obj):
    pass


detected = None
buffer = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    buffer.append(line)
    stats["lines"] += 1
    # Detect until found — NOT just the first 10 lines (see extract-skeleton.py).
    if detected is None:
        try:
            obj = json.loads(line)
            if obj.get("type") in ("user", "assistant"):
                detected = "claude"
            elif obj.get("type") in ("session_meta", "turn_context", "response_item", "event_msg"):
                detected = "codex"
            elif obj.get("role") in ("user", "assistant") and "type" not in obj:
                detected = "cursor"
        except (json.JSONDecodeError, KeyError):
            pass

handlers = {"claude": handle_claude, "codex": handle_codex, "cursor": handle_noop}
handler = handlers.get(detected, handle_noop)

for line in buffer:
    try:
        handler(json.loads(line))
    except (json.JSONDecodeError, KeyError):
        stats["parse_errors"] += 1

print(json.dumps({"_meta": True, **stats}))

if args.output:
    body = sys.stdout.getvalue()
    sys.stdout = _original_stdout
    with open(args.output, "w") as f:
        f.write(body)
    bytes_written = os.path.getsize(args.output)
    print(json.dumps({"_meta": True, "wrote": args.output, "bytes": bytes_written, **stats}))
