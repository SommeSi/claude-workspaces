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
| `/workspace:knowledge-review` | Turn captured session lessons into one `.claude/rules/` PR per repo |
| `/workspace:recall` | Find a past session from a few words, with its resume command |
| `/workspace:mail` | Client mail that doesn't read as AI: facts checked first, right tu/vous, 3 tone versions to pick from, Gmail draft in the thread, promises tracked |

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

`origin` can also be a list of candidate paths, e.g. `["../web", "../../web"]`: the first one that exists is used, so devs with different clone layouts can share one config.

The local file merges into the shared config — repos are matched by `name`, and any field in the local entry overrides the shared one. If a repo is missing `origin`, the plugin will ask for it interactively.

If no config exists, `/workspace:start-worktree` will guide you through creating both files.

### Sprint cards from Notion (optional)

Add a `notion` section and `/workspace:start-worktree` (with no goal in your message) lists the cards assigned to you in the current sprint, then derives branch, goal and spec from the one you pick. Requires the Notion MCP server.

```json
{
  "notion": {
    "data_source": "collection://<data-source-id>",
    "history_data_source": "collection://<delivery-history-id>",
    "sprint_property": "Sprint",
    "sprint_format": "Sprint {week}",
    "assignee_property": "Assigné à",
    "status_property": "Statut",
    "exclude_status": ["✅ Staging", "Production", "Done In Dev"]
  }
}
```

`{week}` is the ISO week number of today.

**Client mails too (optional):** add `"mail": {"query": "to:devs@example.com -from:example.com newer_than:7d", "skill": "bug-from-mail"}`. The picker then also offers the latest client mail threads (Gmail connector); picking one runs that project skill to read the thread and create the card, and the workspace starts on it. No Gmail wait: at session start a detached headless Haiku (`scripts/ws_mail_cache.py`, ~7 s, at most every 15 min) makes the search through the connector and caches the threads; the preflight reads that cache.

**Faster with an integration token (optional):** store a Notion internal-integration token (connected to the board) in the macOS keychain — `security add-generic-password -U -s claude-workspaces-notion -a notion -w` (prompts, never paste it in a chat) — and the preflight fetches your sprint cards itself, in parallel, saving a whole LLM turn. "You" = the Notion member whose email is `notion_user_email` in `~/.claude-workspaces/config.json` (per user, never in a repo), else your git `user.email`. Without a token, the skill uses the Notion MCP.

**PRs without a card:** `/git-pr` checks that the PR is tied to a card (`TASK-<n>` in the branch, or a Notion `Spec`). If not, it lists your open cards across all sprints (`scripts/ws_notion.py cards --all-sprints`) to catch a forgotten one, else proposes a new card in the recap and creates it with the PR (`ws_notion.py create`, existing Feature/Client values only).

With `history_data_source`, `/workspace:finish` adds one row per merged delivery to that Notion database: attention hours, Claude working hours and calendar days, measured from the transcripts by `scripts/ws-actuals.py` (no double counting across parallel sessions). The `estimation` plugin's `devis` skill reads it to calibrate quotes.

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

At the end of every Claude turn inside a workspace, a message lists the files Claude edited during that turn:

```
📝 3 fichiers modifiés ce tour
  M back/app/models/account.rb
  A front/src/features/account/AccountCard.tsx
  D front/src/old.ts
```

`M` edited · `A` added · `D` deleted · `R` written but back to its committed state. Only files Claude actually wrote are listed (recorded from `Edit`/`Write` calls), so unrelated dirty files and test artifacts never show up — capped at 12 lines.

Paths are plain text: the Claude Code UI prints a hook message as raw lines (`Stop says: …`), so markdown links would show as literal URLs instead of being clickable. Works in the CLI and the VS Code extension (hooks `PostToolUse` + `Stop`, script `ws-turn.sh`).

### Team knowledge (automatic)

What a session learns should reach the next sessions, including teammates'. Three pieces:

- **Rules in the repos.** Team lessons live in each repo's `.claude/rules/*.md`. Claude Code loads a rule file natively when the session reads or edits a file matching its `paths:` frontmatter (files without `paths:` load every session). They are shared through git and reviewed in PRs.
- **Capture.** At the end of every session (≥ 3 user messages), the `SessionEnd` hook forks a detached `claude -p --safe-mode --model sonnet` that reads the transcript and writes the confirmed team lessons to `~/.claude-workspaces/knowledge-inbox/<session>.json`, plus a summary to `~/.claude-workspaces/sessions.jsonl` (used by `/workspace:recall`). The hook returns in ~50 ms; the work runs in the background (log: `~/.claude-workspaces/knowledge-capture.log`). Disable with `WS_KNOWLEDGE_DISABLE=1`.
- **Landing.** `/git-pr` adds the inbox lessons matching the PR's files (`scripts/ws-knowledge.py match`); `/workspace:knowledge-review` turns the rest into one PR per repo. Nothing merges without a human.

### Session reminders (automatic)

At every session start, the `SessionStart` hook (`scripts/ws-session-nag.py`) lists, for the session's GitHub org/repos:
- **PRs assigned to you** (as reviewer/merger) still open — merge them before opening new ones;
- **your PRs without an assignee other than you** — every PR must be assigned to a reviewer (the repos' `pr-assignee` check turns red otherwise, as a signal, never blocking);
- **your pending post-deploy actions** — PRs declare manual steps in a `## Déploiement` section (`### Avant` / `### Après`; code actions are migration-jobs that run by themselves); the repos' GitHub Action turns it into a `post-deploy` issue (one box per action and environment) and the `deploy-prerequisites` check turns red on the deploy PR while an "Avant" box is unticked (a signal, never blocking);
- **client promises made by mail and due today** — the `mail` skill records each commitment of a draft ("je reviens vers vous jeudi", an evolution) in `~/.claude-workspaces/mail-promises.jsonl` (`scripts/ws-mail-promises.py`); a later reply in the same thread settles them.

It reads a cache refreshed in the background, so it adds no latency. `scripts/ws-reviewer.py` picks the least-loaded reviewer (open PRs assigned across the org; candidates = `reviewers` in the config, else recent PR authors) — `/git-pr` uses it to assign every new PR.

Each workspace also gets `.claude/settings.local.json` with `autoMemoryDirectory` pointing at the project's memory, so personal auto-memory is no longer scattered (and lost) across worktree directories.

### Review → correction → merge (opt-in)

A launchd job on the PR **author's** Mac watches their open PRs every 5 min (`scripts/ws-review-watch.py`). Enable it per user in `~/.claude-workspaces/config.json` (never in a repo), then install the job:

```json
{ "review_autofix": true, "review_merge": "ask" }
```

```bash
python3 scripts/ws-review-watch.py install     # uninstall: python3 scripts/ws-review-watch.py uninstall
python3 scripts/ws-review-watch.py run --dry-run   # what it would do now, changes nothing
```

Scope: your open, non-draft PRs (`gh search prs --author @me`) in the orgs of your registered projects, **base `develop` only**. Label a PR `no-autofix` to leave it alone.

On each new review or comment from someone else (reviewers, Codex threads) you get a macOS notification (« #1617 relue par Uozak218 : changements demandés, 3 commentaires »), then:

- **Remarks to handle** (unresolved threads, changes requested, a review or PR comment with content) → a headless `claude -p` starts, detached, in the PR's worktree (the workspace on that branch, else a new worktree in `~/.claude-workspaces/autofix/`). It checks each remark first (reviewers and Codex can be wrong), fixes the valid ones, runs the tests of what changed (Rails back: private test DB as in `~/.claude/CLAUDE.md`), commits `fix(review): …`, pushes to the PR branch (never force-push), answers in French in each thread (« Corrigé dans <sha> » / « Pas d'accord : <raison> »), resolves the threads it fixed and re-requests review. **It never merges.** You get its result as a notification. At most 2 agents run at once; one per PR.
- **Mergeable** = approved by the assignee **on the PR's current head commit** (an approval of an older commit does not count, so no code reaches `develop` without a human approving exactly that code), zero unresolved thread, no failing or pending check, base `develop`:
  - `"review_merge": "ask"` (default): notification « #N approuvée et verte : prête à merger », and the next session lists it (« prêtes à merger »); Claude merges when you say so.
  - `"review_merge": "auto"`: the watcher merges with a merge commit (`gh pr merge --merge --match-head-commit <sha>`) and notifies « mergée ».
- **Approved, checks pending** → waits for the next run. Never merges into `main`.

The session reminders list the PRs ready to merge, the fix agents running and the reviews not yet handed to an agent. Files: state `~/.claude-workspaces/review-watch.json`, watcher log `~/.claude-workspaces/review-watch.log`, one agent's log and result `~/.claude-workspaces/autofix/<repo>-<n>.log` / `.json`. Tests: `python3 -m unittest scripts/test_ws_review_watch.py`.

### Oversized PRs → stack (automatic in `/git-pr`)

`/git-pr` measures the branch the way the repo's `pr-size-limit` check does (`scripts/ws-stack.py size`: `MAX_FILES`, `MAX_LINES`, `EXCLUDE_REGEX` read from `.github/workflows/pr-size-limit.yml`). Over the limit, the recap proposes layers (migrations and models → services and jobs → API → front, each with its tests); once validated, `ws-stack.py split <plan> --submit` builds one branch per layer (`<branch>-1-models`…) with git plumbing — never touching your worktree, index or branch — then opens them as a linked GitHub Stack with the official [`gh stack`](https://github.com/github/gh-stack) extension (`init` + `submit --auto --open`, from a throwaway worktree), and sets each PR's title, body and assignee. `ws-update.sh` installs the extension when `gh` is present. Merge with `gh stack merge <top PR> --yes --merge`, then check `git merge-base --is-ancestor <top sha> origin/develop`. Tests: `python3 -m unittest scripts/test_ws_stack.py`.

## Requirements

- Claude Code
- git
- A terminal supporting OSC 11 (WezTerm, iTerm2, Kitty, Windows Terminal, most modern terminals)
- macOS, Linux, or WSL

## How it works

No runtime, no CLI, no dependencies. The plugin is pure markdown skills — Claude executes everything using its built-in tools (Bash, Read, Write, Edit).

State is stored in `~/.claude-workspaces/registry.json`.
