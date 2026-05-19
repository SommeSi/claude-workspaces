#!/bin/bash
# ws-generate-files.sh — Generate all workspace files in one shot
# Usage: ws-generate-files.sh <workspace_path> <slot> <branch> <color> <emoji> <mode> [spec]
#
# Generates: CLAUDE.local.md, .worktree-env.sh, .vscode/settings.json (per repo),
#             .code-workspace (multi-repo), .env.local (per repo with port substitution)

set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# --- Timing helper (debug) ---
WS_T0=$(python3 -c 'import time; print(int(time.time()*1000))')
WS_TLAST=$WS_T0
t() {
  local now
  now=$(python3 -c 'import time; print(int(time.time()*1000))')
  printf '[Δ %5dms │ Σ %6dms] ws-generate-files: %s\n' "$((now - WS_TLAST))" "$((now - WS_T0))" "$*" >&2
  WS_TLAST=$now
}
t "start"

WS_PATH="$1"
SLOT="$2"
BRANCH="$3"
COLOR="$4"
EMOJI="$5"
MODE="${6:-worktree}"
SPEC="${7:-none}"
GOAL="${8:-}"
DATE=$(date '+%Y-%m-%d')
SLUG=$(echo "$BRANCH" | tr '/' '-')

# --- Find config (honor CONFIG/PROJECT_ROOT passed via env first) ---
CONFIG="${CONFIG:-}"
PROJECT_ROOT="${PROJECT_ROOT:-}"
if [ -z "$CONFIG" ] || [ ! -f "$CONFIG" ]; then
  CONFIG=""
  PROJECT_ROOT=""
  for dir in "$WS_PATH" "$(git -C "$WS_PATH" rev-parse --show-toplevel 2>/dev/null || echo '')"; do
    [ -n "$dir" ] && [ -f "$dir/.claude-workspaces.json" ] && CONFIG="$dir/.claude-workspaces.json" && PROJECT_ROOT="$dir" && break
  done
fi

# Also check parent project roots from registry
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

# --- Fail loud if config expected but missing ---
# For worktree mode with a real WS_PATH, a missing config means downstream
# steps (env substitution, DB isolation, repo list in CLAUDE.local.md) will
# silently no-op and produce a broken workspace. Better to crash early.
if [ -z "$CONFIG" ] && [ "$MODE" = "worktree" ]; then
  echo "❌ ws-generate-files: no .claude-workspaces.json found for $WS_PATH" >&2
  echo "   Pass CONFIG=<path> PROJECT_ROOT=<path> via env, or ensure the config" >&2
  echo "   exists at WS_PATH or at the parent git root. Refusing to generate a" >&2
  echo "   half-configured workspace." >&2
  exit 1
fi

# --- Parse config ---
# NOTE: use a quoted heredoc + os.environ to avoid bash mangling '{' and '}'
# inside "$(python3 -c "...{...}...")". That subtle bug made REPO_COUNT stay
# unset, causing the per-repo loops below to silently skip.
if [ -n "$CONFIG" ]; then
  eval "$(CONFIG="$CONFIG" SLOT="$SLOT" PORT_STEP_HINT="10" python3 <<'PYEOF'
import json, os

config = json.load(open(os.environ['CONFIG']))
repos = config.get('repos', [])
port_step = config.get('port_step', int(os.environ.get('PORT_STEP_HINT', '10')))
slot = int(os.environ['SLOT'])

repo_info = []
for r in repos:
    port = r.get('port_base', 3000) + slot * port_step
    repo_info.append({
        'name': r['name'],
        'port': port,
        'origin': r.get('origin', '.'),
    })

names = ' '.join(r['name'] for r in repo_info)
ports = ' '.join(str(r['port']) for r in repo_info)
origins = '|'.join(r['origin'] for r in repo_info)
print(f'REPO_NAMES=({names})')
print(f'REPO_PORTS=({ports})')
print(f'REPO_ORIGINS="{origins}"')
print(f'REPO_COUNT={len(repo_info)}')
print(f'PORT_STEP={port_step}')
PYEOF
)"
fi

# Defaults if no config
REPO_COUNT=${REPO_COUNT:-0}
t "config parsed (REPO_COUNT=$REPO_COUNT)"

# --- 1. CLAUDE.local.md ---
REPOS_LIST=""
if [ "$REPO_COUNT" -gt 0 ]; then
  IFS='|' read -ra ORIGINS <<< "$REPO_ORIGINS"
  for i in $(seq 0 $((REPO_COUNT - 1))); do
    REPOS_LIST="$REPOS_LIST  - ${REPO_NAMES[$i]} -> $WS_PATH/${REPO_NAMES[$i]} (port ${REPO_PORTS[$i]})\n"
  done
fi

cat > "$WS_PATH/CLAUDE.local.md" << CLAUDEEOF
# Workspace — $BRANCH

## Workspace identity
Always prefix your first response in a conversation with the workspace badge:
$EMOJI **[w$SLOT] $BRANCH**

This helps the user know which workspace this Claude session is attached to.

## Workspace info
- **Slot**: $SLOT
- **Mode**: $MODE
- **Branch**: \`$BRANCH\`
- **Created**: $DATE
- **Repos**:
$(echo -e "$REPOS_LIST")
## Goal of this workspace
$GOAL

## Spec
$SPEC

## Progress log

<!--
IMPORTANT — Progress recording protocol (read this at session start):

You MUST record a checkpoint at natural milestones so that work survives
reboots, compactions, and multi-day sessions. Use your judgment — don't
log every bash call, but DO log:

  • after completing a substantive task (feature, fix, refactor step done)
  • after making a non-obvious decision (architectural choice, tradeoff)
  • after discovering a blocker or root cause (bug, config issue, DB mismatch)
  • before a long-running operation that might be interrupted
  • before context gets heavy (anticipate compaction)

How to record (one bash call, no tool approval needed, ~100ms):

  /bin/bash "\${CLAUDE_PLUGIN_ROOT}/scripts/ws-checkpoint.sh" "1–3 concise sentences: what was done / decided / found"

Or from anywhere:
  /bin/bash ~/projects/ws/plugins/ws/scripts/ws-checkpoint.sh "..."

Newest checkpoints appear at the TOP of this section. Git state is captured
automatically per repo. If the last checkpoint is < 5 min old and covers the
same topic, write a follow-up rather than duplicating.
-->

## Notes / decisions / TODOs

CLAUDEEOF
echo "  ✓ CLAUDE.local.md"
t "CLAUDE.local.md written"

# --- 2. .worktree-env.sh ---
cat > "$WS_PATH/.worktree-env.sh" << 'ENVEOF'
#!/bin/bash
# Auto-generated by workspace plugin — do not edit (gitignored)
ENVEOF
cat >> "$WS_PATH/.worktree-env.sh" << ENVEOF2
export WS_SLOT=$SLOT
export WS_BRANCH="$BRANCH"
export WS_COLOR="$COLOR"
export WS_EMOJI="$EMOJI"

# OSC 11: set terminal background color (WezTerm, iTerm2, Kitty)
printf '\033]11;%s\007' "\$WS_COLOR"

# OSC 1337: set tab title via WezTerm user var (survives Claude Code title resets)
TITLE="\$WS_EMOJI \$WS_BRANCH [w\$WS_SLOT]"
B64=\$(echo -n "\$TITLE" | base64)
printf '\033]1337;SetUserVar=panetitle=%s\007' "\$B64"
ENVEOF2
echo "  ✓ .worktree-env.sh"
t ".worktree-env.sh written"

# --- 3. .vscode/settings.json per repo (merge if exists) ---
if [ "$REPO_COUNT" -gt 0 ]; then
  for i in $(seq 0 $((REPO_COUNT - 1))); do
    REPO_DIR="$WS_PATH/${REPO_NAMES[$i]}"
    [ ! -d "$REPO_DIR" ] && continue
    VSCODE_DIR="$REPO_DIR/.vscode"
    VSCODE_FILE="$VSCODE_DIR/settings.json"
    mkdir -p "$VSCODE_DIR"

    if [ -f "$VSCODE_FILE" ]; then
      # Merge: add/replace colorCustomizations
      python3 -c "
import json
f = '$VSCODE_FILE'
try:
    settings = json.load(open(f))
except:
    settings = {}
settings['workbench.colorCustomizations'] = {
    'titleBar.activeBackground': '$COLOR',
    'titleBar.activeForeground': '#ffffff',
    'statusBar.background': '$COLOR',
    'statusBar.foreground': '#ffffff'
}
with open(f, 'w') as out:
    json.dump(settings, out, indent=4)
    out.write('\n')
"
    else
      cat > "$VSCODE_FILE" << VSCEOF
{
    "workbench.colorCustomizations": {
        "titleBar.activeBackground": "$COLOR",
        "titleBar.activeForeground": "#ffffff",
        "statusBar.background": "$COLOR",
        "statusBar.foreground": "#ffffff"
    }
}
VSCEOF
    fi
    echo "  ✓ ${REPO_NAMES[$i]}/.vscode/settings.json"
  done
fi
t ".vscode/settings.json done ($REPO_COUNT repo(s))"

# --- 4. .code-workspace (multi-repo only) ---
if [ "$REPO_COUNT" -gt 1 ]; then
  python3 -c "
import json
repos = '${REPO_NAMES[*]}'.split()
emoji = '$EMOJI'
color = '$COLOR'
slug = '$SLUG'
folders = [{'path': r, 'name': f'{emoji} {r}'} for r in repos]
workspace = {
    'folders': folders,
    'settings': {
        'workbench.colorCustomizations': {
            'titleBar.activeBackground': color,
            'titleBar.activeForeground': '#ffffff',
            'statusBar.background': color,
            'statusBar.foreground': '#ffffff'
        }
    }
}
with open(f'$WS_PATH/{slug}.code-workspace', 'w') as f:
    json.dump(workspace, f, indent=2)
    f.write('\n')
"
  echo "  ✓ $SLUG.code-workspace"
fi
t ".code-workspace done"

# --- 5. .env.local per repo (copy from origin + substitute ports) ---
if [ -n "$CONFIG" ] && [ "$REPO_COUNT" -gt 0 ]; then
  CONFIG="$CONFIG" PROJECT_ROOT="$PROJECT_ROOT" WS_PATH="$WS_PATH" \
  SLOT="$SLOT" BRANCH="$BRANCH" COLOR="$COLOR" EMOJI="$EMOJI" \
  python3 << 'PYEOF'
import json, os, shutil

config = json.load(open(os.environ.get('CONFIG', '')))
ws_path = os.environ['WS_PATH']
slot = int(os.environ['SLOT'])
branch = os.environ['BRANCH']
color = os.environ['COLOR']
emoji = os.environ['EMOJI']
slug = branch.replace('/', '-')
port_step = config.get('port_step', 10)
repos = config.get('repos', [])
project_root = os.environ.get('PROJECT_ROOT', '')

# Calculate all ports
repo_ports = {}
origin_ports = {}
for r in repos:
    port = r.get('port_base', 3000) + slot * port_step
    repo_ports[r['name']] = port
    origin_ports[r['name']] = r.get('port_base', 3000)

for r in repos:
    repo_name = r['name']
    repo_path = os.path.join(ws_path, repo_name)
    port = repo_ports[repo_name]

    if not os.path.isdir(repo_path):
        continue

    # Find origin path
    origin = r.get('origin', '.')
    if origin == '.':
        origin_path = project_root
    else:
        origin_path = os.path.normpath(os.path.join(project_root, origin))

    # Copy .env* files ONLY from this repo's own origin (not project_root).
    # Copying from project_root too used to cross-pollute (e.g. front received
    # back's .env.local), forcing a manual rm afterwards.
    if os.path.isdir(origin_path):
        for f in sorted(os.listdir(origin_path)):
            if f.startswith('.env') and 'production' not in f.lower():
                src = os.path.join(origin_path, f)
                dst = os.path.join(repo_path, f)
                if os.path.isfile(src) and not os.path.isfile(dst):
                    shutil.copy2(src, dst)

    # Copy Rails credentials + master keys from origin (required to boot Rails)
    # These are gitignored per-repo, so the worktree won't have them until we copy.
    creds_sources = [
        ('config/master.key', 'config/master.key'),
        ('config/credentials/development.key', 'config/credentials/development.key'),
        ('config/credentials/test.key', 'config/credentials/test.key'),
        ('config/credentials/staging.key', 'config/credentials/staging.key'),
    ]
    for rel_src, rel_dst in creds_sources:
        src = os.path.join(origin_path, rel_src)
        dst = os.path.join(repo_path, rel_dst)
        if os.path.isfile(src) and not os.path.isfile(dst):
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
            print(f'  ✓ {repo_name}/{rel_dst}')

    # Process .env.local
    env_local = os.path.join(repo_path, '.env.local')
    if not os.path.isfile(env_local):
        existing = ''
    else:
        existing = open(env_local).read()

    # Ensure trailing newline
    if existing and not existing.endswith('\n'):
        existing += '\n'

    # Port substitution: replace origin ports with workspace ports
    for rn, wp in repo_ports.items():
        op = origin_ports.get(rn)
        if op:
            existing = existing.replace(f':{op}', f':{wp}')

    # Workspace variables
    ws_vars = {
        'PORT': str(port),
        'WS_SLOT': str(slot),
        'WS_BRANCH': branch,
        'WS_COLOR': color,
        'WS_EMOJI': emoji,
    }

    # env_template variables
    env_template = r.get('env_template', {})
    for key, val in env_template.items():
        val = str(val)
        val = val.replace('$SLOT', str(slot))
        val = val.replace('$BRANCH', branch)
        val = val.replace('$SLUG', slug)
        val = val.replace('$PORT', str(port))
        val = val.replace('$WORKSPACE_PATH', ws_path)
        for rn, rp in repo_ports.items():
            val = val.replace(f'${rn.upper()}_PORT', str(rp))
        ws_vars[key] = val

    # Apply: replace existing or append
    lines = existing.split('\n')
    existing_keys = set()
    new_lines = []
    for line in lines:
        replaced = False
        for key, val in ws_vars.items():
            if line.startswith(f'{key}='):
                new_lines.append(f'{key}={val}')
                existing_keys.add(key)
                replaced = True
                break
        if not replaced:
            new_lines.append(line)

    for key, val in ws_vars.items():
        if key not in existing_keys:
            new_lines.append(f'{key}={val}')

    with open(env_local, 'w') as f:
        content = '\n'.join(new_lines)
        if not content.endswith('\n'):
            content += '\n'
        f.write(content)

    print(f'  ✓ {repo_name}/.env.local (port {port})')

    # Copy scripts/db/.env from origin if present (holds STAGING/PROD credentials
    # used by pull_db.sh etc. — must NOT be clobbered with .env.local content).
    scripts_db_dir = os.path.join(repo_path, 'scripts', 'db')
    if os.path.isdir(scripts_db_dir):
        origin_db_env = os.path.join(origin_path, 'scripts', 'db', '.env')
        dst_db_env = os.path.join(scripts_db_dir, '.env')
        if os.path.isfile(origin_db_env) and not os.path.isfile(dst_db_env):
            shutil.copy2(origin_db_env, dst_db_env)
            print(f'  ✓ {repo_name}/scripts/db/.env (from origin)')
PYEOF
fi
t ".env.local + creds + scripts/db/.env done"

echo "  ✓ All files generated"
t "DONE"
