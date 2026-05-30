#!/usr/bin/env bash
# Loop Sentinel installer for Claude Code
# Adds a PreToolUse hook that blocks runaway agent loops.
# Requires: Python 3.8+, Claude Code with hooks support

set -e

HOOK_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SRC="$SCRIPT_DIR/hooks/loop-sentinel.py"
HOOK_DST="$HOOK_DIR/loop-sentinel.py"

echo "Loop Sentinel — installing..."

# Create hooks directory
mkdir -p "$HOOK_DIR"

# Copy hook script
cp "$HOOK_SRC" "$HOOK_DST"
chmod +x "$HOOK_DST"

# Wire into settings.json using Python (handles existing hooks cleanly)
python3 - <<'PYEOF'
import json, os, sys

settings_path = os.path.expanduser("~/.claude/settings.json")
hook_cmd = "python3 " + os.path.expanduser("~/.claude/hooks/loop-sentinel.py")

if os.path.exists(settings_path):
    with open(settings_path) as f:
        settings = json.load(f)
else:
    settings = {}

hooks = settings.setdefault("hooks", {})
pre = hooks.setdefault("PreToolUse", [])

# Check if already installed
for entry in pre:
    for h in entry.get("hooks", []):
        if "loop-sentinel" in h.get("command", ""):
            print("  Already installed in settings.json")
            sys.exit(0)

pre.append({
    "matcher": "",
    "hooks": [{"type": "command", "command": hook_cmd}]
})

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)

print("  Wired into ~/.claude/settings.json")
PYEOF

echo ""
echo "Done. Loop Sentinel is active."
echo ""
echo "Thresholds (edit hooks/loop-sentinel.py to adjust):"
echo "  Identical loop: 5 calls with same args in 60s  → blocked"
echo "  Thrash loop:    15 calls any args in 120s       → blocked"
echo ""
echo "To uninstall: bash uninstall.sh"
