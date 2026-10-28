#!/usr/bin/env python3
"""ws_mail_cache.py — client mails for start-worktree's picker, without a Gmail turn.

  ws_mail_cache.py refresh <dir>   fetch now (~20 s): headless Haiku + the claude.ai Gmail connector
  ws_mail_cache.py read <dir>      cached mails as JSON; starts a detached refresh when older than 15 min

<dir> is any directory inside the project (the `mail.query` of its .claude-workspaces.json).
Gmail is only reachable through the connector, i.e. through a model: a headless Haiku makes the
one search_threads call and its raw tool result is parsed here, so nothing gets lost in a summary.
Warmed by ws-session-nag.py at session start and read by ws-preflight.sh. The headless run sets
WS_MAIL_REFRESH so its own SessionStart hook does not start another refresh.
Cache per query: ~/.claude-workspaces/cache/mails-<hash>.json (local, per user).
"""
import hashlib, json, os, subprocess, sys, time

TTL = 900
CLAUDE = os.path.expanduser("~/.local/bin/claude")


def query(start):
    d = os.path.abspath(start)
    while d != "/":
        p = os.path.join(d, ".claude-workspaces.json")
        if os.path.isfile(p):
            try:
                return (json.load(open(p)).get("mail") or {}).get("query")
            except ValueError:
                return None
        d = os.path.dirname(d)
    return None


def path(q):
    return os.path.expanduser(f"~/.claude-workspaces/cache/mails-{hashlib.sha1(q.encode()).hexdigest()[:10]}.json")


def parse(stream):
    """Threads of the search_threads tool result in a stream-json transcript."""
    for line in stream.splitlines():
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if e.get("type") != "user":
            continue
        for b in e["message"].get("content", []):
            if isinstance(b, dict) and b.get("type") == "tool_result":
                c = b["content"]  # the first result is usually the ToolSearch that loads the deferred Gmail tool
                text = c if isinstance(c, str) else "".join(x.get("text", "") for x in c if isinstance(x, dict))
                try:
                    data = json.loads(text)
                except ValueError:
                    continue
                if isinstance(data, dict) and "threads" in data:
                    return data["threads"]
    return None


def slim(threads):
    out = []
    for t in threads:
        m = (t.get("messages") or [{}])[-1]
        sender = m.get("sender", "")
        out.append({"thread": t["id"], "message_id": m.get("id"), "subject": m.get("subject", ""),
                    "sender": sender, "domain": sender.split("@")[-1],
                    # ponytail: the search result carries no date; Gmail ids hold the epoch ms in their top bits
                    "date": time.strftime("%Y-%m-%d", time.localtime((int(m["id"], 16) >> 20) / 1000)) if m.get("id") else ""})
    return out


def refresh(q):
    lock = path(q) + ".lock"
    if os.path.exists(lock) and time.time() - os.path.getmtime(lock) < 180:
        return
    os.makedirs(os.path.dirname(lock), exist_ok=True)
    open(lock, "w").close()
    try:
        prompt = f'Call mcp__claude_ai_Gmail__search_threads once with {json.dumps({"query": q, "pageSize": 10})}, then reply "ok".'
        r = subprocess.run([CLAUDE if os.path.exists(CLAUDE) else "claude", "-p", "--model", "haiku", "--no-session-persistence",
                            "--output-format", "stream-json", "--verbose", "--allowedTools", "mcp__claude_ai_Gmail__search_threads"],
                           input=prompt, capture_output=True, text=True, timeout=180,
                           env=os.environ | {"WS_MAIL_REFRESH": "1"})
        threads = parse(r.stdout)
        if threads is None:
            return
        tmp = path(q) + ".tmp"
        json.dump({"at": time.time(), "query": q, "threads": slim(threads)}, open(tmp, "w"), ensure_ascii=False)
        os.replace(tmp, path(q))
    finally:
        if os.path.exists(lock):
            os.unlink(lock)


def warm(start):
    """Detached refresh when the cache is missing or stale; never blocks the caller."""
    q = query(start)
    if not q or os.environ.get("WS_MAIL_REFRESH"):
        return
    try:
        fresh = time.time() - os.path.getmtime(path(q)) < TTL
    except OSError:
        fresh = False
    if not fresh:
        subprocess.Popen([sys.executable, os.path.abspath(__file__), "refresh", start], start_new_session=True,
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def cached(start):
    """{"age_min", "threads"} from the cache (None without a mail config), warming it if stale."""
    q = query(start)
    if not q:
        return None
    warm(start)
    try:
        c = json.load(open(path(q)))
    except (OSError, ValueError):
        return {"refreshing": True}
    return {"age_min": int((time.time() - c["at"]) / 60), "threads": c["threads"]}


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "refresh":
        q = query(sys.argv[2])
        if q:
            refresh(q)
    elif len(sys.argv) == 3 and sys.argv[1] == "read":
        print(json.dumps(cached(sys.argv[2]), ensure_ascii=False))
    elif os.environ.get("WS_MAIL_CACHE_SELFTEST"):
        raw = json.dumps({"type": "user", "message": {"content": [{"type": "tool_result", "content": [{"type": "text", "text":
              json.dumps({"threads": [{"id": "t1", "messages": [{"id": "1a182bddd809bfec", "sender": "k@humtac.fr", "subject": "S"}]}]})}]}]}})
        search = json.dumps({"type": "user", "message": {"content": [{"type": "tool_result", "content": [{"type": "tool_reference"}]}]}})
        got = slim(parse("noise\n" + search + "\n" + raw))
        assert got[0]["domain"] == "humtac.fr" and got[0]["date"] == "2026-10-28" and got[0]["subject"] == "S", got
        assert parse("nothing") is None
        print("ok")
    else:
        sys.exit(__doc__)
