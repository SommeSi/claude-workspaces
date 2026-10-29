#!/usr/bin/env python3
"""ws-knowledge.py — capture team lessons from Claude sessions, serve them back.

  capture            SessionEnd hook (event JSON on stdin). Forks a detached
                     worker and returns at once (the hook budget is ~1.5s); the
                     worker asks a headless `claude -p --safe-mode` to extract
                     team lessons, tooling frictions + a summary from the
                     transcript, then writes ~/.claude-workspaces/knowledge-inbox/
                     and friction-inbox/<session>.json, and appends the summary
                     to ~/.claude-workspaces/sessions.jsonl.
  list [--repo R]    Pending lessons as JSON (for /knowledge-review).
  match --repo R F…  Pending lessons of repo R whose paths match files F (for /git-pr).
  frictions          Pending tooling frictions grouped by target, most sessions first.
  consume ID…        Drop lessons written into a rules file, or frictions fixed.
  recall WORDS…      Past sessions whose summary/branch/cwd match WORDS.

Repos are identified by their origin slug (Owner/name), stable across worktrees.
Disable capture with WS_KNOWLEDGE_DISABLE=1.
"""
import fnmatch, json, os, re, shutil, subprocess, sys, time
from datetime import datetime

HOME = os.path.expanduser("~")
BASE = os.path.join(HOME, ".claude-workspaces")
INBOX = os.path.join(BASE, "knowledge-inbox")
FRICTIONS = os.path.join(BASE, "friction-inbox")
SESSIONS = os.path.join(BASE, "sessions.jsonl")
LOG = os.path.join(BASE, "knowledge-capture.log")
MIN_USER_TURNS = 3  # a shorter session is still read when a tool failed (often a friction, ~6/week)
MAX_CHARS = 120_000

PROMPT = """You read the transcript of a Claude Code session of a software team and extract the durable knowledge that OTHER developers' Claude sessions should have.

Keep only lessons that are TEAM knowledge AND were confirmed in the session (by the user, a test, the code, or a production observation), never hypotheses that were dropped or disproved:
- business rules and client-specific facts, third-party API behaviour and traps,
- the real cause of a bug and the rule that prevents it coming back,
- conventions or process decisions the team stated,
- corrections the user made to Claude that reveal a team rule.
Exclude: personal interaction preferences, one-off task state, anything obvious from reading the code, and any secret, credential, token, connection string or personal data (emails, phones) — refer to such things by name only.

Separately, list the FRICTIONS: moments where the developer's tooling got in the way, so the tooling can be improved. Tooling = the workspace plugin (its /workspace:* skills, scripts, hooks), worktree and dev-server setup, ports, local databases, permission prompts and classifier refusals, CLI tools, Claude Code config. Signals: the user repeats or rephrases a request, complains, corrects how a tool was used, does a step by hand, or a TOOL ERROR costs several turns or needs a workaround.
Exclude: bugs of the product being developed, the user changing their mind, one-off reasoning mistakes of Claude, and an error fixed at once by a retry.

Repos involved (use the exact slug):
{repos}

Answer with ONE JSON object and nothing else:
{{"summary": "2-3 sentences in French: what was done and the outcome",
  "lessons": [{{"repo": "<slug from the list>", "topic": "short-kebab-key", "paths": ["repo-relative globs where it matters, [] if general"], "lesson": "English, imperative, 1-3 lines, concrete (name the method/file/field), why in a few words", "source": "PR #, ticket, client or date if mentioned"}}],
  "frictions": [{{"target": "the thing to change: `workspace:<skill>`, a script or command name (`bin/prod-runner`, `ws-knowledge.py`), else exactly one of permissions, hooks (git hooks included), ports, database, dev-servers, git, ci, claude-config, other", "symptom": "French, 1 line, concrete: what got in the way and what it cost", "suggestion": "French, 1 line: the change to the tooling that would remove it", "evidence": "short quote of the user or of the error"}}]}}
At most 8 lessons and 5 frictions; empty lists are the normal answer for most sessions.

TRANSCRIPT:
"""


def log(msg):
    os.makedirs(BASE, exist_ok=True)
    with open(LOG, "a") as f:
        f.write(f"{datetime.now():%Y-%m-%d %H:%M:%S} {msg}\n")


def git(path, *args):
    r = subprocess.run(["git", "-C", path, *args], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""


def repos_for(cwd):
    """Git repos of the session: cwd's repo, else its direct children (multi-repo workspace)."""
    top = git(cwd, "rev-parse", "--show-toplevel")
    dirs = [top] if top else [os.path.join(cwd, d) for d in sorted(os.listdir(cwd))
                              if os.path.exists(os.path.join(cwd, d, ".git"))]
    out = []
    for d in dirs:
        url = git(d, "remote", "get-url", "origin")
        m = re.search(r"[:/]([^/:]+/[^/]+?)(?:\.git)?$", url)
        if not m:
            continue
        common = git(d, "rev-parse", "--path-format=absolute", "--git-common-dir")
        out.append({"slug": m.group(1), "branch": git(d, "branch", "--show-current"),
                    "main_checkout": os.path.dirname(common) if common else d})
    return out


def condense(transcript):
    """User + assistant text and failed tool calls (no other tool output, no thinking, no subagents)."""
    parts, user_turns, title, sdk, calls, errors = [], 0, "", False, {}, 0
    for line in open(transcript, errors="ignore"):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if d.get("type") == "ai-title":
            title = d.get("aiTitle") or d.get("title") or title
        if d.get("type") not in ("user", "assistant") or d.get("isSidechain") or d.get("isMeta"):
            continue
        if str(d.get("entrypoint", "")).startswith("sdk"):
            sdk = True
        content = d.get("message", {}).get("content")
        for b in content if isinstance(content, list) else []:
            if not isinstance(b, dict):
                continue
            if b.get("type") == "tool_use":
                i = b.get("input") or {}
                arg = i.get("description") or i.get("command") or i.get("file_path") or i.get("skill") or ""
                calls[b.get("id")] = f"{b.get('name')} {str(arg)[:150]}".strip()
            elif b.get("type") == "tool_result" and b.get("is_error"):
                out = b.get("content")
                out = out if isinstance(out, str) else " ".join(
                    x.get("text", "") for x in out or [] if isinstance(x, dict))
                errors += 1
                parts.append(f"TOOL ERROR ({calls.get(b.get('tool_use_id'), '?')}): {out[:300]}")
        texts = [content] if isinstance(content, str) else [
            b.get("text", "") for b in content or [] if isinstance(b, dict) and b.get("type") == "text"]
        text = "\n".join(t for t in texts if t and not t.lstrip().startswith("<")).strip()
        if not text:
            continue
        if d["type"] == "user":
            user_turns += 1
        parts.append(f"{d['type'].upper()}: {text[:3000]}")
    body = "\n\n".join(parts)
    if len(body) > MAX_CHARS:  # keep the start (the goal) and the end (the outcome)
        body = body[:20_000] + "\n\n[…]\n\n" + body[-(MAX_CHARS - 20_000):]
    return body, user_turns, title, sdk, errors


def claude_bin():
    return shutil.which("claude") or next(
        (p for p in (f"{HOME}/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude")
         if os.path.exists(p)), None)


def extract(event):
    transcript, sid = event.get("transcript_path", ""), event.get("session_id", "")
    cwd = event.get("cwd") or os.getcwd()
    time.sleep(3)  # the transcript is written asynchronously
    if not (transcript and os.path.exists(transcript) and sid):
        return log(f"skip {sid[:8]}: no transcript")
    body, user_turns, title, sdk, errors = condense(transcript)
    if sdk or (user_turns < MIN_USER_TURNS and not errors):
        return log(f"skip {sid[:8]}: {'headless' if sdk else f'{user_turns} user turns'}")
    repos = repos_for(cwd)
    exe = claude_bin()
    if not exe:
        return log(f"skip {sid[:8]}: claude CLI not found")
    repo_list = "\n".join(f"- {r['slug']} (branch {r['branch']})" for r in repos) or "- (none: use \"\" as repo)"
    env = {**os.environ, "WS_KNOWLEDGE_DISABLE": "1"}
    r = subprocess.run([exe, "-p", "--safe-mode", "--model", "sonnet", "--tools", "",
                        "--no-session-persistence", "--output-format", "text"],
                       input=PROMPT.format(repos=repo_list) + body, capture_output=True,
                       text=True, timeout=600, env=env, cwd=HOME)
    m = re.search(r"\{.*\}", r.stdout, re.S)
    try:
        data = json.loads(m.group(0)) if m else None
    except ValueError:
        data = None
    if not data:
        return log(f"fail {sid[:8]}: rc={r.returncode} {(r.stderr or r.stdout)[:200]!r}")
    slugs = {x["slug"]: x for x in repos}
    lessons = []
    for i, l in enumerate(data.get("lessons") or []):
        if l.get("lesson"):
            repo = slugs.get(l.get("repo"), {})
            lessons.append({**l, "id": f"{sid[:8]}-{i}", "main_checkout": repo.get("main_checkout", "")})
    frictions = [{**f, "id": f"{sid[:8]}-f{i}"}
                 for i, f in enumerate(data.get("frictions") or []) if f.get("symptom")]
    now = datetime.now().isoformat(timespec="seconds")
    meta = {"session_id": sid, "date": now, "cwd": cwd, "title": title,
            "branches": [f"{x['slug']}@{x['branch']}" for x in repos], "summary": data.get("summary", "")}
    save(INBOX, "lessons", meta, lessons)
    save(FRICTIONS, "frictions", meta, frictions)
    os.makedirs(BASE, exist_ok=True)
    with open(SESSIONS, "a") as f:
        f.write(json.dumps(meta, ensure_ascii=False) + "\n")
    log(f"ok {sid[:8]}: {len(lessons)} lesson(s), {len(frictions)} friction(s), "
        f"{user_turns} user turns, {errors} tool errors")


def save(folder, key, meta, items):
    path = os.path.join(folder, f"{meta['session_id']}.json")
    if items:
        os.makedirs(folder, exist_ok=True)
        json.dump({**meta, key: items}, open(path, "w"), indent=2, ensure_ascii=False)
    elif os.path.exists(path):  # resumed session that no longer yields any
        os.remove(path)


def capture():
    if os.environ.get("WS_KNOWLEDGE_DISABLE") or os.environ.get("CLAUDE_CODE_SAFE_MODE"):
        return
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return
    if os.fork():  # parent: return to Claude Code immediately
        return
    os.setsid()
    if os.fork():  # second fork: fully detached from the session's process group
        os._exit(0)
    devnull = os.open(os.devnull, os.O_RDWR)
    for fd in (0, 1, 2):
        os.dup2(devnull, fd)
    try:
        extract(event)
    except Exception as e:  # never surface anything to the user's session
        log(f"error {event.get('session_id', '')[:8]}: {e!r}")
    os._exit(0)


def pending(folder=INBOX, key="lessons"):
    out = []
    for name in sorted(os.listdir(folder)) if os.path.isdir(folder) else []:
        if name.endswith(".json"):
            d = json.load(open(os.path.join(folder, name)))
            for l in d.get(key, []):
                out.append({**l, "session_id": d["session_id"], "date": d["date"]})
    return out


def frictions_report():
    groups = {}
    for f in pending(FRICTIONS, "frictions"):
        groups.setdefault(str(f.get("target") or "other").strip("`/ ").lower(), []).append(f)
    sessions = lambda fs: len({f["session_id"] for f in fs})
    for target, fs in sorted(groups.items(), key=lambda g: -sessions(g[1])):
        print(f"{sessions(fs)} session(s)  {target}")
        for f in fs:
            print(f"  - {f['date'][:10]} [{f['id']}] {f['symptom']}\n    → {f.get('suggestion', '')}")
    if not groups:
        print("no friction pending")


def glob_match(path, pattern):
    rx = re.escape(pattern).replace(r"\*\*/", "(?:.*/)?").replace(r"\*\*", ".*").replace(r"\*", "[^/]*")
    return re.fullmatch(rx, path) is not None


def consume(ids):
    ids = set(ids)
    for folder, key in ((INBOX, "lessons"), (FRICTIONS, "frictions")):
        for name in os.listdir(folder) if os.path.isdir(folder) else []:
            p = os.path.join(folder, name)
            if not name.endswith(".json"):
                continue
            d = json.load(open(p))
            keep = [l for l in d.get(key, []) if l["id"] not in ids]
            if len(keep) != len(d.get(key, [])):
                if keep:
                    json.dump({**d, key: keep}, open(p, "w"), indent=2, ensure_ascii=False)
                else:
                    os.remove(p)
    print(f"consumed {len(ids)}")


def recall(words):
    words = [w.lower() for w in words]
    seen = {}
    for line in open(SESSIONS) if os.path.exists(SESSIONS) else []:
        d = json.loads(line)
        seen[d["session_id"]] = d  # last capture of a session wins
    hits = [d for d in seen.values()
            if all(w in json.dumps(d, ensure_ascii=False).lower() for w in words)]
    for d in sorted(hits, key=lambda d: d["date"], reverse=True)[:10]:
        print(f"{d['date'][:16]}  {', '.join(d['branches']) or d['cwd']}\n  {d.get('title') or ''}\n"
              f"  {d['summary']}\n  → cd {d['cwd']} && claude --resume {d['session_id']}\n")
    if not hits:
        print("no session found")


def main():
    cmd, args = (sys.argv[1], sys.argv[2:]) if len(sys.argv) > 1 else ("list", [])
    if cmd == "capture":
        capture()
    elif cmd == "list":
        repo = args[args.index("--repo") + 1] if "--repo" in args else None
        print(json.dumps([l for l in pending() if not repo or l.get("repo") == repo], indent=1, ensure_ascii=False))
    elif cmd == "match":
        repo, files = args[args.index("--repo") + 1], [a for a in args if a != "--repo"][1:]
        print(json.dumps([l for l in pending() if l.get("repo") == repo and any(
            glob_match(f, p) for p in l.get("paths", []) for f in files)], indent=1, ensure_ascii=False))
    elif cmd == "frictions":
        frictions_report()
    elif cmd == "consume":
        consume(args)
    elif cmd == "recall":
        recall(args)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
