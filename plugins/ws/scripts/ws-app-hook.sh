#!/bin/bash
# ws-app-hook.sh — Claude desktop app / `claude -w` bridge.
#
# Wired as BOTH WorktreeCreate and WorktreeRemove hooks. The WorktreeCreate
# hook replaces `git worktree add` entirely: whatever path we print on stdout
# becomes the session cwd — so we hand back the multi-repo workspace dir.
#
# Input (stdin JSON): {"hook_event_name": "...", "cwd": "<project root>", "name": "<worktree name>", ...}
# stdout = the workspace path ONLY. Everything else goes to stderr.

set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)
LOG="$HOME/.claude-workspaces/app-hook.log"
mkdir -p "$(dirname "$LOG")"
echo "$(date '+%F %T') $INPUT" >> "$LOG"   # ponytail: raw log, lets us see WorktreeRemove's real fields

field() { python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d.get('$1') or '')" "$INPUT"; }
EVENT=$(field hook_event_name)

case "$EVENT" in
  WorktreeCreate)
    PROJECT_ROOT=$(git -C "$(field cwd)" rev-parse --show-toplevel)
    BRANCH=$(field name)
    [ -n "$BRANCH" ] || { echo "ws-app-hook: no worktree name" >&2; exit 1; }

    eval "$(bash "$SCRIPT_DIR/ws-preflight.sh" "$PROJECT_ROOT" | python3 -c '
import json, sys, shlex
d = json.load(sys.stdin)
if "error" in d: sys.exit("ws-app-hook: preflight " + d["error"])
for k in ("free_slot", "color", "emoji", "workspaces_root"):
    print(f"{k.upper()}={shlex.quote(str(d[k]))}")
')"
    WS_PATH="$WORKSPACES_ROOT/$(echo "$BRANCH" | tr '/' '-')"

    bash "$SCRIPT_DIR/ws-create.sh" "$WS_PATH" "$FREE_SLOT" "$BRANCH" "$COLOR" "$EMOJI" "$PROJECT_ROOT" none "" 1>&2
    echo "$WS_PATH"
    ;;

  WorktreeRemove)
    # Field name not documented reliably — accept the usual suspects.
    WS_PATH=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
print(d.get('worktree_path') or d.get('path') or (d.get('worktree') or {}).get('path') or '')" "$INPUT")
    [ -n "$WS_PATH" ] || { echo "ws-app-hook: no path in WorktreeRemove input" >&2; exit 1; }
    SLOT=$(python3 -c "
import json, os, sys
reg = json.load(open(os.path.expanduser('~/.claude-workspaces/registry.json')))
print(next((s for s, w in reg['workspaces'].items() if w.get('workspace_path') == sys.argv[1]), ''))" "$WS_PATH")
    [ -n "$SLOT" ] || { echo "ws-app-hook: $WS_PATH not in registry, skipping" >&2; exit 0; }
    bash "$SCRIPT_DIR/ws-destroy.sh" "$WS_PATH" "$SLOT" 1>&2
    ;;
esac
