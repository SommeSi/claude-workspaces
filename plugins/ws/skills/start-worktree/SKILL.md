---
name: start-worktree
description: Create a new isolated workspace with git worktree. Use when the user wants to start working on a new feature, bugfix, or task in an isolated branch. Triggers on "new feature", "start working on", "create workspace", "new worktree", "isolate work".
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

**Respond in the user's language.**

You are creating a new isolated workspace using `git worktree`. Follow the steps below **in order**. Never skip ahead. Never batch multiple questions in a single message.

---

## Step 1 — Verify prerequisites

Run:

```bash
git rev-parse --show-toplevel
```

- If the command succeeds, note the git root path. Continue to Step 2.
- If it fails (not a git repository), stop and tell the user:
  > This directory is not inside a git repository. Use `/workspace:start-sandbox` instead to create an isolated workspace without git.

---

## Step 2 — Load or create project config

Look for `.claude-workspaces.json` at the git root:

```bash
cat <git-root>/.claude-workspaces.json 2>/dev/null
```

### If config exists

Parse it. Then check for a local override file:

```bash
cat <git-root>/.claude-workspaces.local.json 2>/dev/null
```

If a local file exists, **merge** it into the main config:
- `repos` in the local file are matched by `name` — any field present in the local entry overrides the shared entry (typically `origin`).
- Top-level fields (`workspaces_root`, `port_step`, `hooks`, `terminal`) in the local file override the shared ones.
- Repos defined only in the shared config keep their values unchanged.

After merging, check that every repo has an `origin` field. If any repo is missing `origin` (defined in shared config without it, and no local override), **ask the user** for the path and offer to save it to `.claude-workspaces.local.json`.

Continue to Step 3.

### If config does NOT exist

Guide the user through creating one, **one question at a time**:

1. **How many repositories does this project use?** (Enter 1 for a single repo, or a number for a monorepo / multi-repo setup.)
2. For **each repo**, ask:
   - **Name** for this repo (e.g. `back`, `front`, `app`)
   - **Port base** — the starting port number for this repo (e.g. `3000`)
   - **Is this the current repo?** If yes, `origin` is `"."`. If no, ask for the relative path — but explain this will go in the **local** config file since paths differ per developer.
3. **Where should workspaces be created?** (default: `~/workspaces`)
4. **Port step** — how many ports to skip between slots? (default: `10`)
5. **Any setup hooks?** (all optional — press Enter to skip each):
   - `post_create` — runs after worktree is created (e.g. `bundle install`, `yarn install`)
   - `db_create` — sets up a database for this workspace
   - `db_destroy` — tears down the database when the workspace is removed

After collecting answers, generate **two JSON files** and show them to the user. Ask for explicit confirmation before writing.

**Shared config** (`.claude-workspaces.json` — committed to git):

```json
{
  "workspaces_root": "~/workspaces",
  "port_step": 10,
  "repos": [
    { "name": "back", "origin": ".", "port_base": 3001 },
    { "name": "front", "port_base": 3000 }
  ],
  "hooks": {
    "post_create": "cd $WORKSPACE_PATH/back && bundle install",
    "db_create": null,
    "db_destroy": null
  }
}
```

Note: repos whose `origin` is `"."` (the current repo) include it in the shared config. External repos omit `origin` — each developer provides their own path in the local file.

**Local config** (`.claude-workspaces.local.json` — gitignored, per-developer):

```json
{
  "repos": {
    "front": { "origin": "../frontend-app" }
  }
}
```

Write the shared config to `<git-root>/.claude-workspaces.json`.
Write the local config to `<git-root>/.claude-workspaces.local.json`.

Also check if `.claude-workspaces.local.json` is in `.gitignore`. If not, suggest adding it.

---

## Step 3 — Interactive dialogue (ONE question at a time, NEVER batch)

Ask each question separately, waiting for the user's answer before asking the next.

### 3a — Description

Ask: **Briefly describe the goal of this workspace** (2–3 sentences). This will be written to `CLAUDE.local.md` to give future Claude sessions context.

### 3b — Branch name

Based on the user's description, **propose a branch name** following conventional format: `feat/`, `fix/`, `chore/`, `refactor/`, `docs/`, `test/`, `style/`, `perf/`.

Example: if the user says "ajouter l'export CSV pour Polo", propose `feat/polo/export-csv`.

Present it as a select:

> Branch name suggestion:
> 1. `feat/polo/export-csv`
> 2. I want a different name

If **2**, let the user type their own name.

### 3c — Spec link

Ask: **Is there a spec or ticket link for this work?** (optional — "no" or Enter to skip)

---

## Step 4 — Load registry and allocate slot

See references/registry-format.md for the full schema and allocation rules.

### 4a — Read the registry

```bash
cat ~/.claude-workspaces/registry.json 2>/dev/null || echo '{"workspaces":{},"next_slot":1}'
```

### 4b — Find the first free slot

Scan keys `1, 2, 3, ...` in `workspaces` and return the first missing key. This is the new slot number.

### 4c — Derive color and emoji

See references/color-palette.md. Compute: `index = (slot - 1) % 8`, then look up the corresponding hex color and emoji.

### 4d — Calculate ports

For each repo defined in `.claude-workspaces.json`:

```
port = repo.port_base + (slot * config.port_step)
```

### 4e — Derive slug

Replace every `/` in the branch name with `-`.

Example: `feat/polo/export-csv` → `feat-polo-export-csv`

### 4f — Determine workspace path

Expand `~` to `$HOME` in `workspaces_root`, then:

```
workspace_path = <workspaces_root>/<slug>
```

---

## Step 5 — Recap and confirm

Show a clear summary of everything that will be created. For example:

```
Ready to create workspace:

  Branch:    feat/polo/export-csv
  Slug:      feat-polo-export-csv
  Slot:      w3
  Color:     🟣 #2a1a3a (Purple)
  Path:      /Users/you/workspaces/feat-polo-export-csv

  Repos:
    back  →  /Users/you/workspaces/feat-polo-export-csv/back  (port 3030)
    front →  /Users/you/workspaces/feat-polo-export-csv/front (port 4030)

  Hooks:
    post_create: cd $WORKSPACE_PATH/back && bundle install
    db_create:   (none)

Confirm? [Y/n]
```

Wait for the user's response. Accept: `y`, `yes`, `o`, `oui`, or empty (just Enter). **Anything else cancels** — tell the user the workspace was not created.

---

## Step 6 — Create the workspace

Execute the following sub-steps in order. If any step fails, stop immediately, display the error, and clean up (see below).

### 6a — Create workspace directory

```bash
mkdir -p <workspace_path>
```

### 6b — Create git worktrees

For each repo in the config, resolve its absolute origin path:

```bash
# origin is relative to git root
origin_abs="<git-root>/<repo.origin>"
worktree_path="<workspace_path>/<repo.name>"
```

Then create the worktree:

```bash
# If the branch does not exist yet (new branch):
git -C "$origin_abs" worktree add -b "<branch>" "$worktree_path"

# If the branch already exists locally:
git -C "$origin_abs" worktree add "$worktree_path" "<branch>"

# If the branch exists on the remote but not locally:
git -C "$origin_abs" fetch origin "<branch>"
git -C "$origin_abs" worktree add --track -b "<branch>" "$worktree_path" "origin/<branch>"
```

Check the output of the first command. If it fails because the branch already exists, fall back to the second or third form accordingly.

After creating the worktree, pull the latest changes from the base branch to ensure the worktree starts up to date:

```bash
git -C "$worktree_path" pull origin develop 2>/dev/null || git -C "$worktree_path" pull origin main 2>/dev/null || true
```

### 6c — Generate workspace files

See references/generated-files.md for the exact file contents and templates.

- Write `<workspace_path>/CLAUDE.local.md` — fill in slot, branch, mode (`worktree`), creation date, repos list, user description, spec link.
- For each repo, write or merge `<workspace_path>/<repo.name>/.vscode/settings.json` — add `workbench.colorCustomizations` with the workspace color. If the file already exists, merge the color key without overwriting other settings.
- If multi-repo (2+ repos), write `<workspace_path>/<slug>.code-workspace` — VS Code workspace file listing all repos with workspace color. See references/generated-files.md.
- Write `<workspace_path>/.worktree-env.sh` — fill in slot, branch, color, emoji. This file is auto-sourced by the user's shell hook on `cd`. See references/generated-files.md for the template.
- For each repo, generate `<workspace_path>/<repo.name>/.env.local`:
  1. Look for an existing `.env.local` in the origin repo directory. Also check the **git root** of the project (the origin may be a subdirectory). Copy it as the base if found.
  2. Also copy `.env.test`, `.env.development`, and any other `.env.*` files (except `.env.production`) from the same locations — these often contain secrets needed for dev.
  3. Then **append or override** the workspace variables (PORT, WS_SLOT, WS_BRANCH, WS_COLOR, WS_EMOJI) and any `env_template` entries in the `.env.local`. **Always ensure the copied file ends with a newline** before appending — if the last line doesn't end with `\n`, add one first to prevent variables from being concatenated.
  4. If a variable already exists in the base file, replace its value instead of duplicating the line.
  5. **IMPORTANT — Port substitution in copied vars**: After copying from origin, scan ALL variables in the `.env.local` for hardcoded ports that match origin repo ports (e.g. `3001`, `3000`). Replace them with the workspace ports. For example, if origin back port is `3001` and workspace back port is `3051`, replace all occurrences of `:3001` with `:3051` in the entire file. Same for front port, webhook port, etc. This ensures vars like `RAILS_API_URL=http://127.0.0.1:3001` become `RAILS_API_URL=http://127.0.0.1:3051`.

Variable substitution applies to `env_template` values:
- `$SLOT` → slot number
- `$BRANCH` → branch name
- `$SLUG` → workspace slug
- `$PORT` → port for the current repo
- `$WORKSPACE_PATH` → workspace root directory
- `$<REPO_NAME>_PORT` → port for a specific repo (uppercase repo name, e.g. `$BACK_PORT`)

### 6d — Execute hooks

If hooks are defined in the config, run them in this order: `post_create`, then `db_create`.

Before running each hook command, perform variable substitution:
- `$SLOT` → slot number
- `$BRANCH` → branch name
- `$SLUG` → workspace slug
- `$PORT` → port for the first repo (or primary repo)
- `$WORKSPACE_PATH` → workspace root path (with `~` expanded to `$HOME`)

```bash
# Source the user's shell profile to get full PATH (bun, nvm, rbenv, etc.)
source ~/.zshrc 2>/dev/null || source ~/.bashrc 2>/dev/null || true

# Evaluate the hook string with substituted vars
eval "<hook_command_with_substitutions>"
```

**If any hook exits with a non-zero status:**
1. Display the error output clearly.
2. Attempt cleanup: remove worktrees with `git worktree remove --force`, remove the workspace directory with `rm -rf`.
3. Stop — do NOT update the registry.

### 6e — Update registry

Read the registry again (always re-read before writing to avoid races), add the new workspace entry, and update `next_slot`.

See references/registry-format.md for the exact schema.

New entry structure:

```json
{
  "<slot>": {
    "slug": "<slug>",
    "mode": "worktree",
    "branch": "<branch>",
    "color": "<hex-color>",
    "emoji": "<emoji>",
    "created_at": "<ISO-8601-timestamp>",
    "project_root": "<git-root>",
    "workspace_path": "<workspace_path>",
    "repos": [
      {
        "name": "<repo.name>",
        "path": "<worktree_path>",
        "port": <port>
      }
    ]
  }
}
```

Write the updated registry to `~/.claude-workspaces/registry.json`. **Use atomic write to prevent corruption** (see references/registry-format.md). Always re-read the registry before writing. Write the full JSON in a single operation. Create the directory if needed:

```bash
mkdir -p ~/.claude-workspaces
```

### 6f — Color the terminal

Apply the workspace color to the current terminal session. See references/color-palette.md for OSC sequences.

```bash
# Detect the parent terminal device (Claude Code captures stdout)
TTY_DEV="/dev/$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')"

# Set background color (OSC 11)
printf '\033]11;<hex-color>\007' > "$TTY_DEV" 2>/dev/null

# Set tab name (OSC 1) and window title (OSC 0)
printf '\033]1;<emoji> <branch> [w<slot>]\007' > "$TTY_DEV" 2>/dev/null
printf '\033]0;<emoji> <branch> [w<slot>]\007' > "$TTY_DEV" 2>/dev/null
```

---

## Step 7 — Summary

Show a concise success message. For example:

```
✓ Workspace created!

  🟣 [w3] feat/polo/export-csv
  Path: /Users/you/workspaces/feat-polo-export-csv

  Repos:
    back  →  /Users/you/workspaces/feat-polo-export-csv/back  (port 3030)
    front →  /Users/you/workspaces/feat-polo-export-csv/front (port 4030)

```

Then check if `.claude-workspaces.json` has a `terminal` section:

- **If `terminal` is configured** → ask:
  > Want me to open the dev layout? (WezTerm panes + servers + Claude tab)
  > 1. Yes — open layout now (`/workspace:open`)
  > 2. No — just show me the command

  If **1**, execute the `/workspace:open` skill flow (Steps 2-5 from the open skill, skipping Step 1 since we already know the workspace).

  If **2**, display:
  ```
  cd <workspace_path> && claude --name "<branch> [w<slot>]"
  ```

- **If no `terminal` section** → ask:
  > Want me to launch a Claude Code session in the workspace?
  > 1. Yes — launch now
  > 2. No — just show me the command

  - **1** → run:
    ```bash
    claude --name "<branch> [w<slot>]" --cwd "<workspace_path>"
    ```
  - **2** → display the command for the user to copy:
    ```
    cd <workspace_path> && claude --name "<branch> [w<slot>]"
    ```

---

## Rules

- **One question at a time.** Never ask multiple questions in a single message.
- **Never create without confirmation.** Always show the recap (Step 5) and wait for explicit approval.
- **If a hook fails, stop and clean up.** Do not leave partial state. Do not write to the registry.
- **Always read the registry before writing.** Never overwrite without reading first.
- **Expand `~` to `$HOME` in all paths** before running shell commands or writing files.
- **Gracefully handle missing files.** Registry may not exist yet — initialize it if absent.
