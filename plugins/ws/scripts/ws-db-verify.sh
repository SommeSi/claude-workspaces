#!/bin/bash
# ws-db-verify.sh — Audit a workspace's DB isolation and re-apply if drifted.
#
# Why this exists: the rewrites that ws-db-isolate.sh applies to
# config/database.yml and scripts/db/.env are NOT committed — they're local
# tweaks on tracked files. Any of these can silently revert them:
#   - git pull / merge / rebase  (most common — pulls in upstream changes
#     to database.yml and resets your suffixed names back to plain ones)
#   - git checkout -- config/database.yml
#   - git reset --hard
#   - bin/setup / db generators that regenerate the yml
#
# Symptom of drift: bin/jobs in worktree W picks up jobs enqueued from
# develop (or from another worktree). Because the queue/cable DB names lost
# their _w<slot> suffix and now collide on the shared dev DB.
#
# What this script does (idempotent, never touches data):
#   1. Auto-detect workspace slot from PWD via registry.json
#   2. For each repo in the workspace, audit:
#        - .env.local + .env  (DATABASE*_URL keys)
#        - config/database.yml  (hardcoded `database:` under development:)
#        - scripts/db/.env (if present)
#   3. Re-apply isolation on any line that lost its _w<slot> suffix
#   4. Print a clear summary (✓ verified or ✗→✓ re-fixed)
#
# Usage:
#   cd <any worktree path> && ws-db-verify.sh
#   # or:
#   ws-db-verify.sh <workspace_path> <slot>

set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

WS_PATH="${1:-}"
SLOT="${2:-}"

if [ -z "$WS_PATH" ] || [ -z "$SLOT" ]; then
  # Auto-detect from registry — same routine as ws-db-isolate.sh / pull-staging
  REG="$HOME/.claude-workspaces/registry.json"
  if [ ! -f "$REG" ]; then
    echo "❌ No registry at $REG" >&2
    exit 1
  fi
  eval "$(python3 -c "
import json, os
reg = json.load(open(os.path.expanduser('~/.claude-workspaces/registry.json')))
cwd = os.getcwd()
best_len, best, best_slot = 0, None, None
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
    echo "❌ Not inside a workspace (run from a workspace dir, or pass WS_PATH and SLOT)" >&2
    exit 1
  fi
fi

# Locate config
CONFIG=""
PROJECT_ROOT=""
for dir in "$WS_PATH" "$(git -C "$WS_PATH" rev-parse --show-toplevel 2>/dev/null || echo '')"; do
  [ -n "$dir" ] && [ -f "$dir/.claude-workspaces.json" ] && CONFIG="$dir/.claude-workspaces.json" && PROJECT_ROOT="$dir" && break
done
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
[ -z "$CONFIG" ] && { echo "❌ No .claude-workspaces.json found for $WS_PATH" >&2; exit 1; }

echo "→ Verifying DB isolation for w$SLOT ($(basename "$WS_PATH"))"

WS_PATH="$WS_PATH" SLOT="$SLOT" CONFIG="$CONFIG" python3 <<'PYEOF'
import json, os, re, sys
from urllib.parse import urlparse, urlunparse

ws_path = os.environ['WS_PATH']
slot = int(os.environ['SLOT'])
config = json.load(open(os.environ['CONFIG']))
repos = config.get('repos', [])
suffix = f'_w{slot}'

LOCAL_HOSTS = {'localhost', '127.0.0.1', '::1', 'host.docker.internal', ''}
_KEY_SHAPE = re.compile(r'^[A-Z][A-Z0-9_]*$')

def is_db_url_key(key):
    return bool(_KEY_SHAPE.match(key)) and 'DATABASE' in key and key.endswith('_URL')

def needs_suffix_url(url):
    """Return (current_db_name, expected_db_name) if URL points to a local
    DB whose name doesn't end with _w<slot>; else (None, None)."""
    try:
        p = urlparse(url)
    except Exception:
        return None, None
    if not p.scheme.startswith(('postgres', 'mysql', 'sqlite')):
        return None, None
    host = (p.hostname or '').lower()
    if host not in LOCAL_HOSTS:
        return None, None
    path = (p.path or '').lstrip('/')
    if not path or path.endswith(suffix):
        return None, None
    return path, path + suffix

def rewrite_url(url):
    p = urlparse(url)
    db = (p.path or '').lstrip('/')
    return urlunparse(p._replace(path='/' + db + suffix))

def audit_env_file(path):
    """Returns (drifted_keys: list[(key, oldname, newname)], total_db_keys: int).
    Rewrites in place if drift found."""
    drifted = []
    total = 0
    if not os.path.isfile(path):
        return drifted, total
    with open(path) as f:
        lines = f.read().split('\n')
    out = []
    for line in lines:
        m = re.match(r'^([A-Z_][A-Z0-9_]*)=(.*)$', line)
        if m and is_db_url_key(m.group(1)):
            total += 1
            key, val = m.group(1), m.group(2)
            stripped = val.strip()
            q = ''
            if stripped.startswith(('"', "'")) and stripped.endswith(stripped[0]) and len(stripped) >= 2:
                q = stripped[0]
                stripped = stripped[1:-1]
            old, new = needs_suffix_url(stripped)
            if old:
                fixed = rewrite_url(stripped)
                drifted.append((key, old, old + suffix))
                out.append(f'{key}={q}{fixed}{q}')
                continue
        out.append(line)
    if drifted:
        with open(path, 'w') as f:
            f.write('\n'.join(out))
    return drifted, total

def audit_database_yml(path):
    """Same idea for config/database.yml under development:."""
    drifted = []
    total = 0
    if not os.path.isfile(path):
        return drifted, total
    with open(path) as f:
        lines = f.read().split('\n')
    in_dev = False
    out = []
    for line in lines:
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
                if '<%' not in name:
                    total += 1
                    if not name.endswith(suffix):
                        drifted.append(('database.yml', name, name + suffix))
                        out.append(f'{prefix}{name}{suffix}{rest}')
                        continue
        out.append(line)
    if drifted:
        with open(path, 'w') as f:
            f.write('\n'.join(out))
    return drifted, total


def audit_db_name_envs(path):
    """Ensure each local *_URL has a matching *_NAME var equal to that URL's
    (suffixed) DB name — what an env-driven config/database.yml reads for its
    secondary dev DBs. Adds/fixes missing or stale *_NAME lines in place."""
    drifted = []
    if not os.path.isfile(path):
        return drifted, 0
    with open(path) as f:
        lines = f.read().split('\n')
    cur = {}
    for line in lines:
        m = re.match(r'^([A-Z_][A-Z0-9_]*)=(.*)$', line)
        if m:
            cur[m.group(1)] = m.group(2).strip().strip('"\'')
    want = {}
    for key, val in cur.items():
        if not is_db_url_key(key) or not val:
            continue
        db = (urlparse(val).path or '').lstrip('/')
        if db.endswith(suffix):
            want[key[: -len('_URL')] + '_NAME'] = db
    if not want:
        return drifted, 0
    fixes = {k: v for k, v in want.items() if cur.get(k) != v}
    if not fixes:
        return drifted, len(want)
    seen = set()
    out = []
    for line in lines:
        m = re.match(r'^([A-Z_][A-Z0-9_]*)=', line)
        if m and m.group(1) in fixes:
            k = m.group(1)
            out.append(f'{k}={fixes[k]}')
            seen.add(k)
        else:
            out.append(line)
    while out and out[-1] == '':
        out.pop()
    for k, v in fixes.items():
        if k not in seen:
            out.append(f'{k}={v}')
    with open(path, 'w') as f:
        f.write('\n'.join(out) + '\n')
    for k, v in fixes.items():
        drifted.append((k, cur.get(k, '(missing)'), v))
    return drifted, len(want)


exit_code = 0
total_repos = 0
total_drifts = 0

for r in repos:
    name = r['name']
    repo_path = os.path.join(ws_path, name)
    if not os.path.isdir(repo_path):
        continue
    total_repos += 1

    env_local = os.path.join(repo_path, '.env.local')
    env_main = os.path.join(repo_path, '.env')
    scripts_db_env = os.path.join(repo_path, 'scripts', 'db', '.env')
    db_yml = os.path.join(repo_path, 'config', 'database.yml')

    repo_drift = []
    repo_total = 0

    for ef in (env_local, env_main, scripts_db_env):
        d, t = audit_env_file(ef)
        repo_total += t
        for key, old, new in d:
            repo_drift.append((os.path.basename(ef), key, old, new))

    for ef in (env_local, env_main):
        d, t = audit_db_name_envs(ef)
        repo_total += t
        for key, old, new in d:
            repo_drift.append((os.path.basename(ef), key, old, new))

    d, t = audit_database_yml(db_yml)
    repo_total += t
    for f, old, new in d:
        repo_drift.append(('config/database.yml', '', old, new))

    if repo_total == 0:
        print(f'  ↷ {name}: no DB refs detected')
        continue

    if repo_drift:
        total_drifts += len(repo_drift)
        print(f'  ✗→✓ {name}: re-isolated {len(repo_drift)} drifted ref(s)')
        for source, key, old, new in repo_drift:
            label = f'{source}[{key}]' if key else source
            print(f'      {label}: {old} → {new}')
    else:
        print(f'  ✓ {name}: {repo_total} DB ref(s) all correctly suffixed with {suffix}')

if total_drifts > 0:
    print(f'\n  ⚠️  Drift detected and fixed. Restart bin/jobs / bin/dev to pick up the corrected config.')
    exit_code = 0  # non-fatal — we fixed it
else:
    print(f'\n  ✓ All {total_repos} repo(s) properly isolated for w{slot}')

sys.exit(exit_code)
PYEOF
