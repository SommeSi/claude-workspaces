---
name: start-worktree
description: Create a new isolated workspace with git worktree. Use when the user wants to start working on a new feature, bugfix, or task in an isolated branch. Triggers on "new feature", "start working on", "create workspace", "new worktree", "isolate work".
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

**Respond in the user's language.**

You are creating a new isolated workspace using `git worktree`. Follow the steps below **in order**.

---

## Step 1 — Preflight (single Bash call)

Run the preflight script to gather everything at once — git root, config (shared + local merged), registry, free slot, color, ports:

```bash
/bin/bash "${CLAUDE_PLUGIN_ROOT}/scripts/ws-preflight.sh" "[project_root_if_known]"
```

Omit the argument to auto-detect from current git root.

### If the output contains `"error": "not_a_git_repo"`

Stop and tell the user:
> This directory is not inside a git repository. Use `/workspace:start-sandbox` instead.

### If the output contains `"error": "no_config"`

Guide the user through creating `.claude-workspaces.json` — see Appendix A at the bottom of this file.

### If the output contains `"missing_origins"`

Ask the user for the missing repo paths and offer to save them to `.claude-workspaces.local.json`.

### Otherwise

Parse the JSON output. You now have:
- `git_root`, `config`, `registry`, `free_slot`, `color`, `emoji`, `repos_with_ports`, `workspaces_root`, `port_step`

Continue to Step 2.

---

## Step 2 — Derive branch, goal, spec from user message

**DO NOT ask the user for these — extract them from the conversation.**

- **Goal**: what the user described wanting to do. If unclear, use a short summary.
- **Branch**: derive from the goal using conventional format (`feat/*`, `fix/*`, `chore/*`, `refactor/*`, `docs/*`, `test/*`, `style/*`, `perf/*`). Extract 2–4 keywords, slugify. **Pure string manipulation — NO tool calls.**
- **Spec**: if the user mentioned a ticket/URL, use it. Otherwise `none`.

If the user explicitly provided a branch name, use it as-is.

Compute:
- `slot` = `free_slot` from preflight
- `slug` = branch with `/` replaced by `-`
- `workspace_path` = `<workspaces_root>/<slug>`
- ports from `repos_with_ports`

---

## Step 3 — Recap and confirm

Show a clear summary. Example:

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

Wait for the user's response. Accept: `y`, `yes`, `o`, `oui`, or empty. **Anything else cancels.**

---

## Step 4 — Create the workspace (single Bash call)

Run the orchestrator. It chains **worktree creation → file generation → DB isolation → post_create hook → registry update → terminal color** in one bash process.

```bash
/bin/bash "${CLAUDE_PLUGIN_ROOT}/scripts/ws-create.sh" \
  "<workspace_path>" "<slot>" "<branch>" "<color>" "<emoji>" "<git_root>" "<spec>" "<goal>"
```

What it does internally:
- **worktree-create**: parallel `git worktree add` per repo + base-branch pull
- **generate-files**: CLAUDE.local.md, .worktree-env.sh, .vscode/settings.json, .code-workspace, .env.local with port substitution, Rails credentials
- **db-isolate**: rewrites DATABASE_URL / CACHE_DATABASE_URL / etc. to `<name>_w<slot>`, clones via `CREATE DATABASE … TEMPLATE`. Fallback to `bin/rails db:create db:schema:load`
- **post_create hook**: runs with `$SLOT`, `$BRANCH`, `$SLUG`, `$PORT`, `$WORKSPACE_PATH` substitution
- **registry update**: adds the workspace entry atomically
- **terminal color**: applies the workspace color

**On failure** the orchestrator self-cleans (removes worktrees + branches, deletes `$WS_PATH`) and exits non-zero. The registry is NOT updated. Stop and report the error.

---

## Step 5 — Summary

Show a concise success message:

```
✓ Workspace created!

  🟣 [w3] feat/polo/export-csv
  Path: /Users/you/workspaces/feat-polo-export-csv

  Repos:
    back  →  port 3030
    front →  port 4030
```

Then ask:

> Want me to open the dev layout? (`/workspace:open`)

---

## Rules

- **Never create without confirmation.** Always show the recap (Step 3) and wait for explicit approval.
- **If a hook fails, stop and report.** Do not leave partial state.
- **Expand `~` to `$HOME` in all paths** before running shell commands.
- **Do NOT spawn subagents or reimplement script work inline.**
- **Do NOT use tool calls to derive branch names.** Pure string manipulation only.

---

## Appendix A — Creating a new config

Guide the user through creating `.claude-workspaces.json`, **one question at a time**:

1. **How many repositories does this project use?** (1 for single repo, or a number for multi-repo)
2. For **each repo**, ask:
   - **Name** (e.g. `back`, `front`, `app`)
   - **Port base** (e.g. `3000`)
   - **Is this the current repo?** If yes, `origin` is `"."`. If no, ask for the relative path — explain this goes in the **local** config.
3. **Where should workspaces be created?** (default: `~/workspaces`)
4. **Port step** — how many ports to skip between slots? (default: `10`)
5. **Any setup hooks?** (all optional):
   - `post_create` — runs after worktree is created (e.g. `bundle install`, `yarn install`)
   - `db_create` — sets up a database
   - `db_destroy` — tears down the database

Generate **two JSON files** and show for confirmation:

**Shared** (`.claude-workspaces.json` — committed):
```json
{
  "workspaces_root": "~/workspaces",
  "port_step": 10,
  "repos": [
    { "name": "back", "origin": ".", "port_base": 3001 },
    { "name": "front", "port_base": 3000 }
  ],
  "hooks": {
    "post_create": "cd $WORKSPACE_PATH/back && bundle install"
  }
}
```

**Local** (`.claude-workspaces.local.json` — gitignored):
```json
{
  "repos": {
    "front": { "origin": "../frontend-app" }
  }
}
```

Check if `.claude-workspaces.local.json` is in `.gitignore`. Then re-run Step 1 (preflight).
