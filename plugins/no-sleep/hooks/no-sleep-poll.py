"""PreToolUse(Bash): no waiting by sleeping in the foreground.

A background command wakes the session when it exits, and Monitor wakes it when a condition holds,
so a guessed sleep or a polling loop only wastes time. Reads shell text, not a parsed command.
"""

import json
import re
import sys

UNIT = {"": 1, "s": 1, "m": 60, "h": 3600}
CMD_START = r"(?:^|[;&|({!\n]|\bdo\b|\bthen\b|\belse\b)\s*"
SLEEP = re.compile(CMD_START + r"(?:(?:while|until|time)\s+|timeout\s+\S+\s+)*sleep\s+(\d+(?:\.\d+)?)([smh]?)\b")
LOOP = re.compile(CMD_START + r"(until|while|for)\b")
SHELL_C = re.compile(r"\b(?:ba|z|da)?sh\s+(?:-\w+\s+)*-\w*c\s+(?:'([^']*)'|\"((?:[^\"\\]|\\.)*)\")")
SHELL = re.compile(r"(?<![\w.-])(?:ba|z|da)?sh\b(?!\.)")
HEREDOC_WORD = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_]\w*)\1")
WATCH = re.compile(r"\bgh\s+(?:pr\s+checks\b[^;&|\n]*--watch|run\s+watch)\b")

REASON = """Waiting by sleeping in the foreground. Get notified instead:
- Something that finishes on its own (tests, build, runner, script): Bash with run_in_background, no sleep; the session is woken when it exits.
- CI: run `gh pr checks <n> --watch --fail-fast` with run_in_background.
- A condition (server up, log line, file written): Monitor, e.g. until `nc -z 127.0.0.1 <port>`, or until `grep -q "Ready" <log>`.
- A process that pauses for your input (a runner waiting for a verdict file): start it in the background, then Monitor its output until the line it prints when it starts waiting, or its exit.
A sleep of up to 3 s outside a loop (kill; sleep 1; ps) is fine."""


def blank(text, start, end):
    """Spaces over text[start:end], keeping newlines, so positions still line up with the original."""
    return text[:start] + re.sub(r"[^\n]", " ", text[start:end]) + text[end:]


def scan(cmd):
    """Blank quoted strings, `#` comments and heredoc bodies, keeping the length.

    Returns the blanked text and each heredoc body as (start, end, fed_to_shell). One pass, so a quote
    inside a body and a `<<` inside quotes are both read for what they are.
    """
    out, bodies, pending, arith = cmd, [], [], 0
    i, n = 0, len(cmd)
    while i < n:
        c = cmd[i]
        if c == "\\":
            i += 2
        elif c == "'":
            j = cmd.find("'", i + 1)
            j = n if j < 0 else j
            out, i = blank(out, i + 1, j), j + 1
        elif c == '"':
            j = i + 1
            while j < n and cmd[j] != '"':
                j += 2 if cmd[j] == "\\" else 1
            out, i = blank(out, i + 1, min(j, n)), j + 1
        elif c == "#" and (i == 0 or cmd[i - 1] in " \t\n;&|("):
            j = cmd.find("\n", i)
            j = n if j < 0 else j
            out, i = blank(out, i, j), j
        elif cmd.startswith("$((", i):
            arith, i = arith + 1, i + 3
        elif arith and cmd.startswith("))", i):
            arith, i = arith - 1, i + 2
        elif cmd.startswith("<<<", i):
            i += 3
        elif cmd.startswith("<<", i) and not arith and (word := HEREDOC_WORD.match(cmd, i)):
            line_start = out.rfind("\n", 0, i) + 1
            fed_to_shell = bool(SHELL.search(re.split(r"[;&|]", out[line_start:i])[-1]))
            pending.append((word.group(2), fed_to_shell))
            i = word.end()
        elif c == "\n" and pending:
            for delim, fed_to_shell in pending:
                close = re.compile(r"^[ \t]*" + re.escape(delim) + r"[ \t]*$", re.M).search(cmd, i + 1)
                if not close:
                    break
                bodies.append((i + 1, close.start(), fed_to_shell))
                out, i = blank(out, i + 1, close.start()), close.end()
            pending = []
            if i < n and cmd[i] == "\n":
                i += 1
        else:
            i += 1
    return out, bodies


def loop_spans(words):
    """(start, end) of each loop, from its keyword to its matching `done`."""
    spans = []
    for m in LOOP.finditer(words):
        depth, end = 0, len(words)
        for t in re.finditer(r"\b(do|done)\b", words[m.end() :]):
            if t.group(1) == "do":
                depth += 1
            else:
                depth -= 1
                if depth <= 0:
                    end = m.end() + t.end()
                    break
        spans.append((m.start(), end))
    return spans


def waits(cmd, depth=0):
    """True when the command waits by sleeping: in a loop, over 3 s in all, or a foreground gh watch."""
    words, bodies = scan(cmd)
    if depth < 2:
        for start, end, fed_to_shell in bodies:
            if fed_to_shell and waits(cmd[start:end], depth + 1):
                return True
        for m in SHELL_C.finditer(cmd):
            if not words[m.start()].isspace():
                inner = m.group(1) if m.group(1) is not None else re.sub(r"\\(.)", r"\1", m.group(2))
                if waits(inner, depth + 1):
                    return True
    if WATCH.search(words):
        return True
    sleeps = list(SLEEP.finditer(words))
    if sum(float(s.group(1)) * UNIT[s.group(2)] for s in sleeps) > 3:
        return True
    spans = loop_spans(words)
    return any(a <= s.start(1) < b for s in sleeps for a, b in spans)


def main():
    try:
        inp = json.load(sys.stdin).get("tool_input")
    except (ValueError, AttributeError):
        return
    if not isinstance(inp, dict) or not isinstance(inp.get("command"), str) or inp.get("run_in_background"):
        return
    if not waits(inp["command"]):
        return
    decision = {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": REASON}
    print(json.dumps({"hookSpecificOutput": decision}))


main()
