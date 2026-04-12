#!/usr/bin/env bash
# Workspace-aware notification for Claude Code
# Called by Claude Code hooks on Stop/Notification events

set -euo pipefail

# --- Detect workspace from PWD ---
REGISTRY="$HOME/.claude-workspaces/registry.json"
WS_EMOJI=""
WS_BRANCH=""
WS_SLOT=""

if [ -f "$REGISTRY" ] && command -v python3 &>/dev/null; then
  # Use python3 for reliable JSON parsing — matches PWD against workspace paths
  eval "$(python3 -c "
import json, os, sys
try:
    reg = json.load(open(os.path.expanduser('~/.claude-workspaces/registry.json')))
    cwd = os.getcwd()
    best_len = 0
    best_ws = None
    best_slot = None
    for slot, ws in reg.get('workspaces', {}).items():
        wp = ws.get('workspace_path', '')
        paths = [wp] + [r.get('path', '') for r in ws.get('repos', [])]
        for p in paths:
            if p and cwd.startswith(p) and len(p) > best_len:
                best_len = len(p)
                best_ws = ws
                best_slot = slot
    if best_ws:
        name = best_ws.get('branch') or best_ws.get('slug', 'workspace')
        emoji = best_ws.get('emoji', '')
        print(f'WS_EMOJI={emoji!r}')
        print(f'WS_BRANCH={name!r}')
        print(f'WS_SLOT={best_slot!r}')
except Exception:
    pass
" 2>/dev/null)" 2>/dev/null || true
fi

# --- Build notification message ---
TITLE="${WS_EMOJI:+$WS_EMOJI }${WS_BRANCH:-Claude Code}${WS_SLOT:+ [w$WS_SLOT]}"
MESSAGE="${1:-Task completed}"

# Add sound indicator
SOUND="default"

# --- Send notification (platform-specific) ---
case "$(uname -s)" in
  Darwin)
    osascript -e "display notification \"$MESSAGE\" with title \"$TITLE\" sound name \"$SOUND\"" 2>/dev/null || true
    ;;
  Linux)
    if command -v notify-send &>/dev/null; then
      notify-send "$TITLE" "$MESSAGE" 2>/dev/null || true
    fi
    ;;
esac

# --- Always send OSC 9 terminal notification as fallback ---
# Supported by WezTerm, iTerm2, Kitty, Windows Terminal
TTY_DEV="/dev/$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')"
if [ -w "$TTY_DEV" ]; then
  printf '\033]9;%s: %s\007' "$TITLE" "$MESSAGE" > "$TTY_DEV" 2>/dev/null || true
else
  printf '\033]9;%s: %s\007' "$TITLE" "$MESSAGE" 2>/dev/null || true
fi
