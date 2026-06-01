#!/usr/bin/env python3
"""
Loop Sentinel: PreToolUse hook for Claude Code.
Detects runaway agent loops before they burn tokens.

Blocks when it sees:
  - Same tool + same args called 5x in 60s  (identical loop)
  - Same tool called 15x in 120s any args   (thrash loop)

Exit code 2 = Claude Code blocks the action.
"""

import json
import sys
import os
import time
import hashlib
import tempfile

IDENTICAL_LIMIT  = 5    # same tool + same args fingerprint
IDENTICAL_WINDOW = 60   # seconds
THRASH_LIMIT     = 15   # same tool, any args
THRASH_WINDOW    = 120  # seconds

# Read-only tools are usually lower-risk than write/shell tools.
SAFE_TOOLS = {"Read", "Glob", "Grep", "LS", "TodoRead", "TaskGet", "TaskList"}


def fingerprint(tool_input: dict) -> str:
    if "command" in tool_input:
        content = str(tool_input["command"])
    elif "file_path" in tool_input:
        content = str(tool_input["file_path"])
    elif "path" in tool_input:
        content = str(tool_input["path"])
    elif "pattern" in tool_input:
        content = str(tool_input["pattern"])
    else:
        content = json.dumps(tool_input, sort_keys=True)
    return hashlib.sha256(content.encode()).hexdigest()[:16]


def log_path(session_id: str) -> str:
    return os.path.join(tempfile.gettempdir(), f".cls-{session_id[:16]}.log")


def read_window(path: str, window: int) -> list:
    if not os.path.exists(path):
        return []
    cutoff = time.time() - window
    rows = []
    try:
        with open(path) as f:
            for line in f:
                parts = line.strip().split("\t")
                if len(parts) == 3 and float(parts[0]) >= cutoff:
                    rows.append((float(parts[0]), parts[1], parts[2]))
    except Exception:
        pass
    return rows


def append(path: str, tool: str, fp: str):
    with open(path, "a") as f:
        f.write(f"{time.time():.2f}\t{tool}\t{fp}\n")


def prune(path: str, keep: int = 600):
    if not os.path.exists(path):
        return
    cutoff = time.time() - keep
    try:
        with open(path) as f:
            lines = f.readlines()
        fresh = [l for l in lines if float(l.split("\t")[0]) >= cutoff]
        if len(fresh) < len(lines):
            with open(path, "w") as f:
                f.writelines(fresh)
    except Exception:
        pass


def block(reason: str):
    print(json.dumps({"decision": "block", "reason": reason}))
    sys.exit(2)


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    tool  = payload.get("tool_name", "unknown")
    inp   = payload.get("tool_input", {})
    sid   = payload.get("session_id", "default")

    if tool in SAFE_TOOLS:
        sys.exit(0)

    fp  = fingerprint(inp)
    lp  = log_path(sid)

    prune(lp)

    identical = [c for c in read_window(lp, IDENTICAL_WINDOW) if c[1] == tool and c[2] == fp]
    thrash    = [c for c in read_window(lp, THRASH_WINDOW)    if c[1] == tool]

    append(lp, tool, fp)

    if len(identical) >= IDENTICAL_LIMIT:
        elapsed = time.time() - identical[0][0]
        block(
            f"Loop Sentinel blocked '{tool}': called {len(identical)+1}x with identical "
            f"args in {elapsed:.0f}s. This is a runaway loop. "
            f"Stop, reassess the approach, and try a different strategy."
        )

    if len(thrash) >= THRASH_LIMIT:
        elapsed = time.time() - thrash[0][0]
        block(
            f"Loop Sentinel blocked '{tool}': called {len(thrash)+1}x in {elapsed:.0f}s. "
            f"Possible thrash loop. Stop and reassess before continuing."
        )

    sys.exit(0)


if __name__ == "__main__":
    main()
