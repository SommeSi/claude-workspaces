# Generated Files

Files created by /ws:start-worktree and /ws:start-sandbox in each workspace.

## CLAUDE.local.md (at workspace root)

````markdown
# Workspace — <branch-or-slug>

## Workspace identity
Always prefix your first response in a conversation with the workspace badge:
<emoji> **[w<slot>] <branch-or-slug>**

This helps the user know which workspace this Claude session is attached to.

## Workspace info
- **Slot**: <slot>
- **Mode**: <worktree|sandbox>
- **Branch**: `<branch>` (or "N/A" for sandbox)
- **Created**: <YYYY-MM-DD>
- **Repos**:
  - <name> -> <path> (port <port>)

## Goal of this workspace
<user description>

## Spec
<link or "none">

## Notes / decisions / TODOs

````

## .vscode/settings.json (at workspace root)

```json
{
  "workbench.colorCustomizations": {
    "titleBar.activeBackground": "<color>",
    "titleBar.activeForeground": "#ffffff",
    "statusBar.background": "<color>",
    "statusBar.foreground": "#ffffff"
  }
}
```

## .env.local (per repo, only for worktree mode with config)

```bash
PORT=<port>
WS_SLOT=<slot>
WS_BRANCH=<branch>
WS_COLOR=<color>
WS_EMOJI=<emoji>
```

Plus any `env_template` entries from `.claude-workspaces.json` with variable substitution:
- `$SLOT` → slot number
- `$BRANCH` → branch name
- `$SLUG` → workspace slug
- `$PORT` → port for the current repo
- `$WORKSPACE_PATH` → workspace root directory
- `$<REPO_NAME>_PORT` → port for a specific repo (e.g. `$BACK_PORT`, `$FRONT_PORT`)
