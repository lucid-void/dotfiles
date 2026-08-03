#!/usr/bin/env bash
# Installs MesloLGS NF — the one Nerd Font every consumer in this repo asks
# for (alacritty, ghostty, VSCodium). chezmoi re-runs this if the file
# changes (e.g. new fonts added).
set -euo pipefail

FONTS_DIR="$HOME/.local/share/fonts/NerdFonts"
mkdir -p "$FONTS_DIR"

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
