#!/bin/bash
# ws-open.sh — Open WezTerm layout for the current workspace
# Usage: ws-open [workspace_path]
# If no argument, detects workspace from PWD.

set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

REGISTRY="$HOME/.claude-workspaces/registry.json"

# --- Detect WezTerm CLI ---
if [[ -x "/Applications/WezTerm.app/Contents/MacOS/wezterm" ]]; then
  W="/Applications/WezTerm.app/Contents/MacOS/wezterm"
elif command -v wezterm &>/dev/null; then
  W="$(which wezterm)"
else
  echo "❌ WezTerm not found" >&2
  exit 1
fi

# --- Find workspace from PWD or argument ---
WS_PATH="${1:-}"
if [ -z "$WS_PATH" ]; then
  if [ ! -f "$REGISTRY" ]; then
    echo "❌ No registry found" >&2
    exit 1
  fi

  eval "$(python3 -c "
import json, os
reg = json.load(open('$REGISTRY'))
cwd = os.getcwd()
best_len = 0
best = None
for slot, ws in reg.get('workspaces', {}).items():
    wp = ws.get('workspace_path', '')
    paths = [wp] + [r.get('path', '') for r in ws.get('repos', [])]
    for p in paths:
        if p and cwd.startswith(p) and len(p) > best_len:
            best_len = len(p)
            best = ws
            best['slot'] = slot
if best:
    print(f'WS_PATH={best[\"workspace_path\"]!r}')
    print(f'WS_SLOT={best[\"slot\"]!r}')
    print(f'WS_BRANCH={best.get(\"branch\", best.get(\"slug\", \"\"))!r}')
    print(f'WS_EMOJI={best.get(\"emoji\", \"\")!r}')
    print(f'WS_COLOR={best.get(\"color\", \"\")!r}')
    print(f'WS_PROJECT_ROOT={best.get(\"project_root\", \"\")!r}')
else:
    print('echo \"❌ No workspace found for current directory\" >&2; exit 1')
")"
fi

# --- Load project config ---
CONFIG_FILE=""
WS_PROJECT_ROOT="${WS_PROJECT_ROOT:-}"
for f in ${WS_PROJECT_ROOT:+"$WS_PROJECT_ROOT/.claude-workspaces.json"} "$WS_PATH/.claude-workspaces.json"; do
  if [ -f "$f" ]; then
    CONFIG_FILE="$f"
    break
  fi
done

if [ -z "$CONFIG_FILE" ]; then
  echo "❌ No .claude-workspaces.json found" >&2
  exit 1
fi

# --- Parse terminal config and create layout ---
python3 -c "
import json, subprocess, sys, os, time

config = json.load(open('$CONFIG_FILE'))
terminal = config.get('terminal')
if not terminal:
    print('❌ No terminal section in config', file=sys.stderr)
    sys.exit(1)

W = '$W'
ws_path = '$WS_PATH'
slot = '$WS_SLOT'
branch = '$WS_BRANCH'
emoji = '$WS_EMOJI'
panes = terminal.get('panes', [])

# Resolve pane cwds
def resolve_cwd(repo):
    if repo == '.':
        return ws_path
    return os.path.join(ws_path, repo)

# Resolve command variables
def resolve_cmd(cmd, repo_name):
    if not cmd:
        return None
    # Find port for this repo
    port = ''
    for r in config.get('repos', []):
        if r['name'] == repo_name or (repo_name == '.' and r.get('origin') == '.'):
            port = str(r.get('port_base', 3000) + int(slot) * config.get('port_step', 10))
            break
    cmd = cmd.replace('\$PORT', port)
    cmd = cmd.replace('\$SLOT', slot)
    cmd = cmd.replace('\$BRANCH', branch)
    return cmd

if len(panes) == 0:
    print('❌ No panes defined', file=sys.stderr)
    sys.exit(1)

# Spawn first pane (new window)
p0_cwd = resolve_cwd(panes[0]['repo'])
result = subprocess.run([W, 'cli', 'spawn', '--new-window', '--cwd', p0_cwd], capture_output=True, text=True)
tl = result.stdout.strip()

# Get window ID
result = subprocess.run([W, 'cli', 'list', '--format', 'json'], capture_output=True, text=True)
wezterm_panes = json.loads(result.stdout)
window_id = None
for p in wezterm_panes:
    if str(p['pane_id']) == tl:
        window_id = str(p['window_id'])
        break

pane_ids = [tl]

if len(panes) >= 2:
    # Top-right
    p1_cwd = resolve_cwd(panes[1]['repo'])
    result = subprocess.run([W, 'cli', 'split-pane', '--pane-id', tl, '--right', '--percent', '50', '--cwd', p1_cwd], capture_output=True, text=True)
    tr = result.stdout.strip()
    pane_ids.append(tr)

if len(panes) >= 3:
    # Bottom-left
    p2_cwd = resolve_cwd(panes[2]['repo'])
    result = subprocess.run([W, 'cli', 'split-pane', '--pane-id', tl, '--bottom', '--percent', '50', '--cwd', p2_cwd], capture_output=True, text=True)
    bl = result.stdout.strip()
    pane_ids.append(bl)

if len(panes) >= 4:
    # Bottom-right
    p3_cwd = resolve_cwd(panes[3]['repo'])
    result = subprocess.run([W, 'cli', 'split-pane', '--pane-id', tr, '--bottom', '--percent', '50', '--cwd', p3_cwd], capture_output=True, text=True)
    br = result.stdout.strip()
    pane_ids.append(br)

# Send commands to all panes
for i, pane in enumerate(panes[:len(pane_ids)]):
    cmd = resolve_cmd(pane.get('cmd'), pane['repo'])
    if cmd:
        text = f'clear && {cmd}\n'
    else:
        text = 'clear\n'
    subprocess.run([W, 'cli', 'send-text', '--pane-id', pane_ids[i], '--no-paste', text])

# Claude tab
if terminal.get('claude_tab', True) and window_id:
    result = subprocess.run([W, 'cli', 'spawn', '--window-id', window_id, '--cwd', ws_path], capture_output=True, text=True)
    claude_pane = result.stdout.strip()
    time.sleep(1)
    claude_cmd = f'clear && claude --name \"{branch} [w{slot}]\"\n'
    subprocess.run([W, 'cli', 'send-text', '--pane-id', claude_pane, '--no-paste', claude_cmd])
    time.sleep(3)
    subprocess.run([W, 'cli', 'send-text', '--pane-id', claude_pane, '--no-paste', '/workspace:resume\n'])

# Fullscreen
if terminal.get('fullscreen', True) and sys.platform == 'darwin':
    time.sleep(0.5)
    subprocess.run(['osascript', '-e', '''
        tell application \"WezTerm\" to activate
        delay 0.3
        tell application \"System Events\"
            tell process \"WezTerm\"
                set value of attribute \"AXFullScreen\" of window 1 to true
            end tell
        end tell
    '''], capture_output=True)

# Summary
pane_summary = []
for i, pane in enumerate(panes[:len(pane_ids)]):
    cmd = pane.get('cmd', '(terminal)')
    pane_summary.append(f'  {pane[\"repo\"]:10s} → {cmd or \"(terminal)\"}')

print(f'✓ Layout opened! {emoji} [w{slot}] {branch}')
for s in pane_summary:
    print(s)
if terminal.get('claude_tab', True):
    print('  Claude tab → launched')
"
