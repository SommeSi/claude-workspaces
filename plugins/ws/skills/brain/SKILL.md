---
name: brain
description: Open or refresh the team's knowledge graph ("le cerveau") — every reviewed lesson of the repos' `.claude/rules/`, by domain, with the PRs they came from — as a shared claude.ai page. Use when the user says "brain", "cerveau", "le graphe des règles", "ce qu'on a appris", "/brain".
---

**Respond in the user's language.** Three calls at most, no questions.

1. Build the data and the page (one Bash, run from inside the project, e.g. its back repo):
   ```bash
   D="$(mktemp -d)/brain" && mkdir -p "$D" && cp "${CLAUDE_PLUGIN_ROOT}/templates/brain.html" "$D/index.html" \
     && python3 "${CLAUDE_PLUGIN_ROOT}/scripts/ws-brain.py" --out "$D/brain.json" && echo "DIR=$D" \
     && python3 -c "import json,os;print('URL='+json.load(open(os.path.expanduser('~/.claude-workspaces/config.json'))).get('brain_url',''))" 2>/dev/null
   ```
2. Publish with the Artifact tool: `file_path` = `$D/index.html`, `files` = `{"brain.json": "$D/brain.json"}`.
   - `URL=` set → it is this user's page: first `action: "read"` on that URL (required before updating from a new conversation), then publish with `url` = that URL so the team keeps the same link.
   - `URL=` empty → first publish (`icon: "network"`), then save the returned link as `brain_url` in `~/.claude-workspaces/config.json` (one python one-liner, keep the other keys).
3. Reply with the link, the counts printed by step 1, and one line: the page is private until shared from its Share menu with the team.

The graph shows only what is merged on `develop` (reviewed team rules), never personal memory nor the unreviewed lesson inbox. Run it again after `/workspace:knowledge-review` PRs are merged.
