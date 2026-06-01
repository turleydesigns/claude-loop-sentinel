#!/usr/bin/env bash
# Smoke tests that prove Loop Sentinel actually blocks loops.
# Pipes synthetic PreToolUse payloads to the hook and asserts on exit codes.

set -u
HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hooks/loop-sentinel.py"
SID="test-$(date +%s%N)"
TMP_LOG="/tmp/.cls-${SID:0:16}.log"
PASS=0
FAIL=0

cleanup() { rm -f "$TMP_LOG"; }
trap cleanup EXIT

emit() {
  local tool="$1" args="$2"
  echo "{\"session_id\":\"$SID\",\"tool_name\":\"$tool\",\"tool_input\":$args}" | python3 "$HOOK" >/dev/null 2>&1
  echo $?
}

assert_eq() {
  local desc="$1" want="$2" got="$3"
  if [ "$want" = "$got" ]; then
    echo "  PASS: $desc (exit=$got)"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc (want exit=$want, got exit=$got)"
    FAIL=$((FAIL+1))
  fi
}

echo "Test 1: first call passes through"
exit_code=$(emit "Bash" '{"command":"ls"}')
assert_eq "single Bash call" "0" "$exit_code"

echo
echo "Test 2: identical loop blocks at call 6 (limit=5)"
cleanup
SID="test-id-$(date +%s%N)"
TMP_LOG="/tmp/.cls-${SID:0:16}.log"
for i in 1 2 3 4 5; do
  ec=$(emit "Bash" '{"command":"npm test"}')
  assert_eq "call $i below limit" "0" "$ec"
done
ec=$(emit "Bash" '{"command":"npm test"}')
assert_eq "call 6 BLOCKED" "2" "$ec"

echo
echo "Test 3: thrash loop blocks (15x same tool, varying args)"
cleanup
SID="test-th-$(date +%s%N)"
TMP_LOG="/tmp/.cls-${SID:0:16}.log"
for i in $(seq 1 15); do
  ec=$(emit "Bash" "{\"command\":\"echo $i\"}")
  if [ "$i" -lt 15 ]; then
    assert_eq "thrash call $i below limit" "0" "$ec"
  fi
done
ec=$(emit "Bash" '{"command":"echo final"}')
assert_eq "thrash call 16 BLOCKED" "2" "$ec"

echo
echo "Test 4: read-only tools are skipped (never blocked)"
cleanup
SID="test-safe-$(date +%s%N)"
TMP_LOG="/tmp/.cls-${SID:0:16}.log"
for i in 1 2 3 4 5 6 7; do
  ec=$(emit "Read" '{"file_path":"/etc/hosts"}')
  assert_eq "Read call $i (safe)" "0" "$ec"
done

echo
echo "Test 5: different sessions are isolated"
cleanup
SID="test-sa-$(date +%s%N)"
TMP_LOG="/tmp/.cls-${SID:0:16}.log"
for i in 1 2 3 4 5; do
  emit "Bash" '{"command":"x"}' >/dev/null
done
# different session, identical args, should pass
SID2="test-sb-$(date +%s%N)"
echo "{\"session_id\":\"$SID2\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"x\"}}" | python3 "$HOOK" >/dev/null 2>&1
ec=$?
rm -f "/tmp/.cls-${SID2:0:16}.log"
assert_eq "session B call 1 (isolated)" "0" "$ec"

echo
echo "Test 6: block payload includes JSON with decision:block"
cleanup
SID="test-msg-$(date +%s%N)"
TMP_LOG="/tmp/.cls-${SID:0:16}.log"
for i in 1 2 3 4 5; do emit "Bash" '{"command":"y"}' >/dev/null; done
out=$(echo "{\"session_id\":\"$SID\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"y\"}}" | python3 "$HOOK")
if echo "$out" | python3 -c 'import sys,json; d=json.load(sys.stdin); assert d["decision"]=="block"; print("ok")' >/dev/null 2>&1; then
  echo "  PASS: block payload is valid JSON with decision=block"
  PASS=$((PASS+1))
else
  echo "  FAIL: block payload malformed: $out"
  FAIL=$((FAIL+1))
fi

echo
echo "======================================="
echo "  $PASS passed, $FAIL failed"
echo "======================================="
[ "$FAIL" -eq 0 ]
