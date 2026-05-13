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

## Step 2 — Safety checks (delegated to scripts, parallel across repos)

For each repo, run these two commands in parallel:

```bash
git -C <repo_path> status --short
git -C <repo_path> branch --show-current
```

For worktree-mode repos, also run the merge-safety script — it handles fetch, GitHub PR lookup, base auto-detection, and patch-equivalent (squash/rebase) detection:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/ws-check-merged.sh" <repo_path> <branch>
```

The script prints `key=value` lines (`STATUS`, `REASON`, `METHOD`, `BASE`, `COMMITS_AHEAD`, `UNMERGED_COMMITS`) and exits with:
- `0` → branch merged or no commits ahead → **safe**
- `1` → unmerged commits exist → **block, ask for confirmation**
- `2` → unknown (offline, no base ref, …) → **warn, ask for confirmation**

For worktree mode, also note whether the branch is on the remote (informational only):

```bash
git -C <repo_path> ls-remote --heads origin <branch> | wc -l
```

### Check 1 — Uncommitted files

If `git status --short` output is not empty for any repo, show the user the list of uncommitted files and require explicit confirmation:

> ⚠️ You have uncommitted files in `<repo_name>`: `<list>`. These will be LOST. Continue? [y/N]

Default is **NO**. Only proceed if the user explicitly answers `y` or `yes`.

### Check 2 — Unmerged branch (worktree mode only)

Parse the output of `ws-check-merged.sh`:

- If `STATUS=safe` → **no prompt**, the branch is merged (PR merged on GitHub, or patch-equivalent on base — handles squash/rebase). Continue silently.
- If `STATUS=unmerged` → show the commits and require explicit confirmation:

  > ⚠️ Branch `<branch>` has N commit(s) not on `<base>` in `<repo_name>`:
  > `<UNMERGED_COMMITS list>`
  > This branch is **NOT merged**. Deleting it means losing this work.
  > Tip: consider creating a PR first (`gh pr create`).
  >
  > Are you absolutely sure you want to delete unmerged work? Type "delete unmerged" to confirm.

  Default is **NO**. Only proceed if the user explicitly types `delete unmerged`.

- If `STATUS=unknown` → fall back to a soft warning:

  > ⚠️ Could not verify merge state for `<branch>` in `<repo_name>` (`<REASON>`). Continue anyway? [y/N]

  Default is **NO**.

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

If a `pre_destroy` hook is defined in `.claude-workspaces.json`, run it with variable substitution (`$SLOT`, `$BRANCH`, `$SLUG`, `$WORKSPACE_PATH` with `~` expanded to `$HOME`):

```bash
eval "<pre_destroy_command_with_substitutions>"
```

### 5c — Orchestrated destroy (1 script call)

Run `ws-destroy.sh` — it handles **everything** in parallel across repos: drop isolated `_w<slot>` DBs via `dropdb` (no Rails/bundler dependency), `git worktree remove --force` per repo, delete the workspace directory, and atomic registry update:

```bash
CONFIG="<config_path>" PROJECT_ROOT="<git_root>" \
  /bin/bash "${CLAUDE_PLUGIN_ROOT}/scripts/ws-destroy.sh" "<workspace_path>" "<slot>"
```

The script:
- Reads DB URLs from each repo's `.env.local` / `.env`, filters to `_w<slot>` suffix (**refuse of drop any non-isolated DB**)
- Runs `dropdb --if-exists` per DB, parallel across repos
- `git worktree remove --force` per repo, parallel
- `rm -rf <workspace_path>`
- Atomic registry update (tempfile + rename)

If a `db_destroy` hook is defined in the project config, it takes priority over `dropdb` (future enhancement — currently `dropdb` is always used).

Partial failures don't abort: each DB / worktree removal is best-effort with a warning. Continue to 5d.

### 5d — Reset terminal

Reset the terminal title and background color:

```bash
# Detect the parent terminal device (Claude Code captures stdout)
TTY_DEV="/dev/$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')"

# Reset background, tab name, and window title
printf '\033]11;\007' > "$TTY_DEV" 2>/dev/null
printf '\033]1;\007' > "$TTY_DEV" 2>/dev/null
printf '\033]0;\007' > "$TTY_DEV" 2>/dev/null
```

### 5e — Close workspace window

Close the WezTerm window associated with this workspace. Find it by matching the workspace path in the pane list:

```bash
WEZTERM_CLI="/Applications/WezTerm.app/Contents/MacOS/wezterm"
if [ -x "$WEZTERM_CLI" ]; then
  # Find all panes whose cwd starts with the workspace path
  $WEZTERM_CLI cli list --format json | python3 -c "
import json, sys
panes = json.load(sys.stdin)
ws_path = '<workspace_path>'
window_ids = set()
for p in panes:
    cwd = p.get('cwd', '')
    if cwd.startswith(ws_path):
        window_ids.add(p['window_id'])
for wid in window_ids:
    print(wid)
" | while read wid; do
    # Kill all panes in that window
    $WEZTERM_CLI cli list --format json | python3 -c "
import json, sys
panes = json.load(sys.stdin)
for p in panes:
    if str(p['window_id']) == '$wid':
        print(p['pane_id'])
" | while read pid; do
      $WEZTERM_CLI cli kill-pane --pane-id "$pid" 2>/dev/null || true
    done
  done
fi
```

If WezTerm is not installed, skip this step silently.

After closing the window, exit the current Claude Code session:

```bash
exit
```

---

## Step 6 — Summary

Show a concise success message, then exit:

```
✅ Workspace w<slot> (<slug>) removed. Slot freed.
<if memory saved> 💾 Memory "<name>" saved.

Closing session...
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
