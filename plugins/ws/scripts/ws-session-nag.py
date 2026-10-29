#!/usr/bin/env python3
"""ws-session-nag.py — SessionStart hook: what the user must do before anything else.

1. PRs assigned to them (as reviewer/merger) still open: merge them before opening new ones.
2. Their own open PRs without an assignee other than themselves: to assign before merging.
3. Their pending post-deploy actions: the repos' GitHub Action opens one `post-deploy`
   issue per merged PR with a "## Déploiement" section (one box per action and environment).

4. With the review watcher on (ws-review-watch.py): their PRs approved and green, ready to
   merge (`review_merge: "ask"`), the fix agents running, and reviews received that the
   watcher could not hand to an agent yet.
Also warms the client-mail cache of start-worktree's picker (ws_mail_cache.py, detached).

5. Client promises made by mail (ws-mail-promises.py, written by the `mail` skill) due
   today or overdue: the client should not have to chase us.

The PR lists are fetched again before being shown when the cache is older than 2 min
(three parallel gh calls, ~1.5 s, capped at 2.5 s; on timeout the cached lists are shown with
their age), so a PR merged a minute ago no longer shows. Post-deploy issues come from a cache
(~/.claude-workspaces/cache/session-nag.json) refreshed in a detached process when older than
10 min; the watcher's files are read as they are.
Event JSON on stdin; prints the hook JSON on stdout.
"""
import datetime, importlib.util, json, os, re, subprocess, sys, threading, time

CACHE = os.path.expanduser("~/.claude-workspaces/cache/session-nag.json")
WATCH = os.path.expanduser("~/.claude-workspaces/review-watch.json")
AUTOFIX = os.path.expanduser("~/.claude-workspaces/autofix")
TTL = 600
FRESH = 120
FIELDS = "number,title,url,author,assignees,repository,isDraft"


def git(path, *args):
    r = subprocess.run(["git", "-C", path, *args], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""


def slugs(cwd):
    top = git(cwd, "rev-parse", "--show-toplevel")
    dirs = [top] if top else [os.path.join(cwd, d) for d in sorted(os.listdir(cwd))
                              if os.path.exists(os.path.join(cwd, d, ".git"))]
    out = []
    for d in dirs:
        m = re.search(r"[:/]([^/:]+/[^/]+?)(?:\.git)?$", git(d, "remote", "get-url", "origin"))
        if m:
            out.append(m.group(1))
    return out


def load():
    try:
        return json.load(open(CACHE))
    except (OSError, ValueError):
        return {}


def gh_json(*args):
    try:
        r = subprocess.run(["gh", *args], capture_output=True, text=True)
    except OSError:  # gh not installed: nothing to show, never a traceback in the session
        return None
    return json.loads(r.stdout or "null") if r.returncode == 0 else None


def fetch_orgs(owners, timeout=None):
    """{"org:<owner>": {...}} from parallel gh calls; owners whose calls failed or timed out are left out."""
    got = {}

    def run(key, *args):
        got[key] = gh_json(*args)

    threads = [threading.Thread(target=run, args=("me", "api", "user"), daemon=True)] + [
        threading.Thread(target=run, args=((o, w), "search", "prs", "--owner", o, f"--{w}", "@me", "--state", "open",
                                           "--json", FIELDS), daemon=True)
        for o in owners for w in ("author", "assignee")]
    deadline = time.time() + (timeout or 600)
    for t in threads:
        t.start()
    for t in threads:
        t.join(max(0, deadline - time.time()))
    me = (got.get("me") or {}).get("login")
    return {"org:" + o: {"at": time.time(), "me": me, "mine": got[(o, "author")], "assigned": got[(o, "assignee")]}
            for o in owners if me and got.get((o, "author")) is not None and got.get((o, "assignee")) is not None}


def save(cache):
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    tmp = CACHE + f".tmp{os.getpid()}"
    json.dump(cache, open(tmp, "w"))
    os.replace(tmp, CACHE)


def refresh(repos):
    cache = load()
    cache.update(fetch_orgs(sorted({s.split("/")[0] for s in repos})))
    for slug in repos:
        r = subprocess.run(["gh", "issue", "list", "-R", slug, "--label", "post-deploy", "--assignee", "@me",
                            "--state", "open", "--json", "number,title,url,body"], capture_output=True, text=True)
        if r.returncode == 0:
            cache[slug] = {"at": time.time(), "issues": json.loads(r.stdout or "[]")}
    save(cache)


def pending_envs(body):
    return sorted({env for env in re.findall(r"^- \[ \] (staging|prod) —", body or "", re.M)}, reverse=True)


def alive(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except PermissionError:
        return True
    except (OSError, TypeError, ValueError):
        return False


def review_blocks():
    """What ws-review-watch.py left for the user (ignored when the watcher has not run for a day)."""
    try:
        watch = json.load(open(WATCH))
    except (OSError, ValueError):
        return []
    if time.time() - watch.get("at", 0) > 86400:
        return []
    prs = sorted(watch.get("prs", {}).values(), key=lambda p: (p["repo"], p["number"]))
    line = lambda p, extra="": f"#{p['number']} {p['title'][:60]} ({p['repo'].split('/')[1]}){extra} {p['url']}"
    ready = [line(p) + f" [head {p['head_sha']}]" for p in prs if p.get("action") == "ready"]
    waiting = [line(p, f" : {p['pending']}") for p in prs if p.get("pending")]
    running = []
    for name in sorted(os.listdir(AUTOFIX)) if os.path.isdir(AUTOFIX) else []:
        if name.endswith(".json"):
            try:
                j = json.load(open(os.path.join(AUTOFIX, name)))
            except (OSError, ValueError):
                continue
            if not j.get("finished") and alive(j.get("pid")):
                running.append(line(j, f", log {os.path.join(AUTOFIX, name[:-5])}.log"))
    blocks = []
    if ready:
        blocks.append(f"✅ {len(ready)} de tes PR approuvée(s) sur leur dernier commit et verte(s) : prête(s) à merger :")
        blocks += [f"  {l}" for l in ready[:6]]
    if running:
        blocks.append(f"🛠 {len(running)} correction(s) de relecture en cours (agent auto) :")
        blocks += [f"  {l}" for l in running[:6]]
    if waiting:
        blocks.append(f"👀 {len(waiting)} relecture(s) reçue(s) pas encore prise(s) en charge :")
        blocks += [f"  {l}" for l in waiting[:6]]
    return blocks


def mail_blocks():
    spec = importlib.util.spec_from_file_location(
        "mail_promises", os.path.join(os.path.dirname(os.path.abspath(__file__)), "ws-mail-promises.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    today = datetime.date.today().isoformat()
    due = [p for p in m.open_promises() if p["due"] <= today]
    if not due:
        return []
    late = lambda p: " (en retard)" if p["due"] < today else ""
    return [f"📬 {len(due)} promesse(s) faite(s) à des clients par mail, à tenir aujourd'hui :"] + [
        f"  {p['due']}{late(p)} {p['who']} : {p['promise'][:80]} ({p['subject'][:50]})" for p in due[:6]]


def main():
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import ws_mail_cache
    ws_mail_cache.warm(event.get("cwd") or os.getcwd())
    repos = slugs(event.get("cwd") or os.getcwd())
    watch_blocks = review_blocks()
    mail = mail_blocks()
    if not repos and not watch_blocks and not mail:
        return
    cache = load()
    owners = sorted({s.split("/")[0] for s in repos})
    if owners and any(time.time() - cache.get("org:" + o, {}).get("at", 0) > FRESH for o in owners):
        got = fetch_orgs(owners, timeout=2.5)  # what the user sees must be current: they act on it right away
        if got:
            cache.update(got)
            save(cache)
    keys = repos + ["org:" + o for o in owners]
    if repos and any(time.time() - cache.get(k, {}).get("at", 0) > TTL for k in keys) and os.fork() == 0:
        os.setsid()
        devnull = os.open(os.devnull, os.O_RDWR)
        for fd in (0, 1, 2):
            os.dup2(devnull, fd)
        try:
            refresh(repos)
        finally:
            os._exit(0)
    review, unassigned, lines = [], [], []
    for owner in sorted({s.split("/")[0] for s in repos}):
        org = cache.get("org:" + owner, {})
        me = org.get("me", "")
        for p in org.get("assigned", []):
            if p["author"]["login"] != me and not p.get("isDraft"):
                review.append(f"#{p['number']} {p['title'][:70]} ({p['repository']['name']}, de {p['author']['login']}) {p['url']}")
        for p in org.get("mine", []):
            if not p.get("isDraft") and not any(a["login"] != me for a in p.get("assignees", [])):
                unassigned.append(f"#{p['number']} {p['title'][:70]} ({p['repository']['name']}) {p['url']}")
    for s in repos:
        for i in cache.get(s, {}).get("issues", []):
            envs = pending_envs(i.get("body"))
            if envs:
                title = re.sub(r"^Déploiement : ", "", i["title"])
                lines.append(f"#{i['number']} {title} ({' + '.join(envs)}) {i['url']}")
    blocks = []
    age = max((time.time() - cache.get("org:" + o, {}).get("at", time.time()) for o in owners), default=0)
    stale = f" (état d'il y a {int(age // 3600)} h)" if age >= 3600 else f" (état d'il y a {int(age // 60)} min)" if age > FRESH else ""
    if review:
        blocks.append(f"🔀 {len(review)} PR assignée(s) à toi à relire et merger, avant d'en ouvrir une nouvelle{stale} :")
        blocks += [f"  {l}" for l in review[:6]]
    if unassigned:
        blocks.append(f"🙋 {len(unassigned)} de tes PR sans relecteur assigné : assigne-les avant de merger :")
        blocks += [f"  {l}" for l in unassigned[:6]]
    if lines:
        blocks.append(f"⚠️ {len(lines)} action(s) post-déploiement en attente pour toi :")
        blocks += [f"  {l}" for l in lines[:6]]
    blocks += watch_blocks + mail
    if not blocks:
        return
    msg = "\n".join(blocks)
    ready_hint = ("\nPour une PR « prête à merger », propose de la merger et ne le fais que quand l'utilisateur le dit :"
                  " `gh pr merge <n> -R <owner/repo> --merge --match-head-commit <head>` (merge commit, base develop)."
                  if any(b.startswith("✅") for b in watch_blocks) else "")
    print(json.dumps({
        "systemMessage": msg,
        "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": msg +
            "\nRappelle ces points en une ligne dans ta première réponse. Si l'utilisateur veut créer une PR alors qu'il a des PR"
            " assignées à merger, rappelle-lui de les merger d'abord." + ready_hint +
            ("\nPour une promesse client due, propose de préparer le mail de suivi avec le skill mail." if mail else "")},
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
