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

## Step 3 — Interactive dialogue (one combined ask)

Ask the three inputs **in a single message** to minimize LLM ping-pong. The user can reply with short answers inline (one per line is fine).

```
Pour créer ce workspace, j'ai besoin de 3 infos :

  1. Goal — décris brièvement le but (2–3 phrases, ira dans CLAUDE.local.md)
  2. Branch — format conventionnel (feat/*, fix/*, chore/*, refactor/*, docs/*, test/*, style/*, perf/*)
     → si tu donnes juste le goal, je proposerai un nom ; tu pourras corriger au recap
  3. Spec — lien ticket/doc (optionnel, "skip" pour ignorer)
```

**If the user gives only the goal**, auto-derive a branch name following conventional format (e.g. goal "ajouter l'export CSV pour Polo" → `feat/polo/export-csv`).

**Branch name derivation is pure string manipulation — DO NOT use any tools.** No `Read`, no `Grep`, no `Glob`, no `Bash`, no codebase exploration. Just: pick a conventional prefix from the goal's verb (`ajouter/feat`, `fix/fix`, `refactor/refactor`, …), extract 2–4 keywords, slugify them, and join with `/`. The user validates at Step 5 and corrects if needed — that's the whole point of the recap. Spending tool calls to "verify" names defeats the optimization.

**If the user provides all 3 upfront**, skip to Step 4 directly.

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

### 6a — Create worktrees (1 script call)

Run the orchestration script — it handles `mkdir -p`, git worktree with automatic fallback (new branch / existing local / existing remote), and the base-branch pull for every repo. Repos are cloned **in parallel** internally:

```bash
/bin/bash "${CLAUDE_PLUGIN_ROOT}/scripts/ws-worktree-create.sh" "<workspace_path>" "<branch>" "<git_root>"
```

If this exits non-zero, stop and clean up (see Rules below).

### 6b — Generate workspace files (1 script call)

Run `ws-generate-files.sh` — it handles CLAUDE.local.md, .worktree-env.sh, .vscode/settings.json per repo, .code-workspace, .env.local with port substitution, **and copies Rails credentials** (`config/master.key`, `config/credentials/*.key`) so the new worktree can boot without manual setup:

```bash
CONFIG="<config_path>" PROJECT_ROOT="<git_root>" /bin/bash "${CLAUDE_PLUGIN_ROOT}/scripts/ws-generate-files.sh" "<workspace_path>" "<slot>" "<branch>" "<color>" "<emoji>" "worktree" "<spec>" "<goal>"
```

See references/generated-files.md for details on what gets generated.

### 6c — Database isolation (1 script call)

Run `ws-db-isolate.sh` — it:
1. Rewrites all local DB URLs (`DATABASE_URL`, `CACHE_DATABASE_URL`, `QUEUE_DATABASE_URL`, `CABLE_DATABASE_URL`) in `.env.local`/`.env` to `<name>_w<slot>`. Remote hosts (staging/prod) are left untouched.
2. Mirrors the isolated `.env.local` into `scripts/db/.env` when that dir exists.
3. **Clones the local source DB into the isolated DB** via `CREATE DATABASE ... TEMPLATE` (quasi-instantané, copie fichier sur le même serveur Postgres — la workspace démarre avec la vraie data locale, pas un schéma vide). Falls back to `bin/rails db:create db:schema:load` if the source DB doesn't exist locally. A custom `db_create` hook overrides the default.
4. Pulling **staging** data is **not** done here — c'est plus lent et pas toujours voulu. Utiliser une skill dédiée à la demande.

Repos are processed **in parallel**:

```bash
/bin/bash "${CLAUDE_PLUGIN_ROOT}/scripts/ws-db-isolate.sh" "<workspace_path>" "<slot>"
```

Silent no-op when no database is detected.

### 6d — Execute post_create hook

If `hooks.post_create` is defined in the config, run it with variable substitution:
- `$SLOT` → slot number
- `$BRANCH` → branch name
- `$SLUG` → workspace slug
- `$PORT` → port for the first repo
- `$WORKSPACE_PATH` → workspace root path (with `~` expanded to `$HOME`)

```bash
# Source shell profile to get full PATH (bun, nvm, rbenv, etc.)
source ~/.zshrc 2>/dev/null || source ~/.bashrc 2>/dev/null || true
eval "<hook_command_with_substitutions>"
```

**If the hook exits non-zero:**
1. Display the error output.
2. Clean up: `git worktree remove --force` for each repo, then `rm -rf <workspace_path>`.
3. Stop — do NOT update the registry.

Note: `db_create` is handled by `ws-db-isolate.sh` in Step 6c — do not re-run it here.

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

### 6f — Color the terminal (optional — only if run interactively in a workspace-aware terminal)

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
- **Do NOT spawn subagents or reimplement script work inline.** Parallelism is internal to the shell scripts (worktree creation and DB isolation fan out across repos). Stick to the script calls — do not rewrite env files with inline `python3 -c` or re-run steps "just to be sure". For long `post_create` installs across repos, prefer shell-level parallelism in the hook itself (e.g. `(cd back && bundle install) & (cd front && bun install) & wait`).
