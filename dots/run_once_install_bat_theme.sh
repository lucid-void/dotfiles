#!/usr/bin/env bash
# Installs the Catppuccin Macchiato theme for bat and rebuilds its cache.
#
# This used to live inside a `if mise is not installed` block in .zshrc, so it
# only ever fired on a first-ever install and never again. chezmoi re-runs this
# script whenever its contents change.
#
# bat comes from packages/headless.txt. If it isn't on PATH yet (non-Arch host,
# or the pre phase was skipped) the theme is still written, and `bat cache
# --build` is simply skipped — bat picks the theme up the next time it runs.
set -euo pipefail

THEME_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bat/themes"
THEME_URL="https://github.com/catppuccin/bat/raw/main/themes/Catppuccin%20Macchiato.tmTheme"

mkdir -p "$THEME_DIR"

echo "Installing bat Catppuccin Macchiato theme..."
curl -fsSL "$THEME_URL" -o "$THEME_DIR/Catppuccin Macchiato.tmTheme"

if command -v bat >/dev/null 2>&1; then
  bat cache --build >/dev/null
  echo "bat theme installed and cache rebuilt."
else
  echo "bat not on PATH — theme written, cache will build on first use."
fi
