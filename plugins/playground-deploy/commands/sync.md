---
allowed-tools: Bash(git *), Bash(gh *)
description: Sync playground from develop, optionally update your branch too
disable-model-invocation: false
---

Update playground from develop, then optionally update the current branch.

## Detect context

1. Detect the worktree root. The worktree contains two repos: `front/` and `back/`.
2. For each repo, get the current branch: `git -C <repo> branch --show-current`
3. Check for uncommitted changes: `git -C <repo> status --porcelain`
   - If dirty, **auto-commit them silently**:
     ```bash
     git -C <repo> add -A
     git -C <repo> commit -m "wip: auto-commit before playground sync"
     ```
     Inform the user briefly: `"Auto-commit dans <repo>."`

## Step 1 — Update playground from develop (always)

For each repo (`front/`, `back/`):

1. Fetch:
   ```bash
   git -C <repo> fetch origin develop playground
   ```

2. Check if playground is behind develop:
   ```bash
   git -C <repo> rev-list --count origin/playground..origin/develop
   ```
   - If 0: playground is up to date, skip this repo.

3. Checkout playground and rebase on develop:
   ```bash
   git -C <repo> checkout playground
   git -C <repo> rebase origin/develop
   ```
   - Conflicts: resolve freely.

4. Push:
   ```bash
   git -C <repo> push --force-with-lease origin playground
   ```

5. Go back to original branch:
   ```bash
   git -C <repo> checkout <original_branch>
   ```

Report:
```
🔄 Playground mis à jour :
   - front: +N commits depuis develop
   - back: déjà à jour
```

## Step 2 — Update current branch (ask first)

Ask the user:
> "Tu veux aussi mettre ta branche `<branch>` à jour par rapport à playground ?"

If yes, for each repo:

1. Rebase on updated playground:
   ```bash
   git -C <repo> rebase origin/playground
   ```
   - Conflicts: resolve freely.

2. Push:
   ```bash
   git -C <repo> push --force-with-lease origin <branch>
   ```

Report:
```
✅ Branche `<branch>` à jour :
   - front: rebasée sur playground
   - back: rebasée sur playground
```

If no, say:
> "OK, playground est à jour. Ta branche reste comme elle est."
