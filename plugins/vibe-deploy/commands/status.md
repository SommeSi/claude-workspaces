---
allowed-tools: Bash(git *), Bash(gh pr *), Bash(gh api *), Bash(gh run *)
description: Show deployment status — all PRs on playground, your PRs on develop
disable-model-invocation: false
---

Show the current state of deployments across playground and develop for both repos.

## Detect context

1. Detect the worktree root. The worktree contains two repos: `front/` and `back/`.

## Playground — Full view (both repos)

For each repo (`front/`, `back/`):

1. List all open PRs targeting playground:
   ```bash
   gh pr list --base playground --state open --json number,title,author,url,createdAt,statusCheckRollup
   ```

2. List recently merged PRs (last 10):
   ```bash
   gh pr list --base playground --state merged --limit 10 --json number,title,author,url,mergedAt
   ```

3. Check CI status on playground branch:
   ```bash
   gh run list --branch playground --limit 3 --json name,status,conclusion,createdAt
   ```

## Develop — Your PRs only (both repos)

For each repo (`front/`, `back/`):

1. List your open PRs targeting develop:
   ```bash
   gh pr list --base develop --state open --author @me --json number,title,url,createdAt,statusCheckRollup,reviewDecision
   ```

2. List your recently merged PRs (last 5):
   ```bash
   gh pr list --base develop --state merged --author @me --limit 5 --json number,title,url,mergedAt
   ```

## Output

Present a clean, readable summary:

```
📦 Playground
   🔵 Open PRs:
      - front #42: "feat: add form" (by alice) — CI ✅
      - back #18: "feat: add endpoint" (by alice) — CI ⏳
   ✅ Recently merged:
      - front #41: "fix: typo" (by bob) — merged 2h ago
      - back #17: "fix: validation" (by bob) — merged 2h ago
   CI: ✅ All checks passing

🚀 Develop (your PRs)
   🔵 Open:
      - front #39: "chore: promote playground" — review pending
   ✅ Merged:
      - back #15: "chore: promote playground" — merged yesterday
```

If there are no PRs in a section, say "Aucune PR" instead of leaving it empty.
