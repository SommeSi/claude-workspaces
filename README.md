# claude-workspaces

A Claude Code plugin marketplace for managing isolated workspaces with colored terminals, git worktrees, and per-workspace context.

## Installation

```bash
# Add the marketplace
claude plugins marketplace add SommeSi/claude-workspaces

# Install the ws plugin
claude plugins install workspace
```

After installation, restart Claude Code.

### Shell hook (recommended)

Auto-color your terminal when you `cd` into a workspace:

```bash
bash ~/.claude/plugins/cache/claude-workspaces/workspace/*/scripts/setup-shell.sh
```

This adds a hook to your `.zshrc` or `.bashrc` that colors the terminal background and sets the tab title on `cd` into any workspace. Safe to run multiple times.

### Skills

You'll have access to these skills:

| Skill | Description |
|-------|-------------|
| `/workspace:start-worktree` | Create a workspace with git worktree isolation |
| `/workspace:start-sandbox` | Create a lightweight workspace (mkdir + git init) |
| `/workspace:list` | List all active workspaces with status |
| `/workspace:resume` | Load workspace context and color terminal |
| `/workspace:attach` | Attach a workspace to an existing directory (no worktree, no new dir) |
| `/workspace:open` | Open the dev layout — WezTerm panes, dev servers, Claude tab |
| `/workspace:finish` | Finalize workspace — safety checks, cleanup |

## What is a workspace?

A workspace is an isolated work session. Each one gets:

- **Colored terminal** — background color + title so you know where you are at a glance
- **Git worktree** isolation (or a lightweight sandbox) — each feature on its own branch, no stashing
- **CLAUDE.local.md** — Claude knows the goal and context of this workspace in every session
- **Dedicated ports** — run multiple dev servers in parallel without conflicts
- **VS Code/Cursor colors** — IDE title bar matches the terminal color
- **Desktop notifications** — get notified with the workspace badge when Claude finishes

## Why?

When you're working with Claude Code, you often need to wait for a response. Instead of sitting idle, switch to another terminal with a different workspace and keep going. The colored terminals and badges make it impossible to get lost.

## Project config (optional)

For worktree workspaces, create `.claude-workspaces.json` at your project root:

```json
{
  "repos": [
    { "name": "app", "origin": ".", "port_base": 3000 }
  ],
  "port_step": 10,
  "workspaces_root": "~/workspaces",
  "hooks": {
    "post_create": "bin/setup $SLOT",
    "db_create": "bin/db-create $SLOT",
    "db_destroy": "bin/db-drop $SLOT"
  }
}
```

Multi-repo example (e.g., Rails + Next.js):

```json
{
  "repos": [
    { "name": "back", "origin": ".", "port_base": 3001 },
    { "name": "front", "origin": "../frontend-app", "port_base": 3000 }
  ],
  "port_step": 10,
  "workspaces_root": "~/workspaces",
  "hooks": {
    "db_create": "bin/db-create $SLOT",
    "db_destroy": "bin/db-drop $SLOT"
  }
}
```

If no config exists, `/workspace:start-worktree` will guide you through creating one.

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- git
- A terminal supporting OSC 11 (WezTerm, iTerm2, Kitty, Windows Terminal, most modern terminals)
- macOS, Linux, or WSL
- python3 (for desktop notifications)

## How it works

No runtime, no CLI, no dependencies. The plugin is pure markdown skills — Claude executes everything using its built-in tools (Bash, Read, Write, Edit).

State is stored in `~/.claude-workspaces/registry.json`.

## Color palette

Each workspace slot gets a unique color (cycles after 8):

| Slot | Color |
|------|-------|
| 1 | 🟢 Green |
| 2 | 🟠 Orange |
| 3 | 🟣 Purple |
| 4 | 🔴 Red |
| 5 | 🩵 Cyan |
| 6 | 🩷 Pink |
| 7 | 🟡 Yellow |
| 8 | 🔵 Blue |

## License

MIT
