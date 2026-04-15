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
> This branch is **NOT merged**. Deleting it means losing this work.
> Tip: consider creating a PR first (`gh pr create`).
>
> Are you absolutely sure you want to delete unmerged work? Type "delete unmerged" to confirm.

Default is **NO**. Only proceed if the user explicitly types `delete unmerged`. This is stricter than other confirmations because losing unmerged work is the most dangerous action.

### Check 3 — Branch not on remote (worktree mode only, informational)

If `git ls-remote --heads origin <branch>` returns `0`, note:

> ℹ️ Branch `<branch>` has not been pushed to remote.

This check is **informational only** — it does not block the cleanup.

---

## Step 3 — Capture lessons learned (MANDATORY)

Before any cleanup, do two things:

### 3a — Claude's own learnings

Review the entire conversation history and identify things **you** learned that are worth remembering for future sessions. Look for:

- **feedback**: corrections the user made to your approach, preferences expressed, things that worked well
- **project**: architectural decisions, constraints, deadlines, stakeholder context
- **reference**: external tools, dashboards, docs, APIs discovered during the session
- **user**: new info about the user's role, expertise, or preferences

Present your findings as a numbered list:

> Here's what I picked up during this session:
> 1. [feedback] ...
> 2. [project] ...
> 3. [reference] ...
>
> Want me to save any of these? (all / pick numbers / none)

Wait for the user's answer. Save the selected items.

### 3b — User's own learnings

Then ask:

> And you — did you learn anything **surprising or non-obvious** that should be remembered for future sessions?
>
> Examples: tricky API behavior, undocumented convention, pattern that worked well, important decision.
>
> Answer freely, or say "no" to skip.

Wait for the user's answer.

### Saving memories

For each item to save (from 3a or 3b):

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

### 5a — Close WezTerm window (if terminal layout configured)

If the project config has a `terminal` section, close the WezTerm window for this workspace:

```bash
osascript -e '
  tell application "System Events"
    if exists process "WezTerm" then
      tell process "WezTerm"
        repeat with w in windows
          try
            if (name of w) contains "[w<slot>]" then
              click (first button of w whose subrole is "AXCloseButton")
            end if
          end try
        end repeat
      end tell
    end if
  end tell
' 2>/dev/null
```

Log: `✓ Closed WezTerm window` or `- No WezTerm window found`.

### 5b — Kill processes on ports

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

### 5c — Execute pre_destroy hook

If a `pre_destroy` hook is defined in the project config (`.claude-workspaces.json`), run it with variable substitution:

- `$SLOT` → slot number
- `$BRANCH` → branch name
- `$SLUG` → workspace slug
- `$WORKSPACE_PATH` → workspace root path (with `~` expanded to `$HOME`)

```bash
eval "<pre_destroy_command_with_substitutions>"
```

### 5d — Execute db_destroy hook

If a `db_destroy` hook is defined in the project config, run it with the same variable substitution as above.

### 5e — Remove git worktrees (worktree mode only)

For each repo in the workspace:

```bash
git -C <project_root>/<repo_origin> worktree remove <repo_path> --force
```

Where `<repo_origin>` is the relative origin path from `.claude-workspaces.json`.

Log: `✓ Removed worktree <repo_name>` or `⚠ Failed to remove worktree <repo_name>: <error>`.

### 5f — Remove workspace directory

```bash
rm -rf <workspace_path>
```

Log: `✓ Removed directory <workspace_path>`.

### 5g — Update registry

Read the registry, remove the entry for this slot, and write it back:

```bash
cat ~/.claude-workspaces/registry.json
```

Remove the key matching this slot from `workspaces`. Recalculate `next_slot` as `max(remaining_slots) + 1` (or `1` if no workspaces remain). Slot reuse is handled automatically by the "scan 1, 2, 3... for first free" allocation algorithm in the start skills.

Write the updated registry to `~/.claude-workspaces/registry.json`. **Use atomic write to prevent corruption** (see references/registry-format.md). Always re-read the registry before writing. Write the full JSON in a single operation.

### 5h — Reset terminal

Reset the terminal title and background color:

```bash
# Detect the parent terminal device (Claude Code captures stdout)
TTY_DEV="/dev/$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')"

# Reset background, tab name, and window title
printf '\033]11;\007' > "$TTY_DEV" 2>/dev/null
printf '\033]1;\007' > "$TTY_DEV" 2>/dev/null
printf '\033]0;\007' > "$TTY_DEV" 2>/dev/null
```

---

## Step 6 — Summary

Show a concise success message:

```
✅ Workspace w<slot> (<slug>) removed. Slot freed.
<if memory saved> 💾 Memory "<name>" saved.

You can: /workspace:list, /workspace:start-worktree, /workspace:start-sandbox
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
