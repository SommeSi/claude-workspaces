---
allowed-tools: Bash(git *), Bash(gh *)
description: Deploy current branch to playground (front + back)
disable-model-invocation: false
---

Deploy the current worktree branch to `playground` by merging directly — no PR, no friction.

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

2. Checkout playground and merge the feature branch with squash:
   ```bash
   git -C <repo> checkout playground
   git -C <repo> merge --squash <branch>
   git -C <repo> commit -m "feat(<branch>): deploy to playground"
   ```
   - This produces a single commit on playground for this feature.
   - If conflicts arise: resolve them freely. Read the conflicting files, understand the intent, fix them, then `git -C <repo> add .` and continue.

3. Push playground directly:
   ```bash
   git -C <repo> push origin playground
   ```

4. Go back to the feature branch:
   ```bash
   git -C <repo> checkout <branch>
   ```

## On failure

If any repo fails at any step:
1. Abort any in-progress merge: `git -C <repo> merge --abort`
2. Go back to the feature branch: `git -C <repo> checkout <branch>`
3. Tell the user clearly what went wrong and which repo failed.
4. Do NOT continue with the other repo.

## Output

Display a summary:

```
✅ Déployé sur playground :
   - front: pushed (1 commit squashé)
   - back: pushed (1 commit squashé)
```
