---
name: recall
description: Find a past Claude session (and how to resume it) from a few words — feature, ticket, client, branch. Use when the user says "retrouve la session", "le chat où on a fait X", "recall", "on avait fait ça quand ?", "/recall".
allowed-tools: [Bash]
---

**Respond in the user's language.** One call, no follow-up questions.

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/ws-knowledge.py" recall <keywords from the user's message>
```

Show the matches as returned (date, branches, title, summary, resume command). Sessions are indexed when they end (summary written by the `SessionEnd` capture), so very old sessions may be missing: then point to the native picker, `/resume` then **Ctrl+A** (all projects).

If the user only needs what was learned there, the lessons already live in the repos' `.claude/rules/` (loaded automatically) — resuming is only worth it to continue that exact work.
