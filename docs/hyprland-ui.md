# Hyprland UI layer

Desktop-only configuration layered on top of [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland)
(the "illogical impulse" setup). Guarded by the existing `isDesktop` chezmoi variable, so
shell-only hosts (WSL, VMs, Codespaces) never receive any of it.

## Design rule

**Track only files that are ours. Never track upstream-unmodified files.**

end-4's dots are ~1100 tracked files with historically 60–150 commits/month. Vendoring any of
it means inheriting that merge burden forever. Everything here was verified to differ from
upstream before being added.

What that leaves:

| File | Why it's ours |
|---|---|
| `.config/hypr/custom/variables.lua` | 30 lines changed from the upstream stub — terminal, monitor layout, app launchers |
| `.config/hypr/custom/keybinds.lua` | 41 lines changed — HJKL focus/move binds |
| `.config/hypr/hypridle.conf` | idle timeouts raised to 30/45/60 min from upstream's 5/10/15 |
| `.config/fish/conf.d/fish_frozen_key_bindings.fish` | not present in upstream at all |
| `.config/alacritty/alacritty.toml` | **this host's live config — diverges from `main`, see below** |
| `.config/VSCodium/User/{settings,keybindings}.json` | editor prefs; runtime state excluded |

Deliberately **not** tracked, because they are upstream-unmodified:
`.config/fish/config.fish`, `.config/fish/auto-Hypr.fish`, all of `.config/matugen/`,
`.config/hypr/custom/scripts/`, and the empty `custom/*.lua` stubs.

`upstream` for these comparisons is the install-time clone at `~/.cache/dots-hyprland`.

## `custom/` is the supported extension point

`~/.config/hypr/hyprland.lua` sources `hyprland.*` first, then conditionally sources `custom.*`
(via `is_file_exists`). Upstream's own `variables.lua` header says to put changes there:

> Copy these to `~/.config/hypr/custom/variables.lua` to make changes in a dotfiles-update-friendly manner

So anything expressible in `custom/` survives a dots update. Two things are not.

## Known gaps

### 1. `hypridle.conf` has no override hook

There is no `custom/hypridle.conf`. Nothing in the quickshell tree or `~/.local/bin` reads or
writes it — the settings GUI exposes lock *appearance* options only, never the idle timeouts.
So this repo owns the **whole file**, and re-running end-4's installer will overwrite it.

Re-apply after any dots update:

```fish
chezmoi apply ~/.config/hypr/hypridle.conf
pkill -x hypridle; setsid hypridle >/dev/null 2>&1 &
```

### 2. Two edits live in upstream-tracked files and are NOT captured here

Both are *deletions*, which `custom/` cannot express:

- `.config/hypr/hyprland/keybinds.lua` — removed the `SUPER + Tab` overview toggle
- `.config/hypr/hyprland/rules.lua` — removed the Picture-in-Picture size window rule

These will silently return on the next dots update. Migrating them properly:

- **Window rules are additive**, so `custom/rules.lua` cannot delete upstream's PiP rule. Add a
  later, more specific rule that wins instead.
- **For the keybind**, `hl` exposes no raw passthrough or `unbind` — `hyprland/lib/init.lua`
  defines only `is_file_exists`, `create_if_not_exists`, `workspace_in_group`. Rebinding
  `SUPER + Tab` in `custom/keybinds.lua` is worth testing, but Hyprland tolerates duplicate
  binds, so verify the behavior rather than assuming it overrides.

### 3. `illogical-impulse/config.json` is intentionally unmanaged

The quickshell settings GUI writes it through `FileView.writeAdapter()`, and
[`FileView.atomicWrites` defaults to `true`](https://quickshell.org/docs/master/types/Quickshell.Io/FileView/)
— an atomic write replaces the file via rename.

- Under a **symlink** manager (stow), that destroys the link.
- Under **chezmoi**, the risk inverts: change a setting in the GUI, forget `chezmoi re-add`, and
  the next `chezmoi apply` silently reverts it.

With a single desktop host there is nothing to sync it to, so snapshot it manually when wanted:

```fish
cp ~/.config/illogical-impulse/config.json <somewhere-outside-chezmoi>
```

### 4. Generated colour files

`matugen` rewrites `.config/hypr/hyprland/colors.lua` and `.config/hypr/hyprlock/colors.conf`
on every wallpaper change, per `~/.config/matugen/config.toml`. They are in `.chezmoiignore`.
Version matugen *templates* if they are ever customised — never the outputs.

## Merge notes for `main`

- `.chezmoiignore` additions are wrapped in `# --- begin/end: hyprland UI layer ---` markers to
  keep the merge mechanical.
- **`.config/starship.toml` differs between `main` and this host and was left untouched.** Decide
  which version wins during the rework.
- **`.config/alacritty/alacritty.toml` is overwritten on this branch** with the live desktop
  version. `main`'s stays intact on `main`. The two are ~117 lines apart and were never in
  conflict — chezmoi has never been applied on this host, so `main`'s version was never deployed
  here and the live file came from the CachyOS/end-4 install:

  | | `main` | this branch (live desktop) |
  |---|---|---|
  | Font | MesloLGS NF, explicit bold/italic/offsets | end-4 / CachyOS defaults |
  | Theme | imports `catppuccin-macchiato.toml` | none |
  | Extras | — | `[general]` `working_directory`, `live_config_reload` |

  `catppuccin-macchiato.toml` is still tracked but is **no longer imported** by the branch's
  `alacritty.toml`, so it deploys as an inert file until the rework resolves this.
  `alacritty.toml.197afdd6.bak` (end-4 installer detritus) is deliberately not tracked.
- **VSCodium is guarded desktop-only.** If you want editor settings on WSL too, move
  `.config/VSCodium` out of the `{{ if not .isDesktop }}` block during the rework. Note
  `settings.json` contains Arch-specific paths (`/usr/lib/qt6/qml`, `/usr/bin/qmlls6`) that are
  inert but meaningless elsewhere.
- This branch reuses the existing `isDesktop` variable rather than introducing a host-class
  variable. If the rework adds finer-grained host classes, the guards above should move to it.
