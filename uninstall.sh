#!/usr/bin/env bash
set -e

SETTINGS="$HOME/.claude/settings.json"

echo "Loop Sentinel — uninstalling..."

rm -f "$HOME/.claude/hooks/loop-sentinel.py"

python3 - <<'PYEOF'
import json, os

settings_path = os.path.expanduser("~/.claude/settings.json")
if not os.path.exists(settings_path):
    print("  settings.json not found, nothing to remove")
    exit()

with open(settings_path) as f:
    settings = json.load(f)

pre = settings.get("hooks", {}).get("PreToolUse", [])
filtered = [
    e for e in pre
    if not any("loop-sentinel" in h.get("command", "") for h in e.get("hooks", []))
]

settings.setdefault("hooks", {})["PreToolUse"] = filtered

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)

print("  Removed from ~/.claude/settings.json")
PYEOF

echo "Done."
