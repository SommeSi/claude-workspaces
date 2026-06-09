#!/bin/bash
# ws-destroy.sh — Tear down a workspace: drop isolated DBs, remove worktrees,
#                 delete the workspace directory, update registry.
# Usage: ws-destroy.sh <workspace_path> <slot>
#
# Repos are processed in PARALLEL (DB drop + worktree remove fan out).
# Uses `dropdb` directly — no `bin/rails db:drop`, no bundler, no gemfile mess.
# Idempotent: missing DBs/worktrees are skipped with a notice.

set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

WS_PATH="$1"
SLOT="$2"

REG="$HOME/.claude-workspaces/registry.json"

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

# Fallback: derive project root from registry
if [ -z "$CONFIG" ] && [ -f "$REG" ]; then
  eval "$(WS_PATH="$WS_PATH" REG="$REG" python3 <<'PYEOF'
import json, os
reg = json.load(open(os.environ['REG']))
ws = os.environ['WS_PATH']
for s, w in reg.get('workspaces', {}).items():
    if w.get('workspace_path') == ws:
        pr = w.get('project_root', '')
        if pr and os.path.isfile(os.path.join(pr, '.claude-workspaces.json')):
            print(f'CONFIG={json.dumps(os.path.join(pr, ".claude-workspaces.json"))}')
            print(f'PROJECT_ROOT={json.dumps(pr)}')
        break
PYEOF
)"
fi

# Collect workspace repos + origins from config (merge local overrides)
if [ -n "$CONFIG" ]; then
  REPOS_JSON=$(CONFIG="$CONFIG" PROJECT_ROOT="$PROJECT_ROOT" python3 <<'PYEOF'
import json, os
cfg = json.load(open(os.environ['CONFIG']))
repos = {r['name']: dict(r) for r in cfg.get('repos', [])}
pr = os.environ.get('PROJECT_ROOT', '')
lf = os.path.join(pr, '.claude-workspaces.local.json') if pr else ''
if lf and os.path.isfile(lf):
    try:
        local = json.load(open(lf))
        for name, overrides in (local.get('repos') or {}).items():
            if name in repos:
                repos[name].update(overrides)
    except Exception:
        pass
print(json.dumps(list(repos.values())))
PYEOF
)
else
  REPOS_JSON='[]'
fi

# ----------- READ workspace meta from registry (ports, branch, slug) -----------
WS_META=$(SLOT="$SLOT" REG="$REG" python3 <<'PYEOF'
import json, os
try:
    reg = json.load(open(os.environ['REG']))
except Exception:
    reg = {}
w = reg.get('workspaces', {}).get(os.environ['SLOT'], {})
print('PORTS=' + ','.join(str(r.get('port')) for r in w.get('repos', []) if r.get('port')))
print('BRANCH=' + (w.get('branch') or ''))
print('SLUG=' + (w.get('slug') or ''))
PYEOF
)
WS_PORTS=$(echo "$WS_META" | sed -n 's/^PORTS=//p')
WS_BRANCH=$(echo "$WS_META" | sed -n 's/^BRANCH=//p')
WS_SLUG=$(echo "$WS_META" | sed -n 's/^SLUG=//p')

# ----------- KILL processes on workspace ports -----------
if [ -n "$WS_PORTS" ]; then
  echo "→ Killing processes on ports: $WS_PORTS"
  IFS=',' read -ra _PORTS <<< "$WS_PORTS" || true
  for PORT in "${_PORTS[@]}"; do
    [ -z "$PORT" ] && continue
    PIDS=$(lsof -ti ":$PORT" 2>/dev/null || true)
    if [ -n "$PIDS" ]; then
      echo "$PIDS" | xargs kill -TERM 2>/dev/null || true
      sleep 1
      PIDS=$(lsof -ti ":$PORT" 2>/dev/null || true)
      [ -n "$PIDS" ] && echo "$PIDS" | xargs kill -KILL 2>/dev/null || true
      echo "  ✓ port $PORT cleared"
    else
      echo "  ↷ port $PORT: nothing running"
    fi
  done
fi

# ----------- pre_destroy hook (best-effort, never aborts) -----------
if [ -n "$CONFIG" ]; then
  PRE_DESTROY=$(CONFIG="$CONFIG" python3 -c "import json,os;print((json.load(open(os.environ['CONFIG'])).get('hooks',{}) or {}).get('pre_destroy','') or '')" 2>/dev/null || true)
  if [ -n "$PRE_DESTROY" ]; then
    echo "→ Running pre_destroy hook"
    CMD=${PRE_DESTROY//\$SLOT/$SLOT}
    CMD=${CMD//\$BRANCH/$WS_BRANCH}
    CMD=${CMD//\$SLUG/$WS_SLUG}
    CMD=${CMD//\$WORKSPACE_PATH/$WS_PATH}
    CMD=${CMD//\~/$HOME}
    ( eval "$CMD" ) || echo "  ⚠ pre_destroy hook failed (continuing)"
  fi
fi

# ----------- DB DROP (parallel across repos) -----------
echo "→ Dropping isolated DBs (_w$SLOT)"

set +ue
source "$HOME/.zshrc" 2>/dev/null || source "$HOME/.bashrc" 2>/dev/null || true
set -ue

drop_repo_dbs() {
  local NAME="$1"
  local REPO_DIR="$WS_PATH/$NAME"
  local LOG="$2"
  {
    if [ ! -d "$REPO_DIR" ]; then
      echo "  ↷ $NAME: no dir, skipped"
      exit 0
    fi
    # Extract _w<slot> DB names from all DB URL keys in .env.local / .env
    local URLS
    URLS=$(REPO_DIR="$REPO_DIR" SLOT="$SLOT" python3 <<'PYEOF'
import os, re
from urllib.parse import urlparse

repo_dir = os.environ['REPO_DIR']
slot = os.environ['SLOT']
_KEY = re.compile(r'^[A-Z][A-Z0-9_]*$')

def is_db_url_key(k):
    return bool(_KEY.match(k)) and 'DATABASE' in k and k.endswith('_URL')

seen = set()
for fname in ('.env.local', '.env'):
    fp = os.path.join(repo_dir, fname)
    if not os.path.isfile(fp):
        continue
    with open(fp) as f:
        for line in f.read().split('\n'):
            m = re.match(r'^([A-Z_][A-Z0-9_]*)=(.*)$', line)
            if not m or not is_db_url_key(m.group(1)):
                continue
            v = m.group(2).strip()
            if v.startswith(('"', "'")) and v.endswith(v[0]) and len(v) >= 2:
                v = v[1:-1]
            try:
                p = urlparse(v)
            except Exception:
                continue
            if not p.scheme.startswith('postgres'):
                continue
            db = (p.path or '').lstrip('/')
            # Safety: only drop DBs with our isolation suffix
            if not db or not db.endswith(f'_w{slot}'):
                continue
            key = (p.hostname or 'localhost', p.port or 5432, db,
                   p.username or '', p.password or '')
            if key in seen:
                continue
            seen.add(key)
            print('\t'.join([
                p.hostname or 'localhost',
                str(p.port or 5432),
                db,
                p.username or '',
                p.password or '',
            ]))
PYEOF
)
    if [ -z "$URLS" ]; then
      echo "  ↷ $NAME: no _w$SLOT DBs found"
      exit 0
    fi
    echo "$URLS" | while IFS=$'\t' read -r HOST PORT DB USER PASS; do
      [ -z "$DB" ] && continue
      # Build connection args. Use PGPASSWORD for auth (passed via env below).
      local ARGS=(-h "$HOST" -p "$PORT")
      [ -n "$USER" ] && ARGS+=(-U "$USER")
      if PGPASSWORD="$PASS" dropdb --if-exists "${ARGS[@]}" "$DB" 2>&1; then
        echo "  ✓ $NAME: dropped $DB"
      else
        echo "  ⚠ $NAME: failed to drop $DB (continuing)"
      fi
    done
  } >"$LOG" 2>&1
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PIDS=()
LOGS=()
while IFS=$'\t' read -r NAME; do
  [ -z "$NAME" ] && continue
  LOG="$TMP/db-$NAME.log"
  LOGS+=("$LOG")
  drop_repo_dbs "$NAME" "$LOG" &
  PIDS+=($!)
done < <(echo "$REPOS_JSON" | python3 -c "
import json, sys
for r in json.load(sys.stdin):
    print(r['name'])
")

for pid in "${PIDS[@]}"; do wait "$pid" || true; done
for log in "${LOGS[@]}"; do [ -f "$log" ] && cat "$log"; done

# ----------- WORKTREE REMOVE (parallel across repos) -----------
echo "→ Removing git worktrees"

remove_worktree() {
  local NAME="$1"
  local ORIGIN="$2"
  local WT_PATH="$WS_PATH/$NAME"
  local LOG="$3"
  {
    if [ ! -d "$WT_PATH" ]; then
      echo "  ↷ $NAME: no worktree dir"
      exit 0
    fi
    # Safety: never touch a repo that IS the main checkout (attached mode).
    if [ -n "$PROJECT_ROOT" ] && { [ "$WT_PATH" = "$PROJECT_ROOT" ] || [ "$WT_PATH" = "$WS_PATH" -a "$WS_PATH" = "$PROJECT_ROOT" ]; }; then
      echo "  ↷ $NAME: attached main checkout — preserved"
      exit 0
    fi
    # Resolve origin repo (where the worktree was created FROM)
    local ORIGIN_ABS=""
    if [ -n "$PROJECT_ROOT" ]; then
      if [ "$ORIGIN" = "." ]; then
        ORIGIN_ABS="$PROJECT_ROOT"
      else
        ORIGIN_ABS="$(cd "$PROJECT_ROOT" && cd "$ORIGIN" 2>/dev/null && pwd)" || ORIGIN_ABS=""
      fi
    fi
    # Fallback: ask the worktree itself
    if [ -z "$ORIGIN_ABS" ] && [ -d "$WT_PATH/.git" ] || [ -f "$WT_PATH/.git" ]; then
      ORIGIN_ABS="$(git -C "$WT_PATH" rev-parse --git-common-dir 2>/dev/null | sed 's|/.git$||' | sed 's|/\.git/worktrees/.*||')" || ORIGIN_ABS=""
    fi
    if [ -n "$ORIGIN_ABS" ]; then
      if git -C "$ORIGIN_ABS" worktree remove --force "$WT_PATH" 2>&1; then
        echo "  ✓ $NAME: worktree removed"
      else
        echo "  ⚠ $NAME: git worktree remove failed — forcing rm"
        rm -rf "$WT_PATH"
        git -C "$ORIGIN_ABS" worktree prune 2>/dev/null || true
      fi
    else
      echo "  ⚠ $NAME: origin unknown — forcing rm"
      rm -rf "$WT_PATH"
    fi
  } >"$LOG" 2>&1
}

PIDS=()
LOGS=()
while IFS=$'\t' read -r NAME ORIGIN; do
  [ -z "$NAME" ] && continue
  LOG="$TMP/wt-$NAME.log"
  LOGS+=("$LOG")
  remove_worktree "$NAME" "$ORIGIN" "$LOG" &
  PIDS+=($!)
done < <(echo "$REPOS_JSON" | python3 -c "
import json, sys
for r in json.load(sys.stdin):
    print(f\"{r['name']}\t{r.get('origin', '.')}\")")

for pid in "${PIDS[@]}"; do wait "$pid" || true; done
for log in "${LOGS[@]}"; do [ -f "$log" ] && cat "$log"; done

# ----------- REMOVE WORKSPACE DIR -----------
if [ -n "$PROJECT_ROOT" ] && [ "$WS_PATH" = "$PROJECT_ROOT" ]; then
  echo "  ↷ attached workspace — directory preserved ($WS_PATH)"
elif [ -d "$WS_PATH" ]; then
  rm -rf "$WS_PATH"
  echo "  ✓ removed $WS_PATH"
fi

# ----------- UPDATE REGISTRY (atomic) -----------
if [ -f "$REG" ]; then
  SLOT="$SLOT" REG="$REG" python3 <<'PYEOF'
import json, os, tempfile
reg_path = os.environ['REG']
slot = os.environ['SLOT']
reg = json.load(open(reg_path))
ws = reg.get('workspaces', {})
if slot in ws:
    del ws[slot]
    # next_slot = lowest free starting at 1 (start-worktree scans anyway, so
    # just keep next_slot monotonic-ish: max existing + 1, or 1).
    remaining = sorted(int(s) for s in ws.keys() if s.isdigit())
    reg['next_slot'] = (remaining[-1] + 1) if remaining else 1
    reg['workspaces'] = ws
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(reg_path), prefix='.registry.')
    try:
        with os.fdopen(fd, 'w') as f:
            json.dump(reg, f, indent=2)
            f.write('\n')
        os.rename(tmp, reg_path)
        print(f'  ✓ registry: slot {slot} freed')
    except Exception:
        try:
            os.unlink(tmp)
        except Exception:
            pass
        raise
else:
    print(f'  ↷ registry: slot {slot} already absent')
PYEOF
fi

# ----------- RESET terminal title + background -----------
TTY_DEV="/dev/$(ps -o tty= -p "$PPID" 2>/dev/null | tr -d ' ')"
if [ -e "$TTY_DEV" ]; then
  printf '\033]11;\007' > "$TTY_DEV" 2>/dev/null || true
  printf '\033]1;\007'  > "$TTY_DEV" 2>/dev/null || true
  printf '\033]0;\007'  > "$TTY_DEV" 2>/dev/null || true
fi

echo "✓ Workspace w$SLOT destroyed"

# ----------- CLOSE the WezTerm window for this workspace (last; skip attached) -----------
if ! { [ -n "$PROJECT_ROOT" ] && [ "$WS_PATH" = "$PROJECT_ROOT" ]; }; then
  WEZTERM_CLI="/Applications/WezTerm.app/Contents/MacOS/wezterm"
  if [ -x "$WEZTERM_CLI" ]; then
    "$WEZTERM_CLI" cli list --format json 2>/dev/null | WS_PATH="$WS_PATH" python3 -c '
import json, os, sys
ws = os.environ["WS_PATH"]
def cpath(c):
    c = c or ""
    if "://" in c:
        c = c.split("://", 1)[1]
        c = c[c.find("/"):] if "/" in c else c
    return c
try:
    panes = json.load(sys.stdin)
except Exception:
    sys.exit(0)
wins = {p["window_id"] for p in panes if cpath(p.get("cwd","")).startswith(ws)}
for p in panes:
    if p.get("window_id") in wins:
        print(p["pane_id"])
' 2>/dev/null | while read -r pid; do
      [ -n "$pid" ] && "$WEZTERM_CLI" cli kill-pane --pane-id "$pid" 2>/dev/null || true
    done || true
  fi
fi
