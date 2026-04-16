---
name: resume
description: Load workspace context and resume work. Use at the start of every session in a workspace. Auto-detects current workspace from directory. Triggers on "resume workspace", "load context", "where was I", "continue working", "resume feature".
allowed-tools: [Read, Bash, Grep]
---

**Respond in the user's language.**

---

## Step 1 — Detect current workspace

Run:

```bash
pwd
```

Then read the registry:

```bash
cat ~/.claude-workspaces/registry.json 2>/dev/null || echo '{"workspaces":{},"next_slot":1}'
```

Compare the current directory against every `workspace_path` and `repos[].path` entry in the registry. Use longest-prefix matching.

- **Match found**: use that workspace entry. Continue to Step 2.
- **No match, workspaces exist**: display the workspace list (same format as `/workspace:list`) and ask the user which one to resume.
- **No match, no workspaces, or no workspaces for this directory**: inform the user and suggest all three options:
  > No workspace found for this directory. You can:
  > - `/workspace:attach` — attach a workspace to this existing directory (slot + color + context, no worktree)
  > - `/workspace:start-worktree` — create a new workspace with git worktree isolation
  > - `/workspace:start-sandbox` — create a lightweight isolated sandbox

---

## Step 2 — Read workspace context

Read `CLAUDE.local.md` from the workspace root:

```bash
cat <workspace_path>/CLAUDE.local.md
```

Extract the following fields:
- **Slot** (e.g. `w3`)
- **Mode** (`worktree` or `sandbox`)
- **Branch / slug**
- **Repos** list with paths and ports
- **Goal** — the user's stated objective
- **Spec** — link or "none"
- **Notes** — any free-form notes

If `CLAUDE.local.md` is missing but the registry has an entry for this workspace, warn the user:

> `CLAUDE.local.md` is missing from this workspace. The registry entry still exists. Want me to regenerate the context file?

---

## Step 3 — Read git state (in parallel)

For the primary repo (first repo in the workspace entry), run all four commands:

```bash
git -C <primary_repo_path> branch --show-current
git -C <primary_repo_path> log --oneline -10
git -C <primary_repo_path> status --short
git -C <primary_repo_path> diff --stat
```

---

## Step 4 — Color terminal

Run the color script (instant):

```bash
/bin/bash "${CLAUDE_PLUGIN_ROOT}/scripts/ws-color.sh"
```

---

## Step 5 — Display summary (5–7 lines MAX)

```
<emoji> **[w<slot>] <branch-or-slug>**

🎯 **Goal**: <description>
   Spec: <link or "none">

📜 **Last commits**:
   - <hash> <message>
   - <hash> <message>
   - <hash> <message>

🚧 **Work in progress**: <N> files modified (<X> insertions, <Y> deletions)
   Main files: <path>, <path>

📝 **Notes**: <notes or "none">
```

If the Goal section is empty in `CLAUDE.local.md`, add a line at the end:

> No goal recorded. Want me to fill it in?

---

## Step 6 — Propose ONE next step (contextual)

Based on the git state, propose exactly one action. Never impose — always phrase as a proposal.

- **Clean state** (no uncommitted changes): "Everything's clean. Ready to continue — where do you want to start?"
- **Uncommitted changes, no recent commit**: "You have N modified files not committed. Want to finish this step first?"
- **Uncommitted changes + recent commit exists**: "You're in the middle of something — `<files>` modified. Want me to look?"
- **Branch looks well advanced** (many commits, clean state): "Branch looks well advanced. Want to run tests and prepare a PR?"

---

## Rules

- Always read `CLAUDE.local.md` first before reading git state.
- Never execute modifying commands — this skill is read and display only, except for terminal coloring (Step 4).
- Keep the summary (Step 5) to 5–7 lines maximum.
- If `CLAUDE.local.md` is missing but the registry has the workspace, warn and offer to regenerate — do not stop silently.
- Use `workspaces_root` (with **s**) when referring to registry paths.
- Use `references/...` paths (not `@references/...`) when referencing project files.
