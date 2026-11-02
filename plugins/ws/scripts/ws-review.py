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
  pending/<repo>.json    {"count": n}, written by the extension
  alive/<window_id>      mtime refreshed every 10 s by the extension
  failed/<repo>.json     {"reason", "at"}, removed on the next successful snapshot
"""
import json, os, re, subprocess, sys, tempfile, time
from concurrent.futures import ThreadPoolExecutor

REF = "refs/worktree/claude-review/baseline"
ALIVE_MAX_AGE = 60  # seconds: an alive file older than this means the window is gone
_ENV = {"GIT_AUTHOR_NAME": "claude-review", "GIT_AUTHOR_EMAIL": "claude-review@localhost",
        "GIT_COMMITTER_NAME": "claude-review", "GIT_COMMITTER_EMAIL": "claude-review@localhost"}


def _git(cwd, *args, env=None):
    p = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True,
                       stdin=subprocess.DEVNULL, env={**os.environ, **(env or {})})
    if p.returncode:
        raise RuntimeError((p.stderr.strip() or f"git {args[0]} failed")[-500:])
    return p.stdout.strip()


def find_workspace(cwd, registry):
    """Workspace whose workspace_path is the longest prefix of cwd (as ws-finish-preflight.sh)."""
    ws = registry.get("workspaces", {})
    target, match, best = os.path.realpath(cwd), None, -1
    for w in (ws.values() if isinstance(ws, dict) else ws):
        wp = os.path.realpath(w.get("workspace_path") or "") if w.get("workspace_path") else ""
        if wp and (target == wp or target.startswith(wp + os.sep)) and len(wp) > best:
            match, best = w, len(wp)
    return match


def snapshot(repo_path):
    """Commit the whole working tree as a dangling commit, point REF at it, return the SHA."""
    top = _git(repo_path, "rev-parse", "--show-toplevel")
    real_index = _git(top, "rev-parse", "--path-format=absolute", "--git-path", "index")
    fd, tmp = tempfile.mkstemp(prefix="claude-review.")
    os.close(fd)
    try:
        # Seeded from the real index: its stat cache spares rehashing every tracked file.
        if os.path.exists(real_index):
            with open(real_index, "rb") as s, open(tmp, "wb") as d:
                d.write(s.read())
        else:
            os.unlink(tmp)  # no index yet: git wants a missing file, not an empty one
        env = {"GIT_INDEX_FILE": tmp}
        _git(top, "add", "-A", env=env)
        tree = _git(top, "write-tree", env=env)
    finally:
        for f in (tmp, tmp + ".lock"):
            if os.path.exists(f):
                os.unlink(f)
    sha = _git(top, "commit-tree", tree, "-m", "claude-review baseline", env=_ENV)
    _git(top, "update-ref", REF, sha)
    return sha


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
    except (OSError, ValueError, AttributeError):
        return False


def _resolve(payload, home):
    """-> (slug, [(repo_name, path)]) for the payload's cwd."""
    cwd = payload.get("cwd") or os.getcwd()
    try:
        with open(os.path.join(home, "registry.json")) as f:
            w = find_workspace(cwd, json.load(f))
    except (OSError, ValueError):
        w = None
    if w:
        return w["slug"], [(r["name"], r["path"]) for r in w.get("repos", [])]
    top = _git(cwd, "rev-parse", "--show-toplevel")
    return re.sub(r"[^A-Za-z0-9]", "-", top), [(os.path.basename(top), top)]


def on_prompt(payload, home):
    slug, repos = _resolve(payload, home)
    d = os.path.join(home, "review", slug)
    sid = payload.get("session_id")
    if sid:
        os.makedirs(os.path.join(d, "running"), exist_ok=True)
        open(os.path.join(d, "running", sid), "w").close()
    fresh = _alive_fresh(os.path.join(d, "alive"))

    def one(repo):
        name, path = repo
        if not os.path.isdir(path):
            return
        failed = os.path.join(d, "failed", name + ".json")
        if fresh and _pending(d, name):
            return  # unreviewed hunks remain: keep the old baseline
        try:
            snapshot(path)
        except Exception as e:
            os.makedirs(os.path.dirname(failed), exist_ok=True)
            with open(failed, "w") as f:
                json.dump({"reason": str(e), "at": time.strftime("%Y-%m-%dT%H:%M:%S%z")}, f)
        else:
            if os.path.exists(failed):
                os.unlink(failed)

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
