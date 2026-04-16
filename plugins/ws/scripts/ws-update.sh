#!/bin/bash
# ws-update.sh — Update the workspace plugin to the latest version
# Usage: ws-update
# Cleans old cache versions and reinstalls from the marketplace.

set -euo pipefail

CACHE_DIR="$HOME/.claude/plugins/cache/claude-workspaces"
MARKETPLACE_DIR="$HOME/.claude/plugins/marketplaces/claude-workspaces"

echo "Updating claude-workspaces plugins..."

# 1. Remove all cached versions
rm -rf "$CACHE_DIR"
rm -rf "$MARKETPLACE_DIR"
echo "  ✓ Cleared cache"

# 2. Reinstall
claude plugins uninstall workspace 2>/dev/null || true
claude plugins uninstall auto-login 2>/dev/null || true

claude plugins marketplace add SommeSi/claude-workspaces 2>/dev/null
echo "  ✓ Marketplace refreshed"

claude plugins install workspace 2>/dev/null
claude plugins install auto-login 2>/dev/null
echo "  ✓ Plugins installed"

# 3. Show versions
echo ""
echo "Installed versions:"
for dir in "$CACHE_DIR"/workspace/*/; do
  [ -d "$dir" ] && echo "  workspace: $(basename "$dir")"
done
for dir in "$CACHE_DIR"/auto-login/*/; do
  [ -d "$dir" ] && echo "  auto-login: $(basename "$dir")"
done

echo ""
echo "Restart Claude Code to apply."
