#!/bin/bash
# ws-create.sh — Orchestrate the full worktree creation in ONE bash call.
#
# Replaces the previous SKILL Steps 6a + 6b + 6c + 6d (4 separate Bash tool
# calls) to eliminate LLM ping-pong overhead between sub-steps. Each sub-step
# can take 30s+ of LLM latency in the old flow; collapsing them shaves minutes.
#
# Steps performed (in order, with fail-fast + cleanup):
#   6a — ws-worktree-create.sh   (worktrees for every repo, parallel)
#   6b — ws-generate-files.sh    (CLAUDE.local.md, .env.local, .vscode, ...)
#   6c — ws-db-isolate.sh        (rewrite DB URLs, CREATE DATABASE TEMPLATE)
#   6d — post_create hook        (bundle install / bun install / etc.)
#
# Registry update (6e) and terminal color (6f) remain in the SKILL — they
# need data the orchestrator doesn't (color/emoji computed from slot, port
# breakdown for the recap) and are too cheap to bother chaining.
#
# Usage:
#   ws-create.sh <workspace_path> <slot> <branch> <color> <emoji> <project_root> [spec] [goal]

set -euo pipefail
export PATH="$HOME/.bun/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

usage() {
  cat >&2 <<EOF
Usage: ws-create.sh <workspace_path> <slot> <branch> <color> <emoji> <project_root> [spec] [goal]

  workspace_path  /Users/.../worktrees/feat-xxx
  slot            1, 2, 3, ...
  branch          feat/my-feature
  color           #1a3a2a
  emoji           🟢
  project_root    /Users/.../backend-something  (must contain .claude-workspaces.json)
  spec            ticket URL or "none" (optional)
  goal            free-form description (optional)
EOF
  exit 1
}

WS_PATH="${1:-}"
SLOT="${2:-}"
BRANCH="${3:-}"
COLOR="${4:-}"
EMOJI="${5:-}"
PROJECT_ROOT="${6:-}"
SPEC="${7:-none}"
GOAL="${8:-}"

[ -z "$WS_PATH" ] && usage
[ -z "$SLOT" ] && usage
[ -z "$BRANCH" ] && usage
[ -z "$COLOR" ] && usage
[ -z "$EMOJI" ] && usage
[ -z "$PROJECT_ROOT" ] && usage

CONFIG="$PROJECT_ROOT/.claude-workspaces.json"
[ -f "$CONFIG" ] || { echo "❌ No .claude-workspaces.json at $PROJECT_ROOT" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Timing helper ---
WS_T0=$(python3 -c 'import time; print(int(time.time()*1000))')
WS_TLAST=$WS_T0
t() {
  local now
  now=$(python3 -c 'import time; print(int(time.time()*1000))')
  printf '[Δ %5dms │ Σ %6dms] ws-create: %s\n' "$((now - WS_TLAST))" "$((now - WS_T0))" "$*" >&2
  WS_TLAST=$now
}
export WS_T0

# --- Cleanup on failure ---
# Removes any worktrees + branches that may have been created (one repo can
# succeed before another fails — that succeeded repo would otherwise leak a
# branch in the origin). Best-effort: every step is wrapped to never fail
# the cleanup itself.
cleanup_on_failure() {
  local rc=$?
  echo "" >&2
  echo "❌ ws-create: failure detected (exit $rc) — cleaning up partial state" >&2

  PROJECT_ROOT="$PROJECT_ROOT" WS_PATH="$WS_PATH" CONFIG="$CONFIG" BRANCH="$BRANCH" python3 - <<'PYEOF' || true
import json, os, subprocess
config = json.load(open(os.environ['CONFIG']))
project_root = os.environ['PROJECT_ROOT']
ws_path = os.environ['WS_PATH']
branch = os.environ['BRANCH']
repos = {r['name']: dict(r) for r in config.get('repos', [])}
local_cfg = os.path.join(project_root, '.claude-workspaces.local.json')
if os.path.isfile(local_cfg):
    try:
        local = json.load(open(local_cfg))
        for name, ov in (local.get('repos') or {}).items():
            if name in repos:
                repos[name].update(ov)
    except Exception:
        pass
for name, r in repos.items():
    origin = r.get('origin', '.')
    if origin == '.':
        origin_abs = project_root
    else:
        origin_abs = os.path.normpath(os.path.join(project_root, origin))
    wt = os.path.join(ws_path, name)
    # 1) Remove the worktree (if present) — frees the branch from being
    #    checked out so `git branch -D` works.
    if os.path.isdir(wt) or os.path.islink(wt):
        subprocess.run(
            ['git', '-C', origin_abs, 'worktree', 'remove', '--force', wt],
            capture_output=True,
        )
    # 2) Delete the branch we may have created (best-effort — silently OK
    #    if the branch never got created or wasn't created by us).
    subprocess.run(
        ['git', '-C', origin_abs, 'branch', '-D', branch],
        capture_output=True,
    )
PYEOF
  rm -rf "$WS_PATH" 2>/dev/null || true
  echo "  ✓ cleanup done" >&2
  exit "$rc"
}
trap cleanup_on_failure ERR

t "start (ws=$WS_PATH slot=$SLOT branch=$BRANCH)"

# ---------------------------------------------------------------------------
# Step 6a — create worktrees
# ---------------------------------------------------------------------------
t "── 6a: worktree-create ──"
/bin/bash "$SCRIPT_DIR/ws-worktree-create.sh" "$WS_PATH" "$BRANCH" "$PROJECT_ROOT"

# ---------------------------------------------------------------------------
# Step 6b — generate workspace files
# ---------------------------------------------------------------------------
t "── 6b: generate-files ──"
CONFIG="$CONFIG" PROJECT_ROOT="$PROJECT_ROOT" \
  /bin/bash "$SCRIPT_DIR/ws-generate-files.sh" \
    "$WS_PATH" "$SLOT" "$BRANCH" "$COLOR" "$EMOJI" "worktree" "$SPEC" "$GOAL"

# ---------------------------------------------------------------------------
# Step 6c — database isolation
# ---------------------------------------------------------------------------
t "── 6c: db-isolate ──"
CONFIG="$CONFIG" /bin/bash "$SCRIPT_DIR/ws-db-isolate.sh" "$WS_PATH" "$SLOT"

# ---------------------------------------------------------------------------
# Step 6d — post_create hook
# ---------------------------------------------------------------------------
t "── 6d: post_create hook ──"
HOOK_CMD=$(CONFIG="$CONFIG" SLOT="$SLOT" python3 - <<'PYEOF'
import json, os
cfg = json.load(open(os.environ['CONFIG']))
print((cfg.get('hooks') or {}).get('post_create') or '')
PYEOF
)

if [ -n "$HOOK_CMD" ]; then
  SLUG=$(echo "$BRANCH" | tr '/' '-')
  PORT=$(CONFIG="$CONFIG" SLOT="$SLOT" python3 - <<'PYEOF'
import json, os
cfg = json.load(open(os.environ['CONFIG']))
repos = cfg.get('repos', [])
if repos:
    step = cfg.get('port_step', 10)
    print(repos[0].get('port_base', 3000) + int(os.environ['SLOT']) * step)
else:
    print(0)
PYEOF
  )

  # Variable substitution (mirrors what eval would do)
  CMD="$HOOK_CMD"
  CMD="${CMD//\$SLOT/$SLOT}"
  CMD="${CMD//\$BRANCH/$BRANCH}"
  CMD="${CMD//\$SLUG/$SLUG}"
  CMD="${CMD//\$PORT/$PORT}"
  CMD="${CMD//\$WORKSPACE_PATH/$WS_PATH}"

  echo "  → post_create: $CMD" >&2

  # Add common tool shims to PATH instead of sourcing ~/.zshrc (which can
  # exec zsh or set traps that crash bash).
  for p in "$HOME/.rbenv/shims" "$HOME/.rbenv/bin" "$HOME/.bun/bin" \
           "$HOME/.cargo/bin" "$HOME/.yarn/bin"; do
    [ -d "$p" ] && export PATH="$p:$PATH"
  done
  # nvm: find the latest installed node version
  if [ -d "$HOME/.nvm/versions/node" ]; then
    _nvm_node=$(ls "$HOME/.nvm/versions/node/" 2>/dev/null | sort -V | tail -1)
    [ -n "$_nvm_node" ] && export PATH="$HOME/.nvm/versions/node/$_nvm_node/bin:$PATH"
  fi
  t "PATH shimmed (no zshrc source)"

  eval "$CMD"
  t "post_create done"
else
  t "no post_create hook (skipping)"
fi

# Steps 6e/6f are post-success — don't let a registry/color failure nuke
# the fully-created workspace.
trap - ERR

t "── 6e: registry update ──"
REPOS_JSON="${REPOS_JSON:-}"
SLUG=$(echo "$BRANCH" | tr '/' '-')
CONFIG="$CONFIG" SLOT="$SLOT" WS_PATH="$WS_PATH" SLUG="$SLUG" BRANCH="$BRANCH" \
  COLOR="$COLOR" EMOJI="$EMOJI" PROJECT_ROOT="$PROJECT_ROOT" \
  REPOS_JSON="$REPOS_JSON" python3 - <<'PYEOF' || echo "⚠️  registry update failed (workspace still usable)" >&2
import json, os, tempfile, shutil
from datetime import datetime, timezone

reg_path = os.path.expanduser('~/.claude-workspaces/registry.json')
os.makedirs(os.path.dirname(reg_path), exist_ok=True)

if os.path.isfile(reg_path):
    with open(reg_path) as f:
        registry = json.load(f)
else:
    registry = {"workspaces": {}, "next_slot": 1}

slot = os.environ['SLOT']
cfg = json.load(open(os.environ['CONFIG']))
port_step = cfg.get('port_step', 10)

repos_json = os.environ.get('REPOS_JSON', '')
if repos_json:
    repos = json.loads(repos_json)
else:
    repos = []
    for r in cfg.get('repos', []):
        port = r.get('port_base', 3000) + int(slot) * port_step
        repos.append({
            "name": r['name'],
            "path": os.path.join(os.environ['WS_PATH'], r['name']),
            "port": port,
        })

registry['workspaces'][slot] = {
    "slug": os.environ['SLUG'],
    "mode": "worktree",
    "branch": os.environ['BRANCH'],
    "color": os.environ['COLOR'],
    "emoji": os.environ['EMOJI'],
    "created_at": datetime.now(timezone.utc).isoformat(),
    "project_root": os.environ['PROJECT_ROOT'],
    "workspace_path": os.environ['WS_PATH'],
    "repos": repos,
}

next_slot = max(int(k) for k in registry['workspaces']) + 1
registry['next_slot'] = next_slot

# Atomic write
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(reg_path), suffix='.tmp')
with os.fdopen(fd, 'w') as f:
    json.dump(registry, f, indent=2, ensure_ascii=False)
    f.write('\n')
shutil.move(tmp, reg_path)
PYEOF
t "registry updated"

# ---------------------------------------------------------------------------
# Step 6f — terminal color
# ---------------------------------------------------------------------------
t "── 6f: terminal color ──"
/bin/bash "$SCRIPT_DIR/ws-color.sh" "$WS_PATH" 2>/dev/null || true
t "color applied"

t "DONE — workspace ready at $WS_PATH"
echo "" >&2
echo "✓ ws-create finished (registry updated, terminal colored)." >&2
