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
#
# Deliberately not `set -e`. A chezmoi script that exits non-zero aborts the
# whole `chezmoi apply`, and chezmoi runs scripts in target-name order — this
# one sorts before install_browser_extensions, install_fonts,
# install_vscodium_extensions and setup_aria2. A single 5xx from GitHub raw
# used to mean none of those ran. A colour theme is not worth that, so every
# failure path below warns and exits 0.
set -uo pipefail

THEME_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bat/themes"
THEME_URL="https://github.com/catppuccin/bat/raw/main/themes/Catppuccin%20Macchiato.tmTheme"
THEME_FILE="$THEME_DIR/Catppuccin Macchiato.tmTheme"

warn() { printf 'bat-theme: %s\n' "$*" >&2; }

if ! command -v curl >/dev/null 2>&1; then
  warn "curl not installed — skipping"
  exit 0
fi

mkdir -p "$THEME_DIR" || { warn "could not create $THEME_DIR — skipping"; exit 0; }

echo "Installing bat Catppuccin Macchiato theme..."

# Download to a temp file and move into place: writing straight to the
# destination leaves a truncated .tmTheme there when the transfer is cut off,
# and bat then caches the broken theme.
tmp="$(mktemp)" || { warn "could not create temp file — skipping"; exit 0; }
trap 'rm -f "$tmp"' EXIT

if ! curl -fsSL --retry 3 --connect-timeout 20 --max-time 60 -o "$tmp" "$THEME_URL"; then
  warn "download failed — keeping whatever theme is already installed"
  exit 0
fi

if [[ ! -s "$tmp" ]]; then
  warn "downloaded theme is empty — skipping"
  exit 0
fi

# mktemp creates 0600 and mv preserves it; the theme is not a secret, so put it
# back to the mode a plain `curl -o` would have produced.
chmod 644 "$tmp" 2>/dev/null

if ! mv "$tmp" "$THEME_FILE"; then
  warn "could not write $THEME_FILE — skipping"
  exit 0
fi

if command -v bat >/dev/null 2>&1; then
  if bat cache --build >/dev/null 2>&1; then
    echo "bat theme installed and cache rebuilt."
  else
    warn "theme written, but \`bat cache --build\` failed — run it yourself"
  fi
else
  echo "bat not on PATH — theme written, cache will build on first use."
fi
exit 0
