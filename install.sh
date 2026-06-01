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

echo "Loop Sentinel: installing..."

mkdir -p "$HOOK_DIR"

# Back up existing settings.json before mutating
if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
fi

cp "$HOOK_SRC" "$HOOK_DST"
chmod +x "$HOOK_DST"

python3 - <<'PYEOF'
import json, os, sys

settings_path = os.path.expanduser("~/.claude/settings.json")
hook_cmd = "python3 " + os.path.expanduser("~/.claude/hooks/loop-sentinel.py")

settings = {}
if os.path.exists(settings_path):
    try:
        with open(settings_path) as f:
            settings = json.load(f)
    except json.JSONDecodeError:
        print(f"  WARNING: {settings_path} is not valid JSON.")
        print("  Refusing to overwrite. Fix the file by hand or remove it, then rerun install.")
        sys.exit(1)

hooks = settings.setdefault("hooks", {})
pre = hooks.setdefault("PreToolUse", [])

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
echo "Verify install:"
echo "  cat ~/.claude/settings.json"
echo ""
echo "Thresholds (edit hooks/loop-sentinel.py to adjust):"
echo "  Identical loop: 5 calls with same args in 60s  blocked"
echo "  Thrash loop:    15 calls any args in 120s      blocked"
echo ""
echo "To uninstall: bash uninstall.sh"
