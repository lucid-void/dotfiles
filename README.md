# dotfiles

Personal dotfiles managed with [chezmoi](https://chezmoi.io). Every install is **unattended** — nothing ever prompts, so the same repo works for a laptop, a Packer/cloud-init VM, and a Codespace.

## Desktop vs headless

There is exactly one axis of divergence: the `isDesktop` flag. **Desktop is the default** — you only ever pass a flag to opt *out*.

| | `isDesktop = true` (default) | `isDesktop = false` |
|---|---|---|
| **Use for** | Laptop, workstation | VMs, containers, Codespaces, remote nodes |
| **Install with** | `bash install.sh` | `bash install.sh --headless` |
| **GUI terminal configs**<br>alacritty, ghostty, kitty | ✅ deployed | ❌ skipped |
| **Desktop entries**<br>`.local/share/applications` | ✅ deployed | ❌ skipped |
| **System packages** (Arch) | all four lists | the two `headless` lists |
| **System packages** (Debian/Ubuntu) | `headless-apt.txt` only — desktop apps stay Arch-only | `headless-apt.txt` |
| **Everything else**<br>zsh, tmux, nvim, starship, git, ssh | ✅ | ✅ |

The exclusions live in [`dots/.chezmoiignore`](dots/.chezmoiignore); the flag itself is set in [`dots/.chezmoi.toml.tmpl`](dots/.chezmoi.toml.tmpl).

The flag is written into `~/.config/chezmoi/chezmoi.toml` on first install and reused from then on — later `chezmoi apply` / `chezmoi update` runs never ask again.

## What's included

| Tool | Purpose |
|------|---------|
| zsh + zinit | Shell with turbo-loaded plugins |
| starship | Prompt |
| tmux | Multiplexer |
| neovim + AstroNvim | Editor |
| VSCodium | GUI editor (desktop only) |
| eza, bat, fd, ripgrep, fzf, zoxide | Modern CLI replacements |
| carapace | Completion engine covering ~1000 CLIs |
| lazygit | Git UI |
| delta | Syntax-highlighting pager for `git diff` / `git log` |
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

Three phases. Only the middle one is required — the other two need root and are skipped with a warning if that isn't available.

| Phase | Does | Needs root |
|---|---|---|
| **pre** | Installs missing prerequisites (`curl`, `git`, `zsh`, `tar`, + `fontconfig` on desktop) via apt/dnf/pacman/apk, then the full `packages/` lists on Arch or Debian/Ubuntu | yes — skipped if unavailable |
| **main** | Installs chezmoi (if the package list didn't), applies dotfiles | no |
| **post** | Adds zsh to `/etc/shells`, `chsh` to zsh, pre-warms zinit | yes — skipped if unavailable |

The prerequisite step only runs when something is actually missing, so it is a no-op on an already-provisioned machine and won't touch your package manager unnecessarily.

If a phase is skipped, the script prints exactly what to run by hand and still exits 0. Nothing in the pre phase is fatal — a package that fails to install warns and the run continues, since **main** is the phase that actually matters.

**Root, without ever hanging on a password prompt.** Headless runs (VMs, Codespaces, CI)
only ever use `sudo -n` — passwordless or nothing, so an unattended run can never block
waiting for input. An interactive desktop run without passwordless sudo instead asks for
the password **once** (`sudo -v`), then keeps that credential alive in the background for
the rest of the script, instead of prompting-or-skipping at every privileged step.

---

## Package lists

Plain text, one package per line, `#` for comments. Live in [`packages/`](packages/).

| List | Installed on | Source |
|---|---|---|
| [`packages/headless.txt`](packages/headless.txt) | every Arch machine, desktop included | official repos, via `pacman` |
| [`packages/headless-apt.txt`](packages/headless-apt.txt) | every Debian/Ubuntu machine, desktop included | official repos, via `apt-get` |
| [`packages/headless-aur.txt`](packages/headless-aur.txt) | every Arch machine, desktop included | AUR, via `paru` |
| [`packages/desktop.txt`](packages/desktop.txt) | Arch desktop only | official repos, via `pacman` |
| [`packages/desktop-aur.txt`](packages/desktop-aur.txt) | Arch desktop only | AUR, via `paru` |
| [`packages/browser-extensions.txt`](packages/browser-extensions.txt) | desktop only | Chrome Web Store, via enterprise policy |

Desktop installs all four Arch lists; headless installs the two Arch `headless` lists. The `-aur` split exists because a handful of CLI tools (`claude-code`, `carapace-bin`, `pokeget`) have no official-repo package. That's an Arch packaging detail, not a platform restriction: `carapace` and `pokeget` are installed on the Debian/Ubuntu path too, as GitHub release binaries fetched by `install.sh`.

**These lists replaced mise.** Every tool that used to be pinned in `dot_config/mise/config.toml` is now a system package on its repo version — there is no per-tool pinning and no version manager to activate. `pacman -Syu` is the update path on Arch.

**Rust is the one exception:** the list installs `rustup`, not the repo's `rust`, so Arch and Debian/Ubuntu both end up on the same upstream toolchain and Rust can follow stable without waiting on the repo package. rustup works through shims, so there is still nothing to activate in `.zshrc` — but it ships *no* toolchain of its own, and `cargo` on a fresh Arch box fails with "no default toolchain" until one is selected. `install.sh` runs `rustup default stable` after the package step (skipped when a default is already set, so re-runs stay cheap). `rustup update` is the update path for the toolchain itself; `pacman -Syu` only moves rustup.

**Non-Arch parity.** On any host with `pacman`, the four Arch lists above are used. On a Debian/Ubuntu host (no `pacman`, but `apt-get`), `install.sh` installs `packages/headless-apt.txt` instead — full parity with `packages/headless.txt`'s tool set. Most names map straight to an apt package; `gh` comes from its own official apt repo (added automatically); `starship`, `rustup`, `lazygit`, `yq`, `gdu`, `bottom` and `fastfetch` have no apt package at all and are installed unprivileged via each project's official installer or GitHub release binary — into `~/.local/bin`, except `rustup`, which owns `~/.cargo/bin` (`.zshrc` adds both to `PATH`). `desktop.txt`/`desktop-aur.txt`/`headless-aur.txt` remain Arch/AUR-only — a Debian/Ubuntu host gets the headless tool set, not the desktop apps. On dnf (Fedora) or apk (Alpine) hosts the step is still skipped with a notice, same as before.

Notes:

- `pacman -Syu --needed` — a full sync rather than `-Sy`, because installing into a half-updated system is the classic Arch partial-upgrade breakage. Re-runs are cheap; `--needed` skips what's already present.
- `paru` is bootstrapped from `paru-bin` if no helper is present; an existing `paru` or `yay` is used as-is. The AUR step is **skipped when running as root**, since `makepkg` refuses to build as root — it needs a normal user with passwordless sudo.
- On this host several `-aur` entries resolve from the `cachyos` / `chaotic-aur` binary repos instead of being built locally. On vanilla Arch paru builds them from the AUR — same names either way.
- Skip the lists entirely with `bash install.sh --no-packages` (or `DOTFILES_SKIP_PACKAGES=1`) to get just the dotfiles.
- `solaar` installs udev rules that want a reload or reboot after install.

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

## Terminals — alacritty, ghostty, kitty in lockstep

All three ([`dots/dot_config/alacritty`](dots/dot_config/alacritty), [`dots/dot_config/ghostty`](dots/dot_config/ghostty), [`dots/dot_config/kitty`](dots/dot_config/kitty)) are deliberately kept identical: MesloLGS NF 14px, Catppuccin Macchiato, 2px padding, 50000-line scrollback (ghostty's is byte-based — set to 10MB, its own default, rather than an exact conversion), copy-on-select that writes to the system clipboard (not just the middle-click-paste selection), and `0.5` background opacity. Whichever one you open should look and behave the same.

Background blur is a Hyprland compositor-side window rule, not a per-terminal config option (ghostty's own `background-blur` setting only works through KWin's global setting, per its docs — irrelevant here). This host's Hyprland rice ([`dots-hyprland`](https://github.com/end-4/dots-hyprland)/quickshell, not part of this repo) disables blur for every window by default (`hyprland/rules.lua`: `no_blur = true` for `class = ".*"`). [`dots/dot_config/hypr/custom/rules.lua`](dots/dot_config/hypr/custom/rules.lua) re-enables blur for the three terminal classes (`Alacritty`, `kitty`, `com.mitchellh.ghostty`), layered on top of the untouched upstream rice the same way `custom/general.lua` already is — confirmed applied (checked via an intentionally-invalid test key, which surfaced Hyprland's on-screen config-error banner, and a `rounding = 0` test, which visibly squared off a fresh window's corners).

**Ghostty's transparency doesn't actually work on Linux, and that's not fixable from here.** Side-by-side against kitty at the same `0.5` opacity and the same blur rule, kitty is genuinely see-through and ghostty just looks slightly brighter. This is [a known, still-open upstream bug](https://github.com/ghostty-org/ghostty/issues/3449): GTK's scene graph blends ghostty's semi-transparent pixels against GTK's own opaque background *before* the Wayland compositor ever sees real per-pixel alpha, so no Hyprland-side rule can recover it — kitty and alacritty render directly via GL/EGL and aren't affected. `background-opacity` is left set in `ghostty/config` anyway so it does the right thing the day upstream fixes it.

Each terminal's Catppuccin Macchiato values come from that project's own official port (`catppuccin/alacritty`, ghostty's built-in `theme = Catppuccin Macchiato`, `catppuccin/kitty`) rather than being forced to byte-for-byte match each other — the three ports don't always agree on secondary colors like the text-selection background, and that's expected.

All three were validated against real binaries on this host: `alacritty --config-file ... -e true`, `ghostty +validate-config` / `+show-config`, and `kitty --config ... -e true` all report no errors or unrecognized keys.

**kitty replaced a pre-existing, uncommitted `~/.config/kitty/kitty.conf`** that used fish, JetBrains Mono Nerd Font, and a theme generated by [quickshell](https://quickshell.outfoxxed.me/) (this host's Hyprland widget shell) — none of which match this repo's zsh/MesloLGS/static-Catppuccin conventions. That file was backed up to `kitty.conf.pre-dotfiles-backup` rather than deleted. Its companion kittens (`search.py`, `scroll_mark.py` — custom in-terminal search/scroll-to-mark bindings) were left in place since the tracked `kitty.conf` doesn't reference them; they're inert but harmless.

---

## AstroNvim — cloned, not vendored

[`dots/run_once_install_astronvim.sh`](dots/run_once_install_astronvim.sh) clones [`AstroNvim/template`](https://github.com/AstroNvim/template) straight into `~/.config/nvim` during `chezmoi apply`, then strips its `.git`. Nothing under `dot_config/nvim/` is tracked in this repo — a prior vendored copy was removed because every file was still the untouched scaffold (each plugin spec had its `if true then return {} end` deactivation guard in place).

Once real customization happens — `community.lua`, `lua/plugins/*`, `polish.lua` — track those specific files back in chezmoi, the same way `dot_config/VSCodium/User/settings.json` is tracked without vendoring all of VSCodium.

**`run_once_` won't refire** if `~/.config/nvim` is deleted later on a host chezmoi already applied to — the fired-once state is tracked separately from the directory existing:

```bash
rm -rf ~/.config/nvim
chezmoi state delete-bucket --bucket=scriptState
chezmoi apply
```

Validated end-to-end on 2026-08-03: fresh clone, `nvim --headless "+Lazy! sync" +qa` bootstraps lazy.nvim and all 43 plugins with no errors, and `:checkhealth astronvim` reports clean.

---

## Browsers + AdNauseam — desktop only

Two browsers, both native AUR packages, both loading the same extension set.

| Browser | Package | Desktop entry | Overrides |
|---|---|---|---|
| Brave | `brave-origin-bin` | `brave-origin.desktop` | `/usr/share/applications/brave-origin.desktop` |
| ungoogled-chromium | `ungoogled-chromium-bin` | `chromium.desktop` | `/usr/share/applications/chromium.desktop` |

Each entry deliberately uses **the same filename as the system entry** — that is what makes `~/.local/share/applications` take precedence over `/usr/share/applications`. The only reason these files exist is to append the extension flags.

Those flags live in one place, [`dots/.chezmoitemplates/browser-extension-flags`](dots/.chezmoitemplates/browser-extension-flags), and both entries pull them in with `includeTemplate`. Add an extension there once and both browsers pick it up — they can't drift apart.

Only flags both browsers understand go in that template. `chromium.desktop` appends one more of its own, `--extension-mime-request-handling`, because that switch exists only in ungoogled-chromium — see [below](#installing-extensions-by-hand-on-ungoogled-chromium).

### AdNauseam installs and updates itself

[`dots/run_install_adnauseam.sh.tmpl`](dots/run_install_adnauseam.sh.tmpl) downloads the latest release and unpacks it to `~/.local/share/adnauseam` during `chezmoi apply` — so `bash install.sh` gets you a working browser with no manual step. Desktop only; on headless the script renders down to an immediate `exit 0`.

The extension itself is **not** tracked in this repo — it's 20 MB of build output. It lives in `~/.local/share/adnauseam` and must stay there: Chromium reads that directory on every launch rather than copying it into the profile, so deleting it silently disables the extension.

The download uses `releases/latest/download/adnauseam.chromium.zip`, an unversioned alias the project publishes next to its versioned assets. That always tracks the newest release without parsing the GitHub API.

**Updates come for free with `chezmoi apply`.** This is a `run_` script rather than `run_once_`, so it fires on every apply — but it gates itself on the version instead of on chezmoi's script state:

1. Read the installed version out of `~/.local/share/adnauseam/manifest.json`.
2. Follow the `releases/latest` redirect with a single HEAD request; the tag it lands on (`…/releases/tag/v3.28.8`) names the newest version. No GitHub API call, so no rate limit.
3. Compare the two with `sort -V`. If what's installed is already at or ahead of upstream, exit without downloading anything.

So an apply with no new release upstream costs one HEAD request and touches nothing on disk; an apply after a release prints `updating 3.28.7 -> 3.28.8` and swaps the directory. Re-running is always safe.

Version comparison is numeric, not lexical — `sort -V` puts 3.28.8 after 3.9.0, which a string compare gets backwards.

Every failure path — no network, no `unzip`, malformed archive — warns and exits 0 rather than failing the install, because a chezmoi script that exits non-zero aborts the entire `chezmoi apply`. Chromium ignores a missing `--load-extension` directory, so a skipped install degrades quietly instead of breaking the browser. If the version check itself can't reach GitHub, an existing install is left alone rather than clobbered by a blind download.

To force a reinstall of the current version anyway (a corrupted directory, say), delete it and re-apply — no `chezmoi state` surgery needed:

```bash
rm -rf ~/.local/share/adnauseam
chezmoi apply
```

> Adding a second unpacked extension means appending to `--load-extension` as a comma-separated list of directories, not repeating the flag.

### chromium-web-store re-enables the Web Store's install buttons

ungoogled-chromium ships with Chrome Web Store integration stripped out, so its install/update buttons don't do anything by default. [`dots/run_install_chromium_web_store.sh.tmpl`](dots/run_install_chromium_web_store.sh.tmpl) installs [NeverDecaf/chromium-web-store](https://github.com/NeverDecaf/chromium-web-store) unpacked into `~/.local/share/chromium-web-store`, the same way as AdNauseam above, and it's added to the same shared `--load-extension` flag.

Upstream documents installing this via an interactive step — flip `chrome://flags/#extension-mime-request-handling` to "Always prompt for install", then drag the released `.crx` onto the browser. Loading it unpacked skips that entirely: no manual drag. (The equivalent of that flag is set anyway, by the desktop entry rather than by hand — the extension's install buttons need it to do more than download. See [below](#installing-extensions-by-hand-on-ungoogled-chromium).)

It self-updates exactly like AdNauseam: `run_` rather than `run_once_`, gated on the version rather than on chezmoi's script state. The `releases/latest` redirect lands on `…/releases/tag/v1.5.5.3` and the installed manifest reads `1.5.5.3`, so the same `sort -V` compare works unchanged — a steady-state apply costs one HEAD request and touches nothing. To force a reinstall of the current version, delete the directory and re-apply; no `chezmoi state` surgery needed:

```bash
rm -rf ~/.local/share/chromium-web-store
chezmoi apply
```

A `.crx` is a small binary header glued in front of an ordinary zip. `unzip` finds the zip's central directory by scanning backward from EOF, so it extracts the extension fine — it just warns about the leading bytes and exits 1 even on success, so the script checks for `manifest.json` rather than the exit code.

### Installing extensions by hand on ungoogled-chromium

The two unpacked extensions above arrive without any of this — `--load-extension` bypasses the whole extension-install path. Installing anything *else* on ungoogled-chromium, whether by dropping a `.crx` on `chrome://extensions` or by clicking chromium-web-store's install button, needs two settings that Chrome has on by default and ungoogled-chromium does not. Both are set for you:

| Setting | Where it lives | Set by |
| --- | --- | --- |
| `chrome://flags/#extension-mime-request-handling` = "Always prompt for install" | command-line switch | `chromium.desktop` |
| Developer mode on `chrome://extensions` | profile preference | [`dots/run_enable_chromium_developer_mode.sh.tmpl`](dots/run_enable_chromium_developer_mode.sh.tmpl) |

**The flag** decides what happens when you navigate to a `.crx` URL: save it as a file (the default) or offer to install it. `--extension-mime-request-handling=always-prompt-for-install` on the `Exec=` line is exactly equivalent to flipping it in `chrome://flags`, which is why there's no manual flag flip in the setup. It's an ungoogled-chromium patch, not an upstream switch, so it lives in `chromium.desktop` rather than the shared flags template — Brave would just ignore it.

**Developer mode** has no switch. It's `extensions.ui.developer_mode` in `~/.config/chromium/Default/Preferences`, and the `ExtensionDeveloperModeSettings` enterprise policy can only permit or block the toggle, never turn it on — so the script patches the preference with `jq`. Brave is left alone; its Web Store integration is intact and doesn't need it.

That script runs on **every** apply, not `run_once_`, for one reason: Chromium keeps its preferences in memory and rewrites the file on exit, so patching them underneath a running browser accomplishes nothing. If Chromium is up, the script warns and skips — and a `run_once_` script that skipped would be marked done and never retried. Running every time means it keeps trying until Chromium is closed, and once the preference is set it exits without writing, so a steady-state apply touches nothing.

On a machine where Chromium has never started there is no profile to patch, so the script writes a `Preferences` containing only that one key. Chromium reads it on first launch and fills its defaults in around it.

To undo either: turn Developer mode off in the UI and it stays off until the next `chezmoi apply` — the script's job is to enable it, so remove the script if you want it gone for good.

### Web store extensions — one list, one mechanism

Everything in [`packages/browser-extensions.txt`](packages/browser-extensions.txt) gets installed on both browsers by [`dots/run_install_browser_extensions.sh.tmpl`](dots/run_install_browser_extensions.sh.tmpl): it downloads each CRX with `curl` and registers it locally through the browser's **External Extensions** directory. No root, no enterprise policy, one code path.

| Browser | Registration directory |
| --- | --- |
| ungoogled-chromium | `~/.config/chromium/External Extensions/<id>.json` |
| brave-origin | `~/.config/BraveSoftware/Brave-Origin/External Extensions/<id>.json` |

Both land the extension at Chromium's **`external-pref`** location, which is the one the browser UI leaves under your control — you can disable *and* remove each extension from `chrome://extensions`.

#### Why not the enterprise policy

For ungoogled-chromium the policy route is a dead end, and not for the reason you'd guess. The policy is read and parsed correctly — verbose logs show `Found mandatory policy file: /etc/chromium/policies/managed/extensions.json` and every ID entering the pending-install queue as `kExternalPolicyDownload`. What's missing is the other end of the wire: ungoogled-chromium domain-substitutes its compiled-in URLs, so `clients2.google.com/service/update2/crx` doesn't appear in the binary at all — only `clients2.9oo91e.qjz9zk`, which doesn't resolve. The policy is honoured; the downloader behind it is severed. Putting the real URL in the policy doesn't help either, since `external_update_url` takes the same dead path.

Brave's store path is intact, so an `ExtensionSettings` policy written to `/etc/brave/policies/managed/extensions.json` did work there, and `install.sh` wrote one for a while. It's retired: it needed root, it could seed a profile but never prune it, and it meant one list installed by two unrelated mechanisms that failed in different ways. `install.sh` now **deletes** both retired policy files instead of writing either.

> ⚠️ Removal is not optional. A policy naming these IDs outranks the local registration in the pending-install queue, so the working install never fires while it's there — `entered for update more than once. old location: kExternalPolicyDownload  new location: kExternalPref`. `install.sh` only removes a file it recognises as one it wrote, so an unrelated policy at the same path is left alone.

#### How the local install works

The store endpoint is only unreachable *from inside* ungoogled-chromium. `curl` fetches a valid signed CRX3 from it without trouble, and the External Extensions mechanism installs a CRX that's already on disk with no network at all — the same mechanism KDE's `plasma-browser-integration` uses via `/usr/share/chromium/extensions/`. So the script does the download itself and drops a JSON file per extension, per browser:

```json
{
  "external_crx": "/home/you/.local/share/chromium-extensions/<id>-<store-version>.crx",
  "external_version": "5.5.0"
}
```

The browser unpacks it into the profile at launch, no interaction. Verified end to end: `location: 2` (`EXTERNAL_PREF`), `disable_reasons: []` — disableable and removable. **Deleting a JSON uninstalls its extension on the next launch**, which is what makes the directory a genuine mirror of the list rather than a one-way install. Drop an ID from `browser-extensions.txt`, re-apply, and the script removes the JSON from both browsers along with the cached CRX.

`external_version` has to match the CRX's manifest exactly or the browser rejects the registration — note that the store's own filename pads it (`…_5_5_0_0.crx` for a manifest that says `5.5.0`), so the script reads the manifest rather than trusting the filename.

The "is there a newer build?" probe is one request for the whole list. The store's `response=updatecheck` mode takes an `x=` parameter per extension and answers with Omaha update2 XML — an `<app>` per ID carrying `version` (the manifest version, unpadded) and a `codebase` blob URL:

```xml
<app appid="dhdgffkkebhmkfjojejmpbldmpobfkfo" status="ok">
  <updatecheck codebase="https://…/DHDGFF…_5_5_0_0.crx" status="ok" version="5.5.0"/></app>
```

Downloads then go straight to `codebase`, so the build that is fetched is the same one the version check passed judgement on. IDs are batched 32 per request (64 in one ~3 KB URL is fine against the live endpoint; the cap just keeps the URL bounded as the list grows). A probe that fails leaves every version unknown, which re-downloads everything through the old per-ID redirect URL — slower, never wrong.

The store also picks *which* build to serve from the `prodversion` it's asked about. With two browsers sharing one CRX the script asks on behalf of the older of the two — a build that installs on the older one installs on the newer, never the reverse.

Like the AdNauseam script this is `run_`, not `run_once_` — a steady-state apply costs that single request (~0.1s) and touches nothing, while a new upstream build is picked up automatically. Bumping `external_version` is also what triggers the upgrade of an already-installed copy, so these genuinely stay current.

The CRXs are cached once in `~/.local/share/chromium-extensions/` (~30 MB for the current list) and shared by both browsers, because a fresh profile needs them to install from. Only the current version of each is retained. Install a second browser later and the next apply registers the cached CRXs with it without re-downloading anything.

This is desktop-only and never fatal: a failed download warns and is retried on the next apply, and malformed IDs are filtered out before anything is written.

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
