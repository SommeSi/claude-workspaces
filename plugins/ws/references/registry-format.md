# Registry Format

## Location

`~/.claude-workspaces/registry.json`

## Schema

```json
{
  "workspaces": {
    "<slot_number>": {
      "slug": "string — human-readable identifier (e.g. feat-polo-export-csv)",
      "mode": "worktree | sandbox",
      "branch": "string | null — git branch name (null for sandbox)",
      "color": "string — hex color (e.g. #1a3a2a)",
      "emoji": "string — emoji character",
      "created_at": "string — ISO 8601 timestamp",
      "project_root": "string | null — absolute path to the project that owns this workspace (null for sandbox)",
      "workspace_path": "string — absolute path to workspace root directory",
      "repos": [
        {
          "name": "string — repo identifier (e.g. back, front, app)",
          "path": "string — absolute path to this repo's worktree or directory",
          "port": "number | null — assigned port"
        }
      ]
    }
  },
  "next_slot": "number — hint for fast allocation, always max(slot) + 1"
}
```

## Slot Allocation

Find first free slot: scan keys 1, 2, 3... and return first missing key. Update `next_slot` to `max(all_keys) + 1` after any change.

## Reading the Registry

```bash
cat ~/.claude-workspaces/registry.json 2>/dev/null || echo '{"workspaces":{},"next_slot":1}'
```

Always handle missing file gracefully — initialize empty registry if not found.

## Writing the Registry

Always read → modify → write the full file. Use the Write tool, never append.

**IMPORTANT — Atomic writes to prevent corruption:**

Multiple Claude sessions may write to the registry concurrently. To prevent corruption (duplicate keys, truncated JSON), always write via this pattern:

```bash
# Write to a temp file first, then atomically move it
python3 -c "
import json, os, tempfile

registry_path = os.path.expanduser('~/.claude-workspaces/registry.json')

# Read current
try:
    reg = json.load(open(registry_path))
except (FileNotFoundError, json.JSONDecodeError):
    reg = {'workspaces': {}, 'next_slot': 1}

# ... modify reg ...

# Atomic write: temp file + rename (rename is atomic on POSIX)
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(registry_path), suffix='.json')
with os.fdopen(fd, 'w') as f:
    json.dump(reg, f, indent=2)
os.rename(tmp, registry_path)
"
```

Alternatively, when using the Write tool, write the entire JSON content in one operation — never use append or partial writes.

## Finding a Workspace by Current Directory

```bash
pwd
```

Then compare against all `workspace_path` and `repos[].path` entries in the registry. Match the longest prefix.
