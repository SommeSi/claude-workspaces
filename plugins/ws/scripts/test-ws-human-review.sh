#!/usr/bin/env bash
# test-ws-human-review.sh — self-check for ws-human-review.sh (fake registry, fake `code`, nothing opens).
# Usage: bash test-ws-human-review.sh   → exits 1 on first failure.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/ws-human-review.sh"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export WS_REGISTRY="$TMP/registry.json" WS_CODE_BIN="$TMP/code" FAKE_LOG="$TMP/code.log"

fail() { echo "✗ $1"; [ -n "${OUT:-}" ] && echo "--- output ---" && echo "$OUT"; exit 1; }

cat > "$TMP/code" <<'EOF2'
#!/bin/bash
if [ "$1" = "--list-extensions" ]; then echo "${FAKE_EXT:-}"; else echo "$1" >> "$FAKE_LOG"; fi
EOF2
chmod +x "$TMP/code"

WS="$TMP/ws"; OUTER="$TMP/ws/nested"
mkdir -p "$WS/back" "$OUTER/back" "$TMP/plain"
echo '{}' > "$WS/feat-x.code-workspace"
cat > "$WS_REGISTRY" <<EOF2
{ "workspaces": { "1": {"slug":"feat-x","workspace_path":"$WS"},
                  "2": {"slug":"nested","workspace_path":"$OUTER"} } }
EOF2

# 1. .code-workspace exists, extension installed -> one line, opens the file
: > "$FAKE_LOG"
OUT=$(FAKE_EXT="sommesi.claude-review" bash "$SCRIPT" "$WS/back" 2>&1) || fail "script failed"
[ "$(cat "$FAKE_LOG")" = "$WS/feat-x.code-workspace" ] || fail "should open the .code-workspace: $(cat "$FAKE_LOG")"
[ "$(echo "$OUT" | wc -l | tr -d ' ')" = 1 ] || fail "expected one line"

# 2. extension missing -> extra line, still opened
: > "$FAKE_LOG"
OUT=$(FAKE_EXT="ms-python.python" bash "$SCRIPT" "$WS/back" 2>&1) || fail "script failed"
[ -s "$FAKE_LOG" ] || fail "VS Code should still open"
[ "$(echo "$OUT" | wc -l | tr -d ' ')" = 2 ] || fail "expected two lines"
echo "$OUT" | grep -q "not installed" || fail "missing 'not installed' line"

# 3. longest prefix wins; no .code-workspace -> opens the folder
: > "$FAKE_LOG"
OUT=$(FAKE_EXT="sommesi.claude-review" bash "$SCRIPT" "$OUTER/back" 2>&1) || fail "script failed"
[ "$(cat "$FAKE_LOG")" = "$OUTER" ] || fail "nested should open its folder: $(cat "$FAKE_LOG")"

# 4. outside registry -> git top level
git -C "$TMP/plain" init -q
: > "$FAKE_LOG"
OUT=$(FAKE_EXT="sommesi.claude-review" bash "$SCRIPT" "$TMP/plain" 2>&1) || fail "script failed"
[ "$(cat "$FAKE_LOG")" = "$TMP/plain" ] || fail "git fallback: $(cat "$FAKE_LOG")"

# 5. .code-workspace untouched
[ "$(cat "$WS/feat-x.code-workspace")" = '{}' ] || fail ".code-workspace was modified"

echo "✓ ws-human-review: all checks passed"
