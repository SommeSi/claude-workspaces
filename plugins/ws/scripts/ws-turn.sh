#!/usr/bin/env bash
# ws-turn.sh — Per-turn recap of the files Claude edited.
#
# Registered as hooks:
#   PostToolUse (Edit|Write|MultiEdit|NotebookEdit) → ws-turn.sh record
#   Stop                                           → ws-turn.sh recap
#
# Only files Claude actually wrote are listed — no git-status guessing, so
# unrelated dirty files and test artifacts never show up.
#
# The Claude Code UI prints a hook's systemMessage as raw text, one "Stop says:"
# line per line: no markdown, no clickable links. Hence plain relative paths,
# one per line, capped.
#
# Never blocks a turn: always exits 0, silent outside a workspace.
# record MUST print nothing (hook stdout can reach the transcript).
# State lives in $TMPDIR/ws-turn/<session_id>.txt (override: WS_TURN_DIR).

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

WS_HOOK_INPUT="$(cat 2>/dev/null || true)" WS_TURN_MODE="${1:-}" python3 - <<'PYEOF' 2>/dev/null
import fcntl, json, os, re, subprocess, tempfile

MAX_LINES = 12

def ws_root(d):
    d = os.path.abspath(d)
    start = d
    while True:
        f = os.path.join(d, 'CLAUDE.local.md')
        if os.path.isfile(f) and '## Workspace info' in open(f, errors='ignore').read():
            return d
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    # Fallback: registry longest-prefix match (same as ws-progress-capture.sh) —
    # covers layouts where cwd has no CLAUDE.local.md ancestor.
    registry_path = os.environ.get('WS_REGISTRY') or os.path.expanduser('~/.claude-workspaces/registry.json')
    if not os.path.isfile(registry_path):
        return None
    try:
        reg = json.load(open(registry_path))
    except Exception:
        return None
    best, best_len = None, 0
    for ws in reg.get('workspaces', {}).values():
        for p in [ws.get('workspace_path', '')] + [r.get('path', '') for r in ws.get('repos', [])]:
            if p and (start == p or start.startswith(p + os.sep)) and len(p) > best_len:
                best, best_len = ws.get('workspace_path'), len(p)
    return best

def status(path):
    """M edited · A added · D deleted · R back to its committed state."""
    if not os.path.exists(path):
        return 'D'
    repo, name = os.path.dirname(path), os.path.basename(path)
    # --ignored: without it, git omits gitignored paths entirely, which would
    # otherwise misreport a freshly-written ignored file as 'R' (reverted).
    r = subprocess.run(['git', '-C', repo, 'status', '--porcelain', '--ignored', '--', name],
                       capture_output=True, timeout=4)
    if r.returncode != 0:
        return 'M'  # not a git repo: it was still written this turn
    out = r.stdout.decode(errors='surrogateescape')
    if not out.strip():
        return 'R'
    return 'A' if out[0] in ('?', 'A', '!') else 'M'

def main():
    mode = os.environ.get('WS_TURN_MODE')
    try:
        data = json.loads(os.environ.get('WS_HOOK_INPUT') or '{}')
    except ValueError:
        return
    if mode not in ('record', 'recap') or not isinstance(data, dict):
        return
    root = ws_root(data.get('cwd') or os.getcwd())
    if not root:
        return
    sid = re.sub(r'[^A-Za-z0-9_-]', '_', str(data.get('session_id') or 'default'))
    state_dir = os.environ.get('WS_TURN_DIR') or os.path.join(tempfile.gettempdir(), 'ws-turn')
    state_file = os.path.join(state_dir, sid + '.txt')

    if mode == 'record':
        tool_input = data.get('tool_input') or {}
        paths = [tool_input.get('file_path') or tool_input.get('notebook_path') or '']
        paths = [os.path.abspath(p) for p in paths if p]
        if not paths:
            return
        os.makedirs(state_dir, exist_ok=True)
        with open(state_file, 'a') as fh:
            fcntl.flock(fh, fcntl.LOCK_EX)  # concurrent PostToolUse hooks can overlap
            fh.write('\n'.join(paths) + '\n')
        return

    if not os.path.isfile(state_file):
        return
    with open(state_file) as fh:
        paths = list(dict.fromkeys(l.strip() for l in fh if l.strip()))

    # Compute before removing: if status() throws (e.g. git missing/timeout),
    # the state file survives so the recap can still be produced next Stop.
    rows = [(status(p), os.path.relpath(p, root)) for p in paths]
    os.remove(state_file)
    if not rows:
        return
    n = len(rows)
    plural = 's' if n > 1 else ''
    lines = [f'📝 {n} fichier{plural} modifié{plural} ce tour']
    lines += [f'  {st} {rel}' for st, rel in rows[:MAX_LINES]]
    if n > MAX_LINES:
        lines.append(f'  … et {n - MAX_LINES} autres')
    print(json.dumps({'systemMessage': '\n'.join(lines)}, ensure_ascii=False))

try:
    main()
except Exception:
    pass
PYEOF
exit 0
