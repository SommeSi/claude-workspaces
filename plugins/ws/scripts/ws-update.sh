#!/bin/bash
# ws-update.sh — Update claude-workspaces plugins to the latest version
# Usage: bash ws-update.sh
# Clones fresh from GitHub, bypasses Claude Code's broken cache system.

set -euo pipefail

CACHE_DIR="$HOME/.claude/plugins/cache/claude-workspaces"
MARKETPLACE_DIR="$HOME/.claude/plugins/marketplaces/claude-workspaces"
INSTALLED_FILE="$HOME/.claude/plugins/installed_plugins.json"
REPO_URL="https://github.com/SommeSi/claude-workspaces.git"
TMP_DIR="/tmp/claude-workspaces-update-$$"

echo "Updating claude-workspaces plugins..."

# 1. Clone latest from GitHub
git clone --depth 1 "$REPO_URL" "$TMP_DIR" 2>&1 | grep -v "^$" || true
echo "  ✓ Fetched latest from GitHub"

# 2. Clear ALL old cache and marketplace (every version)
rm -rf "$CACHE_DIR"
rm -rf "$MARKETPLACE_DIR"
echo "  ✓ Cleared old cache"

# 3. Copy marketplace metadata
mkdir -p "$MARKETPLACE_DIR"
cp -R "$TMP_DIR/.claude-plugin" "$MARKETPLACE_DIR/"
cp -R "$TMP_DIR/plugins" "$MARKETPLACE_DIR/"

# 4. Read versions from plugin.json files and copy to cache
# Newline-separated "cache_name:version" pairs — bash 3.2 (macOS default) has
# no associative arrays, so we accumulate into a single string and let python
# parse it in step 5. Don't switch to `declare -A` without bumping the shebang
# to /opt/homebrew/bin/bash, which isn't guaranteed to exist on the user's box.
PLUGIN_INFO=""
for plugin_dir in "$TMP_DIR"/plugins/*/; do
  plugin_name=$(basename "$plugin_dir")
  if [ -f "$plugin_dir/.claude-plugin/plugin.json" ]; then
    version=$(python3 -c "import json; print(json.load(open('$plugin_dir/.claude-plugin/plugin.json'))['version'])")
    # Map directory name to plugin name
    case "$plugin_name" in
      ws) cache_name="workspace" ;;
      *) cache_name="$plugin_name" ;;
    esac
    mkdir -p "$CACHE_DIR/$cache_name/$version"
    cp -R "$plugin_dir"/ "$CACHE_DIR/$cache_name/$version/"
    PLUGIN_INFO="${PLUGIN_INFO}${cache_name}:${version}
"
    echo "  ✓ $cache_name v$version"
  fi
done

# 5. Update installed_plugins.json with correct paths and versions
if [ -f "$INSTALLED_FILE" ]; then
  COMMIT_SHA=$(git -C "$TMP_DIR" rev-parse HEAD 2>/dev/null || echo unknown)
  INSTALLED_FILE="$INSTALLED_FILE" CACHE_DIR="$CACHE_DIR" \
  PLUGIN_INFO="$PLUGIN_INFO" COMMIT_SHA="$COMMIT_SHA" \
  python3 <<'PYEOF'
import json, os, datetime

installed_path = os.environ['INSTALLED_FILE']
cache_dir = os.environ['CACHE_DIR']
plugin_info = os.environ['PLUGIN_INFO']
commit_sha = os.environ['COMMIT_SHA']

versions = {}
for line in plugin_info.strip().split('\n'):
    line = line.strip()
    if not line or ':' not in line:
        continue
    name, ver = line.split(':', 1)
    versions[f'{name}@claude-workspaces'] = ver

try:
    data = json.load(open(installed_path))
except Exception:
    data = {'plugins': {}}

plugins = data.get('plugins', {})
if not isinstance(plugins, dict):
    plugins = {}
    data['plugins'] = plugins

now = datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S.000Z')
for key, version in versions.items():
    name = key.split('@')[0]
    install_path = os.path.join(cache_dir, name, version)
    if key in plugins:
        for entry in plugins[key]:
            entry['installPath'] = install_path
            entry['version'] = version
            entry['lastUpdated'] = now
            entry['gitCommitSha'] = commit_sha
    else:
        plugins[key] = [{
            'scope': 'user',
            'installPath': install_path,
            'version': version,
            'installedAt': now,
            'lastUpdated': now,
            'gitCommitSha': commit_sha,
        }]

with open(installed_path, 'w') as f:
    json.dump(data, f, indent=4)
PYEOF
  echo "  ✓ Updated installed_plugins.json"
fi

# 6. Cleanup
rm -rf "$TMP_DIR"

echo ""
echo "Installed:"
ls -d "$CACHE_DIR"/*/* 2>/dev/null | while read dir; do
  plugin=$(basename "$(dirname "$dir")")
  version=$(basename "$dir")
  echo "  $plugin v$version"
done

echo ""
echo "Restart Claude Code to apply."
