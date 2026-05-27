#!/bin/bash
# ws-preflight.sh — Gather all pre-creation data in ONE call
#
# Merges what used to be Steps 1 + 2 + 4a of the SKILL (3 separate LLM tool
# calls) into a single JSON output. The LLM parses this once, computes
# slot/ports/path, and goes straight to the recap.
#
# Usage:
#   ws-preflight.sh [project_root]
#
# If project_root is omitted, uses the current git root.
# Outputs a single JSON object to stdout with:
#   git_root, config (merged), registry, free_slot, color, emoji

set -euo pipefail

COLORS='["#1a3a2a","#3a2a15","#2a1a3a","#3a1515","#15353a","#3a1a2e","#3a3415","#1a2835"]'
EMOJIS='["🟢","🟠","🟣","🔴","🩵","🩷","🟡","🔵"]'

PROJECT_ROOT="${1:-}"

python3 - "$PROJECT_ROOT" "$COLORS" "$EMOJIS" <<'PYEOF'
import json, os, subprocess, sys

project_root = sys.argv[1]
colors = json.loads(sys.argv[2])
emojis = json.loads(sys.argv[3])

# --- Step 1: git root ---
if not project_root:
    r = subprocess.run(['git', 'rev-parse', '--show-toplevel'],
                       capture_output=True, text=True)
    if r.returncode != 0:
        json.dump({"error": "not_a_git_repo"}, sys.stdout)
        sys.exit(1)
    project_root = r.stdout.strip()

# --- Step 2: config (shared + local merge) ---
config_path = os.path.join(project_root, '.claude-workspaces.json')
if not os.path.isfile(config_path):
    json.dump({"error": "no_config", "git_root": project_root}, sys.stdout)
    sys.exit(0)

with open(config_path) as f:
    config = json.load(f)

local_path = os.path.join(project_root, '.claude-workspaces.local.json')
if os.path.isfile(local_path):
    with open(local_path) as f:
        local = json.load(f)
    # Merge top-level overrides
    for key in ('workspaces_root', 'port_step', 'hooks', 'terminal'):
        if key in local:
            config[key] = local[key]
    # Merge repos by name
    local_repos = local.get('repos', {})
    if isinstance(local_repos, dict):
        for repo in config.get('repos', []):
            if repo['name'] in local_repos:
                repo.update(local_repos[repo['name']])

missing_origins = [r['name'] for r in config.get('repos', []) if 'origin' not in r]

# --- Step 4a: registry ---
reg_path = os.path.expanduser('~/.claude-workspaces/registry.json')
if os.path.isfile(reg_path):
    with open(reg_path) as f:
        registry = json.load(f)
else:
    registry = {"workspaces": {}, "next_slot": 1}

# Find first free slot
used = set(int(k) for k in registry.get('workspaces', {}).keys())
slot = 1
while slot in used:
    slot += 1

idx = (slot - 1) % 8
color = colors[idx]
emoji = emojis[idx]

# Compute ports
port_step = config.get('port_step', 10)
repos_with_ports = []
for r in config.get('repos', []):
    port = r.get('port_base', 3000) + (slot * port_step)
    repos_with_ports.append({"name": r['name'], "port": port, "port_base": r.get('port_base', 3000)})

result = {
    "git_root": project_root,
    "config": config,
    "registry": registry,
    "free_slot": slot,
    "color": color,
    "emoji": emoji,
    "repos_with_ports": repos_with_ports,
    "workspaces_root": os.path.expanduser(config.get('workspaces_root', '~/workspaces')),
    "port_step": port_step,
}
if missing_origins:
    result["missing_origins"] = missing_origins

json.dump(result, sys.stdout, ensure_ascii=False)
PYEOF
