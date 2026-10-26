#!/usr/bin/env python3
"""ws-actuals.py — what a feature really cost, measured from Claude transcripts + git.

  ws-actuals.py <workspace path | worktree slug> [--json] [--gh]

Three numbers, never mixed (one person runs many features in parallel):
- human_hours: the person's attention. Every human prompt of the day, across ALL
  sessions, gets the time since the previous prompt (capped at 30 min, > 3 h = away):
  reading the last answer and thinking happen just before typing in that window.
  The features of a day add up to the real working day, no double counting.
- machine_hours: Claude working (prompt → end of its turn, tools and agents
  included), merged across the workspace's sessions.
- elapsed: first to last activity (hours if same day) and calendar_days.
Time outside Claude (browser tests, PR review on GitHub, client calls) is not seen.
- per repo (when the workspace still exists): branch, commits, diff vs base.
- --gh: also the PRs of each branch (merged dates), one gh call per repo.

Transcripts are kept `cleanupPeriodDays` (default 30): older features return 0 h.
"""
import glob, json, os, re, subprocess, sys
from datetime import datetime, timedelta

CAP_S, AWAY_S = 30 * 60, 3 * 3600
REPO_DIRS = ("back", "front", "webhook", "deployment", "web")
ROOT = os.path.expanduser("~/.claude/projects")


def enc(path):
    return re.sub(r"[^A-Za-z0-9]", "-", path)


def git(path, *args):
    r = subprocess.run(["git", "-C", path, *args], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""


def transcript_dirs(ws_path):
    base = enc(ws_path)
    return [d for d in glob.glob(f"{ROOT}/{base}*")
            if os.path.basename(d) == base or re.fullmatch(re.escape(base) + r"-(" + "|".join(REPO_DIRS) + ")", os.path.basename(d))]


def events(path):
    """(timestamp, is_human_prompt, session) of the main thread of one transcript."""
    for line in open(path, errors="ignore"):
        if '"timestamp"' not in line:
            continue
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if e.get("type") not in ("user", "assistant") or e.get("isSidechain") or not e.get("timestamp"):
            continue
        c = e.get("message", {}).get("content")
        text = c if isinstance(c, str) else " ".join(
            b.get("text", "") for b in c or [] if isinstance(b, dict) and b.get("type") == "text")
        human = (e["type"] == "user" and not e.get("isMeta") and text.strip() and not text.lstrip().startswith("<")
                 and "continued from a previous conversation" not in text)
        yield datetime.fromisoformat(e["timestamp"].replace("Z", "+00:00")), bool(human), e.get("sessionId")


def measure(ws_path):
    own = [f for d in transcript_dirs(ws_path) for f in glob.glob(f"{d}/*.jsonl")]
    by_session, prompts = {}, []
    for f in own:
        for t, human, sid in events(f):
            by_session.setdefault(sid, []).append((t, human))
    stamps = sorted(t for evs in by_session.values() for t, _ in evs)
    if not stamps:
        return {"human_hours": 0, "machine_hours": 0, "elapsed_hours": 0, "calendar_days": 0,
                "sessions": 0, "first": None, "last": None}
    # machine: Claude busy between consecutive events of a session, until the next human
    # prompt; a silence over 30 min means the turn was over (late notifications don't count)
    turns = []
    for evs in by_session.values():
        evs.sort()
        turns += [(a, b) for (a, _), (b, human) in zip(evs, evs[1:])
                  if not human and (b - a).total_seconds() <= CAP_S]
    machine, end = 0.0, None
    for a, b in sorted(turns):
        if end is None or a > end:
            machine += (b - a).total_seconds()
            end = b
        elif b > end:
            machine += (b - end).total_seconds()
            end = b
    # human: attribute every prompt of the period, all sessions included
    since = stamps[0] - timedelta(days=1)
    own_set = set(own)
    for f in glob.glob(f"{ROOT}/*/*.jsonl"):
        if os.path.getmtime(f) < since.timestamp():
            continue
        prompts += [(t, f in own_set) for t, human, _ in events(f) if human and t >= since]
    prompts.sort()
    human = sum(min(g, CAP_S) for g, mine in (((b[0] - a[0]).total_seconds(), b[1]) for a, b in zip(prompts, prompts[1:]))
                if mine and g <= AWAY_S)
    return {
        "human_hours": round(human / 3600, 1),
        "machine_hours": round(machine / 3600, 1),
        "elapsed_hours": round((stamps[-1] - stamps[0]).total_seconds() / 3600, 1),
        "calendar_days": (stamps[-1].date() - stamps[0].date()).days + 1,
        "sessions": len(set(by_session) - {None}),
        "first": stamps[0].date().isoformat(),
        "last": stamps[-1].date().isoformat(),
    }


def repos(ws_path, with_gh):
    out = []
    dirs = [ws_path] if os.path.exists(os.path.join(ws_path, ".git")) else \
        [os.path.join(ws_path, d) for d in sorted(os.listdir(ws_path)) if os.path.exists(os.path.join(ws_path, d, ".git"))] \
        if os.path.isdir(ws_path) else []
    for d in dirs:
        branch = git(d, "branch", "--show-current")
        base = "origin/develop" if git(d, "rev-parse", "-q", "--verify", "origin/develop") else "origin/main"
        commits = git(d, "rev-list", "--count", "--no-merges", f"{base}..HEAD") or "0"
        if commits == "0":
            continue  # untouched repo of the workspace
        stat = git(d, "diff", "--shortstat", f"{base}...HEAD")
        nums = [int(n) for n in re.findall(r"(\d+) (?:insertion|deletion)", stat)]
        r = {"repo": os.path.basename(d), "branch": branch, "commits": int(commits),
             "lines_changed": sum(nums), "files": int((re.findall(r"(\d+) files? changed", stat) or ["0"])[0])}
        if with_gh:
            p = subprocess.run(["gh", "pr", "list", "--head", branch, "--state", "all", "--json",
                                "number,state,mergedAt,baseRefName"], cwd=d, capture_output=True, text=True)
            r["prs"] = json.loads(p.stdout or "[]")
        out.append(r)
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        sys.exit(__doc__)
    target = args[0]
    ws_path = target if os.path.isabs(target) else os.path.expanduser(f"~/projects/worktrees/{target}")
    task = re.search(r"task-(\d+)", ws_path)
    res = {"workspace": ws_path, "task_id": f"TASK-{task.group(1)}" if task else None,
           **measure(ws_path), "repos": repos(ws_path, "--gh" in sys.argv)}
    if "--json" in sys.argv:
        print(json.dumps(res, ensure_ascii=False))
        return
    span = f"{res['elapsed_hours']} h" if res["calendar_days"] <= 1 else f"{res['calendar_days']} j"
    print(f"{os.path.basename(ws_path)}: attention {res['human_hours']} h · Claude au travail {res['machine_hours']} h · "
          f"délai {span} ({res['sessions']} sessions, {res['first']} → {res['last']})")
    for r in res["repos"]:
        print(f"  {r['repo']}: {r['branch']} — {r['commits']} commits, {r['files']} fichiers, {r['lines_changed']} lignes")


if __name__ == "__main__":
    main()
