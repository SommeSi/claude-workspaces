#!/usr/bin/env bash
# ws-checkpoint.sh — Record a progress checkpoint to the workspace's CLAUDE.local.md.
#
# Claude invokes this itself at natural milestones (task done, blocker found,
# decision made, etc.) so that after a reboot or compaction, the workspace has
# a running log of what actually happened — not just empty session markers.
#
# Usage: ws-checkpoint.sh "<message>"
#
# The message should be 1–3 concise sentences describing what was just done
# or decided. Git state (branch, changed files, last commit) is captured
# automatically for every repo in the workspace.
#
# Auto-detects the workspace from PWD using the registry. If invoked from
# outside any workspace, exits with an explanatory error.

set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

MSG="${1:-}"
if [ -z "$MSG" ]; then
  cat >&2 <<EOF
Usage: ws-checkpoint.sh "<message>"

Example:
  ws-checkpoint.sh "Finished writing ws-db-isolate.sh. Regex bug fixed, dry-run OK on w6. Next: test actual db:create."
EOF
  exit 1
fi

# --- Find workspace root ---
WS_ROOT=""
dir="$PWD"
while [ "$dir" != "/" ]; do
  if [ -f "$dir/CLAUDE.local.md" ] && grep -q '^## Workspace info' "$dir/CLAUDE.local.md" 2>/dev/null; then
    WS_ROOT="$dir"
    break
  fi
  dir="$(dirname "$dir")"
done

if [ -z "$WS_ROOT" ] && [ -f "$HOME/.claude-workspaces/registry.json" ]; then
  WS_ROOT=$(python3 -c "
import json, os
try:
    reg = json.load(open(os.path.expanduser('~/.claude-workspaces/registry.json')))
    cwd = os.getcwd()
    best_len = 0
    best = None
    for slot, ws in reg.get('workspaces', {}).items():
        wp = ws.get('workspace_path', '')
        paths = [wp] + [r.get('path', '') for r in ws.get('repos', [])]
        for p in paths:
            if p and (cwd == p or cwd.startswith(p + os.sep)) and len(p) > best_len:
                best_len = len(p)
                best = ws
    if best:
        print(best.get('workspace_path', ''))
except Exception:
    pass
" 2>/dev/null)
fi

if [ -z "$WS_ROOT" ] || [ ! -f "$WS_ROOT/CLAUDE.local.md" ]; then
  echo "❌ No workspace detected from $(pwd). Nothing written." >&2
  exit 1
fi

CLAUDE_MD="$WS_ROOT/CLAUDE.local.md"

# --- Capture git state across all repos ---
GIT_STATE=""
while IFS= read -r repo_path; do
  [ -z "$repo_path" ] && continue
  [ ! -d "$repo_path/.git" ] && [ ! -f "$repo_path/.git" ] && continue
  name=$(basename "$repo_path")
  branch=$(git -C "$repo_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')
  changed=$(git -C "$repo_path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  ahead=$(git -C "$repo_path" rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo '?')
  last_msg=$(git -C "$repo_path" log -1 --pretty='%s' 2>/dev/null || echo '')
  GIT_STATE="$GIT_STATE- \`$name\` \`$branch\` — $changed changed, $ahead ahead. Last: $last_msg"$'\n'
done < <(find "$WS_ROOT" -maxdepth 2 -name .git -print0 2>/dev/null | xargs -0 -n1 dirname 2>/dev/null | sort -u)

TS=$(date '+%Y-%m-%d %H:%M')

# --- Append entry under "## Progress log" section (create if missing) ---
WS_CLAUDE_MD="$CLAUDE_MD" WS_MSG="$MSG" WS_TS="$TS" WS_GIT="$GIT_STATE" python3 <<'PYEOF'
import os, re

md = os.environ['WS_CLAUDE_MD']
msg = os.environ['WS_MSG'].strip()
ts = os.environ['WS_TS']
git_state = os.environ['WS_GIT'].rstrip()

with open(md) as f:
    content = f.read()

entry = f"### {ts} — Checkpoint\n\n{msg}\n"
if git_state:
    entry += f"\n**Git state**:\n{git_state}\n"

header = "## Progress log"
if header in content:
    # Insert right after the header (top of the section, most recent first)
    idx = content.index(header)
    # Find the end of the header line
    nl = content.index('\n', idx)
    before = content[:nl + 1]
    after = content[nl + 1:]
    # Skip any leading blank lines after the header
    stripped = after.lstrip('\n')
    new_content = before + '\n' + entry + '\n' + stripped
else:
    if not content.endswith('\n'):
        content += '\n'
    new_content = content + f"\n{header}\n\n{entry}"

with open(md, 'w') as f:
    f.write(new_content)

print(f"✓ Checkpoint recorded at {ts} → {md}")
PYEOF
