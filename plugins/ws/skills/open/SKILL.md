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

**Run the ws-open.sh script** — it handles everything in one shot (instant):

```bash
/bin/bash "${CLAUDE_PLUGIN_ROOT}/scripts/ws-open.sh" "<workspace_path>"
```

The script reads the registry + config, creates all WezTerm panes, sends commands, launches Claude tab, and goes fullscreen — all in a single process. No multiple Bash calls.

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
