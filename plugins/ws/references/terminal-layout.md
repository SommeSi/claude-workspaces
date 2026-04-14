# Terminal Layout

## Configuration

Add a `terminal` section to `.claude-workspaces.json` to enable automatic terminal layout:

```json
{
  "repos": [...],
  "terminal": {
    "type": "wezterm",
    "fullscreen": true,
    "claude_tab": true,
    "panes": [
      { "cwd": "front", "cmd": "bun run dev", "position": "top-left" },
      { "cwd": "back", "cmd": "bin/dev", "position": "top-right" },
      { "cwd": ".", "cmd": null, "position": "bottom-left" },
      { "cwd": "back", "cmd": "bin/jobs start", "position": "bottom-right" }
    ]
  }
}
```

### Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `type` | string | `null` | Terminal emulator. Only `"wezterm"` is supported. `null` = no layout. |
| `fullscreen` | bool | `true` | Put the new window into native macOS fullscreen (its own Space). |
| `claude_tab` | bool | `true` | Open a second tab with a Claude Code session auto-prompted to read `CLAUDE.local.md`. |
| `panes` | array | `[]` | List of panes (max 4, arranged as 2x2 grid). |

### Pane fields

| Field | Type | Description |
|-------|------|-------------|
| `cwd` | string | Working directory relative to workspace root. `"."` = workspace root, `"back"` = `<workspace>/back`, etc. |
| `cmd` | string\|null | Command to run in the pane. `null` = just `cd` + `clear`. |
| `position` | string | One of: `top-left`, `top-right`, `bottom-left`, `bottom-right`. |

### Variable substitution in `cmd`

- `$SLOT` → slot number
- `$BRANCH` → branch name
- `$SLUG` → workspace slug
- `$PORT` → port for the first repo
- `$WORKSPACE_PATH` → workspace root path
- `$<REPO_NAME>_PORT` → port for a specific repo (e.g. `$BACK_PORT`)

## WezTerm Implementation

Uses `wezterm cli` to create panes and send commands.

### Creating the layout

```bash
WEZTERM_CLI="/Applications/WezTerm.app/Contents/MacOS/wezterm"

# 1. Spawn first pane in a NEW WINDOW
TL=$($WEZTERM_CLI cli spawn --new-window --cwd "<workspace_path>/<tl.cwd>")

# 2. Get the window ID for subsequent tabs
WINDOW_ID=$($WEZTERM_CLI cli list --format json | python3 -c "
import json, sys
entries = json.load(sys.stdin)
match = [e for e in entries if str(e['pane_id']) == '$TL']
print(match[0]['window_id'] if match else '')
")

# 3. Split into 2x2 grid
TR=$($WEZTERM_CLI cli split-pane --pane-id $TL --right --percent 50 --cwd "<workspace_path>/<tr.cwd>")
BL=$($WEZTERM_CLI cli split-pane --pane-id $TL --bottom --percent 50 --cwd "<workspace_path>/<bl.cwd>")
BR=$($WEZTERM_CLI cli split-pane --pane-id $TR --bottom --percent 50 --cwd "<workspace_path>/<br.cwd>")

# 4. Send commands to each pane
$WEZTERM_CLI cli send-text --pane-id $TL --no-paste "clear && <tl.cmd>\n"
$WEZTERM_CLI cli send-text --pane-id $TR --no-paste "clear && <tr.cmd>\n"
$WEZTERM_CLI cli send-text --pane-id $BL --no-paste "clear\n"
$WEZTERM_CLI cli send-text --pane-id $BR --no-paste "clear && <br.cmd>\n"
```

### Claude tab (optional)

```bash
# 5. Open a Claude Code tab in the same window
CLAUDE_PANE=$($WEZTERM_CLI cli spawn --window-id $WINDOW_ID --cwd "<workspace_path>")
$WEZTERM_CLI cli send-text --pane-id $CLAUDE_PANE --no-paste "clear && claude --name \"<branch> [w<slot>]\"\n"
# Wait for Claude to boot, then send initial prompt
sleep 3
$WEZTERM_CLI cli send-text --pane-id $CLAUDE_PANE --no-paste "Lis CLAUDE.local.md et resume le contexte de ce workspace.\n"
```

### Fullscreen (optional, macOS only)

```bash
# 6. Native macOS fullscreen via AppleScript (creates its own Space)
sleep 0.5
osascript -e '
  tell application "WezTerm" to activate
  delay 0.3
  tell application "System Events"
    tell process "WezTerm"
      set value of attribute "AXFullScreen" of window 1 to true
    end tell
  end tell
'
```

### Closing the layout

Used by `/workspace:finish` during cleanup:

```bash
# Close WezTerm window by matching tab title containing [w<slot>]
osascript -e '
  tell application "System Events"
    if exists process "WezTerm" then
      tell process "WezTerm"
        repeat with w in windows
          try
            if (name of w) contains "[w<slot>]" then
              click (first button of w whose subrole is "AXCloseButton")
            end if
          end try
        end repeat
      end tell
    end if
  end tell
'
```

## Future Terminal Support

The `type` field allows adding support for other terminals:
- `"tmux"` — tmux split-window / send-keys
- `"iterm2"` — iTerm2 AppleScript API
- `"kitty"` — kitty remote control

Each implementation follows the same pattern: create window, split panes, send commands.
