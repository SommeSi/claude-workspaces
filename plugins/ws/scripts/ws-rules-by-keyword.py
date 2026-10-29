#!/usr/bin/env python3
"""ws-rules-by-keyword.py — UserPromptSubmit hook: team rules for prompts that touch no file.

Native `.claude/rules/*.md` load on their `paths:`, i.e. only once Claude opens a matching file.
A prompt like "réponds à H&T sur le lettrage" opens none, so polo.md never loads. Here a rule
also declares words in its frontmatter:

    ---
    paths: [...]
    keywords: [polo, h&t, lettrage]
    ---

and when the prompt contains one (case and accents ignored, whole words), the rule body is added
to the context. Each rule once per session. Rules without `paths:` are always loaded natively:
skipped. Rules are looked up in the session's repo (git root of cwd) or, at a multi-repo
workspace root, in each child repo. Pure text search, no model call.
"""
import glob, json, os, re, subprocess, sys, tempfile, unicodedata

MAX_CHARS = 30000


def norm(s):
    return "".join(c for c in unicodedata.normalize("NFKD", s.lower()) if not unicodedata.combining(c))


def front(text):
    """(frontmatter keys, body) — just enough YAML for `paths:` and `keywords:` lists."""
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


def repos(cwd):
    r = subprocess.run(["git", "-C", cwd, "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    if r.returncode == 0:
        return [r.stdout.strip()]
    return [os.path.join(cwd, d) for d in sorted(os.listdir(cwd)) if os.path.exists(os.path.join(cwd, d, ".git"))] \
        if os.path.isdir(cwd) else []


def matches(prompt, cwd):
    p = norm(prompt)
    out = []
    for repo in repos(cwd):
        for f in sorted(glob.glob(os.path.join(repo, ".claude", "rules", "*.md"))):
            keys, body = front(open(f, errors="ignore").read())
            if "paths" not in keys:
                continue
            hits = [k for k in keys.get("keywords", []) if re.search(r"(?<![a-z0-9])" + re.escape(norm(k)) + r"(?![a-z0-9])", p)]
            if hits:
                out.append((f, hits, body.strip()))
    return out


def main():
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return
    found = matches(event.get("prompt") or "", event.get("cwd") or os.getcwd())
    if not found:
        return
    state = os.path.join(tempfile.gettempdir(), f"ws-rules-{event.get('session_id', 'none')}.json")
    try:
        seen = set(json.load(open(state)))
    except (OSError, ValueError):
        seen = set()
    parts, size = [], 0
    for f, hits, body in found:
        if f in seen or size + len(body) > MAX_CHARS:
            continue
        seen.add(f)
        size += len(body)
        rel = os.path.relpath(f, os.path.dirname(os.path.dirname(os.path.dirname(f))))
        parts.append(f"### {os.path.basename(os.path.dirname(os.path.dirname(os.path.dirname(f))))}/{rel} (mots-clés : {', '.join(hits)})\n{body}")
    if not parts:
        return
    json.dump(sorted(seen), open(state, "w"))
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext":
        "Règles d'équipe chargées d'après les mots du message (à appliquer comme les règles .claude/rules natives) :\n\n"
        + "\n\n".join(parts)}}, ensure_ascii=False))


if __name__ == "__main__":
    if os.environ.get("WS_RULES_SELFTEST"):  # WS_RULES_SELFTEST=1 python3 ws-rules-by-keyword.py
        d = tempfile.mkdtemp()
        subprocess.run(["git", "init", "-q", d])
        os.makedirs(os.path.join(d, ".claude", "rules"))
        open(os.path.join(d, ".claude", "rules", "polo.md"), "w").write(
            "---\npaths:\n  - \"app/**/polo/**\"\nkeywords: [polo, h&t, débours]\n---\nPOLO RULE\n")
        open(os.path.join(d, ".claude", "rules", "team.md"), "w").write("---\nkeywords:\n  - polo\n---\nALWAYS LOADED\n")
        assert [h for _, h, _ in matches("réponds à H&T sur les DEBOURS", d)] == [["h&t", "débours"]]
        assert matches("apollon et polochon", d) == []
        assert front("---\npaths:\n  - a\nkeywords: [x, 'y z']\n---\nB")[0] == {"paths": ["a"], "keywords": ["x", "y z"]}
        print("ok")
        sys.exit()
    main()
