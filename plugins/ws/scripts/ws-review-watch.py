#!/usr/bin/env python3
"""ws-review-watch.py — review → correction → merge loop, on the PR author's Mac (opt-in).

  run [--dry-run]   launchd, every 5 min. For your open, non-draft PRs whose base is
                    `develop` (label `no-autofix` = ignored), it detects new reviews and
                    comments from others plus unresolved threads, notifies you, then:
                      - approved by the assignee ON THE CURRENT HEAD COMMIT, no unresolved
                        thread, no failing or pending check → `review_merge: "auto"` merges
                        (merge commit); `"ask"` (default) only notifies « prête à merger »;
                      - remarks to handle → starts a detached headless `claude -p` in the
                        PR's worktree: it checks each remark, fixes the valid ones, runs the
                        tests, pushes, answers in the threads and re-requests review. It
                        NEVER merges;
                      - approved but checks pending → waits for the next run.
                    --dry-run prints the decision per PR and changes nothing.
  install           Write and load the launchd agent (every 5 min).
  uninstall         Unload and remove it.

Opt-in per user, in ~/.claude-workspaces/config.json: `"review_autofix": true` (run exits
silently otherwise), `"review_merge": "ask" | "auto"`. State: ~/.claude-workspaces/review-watch.json
(read by ws-session-nag.py); fix agents: ~/.claude-workspaces/autofix/<repo>-<n>.{json,log}.
"""
import fcntl, json, os, plistlib, re, shutil, subprocess, sys, time
from datetime import datetime
from urllib.parse import urlparse

HOME = os.path.expanduser("~")
BASE = os.path.join(HOME, ".claude-workspaces")
STATE = os.path.join(BASE, "review-watch.json")
CONFIG = os.path.join(BASE, "config.json")
REGISTRY = os.path.join(BASE, "registry.json")
AUTOFIX = os.path.join(BASE, "autofix")
LOG = os.path.join(BASE, "review-watch.log")
LABEL = "com.claude-workspaces.review-watch"
PLIST = os.path.join(HOME, "Library", "LaunchAgents", LABEL + ".plist")
BASE_BRANCH, SKIP_LABEL, DEFAULT_ORG = "develop", "no-autofix", "SommeSi"
MAX_AGENTS = 2          # fix agents running at once; the others wait for a later run
AGENT_TIMEOUT = 3600
TOOLS = ["Read", "Edit", "Write", "Grep", "Glob", "Bash(git:*)", "Bash(gh:*)", "Bash(bundle exec rspec:*)",
         "Bash(bin/rails:*)", "Bash(bun:*)", "Bash(npx:*)"]
STATE_FR = {"APPROVED": "approuvée", "CHANGES_REQUESTED": "changements demandés",
            "COMMENTED": "commentée", "DISMISSED": "relecture annulée"}
LOCK_FD = None

QUERY = """query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){pullRequest(number:$n){
 number title url isDraft baseRefName headRefName headRefOid
 assignees(first:10){nodes{login}} labels(first:20){nodes{name}}
 reviews(last:50){nodes{databaseId state body submittedAt author{login __typename} commit{oid}}}
 reviewThreads(first:100){nodes{isResolved comments(first:50){nodes{databaseId author{login __typename}}}}}
 comments(last:50){nodes{databaseId body author{login __typename}}}}}}"""

PROMPT = """You are fixing the review feedback on pull request #{n} of {repo} (branch `{head}`, base `develop`), checked out in the current directory. You run unattended: nobody will answer questions, so decide and act.

1. Sync: `git fetch origin`, check you are on `{head}` (`git branch --show-current`), then `git pull --ff-only origin {head}`. If that fails, stop and explain why. Never touch uncommitted changes you did not make.
2. Read all the feedback:
   - `gh pr view {n} -R {repo} --comments` and `gh api repos/{repo}/pulls/{n}/reviews`;
   - the review threads (work on the unresolved ones): `gh api graphql -f query='query{{repository(owner:"{owner}",name:"{name}"){{pullRequest(number:{n}){{reviewThreads(first:100){{nodes{{id isResolved path line comments(first:50){{nodes{{databaseId author{{login}} body}}}}}}}}}}}}}}'`;
   - `gh pr diff {n} -R {repo}` for context.
3. For each remark, first check against the code that it is correct: reviewers and Codex can be wrong. Fix the valid ones with the smallest change, following the repo's conventions and its .claude/rules. No refactoring beyond the remarks.
4. Run the specs/tests covering what you changed and make them pass. {tests}
5. Stage only the files you changed (`git add <file>…`, never `-A`), commit `fix(review): <short summary in English>`, then `git push origin HEAD:{head}`. Never force-push, never push to another branch.
6. Answer in French in every unresolved thread, replying to its first comment: `gh api -X POST repos/{repo}/pulls/{n}/comments/<databaseId>/replies -f body="Corrigé dans <short sha>"` or `-f body="Pas d'accord : <raison>"`. Then resolve each thread you fixed: `gh api graphql -f query='mutation{{resolveReviewThread(input:{{threadId:"<thread id>"}}){{thread{{isResolved}}}}}}'`. Leave the contested threads unresolved for the reviewer. Remarks made in a review body or a PR comment (outside threads) get one French PR comment answering point by point (`gh pr comment {n} -R {repo} --body-file -`).
7. {rerequest}
Never merge, approve or close the PR, never push to develop or main.

Your final message is sent to the PR author as a notification: 1-2 lines in French — what you fixed, what you contested, tests OK/KO, commit sha."""

RAILS_TESTS = ("This is the Rails back: isolate the test database exactly as the section « SommeSi — base de test privée "
               "(back) » of ~/.claude/CLAUDE.md describes (read it). Its variables are already exported in your environment "
               "with T={tag} (RAILS_ENV, DATABASE_URL, CACHE_DATABASE_URL, QUEUE_DATABASE_URL, CABLE_DATABASE_URL), so do not "
               "export anything: run its verification command, and only once it prints four database names containing _{tag} "
               "run `bin/rails db:create db:schema:load`; then `bundle exec rspec <spec files>`.")
RAILS_TESTS_GENERIC = ("This is a Rails app: never run specs on the shared test database; isolate it as your instructions "
                       "(~/.claude/CLAUDE.md) say, then `bundle exec rspec <spec files>`.")
JS_TESTS = ("Run `bun install` if node_modules is missing, then the tests of what you changed with the scripts of "
            "package.json (`bun run …` / `npx …`), plus the type check and the lint if they exist.")


# ---------- helpers ----------

def sh(*cmd, cwd=None, timeout=120, **kw):
    try:
        return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout, **kw)
    except (OSError, subprocess.TimeoutExpired) as e:
        return subprocess.CompletedProcess(cmd, 1, "", str(e))


def git(path, *args):
    r = sh("git", "-C", path, *args)
    return r.stdout.strip() if r.returncode == 0 else ""


def gh_json(*args):
    r = sh("gh", *args)
    try:
        return json.loads(r.stdout) if r.returncode == 0 and r.stdout.strip() else None
    except ValueError:
        return None


def read_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = f"{path}.{os.getpid()}.tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=1, ensure_ascii=False)
    os.replace(tmp, path)


def now():
    return datetime.now().isoformat(timespec="seconds")


def say(msg):  # run's stdout goes to review-watch.log under launchd
    print(f"{datetime.now():%Y-%m-%d %H:%M:%S} {msg}", flush=True)


def log(msg):  # detached workers have no stdout
    os.makedirs(BASE, exist_ok=True)
    with open(LOG, "a") as f:
        f.write(f"{datetime.now():%Y-%m-%d %H:%M:%S} {msg}\n")


def notify(title, msg, url=None, group=None):
    tn = shutil.which("terminal-notifier") or next(
        (p for p in ("/opt/homebrew/bin/terminal-notifier", "/usr/local/bin/terminal-notifier") if os.path.exists(p)), None)
    if tn:
        cmd = [tn, "-title", title, "-message", msg, "-sound", "Glass", "-group", group or title]
        sh(*(cmd + (["-open", url] if url else [])), timeout=15)
    else:  # argv, not string interpolation: titles/messages may hold quotes
        sh("osascript", "-e", "on run argv", "-e", "display notification (item 2 of argv) with title (item 1 of argv)",
           "-e", "end run", title, msg, timeout=15)


def claude_bin():
    return shutil.which("claude") or next(
        (p for p in (f"{HOME}/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude")
         if os.path.exists(p)), None)


def alive(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except PermissionError:
        return True
    except (OSError, TypeError, ValueError):
        return False


def short(login):
    return "Codex" if "codex" in login.lower() else login.replace("[bot]", "")


def has_text(body):
    return bool(re.sub(r"<!--.*?-->", "", body or "", flags=re.S).strip())


# ---------- decision (pure, unit-tested) ----------

def skip_reason(pr):
    if pr.get("draft"):
        return "brouillon"
    if SKIP_LABEL in pr.get("labels", []):
        return f"label {SKIP_LABEL}"
    if pr.get("base") != BASE_BRANCH:
        return f"base {pr.get('base')} ≠ {BASE_BRANCH}"
    return None


def activity(pr, me, since):
    """Reviews / thread comments / PR comments by others with an id above `since`.
    Bot PR comments are ignored (Codex's is a status summary edited in place; its remarks come as threads)."""
    me, since = me.lower(), since or {}
    return {
        "reviews": [r for r in pr["reviews"] if r["id"] > since.get("review", 0) and r["by"].lower() != me
                    and r["state"] != "PENDING"],
        "comments": [c for t in pr["threads"] for c in t["comments"]
                     if c["id"] > since.get("comment", 0) and c["by"].lower() != me],
        "issue": [c for c in pr["comments"] if c["id"] > since.get("issue", 0) and c["by"].lower() != me and not c["bot"]],
    }


def decide(pr, me, mode="ask", new=None, running=False, checks=None):
    """→ (action, reason). action: skip | running | merge | ready | wait | blocked | stale | fix | waiting | none.
    `new` = activity() since the watcher last handled the PR; `checks` = "pass" | "pending" | "fail" | "none"
    or a zero-arg callable returning it (only called when the PR is otherwise mergeable)."""
    why = skip_reason(pr)
    if why:
        return "skip", why
    if running:
        return "running", "correction auto en cours"
    me_l, new = me.lower(), new or {}
    latest = {}  # latest decisive review per human reviewer
    for r in sorted(pr["reviews"], key=lambda r: r.get("at") or ""):
        if not r["bot"] and r["by"].lower() != me_l and r["state"] in ("APPROVED", "CHANGES_REQUESTED", "DISMISSED"):
            latest[r["by"]] = r
    pool = {a for a in pr.get("assignees", []) if a.lower() != me_l} or set(latest)
    approvals = [r for b, r in latest.items() if r["state"] == "APPROVED" and b in pool]
    changes = [r for r in latest.values() if r["state"] == "CHANGES_REQUESTED"]
    unresolved = [t for t in pr["threads"] if not t["resolved"]]
    unanswered = [t for t in unresolved if t["comments"] and t["comments"][-1]["by"].lower() != me_l]
    fresh_remarks = any(r["state"] == "CHANGES_REQUESTED" or (r["state"] == "COMMENTED" and not r["bot"] and has_text(r["body"]))
                        for r in new.get("reviews", [])) or any(has_text(c.get("body")) for c in new.get("issue", []))
    if approvals and not changes and not unresolved and not fresh_remarks:
        on_head = [r for r in approvals if r.get("commit") == pr["head_sha"]]
        if not on_head:
            return "stale", "approuvée sur un ancien commit : il faut une approbation du dernier commit"
        state = checks() if callable(checks) else checks
        if state == "fail":
            return "blocked", "approuvée mais check(s) en échec"
        if state == "pending":
            return "wait", "approuvée, checks en cours"
        by = ", ".join(sorted(r["by"] for r in on_head))
        if mode == "auto":
            return "merge", f"approuvée par {by} sur {pr['head_sha'][:7]}, checks verts"
        return "ready", f"approuvée par {by} sur {pr['head_sha'][:7]} et verte : prête à merger"
    if any(new.values()) and (unanswered or fresh_remarks):
        n = len(unanswered)
        return "fix", (f"{n} fil(s) non résolu(s)" if n else "remarques") + (", changements demandés" if changes else "")
    if unresolved or changes:
        return "waiting", f"en attente du relecteur ({len(unresolved)} fil(s) non résolu(s))"
    return "none", "pas de relecture à traiter"


# ---------- GitHub ----------

def author(a):
    a = a or {}
    login = a.get("login") or "ghost"
    return {"by": login, "bot": a.get("__typename") == "Bot" or login.endswith("[bot]")}


def fetch(repo, number):
    owner, name = repo.split("/")
    d = gh_json("api", "graphql", "-f", f"query={QUERY}", "-f", f"o={owner}", "-f", f"r={name}", "-F", f"n={number}")
    p = (((d or {}).get("data") or {}).get("repository") or {}).get("pullRequest")
    if not p:
        return None
    return {
        "repo": repo, "number": p["number"], "title": p["title"], "url": p["url"], "draft": p["isDraft"],
        "base": p["baseRefName"], "head": p["headRefName"], "head_sha": p["headRefOid"],
        "assignees": [a["login"] for a in p["assignees"]["nodes"]],
        "labels": [l["name"] for l in p["labels"]["nodes"]],
        "reviews": [dict(author(r["author"]), id=r["databaseId"], state=r["state"], body=r["body"] or "",
                         at=r["submittedAt"] or "", commit=(r.get("commit") or {}).get("oid"))
                    for r in p["reviews"]["nodes"]],
        "threads": [{"resolved": t["isResolved"],
                     "comments": [dict(author(c["author"]), id=c["databaseId"]) for c in t["comments"]["nodes"]]}
                    for t in p["reviewThreads"]["nodes"]],
        "comments": [dict(author(c["author"]), id=c["databaseId"], body=c["body"] or "") for c in p["comments"]["nodes"]],
    }


def checks(repo, number):
    r = sh("gh", "pr", "checks", str(number), "-R", repo, "--json", "name,bucket")  # rc 8 = pending, still JSON
    try:
        buckets = {c["bucket"] for c in json.loads(r.stdout)}
    except ValueError:
        return "none" if "no checks" in (r.stderr or "").lower() else "pending"  # gh error → wait, never merge
    if buckets & {"fail", "cancel"}:
        return "fail"
    return "pending" if "pending" in buckets else "pass"


def local_repos(state):
    """canonical slug (lower) → main checkout, and the orgs of the registry's project roots."""
    canon = state.setdefault("slugs", {})  # origin slug → current GitHub name (repos get renamed)
    checkouts, orgs = {}, set()
    for ws in read_json(REGISTRY, {}).get("workspaces", {}).values():
        root = ws.get("project_root")
        for d in [root] + [r.get("path") for r in ws.get("repos", [])]:
            if not d or not os.path.isdir(d):
                continue
            m = re.search(r"[:/]([^/:]+/[^/]+?)(?:\.git)?$", git(d, "remote", "get-url", "origin"))
            if not m:
                continue
            slug = m.group(1)
            if d == root:
                orgs.add(slug.split("/")[0])
            if slug not in canon:
                full = sh("gh", "api", f"repos/{slug}", "--jq", ".full_name").stdout.strip()
                if not full:
                    continue
                canon[slug] = full
            common = git(d, "rev-parse", "--path-format=absolute", "--git-common-dir")
            checkouts.setdefault(canon[slug].lower(), os.path.dirname(common) if common else d)
    return checkouts, sorted(orgs) or [DEFAULT_ORG]


def agent_base(repo, number):
    return os.path.join(AUTOFIX, f"{repo.split('/')[1]}-{number}")


def agent_running(repo, number):
    j = read_json(agent_base(repo, number) + ".json", {})
    return bool(j) and not j.get("finished") and alive(j.get("pid"))


def summary(pr, act):
    revs = sorted(act["reviews"], key=lambda r: r.get("at") or "")
    n = len(act["comments"]) + len(act["issue"])
    people = sorted({short(x["by"]) for x in revs + act["comments"] + act["issue"]})
    decisive = [r for r in revs if r["state"] in ("APPROVED", "CHANGES_REQUESTED")]
    parts = [STATE_FR.get((decisive or revs)[-1]["state"], "relue")] if revs else []
    if n:
        parts.append(f"{n} commentaire{'s' if n > 1 else ''}")
    return f"#{pr['number']} {'relue' if revs else 'commentée'} par {', '.join(people)} : {', '.join(parts)}"


# ---------- fix agent ----------

def detach(fn, *args):
    """Run fn in a fully detached grandchild (double fork + setsid), like ws-knowledge.py."""
    pid = os.fork()
    if pid:
        os.waitpid(pid, 0)
        return
    os.setsid()
    if os.fork():
        os._exit(0)
    if LOCK_FD is not None:  # do not keep the run lock for the agent's lifetime
        os.close(LOCK_FD)
    devnull = os.open(os.devnull, os.O_RDWR)
    for fd in (0, 1, 2):
        os.dup2(devnull, fd)
    try:
        fn(*args)
    except Exception as e:  # never surface anything
        log(f"autofix error: {e!r}")
    os._exit(0)


def checkout_for(job):
    """The PR's local worktree (any worktree of the main checkout on the head branch), else a new one."""
    main, head, cur, found = job["main"], job["head"], None, []
    for line in git(main, "worktree", "list", "--porcelain").splitlines():
        if line.startswith("worktree "):
            cur = line[len("worktree "):]
        elif line == f"branch refs/heads/{head}" and cur and os.path.isdir(cur):
            found.append(cur)
    if found:
        return sorted(found, key=lambda p: p == main)[0]  # a workspace worktree before the main checkout
    dest = agent_base(job["repo"], job["number"])
    git(main, "worktree", "prune")
    if sh("git", "-C", main, "fetch", "origin", head, timeout=300).returncode:
        raise RuntimeError(f"git fetch origin {head} a échoué")
    r = sh("git", "-C", main, "worktree", "add", "--detach", dest, f"origin/{head}")
    if r.returncode:
        raise RuntimeError("git worktree add : " + r.stderr.strip()[:200])
    if git(dest, "rev-parse", "--verify", "--quiet", f"refs/heads/{head}"):
        steps = [["switch", head], ["merge", "--ff-only", f"origin/{head}"]]
    else:
        steps = [["switch", "-c", head, "--track", f"origin/{head}"]]
    for s in steps:
        r = sh("git", "-C", dest, *s)
        if r.returncode:
            raise RuntimeError(f"git {s[0]} : {r.stderr.strip()[:200]}")
    return dest


def test_setup(cwd, number):
    """Test instructions for the prompt + env (private test DB for the Rails back)."""
    if os.path.exists(os.path.join(cwd, "bin", "rails")):
        try:
            text = open(os.path.join(HOME, ".claude", "CLAUDE.md")).read()
        except OSError:
            text = ""
        m = re.search(r"B=(postgres(?:ql)?://\S+?)\$T", text)
        if not m:
            return RAILS_TESTS_GENERIC, {}
        tag = f"af_{number}"
        b = m.group(1) + tag
        env = {"RAILS_ENV": "test", "DATABASE_URL": b}
        env.update({f"{k}_DATABASE_URL": f"{b}_{k.lower()}" for k in ("CACHE", "QUEUE", "CABLE")})
        return RAILS_TESTS.format(tag=tag), env
    if os.path.exists(os.path.join(cwd, "package.json")):
        return JS_TESTS, {}
    return "Use the project's own test command.", {}


def drop_test_dbs(env):
    psql = shutil.which("psql")
    if not (psql and env.get("DATABASE_URL")):
        return
    u = urlparse(env["DATABASE_URL"])
    names = [urlparse(env[k]).path.lstrip("/") for k in ("DATABASE_URL", "CACHE_DATABASE_URL", "QUEUE_DATABASE_URL",
                                                         "CABLE_DATABASE_URL")]
    sh(psql, "-d", u._replace(path="/postgres").geturl(), *[a for n in names for a in ("-c", f'DROP DATABASE IF EXISTS "{n}"')])


def autofix(job):
    base, n = agent_base(job["repo"], job["number"]), job["number"]
    status = {k: job[k] for k in ("repo", "number", "title", "url", "head")}
    status.update(pid=os.getpid(), started=now())
    write_json(base + ".json", status)
    ok, result, env = False, "", {}
    try:
        cwd = checkout_for(job)
        status["cwd"] = cwd
        write_json(base + ".json", status)
        exe = claude_bin()
        if not exe:
            raise RuntimeError("CLI claude introuvable")
        tests, env = test_setup(cwd, n)
        owner, name = job["repo"].split("/")
        prompt = PROMPT.format(n=n, repo=job["repo"], owner=owner, name=name, head=job["head"], tests=tests,
                               rerequest=job["rerequest"])
        r = sh(exe, "-p", "--permission-mode", "acceptEdits", "--allowedTools", *TOOLS, "--output-format", "json",
               cwd=cwd, timeout=AGENT_TIMEOUT, input=prompt,
               env=dict(os.environ, WS_KNOWLEDGE_DISABLE="1", **env))
        with open(base + ".log", "a") as f:
            f.write(f"=== {now()} #{n} {job['repo']} in {cwd} (rc={r.returncode})\n{r.stdout}\n{r.stderr}\n")
        m = re.search(r"\{.*\}", r.stdout or "", re.S)
        try:
            data = json.loads(m.group(0)) if m else {}
        except ValueError:
            data = {}
        ok = bool(data) and not data.get("is_error") and r.returncode == 0
        result = (data.get("result") or r.stderr or r.stdout or "").strip()
    except Exception as e:
        result = str(e)
    finally:
        status.update(finished=now(), ok=ok, result=result[:2000])
        write_json(base + ".json", status)
        drop_test_dbs(env)
    log(f"autofix #{n} {job['repo']}: {'ok' if ok else 'ko'} {result[:200]!r}")
    msg = re.sub(r"\s+", " ", result)[:230] or "terminée"
    notify(f"#{n} correction auto" + ("" if ok else " : échec"), msg, job["url"], f"ws-review-{job['repo']}#{n}")


def rerequest_step(pr, me):
    me_l = me.lower()
    people = sorted({r["by"] for r in pr["reviews"] if not r["bot"] and r["by"].lower() != me_l}
                    or {a for a in pr["assignees"] if a.lower() != me_l})
    if not people:
        return "No human reviewer to re-request: skip this step."
    args = " ".join(f"-f 'reviewers[]={p}'" for p in people)
    return f"Re-request review: `gh api -X POST repos/{pr['repo']}/pulls/{pr['number']}/requested_reviewers {args}`."


# ---------- run ----------

def run(dry):
    global LOCK_FD
    cfg = read_json(CONFIG, {})
    if not cfg.get("review_autofix") and not (dry and os.environ.get("WS_REVIEW_WATCH_FORCE")):
        return
    mode = "auto" if cfg.get("review_merge") == "auto" else "ask"
    if not dry:
        os.makedirs(BASE, exist_ok=True)
        LOCK_FD = os.open(os.path.join(BASE, "review-watch.lock"), os.O_RDWR | os.O_CREAT)
        try:
            fcntl.flock(LOCK_FD, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            return  # a run is already going
    state = read_json(STATE, {})
    first = not os.path.exists(STATE)
    me = state.get("me") or (gh_json("api", "user") or {}).get("login")
    if not me:
        return say("gh not authenticated")
    state["me"] = me
    checkouts, orgs = local_repos(state)
    found = []
    for org in orgs:
        res = gh_json("search", "prs", "--owner", org, "--author", "@me", "--state", "open", "--limit", "100",
                      "--json", "number,title,url,repository,isDraft,labels")
        if res is None:
            return say(f"gh search prs failed for {org}")  # keep the state as is
        found += res
    old, prs = state.get("prs", {}), {}
    agents = sum(1 for k, e in old.items() if agent_running(e["repo"], e["number"]))
    launched = []
    if dry:
        say(f"dry-run — me={me} orgs={','.join(orgs)} mode={mode} checkouts={sorted(checkouts)}")
    for s in sorted(found, key=lambda s: (s["repository"]["nameWithOwner"], s["number"])):
        repo, n = s["repository"]["nameWithOwner"], s["number"]
        key = f"{repo}#{n}"
        why = skip_reason({"draft": s["isDraft"], "labels": [l["name"] for l in s["labels"]], "base": BASE_BRANCH})
        pr = None if why else fetch(repo, n)
        if not why and not pr:
            say(f"{key}: fetch failed")
            if key in old:
                prs[key] = old[key]
            continue
        if pr:
            why = skip_reason(pr)
        if why:
            if dry:
                say(f"{key:<32} skip     {why}")
            continue
        entry = dict(old.get(key) or {}, seen=dict((old.get(key) or {}).get("seen", {})),
                     handled=dict((old.get(key) or {}).get("handled", {})))
        act = activity(pr, me, entry["handled"])
        fresh = activity(pr, me, entry["seen"])
        running = agent_running(repo, n)
        action, reason = decide(pr, me, mode, new=act, running=running, checks=lambda: checks(repo, n))
        text = summary(pr, fresh) if any(fresh.values()) else ""
        if dry:
            say(f"{key:<32} {action:<8} {reason}" + (f"  [notif: {text}]" if text else ""))
            continue
        outcome, pending, handled = None, None, True
        if action == "merge":
            r = sh("gh", "pr", "merge", str(n), "-R", repo, "--merge", "--match-head-commit", pr["head_sha"])
            if r.returncode == 0:
                action, outcome = "merged", f"mergée dans {BASE_BRANCH}"
            else:
                action, outcome = "error", "merge impossible"
                pending = "merge impossible : " + (r.stderr or r.stdout).strip()[:150]
        elif action == "ready":
            if entry.get("ready_sha") != pr["head_sha"]:
                outcome = "approuvée et verte : prête à merger"
            entry["ready_sha"] = pr["head_sha"]
        elif action == "fix":
            main = checkouts.get(repo.lower())
            if not main:
                handled, pending = False, f"correction auto impossible : pas de checkout local de {repo}"
                outcome = "correction auto impossible (pas de checkout local)"
            elif agents >= MAX_AGENTS:
                handled, pending = False, "correction auto en file d'attente"
            else:
                detach(autofix, {"repo": repo, "number": n, "title": pr["title"], "url": pr["url"], "head": pr["head"],
                                 "main": main, "rerequest": rerequest_step(pr, me)})
                agents += 1
                launched.append(key)
                outcome = "correction auto lancée"
        elif action == "blocked":
            pending = reason
        if action != "ready":
            entry.pop("ready_sha", None)
        say(f"{key:<32} {action:<8} {reason}" + (f" → {outcome}" if outcome else ""))
        if not first and (text or outcome):
            msg = text + (" → " if text and outcome else "") + (outcome or "")
            notify(repo.split("/")[1], msg if text else f"#{n} {msg}", pr["url"], f"ws-review-{key}")
        ids = {"review": max([r["id"] for r in pr["reviews"]] + [entry["seen"].get("review", 0)]),
               "comment": max([c["id"] for t in pr["threads"] for c in t["comments"]] + [entry["seen"].get("comment", 0)]),
               "issue": max([c["id"] for c in pr["comments"]] + [entry["seen"].get("issue", 0)])}
        entry.update(repo=repo, number=n, title=pr["title"], url=pr["url"], head_sha=pr["head_sha"], action=action,
                     reason=reason, pending=pending, last_review=text or entry.get("last_review", ""), at=now(), seen=ids)
        if handled:
            entry["handled"] = ids
        prs[key] = entry
    if dry:
        return
    if first and prs:  # one summary instead of a notification per PR
        ready = sum(1 for e in prs.values() if e["action"] == "ready")
        notify("Revue des PR", f"Surveillance activée : {len(prs)} PR suivie(s), {len(launched)} correction(s) auto lancée(s)"
               + (f", {ready} prête(s) à merger" if ready else ""))
    state.update(prs=prs, at=time.time())
    write_json(STATE, state)


# ---------- launchd ----------

def stable_script():
    """A path that survives plugin updates: the marketplace clone rather than the versioned cache."""
    me = os.path.abspath(__file__)
    m = re.search(r"/plugins/cache/([^/]+)/[^/]+/[^/]+/(scripts/[^/]+)$", me)
    if m:
        alt = os.path.join(HOME, ".claude", "plugins", "marketplaces", m.group(1), "plugins", "ws", m.group(2))
        if os.path.exists(alt):
            return alt
    return me


def install():
    # the user's PATH order (rbenv/nvm shims before /usr/bin), then the usual places for claude, bun, brew
    path = os.environ.get("PATH", "").split(":") + [
        f"{HOME}/.local/bin", f"{HOME}/.bun/bin", f"{HOME}/.rbenv/shims", "/opt/homebrew/bin", "/usr/local/bin",
        "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    path = list(dict.fromkeys(p for p in path if p.startswith("/") and os.path.isdir(p)))
    python = "/usr/bin/python3" if os.path.exists("/usr/bin/python3") else shutil.which("python3") or sys.executable
    os.makedirs(os.path.dirname(PLIST), exist_ok=True)
    os.makedirs(BASE, exist_ok=True)
    with open(PLIST, "wb") as f:
        plistlib.dump({"Label": LABEL, "ProgramArguments": [python, stable_script(), "run"],
                       "StartInterval": 300, "RunAtLoad": True, "AbandonProcessGroup": True,
                       "EnvironmentVariables": {"PATH": ":".join(path), "HOME": HOME},
                       "StandardOutPath": LOG, "StandardErrorPath": LOG}, f)
    domain = f"gui/{os.getuid()}"
    sh("launchctl", "bootout", f"{domain}/{LABEL}")  # reload when already installed
    r = sh("launchctl", "bootstrap", domain, PLIST)
    if r.returncode:
        sys.exit(f"launchctl bootstrap failed: {r.stderr.strip()}")
    print(f"installed {PLIST} (every 5 min, log {LOG})")
    if not read_json(CONFIG, {}).get("review_autofix"):
        print(f'inactive until "review_autofix": true is set in {CONFIG}')


def uninstall():
    sh("launchctl", "bootout", f"gui/{os.getuid()}/{LABEL}")
    if os.path.exists(PLIST):
        os.remove(PLIST)
    print(f"uninstalled {LABEL}")


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "run":
        run("--dry-run" in sys.argv[2:])
    elif cmd == "install":
        install()
    elif cmd == "uninstall":
        uninstall()
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
