#!/bin/bash
# ws-check-merged.sh — Detect whether a branch is safe to delete.
#
# Usage: ws-check-merged.sh <repo_path> <branch>
#
# "Safe" means: the branch's work is already on its base (develop/main). We
# OR several independent signals so a branch is flagged unmerged ONLY when none
# of them say it landed — this kills the false "unmerged" warnings that made
# /finish nag about branches that were squash-merged into develop.
#
# Strategy (first signal that says "merged" wins):
#   1. fetch the base refs + the branch (timeout 10s, non-fatal if offline).
#   2. gh PR lookup: if a PR for <branch> is MERGED → safe. Also read the PR's
#      real baseRefName so we compare against the branch's ACTUAL target, not a
#      guessed origin/develop. (Only method that always catches multi-commit
#      squash-merges.)
#   3. is-ancestor: HEAD fully contained in origin/<base> → safe (FF/merge/rebase).
#   4. git cherry: every commit patch-equivalent on base → safe (single-commit
#      squash/rebase).
#   5. squash heuristic (no gh needed): the branch's touched files are byte-
#      identical between HEAD and origin/<base> → the work landed (multi-commit
#      squash) → safe.
#   6. otherwise → unmerged.
#
# Exit codes:
#   0  → SAFE — branch merged, or no commits ahead of base.
#   1  → UNMERGED — at least one commit not on base; block delete.
#   2  → UNKNOWN — could not determine (no base ref, no remote, etc.).
#
# Stdout (always) — key=value lines for the caller to parse:
#   STATUS=safe|unmerged|unknown
#   REASON=<short human-readable reason>
#   METHOD=gh-pr|is-ancestor|git-cherry|squash-diff|none
#   BASE=<base ref or '' >
#   COMMITS_AHEAD=<number>
#   UNMERGED_COMMITS=<short SHA + subject, semicolon-separated, may be empty>

set -uo pipefail

REPO="${1:-}"
BRANCH="${2:-}"

emit() {
  echo "STATUS=$1"
  echo "REASON=$2"
  echo "METHOD=$3"
  echo "BASE=$4"
  echo "COMMITS_AHEAD=$5"
  echo "UNMERGED_COMMITS=$6"
  exit "$7"
}

if [ -z "$REPO" ] || [ -z "$BRANCH" ]; then
  emit unknown "missing args (repo, branch)" none "" 0 "" 2
fi

if [ ! -d "$REPO/.git" ] && [ ! -f "$REPO/.git" ]; then
  emit unknown "not a git repo: $REPO" none "" 0 "" 2
fi

# --- 1. Fetch (best-effort, short timeout) -------------------------------
fetch_with_timeout() {
  local pid waited=0
  ( git -C "$REPO" fetch --quiet origin \
      develop main master "$BRANCH" 2>/dev/null \
    || git -C "$REPO" fetch --quiet origin 2>/dev/null ) &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge 10 ]; then
      kill -TERM "$pid" 2>/dev/null; sleep 1; kill -KILL "$pid" 2>/dev/null
      return 1
    fi
    sleep 1; waited=$((waited + 1))
  done
  wait "$pid" 2>/dev/null
}
fetch_with_timeout || true

# --- 2. gh PR check (primary; also tells us the REAL base) ----------------
GH_REMOTE=""
PR_BASE=""
if command -v gh >/dev/null 2>&1; then
  REMOTE_URL=$(git -C "$REPO" remote get-url origin 2>/dev/null || true)
  case "$REMOTE_URL" in
    *github.com[:/]*)
      GH_REMOTE=$(echo "$REMOTE_URL" \
        | sed -E 's#^git@github\.com:##; s#^https?://github\.com/##; s#\.git$##')
      ;;
  esac
fi

if [ -n "$GH_REMOTE" ]; then
  # Pull the most recent PR for this head, any state, with its base + merge state.
  PR_LINE=$(gh -R "$GH_REMOTE" pr list \
    --head "$BRANCH" --state all \
    --json number,state,baseRefName,mergedAt \
    --jq 'sort_by(.mergedAt // "") | reverse
          | (map(select(.state=="MERGED")) + .)[0]
          | "\(.number)\t\(.state)\t\(.baseRefName)"' 2>/dev/null || true)
  if [ -n "$PR_LINE" ]; then
    PR_NUM=$(echo "$PR_LINE" | cut -f1)
    PR_STATE=$(echo "$PR_LINE" | cut -f2)
    PR_BASE=$(echo "$PR_LINE" | cut -f3)
    if [ "$PR_STATE" = "MERGED" ]; then
      emit safe "PR #$PR_NUM merged into ${PR_BASE:-base} on $GH_REMOTE" \
        gh-pr "origin/${PR_BASE:-}" 0 "" 0
    fi
  fi
fi

# --- 3. Detect base (prefer the PR's real target) ------------------------
BASE=""
for candidate in "${PR_BASE:+origin/$PR_BASE}" origin/develop origin/main origin/master; do
  [ -z "$candidate" ] && continue
  if git -C "$REPO" rev-parse --verify --quiet "$candidate" >/dev/null; then
    BASE="$candidate"; break
  fi
done

if [ -z "$BASE" ]; then
  emit unknown "no base ref found (tried origin/develop, origin/main, origin/master)" \
    none "" 0 "" 2
fi

# --- 4. is-ancestor: HEAD fully contained in base ------------------------
if git -C "$REPO" merge-base --is-ancestor HEAD "$BASE" 2>/dev/null; then
  emit safe "HEAD already contained in $BASE" is-ancestor "$BASE" 0 "" 0
fi

# --- 5. git cherry against detected base ---------------------------------
CHERRY=$(git -C "$REPO" cherry "$BASE" HEAD 2>/dev/null || true)

if [ -z "$CHERRY" ]; then
  emit safe "no commits ahead of $BASE" git-cherry "$BASE" 0 "" 0
fi

UNMERGED_SHAS=$(echo "$CHERRY" | awk '/^\+/ {print $2}')
COMMITS_AHEAD=$(echo "$CHERRY" | grep -c . | tr -d ' ')

if [ -z "$UNMERGED_SHAS" ]; then
  emit safe "all $COMMITS_AHEAD commit(s) patch-equivalent on $BASE (squash/rebase)" \
    git-cherry "$BASE" "$COMMITS_AHEAD" "" 0
fi

# --- 6. Squash heuristic: are the branch's touched files already on base? --
# Multi-commit squash-merges aren't patch-equivalent, so cherry shows '+'.
# But after the squash lands, the files the branch touched are byte-identical
# between HEAD and base. If `git diff` over exactly those files is empty, the
# work is on base. (No-op if the branch touched nothing.)
MB=$(git -C "$REPO" merge-base "$BASE" HEAD 2>/dev/null || true)
if [ -n "$MB" ]; then
  FILES=()
  while IFS= read -r -d '' f; do
    FILES+=("$f")
  done < <(git -C "$REPO" diff -z --name-only "$MB" HEAD 2>/dev/null)
  if [ "${#FILES[@]}" -gt 0 ]; then
    if git -C "$REPO" diff --quiet "$BASE" HEAD -- "${FILES[@]}" 2>/dev/null; then
      emit safe "branch's touched files already identical in $BASE (squash-merge)" \
        squash-diff "$BASE" "$COMMITS_AHEAD" "" 0
    fi
  fi
fi

# --- 7. Truly unmerged ---------------------------------------------------
UNMERGED_LIST=$(echo "$UNMERGED_SHAS" | while read -r sha; do
  [ -z "$sha" ] && continue
  git -C "$REPO" log -1 --format='%h %s' "$sha" 2>/dev/null
done | paste -sd ';' -)

UNMERGED_COUNT=$(echo "$UNMERGED_SHAS" | grep -c . | tr -d ' ')

emit unmerged "$UNMERGED_COUNT commit(s) not on $BASE" \
  git-cherry "$BASE" "$COMMITS_AHEAD" "$UNMERGED_LIST" 1
