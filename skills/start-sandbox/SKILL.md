---
name: start-sandbox
description: Create a lightweight workspace without an existing repo. Use when the user wants a quick isolated space for experiments, research, or a new project from scratch. Triggers on "sandbox", "quick workspace", "experiment", "scratch", "new project from scratch".
allowed-tools: [Read, Write, Edit, Bash]
---

**Respond in the user's language.**

You are creating a lightweight sandbox workspace — no existing repo required. Follow the steps below **in order**. Never skip ahead. Never batch multiple questions in a single message.

---

## Step 1 — Interactive dialogue (ONE question at a time, NEVER batch)

Ask each question separately, waiting for the user's answer before asking the next.

### 1a — Workspace name

Ask: **What should this workspace be called?**

- Must be in slug format: lowercase, hyphens only, no spaces.
- Examples: `research-perf-audit`, `experiment-new-api`, `scratch-oauth-flow`
- If the user provides something that doesn't match, suggest a corrected slug but accept their choice if they insist.

### 1b — Description

Ask: **Briefly describe the goal of this workspace** (2–3 sentences). This will be written to `CLAUDE.local.md` to give future Claude sessions context.

### 1c — Spec link

Ask: **Is there a spec or ticket link for this work?** (optional — "no" or Enter to skip)

---

## Step 2 — Allocate slot

### 2a — Read the registry

See `references/registry-format.md` for the full schema and allocation rules.

```bash
cat ~/.claude-workspaces/registry.json 2>/dev/null || echo '{"workspaces":{},"next_slot":1}'
```

Handle missing file gracefully — initialize empty registry if not found.

### 2b — Find the first free slot

Scan keys `1, 2, 3, ...` in `workspaces` and return the first missing key. This is the new slot number.

### 2c — Derive color and emoji

See `references/color-palette.md`. Compute: `index = (slot - 1) % 8`, then look up the corresponding hex color and emoji.

### 2d — Determine workspaces_root

1. Check for `.claude-workspaces.json` in the current directory:
   ```bash
   cat .claude-workspaces.json 2>/dev/null
   ```
2. If the file exists and has a `workspaces_root` key, use that value.
3. Otherwise, default to `~/workspaces`.

### 2e — Derive workspace path

Expand `~` to `$HOME` in `workspaces_root`, then:

```
workspace_path = <workspaces_root>/<slug>
```

---

## Step 3 — Recap and confirm

Show a clear summary of everything that will be created. For example:

```
Ready to create sandbox workspace:

  Name:   experiment-new-api
  Slot:   w2
  Color:  🟠 #3a2a15 (Orange)
  Path:   /Users/you/workspaces/experiment-new-api

Confirm? [Y/n]
```

Wait for the user's response. Accept: `y`, `yes`, `o`, `oui`, or empty (just Enter). **Anything else cancels** — tell the user the workspace was not created.

---

## Step 4 — Create workspace

Execute the following sub-steps in order. If any step fails, stop immediately and display the error.

### 4a — Create workspace directory

```bash
mkdir -p <workspace_path>
```

### 4b — Initialize git repository

```bash
git init <workspace_path>
```

### 4c — Generate CLAUDE.local.md

Write `<workspace_path>/CLAUDE.local.md`. See `references/generated-files.md` for the exact template.

- **mode**: `sandbox`
- **branch**: `N/A`
- **Repos section**: omit port — list only the workspace path itself (no sub-repos, no ports)
- Fill in slot, slug, creation date, user description, spec link.

### 4d — Generate .vscode/settings.json

Write `<workspace_path>/.vscode/settings.json` with the workspace color. See `references/generated-files.md` for the exact template.

```bash
mkdir -p <workspace_path>/.vscode
```

Fill in the hex color for `titleBar.activeBackground`, `titleBar.activeForeground`, `statusBar.background`, `statusBar.foreground`.

### 4e — Update registry

Read the registry again (always re-read before writing to avoid races), add the new workspace entry, and update `next_slot`.

See `references/registry-format.md` for the exact schema.

New entry structure for sandbox mode:

```json
{
  "<slot>": {
    "slug": "<slug>",
    "mode": "sandbox",
    "branch": null,
    "color": "<hex-color>",
    "emoji": "<emoji>",
    "created_at": "<ISO-8601-timestamp>",
    "project_root": null,
    "workspace_path": "<workspace_path>",
    "repos": [
      {
        "name": "<slug>",
        "path": "<workspace_path>",
        "port": null
      }
    ]
  }
}
```

Write the updated registry to `~/.claude-workspaces/registry.json`. Create the directory if needed:

```bash
mkdir -p ~/.claude-workspaces
```

### 4f — Color the terminal

Apply the workspace color to the current terminal session. See `references/color-palette.md` for OSC sequences.

```bash
# Set background color (OSC 11)
printf '\033]11;<hex-color>\007'

# Set window/tab title (OSC 0)
printf '\033]0;<emoji> <slug> [w<slot>]\007'
```

---

## Step 5 — Summary

Show a concise success message. For example:

```
✓ Sandbox workspace created!

  🟠 [w2] experiment-new-api
  Path: /Users/you/workspaces/experiment-new-api

Ready to go. Fresh git repo — start building!

Next steps:
  • cd /Users/you/workspaces/experiment-new-api
  • Open a new Claude Code session in the workspace directory
  • Use /ws:resume to reattach later
  • Use /ws:finish when done with this workspace
```

---

## Rules

- **Ultra lightweight** — no hooks, no ports, no project config required.
- **Always git init** — every sandbox workspace gets a fresh git repository.
- **One question at a time.** Never ask multiple questions in a single message.
- **Never create without confirmation.** Always show the recap (Step 3) and wait for explicit approval.
- **Always read the registry before writing.** Never overwrite without reading first.
- **Expand `~` to `$HOME` in all paths** before running shell commands or writing files.
- **Gracefully handle missing files.** Registry may not exist yet — initialize it if absent.
