# dotfiles

Personal dotfiles managed with [chezmoi](https://chezmoi.io). Targets three environments — desktop, headless nodes, and Codespaces — with shared config and per-environment divergence handled via chezmoi templating.

## What's included

| Tool | Purpose |
|------|---------|
| zsh + zinit | Shell with async plugins |
| starship | Prompt |
| tmux | Multiplexer |
| mise | Tool version manager |
| neovim | Editor |
| eza, bat, fd, ripgrep, fzf, zoxide | Modern CLI replacements |
| lazygit | Git UI |
| terraform, ansible, packer | Infrastructure tooling |
| fastfetch + pokeget | System info greeting |

All themeable tools use **Catppuccin Macchiato**.

---

## Desktop

Full install including GUI terminal configs (alacritty, ghostty).

```bash
git clone https://github.com/lucid-void/dotfiles ~/dotfiles
cd ~/dotfiles
bash install.sh
# Prompted: "Desktop machine?" → answer y
```

Or without cloning first:

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply lucid-void/dotfiles
# Prompted: "Desktop machine?" → answer y
```

---

## Headless nodes

Identical to desktop but GUI terminal configs are skipped (`.chezmoiignore` excludes alacritty/ghostty when `isDesktop = false`).

```bash
git clone https://github.com/lucid-void/dotfiles ~/dotfiles
cd ~/dotfiles
bash install.sh
# Prompted: "Desktop machine?" → answer n
```

Or without cloning first:

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply lucid-void/dotfiles
# Prompted: "Desktop machine?" → answer n
```

> **Note:** `install.sh` changes the login shell to zsh and pre-warms zinit. If zsh isn't available, install it first (`apt install zsh` / `dnf install zsh`).

---

## Codespaces

GitHub Codespaces has native dotfiles support. Point it at this repo and it runs `install.sh` automatically with no interaction required — the `CODESPACES=true` environment variable suppresses the desktop prompt and defaults to a headless profile.

**Setup (one-time):**

1. Go to [github.com/settings/codespaces](https://github.com/settings/codespaces)
2. Under **Dotfiles**, enable *Automatically install dotfiles*
3. Select `lucid-void/dotfiles` as the repository

Every new Codespace will then bootstrap the full environment on creation.

---

## Updating

Pull changes and re-apply:

```bash
chezmoi update
```

Update all managed tools:

```bash
mise_update   # defined in .zshrc — runs mise self-update && mise upgrade
```

## Machine-local overrides

Source `~/.zshrc.local` for anything machine-specific (extra aliases, env vars, etc.) — it's loaded last and not tracked.

SSH host configs go in `~/.ssh/config.private` — included by the tracked SSH config but not committed.
