#!/usr/bin/env bash
# Workspace-aware notification for Claude Code
# Called by Claude Code hooks on Stop/Notification events
#
# Usage: notify.sh [message]
# The message is typically $CLAUDE_HOOK_RESPONSE from a prompt hook summary.

set -euo pipefail

# Ensure Homebrew tools are in PATH (macOS)
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Read hook JSON from stdin (Claude Code pipes it to each hook command)
HOOK_JSON=$(cat)

# Extract last_assistant_message and trim to first sentence (max 80 chars)
MESSAGE=""
if [ -n "$HOOK_JSON" ] && command -v jq &>/dev/null; then
  RAW=$(echo "$HOOK_JSON" | jq -r '.last_assistant_message // empty' 2>/dev/null)
  if [ -n "$RAW" ] && command -v python3 &>/dev/null; then
    MESSAGE=$(echo "$RAW" | python3 -c "
import sys, re
t = sys.stdin.read().strip()
# Remove workspace badge line (e.g. emoji **[wN] slug**)
t = re.sub(r'^.*?\[w\d+\][^\n]*\n*', '', t, count=1).strip()
# Strip markdown formatting
t = re.sub(r'[*#\x60|]', '', t)
t = re.sub(r'[\[\]]', '', t)
t = ' '.join(t.split())
# First sentence, max 80 chars
m = re.match(r'(.{0,80}[.!?])', t)
print(m.group(1) if m else t[:80])
" 2>/dev/null) || true
  fi
fi

# Fallback to $1 if provided (backward compat with prompt hooks)
[ -z "$MESSAGE" ] && MESSAGE="${1:-}"

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
    if grep -qi microsoft /proc/version 2>/dev/null; then
      # WSL — use PowerShell to send Windows toast notification
      powershell.exe -NoProfile -Command "
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime] | Out-Null
        \$xml = [Windows.Data.Xml.Dom.XmlDocument]::new()
        \$xml.LoadXml('<toast><visual><binding template=\"ToastText02\"><text id=\"1\">$TITLE</text><text id=\"2\">$MESSAGE</text></binding></visual><audio src=\"ms-winsoundevent:Notification.Default\"/></toast>')
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Claude Code').Show([Windows.UI.Notifications.ToastNotification]::new(\$xml))
      " 2>/dev/null || true
    elif command -v notify-send &>/dev/null; then
      # Native Linux
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
