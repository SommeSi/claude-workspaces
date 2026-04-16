# claude-workspaces

A Claude Code plugin marketplace for managing isolated workspaces with colored terminals, git worktrees, and per-workspace context.

Work on multiple features in parallel — each in its own colored terminal with dedicated ports, isolated databases, and full Claude context. Switch between workspaces instantly without losing track of where you are.

## Installation

```bash
# Add the marketplace
claude plugins marketplace add SommeSi/claude-workspaces

# Install the workspace plugin
claude plugins install workspace

# (Optional) Install the auto-login plugin
claude plugins install auto-login
```

After installation, restart Claude Code.

### Shell hook (recommended)

Auto-color your terminal when you `cd` into a workspace:

```bash
bash ~/.claude/plugins/cache/claude-workspaces/workspace/*/scripts/setup-shell.sh
```

This adds a `chpwd` hook to your `.zshrc` (or `PROMPT_COMMAND` to `.bashrc`) that:
- Colors the terminal background when you enter a workspace directory
- Sets the tab title with the workspace emoji, branch, and slot
- Resets colors when you leave a workspace

Safe to run multiple times — it checks for an existing marker before modifying your shell config.

### Update

```bash
bash ~/.claude/plugins/cache/claude-workspaces/workspace/*/scripts/ws-update.sh
```

This clones the latest from GitHub and updates the local cache. Restart Claude Code after updating.

---

## Skills

| Skill | Description |
|-------|-------------|
| `/workspace:start-worktree` | Create a workspace with git worktree isolation |
| `/workspace:start-sandbox` | Create a lightweight workspace without a repo (mkdir + git init) |
| `/workspace:resume` | Load workspace context, color terminal, show status |
| `/workspace:list` | List all active workspaces with status, ports, and goals |
| `/workspace:open` | Open the dev layout — WezTerm panes, dev servers, Claude tab |
| `/workspace:attach` | Attach a workspace to an existing directory (no worktree) |
| `/workspace:finish` | Finalize workspace — safety checks, capture learnings, cleanup |
| `/workspace:auto-login` | Auto-login to your local dev app via browser MCP *(separate plugin)* |

---

## What is a workspace?

A workspace is an isolated work session. Each one gets:

- **Colored terminal** — unique background color + tab title so you know where you are at a glance
- **Git worktree** isolation (or a lightweight sandbox) — each feature on its own branch, no stashing
- **CLAUDE.local.md** — Claude knows the goal and context of this workspace in every session
- **Dedicated ports** — run multiple dev servers in parallel without conflicts
- **Isolated database** — automatic `_w<slot>` suffix on database names
- **VS Code/Cursor colors** — IDE title bar and status bar match the terminal color
- **WezTerm layout** — 2x2 pane grid with dev servers + a dedicated Claude tab
- **Desktop notifications** — get notified with the workspace badge when Claude finishes

## Why?

When you're working with Claude Code, you often need to wait for a response. Instead of sitting idle, switch to another terminal with a different workspace and keep going. The colored terminals and badges make it impossible to get lost.

---

## Quick start

### 1. Create a workspace

```
/workspace:start-worktree
```

Claude will walk you through an interactive dialogue (one question at a time):

1. **Describe your goal** — e.g. "fix the CSV export bug on Polo"
2. **Branch name** — Claude proposes one based on your description (e.g. `fix/polo/csv-export`)
3. **Spec link** — optional ticket or spec URL

Then Claude creates everything: worktrees, isolated DB, `.env` files with correct ports, and colors your terminal.

### 2. Open the dev layout

```
/workspace:open
```

Opens a WezTerm window with your dev servers running in separate panes, plus a Claude tab with `/workspace:resume` auto-triggered.

### 3. Resume a workspace

```
/workspace:resume
```

When you open a new Claude session in a workspace directory, this loads the full context: goal, git state, modified files, and proposes the next step.

### 4. Finish a workspace

```
/workspace:finish
```

Safety checks (uncommitted files, unmerged branches), captures learnings to memory, drops isolated DBs, removes worktrees, and frees the slot.

---

## Project config

### `.claude-workspaces.json` (committed to git)

Create this at your project root. If it doesn't exist, `/workspace:start-worktree` will guide you through creating one interactively.

**Single repo:**

```json
{
  "workspaces_root": "~/workspaces",
  "port_step": 10,
  "repos": [
    { "name": "app", "origin": ".", "port_base": 3000 }
  ]
}
```

**Multi-repo** (e.g. Rails API + Next.js frontend + microservice):

```json
{
  "workspaces_root": "~/projects/worktrees",
  "port_step": 10,
  "repos": [
    {
      "name": "back",
      "origin": ".",
      "port_base": 3001,
      "env_template": {}
    },
    {
      "name": "front",
      "origin": "../frontend-app",
      "port_base": 3000,
      "env_template": {
        "NEXTAUTH_URL": "http://localhost:$PORT",
        "RAILS_API_URL": "http://127.0.0.1:$BACK_PORT",
        "NEXT_PUBLIC_API_URL": "http://localhost:$BACK_PORT"
      }
    },
    {
      "name": "webhook",
      "origin": "../webhook-service",
      "port_base": 3002,
      "env_template": {}
    }
  ],
  "hooks": {
    "post_create": "cd $WORKSPACE_PATH/back && bundle install && cd $WORKSPACE_PATH/front && bun install",
    "db_create": null,
    "db_destroy": null
  },
  "terminal": {
    "type": "wezterm",
    "fullscreen": true,
    "claude_tab": true,
    "panes": [
      { "repo": "front", "cmd": "bun run dev" },
      { "repo": "back", "cmd": "bin/dev" },
      { "repo": ".", "cmd": null },
      { "repo": "back", "cmd": "bin/jobs" }
    ]
  }
}
```

### `.claude-workspaces.local.json` (gitignored, per-developer)

Override paths that differ between developers:

```json
{
  "repos": {
    "front": { "origin": "../my-frontend-folder" },
    "webhook": { "origin": "../my-webhook-folder" }
  }
}
```

Add `.claude-workspaces.local.json` to your `.gitignore`.

### Config reference

| Field | Description | Default |
|-------|-------------|---------|
| `workspaces_root` | Where workspaces are created | `~/workspaces` |
| `port_step` | Ports to skip between slots | `10` |
| `repos[].name` | Short name for the repo | — |
| `repos[].origin` | Path to the source repo (`.` for current) | — |
| `repos[].port_base` | Starting port for this repo | — |
| `repos[].env_template` | Key-value pairs to write to `.env.local` | `{}` |
| `hooks.post_create` | Runs after worktree creation (e.g. `bundle install`) | `null` |
| `hooks.db_create` | Custom DB setup (overrides auto-detection) | `null` |
| `hooks.db_destroy` | Custom DB teardown | `null` |
| `terminal.type` | Terminal emulator (`wezterm`) | — |
| `terminal.fullscreen` | Go fullscreen on open | `true` |
| `terminal.claude_tab` | Open a Claude tab with `/workspace:resume` | `true` |
| `terminal.panes[]` | Pane definitions (repo + cmd) | — |

### Variable substitution

These variables are available in `hooks`, `terminal.panes[].cmd`, and `env_template` values:

| Variable | Description |
|----------|-------------|
| `$SLOT` | Slot number (e.g. `2`) |
| `$BRANCH` | Branch name (e.g. `feat/polo/export-csv`) |
| `$SLUG` | Slug (branch with `/` → `-`) |
| `$PORT` | Port for the current repo |
| `$WORKSPACE_PATH` | Workspace root directory |
| `$<REPO_NAME>_PORT` | Port for a specific repo (e.g. `$BACK_PORT`, `$FRONT_PORT`) |

---

## How ports work

Each workspace gets its own ports based on slot number:

```
port = repo.port_base + (slot × port_step)
```

Example with `port_step: 10`:

| Slot | back (base 3001) | front (base 3000) | webhook (base 3002) |
|------|------------------|-------------------|---------------------|
| w1 | 3011 | 3010 | 3012 |
| w2 | 3021 | 3020 | 3022 |
| w3 | 3031 | 3030 | 3032 |

All `.env` files are automatically updated with the correct ports, including cross-references (e.g. `RAILS_API_URL` in the front repo points to the back's workspace port).

---

## Database isolation

When creating a worktree workspace, the plugin automatically:

1. Detects database configuration (`DATABASE_URL` or `config/database.yml`)
2. Creates isolated database names with `_w<slot>` suffix
3. Updates `DATABASE_URL` in the workspace's `.env.local`
4. Runs `db:create` + `db:schema:load` (Rails) or your custom `db_create` hook

Example: `sommesi_app_development` → `sommesi_app_development_w2`

Multiple databases (cache, queue, cable) are all isolated automatically.

---

## Generated files

When a workspace is created, these files are generated:

| File | Location | Purpose |
|------|----------|---------|
| `CLAUDE.local.md` | Workspace root | Goal, slot, repos, notes — loaded by Claude in every session |
| `.worktree-env.sh` | Workspace root | Auto-sourced by shell hook on `cd` — sets colors and exports |
| `.vscode/settings.json` | Per repo | Title bar and status bar color customizations (merged with existing) |
| `<slug>.code-workspace` | Workspace root | VS Code/Cursor multi-folder workspace file (multi-repo only) |
| `.env.local` | Per repo | Copied from origin with port substitution + workspace vars |
| `.env.test`, `.env.development` | Per repo | Copied from origin (secrets needed for dev) |

---

## Color palette

Each workspace slot gets a unique color that cycles after 8:

| Slot | Emoji | Color | Hex |
|------|-------|-------|-----|
| 1, 9, 17... | 🟢 | Green | `#1a3a2a` |
| 2, 10, 18... | 🟠 | Orange | `#3a2a15` |
| 3, 11, 19... | 🟣 | Purple | `#2a1a3a` |
| 4, 12, 20... | 🔴 | Red | `#3a1515` |
| 5, 13, 21... | 🩵 | Cyan | `#15353a` |
| 6, 14, 22... | 🩷 | Pink | `#3a1a2e` |
| 7, 15, 23... | 🟡 | Yellow | `#3a3415` |
| 8, 16, 24... | 🔵 | Blue | `#1a2835` |

Colors are applied via OSC escape sequences:
- **OSC 11** — terminal background color
- **OSC 1337** — WezTerm tab title (survives Claude Code title resets)

---

## WezTerm layout

When you run `/workspace:open`, the plugin creates a WezTerm window with a 2x2 pane grid:

```
┌──────────────────┬──────────────────┐
│  front            │  back            │
│  bun run dev      │  bin/dev         │
├──────────────────┼──────────────────┤
│  (terminal)       │  back            │
│                   │  bin/jobs        │
└──────────────────┴──────────────────┘
```

Plus a separate **Claude tab** that auto-starts with `/workspace:resume`.

The layout goes fullscreen automatically on macOS (native fullscreen via AppleScript).

---

## Desktop notifications

The plugin includes Claude Code hooks that send desktop notifications:

- **On session stop** — notifies you with the workspace badge and goal (so you know which workspace finished)
- **On notification events** — system-level alerts

Notifications use `osascript` (macOS), `terminal-notifier` (macOS fallback), or `notify-send` (Linux).

---

## Auto-login plugin

The `auto-login` plugin auto-logs into your local dev app via browser MCP (Playwright or Firefox).

### Installation

```bash
claude plugins install auto-login
```

### Configuration

Create `.auto-login.json` at your project root:

```json
{
  "login": {
    "url": "/login",
    "credentials": {
      "file": ".env.local",
      "email_var": "E2E_TEST_EMAIL",
      "password_var": "E2E_TEST_PASSWORD"
    },
    "success_indicator": {
      "redirect_away_from": "/login"
    }
  },
  "companies": {
    "my-company": {
      "features": {
        "dashboard": { "url": "/dashboard" },
        "settings": { "url": "/settings" }
      }
    }
  }
}
```

### Usage

```
/workspace:auto-login
```

Claude will:
1. Read credentials from `.env.local`
2. Resolve the correct port for your workspace
3. Navigate to the login page
4. Fill and submit the form
5. Navigate to your feature

---

## Registry

All workspace state is stored in `~/.claude-workspaces/registry.json`. This file is managed automatically — you shouldn't need to edit it manually.

```json
{
  "workspaces": {
    "1": {
      "slug": "feat-polo-export-csv",
      "mode": "worktree",
      "branch": "feat/polo/export-csv",
      "color": "#1a3a2a",
      "emoji": "🟢",
      "created_at": "2026-04-16T10:00:00Z",
      "project_root": "/Users/you/projects/my-app",
      "workspace_path": "/Users/you/workspaces/feat-polo-export-csv",
      "repos": [
        { "name": "back", "path": ".../back", "port": 3011 },
        { "name": "front", "path": ".../front", "port": 3010 }
      ]
    }
  },
  "next_slot": 2
}
```

Workspace modes:
- **worktree** — created by `/workspace:start-worktree`, full git worktree isolation
- **sandbox** — created by `/workspace:start-sandbox`, lightweight (mkdir + git init)
- **attached** — created by `/workspace:attach`, wraps an existing directory

---

## How it works

No runtime, no CLI, no npm dependencies. The plugin is **pure markdown skills + shell scripts** — Claude executes everything using its built-in tools (Bash, Read, Write, Edit).

### Architecture

```
~/.claude/plugins/cache/claude-workspaces/
├── workspace/
│   ├── .claude-plugin/plugin.json     # Plugin metadata
│   ├── hooks/hooks.json               # Claude Code lifecycle hooks
│   ├── skills/                        # 7 markdown skills (the core logic)
│   │   ├── start-worktree/SKILL.md
│   │   ├── start-sandbox/SKILL.md
│   │   ├── resume/SKILL.md
│   │   ├── list/SKILL.md
│   │   ├── open/SKILL.md
│   │   ├── attach/SKILL.md
│   │   └── finish/SKILL.md
│   ├── references/                    # Shared docs for skills
│   │   ├── registry-format.md
│   │   ├── color-palette.md
│   │   ├── generated-files.md
│   │   └── terminal-layout.md
│   └── scripts/                       # Shell scripts for terminal control
│       ├── ws-open.sh                 # WezTerm layout creation
│       ├── ws-color.sh                # Apply workspace color
│       ├── ws-generate-files.sh       # Generate workspace files
│       ├── setup-shell.sh             # Install shell hook
│       └── notify.sh                  # Desktop notifications
└── auto-login/
    ├── .claude-plugin/plugin.json
    └── skills/
        └── auto-login/SKILL.md
```

Key design decisions:
- **Atomic registry writes** — Python `tempfile` + `rename` to prevent corruption from concurrent sessions
- **Slot-based port math** — deterministic ports, no runtime detection needed
- **OSC escape sequences** — works across WezTerm, iTerm2, Kitty, and most modern terminals
- **One question at a time** — interactive dialogues never batch questions

---

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- git
- python3 (for registry management and notifications)
- A terminal supporting OSC 11 (WezTerm, iTerm2, Kitty, Windows Terminal, most modern terminals)
- macOS, Linux, or WSL
- [WezTerm](https://wezfurlong.org/wezterm/) (optional, for `/workspace:open` layout)

## License

MIT
