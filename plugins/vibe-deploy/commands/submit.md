---
allowed-tools: Bash(git *), Bash(gh pr *), Bash(gh api *), Bash(gh pr checks *), Bash(gh run *)
description: Promote playground to develop with code review and CI check (front + back)
disable-model-invocation: false
---

Promote everything on `playground` to `develop` by creating PRs on both repos. Requires passing CI and code review.

## Pre-flight (both repos)

For each repo (`front/`, `back/`):

1. Check that there are no open PRs targeting `playground` that are not yet merged:
   ```bash
   gh pr list --base playground --state open --json number,title,url
   ```
   - If open PRs exist, **STOP**:
     > "Il y a encore des PRs ouvertes sur playground. Merge-les ou ferme-les d'abord :"
     > (list the PRs)

2. Check CI status on the playground branch:
   ```bash
   gh api repos/{owner}/{repo}/commits/playground/status --jq '.state'
   ```
   - Also check GitHub Actions runs:
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
   git -C <repo> checkout -B promote-playground-to-develop origin/playground
   ```

3. Rebase on develop:
   ```bash
   git -C <repo> rebase origin/develop
   ```
   - If conflicts arise: attempt to resolve. Read the files, understand intent, fix.
   - If resolution is too complex (more than 3 files in conflict, or logic is ambiguous), **STOP**:
     > "Le rebase a des conflits trop complexes dans `<repo>`. Demande à un dev de t'aider. Fichiers en conflit : <list>"
   - Then abort: `git -C <repo> rebase --abort`

4. Push:
   ```bash
   git -C <repo> push --force-with-lease origin promote-playground-to-develop
   ```

5. Create PR:
   ```bash
   gh pr create --base develop --head promote-playground-to-develop --title "<title>" --body "<body>"
   ```
   - **Title**: `chore: promote playground to develop`
   - **Body**: include the code review summary + list of changes. End with:
     ```
     ✅ CI verte sur playground
     ✅ Code review passée

     🤖 Promoted with [Claude Deploy Plugin](https://github.com/sommesi/claude-deploy-plugin)
     ```

## On failure

If any repo fails:
1. Abort any in-progress rebase: `git -C <repo> rebase --abort`
2. Clean up the promote branch: `git -C <repo> checkout - && git -C <repo> branch -D promote-playground-to-develop`
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
