#!/usr/bin/env bash
# Installs the Catppuccin Macchiato theme for bat and keeps its cache valid.
#
# This is a `run_` script, not `run_once_`, because bat's binary cache is tied
# to the exact bat version that built it. Swap the binary — an upgrade, or an
# Arch host's /usr/bin/bat giving way to Debian's batcat symlink — and every
# later bat run prints
#
#   [bat error]: The binary caches ... are not compatible with this version
#
# on stderr. .zshrc aliases `cat` to bat, so that lands on nearly every command
# the shell runs. A run_once_ script structurally cannot repair it: the cache
# breaks long after the only time it would ever fire.
#
# The cost of running every apply is one `bat -p /dev/null` in the common case.
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

# Debian and Ubuntu ship the binary as `batcat`; install.sh symlinks it to
# ~/.local/bin/bat, but that directory is not necessarily on PATH for the
# non-interactive shell chezmoi runs scripts in, so accept either name.
BAT="$(command -v bat 2>/dev/null || command -v batcat 2>/dev/null || true)"

# Fast path. One command settles both failure modes at once: a theme file that
# was never written, and a cache built by a different bat. `bat -p /dev/null`
# reads ~/.config/bat/config, so it exits non-zero on an unknown theme name as
# well as on an incompatible cache.
if [[ -f "$THEME_FILE" && -n "$BAT" ]] && "$BAT" -p /dev/null >/dev/null 2>&1; then
  exit 0
fi

if [[ ! -f "$THEME_FILE" ]]; then
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

  # mktemp creates 0600 and mv preserves it; the theme is not a secret, so put
  # it back to the mode a plain `curl -o` would have produced.
  chmod 644 "$tmp" 2>/dev/null

  if ! mv "$tmp" "$THEME_FILE"; then
    warn "could not write $THEME_FILE — skipping"
    exit 0
  fi
fi

if [[ -z "$BAT" ]]; then
  echo "bat not on PATH — theme written, cache will build on first use."
  exit 0
fi

# Reached only when the fast-path probe failed, so the cache is missing, stale
# or version-mismatched either way — rebuild unconditionally.
if "$BAT" cache --build >/dev/null 2>&1; then
  echo "bat theme installed and cache rebuilt."
else
  warn "theme written, but \`bat cache --build\` failed — run it yourself"
fi
exit 0
