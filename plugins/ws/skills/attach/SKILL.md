---
name: attach
description: Attach a workspace to an existing directory or repo. Use when the user already has a project and wants to add workspace isolation (slot, color, context) without creating a worktree or new directory. Triggers on "attach workspace", "wrap as workspace", "add workspace to this", "color this project", "track this directory".
allowed-tools: [Read, Write, Edit, Bash, Grep]
---

**Respond in the user's language.**

You are attaching a workspace to an existing directory — no new directory, no worktree, no git init. Follow the steps below **in order**. Never skip ahead. Never batch multiple questions in a single message.

---

## Step 1 — Detect target directory

```bash
pwd
```

Ask: **Attach a workspace to the current directory (`<pwd>`)? Or provide a different path.**

- Default to the current directory if the user confirms or provides no alternative.
- Validate the provided path exists:
  ```bash
  test -d <path> && echo "exists" || echo "not found"
  ```
- Check if it is a git repo:
  ```bash
  git -C <path> rev-parse --show-toplevel 2>/dev/null
  ```
  If not a git repo, warn the user: "This directory does not appear to be a git repository. You can still attach a workspace — branch detection will be skipped." Do **not** block.

---

## Step 2 — Interactive dialogue (ONE question at a time, NEVER batch)

Ask each question separately, waiting for the user's answer before asking the next.

### 2a — Description

Ask: **Briefly describe the goal of this workspace** (2–3 sentences). This will be written to `CLAUDE.local.md` to give future Claude sessions context.

### 2b — Spec link

Ask: **Is there a spec or ticket link for this work?** (optional — "no" or Enter to skip)

---

## Step 3 — Allocate slot

### 3a — Read the registry

See `references/registry-format.md` for the full schema and allocation rules.

```bash
cat ~/.claude-workspaces/registry.json 2>/dev/null || echo '{"workspaces":{},"next_slot":1}'
```

Handle missing file gracefully — initialize empty registry if not found.

### 3b — Find the first free slot

Scan keys `1, 2, 3, ...` in `workspaces` and return the first missing key. This is the new slot number.

### 3c — Derive color and emoji

See `references/color-palette.md`. Compute: `index = (slot - 1) % 8`, then look up the corresponding hex color and emoji.

### 3d — Detect branch (if git repo)

```bash
git -C <path> branch --show-current 2>/dev/null
```

If no branch is detected (non-git dir or detached HEAD), branch is `null`.

### 3e — Derive slug

- If a branch was detected: replace `/` with `-` in the branch name. Example: `feat/polo/export-csv` → `feat-polo-export-csv`.
- Otherwise: use the directory basename. Example: `/Users/you/projects/my-app` → `my-app`.

---

## Step 4 — Recap and confirm

Show a clear summary of everything that will be applied. For example:

```
Ready to attach workspace:

  Slug:    feat-polo-export-csv
  Slot:    w1
  Color:   🟢 #1a3a2a (Green)
  Path:    /Users/you/projects/my-app
  Branch:  feat/polo/export-csv

Confirm? [Y/n]
```

Wait for the user's response. Accept: `y`, `yes`, `o`, `oui`, or empty (just Enter). **Anything else cancels** — tell the user the workspace was not attached.

---

## Step 5 — Apply workspace

Execute the following sub-steps in order. If any step fails, stop immediately and display the error.

### 5a — Generate CLAUDE.local.md

Before writing, check if the file already exists:

```bash
test -f <path>/CLAUDE.local.md && echo "exists" || echo "not found"
```

If it exists, warn: "A `CLAUDE.local.md` already exists at this path. Overwrite it?" and wait for confirmation before proceeding.

Write `<path>/CLAUDE.local.md`. See `references/generated-files.md` for the exact template.

- **mode**: `attached`
- **branch**: detected branch or `N/A` if none
- **Repos section**: single entry pointing to `<path>`, port `null`
- Fill in slot, slug, creation date, user description, spec link.

### 5b — Generate .vscode/settings.json

Before writing, check if a color-customized settings file already exists:

```bash
test -f <path>/.vscode/settings.json && echo "exists" || echo "not found"
```

If it exists, read it and check if it contains `workbench.colorCustomizations`. If so, warn: "A `.vscode/settings.json` with color customizations already exists. Overwrite it?" and wait for confirmation.

Create `.vscode/` if needed:

```bash
mkdir -p <path>/.vscode
```

Write `<path>/.vscode/settings.json` with the workspace color. See `references/generated-files.md` for the exact template.

Fill in the hex color for `titleBar.activeBackground`, `titleBar.activeForeground`, `statusBar.background`, `statusBar.foreground`.

### 5c — Update registry

Read the registry again (always re-read before writing to avoid races), add the new workspace entry, and update `next_slot`.

See `references/registry-format.md` for the exact schema.

Check if `.claude-workspaces.json` exists at the target path to determine port:

```bash
cat <path>/.claude-workspaces.json 2>/dev/null
```

If it exists and has a `port_step` and repos with `port_base`, calculate the port as: `port = port_base + (slot - 1) * port_step`. Otherwise port is `null`.

New entry structure for attached mode:

```json
{
  "<slot>": {
    "slug": "<slug>",
    "mode": "attached",
    "branch": "<branch or null>",
    "color": "<hex-color>",
    "emoji": "<emoji>",
    "created_at": "<ISO-8601-timestamp>",
    "project_root": "<path>",
    "workspace_path": "<path>",
    "repos": [
      {
        "name": "<slug>",
        "path": "<path>",
        "port": "<port or null>"
      }
    ]
  }
}
```

Write the updated registry to `~/.claude-workspaces/registry.json`. Create the directory if needed:

```bash
mkdir -p ~/.claude-workspaces
```

### 5d — Color the terminal

Apply the workspace color to the current terminal session. See `references/color-palette.md` for OSC sequences.

```bash
# Detect the parent terminal device (Claude Code captures stdout)
TTY_DEV="/dev/$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')"

# Set background color (OSC 11)
printf '\033]11;<hex-color>\007' > "$TTY_DEV" 2>/dev/null

# Set tab name (OSC 1) and window title (OSC 0)
printf '\033]1;<emoji> <slug> [w<slot>]\007' > "$TTY_DEV" 2>/dev/null
printf '\033]0;<emoji> <slug> [w<slot>]\007' > "$TTY_DEV" 2>/dev/null
```

---

## Step 6 — Summary

Show a concise success message. For example:

```
✓ Workspace attached!

  🟢 [w1] feat-polo-export-csv
  Path: /Users/you/projects/my-app

Your terminal and IDE are now colored for this workspace.

Next steps:
  • Use /workspace:resume to reattach color and context in future sessions
  • Use /workspace:finish when you're done with this workspace
```

---

## Rules

- **Never create directories** (except `.vscode/`). Never run `mkdir` on the target path itself.
- **Never run git init or git worktree.**
- **One question at a time.** Never ask multiple questions in a single message.
- **Never apply without confirmation.** Always show the recap (Step 4) and wait for explicit approval.
- **Always read the registry before writing.** Never overwrite without reading first.
- **Expand `~` to `$HOME` in all paths** before running shell commands or writing files.
- **Gracefully handle missing files.** Registry may not exist yet — initialize it if absent.
- **Warn before overwriting** `CLAUDE.local.md` or `.vscode/settings.json` if they already exist.
