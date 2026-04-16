#!/bin/bash
# ws-update.sh — Update claude-workspaces plugins to the latest version
# Usage: bash ws-update.sh
# Clones fresh from GitHub, bypasses Claude Code's broken cache system.

set -euo pipefail

CACHE_DIR="$HOME/.claude/plugins/cache/claude-workspaces"
MARKETPLACE_DIR="$HOME/.claude/plugins/marketplaces/claude-workspaces"
REPO_URL="https://github.com/SommeSi/claude-workspaces.git"
TMP_DIR="/tmp/claude-workspaces-update-$$"

echo "Updating claude-workspaces plugins..."

# 1. Clone latest from GitHub
git clone --depth 1 "$REPO_URL" "$TMP_DIR" 2>&1 | grep -v "^$" || true
echo "  ✓ Fetched latest from GitHub"

# 2. Clear old cache and marketplace
rm -rf "$CACHE_DIR"
rm -rf "$MARKETPLACE_DIR"
echo "  ✓ Cleared old cache"

# 3. Copy marketplace metadata
mkdir -p "$MARKETPLACE_DIR"
cp -R "$TMP_DIR/.claude-plugin" "$MARKETPLACE_DIR/"
cp -R "$TMP_DIR/plugins" "$MARKETPLACE_DIR/"

# 4. Read versions from plugin.json files and copy to cache
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
    echo "  ✓ $cache_name v$version"
  fi
done

# 5. Cleanup
rm -rf "$TMP_DIR"

echo ""
echo "Done! Restart Claude Code to apply."
