#!/bin/bash
# ws-human-review.sh — open VS Code on the current workspace so the Claude Review
# extension shows the blocks to accept or reject. Read-only: never edits the
# .code-workspace or any setting (colours already live in the .code-workspace).
#
# Usage: ws-human-review.sh [path]      (defaults to $PWD)
#
# Env overrides (tests):
#   WS_REGISTRY   registry path (default ~/.claude-workspaces/registry.json)
#   WS_CODE_BIN   VS Code CLI to use (default: the app's bundled `code`, else `code` on PATH)

set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

TARGET="${1:-$PWD}"

# --- Workspace: longest registry workspace_path prefixing the directory ---
read -r SLUG WS_PATH < <(TARGET="$TARGET" python3 <<'PYEOF'
import json, os
reg = os.environ.get("WS_REGISTRY") or os.path.expanduser("~/.claude-workspaces/registry.json")
target = os.path.realpath(os.environ["TARGET"])
best, match = -1, ("", "")
try:
    data = json.load(open(reg))
    ws = data.get("workspaces", {}) if isinstance(data, dict) else data
    for w in (ws.values() if isinstance(ws, dict) else ws if isinstance(ws, list) else []):
        if not isinstance(w, dict) or not w.get("slug") or not w.get("workspace_path"):
            continue
        wp = os.path.realpath(w["workspace_path"])
        if target == wp or target.startswith(wp + os.sep):
            if len(wp) > best:
                best, match = len(wp), (w["slug"], wp)
except (OSError, ValueError, AttributeError, TypeError):
    pass
print(match[0] or "-", match[1] or "-")
PYEOF
)

if [ "${WS_PATH:--}" = "-" ]; then
  WS_PATH="$(git -C "$TARGET" rev-parse --show-toplevel 2>/dev/null)" \
    || { echo "human-review: no workspace and no git repo at $TARGET" >&2; exit 1; }
  SLUG="$(basename "$WS_PATH")"
fi

# --- What to open ---
if [ -f "$WS_PATH/$SLUG.code-workspace" ]; then
  OPEN="$WS_PATH/$SLUG.code-workspace"; KIND="workspace file"
else
  OPEN="$WS_PATH"; KIND="folder"
fi

# --- VS Code CLI (`code` is often only a zsh alias, absent from non-interactive shells) ---
CODE="${WS_CODE_BIN:-/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code}"
if [ ! -x "$CODE" ]; then
  CODE="$(command -v code)" || { echo "human-review: VS Code CLI not found" >&2; exit 1; }
fi

"$CODE" "$OPEN" || { echo "human-review: failed to launch VS Code" >&2; exit 1; }
echo "VS Code opened on $KIND: $OPEN"

# Captured first: under pipefail, `code ... | grep -q` fails when grep stops reading early.
EXTS="$("$CODE" --list-extensions 2>/dev/null || true)"
if ! grep -qix 'sommesi.claude-review' <<<"$EXTS"; then
  echo "The Claude Review extension (sommesi.claude-review) is not installed yet — VS Code is open without the review view."
fi
