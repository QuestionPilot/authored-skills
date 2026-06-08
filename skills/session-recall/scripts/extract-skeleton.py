#!/usr/bin/env python3
"""Extract the conversation skeleton from a Claude Code or Codex JSONL session.

Usage:
  cat <session.jsonl> | python3 extract-skeleton.py
  cat <session.jsonl> | python3 extract-skeleton.py --output PATH

Auto-detects platform. Extracts user messages (text only), assistant text (no
thinking/reasoning), and collapsed tool-call summaries. With --output PATH the
skeleton is written to PATH and stdout receives only a one-line JSON status, so
callers route bulk content to a scratch file without round-tripping it.

PORT NOTES (vs CE ce-sessions — see reference/port-notes.md):
  - A narrow redaction pass scrubs obvious credential shapes (Claude/Slack/GitHub/
    AWS keys, generic key=value secrets) from the printed content and tool targets.
    Defense-in-depth only — the synthesizer runs locally in the same harness, so
    this is belt-and-suspenders, not an exfil boundary. Deliberately narrow: it
    does NOT redact plain identifiers/hashes (avoids destroying technical context).
  - The Cursor handler is retained but inert (this skill discovers Claude + Codex).
"""
import argparse
import io
import os
import sys
import json
import re

parser = argparse.ArgumentParser(add_help=True)
parser.add_argument("--output", metavar="PATH",
                    help="Write skeleton to PATH; stdout receives a one-line _meta status.")
args = parser.parse_args()

_original_stdout = sys.stdout
if args.output:
    sys.stdout = io.StringIO()

stats = {"lines": 0, "parse_errors": 0, "user": 0, "assistant": 0, "tool": 0, "redactions": 0}

# Narrow credential-shape redaction. Patterns assembled from fragments so this
# source file does not itself trip a credential scanner when piped for review.
_REDACT = [
    re.compile(r"sk-" + r"ant-[A-Za-z0-9_\-]{20,}"),                 # Claude API keys
    re.compile(r"xox" + r"[baprs]-[A-Za-z0-9-]{10,}"),                # Slack tokens
    re.compile(r"gh" + r"[pousr]_[A-Za-z0-9]{20,}"),                  # GitHub classic tokens
    re.compile(r"github" + r"_pat_[A-Za-z0-9_]{20,}"),                # GitHub fine-grained PAT
    re.compile(r"AKIA" + r"[0-9A-Z]{16}"),                            # AWS access key id
    re.compile(r"(?i)bearer\s+[A-Za-z0-9._\-]{20,}"),                 # bearer auth headers
    # key=value / key: "value" assignments whose key name embeds a secret word
    # (covers OPENAI_API_KEY="..", AWS_SECRET_ACCESS_KEY=.., token: .., password=..)
    re.compile(r"(?i)[\w-]*(?:secret|token|passw(?:or)?d|api[_-]?key|access[_-]?key)[\w-]*\s*[:=]\s*[\"']?[^\s\"']{6,}"),
]


def redact(text):
    for rx in _REDACT:
        text, n = rx.subn("[REDACTED]", text)
        if n:
            stats["redactions"] += n
    return text


_STRIP_BLOCK = re.compile(
    r"<(?:task-notification|local-command-caveat|local-command-stdout|local-command-stderr|system-reminder)[^>]*>.*?</(?:task-notification|local-command-caveat|local-command-stdout|local-command-stderr|system-reminder)>",
    re.DOTALL,
)
_STRIP_TAG = re.compile(r"</?(?:command-message|command-name|command-args|user_query)[^>]*>")


def clean_text(text):
    """Strip framework wrapper tags, then redact credential shapes."""
    text = _STRIP_BLOCK.sub("", text)
    text = _STRIP_TAG.sub("", text)
    text = re.sub(r"\n{3,}", "\n\n", text).strip()
    return redact(text)


pending_tools = []


def flush_tools():
    if not pending_tools:
        return
    groups = []
    for entry in pending_tools:
        if groups and groups[-1][0]["name"] == entry["name"]:
            groups[-1].append(entry)
        else:
            groups.append([entry])

    for group in groups:
        name = group[0]["name"]
        if len(group) <= 2:
            for e in group:
                status = f" -> {e['status']}" if e.get("status") else ""
                ts_prefix = f"[{e['ts']}] " if e.get("ts") else ""
                print(f"{ts_prefix}[tool] {name} {redact(e['target'])}{status}")
                stats["tool"] += 1
        else:
            ts = group[0].get("ts", "")
            targets = [e["target"] for e in group if e.get("target")]
            ok = sum(1 for e in group if e.get("status") == "ok")
            err = sum(1 for e in group if e.get("status") and e["status"] != "ok")
            no_status = len(group) - ok - err
            if len(targets) > 2:
                target_str = ", ".join(targets[:2]) + f", +{len(targets) - 2} more"
            elif targets:
                target_str = ", ".join(targets)
            else:
                target_str = ""
            if no_status == len(group):
                status_str = ""
            elif err == 0:
                status_str = " -> all ok"
            else:
                status_str = f" -> {ok} ok, {err} error"
            ts_prefix = f"[{ts}] " if ts else ""
            print(f"{ts_prefix}[tools] {len(group)}x {name} ({redact(target_str)}){status_str}")
            stats["tool"] += len(group)

    pending_tools.clear()


def _safe_slice(value, n):
    return value[:n] if isinstance(value, str) else ""


def summarize_claude_tool(block):
    name = block.get("name", "unknown")
    inp = block.get("input", {})
    fp = inp.get("file_path")
    p = inp.get("path")
    target = (
        (fp if isinstance(fp, str) else None)
        or (p if isinstance(p, str) else None)
        or _safe_slice(inp.get("command"), 120)
        or _safe_slice(inp.get("pattern"), 200)
        or _safe_slice(inp.get("query"), 80)
        or _safe_slice(inp.get("prompt"), 80)
        or ""
    )
    if isinstance(target, str) and len(target) > 120:
        target = target[:120]
    return name, target


def handle_claude(obj):
    msg_type = obj.get("type")
    ts = obj.get("timestamp", "")[:19]

    if msg_type == "user":
        msg = obj.get("message", {})
        content = msg.get("content", "")
        if isinstance(content, list):
            for block in content:
                if block.get("type") == "tool_result":
                    is_error = block.get("is_error", False)
                    status = "error" if is_error else "ok"
                    tool_use_id = block.get("tool_use_id")
                    matched = False
                    if tool_use_id:
                        for entry in pending_tools:
                            if entry.get("id") == tool_use_id:
                                entry["status"] = status
                                matched = True
                                break
                    if not matched:
                        for entry in pending_tools:
                            if not entry.get("status"):
                                entry["status"] = status
                                break
            texts = [c.get("text", "") for c in content
                     if c.get("type") == "text" and len(c.get("text", "")) > 10]
            content = " ".join(texts)
        if isinstance(content, str):
            content = clean_text(content)
            if len(content) > 15:
                flush_tools()
                print(f"[{ts}] [user] {content[:800]}")
                print("---")
                stats["user"] += 1

    elif msg_type == "assistant":
        msg = obj.get("message", {})
        content = msg.get("content", [])
        if isinstance(content, list):
            has_text = False
            for block in content:
                if block.get("type") == "text":
                    text = clean_text(block.get("text", ""))
                    if len(text) > 20:
                        if not has_text:
                            flush_tools()
                            has_text = True
                        print(f"[{ts}] [assistant] {text[:800]}")
                        print("---")
                        stats["assistant"] += 1
                elif block.get("type") == "tool_use":
                    name, target = summarize_claude_tool(block)
                    entry = {"ts": ts, "name": name, "target": target}
                    tool_id = block.get("id")
                    if tool_id:
                        entry["id"] = tool_id
                    pending_tools.append(entry)


def handle_codex(obj):
    msg_type = obj.get("type")
    ts = obj.get("timestamp", "")[:19]

    if msg_type == "event_msg":
        p = obj.get("payload", {})
        if p.get("type") == "user_message":
            text = p.get("message", "")
            if isinstance(text, str) and len(text) > 15:
                parts = text.split("</system_instruction>")
                user_text = (parts[-1].strip() if parts else text)
                user_text = redact(user_text)
                if len(user_text) > 15:
                    flush_tools()
                    print(f"[{ts}] [user] {user_text[:800]}")
                    print("---")
                    stats["user"] += 1
        elif p.get("type") == "exec_command_end":
            command = p.get("command", [])
            cmd_str = command[-1] if command else ""
            output = p.get("aggregated_output", "")
            status = "ok"
            if "Process exited with code " in output:
                try:
                    code = int(output.split("Process exited with code ")[1].split("\n")[0])
                    if code != 0:
                        status = f"error(exit {code})"
                except (IndexError, ValueError):
                    pass
            if cmd_str:
                pending_tools.append({"ts": ts, "name": "exec", "target": cmd_str[:120], "status": status})

    elif msg_type == "response_item":
        p = obj.get("payload", {})
        if p.get("type") == "message" and p.get("role") == "assistant":
            for block in p.get("content", []):
                if block.get("type") == "output_text" and len(block.get("text", "")) > 20:
                    flush_tools()
                    print(f"[{ts}] [assistant] {redact(block['text'])[:800]}")
                    print("---")
                    stats["assistant"] += 1


def handle_cursor(obj):
    """Retained but inert — this skill does not discover Cursor sessions."""
    role = obj.get("role")
    content = obj.get("message", {}).get("content", [])
    if role == "user":
        texts = [b.get("text", "") for b in (content if isinstance(content, list) else [])
                 if b.get("type") == "text"]
        text = clean_text(" ".join(texts))
        if len(text) > 15:
            flush_tools()
            print(f"[user] {text[:800]}")
            print("---")
            stats["user"] += 1
    elif role == "assistant":
        has_text = False
        for block in (content if isinstance(content, list) else []):
            if block.get("type") == "text":
                text = block.get("text", "")
                if len(text) > 20 and text.strip() != "[REDACTED]":
                    if not has_text:
                        flush_tools()
                        has_text = True
                    print(f"[assistant] {redact(text)[:800]}")
                    print("---")
                    stats["assistant"] += 1
            elif block.get("type") == "tool_use":
                name = block.get("name", "unknown")
                inp = block.get("input", {})
                target = (
                    (inp.get("path") if isinstance(inp.get("path"), str) else None)
                    or (inp.get("file_path") if isinstance(inp.get("file_path"), str) else None)
                    or _safe_slice(inp.get("command"), 120)
                    or _safe_slice(inp.get("pattern"), 200)
                    or ""
                )
                if isinstance(target, str) and len(target) > 120:
                    target = target[:120]
                pending_tools.append({"ts": "", "name": name, "target": target})


detected = None
buffer = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    buffer.append(line)
    stats["lines"] += 1
    # Detect until found — NOT just the first 10 lines. Resumed/compacted Claude
    # transcripts can open with a queue-operation/attachment preamble longer than
    # 10 records; capping detection at 10 would default them to the codex handler
    # and emit an empty skeleton (mirrors the metadata 200-line scan fix).
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

handlers = {"claude": handle_claude, "codex": handle_codex, "cursor": handle_cursor}
handler = handlers.get(detected, handle_codex)

for line in buffer:
    try:
        handler(json.loads(line))
    except (json.JSONDecodeError, KeyError):
        stats["parse_errors"] += 1

flush_tools()
print(json.dumps({"_meta": True, **stats}))

if args.output:
    body = sys.stdout.getvalue()
    sys.stdout = _original_stdout
    with open(args.output, "w") as f:
        f.write(body)
    bytes_written = os.path.getsize(args.output)
    print(json.dumps({"_meta": True, "wrote": args.output, "bytes": bytes_written, **stats}))
