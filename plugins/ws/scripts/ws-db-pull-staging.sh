#!/bin/bash
# ws-db-pull-staging.sh — Pull staging data into the isolated workspace DB.
# Usage: ws-db-pull-staging.sh [<repo_name>]
#
# Auto-detects the workspace from PWD via ~/.claude-workspaces/registry.json.
# For each repo (or the given one):
#   1. Read hooks.db_pull_staging from .claude-workspaces.json
#   2. Execute it with substitutions: $SLOT, $WORKSPACE_PATH, $REPO_NAME
#   3. Fallback: pg_dump $STAGING_DATABASE_URL | psql $DATABASE_URL
#      (requires STAGING_DATABASE_URL defined in the repo's .env.local)
#
# The DB stays isolated — we only touch the <name>_w<slot> database, never
# the source. Streams progress to stdout so the user sees what's happening.

set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

REPO_FILTER="${1:-}"

REG="$HOME/.claude-workspaces/registry.json"
[ -f "$REG" ] || { echo "❌ No registry at $REG" >&2; exit 1; }

# Detect workspace from cwd
eval "$(python3 -c "
import json, os
reg = json.load(open(os.path.expanduser('~/.claude-workspaces/registry.json')))
cwd = os.getcwd()
best_len = 0
best = None
best_slot = None
for slot, ws in reg.get('workspaces', {}).items():
    wp = ws.get('workspace_path', '')
    paths = [wp] + [r.get('path', '') for r in ws.get('repos', [])]
    for p in paths:
        if p and (cwd == p or cwd.startswith(p + os.sep)) and len(p) > best_len:
            best_len = len(p)
            best = ws
            best_slot = slot
if best:
    print(f'WS_PATH={best[\"workspace_path\"]!r}')
    print(f'SLOT={best_slot!r}')
    print(f'PROJECT_ROOT={best.get(\"project_root\", \"\")!r}')
" 2>/dev/null)"

if [ -z "${WS_PATH:-}" ] || [ -z "${SLOT:-}" ]; then
  echo "❌ Not inside a workspace (run from a workspace directory)" >&2
  exit 1
fi

CONFIG=""
for dir in "$WS_PATH" "${PROJECT_ROOT:-}"; do
  [ -n "$dir" ] && [ -f "$dir/.claude-workspaces.json" ] && CONFIG="$dir/.claude-workspaces.json" && break
done
[ -n "$CONFIG" ] || { echo "❌ No .claude-workspaces.json found" >&2; exit 1; }

echo "→ Workspace w$SLOT — pulling staging data"

# shellcheck disable=SC1090
source "$HOME/.zshrc" 2>/dev/null || source "$HOME/.bashrc" 2>/dev/null || true

WS_PATH="$WS_PATH" SLOT="$SLOT" CONFIG="$CONFIG" REPO_FILTER="$REPO_FILTER" python3 << 'PYEOF'
import json, os, re, subprocess, sys
from urllib.parse import urlparse

ws_path = os.environ['WS_PATH']
slot = int(os.environ['SLOT'])
repo_filter = os.environ.get('REPO_FILTER') or ''
config = json.load(open(os.environ['CONFIG']))
repos = config.get('repos', [])
hooks = config.get('hooks', {}) or {}
pull_hook = hooks.get('db_pull_staging')

def read_env(path):
    env = {}
    if not os.path.isfile(path):
        return env
    with open(path) as f:
        for line in f.read().split('\n'):
            m = re.match(r'^([A-Z_][A-Z0-9_]*)=(.*)$', line)
            if not m:
                continue
            k, v = m.group(1), m.group(2).strip()
            if v.startswith(('"', "'")) and v.endswith(v[0]) and len(v) >= 2:
                v = v[1:-1]
            env[k] = v
    return env

did_anything = False
exit_code = 0

for r in repos:
    name = r['name']
    if repo_filter and name != repo_filter:
        continue
    repo_path = os.path.join(ws_path, name)
    if not os.path.isdir(repo_path):
        continue

    env_local = os.path.join(repo_path, '.env.local')
    env_main = os.path.join(repo_path, '.env')
    env = {**read_env(env_main), **read_env(env_local)}

    target_url = env.get('DATABASE_URL')
    staging_url = env.get('STAGING_DATABASE_URL')

    # No DB for this repo → skip silently
    if not target_url and not pull_hook:
        continue

    did_anything = True
    print(f'→ {name}:')

    # Resolution order:
    #   1. Explicit `hooks.db_pull_staging` in config → run as-is.
    #   2. Project's own `scripts/db/pull_db.sh` → delegate. This is the
    #      blessed path for repos that have it (e.g. backend-sommesi-app):
    #      it auto-detects LOCAL_DB_NAME from DATABASE_URL (so the worktree's
    #      isolated DB is targeted), reads creds from scripts/db/.env in
    #      decomposed form (STAGING_DB_HOST/PORT/USER/PASS/NAME), re-encrypts
    #      FEATURE_ENCRYPTION_KEY, and runs db:migrate. Re-implementing all
    #      that here would just duplicate (and lag behind) the team's script.
    #   3. Fallback: `pg_dump $STAGING_DATABASE_URL | psql $DATABASE_URL`,
    #      requires a single URL var in .env.local.
    project_pull_db = os.path.join(repo_path, 'scripts', 'db', 'pull_db.sh')

    if pull_hook:
        cmd = pull_hook.replace('$SLOT', str(slot))
        cmd = cmd.replace('$WORKSPACE_PATH', ws_path)
        cmd = cmd.replace('$REPO_NAME', name)
        print(f'    running db_pull_staging hook')
        rc = subprocess.call(['/bin/bash', '-lc', cmd], cwd=repo_path)
        if rc != 0:
            print(f'    ✗ hook failed (exit {rc})', file=sys.stderr)
            exit_code = rc
            continue
    elif os.path.isfile(project_pull_db) and os.access(project_pull_db, os.X_OK):
        print(f'    delegating to scripts/db/pull_db.sh staging')
        # SKIP_CONFIRM=1 — we're already in a workspace-scoped context, the
        # outer skill will have asked the user. Pass DEBUG=1 only if the
        # caller already set it.
        env = os.environ.copy()
        env['SKIP_CONFIRM'] = '1'
        rc = subprocess.call(
            ['/bin/bash', project_pull_db, 'staging'],
            cwd=repo_path, env=env,
        )
        if rc != 0:
            print(f'    ✗ scripts/db/pull_db.sh failed (exit {rc})', file=sys.stderr)
            exit_code = rc
            continue
    else:
        # Default: pg_dump staging | psql target
        if not staging_url:
            print(f'    ↷ no STAGING_DATABASE_URL, no scripts/db/pull_db.sh, no db_pull_staging hook — skipped')
            continue
        try:
            tgt = urlparse(target_url)
            tgt_db = (tgt.path or '').lstrip('/')
        except Exception:
            print(f'    ✗ could not parse DATABASE_URL', file=sys.stderr)
            exit_code = 1
            continue

        # Safety: target must have the _w<slot> suffix (never touch non-isolated)
        if not tgt_db.endswith(f'_w{slot}'):
            print(f'    ✗ target {tgt_db} is not isolated (_w{slot}) — refusing', file=sys.stderr)
            exit_code = 1
            continue

        print(f'    pg_dump staging → {tgt_db}')
        # --clean --if-exists: drop existing objects first so we get a clean state
        # -Fc + pg_restore would be marginally faster but plain text SQL piped
        # directly into psql is zero-intermediate-file and works in one shot.
        cmd = (
            f'pg_dump --no-owner --no-acl --clean --if-exists '
            f'{staging_url!r} | psql {target_url!r}'
        )
        proc = subprocess.run(['/bin/bash', '-lc', cmd], cwd=repo_path)
        if proc.returncode != 0:
            print(f'    ✗ pull failed (exit {proc.returncode})', file=sys.stderr)
            exit_code = proc.returncode
            continue

    print(f'    ✓ {name} done')

if not did_anything:
    print('  (no matching repos with DB)')

sys.exit(exit_code)
PYEOF
