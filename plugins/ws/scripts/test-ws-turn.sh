#!/usr/bin/env bash
# test-ws-turn.sh — self-check for ws-turn.sh (per-turn changed files recap).
# Usage: bash test-ws-turn.sh   → exits 1 on first failure.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TURN="$HERE/ws-turn.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export WS_TURN_DIR="$TMP/state"

fail() { echo "✗ $1"; echo "--- output ---"; echo "$OUT"; exit 1; }
hook() { # hook <mode> <cwd> [session]
  printf '{"session_id":"%s","cwd":"%s"}' "${3:-s1}" "$2" | bash "$TURN" "$1"
}
has() { echo "$OUT" | grep -qF -- "$1" || fail "expected: $1"; }
hasnt() { echo "$OUT" | grep -qF -- "$1" && fail "unexpected: $1"; true; }

# --- Workspace with one repo "back" ---
WS="$TMP/ws"
mkdir -p "$WS/back"
printf '# Workspace\n\n## Workspace info\n' > "$WS/CLAUDE.local.md"
git -C "$WS/back" init -q
for f in clean.rb gone.rb dirty_keep.rb dirty_touch.rb dirty_revert.rb; do echo v1 > "$WS/back/$f"; done
git -C "$WS/back" add . && git -C "$WS/back" -c user.email=t@t -c user.name=t commit -qm init

# Dirty before the turn
echo pre > "$WS/back/dirty_keep.rb"
echo pre > "$WS/back/dirty_touch.rb"
echo pre > "$WS/back/dirty_revert.rb"

OUT=$(hook snapshot "$WS/back")
[ -z "$OUT" ] || fail "snapshot must print nothing"

# Claude's turn
echo v2 > "$WS/back/clean.rb"
echo new > "$WS/back/added.rb"
rm "$WS/back/gone.rb"
echo again > "$WS/back/dirty_touch.rb"
git -C "$WS/back" checkout -q -- dirty_revert.rb

OUT=$(hook diff "$WS/back")
echo "$OUT" | python3 -c 'import json,sys; json.load(sys.stdin)["systemMessage"]' || fail "diff output must be JSON with systemMessage"
has "5 fichiers modifiés ce tour"
has "M [clean.rb](vscode://file$WS/back/clean.rb:1)"
has "A [added.rb](vscode://file$WS/back/added.rb:1)"
has "D gone.rb"
has "M [dirty_touch.rb]"
has "R [dirty_revert.rb]"
hasnt "dirty_keep.rb"
has "back"

# Snapshot consumed → second diff prints nothing
OUT=$(hook diff "$WS/back")
[ -z "$OUT" ] || fail "missing snapshot must print nothing"

# No change during turn → nothing
OUT=$(hook snapshot "$WS"); OUT=$(hook diff "$WS")
[ -z "$OUT" ] || fail "no change must print nothing"

# Outside a workspace → nothing, no state written
mkdir -p "$TMP/elsewhere"
OUT=$(hook snapshot "$TMP/elsewhere" s2)
[ -z "$OUT" ] && [ ! -f "$WS_TURN_DIR/s2.json" ] || fail "outside workspace must be a no-op"

# Garbage input → exit 0, nothing
OUT=$(echo 'not json' | bash "$TURN" diff; echo "rc=$?")
[ "$OUT" = "rc=0" ] || fail "garbage input must exit 0 silently"

echo "✓ all ws-turn checks passed"
