---
name: start-worktree
description: Create a new isolated workspace with git worktree. Use when the user wants to start working on a new feature, bugfix, or task in an isolated branch. Triggers on "new feature", "start working on", "create workspace", "new worktree", "isolate work".
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion, mcp__notion__notion-query-data-sources, mcp__notion__notion-update-page]
---

**Respond in the user's language.**

You are creating a new isolated workspace using `git worktree`. Follow the steps below **in order**.

---

## Step 1 — Preflight (already run)

The preflight ran when this skill loaded (current git root). Output:

```json
!`/bin/bash "${CLAUDE_PLUGIN_ROOT}/scripts/ws-preflight.sh" 2>/dev/null`
```

If the block above shows a literal `!`-command instead of JSON, injection is unsupported: run the command yourself (one Bash call).

**Do NOT re-run it** — unless the user targets another project than the current directory, then run once:
`/bin/bash "${CLAUDE_PLUGIN_ROOT}/scripts/ws-preflight.sh" "<project_root>"`

### If the output contains `"error": "not_a_git_repo"`

Stop and tell the user:
> This directory is not inside a git repository. Use `/workspace:start-sandbox` instead.

### If the output contains `"error": "no_config"`

Guide the user through creating `.claude-workspaces.json` — see Appendix A at the bottom of this file.

### If the output contains `"missing_origins"`

Ask the user for the missing repo paths and offer to save them to `.claude-workspaces.local.json`.

### Otherwise

Parse the JSON output. You now have:
- `git_root`, `config`, `free_slot`, `color`, `emoji`, `repos_with_ports`, `workspaces_root`, `port_step`

Continue to Step 2.

---

## Step 2 — Derive branch, goal, spec from user message

**DO NOT ask the user for these — extract them from the conversation.**

### Step 2a — Pick a sprint card (only if `config.notion` exists)

Run this **only when** `config.notion` is set **and** the user's message has no clear goal (e.g. just "start worktree"), or mentions the sprint / Notion / "mes cartes". If the user already described the task, skip to the derivation below — no extra call.

1. `week` = ISO week number of today (`%V`, no leading zero). Sprint value = `config.notion.sprint_format` with `{week}` replaced (e.g. `"Sprint {week}"` → `"Sprint 44"`).
2. **Your very first tool call** — no thinking out loud, no text before it — is **one** call to `mcp__notion__notion-query-data-sources`:
   ```json
   {"data": {"mode": "rows", "data_source_url": "<config.notion.data_source>", "limit": 30,
     "filter": {"type": "group", "operator": "and", "filters": [
       {"type": "property", "property": "<config.notion.sprint_property>", "propertyType": "multi_select",
        "operator": "enum_contains", "value": {"type": "exact", "value": "<sprint value>"}},
       {"type": "property", "property": "<config.notion.assignee_property>", "propertyType": "person",
        "operator": "person_contains", "value": {"type": "relative", "value": "me"}}
     ]}}}
   ```
3. Drop rows whose `<config.notion.status_property>` is in `config.notion.exclude_status`. Sort by priority (Critical → Low).
4. **No cards / Notion error** → say so in one line and fall back to the normal derivation (ask for the goal only if the message has none).
5. Otherwise, immediately `AskUserQuestion` (single-select, max 4 options — top 4 by priority; "Other" covers free text):
   - label: card title (strip HTML, ≤ 5 words), description: `<Type> · <Feature> · <Priority> · <Statut>`.
6. From the chosen card:
   - **Goal** = title + `Description générale` (if any)
   - **Branch** = `<prefix>/<feature-slug>/task-<ID>-<2–3 title keywords>`, prefix from `Type`: `Bug`→`fix`, `Refacto`→`refactor`, `Documentation`→`docs`, else `feat`; `<ID>` = `userDefined:ID`. **Keep `task-<ID>`** — the GitHub Action moves the card (In Review / Staging / Production) by finding it in the branch name.
   - **Spec** = card `url`
7. After the pick, go **straight to the Step 3 recap** in the same reply (no tool call in between).

If the user picks "Other", treat their text as the goal and continue below.

### Step 2b — Derive

- **Goal**: what the user described wanting to do. If unclear, use a short summary.
- **Branch**: derive from the goal using conventional format (`feat/*`, `fix/*`, `chore/*`, `refactor/*`, `docs/*`, `test/*`, `style/*`, `perf/*`). Extract 2–4 keywords, slugify. **Pure string manipulation — NO tool calls.**
- **Spec**: if the user mentioned a ticket/URL, use it. Otherwise `none`.

If the user explicitly provided a branch name, use it as-is.

Compute:
- `slot` = `free_slot` from preflight
- `slug` = branch with `/` replaced by `-`
- `workspace_path` = `<workspaces_root>/<slug>`
- ports from `repos_with_ports`

### Optional repos (opt-in)

Some repos in `repos_with_ports` may have `"optional": true`. These are **skipped by default** — most workspaces don't need them, and skipping a repo avoids an extra worktree + base-branch pull.

Include an optional repo **only when the user's message explicitly asks for it** (e.g. "with webhook", "avec le webhook", "+ webhook"). Build:

- `WS_INCLUDE` = comma-separated names of the optional repos to include (empty string if none).

Non-optional repos are always created.

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

**List only the repos that will be created** (non-optional repos + any in `WS_INCLUDE`). If there are optional repos you are NOT including, add a one-line hint so the user knows they exist, e.g.:

```
  (webhook is optional and skipped — say "with webhook" to include it)
```

Wait for the user's response. Accept: `y`, `yes`, `o`, `oui`, or empty. **Anything else cancels.**

---

## Step 4 — Create the workspace (single Bash call, in the background)

Run the orchestrator **with `run_in_background: true`** (it takes ~30–60 s: git pulls, DB clones, installs). Right after launching, tell the user in one line that the workspace is being created and that they can keep talking (e.g. describe the feature); do not poll — the completion notification triggers Step 5. It chains **worktree creation → file generation → DB isolation → post_create hook → registry update → terminal color** in one bash process.

```bash
WS_INCLUDE="<comma-separated optional repos, or empty>" \
/bin/bash "${CLAUDE_PLUGIN_ROOT}/scripts/ws-create.sh" \
  "<workspace_path>" "<slot>" "<branch>" "<color>" "<emoji>" "<git_root>" "<spec>" "<goal>"
```

**If the workspace comes from a Notion card**, send in the **same message** as the Bash call above (parallel, zero added latency) one `mcp__notion__notion-update-page` call: `{"page_id": "<card url>", "command": "update_properties", "allow_async": true, "properties": {"<config.notion.status_property>": "🔄 In Progress"}}`. A Notion failure never blocks creation — mention it in one line at the end.

`WS_INCLUDE` opts optional repos in (see Step 2). Omit it or pass `""` to create only the default (non-optional) repos.

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
