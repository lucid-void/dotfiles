#!/usr/bin/env bash
# Installs/updates the VSCodium extensions dot_config/VSCodium/User/settings.json
# depends on. Runs on every `chezmoi apply` (plain `run_` prefix, not
# `run_once_`) so extensions get pulled to their latest version each time,
# not just installed once and left to drift.
set -euo pipefail

EXTENSIONS=(
  anthropic.claude-code
  ms-vscode-remote.remote-ssh
  ms-vscode-remote.remote-ssh-edit
  ms-vscode.remote-explorer
  # Required by settings.json's workbench.colorTheme / iconTheme keys —
  # without these the theme silently falls back to the VSCodium default.
  Catppuccin.catppuccin-vsc
  Catppuccin.catppuccin-vsc-icons
)

if ! command -v codium >/dev/null 2>&1; then
  echo "codium not on PATH — skipping extension install."
  exit 0
fi

for ext in "${EXTENSIONS[@]}"; do
  echo "Installing $ext..."
  # NODE_NO_WARNINGS silences codium's own DEP0169 url.parse() deprecation
  # noise (upstream cliProcessMain.js, not ours to fix) on every extension.
  NODE_NO_WARNINGS=1 codium --install-extension "$ext" --force
done
