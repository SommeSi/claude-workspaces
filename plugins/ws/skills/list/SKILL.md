---
name: list
description: List all active workspaces with their status. Use when the user wants to see what workspaces exist, check status, or decide which workspace to resume. Triggers on "list workspaces", "show workspaces", "what am I working on", "which features".
allowed-tools: [Read, Bash, Grep]
---

**Respond in the user's language.**

Read-only skill — never modifies anything.

---

## Step 1 — Read registry

```bash
cat ~/.claude-workspaces/registry.json 2>/dev/null || echo '{"workspaces":{},"next_slot":1}'
```

- If the file is missing or `workspaces` is empty: reply with "No active workspaces. Use /workspace:start-worktree or /workspace:start-sandbox." and stop.

---

## Step 2 — Enrich each workspace (run all git commands in parallel)

For each slot in `workspaces`, run these commands in parallel:

```bash
# Last commit (short)
git -C <repo_path> log --oneline -1 2>/dev/null

# Number of modified/untracked files
git -C <repo_path> status --short 2>/dev/null | wc -l | tr -d ' '

# Check workspace path exists
test -d <workspace_path> && echo "exists" || echo "missing"
```

Where `<repo_path>` is the first repo's `path` in the workspace entry, and `<workspace_path>` is the workspace's `workspace_path`.

**Goal extraction:** For each workspace, attempt to read `<workspace_path>/CLAUDE.local.md` and extract the first non-empty line that appears after the heading `## Goal of this workspace`. If the file is missing or the section is absent, use `—`.

---

## Step 3 — Display table

Format the output as a table. Truncate branch/name to 25 characters and goal to 40 characters. For ports, list all repo ports separated by commas; use `—` if none.

```
SLOT │ BRANCH/NAME              │ PORTS      │ MODIFIED │ GOAL
─────┼──────────────────────────┼────────────┼──────────┼──────────────────────────────────────────
1    │ feat/polo/export-csv     │ 3011,3010  │ 3 files  │ Add CSV export to the reporting screen...
2    │ research-perf-audit      │ —          │ 0 files  │ Investigate slow query on dashboard load
```

Below each row, display the last commit on a separate indented line:

```
     └─ abc1234 fix: correct export encoding
```

---

## Step 4 — Warnings and proposals

After the table, print any applicable warnings:

- **Orphaned workspace** (path doesn't exist): warn with a note like `⚠ Slot 3: workspace path not found — consider /workspace:finish to clean up.`
- **Many uncommitted files** (>5 in a workspace): warn with `⚠ Slot 1: 8 uncommitted files.`

End with a prompt:

> Want to resume one? Run `/workspace:resume` and specify the slot number.

---

## Rules

- Read-only — never modify any file or registry entry.
- Handle missing paths gracefully — a missing workspace directory is not an error, just a warning.
- Truncate branch to max 25 chars (append `…` if truncated), goal to max 40 chars (append `…` if truncated).
- Run all git commands in parallel across workspaces.
- Use `workspaces_root` (with s) when reading config paths.
