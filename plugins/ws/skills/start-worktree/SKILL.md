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

**Run the ws-generate-files.sh script** — it handles everything in one shot (CLAUDE.local.md, .worktree-env.sh, .vscode/settings.json per repo, .code-workspace, .env.local with port substitution):

```bash
CONFIG="<config_path>" PROJECT_ROOT="<git_root>" /bin/bash "${CLAUDE_PLUGIN_ROOT}/scripts/ws-generate-files.sh" "<workspace_path>" "<slot>" "<branch>" "<color>" "<emoji>" "worktree" "<spec>" "<goal>"
```

See references/generated-files.md for details on what gets generated.

### 6d — Database isolation (automatic)

Automatically detect and create an isolated database for the worktree. This runs **before** hooks and **without any configuration** from the user.

**Detection**: For each repo, check for database configuration:
- **Rails**: look for `config/database.yml` and/or `DATABASE_URL` in `.env.local`
- **Node/Next.js**: look for `DATABASE_URL` in `.env.local`

**If a database is detected**:

1. Parse the current database name from `DATABASE_URL` or `database.yml` (e.g. `sommesi_app_development`)
2. Create an isolated database name: `<original_name>_w<slot>` (e.g. `sommesi_app_development_w5`)
3. Update `DATABASE_URL` in the worktree's `.env.local` to point to the new database name
4. If there are multiple databases (cache, queue, cable), create isolated versions for each:
   - `sommesi_app_development_cache_w5`
   - `sommesi_app_development_queue_w5`
   - `sommesi_app_development_cable_w5`
5. Clone the database from staging (or main dev DB if staging is not available):

```bash
# Source shell profile for PATH
source ~/.zshrc 2>/dev/null || source ~/.bashrc 2>/dev/null || true

cd <workspace_path>/<repo_name>

# Rails: create DB and load schema
bin/rails db:create
bin/rails db:schema:load

# If a db_create hook is defined, run it instead of the above
```

6. If a `db_create` hook is defined in `.claude-workspaces.json`, run that **instead** of the automatic commands above (the hook has priority).

**If no database is detected**, skip this step silently.

### 6e — Execute hooks

If hooks are defined in the config, run them in this order: `post_create`, then `db_create` (if not already handled in 6d).

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

```bash
/bin/bash "${CLAUDE_PLUGIN_ROOT}/scripts/ws-color.sh" "<workspace_path>"
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

Then ask:

> Want me to open the dev layout? (`/workspace:open`)
> 1. Yes — open now
> 2. No

If **1**, execute the `/workspace:open` skill (skipping Step 1 since we already know the workspace).

---

## Rules

- **One question at a time.** Never ask multiple questions in a single message.
- **Never create without confirmation.** Always show the recap (Step 5) and wait for explicit approval.
- **If a hook fails, stop and clean up.** Do not leave partial state. Do not write to the registry.
- **Always read the registry before writing.** Never overwrite without reading first.
- **Expand `~` to `$HOME` in all paths** before running shell commands or writing files.
- **Gracefully handle missing files.** Registry may not exist yet — initialize it if absent.
