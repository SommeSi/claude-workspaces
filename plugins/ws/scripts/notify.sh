#!/usr/bin/env bash
# Workspace-aware notification for Claude Code
# Called by Claude Code hooks on Stop/Notification events
#
# Usage: notify.sh [message]
# The message is typically $CLAUDE_HOOK_RESPONSE from a prompt hook summary.

set -euo pipefail

MESSAGE="${1:-}"

# --- Detect workspace from PWD ---
REGISTRY="$HOME/.claude-workspaces/registry.json"
WS_EMOJI=""
WS_SLUG=""
WS_BRANCH=""
WS_SLOT=""
WS_GOAL=""

if [ -f "$REGISTRY" ] && command -v python3 &>/dev/null; then
  eval "$(python3 -c "
import json, os, re
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
        print(f'WS_EMOJI={best_ws.get(\"emoji\", \"\")!r}')
        print(f'WS_SLUG={best_ws.get(\"slug\", \"\")!r}')
        print(f'WS_BRANCH={best_ws.get(\"branch\") or best_ws.get(\"slug\", \"\")!r}')
        print(f'WS_SLOT={best_slot!r}')
        wp = best_ws.get('workspace_path', '')
        claude_md = os.path.join(wp, 'CLAUDE.local.md')
        if os.path.isfile(claude_md):
            content = open(claude_md).read()
            m = re.search(r'## Goal of this workspace\s*\n+(.+)', content)
            if m:
                print(f'WS_GOAL={m.group(1).strip()[:80]!r}')
except Exception:
    pass
" 2>/dev/null)" 2>/dev/null || true
fi

# --- Build title: emoji + slug (worktree name) ---
if [ -n "$WS_EMOJI" ]; then
  TITLE="$WS_EMOJI ${WS_SLUG:-Claude Code}"
else
  TITLE="${WS_SLUG:-Claude Code}"
fi

# --- Build message: summary from prompt hook, fallback to goal ---
if [ -z "$MESSAGE" ] && [ -n "$WS_GOAL" ]; then
  MESSAGE="$WS_GOAL"
fi
[ -z "$MESSAGE" ] && MESSAGE="Done"

# --- Send notification (platform-specific) ---
case "$(uname -s)" in
  Darwin)
    if command -v terminal-notifier &>/dev/null; then
      terminal-notifier \
        -title "$TITLE" \
        -message "$MESSAGE" \
        -sound Hero \
        -group "claude-${WS_SLUG:-default}" \
        >/dev/null 2>&1 || true
    else
      osascript -e "display notification \"$MESSAGE\" with title \"$TITLE\" sound name \"Hero\"" 2>/dev/null || true
    fi
    ;;
  Linux)
    if command -v notify-send &>/dev/null; then
      notify-send "$TITLE" "$MESSAGE" 2>/dev/null || true
    fi
    ;;
esac

# --- OSC 9 terminal notification as fallback ---
TTY_DEV="/dev/$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')"
if [ -w "$TTY_DEV" ]; then
  printf '\033]9;%s: %s\007' "$TITLE" "$MESSAGE" > "$TTY_DEV" 2>/dev/null || true
else
  printf '\033]9;%s: %s\007' "$TITLE" "$MESSAGE" 2>/dev/null || true
fi
