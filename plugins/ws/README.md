# workspace — Claude Code Workspace Manager

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
| `/workspace:start-worktree` | Create a workspace with git worktree isolation |
| `/workspace:start-sandbox` | Create a lightweight workspace (mkdir + git init) |
| `/workspace:list` | List all active workspaces with status |
| `/workspace:resume` | Load workspace context and color terminal |
| `/workspace:attach` | Attach a workspace to an existing directory (no worktree, no new dir) |
| `/workspace:open` | Open (or reopen) the dev environment — WezTerm panes, background servers, or VS Code + Claude tab |
| `/workspace:finish` | Finalize workspace — safety checks, cleanup |

## Setup

### Shell hook (recommended)

The plugin generates a `.worktree-env.sh` in each workspace. To auto-color your terminal when you `cd` into a workspace, run the setup script:

```bash
bash ~/.claude/plugins/cache/claude-workspaces/workspace/*/scripts/setup-shell.sh
```

Or ask Claude: "set up the workspace shell hook" — it will find and run the script for you.

This adds a small hook to your `.zshrc` or `.bashrc` that:
- Colors the terminal background on `cd` into a workspace
- Sets the tab title with the workspace emoji and branch
- Resets colors when you leave a workspace

Safe to run multiple times — skips if already installed. Supports zsh and bash.

### Project config (optional)

Create `.claude-workspaces.json` at your project root (committed to git):

```json
{
  "repos": [
    { "name": "back", "origin": ".", "port_base": 3001 },
    { "name": "front", "port_base": 3000 }
  ],
  "port_step": 10,
  "workspaces_root": "~/workspaces",
  "hooks": {
    "post_create": "cd $WORKSPACE_PATH/back && bundle install",
    "db_create": "bin/db-create $SLOT",
    "db_destroy": "bin/db-drop $SLOT"
  }
}
```

For multi-repo projects, external repos (repos outside the current git root) should **omit `origin`** in the shared config. Each developer provides their own paths in `.claude-workspaces.local.json` (gitignored):

```json
{
  "repos": {
    "front": { "origin": "../frontend-app" }
  }
}
```

The local file merges into the shared config — repos are matched by `name`, and any field in the local entry overrides the shared one. If a repo is missing `origin`, the plugin will ask for it interactively.

If no config exists, `/workspace:start-worktree` will guide you through creating both files.

### Terminal layout (optional, WezTerm)

Add a `terminal` section to auto-open a WezTerm window with dev servers when creating or reopening a workspace:

```json
{
  "repos": [
    { "name": "back", "origin": ".", "port_base": 3001 },
    { "name": "front", "origin": "../frontend-app", "port_base": 3000 }
  ],
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

Use `/workspace:open` to launch or reopen the layout at any time.

### VS Code mode

`/workspace:open` → option **3. VS Code** opens the workspace's `<slug>.code-workspace` in VS Code instead of a WezTerm window:

- each pane with a `cmd` becomes a VS Code task (`runOn: folderOpen`) running in its own integrated terminal — `$PORT`, `$SLOT`, `$BRANCH` are substituted
- the right sidebar opens with Claude Code (requires the Claude Code extension) — click its "Claude Code" tab once, VS Code remembers it for that workspace
- existing folders, settings and your own tasks are kept; only tasks labelled `ws: …` are managed by the plugin
- single-repo workspaces get a `.code-workspace` created on first open

On first launch VS Code asks **"Allow automatic tasks"** — choose Allow. Requires the `code` CLI (VS Code → *Shell Command: Install 'code' command in PATH*).

### Per-turn changed files recap

At the end of every Claude turn inside a workspace, a message lists the files Claude changed during that turn, each linking to `vscode://file/…` to open it in VS Code:

```
📝 3 fichiers modifiés ce tour
  back   M app/models/account.rb
  front  A src/features/account/AccountCard.tsx
  front  D src/old.ts
```

`M` modified · `A` added · `D` deleted · `R` restored to its committed state. Files that were already dirty before your prompt and untouched by Claude are not listed. Works in the CLI and the VS Code extension (hooks `UserPromptSubmit` + `Stop`, script `ws-turn.sh`).


## Requirements

- Claude Code
- git
- A terminal supporting OSC 11 (WezTerm, iTerm2, Kitty, Windows Terminal, most modern terminals)
- macOS, Linux, or WSL

## How it works

No runtime, no CLI, no dependencies. The plugin is pure markdown skills — Claude executes everything using its built-in tools (Bash, Read, Write, Edit).

State is stored in `~/.claude-workspaces/registry.json`.
