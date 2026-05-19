---
name: pull-staging
description: Pull staging data into the isolated workspace DB. One-shot pg_dump | psql into the workspace's <name>_w<slot> database. Safe — only touches the isolated DB, never the source. Triggers on "pull staging", "refresh DB", "get staging data", "sync staging", "pull la data".
allowed-tools: [Bash]
---

**Respond in the user's language.**

One-shot skill. No dialogue, no recap — just run the script. Auto-detects the current workspace from the working directory.

## Step 1 — Run

```bash
/bin/bash "${CLAUDE_PLUGIN_ROOT}/scripts/ws-db-pull-staging.sh" "${REPO:-}"
```

`REPO` is optional — if the user names a specific repo (e.g. "pull staging for back"), pass it as the first argument. Otherwise the script pulls for every repo in the workspace that has a DB.

## Step 2 — Report

Stream the script's output verbatim. On success, say:

> ✓ Staging data pulled into w$SLOT.

On failure (non-zero exit), surface the error message from the script — don't guess the cause.

---

## How it works (for reference)

For each repo, the script tries the following resolution order — first match wins:

1. **`hooks.db_pull_staging`** in `.claude-workspaces.json` — full control over dump flags, filtering, anonymization, re-encryption.
2. **`scripts/db/pull_db.sh staging`** (the project's own script) — invoked with `SKIP_CONFIRM=1`. Used when the project ships its own blessed pull tool (e.g. backend-sommesi-app, which auto-detects `LOCAL_DB_NAME` from `DATABASE_URL`, reads creds from `scripts/db/.env` in decomposed form `STAGING_DB_HOST/PORT/USER/PASS/NAME`, re-encrypts `FEATURE_ENCRYPTION_KEY`, and runs `db:migrate`).
3. **Fallback** — `pg_dump --clean --if-exists --no-owner --no-acl $STAGING_DATABASE_URL | psql $DATABASE_URL` in one pipe. Requires a single `STAGING_DATABASE_URL` env var in `.env.local`.

Safety check (every path): the target DB name must end with `_w<slot>`. If not, the script refuses — we never touch a non-isolated DB.

## Config — custom hook (optional)

In `.claude-workspaces.json`:

```json
{
  "hooks": {
    "db_pull_staging": "scripts/db/pull-staging.sh $DATABASE_URL"
  }
}
```

Substitutions available: `$SLOT`, `$WORKSPACE_PATH`, `$REPO_NAME`. The hook runs with the repo as cwd and inherits `.env.local` via the shell — reference `$DATABASE_URL` directly in the command.

## Rules

- **Never write to the source DB.** The script refuses if the target isn't `<name>_w<slot>`.
- **One-shot.** No confirmation prompt — the user invoked this skill explicitly.
- **Stream output.** Staging dumps can be large; user needs to see progress.
