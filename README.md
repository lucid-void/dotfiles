# dotfiles

Personal dotfiles managed with [chezmoi](https://chezmoi.io). Every install is **unattended** — nothing ever prompts, so the same repo works for a laptop, a Packer/cloud-init VM, and a Codespace.

## Desktop vs headless

There is exactly one axis of divergence: the `isDesktop` flag. **Desktop is the default** — you only ever pass a flag to opt *out*.

| | `isDesktop = true` (default) | `isDesktop = false` |
|---|---|---|
| **Use for** | Laptop, workstation | VMs, containers, Codespaces, remote nodes |
| **Install with** | `bash install.sh` | `bash install.sh --headless` |
| **GUI terminal configs**<br>alacritty, ghostty | ✅ deployed | ❌ skipped |
| **Desktop entries**<br>`.local/share/applications` | ✅ deployed | ❌ skipped |
| **System packages** (Arch) | all four lists | the two `headless` lists |
| **Everything else**<br>zsh, tmux, nvim, starship, git, ssh | ✅ | ✅ |

The exclusions live in [`dots/.chezmoiignore`](dots/.chezmoiignore); the flag itself is set in [`dots/.chezmoi.toml.tmpl`](dots/.chezmoi.toml.tmpl).

The flag is written into `~/.config/chezmoi/chezmoi.toml` on first install and reused from then on — later `chezmoi apply` / `chezmoi update` runs never ask again.

## What's included

| Tool | Purpose |
|------|---------|
| zsh + zinit | Shell with turbo-loaded plugins |
| starship | Prompt |
| tmux | Multiplexer |
| neovim | Editor |
| VSCodium | GUI editor (desktop only) |
| eza, bat, fd, ripgrep, fzf, zoxide | Modern CLI replacements |
| atuin | SQLite shell history — fuzzy search, per-dir filtering, sync (Ctrl-R) |
| carapace | Completion engine covering ~1000 CLIs |
| lazygit | Git UI |
| delta | Syntax-highlighting pager for `git diff` / `git log` |
| terraform, ansible, packer | Infrastructure tooling |
| fastfetch + pokeget | System info greeting |

All themeable tools use **Catppuccin Macchiato**.

---

## Install — desktop

The default. Clone anywhere you like; `sourceDir` is recorded from wherever you put it.

```bash
git clone https://github.com/lucid-void/dotfiles ~/dotfiles
cd ~/dotfiles
bash install.sh
```

---

## Install — headless

Same as desktop, minus the GUI configs (see the table above).

```bash
git clone https://github.com/lucid-void/dotfiles ~/dotfiles
cd ~/dotfiles
bash install.sh --headless
```

`DOTFILES_HEADLESS=1 bash install.sh` is equivalent, which is handy for provisioners that pass env rather than args.

---

## What `install.sh` does

Three phases. Only the middle one is required — the other two need root or **passwordless** sudo (`sudo -n`, so an unattended run can never hang on a password prompt) and are skipped with a warning if that isn't available.

| Phase | Does | Needs root |
|---|---|---|
| **pre** | Installs missing prerequisites (`curl`, `git`, `zsh`, `tar`, + `fontconfig` on desktop) via apt/dnf/pacman/apk, then the `packages/` lists on Arch | yes — skipped if unavailable |
| **main** | Installs chezmoi (if the package list didn't), applies dotfiles | no |
| **post** | Adds zsh to `/etc/shells`, `chsh` to zsh, pre-warms zinit | yes — skipped if unavailable |

The prerequisite step only runs when something is actually missing, so it is a no-op on an already-provisioned machine and won't touch your package manager unnecessarily.

If a phase is skipped, the script prints exactly what to run by hand and still exits 0. Nothing in the pre phase is fatal — a package that fails to install warns and the run continues, since **main** is the phase that actually matters.

---

## Package lists

Plain text, one package per line, `#` for comments. Live in [`packages/`](packages/).

| List | Installed on | Source |
|---|---|---|
| [`packages/headless.txt`](packages/headless.txt) | every machine, desktop included | official repos, via `pacman` |
| [`packages/headless-aur.txt`](packages/headless-aur.txt) | every machine, desktop included | AUR, via `paru` |
| [`packages/desktop.txt`](packages/desktop.txt) | desktop only | official repos, via `pacman` |
| [`packages/desktop-aur.txt`](packages/desktop-aur.txt) | desktop only | AUR, via `paru` |
| [`packages/browser-extensions.txt`](packages/browser-extensions.txt) | desktop only | Chrome Web Store, via `ExtensionInstallForcelist` policy |

Desktop installs all four; headless installs the two `headless` lists. The `-aur` split exists because a handful of CLI tools (`claude-code`, `carapace-bin`, `pokeget`) have no official-repo package.

**These lists replaced mise.** Every tool that used to be pinned in `dot_config/mise/config.toml` is now a system package on its repo version — there is no per-tool pinning and no version manager to activate. `pacman -Syu` is the update path.

**Arch only.** The lists hold pacman package names, which don't carry over to apt/dnf/apk — on any other distro the whole step is skipped with a notice and you get the four cross-distro prerequisites alone. ⚠️ Since mise is gone, that now means **a non-Arch host installs the dotfiles and no tools** — see the mise section in [TODO.md](TODO.md).

Notes:

- `pacman -Syu --needed` — a full sync rather than `-Sy`, because installing into a half-updated system is the classic Arch partial-upgrade breakage. Re-runs are cheap; `--needed` skips what's already present.
- `paru` is bootstrapped from `paru-bin` if no helper is present; an existing `paru` or `yay` is used as-is. The AUR step is **skipped when running as root**, since `makepkg` refuses to build as root — it needs a normal user with passwordless sudo.
- On this host several `-aur` entries resolve from the `cachyos` / `chaotic-aur` binary repos instead of being built locally. On vanilla Arch paru builds them from the AUR — same names either way.
- Skip the lists entirely with `bash install.sh --no-packages` (or `DOTFILES_SKIP_PACKAGES=1`) to get just the dotfiles.
- A few packages need one manual step after install: `rustup default stable`, and `solaar` installs udev rules that want a reload or reboot.

---

## Using chezmoi directly

`install.sh` is a wrapper; the underlying commands are:

```bash
# desktop (default)
chezmoi init --apply --source "$PWD"

# headless
chezmoi init --apply --promptBool isDesktop=false --source "$PWD"
```

> **Unattended gotcha:** chezmoi does *not* fall back to a template default when it can't reach a TTY — it aborts with `EOF`. So any non-interactive first install must pass `--promptBool isDesktop=<true|false>` explicitly. `install.sh` always does. The flag matches on the *prompt string*, which is why the prompt is literally `isDesktop`.

After the first install the answer is persisted in `~/.config/chezmoi/chezmoi.toml`, so plain `chezmoi apply` and `chezmoi update` are unattended-safe with no flags at all.

---

## Codespaces

GitHub Codespaces has native dotfiles support. Point it at this repo and it runs `install.sh` automatically — `CODESPACES` is detected and the install switches to headless with no interaction.

**Setup (one-time):**

1. Go to [github.com/settings/codespaces](https://github.com/settings/codespaces)
2. Under **Dotfiles**, enable *Automatically install dotfiles*
3. Select `lucid-void/dotfiles` as the repository

Every new Codespace will then bootstrap the full environment on creation.

---

## Browsers + AdNauseam — desktop only

Two browsers, both native AUR packages, both loading the same extension set.

| Browser | Package | Desktop entry | Overrides |
|---|---|---|---|
| Brave | `brave-origin-bin` | `brave-origin.desktop` | `/usr/share/applications/brave-origin.desktop` |
| ungoogled-chromium | `ungoogled-chromium-bin` | `chromium.desktop` | `/usr/share/applications/chromium.desktop` |

Each entry deliberately uses **the same filename as the system entry** — that is what makes `~/.local/share/applications` take precedence over `/usr/share/applications`. The only reason these files exist is to append the extension flags.

Those flags live in one place, [`dots/.chezmoitemplates/browser-extension-flags`](dots/.chezmoitemplates/browser-extension-flags), and both entries pull them in with `includeTemplate`. Add an extension there once and both browsers pick it up — they can't drift apart.

### AdNauseam installs itself

[`dots/run_once_install_adnauseam.sh.tmpl`](dots/run_once_install_adnauseam.sh.tmpl) downloads the latest release and unpacks it to `~/.local/share/adnauseam` during `chezmoi apply` — so `bash install.sh` gets you a working browser with no manual step. Desktop only; on headless the script renders down to an immediate `exit 0`.

The extension itself is **not** tracked in this repo — it's 20 MB of build output. It lives in `~/.local/share/adnauseam` and must stay there: Chromium reads that directory on every launch rather than copying it into the profile, so deleting it silently disables the extension.

The download uses `releases/latest/download/adnauseam.chromium.zip`, an unversioned alias the project publishes next to its versioned assets. That always tracks the newest release without parsing the GitHub API.

Every failure path — no network, no `unzip`, malformed archive — warns and exits 0 rather than failing the install, because a `run_once_` script that exits non-zero aborts the entire `chezmoi apply`. Chromium ignores a missing `--load-extension` directory, so a skipped install degrades quietly instead of breaking the browser.

**To update AdNauseam later**, `run_once_` means exactly that — the script won't fire again on its own:

```bash
rm -rf ~/.local/share/adnauseam
chezmoi state delete-bucket --bucket=scriptState
chezmoi apply
```

> Adding a second unpacked extension means appending to `--load-extension` as a comma-separated list of directories, not repeating the flag.

### Web store extensions — force-installed by policy

Everything in [`packages/browser-extensions.txt`](packages/browser-extensions.txt) is installed via an `ExtensionInstallForcelist` enterprise policy. `install.sh` reads the list and writes the same JSON to both browsers' policy directories:

```
/etc/chromium/policies/managed/extensions.json   # ungoogled-chromium
/etc/brave/policies/managed/extensions.json      # brave-origin
```

Both paths are compiled into the shipped binaries, not guesses. The browsers pick the policy up on next launch and install the extensions from the Chrome Web Store.

This is desktop-only, needs root or passwordless sudo, and is never fatal — without privileges `install.sh` warns and moves on. Malformed IDs are filtered out before the file is written, so one typo can't produce a policy the browser rejects wholesale.

> **Two caveats.** Force-installed extensions **cannot be disabled or removed from the browser UI** — the only way to drop one is to delete it from the list and re-run. And ungoogled-chromium ships with web store integration stripped, so whether it actually fetches the CRXs depends on the build; the policy is written for it either way. Brave is unaffected.

---

## Updating

Pull changes and re-apply:

```bash
chezmoi update
```

Update all managed tools — they're system packages now, so this is just a system update:

```bash
paru -Syu          # repo + AUR in one pass
pacman -Syu        # repo only
```

To pick up packages added to `packages/*.txt` since the last run, re-run the installer. `--needed` means already-installed packages are skipped:

```bash
bash install.sh    # add --headless on a non-desktop host
```

## Machine-local overrides

Source `~/.zshrc.local` for anything machine-specific (extra aliases, env vars, etc.) — it's loaded last and not tracked.

SSH host configs go in `~/.ssh/config.private` — included by the tracked SSH config but not committed.
