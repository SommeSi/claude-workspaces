#!/usr/bin/env bash
# ws-progress-capture.sh — Append a meaningful progress entry to the workspace's
# CLAUDE.local.md whenever a Claude session stops or compacts.
#
# Registered as a Stop + PostCompact hook. Replaces the legacy
# ~/.claude/scripts/auto-capture-context.sh (which silently failed in worktrees
# and always fell back to empty "Session marker" timestamps).
#
# Fixes vs legacy:
#   - Finds the workspace root by walking up from PWD (or via registry) instead
#     of requiring CLAUDE.local.md at PWD exactly
#   - Uses .last_assistant_message (the actual field Claude Code sends) as the
#     summary, falling back to .transcript_path for a tail read
#   - Captures git state (branch, changed files, last commit) so resuming after
#     a reboot gives real context
#   - Deduplicates: replaces the last entry if it was written < 5 min ago, to
#     prevent hundreds of near-identical markers
#
# Input: hook event JSON on stdin.

set -e
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

LOG_DIR="$HOME/.claude/logs"
mkdir -p "$LOG_DIR"
DEBUG_LOG="$LOG_DIR/ws-progress-debug.log"

INPUT=$(cat || true)

# --- 1. Find the workspace root CLAUDE.local.md ---
WS_ROOT=""
dir="$PWD"
while [ "$dir" != "/" ]; do
  if [ -f "$dir/CLAUDE.local.md" ] && grep -q '^## Workspace info' "$dir/CLAUDE.local.md" 2>/dev/null; then
    WS_ROOT="$dir"
    break
  fi
  dir="$(dirname "$dir")"
done

# Fallback: ask the registry
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

[ -z "$WS_ROOT" ] && exit 0
CLAUDE_MD="$WS_ROOT/CLAUDE.local.md"
[ ! -f "$CLAUDE_MD" ] && exit 0

# --- 2. Extract the actual summary from the hook payload ---
SUMMARY=""
if [ -n "$INPUT" ] && command -v jq &>/dev/null; then
  SUMMARY=$(echo "$INPUT" | jq -r '
    .last_assistant_message //
    .summary //
    .compaction.summary //
    .transcript //
    .content //
    empty
  ' 2>/dev/null)
  # If last_assistant_message isn't in the payload but transcript_path is,
  # read the last assistant message from the transcript JSONL
  if [ -z "$SUMMARY" ] || [ "$SUMMARY" = "null" ]; then
    TP=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
    if [ -n "$TP" ] && [ -f "$TP" ]; then
      SUMMARY=$(tail -n 200 "$TP" | python3 -c "
import sys, json
last = ''
for line in sys.stdin:
    try:
        ev = json.loads(line)
        if ev.get('type') == 'assistant':
            msg = ev.get('message', {})
            for block in msg.get('content', []) if isinstance(msg.get('content'), list) else []:
                if block.get('type') == 'text':
                    last = block.get('text', '') or last
    except Exception:
        pass
print(last.strip()[:1500])
" 2>/dev/null || true)
    fi
  fi
fi

# Clean + trim summary
if [ -n "$SUMMARY" ] && [ "$SUMMARY" != "null" ]; then
  SUMMARY=$(echo "$SUMMARY" | python3 -c "
import sys, re
t = sys.stdin.read().strip()
# Strip workspace badge first line
t = re.sub(r'^\S+\s*\*\*\[w\d+\][^\n]*\n+', '', t, count=1)
# Take first ~1500 chars
print(t[:1500])
" 2>/dev/null || true)
fi

# --- 3. Capture git state for each repo in the workspace ---
GIT_STATE=""
while IFS= read -r repo_path; do
  [ -z "$repo_path" ] && continue
  [ ! -d "$repo_path/.git" ] && [ ! -f "$repo_path/.git" ] && continue
  name=$(basename "$repo_path")
  branch=$(git -C "$repo_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')
  changed=$(git -C "$repo_path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  ahead=$(git -C "$repo_path" rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo '?')
  last_msg=$(git -C "$repo_path" log -1 --pretty='%s' 2>/dev/null || echo '')
  GIT_STATE="$GIT_STATE- **$name** \`$branch\` — $changed changed, $ahead ahead of upstream. Last: $last_msg"$'\n'
done < <(find "$WS_ROOT" -maxdepth 2 -name .git -print0 2>/dev/null | xargs -0 -n1 dirname 2>/dev/null | sort -u)

# --- 4. Build the new entry ---
TS=$(date '+%Y-%m-%d %H:%M')
ENTRY=""
if [ -n "$SUMMARY" ] && [ "$SUMMARY" != "null" ]; then
  ENTRY=$(printf '### Progress — %s\n\n%s\n\n**Repos**:\n%s\n' "$TS" "$SUMMARY" "$GIT_STATE")
else
  ENTRY=$(printf '### Progress — %s\n\n_(no assistant summary captured)_\n\n**Repos**:\n%s\n' "$TS" "$GIT_STATE")
fi

# --- 5. Dedup: if last entry is younger than 5 min, replace it ---
WS_CLAUDE_MD="$CLAUDE_MD" WS_ENTRY="$ENTRY" python3 <<'PYEOF'
import os, re, datetime

md = os.environ['WS_CLAUDE_MD']
entry = os.environ['WS_ENTRY'].rstrip() + '\n'

with open(md) as f:
    content = f.read()

now = datetime.datetime.now()

def keep_existing(last_ts_str: str) -> bool:
    try:
        last = datetime.datetime.strptime(last_ts_str, '%Y-%m-%d %H:%M')
        return (now - last).total_seconds() < 300  # 5 min
    except Exception:
        return False

# Find the last '### Progress — <ts>' heading block
pattern = re.compile(
    r'(###\s+Progress\s+—\s+)(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2})(.*?)(?=\n###\s|\Z)',
    re.DOTALL,
)
matches = list(pattern.finditer(content))
if matches and keep_existing(matches[-1].group(2)):
    new_content = content[:matches[-1].start()] + entry
else:
    if content and not content.endswith('\n'):
        content += '\n'
    new_content = content + '\n' + entry

with open(md, 'w') as f:
    f.write(new_content)
PYEOF

# Debug log (bounded)
{
  echo "---"
  echo "TIME: $TS"
  echo "WS_ROOT: $WS_ROOT"
  echo "SUMMARY_LEN: ${#SUMMARY}"
} >> "$DEBUG_LOG"
if [ -f "$DEBUG_LOG" ] && [ "$(wc -l < "$DEBUG_LOG")" -gt 500 ]; then
  tail -n 300 "$DEBUG_LOG" > "$DEBUG_LOG.tmp" && mv "$DEBUG_LOG.tmp" "$DEBUG_LOG"
fi
