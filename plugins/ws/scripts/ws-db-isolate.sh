#!/bin/bash
# ws-db-isolate.sh — Isolate databases for a worktree (1-shot).
# Usage: ws-db-isolate <workspace_path> <slot>
#
# For each repo that has a DATABASE_URL in .env.local or config/database.yml:
#   1. Parse the original database name(s)
#   2. Rewrite .env.local so DATABASE_URL (+ cache/queue/cable variants) point to
#      <original>_w<slot>
#   3. If a db_create hook is defined in .claude-workspaces.json, run it
#      Otherwise, for Rails, run `bin/rails db:create && bin/rails db:schema:load`
#
# Safe to run multiple times: existing isolated DBs are skipped.
# Silent exit when no DB is detected.

set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

usage() {
  cat >&2 <<EOF
Usage: ws-db-isolate.sh [<workspace_path> <slot>]

With no arguments, the script auto-detects the current workspace from PWD
via ~/.claude-workspaces/registry.json.

Examples:
  # Auto-detect from current directory:
  cd ~/projects/worktrees/feat-xxx && ws-db-isolate.sh

  # Explicit:
  ws-db-isolate.sh /Users/you/projects/worktrees/feat-xxx 6
EOF
  exit 1
}

WS_PATH="${1:-}"
SLOT="${2:-}"

# Auto-detect from registry if args missing
if [ -z "$WS_PATH" ] || [ -z "$SLOT" ]; then
  REG="$HOME/.claude-workspaces/registry.json"
  if [ ! -f "$REG" ]; then
    echo "❌ No registry found at $REG" >&2
    usage
  fi
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
" 2>/dev/null)"

  if [ -z "${WS_PATH:-}" ] || [ -z "${SLOT:-}" ]; then
    echo "❌ Could not auto-detect workspace from $(pwd)" >&2
    usage
  fi
  echo "→ Auto-detected: slot=$SLOT path=$WS_PATH"
fi

# Locate config (honor CONFIG/PROJECT_ROOT passed via env first)
CONFIG="${CONFIG:-}"
PROJECT_ROOT="${PROJECT_ROOT:-}"
if [ -z "$CONFIG" ] || [ ! -f "$CONFIG" ]; then
  CONFIG=""
  PROJECT_ROOT=""
  for dir in "$WS_PATH" "$(git -C "$WS_PATH" rev-parse --show-toplevel 2>/dev/null || echo '')"; do
    [ -n "$dir" ] && [ -f "$dir/.claude-workspaces.json" ] && CONFIG="$dir/.claude-workspaces.json" && PROJECT_ROOT="$dir" && break
  done
fi

# Fallback via registry
if [ -z "$CONFIG" ] && [ -f "$HOME/.claude-workspaces/registry.json" ]; then
  eval "$(python3 -c "
import json, os
reg = json.load(open(os.path.expanduser('~/.claude-workspaces/registry.json')))
ws = '$WS_PATH'
for s, w in reg.get('workspaces', {}).items():
    if w.get('workspace_path') == ws:
        pr = w.get('project_root', '')
        if pr and os.path.isfile(os.path.join(pr, '.claude-workspaces.json')):
            print(f'CONFIG={os.path.join(pr, \".claude-workspaces.json\")!r}')
            print(f'PROJECT_ROOT={pr!r}')
        break
" 2>/dev/null)" 2>/dev/null || true
fi

[ -z "$CONFIG" ] && { echo "  (skipped: no config found)"; exit 0; }

# Source shell profile for full PATH (bun, nvm, rbenv, bundler, etc.)
# Temporarily disable -u/-e: user profiles reference unset vars that would
# otherwise kill this script silently (before the fix this caused step 6c
# to return in ~5ms with no output and no error).
# shellcheck disable=SC1090
set +ue
source "$HOME/.zshrc" 2>/dev/null || source "$HOME/.bashrc" 2>/dev/null || true
set -ue

WS_PATH="$WS_PATH" SLOT="$SLOT" CONFIG="$CONFIG" python3 << 'PYEOF'
import json, os, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from urllib.parse import urlparse, urlunparse

ws_path = os.environ['WS_PATH']
slot = int(os.environ['SLOT'])
config = json.load(open(os.environ['CONFIG']))
repos = config.get('repos', [])
hooks = config.get('hooks', {}) or {}
db_create_hook = hooks.get('db_create')

# Any env var that looks like a DB connection URL.
# Rule: ALL_CAPS key that contains DATABASE and ends with _URL.
# Matches: DATABASE_URL, CACHE_DATABASE_URL, DATABASE_CACHE_URL,
#          DATABASE_QUEUE_URL, PRIMARY_DATABASE_URL, LEGACY_DATABASE_URL, etc.
_KEY_SHAPE = re.compile(r'^[A-Z][A-Z0-9_]*$')

def is_db_url_key(key: str) -> bool:
    return bool(_KEY_SHAPE.match(key)) and 'DATABASE' in key and key.endswith('_URL')

def isolate_db_name(name: str, slot: int) -> str:
    suffix = f'_w{slot}'
    return name if name.endswith(suffix) else f'{name}{suffix}'

LOCAL_HOSTS = {'localhost', '127.0.0.1', '::1', 'host.docker.internal', ''}

def rewrite_url(url: str, slot: int) -> str:
    """Rewrite DB name only for LOCAL URLs. Remote hosts (staging, prod, legacy)
    are left untouched to avoid accidental isolation of shared/remote databases."""
    try:
        parsed = urlparse(url)
        if not parsed.scheme.startswith(('postgres', 'mysql', 'sqlite')):
            return url
        host = (parsed.hostname or '').lower()
        if host not in LOCAL_HOSTS:
            return url
        path = parsed.path or ''
        if path.startswith('/'):
            db = path[1:]
            if not db:
                return url
            new_path = '/' + isolate_db_name(db, slot)
            return urlunparse(parsed._replace(path=new_path))
    except Exception:
        pass
    return url

def rewrite_env_local(env_file: str, slot: int) -> bool:
    if not os.path.isfile(env_file):
        return False
    changed = False
    out = []
    with open(env_file) as f:
        for line in f.read().split('\n'):
            m = re.match(r'^([A-Z_][A-Z0-9_]*)=(.*)$', line)
            if m and is_db_url_key(m.group(1)):
                key, val = m.group(1), m.group(2)
                # Strip optional surrounding quotes
                stripped = val.strip()
                q = ''
                if stripped.startswith(('"', "'")) and stripped.endswith(stripped[0]) and len(stripped) >= 2:
                    q = stripped[0]
                    stripped = stripped[1:-1]
                new_val = rewrite_url(stripped, slot)
                if new_val != stripped:
                    out.append(f'{key}={q}{new_val}{q}')
                    changed = True
                    continue
            out.append(line)
    if changed:
        with open(env_file, 'w') as f:
            f.write('\n'.join(out))
    return changed


def read_db_urls(env_file: str):
    """Return {KEY: url} for every DB URL key in an env file (unquoted values)."""
    result = {}
    if not os.path.isfile(env_file):
        return result
    with open(env_file) as f:
        for line in f.read().split('\n'):
            m = re.match(r'^([A-Z_][A-Z0-9_]*)=(.*)$', line)
            if not m:
                continue
            key, val = m.group(1), m.group(2)
            if not is_db_url_key(key):
                continue
            stripped = val.strip()
            if stripped.startswith(('"', "'")) and stripped.endswith(stripped[0]) and len(stripped) >= 2:
                stripped = stripped[1:-1]
            result[key] = stripped
    return result


def clone_local_pg(isolated_url: str, slot: int) -> tuple:
    """Clone the source dev DB into the isolated DB via CREATE DATABASE TEMPLATE.
    Near-instant (file copy) on the same Postgres server. Requires no active
    connections on the source — we terminate them first.

    Returns (ok: bool, message: str). Only handles local Postgres.
    """
    try:
        parsed = urlparse(isolated_url)
    except Exception as e:
        return False, f'url parse failed: {e}'
    if not parsed.scheme.startswith('postgres'):
        return False, 'not postgres'
    host = (parsed.hostname or '').lower()
    if host not in LOCAL_HOSTS:
        return False, f'remote host ({host}) — skipped for safety'
    path = (parsed.path or '').lstrip('/')
    if not path:
        return False, 'no db name in url'
    isolated_db = path
    suffix = f'_w{slot}'
    if not isolated_db.endswith(suffix):
        return False, f'isolated db {isolated_db} missing {suffix} suffix'
    source_db = isolated_db[: -len(suffix)]

    # Admin connection URL (connect to 'postgres' DB to run CREATE/DROP)
    admin = parsed._replace(path='/postgres')
    admin_url = urlunparse(admin)

    # Each statement must run in its own transaction — DROP/CREATE DATABASE
    # are forbidden inside a transaction block. psql wraps multi-statement -c
    # in ONE transaction, so we use multiple -c flags (each = its own tx).
    cmd = [
        'psql', admin_url, '-v', 'ON_ERROR_STOP=1',
        '-c',
        f"SELECT pg_terminate_backend(pid) FROM pg_stat_activity "
        f"WHERE datname = '{source_db}' AND pid <> pg_backend_pid();",
        '-c', f'DROP DATABASE IF EXISTS "{isolated_db}";',
        '-c', f'CREATE DATABASE "{isolated_db}" TEMPLATE "{source_db}";',
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        return False, (proc.stderr or proc.stdout or 'psql failed').strip()
    return True, f'{source_db} → {isolated_db}'

def rewrite_database_yml(database_yml: str, slot: int) -> bool:
    """Rewrite hardcoded DB names under development: in Rails config/database.yml.
    Needed because Rails only honors DATABASE_URL for the primary connection.
    Secondary DBs (cache/queue/cable in Solid Queue/Cache/Cable) read the
    hardcoded `database:` key directly — without this rewrite, every worktree's
    workers collide on the same queue DB and steal each other's jobs."""
    if not os.path.isfile(database_yml):
        return False
    suffix = f'_w{slot}'
    with open(database_yml) as f:
        lines = f.read().split('\n')
    in_dev = False
    changed = False
    out = []
    for line in lines:
        # Track whether we're inside development: block (top-level only)
        if re.match(r'^development\s*:', line):
            in_dev = True
            out.append(line)
            continue
        if in_dev and re.match(r'^\S', line):
            in_dev = False
        if in_dev:
            m = re.match(r'^(\s*database\s*:\s*)(\S+)(.*)$', line)
            if m:
                prefix, name, rest = m.group(1), m.group(2), m.group(3)
                # Skip ERB (env-driven names)
                if '<%' not in name and not name.endswith(suffix):
                    new_line = f'{prefix}{name}{suffix}{rest}'
                    out.append(new_line)
                    changed = True
                    continue
        out.append(line)
    if changed:
        with open(database_yml, 'w') as f:
            f.write('\n'.join(out))
    return changed


def parse_rails_db_names(database_yml: str):
    """Return list of DB names from Rails config/database.yml (development env)."""
    if not os.path.isfile(database_yml):
        return []
    try:
        import yaml  # optional; fallback to regex
        data = yaml.safe_load(open(database_yml))
    except Exception:
        data = None

    names = []
    if isinstance(data, dict):
        dev = data.get('development', {})
        if isinstance(dev, dict):
            if 'database' in dev:
                names.append(dev['database'])
            else:
                # Multi-DB (primary, cache, queue, cable)
                for key, val in dev.items():
                    if isinstance(val, dict) and 'database' in val:
                        names.append(val['database'])
    if not names:
        # Regex fallback for simple cases
        with open(database_yml) as f:
            text = f.read()
        in_dev = False
        for line in text.split('\n'):
            if re.match(r'^development\s*:', line):
                in_dev = True
                continue
            if in_dev and re.match(r'^\S', line):
                break
            if in_dev:
                m = re.search(r'database\s*:\s*(\S+)', line)
                if m:
                    names.append(m.group(1))
    return names

def process_repo(r):
    """Rewrite URLs + run db:create for one repo. Returns (name, log, rc)."""
    import io
    import shutil
    repo_name = r['name']
    repo_path = os.path.join(ws_path, repo_name)
    buf = io.StringIO()

    if not os.path.isdir(repo_path):
        return (repo_name, '', 0, False)

    env_local = os.path.join(repo_path, '.env.local')
    env_main = os.path.join(repo_path, '.env')
    database_yml = os.path.join(repo_path, 'config', 'database.yml')

    has_url = False
    for ef in (env_local, env_main):
        if os.path.isfile(ef):
            with open(ef) as fh:
                for line in fh:
                    m = re.match(r'^([A-Z_][A-Z0-9_]*)=', line)
                    if m and is_db_url_key(m.group(1)):
                        has_url = True
                        break
            if has_url:
                break

    has_rails = os.path.isfile(database_yml)

    if not has_url and not has_rails:
        return (repo_name, '', 0, False)

    print(f'  → {repo_name}: isolating databases', file=buf)

    for ef in (env_local, env_main):
        if rewrite_env_local(ef, slot):
            print(f'    ✓ {os.path.basename(ef)} rewritten', file=buf)

    # Rewrite config/database.yml — secondary DBs (cache/queue/cable) are not
    # overridden by DATABASE_URL, so their hardcoded names must be suffixed.
    if rewrite_database_yml(database_yml, slot):
        print(f'    ✓ config/database.yml rewritten', file=buf)

    # scripts/db/.env holds STAGING/PROD credentials used by pull_db.sh etc.
    # Never overwrite it — only rewrite any local DB URLs it may contain.
    scripts_db_env = os.path.join(repo_path, 'scripts', 'db', '.env')
    if os.path.isfile(scripts_db_env):
        if rewrite_env_local(scripts_db_env, slot):
            print(f'    ✓ scripts/db/.env DB URLs rewritten', file=buf)

    rc = 0
    if db_create_hook:
        cmd = db_create_hook.replace('$SLOT', str(slot))
        cmd = cmd.replace('$WORKSPACE_PATH', ws_path)
        print(f'    → running db_create hook', file=buf)
        proc = subprocess.run(
            ['/bin/bash', '-lc', cmd], cwd=repo_path,
            capture_output=True, text=True,
        )
        buf.write(proc.stdout)
        buf.write(proc.stderr)
        rc = proc.returncode
        if rc != 0:
            print(f'    ✗ db_create hook failed (exit {rc})', file=buf)
    else:
        # Default strategy: clone the local source DB via CREATE DATABASE TEMPLATE.
        # Near-instant (file copy on the same Postgres server) and gives the new
        # isolated DB real data, not just an empty schema. For remote staging,
        # a separate on-demand skill handles the pull.
        #
        # Fallback: if the source DB doesn't exist locally (fresh checkout) we
        # fall back to Rails' empty-schema init so the workspace still boots.
        cloned = False
        urls = read_db_urls(env_local) or read_db_urls(env_main)
        # Only clone the primary URL — secondary (cache/queue/cable) DBs are
        # created on the fly by Rails when needed and are usually empty anyway.
        primary_url = urls.get('DATABASE_URL') or next(iter(urls.values()), None)
        if primary_url:
            ok, msg = clone_local_pg(primary_url, slot)
            if ok:
                print(f'    ✓ cloned via TEMPLATE: {msg}', file=buf)
                cloned = True
            else:
                print(f'    ↷ TEMPLATE clone skipped ({msg})', file=buf)

        if not cloned:
            if has_rails and os.path.isfile(os.path.join(repo_path, 'bin', 'rails')):
                print(f'    → fallback: bin/rails db:create db:schema:load', file=buf)
                proc = subprocess.run(
                    ['/bin/bash', '-lc', 'bin/rails db:create db:schema:load'],
                    cwd=repo_path, capture_output=True, text=True,
                )
                buf.write(proc.stdout)
                buf.write(proc.stderr)
                rc = proc.returncode
                if rc != 0:
                    print(f'    ✗ Rails db:create failed (exit {rc})', file=buf)
            else:
                print(f'    (no rails fallback — URLs updated, DB creation skipped)', file=buf)

    if rc == 0:
        print(f'    ✓ {repo_name} done', file=buf)
    return (repo_name, buf.getvalue(), rc, True)


# Fan-out across repos — each repo's db:create runs concurrently.
# Most time is waiting on a remote Postgres, so threads are fine.
results = []
with ThreadPoolExecutor(max_workers=max(1, len(repos))) as pool:
    futures = [pool.submit(process_repo, r) for r in repos]
    for f in as_completed(futures):
        results.append(f.result())

# Stream logs in a stable (config) order.
by_name = {name: (log, rc, did) for (name, log, rc, did) in results}
did_anything = False
exit_code = 0
for r in repos:
    name = r['name']
    log, rc, did = by_name.get(name, ('', 0, False))
    if log:
        sys.stdout.write(log)
    if did:
        did_anything = True
    if rc != 0:
        exit_code = rc

if not did_anything:
    print('  (no databases detected)')

sys.exit(exit_code)
PYEOF
