#!/usr/bin/env bash
# Workspace-aware notification for Claude Code
# Called by Claude Code hooks on Stop/Notification events

set -euo pipefail

# --- Detect workspace from PWD ---
REGISTRY="$HOME/.claude-workspaces/registry.json"
WS_EMOJI=""
WS_BRANCH=""
WS_SLOT=""

if [ -f "$REGISTRY" ]; then
  # Extract workspace info matching current directory
  # Use simple grep/sed since we can't assume jq is installed
  CURRENT_DIR="$(pwd)"

  # Read the registry and find matching workspace
  while IFS= read -r line; do
    if echo "$line" | grep -q '"workspace_path"'; then
      ws_path=$(echo "$line" | sed 's/.*"workspace_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
      ws_path=$(eval echo "$ws_path")  # expand ~
    fi
    if echo "$line" | grep -q '"emoji"'; then
      ws_emoji=$(echo "$line" | sed 's/.*"emoji"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    fi
    if echo "$line" | grep -q '"branch"'; then
      ws_branch=$(echo "$line" | sed 's/.*"branch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    fi
    if echo "$line" | grep -q '"slug"'; then
      ws_slug=$(echo "$line" | sed 's/.*"slug"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    fi
  done < "$REGISTRY"

  # Simple matching: check if PWD starts with any workspace_path
  # This is a simplified approach - in practice, the JSON parsing would need to be
  # workspace-by-workspace. Let's use a python one-liner for reliability.
  if command -v python3 &>/dev/null; then
    eval "$(python3 -c "
import json, os, sys
try:
    reg = json.load(open(os.path.expanduser('~/.claude-workspaces/registry.json')))
    cwd = os.getcwd()
    for slot, ws in reg.get('workspaces', {}).items():
        wp = ws.get('workspace_path', '')
        paths = [wp] + [r.get('path', '') for r in ws.get('repos', [])]
        for p in paths:
            if cwd.startswith(p):
                name = ws.get('branch') or ws.get('slug', 'workspace')
                print(f'WS_EMOJI=\"{ws.get(\"emoji\", \"\")}\"')
                print(f'WS_BRANCH=\"{name}\"')
                print(f'WS_SLOT=\"{slot}\"')
                sys.exit(0)
except Exception:
    pass
")"
  fi
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
printf '\033]9;%s: %s\007' "$TITLE" "$MESSAGE" 2>/dev/null || true
