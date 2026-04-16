#!/bin/bash
# ws-color.sh — Apply workspace color to current terminal
# Usage: ws-color [workspace_path]
# If no argument, detects workspace from PWD.

set -euo pipefail

REGISTRY="$HOME/.claude-workspaces/registry.json"

if [ ! -f "$REGISTRY" ]; then
  exit 0
fi

eval "$(python3 -c "
import json, os
try:
    reg = json.load(open(os.path.expanduser('~/.claude-workspaces/registry.json')))
    cwd = '${1:-}' or os.getcwd()
    best_len = 0
    best = None
    for slot, ws in reg.get('workspaces', {}).items():
        wp = ws.get('workspace_path', '')
        paths = [wp] + [r.get('path', '') for r in ws.get('repos', [])]
        for p in paths:
            if p and cwd.startswith(p) and len(p) > best_len:
                best_len = len(p)
                best = ws
                best['slot'] = slot
    if best:
        print(f'WS_COLOR={best[\"color\"]!r}')
        print(f'WS_EMOJI={best[\"emoji\"]!r}')
        print(f'WS_BRANCH={best.get(\"branch\", best.get(\"slug\", \"\"))!r}')
        print(f'WS_SLOT={best[\"slot\"]!r}')
except Exception:
    pass
" 2>/dev/null)" 2>/dev/null || true

if [ -n "${WS_COLOR:-}" ]; then
  # Detect TTY
  TTY_DEV="/dev/$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')" 2>/dev/null || TTY_DEV=""

  if [ -n "$TTY_DEV" ] && [ -w "$TTY_DEV" ]; then
    printf '\033]11;%s\007' "$WS_COLOR" > "$TTY_DEV"
    printf '\033]1;%s %s [w%s]\007' "$WS_EMOJI" "$WS_BRANCH" "$WS_SLOT" > "$TTY_DEV"
    printf '\033]0;%s %s [w%s]\007' "$WS_EMOJI" "$WS_BRANCH" "$WS_SLOT" > "$TTY_DEV"
  else
    printf '\033]11;%s\007' "$WS_COLOR"
    printf '\033]1;%s %s [w%s]\007' "$WS_EMOJI" "$WS_BRANCH" "$WS_SLOT"
    printf '\033]0;%s %s [w%s]\007' "$WS_EMOJI" "$WS_BRANCH" "$WS_SLOT"
  fi
fi
