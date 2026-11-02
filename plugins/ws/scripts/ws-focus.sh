#!/usr/bin/env bash
# ws-focus.sh — bring back the window of a Claude session (click on its macOS notification).
#
# Usage: ws-focus.sh wezterm <pane id> | vscode <workspace or repo path> | desktop | app <name>
#        ws-focus.sh notify <title> <message> <group> <target...>   show it, then focus on click
#
# WezTerm can raise a tab (`cli activate-pane`) but not a window: the pane emits a user var and
# ~/.wezterm.lua answers with window:focus() (handler added by ws-update.sh; without it the app
# still comes forward, on its last window).
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
WZ=/Applications/WezTerm.app/Contents/MacOS/wezterm
case "${1:-}" in
  wezterm)
    open -a WezTerm
    "$WZ" cli activate-pane --pane-id "$2" 2>/dev/null
    TTY=$("$WZ" cli list --format json 2>/dev/null | python3 -c "
import json, sys
print(next((p['tty_name'] for p in json.load(sys.stdin) if str(p['pane_id']) == sys.argv[1]), ''))" "$2")
    [ -w "$TTY" ] && printf '\033]1337;SetUserVar=ws_focus=%s\007' "$(date +%s | base64)" > "$TTY"
    ;;
  vscode)
    F=$(ls "$2"/*.code-workspace 2>/dev/null | head -1)
    open -a "Visual Studio Code" "${F:-$2}"
    ;;
  desktop) open -a Claude ;;
  app) open -a "$2" ;;
  notify)
    TITLE=$2 MESSAGE=$3 GROUP=$4
    shift 4
    # Stable path for the keyboard shortcut: jumps to the latest notification without the mouse
    { echo '#!/bin/bash'; printf 'pkill -f -- %q\n' "--group $GROUP --sound"
      printf 'exec /bin/bash %q' "${BASH_SOURCE[0]}"; printf ' %q' "$@"; echo; } > "$HOME/.claude-workspaces/focus-last.sh"
    ANSWER=$(alerter --title "$TITLE" --message "$MESSAGE" --group "$GROUP" --sound Hero --timeout 3600)
    case "$ANSWER" in
      ""|@TIMEOUT|@CLOSED) ;;
      *) exec /bin/bash "${BASH_SOURCE[0]}" "$@" ;;
    esac
    ;;
esac
