---
name: open
description: "Open (or reopen) the terminal layout for a workspace — WezTerm panes, dev servers, Claude tab. Use when the user wants to launch their dev environment, reopen after a reboot, or says 'open workspace', 'launch servers', 'open layout'."
user_invocable: true
trigger: "open workspace, launch servers, open layout, open dev, reopen, wezterm layout"
---

**Respond in the user's language.**

You are opening (or reopening) the terminal layout for an existing workspace. This creates a WezTerm window with panes running dev servers and optionally a Claude Code tab.

---

## Step 1 — Detect workspace

### 1a — Read the registry

```bash
cat ~/.claude-workspaces/registry.json 2>/dev/null || echo '{"workspaces":{},"next_slot":1}'
```

### 1b — Match current directory

```bash
pwd
```

Compare `pwd` against all `workspace_path` and `repos[].path` entries. Use longest-prefix match.

If no match is found, ask the user which workspace to open (show the list from registry).

### 1c — Load project config

```bash
cat <project_root>/.claude-workspaces.json 2>/dev/null
```

If no config exists, or if the config has no `terminal` section, tell the user:

> No terminal layout configured. Add a `terminal` section to `.claude-workspaces.json`. See the plugin docs for the format.

And stop.

### 1d — Choose launch mode

Ask the user with a select:

> How do you want to launch the servers?
> 1. WezTerm — separate terminal panes (requires WezTerm)
> 2. Background — launch servers as background processes in this Claude session

If **1** → continue to Step 2 (WezTerm flow).
If **2** → skip to Step 6 (Background flow).

If the config has a `terminal` section with `type: "wezterm"`, show option 1 first. If no `terminal` section, only show option 2.

---

## Step 2 — Check WezTerm CLI

```bash
WEZTERM_CLI="/Applications/WezTerm.app/Contents/MacOS/wezterm"
test -x "$WEZTERM_CLI" && echo "found" || echo "not found"
```

If on Linux, try:

```bash
which wezterm 2>/dev/null && echo "found" || echo "not found"
```

If WezTerm CLI is not found, stop and tell the user:

> WezTerm CLI not found. Make sure WezTerm is installed and the CLI is accessible.

---

## Step 3 — Recap and confirm

Show what will be opened:

```
Ready to open layout for workspace:

  🔴 [w4] feat/polo/disbursement-account
  Path: /Users/you/workspaces/feat-polo-disbursement-account

  Panes:
    ┌──────────────────┬──────────────────┐
    │  front            │  back            │
    │  bun run dev      │  bin/dev         │
    ├──────────────────┼──────────────────┤
    │  (terminal)       │  back            │
    │                   │  bin/jobs start  │
    └──────────────────┴──────────────────┘

  Claude tab: yes
  Fullscreen: yes

Launch? [Y/n]
```

Wait for the user's response. Accept: `y`, `yes`, `o`, `oui`, or empty (just Enter). **Anything else cancels.**

---

## Step 4 — Create the layout

See `references/terminal-layout.md` for the full WezTerm implementation details.

Execute the following in order. Run each bash command and check for errors.

### 4a — Resolve paths

For each pane in `terminal.panes`, resolve the absolute `cwd`:

- `"."` → `<workspace_path>`
- `"back"` → `<workspace_path>/back`
- `"front"` → `<workspace_path>/front`
- etc.

### 4b — Detect WezTerm CLI path

```bash
if [[ -x "/Applications/WezTerm.app/Contents/MacOS/wezterm" ]]; then
  WEZTERM_CLI="/Applications/WezTerm.app/Contents/MacOS/wezterm"
else
  WEZTERM_CLI="$(which wezterm 2>/dev/null)"
fi
echo "$WEZTERM_CLI"
```

### 4c — Spawn the window and panes

Create a new WezTerm window with the first pane (top-left), then split to create the 2x2 grid:

```bash
# Top-left pane (new window)
TL=$($WEZTERM_CLI cli spawn --new-window --cwd "<tl_cwd>")

# Get window ID
WINDOW_ID=$($WEZTERM_CLI cli list --format json | python3 -c "
import json, sys
entries = json.load(sys.stdin)
match = [e for e in entries if str(e['pane_id']) == '$TL']
print(match[0]['window_id'] if match else '')
")

# Top-right
TR=$($WEZTERM_CLI cli split-pane --pane-id $TL --right --percent 50 --cwd "<tr_cwd>")

# Bottom-left
BL=$($WEZTERM_CLI cli split-pane --pane-id $TL --bottom --percent 50 --cwd "<bl_cwd>")

# Bottom-right
BR=$($WEZTERM_CLI cli split-pane --pane-id $TR --bottom --percent 50 --cwd "<br_cwd>")
```

### 4d — Send commands

For each pane, if `cmd` is not null, send the command. Apply variable substitution first (see `references/terminal-layout.md`).

```bash
$WEZTERM_CLI cli send-text --pane-id $TL --no-paste "clear && <tl_cmd>\n"
$WEZTERM_CLI cli send-text --pane-id $TR --no-paste "clear && <tr_cmd>\n"
$WEZTERM_CLI cli send-text --pane-id $BL --no-paste "clear\n"
$WEZTERM_CLI cli send-text --pane-id $BR --no-paste "clear && <br_cmd>\n"
```

For panes with `cmd: null`, just send `clear`:

```bash
$WEZTERM_CLI cli send-text --pane-id $BL --no-paste "clear\n"
```

### 4e — Claude tab (if enabled)

If `terminal.claude_tab` is `true` (default):

```bash
CLAUDE_PANE=$($WEZTERM_CLI cli spawn --window-id $WINDOW_ID --cwd "<workspace_path>")
```

Wait a moment, then launch Claude:

```bash
sleep 1
$WEZTERM_CLI cli send-text --pane-id $CLAUDE_PANE --no-paste "clear && claude --name \"<branch> [w<slot>]\"\n"
```

Wait for Claude to boot, then send initial context prompt:

```bash
sleep 3
$WEZTERM_CLI cli send-text --pane-id $CLAUDE_PANE --no-paste "Lis CLAUDE.local.md et resume le contexte de ce workspace.\n"
```

### 4f — Fullscreen (if enabled, macOS only)

If `terminal.fullscreen` is `true` (default) and we're on macOS:

```bash
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

---

## Step 5 — Summary

```
✓ Layout opened!

  🔴 [w4] feat/polo/disbursement-account

  Panes:
    top-left:     front — bun run dev
    top-right:    back — bin/dev
    bottom-left:  (terminal)
    bottom-right: back — bin/jobs start

  Claude tab: launched
  Fullscreen: yes
```

---

## Step 6 — Background mode (alternative to WezTerm)

Launch servers as background processes in the current Claude session. No WezTerm required.

### 6a — Detect servers to launch

Read the config to find what commands to run. If a `terminal` section exists, use the `panes` commands. Otherwise, detect from the project:

- **Rails**: look for `bin/dev`, `bin/rails server`, or `Procfile` in back repo
- **Next.js**: look for `bun run dev`, `npm run dev` in front repo
- **Generic**: check `package.json` scripts for a `dev` command

### 6b — Recap and confirm

```
Ready to launch servers in background:

  🩵 [w5] feat/ai-studio

  Servers:
    back  → bin/dev (port 3051)
    front → bun run dev --port 3050

Launch? [Y/n]
```

### 6c — Launch servers

For each server, use the Bash tool with `run_in_background: true`:

```bash
# Source shell profile for PATH (bun, nvm, rbenv)
source ~/.zshrc 2>/dev/null || source ~/.bashrc 2>/dev/null || true

cd <workspace_path>/<repo_name> && <command>
```

Apply variable substitution:
- `$PORT` → repo port
- `$SLOT` → workspace slot
- `$BRANCH` → branch name

### 6d — Verify servers started

Wait a few seconds, then check if the ports are responding:

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:<port> 2>/dev/null || echo "not ready"
```

Report status for each server.

### 6e — Summary

```
✓ Servers launched in background!

  🩵 [w5] feat/ai-studio

  back  → running on port 3051
  front → running on port 3050

Note: servers will stop when this Claude session ends.
```

---

## Rules

- **Always confirm before launching.** Show the recap and wait for approval.
- **If any server fails to start, display the error.** Don't leave partial state.
- **Variable substitution** in commands follows the same rules as hook commands.
- **WezTerm mode**: check for WezTerm CLI before attempting layout. Fewer than 4 panes is fine — adapt the grid.
- **Background mode**: warn that servers stop when the Claude session ends.
