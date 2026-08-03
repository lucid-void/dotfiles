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
set -euo pipefail

NVIM_DIR="$HOME/.config/nvim"

if [[ -e "$NVIM_DIR" ]]; then
  echo "astronvim: $NVIM_DIR already exists, skipping"
  exit 0
fi

echo "Installing AstroNvim..."
git clone --depth=1 https://github.com/AstroNvim/template "$NVIM_DIR"
rm -rf "$NVIM_DIR/.git"
echo "AstroNvim installed to $NVIM_DIR"
