#!/usr/bin/env python3
"""safety-check.py — enforcement core for the safety-scoping skill.

Invoked by the thin shell hooks check-careful.sh (mode "bash") and
check-freeze.sh (mode "edit"). Reads the PreToolUse event JSON on stdin and the
session state under $SAFETY_STATE_DIR, and prints a PreToolUse decision:

    {"hookSpecificOutput":{"hookEventName":"PreToolUse",
                           "permissionDecision":"deny"|"ask",
                           "permissionDecisionReason":"..."}}

or "{}" (no decision -> normal permission flow) when nothing applies.

Design (Codex design + impl reviews, 2026-06-06):
  * python3 is the PRIMARY parser/resolver — never grep/sed.
  * Path comparison is canonical: realpath resolves symlinks (incl. the final
    component) and "..", so a symlink inside the boundary pointing out cannot
    smuggle a write past freeze.
  * Bash analysis splits the command into simple commands on shell control
    operators (; && || | & () ) and strips assignment prefixes + benign command
    wrappers, so composition (`true; touch out`, `FOO=x touch out`,
    `( rm out )`, `printf|tee out`) cannot hide a write.
  * Tiered: a write whose target provably resolves outside the boundary -> deny;
    write-looking syntax that cannot be proven (variables, command/process
    substitution, unparseable) -> ask; no write evidence -> allow.
  * Fail closed: while a freeze boundary is active, an unparseable/unreadable
    Edit/Write -> deny; an unparseable Bash command or malformed boundary -> ask.
  * NOT a security boundary: eval, language runtimes, alias/function, and
    variable-computed paths are out of scope (documented in SKILL.md).
"""
import json
import os
import re
import shlex
import sys

STATE_DIR = os.environ.get("SAFETY_STATE_DIR", "")
CAREFUL_FLAG = os.path.join(STATE_DIR, "careful-on")
FREEZE_FILE = os.path.join(STATE_DIR, "freeze-dir.txt")

FREEZE_INVALID = object()  # boundary file present but empty/unreadable

# --- output ---------------------------------------------------------------

def emit(decision=None, reason=""):
    if decision is None:
        sys.stdout.write("{}")
        return
    out = {"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": decision,
        "permissionDecisionReason": reason,
    }}
    sys.stdout.write(json.dumps(out, separators=(",", ":")))


def read_freeze_boundary():
    """None (no boundary) | FREEZE_INVALID (present but bad) | canonical path."""
    if not os.path.exists(FREEZE_FILE):
        return None
    try:
        with open(FREEZE_FILE, "r", encoding="utf-8") as fh:
            raw = fh.readline().rstrip("\n")
    except OSError:
        return FREEZE_INVALID
    raw = raw.rstrip("/")
    if not raw:
        return FREEZE_INVALID
    canon = canonicalize(raw)
    return canon if canon else FREEZE_INVALID


def canonicalize(path):
    if not path:
        return None
    if not os.path.isabs(path):
        path = os.path.join(os.getcwd(), path)
    return os.path.realpath(path)


def inside_boundary(target, boundary):
    if target is None or boundary is None:
        return False
    return target == boundary or target.startswith(boundary + os.sep)


def read_event():
    try:
        return json.loads(sys.stdin.read())
    except Exception:
        return None


def tool_input(event):
    ti = event.get("tool_input") if isinstance(event, dict) else None
    return ti if isinstance(ti, dict) else {}

# --- freeze (Edit/Write/NotebookEdit/MultiEdit) ---------------------------

EDIT_PATH_KEYS = ("file_path", "notebook_path", "path")


def edit_targets(ti):
    paths = []
    for k in EDIT_PATH_KEYS:
        v = ti.get(k)
        if isinstance(v, str) and v:
            paths.append(v)
    edits = ti.get("edits")
    if isinstance(edits, list):
        for e in edits:
            if isinstance(e, dict):
                p = e.get("file_path") or e.get("path")
                if isinstance(p, str) and p:
                    paths.append(p)
    return paths


def check_edit(event):
    boundary = read_freeze_boundary()
    if boundary is None:
        return emit(None)
    if boundary is FREEZE_INVALID:
        return emit("deny", "[safety-scoping/freeze] Freeze state is unreadable; "
                            "blocked. Re-run /freeze or /unfreeze.")
    ti = tool_input(event)
    targets = edit_targets(ti)
    if not targets:
        return emit("deny", "[safety-scoping/freeze] Cannot determine the edit "
                            "target; blocked because a freeze boundary is active.")
    for raw in targets:
        canon = canonicalize(raw)
        if not inside_boundary(canon, boundary):
            return emit("deny", "[safety-scoping/freeze] Blocked: %s is outside "
                                "the freeze boundary (%s/). Run /unfreeze to lift it."
                                % (canon, boundary))
    return emit(None)

# --- bash command analysis ------------------------------------------------

SAFE_RM_BASENAMES = {
    "node_modules", "dist", ".next", "__pycache__", ".cache",
    "build", ".turbo", "coverage",
}
DEST_LAST_CMDS = {"cp", "install", "rsync"}        # dest = last operand
TARGET_ALL_CMDS = {"touch", "mkdir", "ln", "truncate", "rmdir",
                   "chmod", "chown", "chgrp", "mkfifo", "mknod"}
INPLACE_EDIT = {"sed", "perl"}
WRAPPERS = {"command", "env", "builtin", "noglob", "nohup", "time",
            "exec", "stdbuf", "nice", "ionice", "sudo", "doas"}
SHELLS = {"sh", "bash", "zsh", "dash", "ksh"}
DEV_ALLOW = {"/dev/null", "/dev/stdout", "/dev/stderr", "/dev/tty", "/dev/zero"}
CONTROL_DELIMS = set(";\n|&()")
_ASSIGN_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")


def _split_segments(cmd):
    """Quote/escape-aware split into simple-command strings on unquoted control
    operators ; \\n | & ( ). Brace { } handled as standalone tokens later."""
    segs, buf = [], []
    in_s = in_d = esc = False
    for c in cmd:
        if esc:
            buf.append(c); esc = False; continue
        if c == "\\" and not in_s:
            buf.append(c); esc = True; continue
        if in_s:
            buf.append(c)
            if c == "'":
                in_s = False
            continue
        if in_d:
            buf.append(c)
            if c == '"':
                in_d = False
            continue
        if c == "'":
            in_s = True; buf.append(c); continue
        if c == '"':
            in_d = True; buf.append(c); continue
        if c in CONTROL_DELIMS:
            if buf:
                segs.append("".join(buf)); buf = []
            continue
        buf.append(c)
    if buf:
        segs.append("".join(buf))
    return [s.strip() for s in segs if s.strip()]


def _strip_prefixes(toks):
    """Drop leading VAR=val assignments and benign command wrappers (sudo, env,
    command, nohup, …) so the real command head is exposed. Also drop standalone
    grouping tokens { }."""
    toks = [t for t in toks if t not in ("{", "}")]
    i = 0
    while i < len(toks):
        t = toks[i]
        if _ASSIGN_RE.match(t):
            i += 1; continue
        if os.path.basename(t) in WRAPPERS:
            i += 1
            while i < len(toks) and toks[i].startswith("-"):
                i += 1
            continue
        break
    return toks[i:]


def _redirect_target(tok):
    """If `tok` is a write redirection, return its target ('__NEXT__' if it is
    the following token), else None. Ignores fd-dup (2>&1)."""
    body = tok
    if body and body[0].isdigit():
        body = body.lstrip("0123456789")
    if body.startswith("&>"):
        body = body[1:]
    if not body.startswith(">"):
        return None
    rest = body.lstrip(">")
    if rest.startswith("&"):
        return None
    return rest if rest else "__NEXT__"


def _has_write_syntax(seg):
    return (">" in seg or " tee " in (" " + seg + " ") or "sed -i" in seg
            or any((" %s " % c) in (" " + seg + " ")
                   for c in (DEST_LAST_CMDS | {"mv", "tee"})))


def _has_inplace_flag(toks):
    for t in toks:
        if t in ("-i", "-pi") or t.startswith("-i") or t.startswith("-pi"):
            return True
    return False


def freeze_write_violation(cmd, boundary):
    """Scan a Bash command for filesystem writes whose target resolves OUTSIDE
    `boundary`. Returns ("deny"|"ask"|"", reason)."""
    has_subst = ">(" in cmd or "<(" in cmd or "$(" in cmd or "`" in cmd
    ask_reason = ""
    saw_ask = False
    for seg in _split_segments(cmd):
        decision, reason = _analyze_segment(seg, boundary, has_subst)
        if decision == "deny":
            return "deny", reason
        if decision == "ask":
            saw_ask = True; ask_reason = reason
    return ("ask", ask_reason) if saw_ask else ("", "")


def _analyze_segment(seg, boundary, has_subst):
    try:
        toks = shlex.split(seg, posix=True)
    except ValueError:
        if _has_write_syntax(seg):
            return "ask", "could not parse a command segment to prove writes stay inside the freeze boundary"
        return "", ""
    toks = _strip_prefixes(toks)
    if not toks:
        return "", ""

    # one-level shell -c "<literal>" recursion
    head = os.path.basename(toks[0])
    if head in SHELLS:
        for j in range(1, len(toks) - 1):
            if toks[j] == "-c":
                return freeze_write_violation(toks[j + 1], boundary)

    targets = []
    ambiguous = False

    # redirections anywhere in the segment
    i = 0
    while i < len(toks):
        red = _redirect_target(toks[i])
        if red == "__NEXT__":
            if i + 1 < len(toks):
                targets.append(toks[i + 1]); i += 2; continue
        elif red is not None:
            targets.append(red)
        i += 1

    operands = [t for t in toks[1:] if not t.startswith("-")]
    if head in DEST_LAST_CMDS and operands:
        targets.append(operands[-1])
    elif head == "mv":
        targets.extend(operands)          # sources are deleted too
    elif head in TARGET_ALL_CMDS:
        targets.extend(operands)
    elif head in INPLACE_EDIT and _has_inplace_flag(toks):
        targets.extend(operands)
    elif head == "tee":
        targets.extend(operands)
    elif head in ("rm", "rmdir") and operands:
        targets.extend(operands)
    elif head in ("xargs", "find"):
        if any(os.path.basename(t) in (TARGET_ALL_CMDS | DEST_LAST_CMDS |
               {"rm", "rmdir", "tee", "mv"}) for t in toks):
            ambiguous = True

    for tok in targets:
        if tok in DEV_ALLOW or tok.startswith("/dev/fd/"):
            continue
        if _looks_unresolvable(tok) or (has_subst and ("(" in tok or tok in (">", "<"))):
            ambiguous = True; continue
        canon = canonicalize(tok)
        if canon is None:
            ambiguous = True; continue
        if not inside_boundary(canon, boundary):
            return "deny", ("write to %s is outside the freeze boundary (%s/)"
                            % (canon, boundary))

    if ambiguous:
        return "ask", "a write target could not be proven to stay inside the freeze boundary"
    return "", ""


def _looks_unresolvable(tok):
    return any(c in tok for c in ("$", "`", "*", "?", "[", "~")) or tok.startswith("(")

# --- careful (destructive command warnings) -------------------------------

def destructive_warning(cmd):
    for seg in _split_segments(cmd):
        w = _segment_destructive(seg)
        if w:
            return w
    return ""


def _segment_destructive(seg):
    try:
        toks = shlex.split(seg, posix=True)
    except ValueError:
        toks = seg.split()
    toks = _strip_prefixes(toks)
    if not toks:
        return ""
    head = os.path.basename(toks[0])
    segl = seg.lower()

    if _scan_rm_recursive(toks) and not _rm_targets_all_safe(toks):
        return "recursive delete (rm -r) — permanently removes files"
    if "drop" in segl and ("table" in segl or "database" in segl):
        return "SQL DROP — permanently deletes database objects"
    if _word(segl, "truncate") and not _is_truncate_binary(toks):
        return "SQL TRUNCATE — deletes all rows from a table"
    if head == "git":
        sub = _git_subcommand(toks)
        if sub == "push" and (_has_force(toks) or any(t.startswith("--force") for t in toks)):
            return "git force-push — rewrites remote history; collaborators may lose work"
        if sub == "reset" and "--hard" in toks:
            return "git reset --hard — discards all uncommitted changes"
        if sub in ("checkout", "restore") and "." in toks:
            return "git checkout/restore . — discards uncommitted working-tree changes"
    if head == "kubectl" and "delete" in toks:
        return "kubectl delete — removes Kubernetes resources; may impact production"
    if head == "docker":
        if "prune" in toks:
            return "docker prune — may delete containers/images/volumes"
        if "rm" in toks and _has_force(toks):
            return "docker rm -f — force-removes containers"
    return ""


def _scan_rm_recursive(toks):
    for i, t in enumerate(toks):
        if os.path.basename(t) == "rm" and _flags_have_r(toks[i + 1:]):
            return True
    return False


def _flags_have_r(rest):
    for t in rest:
        if t == "--recursive":
            return True
        if t.startswith("-") and not t.startswith("--") and ("r" in t or "R" in t):
            return True
        if not t.startswith("-"):
            break
    return False


def _rm_targets_all_safe(toks):
    operands, seen = [], False
    for t in toks:
        if os.path.basename(t) == "rm":
            seen = True; continue
        if not seen or t.startswith("-"):
            continue
        operands.append(t)
    if not operands:
        return False
    for op in operands:
        if _looks_unresolvable(op) or ".." in op.split("/"):
            return False
        if os.path.basename(op.rstrip("/")) not in SAFE_RM_BASENAMES:
            return False
    return True


def _has_force(toks):
    for t in toks:
        if t == "--force":
            return True
        if t.startswith("-") and not t.startswith("--") and "f" in t:
            return True
    return False


def _git_subcommand(toks):
    i = 1
    while i < len(toks):
        t = toks[i]
        if t in ("-C", "-c", "--git-dir", "--work-tree", "--namespace"):
            i += 2; continue
        if t.startswith("-"):
            i += 1; continue
        return t
    return ""


def _word(low, w):
    return re.search(r"\b" + re.escape(w) + r"\b", low) is not None


def _is_truncate_binary(toks):
    return "truncate" in [os.path.basename(t) for t in toks] and "-s" in toks

# --- dispatch -------------------------------------------------------------

def check_bash(event):
    careful_on = os.path.exists(CAREFUL_FLAG)
    boundary = read_freeze_boundary()
    if not careful_on and boundary is None:
        return emit(None)
    if event is None:
        return emit("ask", "[safety-scoping] Could not parse the command; proceed?")
    cmd = tool_input(event).get("command", "")
    if not isinstance(cmd, str) or not cmd:
        return emit(None)

    if boundary is FREEZE_INVALID:
        return emit("ask", "[safety-scoping/guard] Freeze state is unreadable; proceed?")
    if boundary is not None:
        decision, reason = freeze_write_violation(cmd, boundary)
        if decision == "deny":
            return emit("deny", "[safety-scoping/guard] Blocked: %s." % reason)
        if decision == "ask":
            return emit("ask", "[safety-scoping/guard] %s — proceed?" % reason)
    if careful_on:
        warn = destructive_warning(cmd)
        if warn:
            return emit("ask", "[safety-scoping/careful] Destructive: %s. Proceed?" % warn)
    return emit(None)


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    event = read_event()
    if mode == "edit":
        check_edit(event)
    elif mode == "bash":
        check_bash(event)
    else:
        emit(None)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
