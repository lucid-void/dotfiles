#!/usr/bin/env bash
# Bootstraps AstroNvim into ~/.config/nvim from the upstream template.
#
# This used to be vendored file-by-file under dots/dot_config/nvim/, but every
# file was the untouched scaffold — each plugin spec still had its
# `if true then return {} end -- WARN: REMOVE THIS LINE TO ACTIVATE THIS FILE`
# guard in place, README.md was the template's own install instructions, and
# neovim.yml was its CI workflow. There was no customization to track, just a
# copy-paste of AstroNvim/template. Cloning it here instead keeps this repo
# free of a vendored copy that has to be manually kept in sync with upstream.
#
# Once real customization happens (community.lua, lua/plugins/*, polish.lua),
# track just those specific files back in chezmoi the way dot_config/VSCodium
# tracks settings.json without vendoring the whole editor.
#
# Deliberately not `set -e` — see run_once_install_bat_theme.sh. This script
# sorts before install_browser_extensions, install_fonts,
# install_vscodium_extensions and setup_aria2, so an unreachable github.com
# used to stop all four from running.
set -uo pipefail

NVIM_DIR="$HOME/.config/nvim"

warn() { printf 'astronvim: %s\n' "$*" >&2; }

if [[ -e "$NVIM_DIR" ]]; then
  echo "astronvim: $NVIM_DIR already exists, skipping"
  exit 0
fi

if ! command -v git >/dev/null 2>&1; then
  warn "git not installed — skipping"
  exit 0
fi

echo "Installing AstroNvim..."

# Clone into a temp dir and move the finished tree into place. Cloning straight
# to $NVIM_DIR meant an interrupt left a half-populated ~/.config/nvim that
# still satisfies the `-e` check above — so the repair never happened and nvim
# started into a broken config. Staging makes the visible directory appear only
# once it is complete and .git has been stripped.
tmp="$(mktemp -d)" || { warn "could not create temp dir — skipping"; exit 0; }
trap 'rm -rf "$tmp"' EXIT

if ! git clone --depth=1 https://github.com/AstroNvim/template "$tmp/nvim"; then
  warn "clone failed — skipping (it will be retried on the next apply)"
  exit 0
fi

rm -rf "$tmp/nvim/.git"

mkdir -p "$(dirname "$NVIM_DIR")" || { warn "could not create $(dirname "$NVIM_DIR") — skipping"; exit 0; }
if ! mv "$tmp/nvim" "$NVIM_DIR"; then
  warn "could not move the clone into $NVIM_DIR — skipping"
  exit 0
fi

echo "AstroNvim installed to $NVIM_DIR"
exit 0
