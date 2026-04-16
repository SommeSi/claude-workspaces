#!/bin/bash
# ws-env-setup.sh — Copy .env files from origin and setup workspace vars
# Usage: ws-env-setup <workspace_path> <slot> <branch> <color> <emoji>
#
# Reads .claude-workspaces.json from project root and:
# 1. Copies .env* from origin repos
# 2. Appends workspace variables
# 3. Substitutes ports
# 4. Applies env_template

set -euo pipefail

WS_PATH="$1"
SLOT="$2"
BRANCH="$3"
COLOR="$4"
EMOJI="$5"

# Find config
CONFIG=""
for dir in "$WS_PATH" "$(git -C "$WS_PATH" rev-parse --show-toplevel 2>/dev/null || true)"; do
  if [ -f "$dir/.claude-workspaces.json" ]; then
    CONFIG="$dir/.claude-workspaces.json"
    break
  fi
done

if [ -z "$CONFIG" ]; then
  echo "No .claude-workspaces.json found" >&2
  exit 1
fi

python3 -c "
import json, os, re, shutil

config = json.load(open('$CONFIG'))
ws_path = '$WS_PATH'
slot = int('$SLOT')
branch = '$BRANCH'
color = '$COLOR'
emoji = '$EMOJI'
port_step = config.get('port_step', 10)
repos = config.get('repos', [])
slug = branch.replace('/', '-')

# Calculate all ports
repo_ports = {}
for r in repos:
    port = r.get('port_base', 3000) + slot * port_step
    repo_ports[r['name']] = port

# Find git root for origin resolution
git_root = os.popen(f'git -C \"{ws_path}\" rev-parse --show-toplevel 2>/dev/null').read().strip()
if not git_root:
    git_root = os.path.dirname('$CONFIG')

for r in repos:
    repo_name = r['name']
    repo_path = os.path.join(ws_path, repo_name)
    port = repo_ports[repo_name]

    if not os.path.isdir(repo_path):
        continue

    # Find origin .env files
    origin = r.get('origin', '.')
    if origin == '.':
        origin_path = git_root
    else:
        origin_path = os.path.normpath(os.path.join(git_root, origin))

    # Copy .env* files from origin (and git root)
    for search_dir in [origin_path, git_root]:
        if not os.path.isdir(search_dir):
            continue
        for f in os.listdir(search_dir):
            if f.startswith('.env') and 'production' not in f:
                src = os.path.join(search_dir, f)
                dst = os.path.join(repo_path, f)
                if os.path.isfile(src) and not os.path.isfile(dst):
                    shutil.copy2(src, dst)

    # Build .env.local content
    env_local = os.path.join(repo_path, '.env.local')
    existing = ''
    if os.path.isfile(env_local):
        existing = open(env_local).read()

    # Ensure trailing newline
    if existing and not existing.endswith('\n'):
        existing += '\n'

    # Port substitution: replace origin ports with workspace ports
    for rn, rp in repo_ports.items():
        for orig_r in repos:
            if orig_r['name'] == rn:
                orig_port = orig_r.get('port_base', 3000)
                existing = existing.replace(f':{orig_port}', f':{rp}')
                break

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
        val = val.replace('\$SLOT', str(slot))
        val = val.replace('\$BRANCH', branch)
        val = val.replace('\$SLUG', slug)
        val = val.replace('\$PORT', str(port))
        val = val.replace('\$WORKSPACE_PATH', ws_path)
        for rn, rp in repo_ports.items():
            val = val.replace(f'\${rn.upper()}_PORT', str(rp))
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

    # Append new vars not already present
    for key, val in ws_vars.items():
        if key not in existing_keys:
            new_lines.append(f'{key}={val}')

    # Write
    with open(env_local, 'w') as f:
        f.write('\n'.join(new_lines))
        if not new_lines[-1] == '':
            f.write('\n')

    print(f'  ✓ {repo_name}/.env.local (port {port})')
"
