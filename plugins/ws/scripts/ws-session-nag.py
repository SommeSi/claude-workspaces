#!/usr/bin/env python3
"""ws-session-nag.py — SessionStart hook: what the user must do before anything else.

1. PRs assigned to them (as reviewer/merger) still open: merge them before opening new ones.
2. Their own open PRs without an assignee other than themselves: to assign before merging.
3. Their pending post-deploy actions: the repos' GitHub Action opens one `post-deploy`
   issue per merged PR with a "## Déploiement" section (one box per action and environment).

Zero latency: it reads a cache (~/.claude-workspaces/cache/session-nag.json) and, when
it is older than 10 min, refreshes it in a detached process for the next session.
Event JSON on stdin; prints the hook JSON on stdout.
"""
import json, os, re, subprocess, sys, time

CACHE = os.path.expanduser("~/.claude-workspaces/cache/session-nag.json")
TTL = 600


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
    r = subprocess.run(["gh", *args], capture_output=True, text=True)
    return json.loads(r.stdout or "null") if r.returncode == 0 else None


def refresh(repos):
    cache = load()
    me = (gh_json("api", "user") or {}).get("login")
    for owner in sorted({s.split("/")[0] for s in repos}):
        fields = "number,title,url,author,assignees,repository,isDraft"
        mine = gh_json("search", "prs", "--owner", owner, "--author", "@me", "--state", "open", "--json", fields)
        assigned = gh_json("search", "prs", "--owner", owner, "--assignee", "@me", "--state", "open", "--json", fields)
        if mine is not None and assigned is not None and me:
            cache["org:" + owner] = {"at": time.time(), "me": me, "mine": mine, "assigned": assigned}
    for slug in repos:
        r = subprocess.run(["gh", "issue", "list", "-R", slug, "--label", "post-deploy", "--assignee", "@me",
                            "--state", "open", "--json", "number,title,url,body"], capture_output=True, text=True)
        if r.returncode == 0:
            cache[slug] = {"at": time.time(), "issues": json.loads(r.stdout or "[]")}
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    tmp = CACHE + ".tmp"
    json.dump(cache, open(tmp, "w"))
    os.replace(tmp, CACHE)


def pending_envs(body):
    return sorted({env for env in re.findall(r"^- \[ \] (staging|prod) —", body or "", re.M)}, reverse=True)


def main():
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return
    repos = slugs(event.get("cwd") or os.getcwd())
    if not repos:
        return
    cache = load()
    keys = repos + ["org:" + s.split("/")[0] for s in repos]
    if any(time.time() - cache.get(k, {}).get("at", 0) > TTL for k in keys) and os.fork() == 0:
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
    if review:
        blocks.append(f"🔀 {len(review)} PR assignée(s) à toi à relire et merger, avant d'en ouvrir une nouvelle :")
        blocks += [f"  {l}" for l in review[:6]]
    if unassigned:
        blocks.append(f"🙋 {len(unassigned)} de tes PR sans relecteur assigné : assigne-les avant de merger :")
        blocks += [f"  {l}" for l in unassigned[:6]]
    if lines:
        blocks.append(f"⚠️ {len(lines)} action(s) post-déploiement en attente pour toi :")
        blocks += [f"  {l}" for l in lines[:6]]
    if not blocks:
        return
    msg = "\n".join(blocks)
    print(json.dumps({
        "systemMessage": msg,
        "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": msg +
            "\nRappelle ces points en une ligne dans ta première réponse. Si l'utilisateur veut créer une PR alors qu'il a des PR"
            " assignées à merger, rappelle-lui de les merger d'abord."},
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
