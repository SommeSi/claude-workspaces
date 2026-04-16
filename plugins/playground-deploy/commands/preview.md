---
allowed-tools: Bash(git *), Bash(gh pr *), Bash(gh api *)
description: Deploy current branch to playground (front + back)
disable-model-invocation: false
---

Deploy the current worktree branch to `playground` by creating PRs on both repos.

## Pre-flight

1. Detect the worktree root. The worktree contains two repos: `front/` and `back/`.
2. For each repo (`front/`, `back/`):
   - Get the current branch name: `git -C <repo> branch --show-current`
   - If the branch is `playground` or `develop`, **STOP**:
     > "Tu es sur `<branch>` directement. Crée une branche de feature d'abord."
   - Run `git -C <repo> status --porcelain`
   - If there are uncommitted changes, **auto-commit them silently**:
     ```bash
     git -C <repo> add -A
     git -C <repo> commit -m "wip: auto-commit before playground deploy"
     ```
     Inform the user briefly: `"Auto-commit dans <repo>."`

## Deploy (repeat for front/ and back/)

For each repo, in sequence (do NOT parallelize — if one fails, abort both):

1. Fetch remote:
   ```bash
   git -C <repo> fetch origin playground
   ```

2. Rebase on playground:
   ```bash
   git -C <repo> rebase origin/playground
   ```
   - If conflicts arise: resolve them freely. Read the conflicting files, understand the intent, fix them, then `git -C <repo> add .` and `git -C <repo> rebase --continue`.

3. Push:
   ```bash
   git -C <repo> push --force-with-lease origin <branch>
   ```

4. Create or update PR:
   ```bash
   gh pr create --repo origin --base playground --head <branch> --title "<title>" --body "<body>"
   ```
   - If a PR already exists, skip creation and inform the user.
   - Use `gh pr list --base playground --head <branch> --json number,url` to check first.
   - **Title**: conventional format, e.g. `feat: add client statement page`
   - **Body**: auto-generate a readable summary of the changes (no jargon). End with:
     ```
     🤖 Deployed with [Playground Deploy](https://github.com/sommesi/playground-deploy)
     ```

5. Merge the PR immediately:
   ```bash
   gh pr merge <PR_NUMBER> --merge --delete-branch=false
   ```
   - Do NOT delete the source branch after merge — the user may keep working on it.
   - If merge fails (e.g. merge conflict, required checks), inform the user and continue to the next repo.

## On failure

If any repo fails at any step:
1. If a rebase is in progress, abort it: `git -C <repo> rebase --abort`
2. Tell the user clearly what went wrong and which repo failed.
3. Do NOT continue with the other repo.

## Output

Display a summary:

```
✅ Déployé sur playground :
   - front: <PR_URL> (merged ✅)
   - back: <PR_URL> (merged ✅)
```
