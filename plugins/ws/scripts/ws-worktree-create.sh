#!/bin/bash
# ws-worktree-create.sh — Create git worktrees for every repo in .claude-workspaces.json
# Usage: ws-worktree-create <workspace_path> <branch> <project_root>
#
# For each repo:
#   - Resolves origin relative to project_root
#   - Creates a worktree at <workspace_path>/<repo.name>
#   - Auto-selects new-branch / existing-local / existing-remote variants
#   - Pulls the base branch (develop → main → noop) to start up-to-date
#
# Idempotent: existing worktrees are detected and skipped.
# Repos are processed in PARALLEL — fetches + worktree adds run concurrently.

set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

WS_PATH="$1"
BRANCH="$2"
PROJECT_ROOT="$3"

CONFIG="$PROJECT_ROOT/.claude-workspaces.json"
LOCAL_CONFIG="$PROJECT_ROOT/.claude-workspaces.local.json"

[ -f "$CONFIG" ] || { echo "❌ Config not found: $CONFIG" >&2; exit 1; }

mkdir -p "$WS_PATH"

# Read repos (merge local overrides)
REPOS_JSON=$(python3 -c "
import json, os, sys
cfg = json.load(open('$CONFIG'))
repos = {r['name']: dict(r) for r in cfg.get('repos', [])}
lf = '$LOCAL_CONFIG'
if os.path.isfile(lf):
    try:
        local = json.load(open(lf))
        for name, overrides in (local.get('repos') or {}).items():
            if name in repos:
                repos[name].update(overrides)
    except Exception:
        pass
print(json.dumps(list(repos.values())))
")

# Worker: clone one repo. Runs in background subshell.
clone_one() {
  local NAME="$1"
  local ORIGIN="$2"
  local LOG="$3"

  {
    # Resolve absolute origin path
    if [ "$ORIGIN" = "." ]; then
      ORIGIN_ABS="$PROJECT_ROOT"
    else
      ORIGIN_ABS="$(cd "$PROJECT_ROOT" && cd "$ORIGIN" 2>/dev/null && pwd)" || {
        echo "  ✗ $NAME: origin not found ($ORIGIN relative to $PROJECT_ROOT)"
        exit 1
      }
    fi

    WT_PATH="$WS_PATH/$NAME"

    if [ -d "$WT_PATH/.git" ] || [ -f "$WT_PATH/.git" ]; then
      echo "  ↷ $NAME: already exists at $WT_PATH"
      exit 0
    fi

    echo "  → $NAME: creating worktree"

    # Try: new branch first; fallback to existing-local; fallback to remote tracking
    if git -C "$ORIGIN_ABS" worktree add -b "$BRANCH" "$WT_PATH" 2>/dev/null; then
      :
    elif git -C "$ORIGIN_ABS" worktree add "$WT_PATH" "$BRANCH" 2>/dev/null; then
      :
    else
      git -C "$ORIGIN_ABS" fetch origin "$BRANCH" 2>/dev/null || true
      if ! git -C "$ORIGIN_ABS" worktree add --track -b "$BRANCH" "$WT_PATH" "origin/$BRANCH" 2>/dev/null; then
        echo "  ✗ $NAME: failed to create worktree for $BRANCH"
        exit 1
      fi
    fi

    # Pull base branch (best-effort — don't fail if no remote / no upstream)
    (cd "$WT_PATH" && git pull origin develop 2>/dev/null) \
      || (cd "$WT_PATH" && git pull origin main 2>/dev/null) \
      || true

    echo "  ✓ $NAME ready"
  } >"$LOG" 2>&1
}

TMPDIR_WT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_WT"' EXIT

# Fan-out: launch one background job per repo
PIDS=()
LOGS=()
NAMES=()
while IFS=$'\t' read -r NAME ORIGIN; do
  [ -z "$NAME" ] && continue
  LOG="$TMPDIR_WT/$NAME.log"
  LOGS+=("$LOG")
  NAMES+=("$NAME")
  clone_one "$NAME" "$ORIGIN" "$LOG" &
  PIDS+=($!)
done < <(echo "$REPOS_JSON" | python3 -c "
import json, sys
for r in json.load(sys.stdin):
    print(f\"{r['name']}\t{r.get('origin', '.')}\")")

# Fan-in: wait for all, then stream logs in stable order
FAIL=0
for i in "${!PIDS[@]}"; do
  if ! wait "${PIDS[$i]}"; then
    FAIL=1
  fi
done

for i in "${!LOGS[@]}"; do
  cat "${LOGS[$i]}"
done

[ "$FAIL" -eq 0 ] || exit 1

echo "  ✓ All worktrees created"
