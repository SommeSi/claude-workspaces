---
name: human-review
description: Open VS Code on the current workspace, in its colours, where the Claude Review extension shows the blocks to accept or reject. Use when the user wants to review what Claude changed. Triggers on "human review", "relire", "revue", "ouvre la revue", "/human_review".
user_invocable: true
allowed-tools: [Bash]
---

**Respond in the user's language.**

Opens VS Code on the current workspace so the user can review Claude's changes block by block. Never edits the `.code-workspace` or any setting.

---

## Step 1 — Open

One Bash call, nothing else:

```bash
/bin/bash "${CLAUDE_PLUGIN_ROOT}/scripts/ws-human-review.sh"
```

The script finds the workspace from the current directory (longest `workspace_path` in the registry, else the git top level), opens its `<slug>.code-workspace` (or the folder), and prints what it opened.

---

## Step 2 — Reply

Show the script output in one short sentence. If it says the Claude Review extension is not installed, say so and stop — do not install anything.

---

## Rules

- One Bash call, no other tool.
- Never modify the `.code-workspace`, VS Code settings, or the registry.
- Never install extensions.
