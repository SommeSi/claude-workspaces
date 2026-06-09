#!/bin/bash
# ws-finish-preflight.sh — ONE read-only call that does ALL the thinking for
# /finish: detect the workspace from $PWD, run every safety check across repos,
# and print a ready-to-show recap plus a machine block the caller passes
# straight to ws-destroy.sh.
#
# Usage: ws-finish-preflight.sh [path]      (defaults to $PWD)
#
# Never destroys anything. The LLM runs this, shows the RECAP verbatim, asks ONE
# y/N, then on yes runs ws-destroy.sh with the WS_* vars from the MACHINE block.
#
# Output:
#   <human recap>
#   ===WS-FINISH-MACHINE===
#   WS_SLOT=...        WS_PATH=...     WS_SLUG=...      WS_MODE=...
#   WS_PROJECT_ROOT=... WS_CONFIG=...  WS_PORTS=...     OVERALL=safe|warn|none

set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-$PWD}"

CHECK_MERGED="$HERE/ws-check-merged.sh" \
TARGET="$TARGET" \
python3 <<'PYEOF'
import json, os, re, subprocess, sys

REG = os.path.expanduser("~/.claude-workspaces/registry.json")
target = os.path.realpath(os.environ["TARGET"])
check_merged = os.environ["CHECK_MERGED"]

# Transient files we never warn about (always present in worktrees).
NOISE = (
    re.compile(r'(^|/)\.env\.local(\..*)?$'),
    re.compile(r'(^|/)\.vscode(/|$)'),
    re.compile(r'(^|/)\.idea(/|$)'),
    re.compile(r'(^|/)\.DS_Store$'),
    re.compile(r'(^|/)config/database\.yml$'),          # rewritten by ws-db-isolate every worktree
    re.compile(r'(^|/)db/(cable|cache|queue)_schema\.rb$'),  # Solid adapter schema dumps, regenerated per worktree
)

def is_noise(path):
    return any(p.search(path) for p in NOISE)

def sh(args):
    try:
        return subprocess.run(args, capture_output=True, text=True).stdout.strip()
    except Exception:
        return ""

# --- Load registry ------------------------------------------------------
if not os.path.isfile(REG):
    print("ERROR: no registry — no workspaces to finish.")
    print("===WS-FINISH-MACHINE===")
    print("OVERALL=none")
    sys.exit(0)

reg = json.load(open(REG))
workspaces = reg.get("workspaces", {})

# --- Detect workspace: longest workspace_path that is a prefix of target -
match = None
best = -1
for slot, w in workspaces.items():
    wp = os.path.realpath(w.get("workspace_path", "") or "")
    if not wp:
        continue
    if target == wp or target.startswith(wp + os.sep):
        if len(wp) > best:
            best = len(wp)
            match = (slot, w)

if match is None:
    print("No workspace matches the current directory.")
    print("Existing workspaces:")
    for slot, w in sorted(workspaces.items(), key=lambda kv: kv[0]):
        print(f"  w{slot}  {w.get('slug','?'):<28} {w.get('mode','?'):<9} "
              f"{w.get('workspace_path','?')}")
    print("===WS-FINISH-MACHINE===")
    print("OVERALL=none")
    sys.exit(0)

slot, w = match
ws_path = w.get("workspace_path", "")
slug = w.get("slug", "?")
mode = w.get("mode", "?")
project_root = w.get("project_root") or ""
repos = w.get("repos", []) or []
emoji = w.get("emoji", "")

# --- Locate config (for origins + pre_destroy hook) ---------------------
config_path = ""
for d in (project_root, ws_path):
    if d and os.path.isfile(os.path.join(d, ".claude-workspaces.json")):
        config_path = os.path.join(d, ".claude-workspaces.json")
        break

# --- Per-repo safety checks (parallel — the merge check does a git fetch) -
import concurrent.futures

warnings = []        # human lines
overall = "safe"
ports = []
ws_exists = os.path.isdir(ws_path)
# In attached mode the directory is preserved, so no code/branch is ever lost —
# safety checks (uncommitted/unmerged) are irrelevant there.
will_delete = ws_exists and ws_path != project_root
checked = 0          # repos we could actually inspect
missing_repos = []   # repos whose dir is gone

for r in repos:
    if r.get("port"):
        ports.append(str(r["port"]))


def check_repo(r):
    """Run a repo's safety checks. Returns (name, missing, warn, lines)."""
    name = r.get("name", "?")
    path = r.get("path", "")
    if not path or not os.path.isdir(path):
        return (name, True, False, [])

    warn = False
    lines = []

    # 1. Uncommitted (filtered)
    # NB: do NOT strip — porcelain v1 has 2 status cols + a space, so the path
    # starts at index 3. Stripping would shift the first line's columns.
    status = subprocess.run(
        ["git", "-C", path, "status", "--short"],
        capture_output=True, text=True).stdout
    dirty = []
    for line in status.splitlines():
        if not line:
            continue
        f = line[3:] if len(line) > 3 else line
        f = f.split(" -> ")[-1].strip().strip('"')
        if f and not is_noise(f):
            dirty.append(line.rstrip())
    if dirty:
        warn = True
        lines.append(f"  ⚠ {name}: {len(dirty)} uncommitted change(s) will be LOST:")
        for d in dirty[:12]:
            lines.append(f"        {d}")
        if len(dirty) > 12:
            lines.append(f"        … +{len(dirty) - 12} more")

    # 2. Unmerged branch (worktree mode only)
    if mode == "worktree":
        branch = sh(["git", "-C", path, "rev-parse", "--abbrev-ref", "HEAD"])
        if not branch or branch == "HEAD":
            branch = w.get("branch") or ""   # fallback: registry branch (detached HEAD)
        if branch and branch != "HEAD":
            res = subprocess.run([check_merged, path, branch],
                                 capture_output=True, text=True)
            info = {}
            for line in res.stdout.splitlines():
                if "=" in line:
                    k, v = line.split("=", 1)
                    info[k] = v
            st = info.get("STATUS", "unknown")
            if st == "unmerged":
                warn = True
                lines.append(
                    f"  ⚠ {name}: branch '{branch}' NOT merged into "
                    f"{info.get('BASE','base')} "
                    f"({info.get('COMMITS_AHEAD','?')} commit(s) ahead):")
                for c in (info.get("UNMERGED_COMMITS", "") or "").split(";"):
                    if c.strip():
                        lines.append(f"        {c.strip()}")
            elif st == "unknown":
                warn = True
                lines.append(
                    f"  ⚠ {name}: could not verify merge state "
                    f"({info.get('REASON','?')})")
            # st == safe → silent, nothing to warn about

    return (name, False, warn, lines)


if will_delete and repos:
    # Fan out: the merge check fetches per repo, so run repos concurrently.
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(8, len(repos))) as ex:
        results = list(ex.map(check_repo, repos))   # preserves repo order
    for name, missing, warn, lines in results:
        if missing:
            missing_repos.append(name)
            continue
        checked += 1
        if warn:
            overall = "warn"
        warnings.extend(lines)

# --- Build human recap --------------------------------------------------
repo_lines = []
for r in repos:
    p = r.get("port")
    repo_lines.append(f"    {r.get('name','?'):<10} {('port '+str(p)) if p else ''}")

print(f"{emoji} Finish workspace w{slot} — {slug}")
print()
print(f"  Mode   : {mode}")
print(f"  Path   : {ws_path}")
if mode != "worktree" and ws_path == project_root:
    print("  Repos  : (attached — directory will be PRESERVED, only the slot is freed)")
else:
    print("  Repos  :")
    print("\n".join(repo_lines))
print()

missing_note = ("  Note: repo dir(s) missing, skipped: " + ", ".join(missing_repos)) if missing_repos else ""

if not ws_exists:
    # Stale registry entry — the directory is already gone.
    print("  Safety check: ↷ workspace directory no longer exists on disk.")
    print("    Nothing to delete — finishing will just free the registry slot.")
elif not will_delete:
    # Attached mode — directory preserved, nothing is lost.
    print("  Safety check: ✓ attached — directory preserved, no code or branch is lost.")
elif warnings:
    print("  Safety check:")
    print("\n".join(warnings))
    if missing_note:
        print(missing_note)
elif checked == 0:
    print("  Safety check: ↷ no repo directories found to inspect (registry may be stale).")
else:
    print(f"  Safety check: ✓ verified {checked} repo(s) — all committed & merged, nothing will be lost.")
    if missing_note:
        print(missing_note)
print()

# What the cleanup will do
print("  Cleanup will:")
if ports:
    print(f"    • kill processes on port(s): {', '.join(ports)}")
if not ws_exists:
    print(f"    • free slot w{slot} (directory already gone)")
elif mode == "worktree":
    print("    • drop isolated _w%s databases" % slot)
    print("    • git worktree remove each repo")
    print(f"    • delete {ws_path}")
    print(f"    • free slot w{slot} in the registry")
elif ws_path == project_root:
    print("    • free the slot (directory PRESERVED — attached mode)")
else:
    print(f"    • delete {ws_path}")
    print(f"    • free slot w{slot} in the registry")
print()
if overall == "warn":
    print("  ⚠ This is IRREVERSIBLE and you have unsaved/unmerged work above.")
elif not ws_exists:
    print("  Safe — only a stale registry slot will be freed.")
elif not will_delete:
    print("  Safe — only the registry slot is freed; your files stay untouched.")
else:
    print("  This is irreversible.")

# --- Machine block ------------------------------------------------------
print("===WS-FINISH-MACHINE===")
print(f"WS_SLOT={slot}")
print(f"WS_PATH={ws_path}")
print(f"WS_SLUG={slug}")
print(f"WS_MODE={mode}")
print(f"WS_PROJECT_ROOT={project_root}")
print(f"WS_CONFIG={config_path}")
print(f"WS_PORTS={','.join(ports)}")
print(f"OVERALL={overall}")
PYEOF
