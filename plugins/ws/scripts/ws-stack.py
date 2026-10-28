#!/usr/bin/env python3
"""ws-stack.py — keep PRs under the repo's pr-size-limit check by splitting them into a stack.

  ws-stack.py size [--base origin/develop]
      Counts <base>...HEAD the way .github/workflows/pr-size-limit.yml does (same MAX_FILES,
      MAX_LINES, EXCLUDE_REGEX; defaults = backend values when the file is missing) and prints
      FILES= LINES= MAX_FILES= MAX_LINES= OVER=0|1. When OVER=1 it then lists every changed
      file: "<lines> <path>" when counted, "- <path>" when excluded (tests, generated files).

  ws-stack.py split <plan.json | -> [--submit] [--force]
      plan = {"base": "origin/develop", "assignee": "<login>",
              "layers": [{"branch": "...", "title": "...", "body": "...", "files": [...]}, ...]}
      Layers go bottom -> top. Each layer is one commit on top of the previous one (the first on
      the merge-base), holding its files as they are at HEAD, deletions and renames included (a
      rename is listed by its new path). Branches are created in one atomic ref update, only
      after every check passed: each changed file in exactly one layer, each layer under the
      limits, last tree == HEAD's tree, no existing branch (--force overwrites, never a branch
      checked out in a worktree). Never touches the worktree, the index or the current branch.
      --submit: gh stack init + gh stack submit --auto --open in a throwaway worktree, then
      gh pr edit (title, body, assignee) on each PR; prints one PR=<url> line per layer.
"""
import argparse, json, os, re, shutil, subprocess, sys, tempfile

WORKFLOW = ".github/workflows/pr-size-limit.yml"
DEFAULTS = {"MAX_FILES": 20, "MAX_LINES": 500,
            "EXCLUDE_REGEX": r"^spec/|^test/|^cypress/|(^|/)__tests__/|_spec[.]rb$|_test[.]rb$"
                             r"|[.](spec|test)[.](js|jsx|ts|tsx)$|^db/schema[.]rb$|^db/structure[.]sql$"}


def die(msg):
    sys.exit(f"ERROR: {msg}")


def git(*args, env=None, input=None):
    r = subprocess.run(["git", *args], capture_output=True, text=True, env=env, input=input)
    if r.returncode != 0:
        die(f"git {' '.join(args[:2])} : {r.stderr.strip()}")
    return r.stdout


def limits():
    """MAX_FILES / MAX_LINES / EXCLUDE_REGEX from the repo's workflow, else the defaults."""
    lim = dict(DEFAULTS)
    try:
        text = open(WORKFLOW).read()
    except OSError:
        return lim
    for key in lim:
        m = re.search(rf"^\s*{key}:\s*(?:'((?:[^']|'')*)'|\"([^\"]*)\"|(\S+))", text, re.M)
        if m:
            value = next(g for g in m.groups() if g is not None).replace("''", "'")
            lim[key] = value if key == "EXCLUDE_REGEX" else int(value)
    return lim


def merge_base(base):
    r = subprocess.run(["git", "merge-base", base, "HEAD"], capture_output=True, text=True)
    if r.returncode != 0:
        die(f"pas de base commune avec {base} (git fetch origin ?)")
    return r.stdout.strip()


def numstat(a, b):
    """[(path, lines, old_path or None)] of a..b, renames detected like GitHub's PR file list."""
    out, entries, i = git("diff", "--numstat", "-z", "-M", a, b).split("\0"), [], 0
    while i < len(out) and out[i]:
        added, deleted, path = out[i].split("\t", 2)
        old = None
        if not path:  # rename: "added\tdeleted\t\0old\0new\0"
            old, path, i = out[i + 1], out[i + 2], i + 2
        entries.append((path, sum(int(n) for n in (added, deleted) if n != "-"), old))
        i += 1
    return entries


def count(entries, rx):
    """Same rule as the workflow's awk: files not matching EXCLUDE_REGEX, additions + deletions."""
    kept = [n for path, n, _ in entries if not rx.search(path)]
    return len(kept), sum(kept)


def over(files, lines, lim):
    return files > lim["MAX_FILES"] or lines > lim["MAX_LINES"]


def cmd_size(base):
    lim = limits()
    rx, entries = re.compile(lim["EXCLUDE_REGEX"]), numstat(merge_base(base), "HEAD")
    files, lines = count(entries, rx)
    is_over = over(files, lines, lim)
    print(f"FILES={files} LINES={lines} MAX_FILES={lim['MAX_FILES']} MAX_LINES={lim['MAX_LINES']} OVER={int(is_over)}")
    if is_over:
        for path, n, old in sorted(entries, key=lambda e: e[0]):
            print(f"{'-' if rx.search(path) else n} {path}" + (f" (renamed from {old})" if old else ""))


def checked_out_branches():
    return {line[len("branch refs/heads/"):] for line in git("worktree", "list", "--porcelain").splitlines()
            if line.startswith("branch refs/heads/")}


def cmd_split(plan_path, submit_too, force):
    plan = json.load(sys.stdin if plan_path == "-" else open(plan_path))
    base, layers = plan.get("base", "origin/develop"), plan.get("layers") or []
    if len(layers) < 2:
        die("le plan doit avoir au moins 2 couches")
    lim = limits()
    rx, start, head = re.compile(lim["EXCLUDE_REGEX"]), merge_base(base), git("rev-parse", "HEAD").strip()
    changed = numstat(start, head)
    # A rename is one unit: its new path is the key, its old path an accepted alias.
    key_of = {alias: path for path, _, old in changed for alias in (path, old) if alias}
    paths_of = {path: [p for p in (old, path) if p] for path, _, old in changed}

    errors, layer_of = [], {}
    for i, layer in enumerate(layers, 1):
        if not layer.get("files"):
            errors.append(f"couche {i} : aucun fichier")
        for f in layer.get("files") or []:
            key = key_of.get(f)
            if key is None:
                errors.append(f"couche {i} : {f} n'est pas modifié entre {base} et HEAD")
            elif layer_of.setdefault(key, i) != i:
                errors.append(f"{key} est dans les couches {layer_of[key]} et {i}")
    errors += [f"{path} n'est dans aucune couche" for path in paths_of if path not in layer_of]

    names, busy = [layer.get("branch", "") for layer in layers], checked_out_branches()
    for name in names:
        if subprocess.run(["git", "check-ref-format", "--branch", name], capture_output=True).returncode:
            errors.append(f"nom de branche invalide : {name!r}")
        elif names.count(name) > 1:
            errors.append(f"branche en double dans le plan : {name}")
        elif name in busy:
            errors.append(f"{name} est checkée dans un worktree : jamais écrasée")
        elif not force and not subprocess.run(["git", "show-ref", "--verify", "--quiet", f"refs/heads/{name}"]).returncode:
            errors.append(f"la branche {name} existe déjà (--force pour l'écraser)")
    if errors:
        die("plan refusé, rien n'a été écrit :\n  " + "\n  ".join(dict.fromkeys(errors)))

    # Build the commits with a throwaway index: the user's index and worktree are never read or written.
    tree_at_head = {}
    for rec in git("ls-tree", "-r", "-z", "--full-tree", head).split("\0"):
        if rec:
            meta, path = rec.split("\t", 1)
            tree_at_head[path] = meta  # "<mode> <type> <sha>", fed back as-is to --index-info
    zero = "0" * len(head)
    tmp = tempfile.mkdtemp(prefix="ws-stack-")
    env = {**os.environ, "GIT_INDEX_FILE": os.path.join(tmp, "index")}
    built, parent = [], start
    try:
        git("read-tree", start, env=env)
        for i, layer in enumerate(layers, 1):
            keys = sorted({key_of[f] for f in layer["files"]})
            info = "".join(f"{tree_at_head[p]}\t{p}\0" if p in tree_at_head else f"0 {zero}\t{p}\0"
                           for k in keys for p in paths_of[k])  # mode 0 = remove the path
            git("update-index", "-z", "--index-info", env=env, input=info)
            tree = git("write-tree", env=env).strip()
            commit = git("commit-tree", tree, "-p", parent, "-m", layer.get("title") or layer["branch"]).strip()
            files, lines = count(numstat(parent, commit), rx)
            if over(files, lines, lim):
                errors.append(f"couche {i} ({layer['branch']}) : {files} fichiers / {lines} lignes, "
                              f"max {lim['MAX_FILES']} / {lim['MAX_LINES']}")
            built.append((layer, commit, files, lines))
            parent = commit
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if git("rev-parse", f"{parent}^{{tree}}").strip() != git("rev-parse", f"{head}^{{tree}}").strip():
        errors.append("l'arbre de la dernière couche diffère de celui de HEAD")
    if errors:
        die("plan refusé, rien n'a été écrit :\n  " + "\n  ".join(errors))

    verb = "update" if force else "create"
    git("update-ref", "--stdin", input="".join(f"{verb} refs/heads/{layer['branch']} {commit}\n"
                                               for layer, commit, *_ in built))  # atomic: all or none
    for i, (layer, commit, files, lines) in enumerate(built, 1):
        print(f"LAYER={i} BRANCH={layer['branch']} FILES={files} LINES={lines} COMMIT={commit[:10]}")
    print(f"OK: {len(built)} branches créées depuis {start[:10]}, branche courante et worktree inchangés")
    if submit_too:
        submit(base, plan.get("assignee"), [layer for layer, *_ in built])


def submit(base, assignee, layers):
    """gh stack init + submit from a throwaway worktree on the top branch (init checks out the
    last branch: never in the user's checkout), then title / body / assignee on every PR."""
    trunk = re.sub(r"^(refs/remotes/)?origin/", "", base)
    names = [layer["branch"] for layer in layers]
    tmp = tempfile.mkdtemp(prefix="ws-stack-")
    wt, env = os.path.join(tmp, "wt"), {**os.environ, "GH_STACK_NO_UPDATE_NOTIFIER": "1"}

    def gh(*args, input=""):  # stdin/stdout are pipes: gh stack never opens its TUI
        return subprocess.run(["gh", *args], cwd=wt, env=env, input=input, capture_output=True, text=True)

    git("-c", "core.hooksPath=/dev/null", "worktree", "add", "--quiet", wt, names[-1])
    try:
        r = gh("stack", "init", "--base", trunk, *names)
        if r.returncode:
            die(f"gh stack init (exit {r.returncode}) : {r.stderr.strip()}")
        r = gh("stack", "submit", "--auto", "--open", "--remote", "origin")
        submit_rc, submit_err = r.returncode, (r.stderr or r.stdout).strip()
        for layer in layers:
            branch = layer["branch"]
            url = gh("pr", "view", branch, "--json", "url", "--jq", ".url").stdout.strip()
            if not url:
                print(f"PR=- BRANCH={branch} (pas de PR)")
                continue
            e = gh("pr", "edit", branch, "--title", layer.get("title") or branch, "--body-file", "-",
                   *(["--add-assignee", assignee] if assignee else []), input=layer.get("body") or "")
            print(f"PR={url} BRANCH={branch}" + (f" EDIT_FAILED={e.stderr.strip()[:200]}" if e.returncode else ""))
        if submit_rc == 9:
            die("Stacked PRs non activés sur ce repo (gh stack exit 9) : créer les PR à la main, chacune "
                "sur la couche précédente (gh pr create --base <couche-1> --head <couche>)")
        if submit_rc:
            die(f"gh stack submit (exit {submit_rc}) : {submit_err}")
    finally:
        subprocess.run(["git", "worktree", "remove", "--force", wt], capture_output=True)
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("size")
    s.add_argument("--base", default="origin/develop")
    p = sub.add_parser("split")
    p.add_argument("plan")
    p.add_argument("--submit", action="store_true")
    p.add_argument("--force", action="store_true")
    a = ap.parse_args()
    top = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    if top.returncode:
        die("pas dans un repo git")
    plan = None if a.cmd == "size" else a.plan if a.plan == "-" else os.path.abspath(a.plan)
    os.chdir(top.stdout.strip())
    cmd_size(a.base) if a.cmd == "size" else cmd_split(plan, a.submit, a.force)


if __name__ == "__main__":
    main()
