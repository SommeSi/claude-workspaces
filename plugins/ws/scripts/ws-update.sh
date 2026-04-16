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
declare -A PLUGIN_VERSIONS
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
    PLUGIN_VERSIONS[$cache_name]=$version
    echo "  ✓ $cache_name v$version"
  fi
done

# 5. Update installed_plugins.json with correct paths and versions
if [ -f "$INSTALLED_FILE" ]; then
  python3 -c "
import json, os

installed_path = os.path.expanduser('$INSTALLED_FILE')
cache_dir = os.path.expanduser('$CACHE_DIR')

try:
    data = json.load(open(installed_path))
except:
    data = {'plugins': {}}

plugins = data.get('plugins', data)
if isinstance(plugins, list):
    plugins = data

versions = {
$(for name in "${!PLUGIN_VERSIONS[@]}"; do
    echo "    '$name@claude-workspaces': '${PLUGIN_VERSIONS[$name]}',"
done)
}

for key, version in versions.items():
    name = key.split('@')[0]
    install_path = os.path.join(cache_dir, name, version)
    if key in plugins:
        for entry in plugins[key]:
            entry['installPath'] = install_path
            entry['version'] = version
    else:
        plugins[key] = [{
            'scope': 'user',
            'installPath': install_path,
            'version': version,
            'installedAt': '$(date -u +%Y-%m-%dT%H:%M:%S.000Z)',
            'lastUpdated': '$(date -u +%Y-%m-%dT%H:%M:%S.000Z)',
            'gitCommitSha': '$(git -C "$TMP_DIR" rev-parse HEAD 2>/dev/null || echo unknown)'
        }]

with open(installed_path, 'w') as f:
    json.dump(data, f, indent=4)
"
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
