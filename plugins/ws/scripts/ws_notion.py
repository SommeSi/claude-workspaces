#!/usr/bin/env python3
"""ws_notion.py — Kanban cards through the Notion integration token (no LLM turn).

  ws_notion.py cards [--all-sprints]   my open cards as JSON (current sprint, or every sprint)
  ws_notion.py create --title T --type Bug|Feature|Refacto|Documentation|Test
                      [--feature F] [--client C] [--desc D] [--status S]
                                       new card in the current sprint, assigned to me;
                                       prints "TASK-123 <url>"

Config: the `notion` block of the project's .claude-workspaces.json (found from cwd upward).
Token: keychain service claude-workspaces-notion. "Me" = notion_user_email in the per-user
~/.claude-workspaces/config.json, else git's user.email (never a repo file: teammates would
get someone else's cards). Exit 2 when the token or config is missing: callers fall back to
the Notion MCP. Imported by ws-preflight.sh for start-worktree's card picker.
"""
import argparse, datetime, json, os, subprocess, sys, urllib.request

PRIO = ['Critical', 'High', 'Medium', 'Low']
KEYS = ('ID', 'Tâche', 'Type', 'Priorité', 'Feature', 'Client', 'Description générale')


def token():
    return subprocess.run(['security', 'find-generic-password', '-s', 'claude-workspaces-notion', '-a', 'notion', '-w'],
                          capture_output=True, text=True).stdout.strip()


def api(tok, path, body=None):
    req = urllib.request.Request('https://api.notion.com/v1/' + path, method='POST' if body is not None else 'GET',
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={'Authorization': f'Bearer {tok}', 'Notion-Version': '2025-09-03',
                                          'Content-Type': 'application/json'})
    return json.load(urllib.request.urlopen(req, timeout=4))


def my_id(tok):
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
        users = {u['person']['email']: u['id'] for u in api(tok, 'users?page_size=100')['results']
                 if u.get('type') == 'person' and u.get('person', {}).get('email')}
        os.makedirs(os.path.dirname(cache_path), exist_ok=True)
        json.dump(users, open(cache_path, 'w'))
    return email, users.get(email)


def sprint(n):
    return n.get('sprint_format', 'Sprint {week}').replace('{week}', str(datetime.date.today().isocalendar()[1]))


def val(p):
    t = p.get('type')
    if t in ('title', 'rich_text'):
        return ''.join(x.get('plain_text', '') for x in p[t])[:300]
    if t == 'select':
        return (p['select'] or {}).get('name', '')
    if t == 'unique_id':
        return f"{p['unique_id'].get('prefix') or ''}-{p['unique_id']['number']}".lstrip('-')
    return ''


def cards(n, all_sprints=False):
    tok = token()
    if not tok or not n.get('data_source'):
        return None
    email, uid = my_id(tok)
    if not uid:
        return {"error": f"no Notion user with email {email} (set notion_user_email in ~/.claude-workspaces/config.json)"}
    flt = [{"property": n.get('assignee_property', 'Assigné à'), "people": {"contains": uid}}]
    if not all_sprints:
        flt.append({"property": n.get('sprint_property', 'Sprint'), "multi_select": {"contains": sprint(n)}})
    rows = api(tok, f"data_sources/{n['data_source'].replace('collection://', '')}/query",
               {"page_size": 100, "filter": {"and": flt}})['results']
    status = n.get('status_property', 'Statut')
    out = [{k: val(r['properties'][k]) for k in KEYS + (status,) if k in r['properties']} | {'url': r['url']}
           for r in rows]
    out = [c for c in out if c.get(status) not in n.get('exclude_status', [])]
    out.sort(key=lambda c: next((i for i, p in enumerate(PRIO) if p in c.get('Priorité', '')), 9))
    return {"sprint": sprint(n), "cards": out}


def create(n, title, type_, feature=None, client=None, desc=None, status='👀 In Review'):
    tok = token()
    _, uid = my_id(tok)
    ds = n['data_source'].replace('collection://', '')
    schema = api(tok, f'data_sources/{ds}')['properties']

    def option(prop, name):  # existing option only: never let a typo add a new Feature/Client
        names = [o['name'] for o in (schema.get(prop) or {}).get('select', {}).get('options', [])]
        hit = next((o for o in names if o.lower() == (name or '').lower()), None)
        if name and not hit:
            print(f"# {prop} « {name} » inconnu, laissé vide (valeurs : {', '.join(names)})", file=sys.stderr)
        return hit

    props = {'Tâche': {'title': [{'text': {'content': title}}]},
             'Type': {'select': {'name': type_}},
             n.get('status_property', 'Statut'): {'select': {'name': status}},
             n.get('sprint_property', 'Sprint'): {'multi_select': [{'name': sprint(n)}]}}
    if uid:
        props[n.get('assignee_property', 'Assigné à')] = {'people': [{'id': uid}]}
    for prop, name in (('Feature', feature), ('Client', client)):
        if option(prop, name):
            props[prop] = {'select': {'name': option(prop, name)}}
    if desc:
        props['Description générale'] = {'rich_text': [{'text': {'content': desc[:2000]}}]}
    page = api(tok, 'pages', {'parent': {'type': 'data_source_id', 'data_source_id': ds}, 'properties': props})
    print(f"{val(page['properties'].get('ID', {}))} {page['url']}")


def project_notion():
    d = os.getcwd()
    while d != '/':
        for base in (d, os.path.dirname(d)):
            p = os.path.join(base, '.claude-workspaces.json')
            if os.path.isfile(p):
                return json.load(open(p)).get('notion') or {}
        d = os.path.dirname(d)
    return {}


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    c = sub.add_parser('cards')
    c.add_argument('--all-sprints', action='store_true')
    m = sub.add_parser('create')
    m.add_argument('--title', required=True)
    m.add_argument('--type', required=True, choices=['Bug', 'Feature', 'Refacto', 'Documentation', 'Test'])
    for opt in ('--feature', '--client', '--desc'):
        m.add_argument(opt)
    m.add_argument('--status', default='👀 In Review')
    a = ap.parse_args()
    n = project_notion()
    if not n.get('data_source') or not token():
        sys.exit(2)
    if a.cmd == 'cards':
        print(json.dumps(cards(n, a.all_sprints), ensure_ascii=False))
    else:
        create(n, a.title, a.type, a.feature, a.client, a.desc, a.status)


if __name__ == '__main__':
    main()
