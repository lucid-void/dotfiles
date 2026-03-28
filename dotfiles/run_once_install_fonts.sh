#!/usr/bin/env bash
# Installs FiraCode Nerd Font and MesloLGS NF.
# chezmoi re-runs this if the file changes (e.g. new fonts added).
set -euo pipefail

FONTS_DIR="$HOME/.local/share/fonts/NerdFonts"
mkdir -p "$FONTS_DIR"

# ── FiraCode Nerd Font ─────────────────────────────────────────
echo "Installing FiraCode Nerd Font..."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.tar.xz" \
  | tar -xJ -C "$tmp"
find "$tmp" -name "*.ttf" ! -name "*Windows*" -exec cp {} "$FONTS_DIR/" \;

# ── MesloLGS NF (romkatv variant) ─────────────────────────────
echo "Installing MesloLGS NF..."
base="https://github.com/romkatv/powerlevel10k-media/raw/master"
for style in "Regular" "Bold" "Italic" "Bold Italic"; do
  encoded="${style/ /%20}"
  curl -fsSL "${base}/MesloLGS%20NF%20${encoded}.ttf" \
    -o "$FONTS_DIR/MesloLGS NF ${style}.ttf"
done

# ── Rebuild font cache ─────────────────────────────────────────
fc-cache -f "$FONTS_DIR"
echo "Fonts installed."
