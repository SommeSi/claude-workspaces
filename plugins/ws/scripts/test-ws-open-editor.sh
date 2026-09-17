#!/usr/bin/env bash
# test-ws-open-editor.sh — self-check for ws-open-editor.sh (no editor launched).
# Usage: bash test-ws-open-editor.sh   → exits 1 on first failure.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
OPEN="$HERE/ws-open-editor.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export WS_EDITOR_NO_LAUNCH=1 WS_REGISTRY="$TMP/registry.json"

fail() { echo "✗ $1"; [ -n "${OUT:-}" ] && echo "--- output ---" && echo "$OUT"; exit 1; }
q() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print($2)" "$1"; }

# --- Multi-repo workspace with an existing .code-workspace ---
PROJ="$TMP/proj"; WS="$TMP/ws"
mkdir -p "$PROJ" "$WS/back" "$WS/front"
cat > "$PROJ/.claude-workspaces.json" <<EOF
{ "repos": [{"name":"back","origin":".","port_base":3001},{"name":"front","port_base":3000}],
  "terminal": { "type":"wezterm", "claude_tab": true, "panes": [
    {"repo":"front","cmd":"bun run dev --port \$PORT"},
    {"repo":"back","cmd":"bin/dev"},
    {"repo":".","cmd":null},
    {"repo":"back","cmd":"bin/jobs w\$SLOT"} ] } }
EOF
cat > "$WS_REGISTRY" <<EOF
{ "workspaces": { "4": { "slug":"feat-x", "branch":"feat/x", "color":"#112233", "emoji":"🔴",
  "project_root":"$PROJ", "workspace_path":"$WS",
  "repos":[{"name":"back","path":"$WS/back","port":3041},{"name":"front","path":"$WS/front","port":3040}] } } }
EOF
cat > "$WS/feat-x.code-workspace" <<EOF
{ "folders":[{"path":"back","name":"🔴 back"},{"path":"front","name":"🔴 front"}],
  "settings":{"workbench.colorCustomizations":{"titleBar.activeBackground":"#112233"},"custom":1},
  "tasks":{"version":"2.0.0","tasks":[{"label":"my task","type":"shell","command":"echo hi"},
                                      {"label":"ws: stale","type":"shell","command":"old"}]} }
EOF

OUT=$(bash "$OPEN" "$WS/back" 2>&1) || fail "script failed"
F="$WS/feat-x.code-workspace"
[ "$(q "$F" "[t['label'] for t in d['tasks']['tasks']]")" = "['my task', 'ws: front — bun run dev --port 3040', 'ws: back — bin/dev', 'ws: back — bin/jobs w4']" ] || fail "task labels: $(q "$F" "[t['label'] for t in d['tasks']['tasks']]")"
[ "$(q "$F" "d['tasks']['tasks'][1]['options']['cwd']")" = "$WS/front" ] || fail "absolute cwd"
[ "$(q "$F" "d['tasks']['tasks'][1]['runOptions']['runOn']")" = "folderOpen" ] || fail "runOn folderOpen"
[ "$(q "$F" "d['settings']['custom']")" = "1" ] || fail "settings preserved"
[ "$(q "$F" "len(d['folders'])")" = "2" ] || fail "folders preserved"
echo "$OUT" | grep -qF "vscode://anthropic.claude-code/open" || fail "claude tab announced"

# Idempotent
bash "$OPEN" "$WS" >/dev/null 2>&1 || fail "second run failed"
[ "$(q "$F" "len(d['tasks']['tasks'])")" = "4" ] || fail "idempotent task count"

# WS_PANES_JSON takes priority
WS_PANES_JSON='[{"repo":"back","cmd":"bin/rails s -p $PORT"}]' bash "$OPEN" "$WS" >/dev/null 2>&1 || fail "panes override run failed"
[ "$(q "$F" "[t['label'] for t in d['tasks']['tasks']]")" = "['my task', 'ws: back — bin/rails s -p 3041']" ] || fail "WS_PANES_JSON priority"

# --- Mono-repo workspace (attach), no .code-workspace, no terminal section, claude_tab default ---
SOLO="$TMP/solo"; mkdir -p "$SOLO"
echo '{ "repos": [{"name":"app","origin":".","port_base":4000}] }' > "$SOLO/.claude-workspaces.json"
python3 - "$WS_REGISTRY" "$SOLO" <<'EOF'
import json, sys
p, solo = sys.argv[1], sys.argv[2]
r = json.load(open(p))
r['workspaces']['5'] = {"slug": "solo", "branch": "main", "color": "#445566", "emoji": "🟣",
    "project_root": solo, "workspace_path": solo, "repos": [{"name": "app", "path": solo, "port": 4050}]}
json.dump(r, open(p, 'w'))
EOF
OUT=$(WS_PANES_JSON='[{"repo":".","cmd":"npm run dev -- --port $PORT"}]' bash "$OPEN" "$SOLO" 2>&1) || fail "solo run failed"
S="$SOLO/solo.code-workspace"
[ -f "$S" ] || fail "solo .code-workspace created"
[ "$(q "$S" "d['folders']")" = "[{'path': '.', 'name': '🟣 app'}]" ] || fail "solo folders: $(q "$S" "d['folders']")"
[ "$(q "$S" "d['settings']['workbench.colorCustomizations']['statusBar.background']")" = "#445566" ] || fail "solo colors"
[ "$(q "$S" "d['tasks']['tasks'][0]['command']")" = "npm run dev -- --port 4050" ] || fail "solo port for repo '.'"

# No panes at all → still opens, no tasks, exit 0
rm "$S"
OUT=$(bash "$OPEN" "$SOLO" 2>&1) || fail "no panes must not fail"
[ "$(q "$S" "len(d['tasks']['tasks'])")" = "0" ] || fail "no panes → no tasks"

# Unknown workspace → exit 1
bash "$OPEN" "$TMP/nowhere" >/dev/null 2>&1 && fail "unknown workspace must fail"

echo "✓ all ws-open-editor checks passed"
