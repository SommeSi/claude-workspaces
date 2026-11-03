#!/usr/bin/env python3
"""ws-review.py — per-repo baseline snapshots for the VS Code review extension.

  prompt   UserPromptSubmit: mark the session as running, then snapshot each repo of the
           workspace into refs/worktree/claude-review/baseline (branch, real index and
           files untouched). A repo whose changes are still pending review in a live
           VS Code window keeps its old baseline so unreviewed hunks accumulate.
  stop     Stop / StopFailure / SessionEnd: remove the running marker.

Hook JSON on stdin (cwd, session_id). Always exits 0 and never prints: stdout of
UserPromptSubmit is added to Claude's context.

State, under $WS_HOME/review/<slug>/ (WS_HOME defaults to ~/.claude-workspaces):
  running/<session_id>   empty, present while the session works
  pending/<repo>.json    {"count": n, "baseline": sha}, written by the extension (only count is read)
  alive/<window_id>      mtime refreshed every 10 s by the extension
  failed/<repo>.json     {"reason", "at"}: "instantané interrompu" while a snapshot runs (left
                         behind if the hook is killed), removed on success
  moved/<repo>.json      {"from", "to", "at"}: HEAD moved (pull, rebase, checkout...) while blocks
                         were pending, so the review restarted; the extension shows it and removes it

The baseline commit has HEAD as its parent (none on an unborn branch): when HEAD no longer
matches, the snapshot is renewed even with pending blocks, so upstream changes never enter
the review.
"""
import json, os, re, subprocess, sys, tempfile, time
from concurrent.futures import ThreadPoolExecutor

REF = "refs/worktree/claude-review/baseline"
ALIVE_MAX_AGE = 60  # seconds: an alive file older than this means the window is gone
DEADLINE = 3.5  # seconds for all git calls of one prompt (Claude Code kills the hook at 5 s)
MAX_UNTRACKED = 50 * 1024 * 1024  # untracked files above this stay out of the snapshot
DAY = 86400
INTERRUPTED = "instantané interrompu"
_ENV = {"GIT_AUTHOR_NAME": "claude-review", "GIT_AUTHOR_EMAIL": "claude-review@localhost",
        "GIT_COMMITTER_NAME": "claude-review", "GIT_COMMITTER_EMAIL": "claude-review@localhost"}
_deadline = None  # monotonic time shared by every git call of the current prompt


def _git(cwd, *args, env=None, input=None, ok=(0,)):
    timeout = 4 if _deadline is None else _deadline - time.monotonic()
    if timeout <= 0:
        raise RuntimeError(INTERRUPTED + " (délai dépassé)")
    try:
        p = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, input=input,
                           stdin=None if input is not None else subprocess.DEVNULL,
                           timeout=timeout, env={**os.environ, **(env or {})})
    except subprocess.TimeoutExpired:
        raise RuntimeError(f"{INTERRUPTED} (git {args[0]} trop lent)")
    if p.returncode not in ok:
        raise RuntimeError((p.stderr.strip() or f"git {args[0]} failed")[-500:])
    return p.stdout.strip()


def _workspaces(registry):
    """Usable registry entries, filtered as the extension's workspace.ts does."""
    ws = registry.get("workspaces", {}) if isinstance(registry, dict) else []
    for w in (ws.values() if isinstance(ws, dict) else ws if isinstance(ws, list) else []):
        if isinstance(w, dict) and w.get("slug") and w.get("workspace_path") and isinstance(w.get("repos"), list):
            yield w


def find_workspace(cwd, registry):
    """Workspace whose workspace_path is the longest prefix of cwd (as ws-finish-preflight.sh)."""
    target, match, best = os.path.realpath(cwd), None, -1
    for w in _workspaces(registry):
        wp = os.path.realpath(w["workspace_path"])
        if (target == wp or target.startswith(wp + os.sep)) and len(wp) > best:
            match, best = w, len(wp)
    return match


def _heads(path):
    """-> (HEAD, baseline, baseline's parent), None for each missing, in one git call."""
    out = _git(path, "cat-file", "--batch-check=%(objectname)", input=f"HEAD\n{REF}\n{REF}^\n")
    vals = [None if l.endswith(" missing") or not l else l for l in out.split("\n")]
    return tuple((vals + [None] * 3)[:3])


def _large_untracked(top):
    out = subprocess.run(["git", "ls-files", "-o", "--exclude-standard", "-z"], cwd=top, capture_output=True,
                         stdin=subprocess.DEVNULL, timeout=max(0.01, _deadline - time.monotonic()) if _deadline else 4)
    big = []
    for rel in out.stdout.decode("utf-8", "surrogateescape").split("\0"):
        try:
            if rel and os.lstat(os.path.join(top, rel)).st_size > MAX_UNTRACKED:
                big.append(rel)
        except OSError:
            pass
    return big


_UNSET = object()


def snapshot(repo_path, head=_UNSET):
    """Commit the whole working tree as a dangling commit whose parent is HEAD, point REF at it.
    Returns (sha, [untracked files left out because too large])."""
    top, real_index = _git(repo_path, "rev-parse", "--path-format=absolute", "--show-toplevel",
                           "--git-path", "index").split("\n")
    if head is _UNSET:
        head = _heads(top)[0]
    big = _large_untracked(top)
    fd, tmp = tempfile.mkstemp(prefix="claude-review.")
    os.close(fd)
    try:
        # Seeded from the real index: its stat cache spares rehashing every tracked file.
        if os.path.exists(real_index):
            with open(real_index, "rb") as s, open(tmp, "wb") as d:
                d.write(s.read())
            # Same mtime as the real index: git's racy-index guard depends on it.
            st = os.stat(real_index)
            os.utime(tmp, ns=(st.st_atime_ns, st.st_mtime_ns))
        else:
            os.unlink(tmp)  # no index yet: git wants a missing file, not an empty one
        env = {"GIT_INDEX_FILE": tmp}
        excl = [":(exclude,literal)" + rel for rel in big]
        _git(top, "add", "-A", *(["--", ".", *excl] if big else []), env=env)
        tree = _git(top, "write-tree", env=env)
    finally:
        for f in (tmp, tmp + ".lock"):
            if os.path.exists(f):
                os.unlink(f)
    sha = _git(top, "commit-tree", tree, *(["-p", head] if head else []), "-m", "claude-review baseline", env=_ENV)
    _git(top, "update-ref", REF, sha)
    return sha, big


def _alive_fresh(d):
    try:
        now = time.time()
        return any(now - os.stat(os.path.join(d, n)).st_mtime < ALIVE_MAX_AGE for n in os.listdir(d))
    except OSError:
        return False


def _pending(d, name):
    try:
        with open(os.path.join(d, "pending", name + ".json")) as f:
            return json.load(f).get("count", 0) > 0
    except (OSError, ValueError, AttributeError, TypeError):
        return False


def _now():
    return time.strftime("%Y-%m-%dT%H:%M:%S%z")


def _write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = f"{path}.{os.getpid()}.tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, ensure_ascii=False)
    os.replace(tmp, path)


def _rm(path):
    try:
        os.unlink(path)
    except OSError:
        pass


def _resolve(payload, home):
    """-> (slug, [(repo_name, path)]) for the payload's cwd."""
    cwd = payload.get("cwd") or os.getcwd()
    try:
        with open(os.path.join(home, "registry.json")) as f:
            w = find_workspace(cwd, json.load(f))
    except (OSError, ValueError):
        w = None
    if w:
        return w["slug"], [(r["name"], r["path"]) for r in w["repos"]
                           if isinstance(r, dict) and r.get("name") and r.get("path")]
    top = _git(cwd, "rev-parse", "--show-toplevel")
    return re.sub(r"[^A-Za-z0-9]", "-", top), [(os.path.basename(top), top)]


def _live_sessions():
    """{session_id: bool alive} from Claude Code's sessions files (as the extension's state.ts)."""
    d = os.environ.get("CLAUDE_REVIEW_SESSIONS_DIR") or os.path.join(os.path.expanduser("~"), ".claude", "sessions")
    out = {}
    try:
        names = os.listdir(d)
    except OSError:
        return out
    for n in names:
        if not n.endswith(".json"):
            continue
        try:
            with open(os.path.join(d, n)) as f:
                s = json.load(f)
            pid = s["pid"]
            try:
                os.kill(pid, 0)
                alive = True
            except PermissionError:
                alive = True
            except OSError:
                alive = False
            out[s["sessionId"]] = out.get(s["sessionId"], False) or alive
        except (OSError, ValueError, KeyError, TypeError):
            pass
    return out


def _cleanup(d, sid):
    """Drop state left by crashed windows and sessions. Cheap: a few listdir and stat."""
    now = time.time()

    def entries(sub):
        p = os.path.join(d, sub)
        try:
            return [(n, os.path.join(p, n), now - os.stat(os.path.join(p, n)).st_mtime) for n in os.listdir(p)]
        except OSError:
            return []
    for _, p, age in entries("alive"):
        if age > DAY:
            _rm(p)
    running = [e for e in entries("running") if e[0] != sid]
    if running:
        sessions = _live_sessions()
        for n, p, age in running:
            if (n in sessions and not sessions[n]) or (n not in sessions and age > DAY):
                _rm(p)
    for n, p, age in entries("pending"):
        if n.startswith(".") and n.endswith(".tmp") and age > 3600:
            _rm(p)


def on_prompt(payload, home):
    global _deadline
    _deadline = time.monotonic() + DEADLINE
    try:
        _prompt(payload, home)
    finally:
        _deadline = None


def _prompt(payload, home):
    slug, repos = _resolve(payload, home)
    d = os.path.join(home, "review", slug)
    sid = payload.get("session_id")
    if sid:
        os.makedirs(os.path.join(d, "running"), exist_ok=True)
        open(os.path.join(d, "running", sid), "w").close()
    try:
        _cleanup(d, sid)
    except Exception:
        pass
    fresh = _alive_fresh(os.path.join(d, "alive"))

    def one(repo):
        name, path = repo
        if not os.path.isdir(path):
            return
        failed = os.path.join(d, "failed", name + ".json")
        moved = os.path.join(d, "moved", name + ".json")
        marker = None
        try:
            with open(failed) as f:
                previous = f.read()
        except OSError:
            previous = None
        try:
            # Left in place if Claude Code kills the hook before the end: the extension shows it.
            _write_json(failed, {"reason": INTERRUPTED, "at": _now()})
            head, base, parent = _heads(path)
            branch_moved = base is not None and head != parent
            pending = _pending(d, name)
            if fresh and pending and not branch_moved:
                if previous is None:
                    _rm(failed)
                else:
                    with open(failed, "w") as f:
                        f.write(previous)
                return  # unreviewed hunks remain: keep the old baseline
            if branch_moved and pending:
                marker = {"from": parent, "to": head, "at": _now()}
                _write_json(moved, marker)  # before the ref moves: the extension never misses it
            _, big = snapshot(path, head)
        except Exception as e:
            if marker:
                _rm(moved)
            _write_json(failed, {"reason": str(e), "at": _now()})
        else:
            if big:
                _write_json(failed, {"reason": "fichiers trop gros ignorés : " + ", ".join(big), "at": _now()})
            else:
                _rm(failed)

    with ThreadPoolExecutor(max_workers=max(1, len(repos))) as ex:
        list(ex.map(one, repos))


def on_stop(payload, home):
    slug, _ = _resolve(payload, home)
    sid = payload.get("session_id")
    if sid:
        try:
            os.unlink(os.path.join(home, "review", slug, "running", sid))
        except OSError:
            pass


def main():
    try:
        payload = json.load(sys.stdin)
        home = os.environ.get("WS_HOME") or os.path.join(os.path.expanduser("~"), ".claude-workspaces")
        {"prompt": on_prompt, "stop": on_stop}[sys.argv[1]](payload, home)
    except BaseException:
        pass
    sys.exit(0)


if __name__ == "__main__":
    main()
