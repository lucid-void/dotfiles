#!/usr/bin/env bash
# Installs MesloLGS NF — the one Nerd Font every consumer in this repo asks
# for (alacritty, ghostty, VSCodium). chezmoi re-runs this if the file
# changes (e.g. new fonts added).
#
# Desktop-only: .chezmoiignore drops this on headless machines (matched by
# target name, `install_fonts.sh`, not the source filename).
#
# Deliberately not `set -e` — see run_once_install_bat_theme.sh for the full
# reasoning. A missing glyph is not worth aborting the rest of `chezmoi apply`
# over, and this script sorts before install_vscodium_extensions and
# setup_aria2.
set -uo pipefail

FONTS_DIR="$HOME/.local/share/fonts/NerdFonts"
BASE="https://github.com/romkatv/powerlevel10k-media/raw/master"
STYLES=("Regular" "Bold" "Italic" "Bold Italic")

warn() { printf 'fonts: %s\n' "$*" >&2; }

if ! command -v curl >/dev/null 2>&1; then
  warn "curl not installed — skipping"
  exit 0
fi

mkdir -p "$FONTS_DIR" || { warn "could not create $FONTS_DIR — skipping"; exit 0; }

tmp="$(mktemp -d)" || { warn "could not create temp dir — skipping"; exit 0; }
trap 'rm -rf "$tmp"' EXIT

echo "Installing MesloLGS NF..."

# Every style is downloaded to $tmp first and only moved into $FONTS_DIR once
# all four have arrived. Writing straight to the destination left a truncated
# .ttf behind on an interrupted transfer, which fc-cache then happily indexed;
# and a partial family is worse than none, because the missing styles fall back
# to a different font mid-render.
for style in "${STYLES[@]}"; do
  # `//`, not `/`: the single-slash form replaces only the *first* space, which
  # happens to be right for "Bold Italic" and silently wrong for any future
  # style name with two.
  encoded="${style// /%20}"
  if ! curl -fsSL --retry 3 --connect-timeout 20 --max-time 120 \
      -o "$tmp/MesloLGS NF ${style}.ttf" \
      "${BASE}/MesloLGS%20NF%20${encoded}.ttf"; then
    warn "download failed for '$style' — leaving the installed fonts untouched"
    exit 0
  fi
  if [[ ! -s "$tmp/MesloLGS NF ${style}.ttf" ]]; then
    warn "'$style' downloaded empty — leaving the installed fonts untouched"
    exit 0
  fi
done

for style in "${STYLES[@]}"; do
  if ! mv "$tmp/MesloLGS NF ${style}.ttf" "$FONTS_DIR/MesloLGS NF ${style}.ttf"; then
    warn "could not install '$style' into $FONTS_DIR"
  fi
done

# ── Rebuild font cache ─────────────────────────────────────────
# install.sh adds fontconfig to REQUIRED_CMDS in desktop mode, but a bare
# `chezmoi apply` on a machine that never ran install.sh won't have it.
if command -v fc-cache >/dev/null 2>&1; then
  fc-cache -f "$FONTS_DIR" >/dev/null 2>&1 \
    || warn "fc-cache failed — the fonts are installed but may not be visible yet"
  echo "Fonts installed."
else
  warn "fc-cache not installed — fonts written, run \`fc-cache -f\` yourself"
fi
exit 0
