---
name: finish
description: Finalize and clean up a workspace — safety checks, capture learnings, remove worktree, free slot. Use when the user is done with a feature, wants to clean up, or says "finish", "done", "close workspace", "remove workspace", "clean up".
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob]
---

**Respond in the user's language.**

You are finalizing and removing a workspace. Follow the steps below **in order**. Never skip ahead. Never batch multiple questions in a single message.

---

## Step 1 — Detect current workspace

Read the registry:

```bash
cat ~/.claude-workspaces/registry.json 2>/dev/null || echo '{"workspaces":{},"next_slot":1}'
```

Match `pwd` against the `workspace_path` of each registry entry (check if `pwd` starts with or equals the workspace path).

- If a match is found: proceed with that workspace.
- If no match: show the list of existing workspaces and ask the user which one to finish.
- If the registry is empty or has no workspaces: inform the user there are no workspaces to finish, and stop.

---

## Step 2 — Safety checks (run all git commands in parallel for all repos)

For each repo in the workspace, run these three commands:

```bash
git -C <repo_path> status --short
git -C <repo_path> branch --show-current
git -C <repo_path> log main..HEAD --oneline 2>/dev/null || git -C <repo_path> log develop..HEAD --oneline 2>/dev/null || echo "COULD_NOT_COMPARE"
```

Also run for worktree mode repos:

```bash
git ls-remote --heads origin <branch> | wc -l
```

### Check 1 — Uncommitted files

If `git status --short` output is not empty for any repo, show the user the list of uncommitted files and require explicit confirmation:

> ⚠️ You have uncommitted files in `<repo_name>`: `<list>`. These will be LOST. Continue? [y/N]

Default is **NO**. Only proceed if the user explicitly answers `y` or `yes`.

### Check 2 — Unmerged branch (worktree mode only)

If `git log main..HEAD` (or `develop..HEAD`) shows any commits for any repo, show them and require explicit confirmation:

> ⚠️ Branch `<branch>` has N commit(s) not in main/develop in `<repo_name>`:
> `<commit list>`
> Branch is not merged. Delete anyway? [y/N]
> Tip: consider creating a PR first (`gh pr create`).

Default is **NO**. Only proceed if the user explicitly answers `y` or `yes`.

### Check 3 — Branch not on remote (worktree mode only, informational)

If `git ls-remote --heads origin <branch>` returns `0`, note:

> ℹ️ Branch `<branch>` has not been pushed to remote.

This check is **informational only** — it does not block the cleanup.

---

## Step 3 — Capture lessons learned (MANDATORY question)

Before any cleanup, ask:

> Before cleanup: did you learn anything **surprising or non-obvious** during this workspace that should be remembered for future sessions?
>
> Examples: tricky API behavior, undocumented convention, pattern that worked well, important architectural decision.
>
> Answer freely, or say "no" to skip.

Wait for the user's answer. Do NOT proceed until answered.

### If the user has something to share:

1. Determine the appropriate memory type: `feedback`, `project`, `reference`, or `user`.
2. Draft a memory file with proper frontmatter:
   ```markdown
   ---
   name: <short-identifier>
   description: <one-line summary>
   type: <feedback|project|reference|user>
   ---
   <content>
   ```
3. Show the draft to the user and ask for confirmation before saving.
4. Save to the Claude memory directory (same location as `MEMORY.md`).
5. Update `MEMORY.md` to add an entry in the index.

### If the user says "no":

Proceed to Step 4.

---

## Step 4 — Final confirmation with full recap

Show a complete summary of what will be destroyed:

```
Cleanup recap for workspace w<slot> (<slug>):
  Mode     : <worktree|sandbox>
  Branch   : <branch or N/A>
  Path     : <workspace_path>
  Repos    : <repo_name> (port <port>), ...

Actions:
  1. Kill processes on ports <port_list>
  2. Execute hooks (pre_destroy, db_destroy) if defined
  3. git worktree remove for each repo (worktree mode)
  4. Remove directory <workspace_path>
  5. Free slot <slot> in registry

⚠️ This is **irreversible**. Proceed? [y/N]
```

Default is **NO**. Only proceed if the user explicitly answers `y` or `yes`. Anything else cancels — inform the user that the workspace was NOT removed.

---

## Step 5 — Execute cleanup

**CRITICAL: run `cd $HOME` first if the current directory is inside the workspace.**

```bash
# Check if inside workspace before proceeding
[[ "$PWD" == <workspace_path>* ]] && cd $HOME
```

Execute each sub-step in order. If a step fails, log a warning and **continue** — do not abort the entire cleanup.

### 5a — Kill processes on ports

For each port in the workspace:

```bash
pids=$(lsof -ti :<port> 2>/dev/null || true)
if [ -n "$pids" ]; then
  echo "$pids" | xargs kill -TERM 2>/dev/null || true
  sleep 2
  pids=$(lsof -ti :<port> 2>/dev/null || true)
  [ -n "$pids" ] && echo "$pids" | xargs kill -KILL 2>/dev/null || true
fi
```

Log: `✓ Killed process on port <port>` or `- Nothing on port <port>`.

### 5b — Execute pre_destroy hook

If a `pre_destroy` hook is defined in the project config (`.claude-workspaces.json`), run it with variable substitution:

- `$SLOT` → slot number
- `$BRANCH` → branch name
- `$SLUG` → workspace slug
- `$WORKSPACE_PATH` → workspace root path (with `~` expanded to `$HOME`)

```bash
eval "<pre_destroy_command_with_substitutions>"
```

### 5c — Execute db_destroy hook

If a `db_destroy` hook is defined in the project config, run it with the same variable substitution as above.

### 5d — Remove git worktrees (worktree mode only)

For each repo in the workspace:

```bash
git -C <project_root>/<repo_origin> worktree remove <repo_path> --force
```

Where `<repo_origin>` is the relative origin path from `.claude-workspaces.json`.

Log: `✓ Removed worktree <repo_name>` or `⚠ Failed to remove worktree <repo_name>: <error>`.

### 5e — Remove workspace directory

```bash
rm -rf <workspace_path>
```

Log: `✓ Removed directory <workspace_path>`.

### 5f — Update registry

Read the registry, remove the entry for this slot, and write it back:

```bash
cat ~/.claude-workspaces/registry.json
```

Remove the key matching this slot from `workspaces`. Recalculate `next_slot` as `min(freed_slot, current_next_slot)` so freed slots can be reused.

Write the updated registry to `~/.claude-workspaces/registry.json`.

### 5g — Reset terminal

Reset the terminal title and background color:

```bash
printf '\033]11;\007'
printf '\033]0;\007'
```

---

## Step 6 — Summary

Show a concise success message:

```
✅ Workspace w<slot> (<slug>) removed. Slot freed.
<if memory saved> 💾 Memory "<name>" saved.

You can: /ws:list, /ws:start-worktree, /ws:start-sandbox
```

---

## Rules

- **Never delete without explicit confirmation.** Default answer is always NO.
- **Uncommitted work = double confirmation.** Show the files, require explicit `y`/`yes`.
- **Unmerged branch = explicit acknowledgment.** Show the commits, require explicit `y`/`yes`.
- **Always ask about lessons learned** before starting cleanup. This step is mandatory.
- **cd out before deleting** the workspace directory. Never delete the directory you're currently in.
- **Partial failure = log and continue.** Do not abort the entire cleanup if one step fails.
- **Never save to memory** things that are derivable from code or easily looked up.
- **One question at a time.** Never batch multiple questions in a single message.
- **Always read the registry before writing.** Never overwrite without reading first.
- **Expand `~` to `$HOME` in all paths** before running shell commands.
