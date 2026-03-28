#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

# ── 1. Install chezmoi ─────────────────────────────────────────
if ! command -v chezmoi &>/dev/null; then
  sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
fi

# ── 2. Apply dotfiles (non-interactive, CODESPACES=true bypasses prompts) ──
chezmoi init --apply --no-tty --source "$PWD"

# ── 3. Install all tools via mise ──────────────────────────────
if ! command -v mise &>/dev/null; then
  curl https://mise.run | sh
fi
mise install

# ── 4. Switch to zsh for subsequent sessions ───────────────────
ZSH_PATH="$(command -v zsh 2>/dev/null || true)"
if [[ -n "$ZSH_PATH" ]]; then
  sudo chsh -s "$ZSH_PATH" "$USER" 2>/dev/null || true

  # Pre-warm zinit so the first real terminal is fast
  zsh -ic '' 2>/dev/null || true
fi
