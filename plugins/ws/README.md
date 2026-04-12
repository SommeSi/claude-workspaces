# ws — Claude Code Workspace Manager

Manage isolated workspaces for parallel development with Claude Code.

Each workspace gets:
- A **colored terminal** (background + title) so you know where you are
- **Git worktree** isolation (or a lightweight sandbox)
- **CLAUDE.local.md** with workspace context and badge
- **Dedicated ports** to run multiple apps in parallel
- **VS Code/Cursor colors** matching the terminal

## Skills

| Skill | Description |
|-------|-------------|
| `/ws:start-worktree` | Create a workspace with git worktree isolation |
| `/ws:start-sandbox` | Create a lightweight workspace (mkdir + git init) |
| `/ws:list` | List all active workspaces with status |
| `/ws:resume` | Load workspace context and color terminal |
| `/ws:attach` | Attach a workspace to an existing directory (no worktree, no new dir) |
| `/ws:finish` | Finalize workspace — safety checks, cleanup |

## Setup

### Project config (optional)

Create `.claude-workspaces.json` at your project root:

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

If no config exists, `/ws:start-worktree` will guide you through creating one.

## Requirements

- Claude Code
- git
- A terminal supporting OSC 11 (WezTerm, iTerm2, Kitty, Windows Terminal, most modern terminals)
- macOS, Linux, or WSL

## How it works

No runtime, no CLI, no dependencies. The plugin is pure markdown skills — Claude executes everything using its built-in tools (Bash, Read, Write, Edit).

State is stored in `~/.claude-workspaces/registry.json`.
