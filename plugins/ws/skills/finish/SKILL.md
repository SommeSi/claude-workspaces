---
name: finish
description: Finalize and clean up a workspace — safety checks, capture learnings, remove worktree, free slot. Use when the user is done with a feature, wants to clean up, or says "finish", "done", "close workspace", "remove workspace", "clean up".
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob]
---

**Respond in the user's language.**

You are finalizing and removing a workspace. The scripts do all the work; you only relay the recap and collect **one** confirmation. Do not run extra git/registry commands by hand — the preflight already did the thinking.

---

## Step 1 — Preflight (ONE call, read-only)

Run the preflight. It detects the workspace from the current directory, runs every safety check across all repos (filtered uncommitted files + merge-state vs the branch's real base), and prints a ready-to-show recap plus a machine block.

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/ws-finish-preflight.sh"
```

Parse the output:

- Everything **before** `===WS-FINISH-MACHINE===` is the human recap → show it to the user as-is (you may translate it).
- Everything **after** is `key=value` data for Step 3: `WS_SLOT`, `WS_PATH`, `WS_SLUG`, `WS_MODE`, `WS_PROJECT_ROOT`, `WS_CONFIG`, `WS_PORTS`, `OVERALL`.

Handle the edge cases:

- `OVERALL=none` **and** the output says "No workspace matches" → show the listed workspaces and ask which one to finish, then re-run the preflight with that path as the argument: `ws-finish-preflight.sh <workspace_path>`.
- `OVERALL=none` **and** the output says "no registry" → tell the user there are no workspaces to finish, and stop.

---

## Step 2 — The single validation

Show the recap, then ask **exactly one** question:

> Proceed? [y/N]

- Default is **NO**. Proceed only on an explicit `y` / `yes` / `oui`.
- The recap already lists every warning (uncommitted, unmerged) inline — do **not** split them into separate prompts. One recap, one question.
- If `OVERALL=warn`, the recap shows the work that will be lost; the same single `y/N` covers it.

Anything other than yes → tell the user the workspace was **not** removed, and stop.

---

## Step 3 — Execute (ONE call) + silent memory

On `yes`, run the orchestrated teardown. It kills the ports, runs the `pre_destroy` hook, drops the isolated `_w<slot>` DBs, removes the worktrees, deletes the directory (preserved in attached mode), frees the slot, resets the terminal, and closes the workspace window:

```bash
CONFIG="<WS_CONFIG>" PROJECT_ROOT="<WS_PROJECT_ROOT>" \
  /bin/bash "${CLAUDE_PLUGIN_ROOT}/scripts/ws-destroy.sh" "<WS_PATH>" "<WS_SLOT>"
```

(If `WS_CONFIG` is empty, omit the `CONFIG=` part — the script will locate it.)

**Then, silently** (no prompt, non-blocking): if anything genuinely worth remembering came up this session — a correction the user made, a non-obvious project constraint, a useful external resource — save it to the Claude memory directory (one file per fact with proper frontmatter) and add a one-line entry to `MEMORY.md`. Skip anything derivable from code or git history. Never interrupt the flow to ask about this.

---

## Step 4 — Summary

If the window wasn't closed (attached mode, or WezTerm absent), print a concise success line:

```
✅ Workspace w<slot> (<slug>) removed. Slot freed.
```

In worktree/sandbox mode the workspace window closes itself, so a summary may not be seen — that's expected.

---

## Rules

- **One question, total.** Detect and check silently; the only user interaction is the single `y/N` validation.
- **Never delete without that explicit yes.** Default is always NO.
- **Trust the scripts.** Don't re-run git status / merge checks / registry reads yourself — the preflight already did them and the destroy script is idempotent and best-effort (partial failures log and continue).
- **Attached mode never deletes the directory.** The main checkout is preserved; only the slot is freed.
- **Memory is silent and optional** — save in the background, never as a step that blocks the teardown.
