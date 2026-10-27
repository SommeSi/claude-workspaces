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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${1:-}"

python3 - "$PROJECT_ROOT" "$SCRIPT_DIR" <<'PYEOF'
import json, os, subprocess, sys

project_root = sys.argv[1]
script_dir = sys.argv[2]

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

# --- Sprint cards straight from the Notion API (in a thread, alongside the rest) ---
# Saves start-worktree a whole LLM turn. Needs the integration token in the keychain
# (service claude-workspaces-notion); without it the skill falls back to the Notion MCP.
# The token is a bot, so "me" = the person whose email is notion_user_email in the
# per-user ~/.claude-workspaces/config.json (else git's user.email), resolved once via
# /v1/users and cached. Never in a repo file: teammates would get someone else's cards.
import threading, urllib.request, datetime

def notion_cards(n):
    tok = subprocess.run(['security', 'find-generic-password', '-s', 'claude-workspaces-notion', '-a', 'notion', '-w'],
                         capture_output=True, text=True).stdout.strip()
    if not tok or not n.get('data_source'):
        return None
    def api(path, body=None):
        req = urllib.request.Request('https://api.notion.com/v1/' + path, method='POST' if body is not None else 'GET',
                                     data=json.dumps(body).encode() if body is not None else None,
                                     headers={'Authorization': f'Bearer {tok}', 'Notion-Version': '2025-09-03',
                                              'Content-Type': 'application/json'})
        return json.load(urllib.request.urlopen(req, timeout=4))
    try:
        user_cfg = json.load(open(os.path.expanduser('~/.claude-workspaces/config.json')))
    except (OSError, ValueError):
        user_cfg = {}
    email = user_cfg.get('notion_user_email') or subprocess.run(['git', 'config', 'user.email'],
                                                            capture_output=True, text=True).stdout.strip()
    cache_path = os.path.expanduser('~/.claude-workspaces/cache/notion-users.json')
    try:
        users = json.load(open(cache_path))
    except (OSError, ValueError):
        users = {}
    if email not in users:
        users = {u['person']['email']: u['id'] for u in api('users?page_size=100')['results']
                 if u.get('type') == 'person' and u.get('person', {}).get('email')}
        os.makedirs(os.path.dirname(cache_path), exist_ok=True)
        json.dump(users, open(cache_path, 'w'))
    uid = users.get(email)
    if not uid:
        return {"error": f"no Notion user with email {email} (set notion_user_email in ~/.claude-workspaces/config.json)"}
    sprint = n.get('sprint_format', 'Sprint {week}').replace('{week}', str(datetime.date.today().isocalendar()[1]))
    rows = api(f"data_sources/{n['data_source'].replace('collection://', '')}/query", {"page_size": 50, "filter": {"and": [
        {"property": n.get('sprint_property', 'Sprint'), "multi_select": {"contains": sprint}},
        {"property": n.get('assignee_property', 'Assigné à'), "people": {"contains": uid}}]}})['results']
    def val(p):
        t = p.get('type')
        if t in ('title', 'rich_text'):
            return ''.join(x.get('plain_text', '') for x in p[t])[:300]
        if t == 'select':
            return (p['select'] or {}).get('name', '')
        if t == 'unique_id':
            return f"{p['unique_id'].get('prefix') or ''}-{p['unique_id']['number']}".lstrip('-')
        return ''
    status = n.get('status_property', 'Statut')
    prio = ['Critical', 'High', 'Medium', 'Low']
    cards = [{k: val(r['properties'][k]) for k in ('ID', 'Tâche', 'Type', 'Priorité', status, 'Description générale')
              if k in r['properties']} | {'url': r['url']} for r in rows]
    cards = [c for c in cards if c.get(status) not in n.get('exclude_status', [])]
    cards.sort(key=lambda c: next((i for i, p in enumerate(prio) if p in c.get('Priorité', '')), 9))
    return {"sprint": sprint, "cards": cards}

cards_box = {}
def _fetch():
    try:
        cards_box['v'] = notion_cards(config.get('notion') or {})
    except Exception as e:  # never break the preflight for Notion
        cards_box['v'] = {"error": f"notion: {e}"}
cards_thread = threading.Thread(target=_fetch, daemon=True) if config.get('notion') else None
if cards_thread:
    cards_thread.start()

# origin may be a list of candidate paths: keep the first that exists.
# A repo whose origin is absent or not found on disk is reported missing.
for r in config.get('repos', []):
    if isinstance(r.get('origin'), list):
        r['origin'] = next((c for c in r['origin'] if os.path.isdir(os.path.join(project_root, c))), None)
missing_origins = [r['name'] for r in config.get('repos', [])
                   if not r.get('origin') or not os.path.isdir(os.path.join(project_root, r['origin']))]

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

# Resolve color/emoji from the shared palette (single source of truth).
# Slots 1..16 are curated; 17+ are generated → effectively infinite.
pal = subprocess.run(
    [os.path.join(script_dir, 'ws-palette.sh'), str(slot)],
    capture_output=True, text=True,
)
color, emoji = '', ''
for line in pal.stdout.splitlines():
    if line.startswith('COLOR='):
        color = line[len('COLOR='):]
    elif line.startswith('EMOJI='):
        emoji = line[len('EMOJI='):]

# Compute ports
port_step = config.get('port_step', 10)
repos_with_ports = []
for r in config.get('repos', []):
    port = r.get('port_base', 3000) + (slot * port_step)
    repos_with_ports.append({
        "name": r['name'],
        "port": port,
        "port_base": r.get('port_base', 3000),
        "optional": bool(r.get('optional', False)),
    })

# Slim output: it is read by an LLM, every token costs latency.
# env_template/terminal/registry are consumed by other scripts, not by callers of this one.
slim = {k: v for k, v in config.items() if k != 'terminal'}
slim['repos'] = [{k: v for k, v in r.items() if k != 'env_template'} for r in config.get('repos', [])]

result = {
    "git_root": project_root,
    "config": slim,
    "free_slot": slot,
    "color": color,
    "emoji": emoji,
    "repos_with_ports": repos_with_ports,
    "workspaces_root": os.path.expanduser(config.get('workspaces_root', '~/workspaces')),
    "port_step": port_step,
}
if missing_origins:
    result["missing_origins"] = missing_origins
if cards_thread:
    cards_thread.join(timeout=5)
    if cards_box.get('v'):
        result["sprint_cards"] = cards_box['v']

json.dump(result, sys.stdout, ensure_ascii=False)
PYEOF
