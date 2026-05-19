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

### 6a–6d — Orchestrated creation (1 single script call)

Run the orchestrator. It chains **worktree creation → file generation → DB isolation → post_create hook** in a single bash process. This collapses what used to be 4 separate tool calls into one, eliminating the 30s–60s of LLM ping-pong overhead per inter-step transition (was the dominant cost — minutes saved).

```bash
/bin/bash "${CLAUDE_PLUGIN_ROOT}/scripts/ws-create.sh" \
  "<workspace_path>" "<slot>" "<branch>" "<color>" "<emoji>" "<git_root>" "<spec>" "<goal>"
```

What the orchestrator does internally:
- **6a** — `ws-worktree-create.sh`: parallel `git worktree add` per repo, plus base-branch pull. Fails LOUDLY now if all 3 add-attempts fail (e.g. ref-collision like `feat/ats` blocking `feat/ats/sub`).
- **6b** — `ws-generate-files.sh`: CLAUDE.local.md, .worktree-env.sh, .vscode/settings.json, .code-workspace, .env.local with port substitution, Rails credentials (`config/master.key`, `config/credentials/*.key`). See references/generated-files.md.
- **6c** — `ws-db-isolate.sh`: rewrites local `DATABASE_URL` / `CACHE_DATABASE_URL` / etc. to `<name>_w<slot>` (remote hosts left alone), mirrors into `scripts/db/.env`, and clones the local source DB via `CREATE DATABASE … TEMPLATE`. Fallback to `bin/rails db:create db:schema:load` if no source DB exists locally. Honors `hooks.db_create` if defined.
- **6d** — runs `hooks.post_create` with variable substitution: `$SLOT`, `$BRANCH`, `$SLUG`, `$PORT` (first repo's port), `$WORKSPACE_PATH`. Shell profile sourced so `bundle`/`bun`/`nvm`/`rbenv` are in PATH.

**On failure** the orchestrator self-cleans (removes any partial worktrees, deletes `$WS_PATH`) and exits non-zero. **Do NOT update the registry** in that case — stop and report the error to the user. The script prints timing logs to stderr (`[Δ Nms │ Σ Nms]`) so you can see exactly which sub-step blew up.

Staging data is **not** pulled here — that's a separate on-demand skill.

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
