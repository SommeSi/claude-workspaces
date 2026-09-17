#!/usr/bin/env bash
# ws-turn.sh — Per-turn recap of files changed by Claude, with clickable links.
#
# Registered as hooks:
#   UserPromptSubmit → ws-turn.sh snapshot   (records dirty files + content hash)
#   Stop             → ws-turn.sh diff       (prints {"systemMessage": recap})
#
# A file shows up only if Claude touched it during the turn: files already dirty
# before the prompt and left untouched are ignored.
#
# Never blocks a turn: always exits 0, silent outside a workspace.
# snapshot MUST print nothing (UserPromptSubmit stdout is injected as context).
# State lives in $TMPDIR/ws-turn/<session_id>.json (override: WS_TURN_DIR).

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

WS_HOOK_INPUT="$(cat 2>/dev/null || true)" WS_TURN_MODE="${1:-}" python3 - <<'PYEOF' 2>/dev/null
import hashlib, json, os, re, subprocess, sys, tempfile, urllib.parse

MAX_LINES = 20

def ws_root(d):
    d = os.path.abspath(d)
    while True:
        f = os.path.join(d, 'CLAUDE.local.md')
        if os.path.isfile(f) and '## Workspace info' in open(f, errors='ignore').read():
            return d
        parent = os.path.dirname(d)
        if parent == d:
            return None
        d = parent

def repos(root):
    # Same scope as ws-progress-capture.sh: root and its direct children.
    cands = [root] + [os.path.join(root, n) for n in sorted(os.listdir(root))]
    return [c for c in cands if os.path.isdir(c) and os.path.exists(os.path.join(c, '.git'))]

def state(repo):
    """{rel_path: [sha1|'DELETED', porcelain_xy]} for every dirty/untracked file."""
    r = subprocess.run(['git', '-C', repo, 'status', '--porcelain', '-z', '--untracked-files=all'],
                       capture_output=True, timeout=4)
    if r.returncode != 0:
        return {}
    parts = r.stdout.decode(errors='surrogateescape').split('\0')
    out, i = {}, 0
    while i < len(parts):
        e = parts[i]
        i += 1
        if len(e) < 4:
            continue
        xy, path = e[:2], e[3:]
        if 'R' in xy or 'C' in xy:
            i += 1  # skip the original path of a rename/copy
        full = os.path.join(repo, path)
        if os.path.isdir(full):
            continue  # submodule
        if os.path.isfile(full):
            with open(full, 'rb') as fh:
                out[path] = [hashlib.sha1(fh.read()).hexdigest(), xy]
        else:
            out[path] = ['DELETED', xy]
    return out

def main():
    mode = os.environ.get('WS_TURN_MODE')
    try:
        data = json.loads(os.environ.get('WS_HOOK_INPUT') or '{}')
    except ValueError:
        return
    if mode not in ('snapshot', 'diff') or not isinstance(data, dict):
        return
    root = ws_root(data.get('cwd') or os.getcwd())
    if not root:
        return
    sid = re.sub(r'[^A-Za-z0-9_-]', '_', str(data.get('session_id') or 'default'))
    state_dir = os.environ.get('WS_TURN_DIR') or os.path.join(tempfile.gettempdir(), 'ws-turn')
    state_file = os.path.join(state_dir, sid + '.json')

    if mode == 'snapshot':
        os.makedirs(state_dir, exist_ok=True)
        with open(state_file, 'w') as fh:
            json.dump({repo: state(repo) for repo in repos(root)}, fh)
        return

    if not os.path.isfile(state_file):
        return
    with open(state_file) as fh:
        before_all = json.load(fh)
    os.remove(state_file)

    rows = []
    for repo in repos(root):
        before, after = before_all.get(repo, {}), state(repo)
        label = '.' if repo == root else os.path.relpath(repo, root)
        for path in sorted(set(before) | set(after)):
            b, a = before.get(path), after.get(path)
            if b == a:
                continue
            if a is None:
                status = 'R'  # was dirty, now back to committed state
            elif a[0] == 'DELETED':
                status = 'D'
            elif a[1] == '??' or 'A' in a[1]:
                status = 'A'
            else:
                status = 'M'
            if status == 'D':
                shown = path
            else:
                url = 'vscode://file' + urllib.parse.quote(os.path.join(repo, path)) + ':1'
                shown = f'[{path}]({url})'
            rows.append((label, status, shown))

    if not rows:
        return
    width = max(len(r[0]) for r in rows)
    n = len(rows)
    lines = [f'📝 {n} fichier{"s" if n > 1 else ""} modifié{"s" if n > 1 else ""} ce tour']
    lines += [f'  {label.ljust(width)}  {status} {shown}' for label, status, shown in rows[:MAX_LINES]]
    if n > MAX_LINES:
        lines.append(f'  … et {n - MAX_LINES} autres')
    print(json.dumps({'systemMessage': '\n'.join(lines)}, ensure_ascii=False))

try:
    main()
except Exception:
    pass
PYEOF
exit 0
