---
name: knowledge-review
description: Turn the team lessons captured automatically at the end of Claude sessions into one PR per repo that updates `.claude/rules/`, and list the recurring tooling frictions to fix. Use weekly, or when the user says "knowledge review", "revue des leçons", "range les leçons", "/knowledge-review".
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob]
---

**Respond in the user's language.** No questions: the PR is the human review.

The `SessionEnd` hook of this plugin stores lessons in `~/.claude-workspaces/knowledge-inbox/` (one JSON per session). `/git-pr` already consumes the ones matching the files of a PR; this skill handles the rest.

## Step 1 — Read the inbox (ONE call)

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/ws-knowledge.py" list
```

Empty list → say "Aucune leçon en attente." and stop. Otherwise group lessons by `repo` (origin slug) and `main_checkout` (local path of the main clone). Lessons with an empty `main_checkout` or repo: list them in the final report, leave them pending.

## Step 2 — One PR per repo (repos in parallel)

1. **Worktree (ONE Bash call per repo):** never touch the main checkout (it holds someone's WIP).
   ```bash
   cd "<main_checkout>" && git fetch -q origin
   BASE=$(git rev-parse -q --verify origin/develop >/dev/null && echo develop || git symbolic-ref --short refs/remotes/origin/HEAD | sed 's#origin/##')
   WT="$(mktemp -d)/knowledge" && git worktree add -q -b "docs/knowledge-$(date +%Y%m%d)" "$WT" "origin/$BASE"
   echo "WT=$WT BASE=$BASE"; head -12 "$WT"/.claude/rules/*.md 2>/dev/null
   ```
2. **Merge each lesson** into `$WT/.claude/rules/`:
   - Already covered by a rule, or made false by the current code (one `git grep` when it names an identifier) → drop it.
   - Otherwise add one bullet to the file whose `paths:` fit best: English, imperative, concrete (method/file/field), why in a few words, source in parentheses. New topic → new file with the narrowest `paths:` (check each glob matches files with `git ls-files`). No `paths:` only for rules every session needs.
   - It contradicts an existing rule → keep what the code confirms, and say so in the PR body.
   - Never write secrets, credentials or client staff contact details.
3. **Commit, push, PR:** `git commit -m "docs(claude): add team lessons from recent sessions"` (only `.claude/rules/` files), `git push -u origin HEAD`, `gh pr create --base "$BASE"` with a French body: lessons added (one line each), lessons dropped and why. If a pre-commit hook fails for a reason unrelated to docs (e.g. it boots the app and wants a migrated local DB), skip only that hook (`LEFTHOOK_EXCLUDE=<hook>`) and say so in the PR body. **Never merge.**
4. **Clean up:** `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/ws-knowledge.py" consume <every processed id, added or dropped>`, then `git -C "<main_checkout>" worktree remove "$WT"`.

## Step 3 — Frictions (ONE call)

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/ws-knowledge.py" frictions
```

The same hook stores the moments where the tooling got in the way (workspace skills, worktree, ports, DB, permissions…), grouped here by target, most sessions first. First merge groups that describe the same problem under different targets (e.g. one git hook failing under `git` and `hooks`). Keep the problems seen in **≥ 2 sessions**; merge their symptoms into one line and pick the most concrete suggestion. Do not fix them here and do not consume them: the user decides, and the ids are consumed once a fix is merged.

## Step 4 — Report

PR links, counts (added / dropped / left pending), the pending ones that need a human, then the recurring frictions: target, sessions count, symptom, suggestion, ids.
