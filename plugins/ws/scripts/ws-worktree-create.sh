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

# --- Timing helper (debug) ---
# Usage: t "step description" — prints to stderr.
# python3 fallback for ms precision (macOS /bin/bash is 3.2, no EPOCHREALTIME).
WS_T0=$(python3 -c 'import time; print(int(time.time()*1000))')
WS_TLAST=$WS_T0
t() {
  local now
  now=$(python3 -c 'import time; print(int(time.time()*1000))')
  printf '[Δ %5dms │ Σ %6dms] ws-worktree: %s\n' "$((now - WS_TLAST))" "$((now - WS_T0))" "$*" >&2
  WS_TLAST=$now
}
export WS_T0  # so clone_one subshells can compute Σ relative to script start

WS_PATH="$1"
BRANCH="$2"
PROJECT_ROOT="$3"
t "start (ws=$WS_PATH branch=$BRANCH)"

CONFIG="$PROJECT_ROOT/.claude-workspaces.json"
LOCAL_CONFIG="$PROJECT_ROOT/.claude-workspaces.local.json"

[ -f "$CONFIG" ] || { echo "❌ Config not found: $CONFIG" >&2; exit 1; }

mkdir -p "$WS_PATH"

# Read repos (merge local overrides).
# Optional repos (\"optional\": true in config) are skipped by default and only
# created when their name appears in the WS_INCLUDE env var (comma-separated).
# This is THE decision point for which worktree dirs get created — everything
# downstream (generate-files docs, registry, db-isolate) keys off this set.
REPOS_JSON=$(WS_INCLUDE="${WS_INCLUDE:-}" python3 -c "
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
include = set(n.strip() for n in os.environ.get('WS_INCLUDE', '').split(',') if n.strip())
active = [r for r in repos.values() if not r.get('optional') or r.get('name') in include]
print(json.dumps(active))
")
t "config parsed"

# Per-repo timing helper — writes to the same log file, includes Σ since script start.
_t_repo() {
  local name="$1"
  local msg="$2"
  local now
  now=$(python3 -c 'import time; print(int(time.time()*1000))')
  printf '[Δ ----- │ Σ %6dms] ws-worktree[%s]: %s\n' "$((now - WS_T0))" "$name" "$msg" >&2
}

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
      _t_repo "$NAME" "skipped (already exists)"
      exit 0
    fi

    echo "  → $NAME: creating worktree"
    _t_repo "$NAME" "begin worktree add"

    # Try in order: new branch, existing-local, remote-tracking.
    # Capture stderr of each attempt — if all 3 fail we surface them so the
    # user can see WHY (e.g. ref conflict, dirty index, network error).
    # Previously these errors were silenced with 2>/dev/null which hid real
    # bugs like the "refs/heads/feat/ats exists; cannot create
    # refs/heads/feat/ats/sub" git ref-collision case.
    OUT1="" OUT2="" OUT3=""
    if OUT1=$(git -C "$ORIGIN_ABS" worktree add -b "$BRANCH" "$WT_PATH" 2>&1); then
      [ -n "$OUT1" ] && echo "$OUT1"
      _t_repo "$NAME" "worktree add -b OK (new branch)"
    elif OUT2=$(git -C "$ORIGIN_ABS" worktree add "$WT_PATH" "$BRANCH" 2>&1); then
      [ -n "$OUT2" ] && echo "$OUT2"
      _t_repo "$NAME" "worktree add OK (existing local branch)"
    else
      _t_repo "$NAME" "fetch origin $BRANCH (network)"
      git -C "$ORIGIN_ABS" fetch origin "$BRANCH" 2>/dev/null || true
      _t_repo "$NAME" "fetch done; worktree add --track"
      if OUT3=$(git -C "$ORIGIN_ABS" worktree add --track -b "$BRANCH" "$WT_PATH" "origin/$BRANCH" 2>&1); then
        [ -n "$OUT3" ] && echo "$OUT3"
        _t_repo "$NAME" "worktree add --track OK"
      else
        echo "  ✗ $NAME: all 3 worktree-add attempts failed for branch $BRANCH"
        echo "    [1] git worktree add -b $BRANCH $WT_PATH"
        echo "$OUT1" | sed 's/^/        /'
        echo "    [2] git worktree add $WT_PATH $BRANCH"
        echo "$OUT2" | sed 's/^/        /'
        echo "    [3] git worktree add --track -b $BRANCH $WT_PATH origin/$BRANCH"
        echo "$OUT3" | sed 's/^/        /'
        _t_repo "$NAME" "FAILED (see error details above)"
        exit 1
      fi
    fi

    # Pull base branch (best-effort — don't fail if no remote / no upstream)
    _t_repo "$NAME" "git pull origin develop|main (network)"
    (cd "$WT_PATH" && git pull origin develop 2>/dev/null) \
      || (cd "$WT_PATH" && git pull origin main 2>/dev/null) \
      || true
    _t_repo "$NAME" "pull done"

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
t "fan-out: ${#PIDS[@]} repo(s) launched in parallel"

# Fan-in: wait for all, then stream logs in stable order
FAIL=0
for i in "${!PIDS[@]}"; do
  if ! wait "${PIDS[$i]}"; then
    FAIL=1
  fi
done
t "fan-in: all clones done"

for i in "${!LOGS[@]}"; do
  cat "${LOGS[$i]}"
done

[ "$FAIL" -eq 0 ] || exit 1

echo "  ✓ All worktrees created"
t "DONE"
