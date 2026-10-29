#!/usr/bin/env python3
"""ws-brain.py — the team's knowledge as a graph: rules → sections → lessons → PRs.

  ws-brain.py [--out brain.json]     run inside the project (its .claude-workspaces.json lists the repos)

Reads every repo's `.claude/rules/*.md` as merged on origin/develop (falls back to HEAD), so the
graph shows reviewed team knowledge only — never personal memory nor the unreviewed inbox.
Each top-level bullet or numbered item is a lesson; its date is the month written in it
("2026-09/10" → 2026-09) when there is one, else the day its first line landed (git blame).
"#1234" references become PR nodes (repo from a nearby "front"/"back", else the rule's repo).
Read by the brain page published by the `brain` skill.
"""
import argparse, json, os, re, subprocess, sys, time
from collections import Counter


def git(path, *args):
    r = subprocess.run(["git", "-C", path, *args], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""


def project():
    d = os.getcwd()
    while d != "/":
        p = os.path.join(d, ".claude-workspaces.json")
        if os.path.isfile(p):
            return d, json.load(open(p))
        d = os.path.dirname(d)
    sys.exit("no .claude-workspaces.json above the current directory")


def repo_dirs(root, cfg):
    for r in cfg.get("repos", []):
        origins = r.get("origin") if isinstance(r.get("origin"), list) else [r.get("origin")]
        for o in origins:
            if o and os.path.isdir(os.path.join(root, o, ".git")) or (o and os.path.isfile(os.path.join(root, o, ".git"))):
                yield r["name"], os.path.normpath(os.path.join(root, o))
                break


def front(text):
    m = re.match(r"---\n(.*?)\n---\n?", text, re.S)
    if not m:
        return {}, text
    keys, cur = {}, None
    for line in m.group(1).splitlines():
        if re.match(r"^\w[\w-]*:", line):
            cur, _, rest = line.partition(":")
            rest = rest.strip()
            keys[cur] = [x.strip().strip("'\"") for x in rest.strip("[]").split(",") if x.strip()] if rest else []
        elif cur and line.strip().startswith("- "):
            keys[cur].append(line.strip()[2:].strip().strip("'\""))
    return keys, text[m.end():]


def blame_days(path, ref, f):
    """line number (1-based, whole file) → YYYY-MM-DD the line landed."""
    out, days, cur = git(path, "blame", "--line-porcelain", ref, "--", f), {}, None
    for line in out.splitlines():
        m = re.match(r"^[0-9a-f]{40} \d+ (\d+)", line)
        if m:
            cur = int(m.group(1))
        elif line.startswith("author-time ") and cur:
            days[cur] = time.strftime("%Y-%m-%d", time.localtime(int(line.split()[1])))
    return days


def lessons(body, offset):
    """[(section, text, first line number)] — bullets / numbered items with their continuation lines."""
    out, section, cur = [], "", None
    for i, line in enumerate(body.splitlines(), start=offset):
        if line.startswith("## "):
            section, cur = line[3:].strip(), None
        elif re.match(r"^(- |\d+\. )", line):
            cur = [section, re.sub(r"^(- |\d+\. )", "", line).strip(), i]
            out.append(cur)
        elif cur and line.strip() and not line.startswith("#"):
            cur[1] += " " + line.strip()
        elif not line.strip():
            cur = None
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out")
    a = ap.parse_args()
    root, cfg = project()
    nodes, edges, seen = {}, [], set()

    def node(nid, **kw):
        nodes.setdefault(nid, {"id": nid, **kw})
        return nodes[nid]

    def edge(s, t):
        if (s, t) not in seen:
            seen.add((s, t))
            edges.append({"source": s, "target": t})

    repos = []
    for name, path in repo_dirs(root, cfg):
        subprocess.run(["git", "-C", path, "fetch", "-q", "origin", "develop"], capture_output=True, timeout=30)
        ref = "origin/develop" if git(path, "rev-parse", "-q", "--verify", "origin/develop") else "HEAD"
        files = [f for f in git(path, "ls-tree", "--name-only", ref, ".claude/rules/").split() if f.endswith(".md")]
        if not files:
            continue
        slug = (re.search(r"[:/]([^/:]+/[^/]+?)(?:\.git)?$", git(path, "remote", "get-url", "origin").strip()) or [None, ""])[1]
        repos.append({"name": name, "slug": slug, "ref": ref})
        node(f"repo:{name}", type="repo", label=name, slug=slug)
        for f in files:
            text = git(path, "show", f"{ref}:{f}")
            keys, body = front(text)
            stem = os.path.basename(f)[:-3]
            title = (re.search(r"^# (.+)$", body, re.M) or [None, stem])[1].replace(" (team knowledge)", "")
            d = node(f"domain:{stem}", type="domain", label=title, stem=stem, repos=[], files=[],
                     always="paths" not in keys, keywords=[], paths=[])
            d["repos"].append(name)
            d["files"].append(f"{name}/{f}")
            d["keywords"] = sorted(set(d["keywords"]) | set(keys.get("keywords", [])))
            d["paths"] += [f"{name}: {p}" for p in keys.get("paths", [])]
            edge(f"repo:{name}", d["id"])
            days = blame_days(path, ref, f)
            offset = text.count("\n", 0, len(text) - len(body)) + 1
            for n, (section, ltext, line) in enumerate(lessons(body, offset)):
                parent = d["id"]
                if section:
                    parent = node(f"section:{stem}:{section}", type="section", label=section, domain=stem)["id"]
                    edge(d["id"], parent)
                month = re.search(r"\b(20\d\d-[01]\d)(?:-\d\d)?\b", ltext)
                lid = f"lesson:{name}:{stem}:{n}"
                node(lid, type="lesson", label=ltext[:80], text=ltext, domain=stem, repo=name, section=section,
                     date=month.group(1) + "-01" if month else days.get(line, ""), file=f"{name}/{f}")
                edge(parent, lid)
                for m in re.finditer(r"#(\d{3,5})\b", ltext):
                    before = ltext[max(0, m.start() - 12):m.start()].lower()
                    r = "front" if "front" in before else "back" if "back" in before else name
                    rslug = next((x["slug"] for x in repos if x["name"] == r), slug)
                    pid = f"pr:{r}#{m.group(1)}"
                    node(pid, type="pr", label=f"{r} #{m.group(1)}", url=f"https://github.com/{rslug}/pull/{m.group(1)}" if rslug else "")
                    edge(lid, pid)
    ls = [n for n in nodes.values() if n["type"] == "lesson"]
    out = {"generated_at": time.strftime("%Y-%m-%d %H:%M"), "repos": repos,
           "stats": {"lessons": len(ls), "domains": sum(n["type"] == "domain" for n in nodes.values()),
                     "prs": sum(n["type"] == "pr" for n in nodes.values()),
                     "by_month": dict(sorted(Counter(n["date"][:7] for n in ls if n["date"]).items()))},
           "nodes": list(nodes.values()), "edges": edges}
    s = json.dumps(out, ensure_ascii=False)
    if a.out:
        open(a.out, "w").write(s)
        print(f"{a.out}: {out['stats']['lessons']} lessons, {out['stats']['domains']} domains, {out['stats']['prs']} PRs")
    else:
        print(s)


if __name__ == "__main__":
    main()
