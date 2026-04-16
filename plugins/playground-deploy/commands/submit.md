---
allowed-tools: Bash(git *), Bash(gh pr *), Bash(gh api *), Bash(gh pr checks *), Bash(gh run *)
description: Promote playground to develop with code review and CI check (front + back)
disable-model-invocation: false
---

Promote playground to `develop` by creating PRs. One squashed commit per feature, identified by the worktree branch. develop is the source of truth.

## Detect feature name

1. Get the current branch name from the worktree:
   ```bash
   git -C <repo> branch --show-current
   ```
2. If the branch is a feature branch (e.g. `feat/demo-playground`), use it as the feature name for commit messages.
3. If the branch is `playground` or `develop` (no worktree / not on a feature branch), use a generic name: `promote-playground`.

## Pre-flight (both repos)

For each repo (`front/`, `back/`):

1. Check CI status on the playground branch:
   ```bash
   gh run list --branch playground --limit 1 --json status,conclusion,name
   ```
   - If CI is not green (conclusion != "success"), **STOP**:
     > "La CI n'est pas verte sur playground. Voici les checks en échec :"
     > (list failing checks)

## Code Review

Before creating the PRs, perform a code review of the diff between `playground` and `develop`:

1. For each repo, get the diff:
   ```bash
   git -C <repo> fetch origin develop playground
   git -C <repo> diff origin/develop..origin/playground
   ```

2. Review the diff using a Sonnet agent. The agent should:
   - Check for obvious bugs, security issues, and logic errors
   - Flag anything that looks risky for production
   - Keep the review concise and actionable

3. Present the review to the user:
   > "Voici la review avant de promouvoir sur develop :"
   > (review results)

4. Ask the user:
   > "Tu veux continuer avec la PR vers develop ?"
   - If no → stop.

## Promote (repeat for front/ and back/)

For each repo, in sequence (if one fails, abort both):

1. Fetch:
   ```bash
   git -C <repo> fetch origin develop playground
   ```

2. Create a local branch from playground:
   ```bash
   git -C <repo> checkout -B promote/<feature-name> origin/playground
   ```

3. Squash all commits into a single one on top of develop:
   ```bash
   git -C <repo> reset --soft origin/develop
   git -C <repo> commit -m "feat(<feature-name>): promote to develop"
   ```
   - This produces a single clean commit containing all playground changes for this feature.
   - If there are no changes to commit (playground == develop), skip this repo.
   - If reset fails, fall back to rebase:
     ```bash
     git -C <repo> rebase origin/develop
     ```
     - If resolution is too complex (more than 3 files in conflict, or logic is ambiguous), **STOP**:
       > "Le rebase a des conflits trop complexes dans `<repo>`. Demande à un dev de t'aider. Fichiers en conflit : <list>"
     - Then abort: `git -C <repo> rebase --abort`

4. Push:
   ```bash
   git -C <repo> push --force-with-lease origin promote/<feature-name>
   ```

5. Create PR:
   ```bash
   gh pr create --base develop --head promote/<feature-name> --title "feat(<feature-name>): promote to develop" --body "<body>"
   ```
   - **Body**: include the code review summary + list of changes. End with:
     ```
     ✅ CI verte sur playground
     ✅ Code review passée

     🤖 Promoted with [Playground Deploy](https://github.com/sommesi/playground-deploy)
     ```

6. Go back to the feature branch:
   ```bash
   git -C <repo> checkout <original-branch>
   ```

## On failure

If any repo fails:
1. Abort any in-progress rebase: `git -C <repo> rebase --abort`
2. Clean up the promote branch: `git -C <repo> checkout <original-branch> && git -C <repo> branch -D promote/<feature-name>`
3. Tell the user what went wrong.
4. Do NOT continue with the other repo.

## Output

```
✅ PRs créées sur develop :
   - front: <PR_URL>
   - back: <PR_URL>

📋 Review summary:
   <brief review summary>
```
