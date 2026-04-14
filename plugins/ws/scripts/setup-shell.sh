#!/bin/bash
# setup-shell.sh — Add workspace auto-color hook to your shell config.
# Supports zsh (.zshrc) and bash (.bashrc).
# Safe to run multiple times — skips if already installed.

set -euo pipefail

MARKER="# [claude-workspaces] auto-color hook"

HOOK_CODE='
'"$MARKER"'
# Upsearches from $PWD up to 3 levels so .worktree-env.sh at the workspace
# root applies to any cd into the workspace or its sub-directories.
chpwd_worktree() {
  local dir="$PWD"
  local found=""
  local i
  for i in 1 2 3; do
    if [[ -f "$dir/.worktree-env.sh" ]]; then
      found="$dir/.worktree-env.sh"
      break
    fi
    dir="$(dirname "$dir")"
    [[ "$dir" == "/" ]] && break
  done

  if [[ -n "$found" ]]; then
    source "$found"
  elif [[ -n ${WS_SLOT:-} ]]; then
    # Leaving a workspace — reset background + title
    printf '"'"'\033]111\007'"'"'
    printf '"'"'\033]1337;SetUserVar=panetitle=%s\007'"'"' "$(echo -n '"'"''"'"' | base64)"
    unset WS_SLOT WS_BRANCH WS_COLOR WS_EMOJI
  fi
}
'

# Shell-specific hook registration
ZSH_REGISTER='chpwd_functions+=(chpwd_worktree)
chpwd_worktree  # apply on shell startup
# [/claude-workspaces]'

BASH_REGISTER='__ws_prompt_command() { chpwd_worktree; }
if [[ ! "$PROMPT_COMMAND" == *__ws_prompt_command* ]]; then
  PROMPT_COMMAND="__ws_prompt_command;${PROMPT_COMMAND:-}"
fi
chpwd_worktree  # apply on shell startup
# [/claude-workspaces]'

detect_shell_config() {
  local shell_name
  shell_name="$(basename "${SHELL:-/bin/bash}")"
  case "$shell_name" in
    zsh)  echo "$HOME/.zshrc" ;;
    bash) echo "$HOME/.bashrc" ;;
    *)    echo "$HOME/.${shell_name}rc" ;;
  esac
}

main() {
  local rc_file
  rc_file="$(detect_shell_config)"
  local shell_name
  shell_name="$(basename "${SHELL:-/bin/bash}")"

  echo "Shell detected: $shell_name"
  echo "Config file:    $rc_file"

  # Check if already installed
  if [[ -f "$rc_file" ]] && grep -qF "$MARKER" "$rc_file"; then
    echo "Already installed in $rc_file — skipping."
    echo "To reinstall, remove the block between '$MARKER' and '# [/claude-workspaces]' first."
    exit 0
  fi

  # Pick the right registration block
  local register
  if [[ "$shell_name" == "zsh" ]]; then
    register="$ZSH_REGISTER"
  else
    register="$BASH_REGISTER"
  fi

  # Append to rc file
  echo "" >> "$rc_file"
  echo "$HOOK_CODE" >> "$rc_file"
  echo "$register" >> "$rc_file"

  echo "Installed workspace auto-color hook in $rc_file"
  echo ""
  echo "Restart your terminal or run:"
  echo "  source $rc_file"
}

main "$@"
