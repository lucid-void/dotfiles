#!/usr/bin/env bash
# Installs/updates the VSCodium extensions dot_config/VSCodium/User/settings.json
# depends on. Runs on every `chezmoi apply` (plain `run_` prefix, not
# `run_once_`) so extensions get pulled to their latest version each time,
# not just installed once and left to drift.
set -euo pipefail

# Installed through codium's configured gallery. The vscodium-bin-marketplace
# package repoints that at the Microsoft marketplace, so only extensions
# published there belong in this list.
EXTENSIONS=(
  anthropic.claude-code
  # Required by settings.json's workbench.colorTheme / iconTheme keys —
  # without these the theme silently falls back to the VSCodium default.
  Catppuccin.catppuccin-vsc
  Catppuccin.catppuccin-vsc-icons
)

# Open VSX-only extensions. jeanp413 never published open-remote-ssh to the
# Microsoft marketplace, so `--install-extension jeanp413.open-remote-ssh`
# reports "not found" and fails the whole chezmoi apply. Fetch the VSIX from
# Open VSX directly instead of depending on whichever gallery is configured.
OPENVSX_EXTENSIONS=(
  jeanp413.open-remote-ssh
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

if ((${#OPENVSX_EXTENSIONS[@]})); then
  # Named after the extension rather than mktemp's random suffix so codium's
  # "was successfully installed" line names something recognisable.
  vsixdir=$(mktemp -d)
  trap 'rm -rf "$vsixdir"' EXIT

  for ext in "${OPENVSX_EXTENSIONS[@]}"; do
    echo "Installing $ext from Open VSX..."
    url=$(curl -fsSL "https://open-vsx.org/api/${ext%%.*}/${ext#*.}/latest" |
      jq -er '.files.download')
    curl -fsSL -o "$vsixdir/$ext.vsix" "$url"
    NODE_NO_WARNINGS=1 codium --install-extension "$vsixdir/$ext.vsix" --force
  done
fi
