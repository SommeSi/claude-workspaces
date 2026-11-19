#!/usr/bin/env python3
"""ws-reviewer.py — pick the PR assignee (reviewer/merger) with the lightest load.

  ws-reviewer.py            run inside a repo; prints REVIEWER=<login> then the load table

Candidates: `reviewers` in the project's .claude-workspaces.json if set, else the
people who authored a PR merged in this repo over the last 45 days (bots excluded).
The author (you) is never a candidate, nor anyone in `reviewers_exclude` (project config, found in
the repo, its parent or a sibling repo of the workspace, plus ~/.claude-workspaces/config.json). Load = open PRs assigned to them across the
whole GitHub org. Ties go to whoever you assigned least in your last 30 PRs.
"""
import glob, json, os, re, subprocess, sys
from collections import Counter
from datetime import datetime, timedelta, timezone


def gh(*args):
    r = subprocess.run(["gh", *args], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"REVIEWER=\n# gh failed: {r.stderr.strip()[:200]}")
    return json.loads(r.stdout or "null")


def project_config():
    """The workspace's .claude-workspaces.json: in the repo, its parent, or a sibling repo (front next to back)."""
    d = os.getcwd()
    while d != "/":
        parent = os.path.dirname(d)
        for p in [os.path.join(d, ".claude-workspaces.json"), os.path.join(parent, ".claude-workspaces.json"),
                  *sorted(glob.glob(os.path.join(parent, "*", ".claude-workspaces.json")))]:
            if os.path.isfile(p):
                return json.load(open(p))
        d = parent
    return {}


def excluded(cfg):
    try:
        user = json.load(open(os.path.expanduser("~/.claude-workspaces/config.json")))
    except (OSError, ValueError):
        user = {}
    return {x.lower() for x in cfg.get("reviewers_exclude", []) + user.get("reviewers_exclude", [])}


def main():
    url = subprocess.run(["git", "remote", "get-url", "origin"], capture_output=True, text=True).stdout
    m = re.search(r"[:/]([^/:]+)/([^/]+?)(?:\.git)?$", url.strip())
    if not m:
        sys.exit("REVIEWER=\n# not in a GitHub repo")
    owner, repo = m.groups()
    me = gh("api", "user")["login"]
    cfg = project_config()
    candidates = cfg.get("reviewers")
    if not candidates:
        since = datetime.now(timezone.utc) - timedelta(days=45)
        merged = gh("pr", "list", "-R", f"{owner}/{repo}", "--state", "merged", "--limit", "100",
                    "--json", "author,mergedAt")
        candidates = sorted({p["author"]["login"] for p in merged
                             if not p["author"].get("is_bot") and "[bot]" not in p["author"]["login"]
                             and datetime.fromisoformat(p["mergedAt"].replace("Z", "+00:00")) >= since})
    skip = excluded(cfg) | {me.lower()}
    candidates = [c for c in candidates if c.lower() not in skip]
    if not candidates:
        sys.exit("REVIEWER=\n# no candidate reviewer")
    open_prs = gh("search", "prs", "--owner", owner, "--state", "open", "--limit", "200", "--json", "assignees")
    load = Counter(a["login"] for p in open_prs for a in p.get("assignees", []))
    mine = gh("pr", "list", "-R", f"{owner}/{repo}", "--author", "@me", "--state", "all", "--limit", "30",
              "--json", "assignees")
    given = Counter(a["login"] for p in mine for a in p.get("assignees", []))
    pick = min(candidates, key=lambda c: (load[c], given[c], c.lower()))
    print(f"REVIEWER={pick}")
    for c in sorted(candidates, key=lambda c: (load[c], given[c])):
        print(f"# {c}: {load[c]} PR ouverte(s) à traiter")


if __name__ == "__main__":
    main()
