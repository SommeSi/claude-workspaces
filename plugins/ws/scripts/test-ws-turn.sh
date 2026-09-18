#!/usr/bin/env bash
# test-ws-turn.sh — self-check for ws-turn.sh (per-turn recap of edited files).
# Usage: bash test-ws-turn.sh   → exits 1 on first failure.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TURN="$HERE/ws-turn.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export WS_TURN_DIR="$TMP/state"

fail() { echo "✗ $1"; echo "--- output ---"; echo "${OUT:-}"; exit 1; }
record() { # record <abs_file> [session] — as PostToolUse:Edit would
  printf '{"session_id":"%s","cwd":"%s","tool_name":"Edit","tool_input":{"file_path":"%s"}}' \
    "${2:-s1}" "$(dirname "$1")" "$1" | bash "$TURN" record
}
recap() { printf '{"session_id":"%s","cwd":"%s"}' "${2:-s1}" "$1" | bash "$TURN" recap; }
has() { echo "$OUT" | grep -qF -- "$1" || fail "expected: $1"; }
hasnt() { echo "$OUT" | grep -qF -- "$1" && fail "unexpected: $1"; true; }

# --- Workspace with one repo "back" ---
WS="$TMP/ws"
mkdir -p "$WS/back"
printf '# Workspace\n\n## Workspace info\n' > "$WS/CLAUDE.local.md"
git -C "$WS/back" init -q
for f in edited.rb gone.rb reverted.rb untouched.rb; do echo v1 > "$WS/back/$f"; done
git -C "$WS/back" add . && git -C "$WS/back" -c user.email=t@t -c user.name=t commit -qm init

# Dirty before the turn, and not touched by Claude → must not be listed
echo pre > "$WS/back/untouched.rb"

# Claude's turn: edits 4 files (one twice), one of them ends up back as committed
echo v2 > "$WS/back/edited.rb";      OUT=$(record "$WS/back/edited.rb")
[ -z "$OUT" ] || fail "record must print nothing"
echo v3 > "$WS/back/edited.rb";      record "$WS/back/edited.rb"
echo new > "$WS/back/added.rb";      record "$WS/back/added.rb"
rm "$WS/back/gone.rb";               record "$WS/back/gone.rb"
echo tmp > "$WS/back/reverted.rb";   record "$WS/back/reverted.rb"
git -C "$WS/back" checkout -q -- reverted.rb

OUT=$(recap "$WS/back")
echo "$OUT" | python3 -c 'import json,sys; json.load(sys.stdin)["systemMessage"]' || fail "recap must be JSON with systemMessage"
has "4 fichiers modifiés ce tour"
has "M back/edited.rb"
has "A back/added.rb"
has "D back/gone.rb"
has "R back/reverted.rb"
hasnt "untouched.rb"
hasnt "vscode://"   # the UI shows raw text: no links, no markdown
[ "$(echo "$OUT" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["systemMessage"].splitlines()))')" = 5 ] \
  || fail "one line per file, no duplicate for the twice-edited file"

# State consumed → second recap prints nothing
OUT=$(recap "$WS/back")
[ -z "$OUT" ] || fail "recap without records must print nothing"

# Singular wording
echo v4 > "$WS/back/edited.rb"; record "$WS/back/edited.rb"
OUT=$(recap "$WS/back"); has "1 fichier modifié ce tour"; hasnt "fichiers"

# Cap at 12 files
for i in $(seq 1 15); do echo x > "$WS/back/f$i.rb"; record "$WS/back/f$i.rb"; done
OUT=$(recap "$WS/back")
has "15 fichiers modifiés ce tour"; has "… et 3 autres"

# Tool call without a file path → nothing recorded
printf '{"session_id":"s9","cwd":"%s","tool_name":"Bash","tool_input":{"command":"ls"}}' "$WS/back" | bash "$TURN" record
[ ! -f "$WS_TURN_DIR/s9.txt" ] || fail "no file_path must record nothing"

# Outside a workspace → no-op
mkdir -p "$TMP/elsewhere"; echo x > "$TMP/elsewhere/z.rb"
OUT=$(record "$TMP/elsewhere/z.rb" s2)
[ -z "$OUT" ] && [ ! -f "$WS_TURN_DIR/s2.txt" ] || fail "outside workspace must be a no-op"

# Garbage input → exit 0, nothing
OUT=$(echo 'not json' | bash "$TURN" recap; echo "rc=$?")
[ "$OUT" = "rc=0" ] || fail "garbage input must exit 0 silently"

echo "✓ all ws-turn checks passed"
