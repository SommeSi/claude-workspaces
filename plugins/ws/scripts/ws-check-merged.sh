#!/bin/bash
# ws-check-merged.sh — Detect whether a branch is safe to delete.
#
# Usage: ws-check-merged.sh <repo_path> <branch>
#
# Strategy (in order):
#   1. `git fetch --quiet origin` (timeout 10s, non-fatal if offline).
#   2. If `gh` is available AND the repo has a github.com remote:
#        ask GitHub whether a PR for <branch> is in state MERGED.
#        This is the ONLY method that catches squash-merges with multiple commits.
#   3. Else (or no PR found): run `git cherry <base> HEAD` against the auto-detected
#        base (origin/develop, falling back to origin/main). Commits prefixed with
#        `-` are patch-equivalent on the base — i.e. merged, even via squash/rebase.
#        Only commits prefixed with `+` count as truly unmerged.
#
# Exit codes:
#   0  → SAFE — branch merged, or no commits ahead of base.
#   1  → UNMERGED — at least one commit not on base; block delete.
#   2  → UNKNOWN — could not determine (no base ref, no remote, etc.).
#
# Stdout (always, even on exit 1/2) — key=value lines for the caller to parse:
#   STATUS=safe|unmerged|unknown
#   REASON=<short human-readable reason>
#   METHOD=gh-pr|git-cherry|none
#   BASE=<base ref or '' >
#   COMMITS_AHEAD=<number>
#   UNMERGED_COMMITS=<short SHA + subject, semicolon-separated, may be empty>

set -uo pipefail

REPO="${1:-}"
BRANCH="${2:-}"

if [ -z "$REPO" ] || [ -z "$BRANCH" ]; then
  echo "STATUS=unknown"
  echo "REASON=missing args (repo, branch)"
  echo "METHOD=none"
  echo "BASE="
  echo "COMMITS_AHEAD=0"
  echo "UNMERGED_COMMITS="
  exit 2
fi

if [ ! -d "$REPO/.git" ] && [ ! -f "$REPO/.git" ]; then
  echo "STATUS=unknown"
  echo "REASON=not a git repo: $REPO"
  echo "METHOD=none"
  echo "BASE="
  echo "COMMITS_AHEAD=0"
  echo "UNMERGED_COMMITS="
  exit 2
fi

# --- 1. Fetch (best-effort, short timeout) -------------------------------
# Use a wrapper that kills git fetch if it hangs (offline / slow remote).
fetch_with_timeout() {
  local pid
  ( git -C "$REPO" fetch --quiet origin 2>/dev/null ) &
  pid=$!
  local waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge 10 ]; then
      kill -TERM "$pid" 2>/dev/null
      sleep 1
      kill -KILL "$pid" 2>/dev/null
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid" 2>/dev/null
}
fetch_with_timeout || true

# --- 2. gh PR check (primary, catches squash-merges) ---------------------
GH_REMOTE=""
if command -v gh >/dev/null 2>&1; then
  # Find a github.com origin URL on this repo
  REMOTE_URL=$(git -C "$REPO" remote get-url origin 2>/dev/null || true)
  case "$REMOTE_URL" in
    *github.com[:/]*)
      # Extract owner/repo from either ssh or https form
      GH_REMOTE=$(echo "$REMOTE_URL" \
        | sed -E 's#^git@github\.com:##; s#^https?://github\.com/##; s#\.git$##')
      ;;
  esac
fi

if [ -n "$GH_REMOTE" ]; then
  MERGED_PR=$(gh -R "$GH_REMOTE" pr list \
    --head "$BRANCH" \
    --state merged \
    --json number,mergedAt \
    --jq '.[0].number // empty' 2>/dev/null || true)
  if [ -n "$MERGED_PR" ]; then
    echo "STATUS=safe"
    echo "REASON=PR #$MERGED_PR merged on $GH_REMOTE"
    echo "METHOD=gh-pr"
    echo "BASE="
    echo "COMMITS_AHEAD=0"
    echo "UNMERGED_COMMITS="
    exit 0
  fi
fi

# --- 3. Detect base ------------------------------------------------------
BASE=""
for candidate in origin/develop origin/main origin/master; do
  if git -C "$REPO" rev-parse --verify --quiet "$candidate" >/dev/null; then
    BASE="$candidate"
    break
  fi
done

if [ -z "$BASE" ]; then
  echo "STATUS=unknown"
  echo "REASON=no base ref found (tried origin/develop, origin/main, origin/master)"
  echo "METHOD=none"
  echo "BASE="
  echo "COMMITS_AHEAD=0"
  echo "UNMERGED_COMMITS="
  exit 2
fi

# --- 4. git cherry against detected base ---------------------------------
# `git cherry <base> HEAD` lists every commit on HEAD not yet in <base>.
# Prefix '+' = unmerged. Prefix '-' = patch-equivalent (merged even if squashed/rebased).
CHERRY=$(git -C "$REPO" cherry "$BASE" HEAD 2>/dev/null || true)

if [ -z "$CHERRY" ]; then
  echo "STATUS=safe"
  echo "REASON=no commits ahead of $BASE"
  echo "METHOD=git-cherry"
  echo "BASE=$BASE"
  echo "COMMITS_AHEAD=0"
  echo "UNMERGED_COMMITS="
  exit 0
fi

# Count + lines (truly unmerged)
UNMERGED_SHAS=$(echo "$CHERRY" | awk '/^\+/ {print $2}')
COMMITS_AHEAD=$(echo "$CHERRY" | wc -l | tr -d ' ')

if [ -z "$UNMERGED_SHAS" ]; then
  echo "STATUS=safe"
  echo "REASON=all $COMMITS_AHEAD commit(s) patch-equivalent on $BASE (squash/rebase)"
  echo "METHOD=git-cherry"
  echo "BASE=$BASE"
  echo "COMMITS_AHEAD=$COMMITS_AHEAD"
  echo "UNMERGED_COMMITS="
  exit 0
fi

# Format unmerged commits as "shortsha subject; shortsha subject; ..."
UNMERGED_LIST=$(echo "$UNMERGED_SHAS" | while read -r sha; do
  [ -z "$sha" ] && continue
  git -C "$REPO" log -1 --format='%h %s' "$sha" 2>/dev/null
done | paste -sd ';' -)

UNMERGED_COUNT=$(echo "$UNMERGED_SHAS" | wc -l | tr -d ' ')

echo "STATUS=unmerged"
echo "REASON=$UNMERGED_COUNT commit(s) not on $BASE"
echo "METHOD=git-cherry"
echo "BASE=$BASE"
echo "COMMITS_AHEAD=$COMMITS_AHEAD"
echo "UNMERGED_COMMITS=$UNMERGED_LIST"
exit 1
