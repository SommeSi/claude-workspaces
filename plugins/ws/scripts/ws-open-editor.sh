#!/bin/bash
# ws-open-editor.sh — Open a workspace in VS Code: servers as folderOpen tasks
# in integrated terminals + Claude Code in the right sidebar.
# Usage: ws-open-editor.sh [workspace_path]   (defaults to PWD)
#
# Writes/merges <workspace_path>/<slug>.code-workspace:
#   - keeps existing folders, settings and non-"ws: " tasks
#   - one task per pane with a cmd (from WS_PANES_JSON, else terminal.panes)
# Env:
#   WS_PANES_JSON        panes override, same format as terminal.panes
#   WS_REGISTRY          registry path (default ~/.claude-workspaces/registry.json)
#   WS_EDITOR_NO_LAUNCH  if set, write the file but don't launch code / the URI

set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

LOOKUP_PATH="${1:-$(pwd)}" python3 - <<'PYEOF'
import json, os, shutil, subprocess, sys

registry_path = os.environ.get('WS_REGISTRY') or os.path.expanduser('~/.claude-workspaces/registry.json')
if not os.path.isfile(registry_path):
    sys.exit(f'❌ No registry found at {registry_path}')

# --- Find workspace (longest-prefix match, same as ws-open.sh) ---
lookup = os.path.realpath(os.environ['LOOKUP_PATH'])
best, best_len = None, 0
for slot, ws in json.load(open(registry_path)).get('workspaces', {}).items():
    for p in [ws.get('workspace_path', '')] + [r.get('path', '') for r in ws.get('repos', [])]:
        if not p:
            continue
        real = os.path.realpath(p)
        if (lookup == real or lookup.startswith(real + os.sep)) and len(real) > best_len:
            best, best_len = dict(ws, slot=slot), len(real)
if not best:
    sys.exit(f'❌ No workspace found matching {lookup!r}')

ws_path = best['workspace_path']
slot, emoji, color = str(best['slot']), best.get('emoji', ''), best.get('color', '')
branch = best.get('branch') or best.get('slug') or ''
slug = best.get('slug') or branch.replace('/', '-')
repos = best.get('repos', [])

# --- Panes: WS_PANES_JSON > terminal.panes > none ---
config = {}
for root in (best.get('project_root'), ws_path):
    f = root and os.path.join(root, '.claude-workspaces.json')
    if f and os.path.isfile(f):
        config = json.load(open(f))
        break
terminal = config.get('terminal') or {}
panes = json.loads(os.environ['WS_PANES_JSON']) if os.environ.get('WS_PANES_JSON') else terminal.get('panes', [])

def repo_for(name):
    for r in repos:
        if r.get('name') == name:
            return r
    if name == '.':
        for r in repos:
            if os.path.realpath(r.get('path', '')) == os.path.realpath(ws_path):
                return r
    return None

tasks = []
for pane in panes:
    cmd, name = pane.get('cmd'), pane.get('repo') or pane.get('cwd') or '.'
    if not cmd:
        continue  # plain terminal pane: VS Code always has one
    repo = repo_for(name)
    port = str(repo.get('port') or '') if repo else ''
    cmd = cmd.replace('$PORT', port).replace('$SLOT', slot).replace('$BRANCH', branch)
    tasks.append({
        'label': f'ws: {name} — {cmd}',
        'type': 'shell',
        'command': cmd,
        'options': {'cwd': ws_path if name == '.' else os.path.join(ws_path, name)},
        'isBackground': True,
        'problemMatcher': [],
        'presentation': {'panel': 'dedicated', 'reveal': 'always', 'group': 'ws-servers'},
        'runOptions': {'runOn': 'folderOpen'},
    })

# --- Merge into <slug>.code-workspace ---
target = os.path.join(ws_path, f'{slug}.code-workspace')
claude_tab = terminal.get('claude_tab', True)
if os.path.isfile(target):
    try:
        doc = json.load(open(target))
    except json.JSONDecodeError as e:
        # VS Code tolerates comments/trailing commas in .code-workspace; we don't.
        sys.exit(f'❌ {target} is not valid JSON ({e}) — remove any comments/trailing commas and retry')
else:
    folders = []
    for r in repos:
        rp = r.get('path')
        if not rp:
            continue
        rel = os.path.relpath(rp, ws_path)
        folders.append({'path': rel, 'name': f'{emoji} {r.get("name", "")}'.strip()})
    doc = {
        'folders': folders or [{'path': '.'}],
        'settings': {'workbench.colorCustomizations': {
            'titleBar.activeBackground': color, 'titleBar.activeForeground': '#ffffff',
            'statusBar.background': color, 'statusBar.foreground': '#ffffff'}},
    }
if claude_tab:
    # Claude Code lives in the secondary (right) sidebar; open it by default.
    doc.setdefault('settings', {}).setdefault('workbench.secondarySideBar.defaultVisibility', 'visible')
doc.setdefault('tasks', {}).setdefault('version', '2.0.0')
kept = [t for t in doc['tasks'].get('tasks', []) if not str(t.get('label', '')).startswith('ws: ')]
doc['tasks']['tasks'] = kept + tasks
with open(target, 'w') as out:
    json.dump(doc, out, indent=2, ensure_ascii=False)
    out.write('\n')

# --- Launch ---
# No vscode://anthropic.claude-code/open: that URI always opens Claude as a
# left editor tab and ignores claudeCode.preferredLocation (checked in v2.1.273).
if not os.environ.get('WS_EDITOR_NO_LAUNCH'):
    code = shutil.which('code') or next((c for c in (
        '/usr/local/bin/code',
        '/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code') if os.path.exists(c)), None)
    if not code:
        sys.exit("❌ VS Code CLI 'code' not found — in VS Code run: Shell Command: Install 'code' command in PATH")
    try:
        subprocess.run([code, target], check=True)
    except subprocess.CalledProcessError as e:
        sys.exit(f'❌ VS Code failed to open the workspace (exit {e.returncode})')

print(f'✓ VS Code opened! {emoji} [w{slot}] {branch}')
print(f'  Workspace file → {target}')
for t in tasks:
    print(f'  Task → {t["label"][4:]}')
if not tasks:
    print('  Tasks → none (no panes with a command)')
if claude_tab:
    print('  Claude → right sidebar (click the "Claude Code" tab once, VS Code remembers it)')
PYEOF
