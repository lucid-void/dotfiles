# TODO

## Repo revision pass

Going through every configured app one by one — reviewing config, swapping out
apps that are being replaced. Layout stays as-is (chezmoi, `dots/` source root,
desktop/headless split via `isDesktop`).

Legend: `[ ]` not started · `[~]` in progress · `[x]` done

### Editors

- [x] **VSCodium** — `dots/dot_config/VSCodium/User/` — `settings.json` +
      `keybindings.json` now tracked. Desktop-only. See open items below.
- [ ] **Neovim / AstroNvim** — `dots/dot_config/nvim/` — 15 files: `init.lua`,
      `lazy_setup.lua`, `community.lua`, `polish.lua`, 7 × `lua/plugins/*`, plus
      `.luarc.json`, `.neoconf.json`, `.stylua.toml`, `selene.toml`, `neovim.yml`.
      Biggest single config in the repo. Decide: keep AstroNvim or go bare/LazyVim?

### Shell

- [x] **zsh** — `dots/dot_zshrc.tmpl` — merged with the previous standalone zshrc.
      See the dedicated section below for what changed and what's still open.
- [x] **zinit** — turbo loading reworked: correct ice mods and load order, plus
      autopair / OMZP::sudo / fzf-git.sh added. See the zsh section below.
- [ ] **starship** — `dots/dot_config/starship.toml`

### Terminals (desktop only)

- [x] **alacritty** — revised and validated against alacritty 0.17.0. See
      "Terminals — TERM settled" below.
- [x] **ghostty** — brought to parity with alacritty. ⚠️ **unvalidated** — ghostty
      is not installed on this host. See below.
- [x] **tmux** — `dots/dot_tmux.conf` — revised; see the section below.

### CLI tools with config in repo

- [x] **bat** — `dots/dot_config/bat/config` — the Catppuccin theme fetch moved out of
      `.zshrc` into `dots/run_once_install_bat_theme.sh`, so it no longer depends on a
      first-ever install to fire.
- [ ] **fastfetch** — `dots/dot_config/fastfetch/config.jsonc`
- [x] **mise** — removed. See "mise — dropped for system packages" below.

### CLI tools installed but unconfigured

Installed from `packages/headless.txt`, no dotfile of their own. Decide per tool
whether it needs config or should be dropped.

- [x] **ripgrep** — `dots/dot_config/ripgrep/config` now exists, so the guarded
      `.zshrc` export resolves. See "ripgrep — config added" below.
- [ ] eza, fd, fzf, zoxide — configured purely via `.zshrc` env/aliases
- [ ] lazygit, gdu, bottom, yq — no config
- [ ] pokeget — used by the fastfetch greeting. AUR-only, so it moved to
      `packages/headless-aur.txt` (was `cargo:pokeget` under mise).

### Version control & network

- [x] **git** — `dots/dot_gitconfig` — `pager = cat` replaced with delta, and both
      tool names corrected to `nvimdiff`. See "git — delta and real difftools" below.
- [x] **ssh** — `dots/private_dot_ssh/config` — gained `SetEnv TERM=xterm-256color`
      in the terminal pass, and `IdentityFile` is now `~/.ssh/id_ed25519`. The old
      `~/.ssh/ed25519` matched no file on disk, so the entry was inert and ssh fell
      back to trying default key names.

### Desktop integration (desktop only)

- [x] **Browsers (Brave + ungoogled-chromium) + AdNauseam** — both now native, both
      loading a shared extension flag set. See "Browsers — resolved, went native" below.
- [~] **Fonts** — `dots/run_once_install_fonts.sh` — FiraCode NF + MesloLGS NF. Now
      skipped on headless (see below). Still open: which font actually wins — the
      terminals ask for MesloLGS, VSCodium asks for FiraCode.

### Infra / language tooling (from `packages/headless.txt`, no config)

- [ ] terraform, ansible, packer — only `.zshrc` aliases (`tf`, `tfi`, `tfp`, `tfa`, `ap`, `apv`)
- [ ] python + pipx, rust, node, claude

---

## VSCodium — done, with open items

Now tracked at `dots/dot_config/VSCodium/User/`:

- `settings.json` — 15 keys: FiraCode Nerd Font 17px + ligatures, Catppuccin Macchiato
  theme + icons, minimap off, inline diffs, bracket-pair guides.
- `keybindings.json` — `ctrl+d` rebound from add-selection-to-next-match to
  `editor.action.duplicateSelection`, plus seven `-`-prefixed unbindings that clear
  the default `ctrl+/` and `ctrl+d` handlers out of the way.

Decisions made:

- **VSCodium only.** `~/.config/Code` and `~/.config/Code - OSS` on the current host
  are vestigial and left untracked.
- **Desktop-only**, via the `{{ if not .isDesktop }}` block in `.chezmoiignore` —
  remote-ssh and Codespaces read `~/.vscode-server/`, not `~/.config/VSCodium`.
- Content came from the canonical config, **not** from this host — the current
  machine is mid-overhaul and its live `~/.config/VSCodium` is stale.

Open items:

- [ ] **Extensions list.** Not created — the installed set on this host is stale, so
      generating one from it would bake in the wrong list. Once a host is actually
      converged, add `extensions.txt` and decide whether a `run_once_` script installs
      from it via `codium --install-extension`. The stale `vscode/extensions.txt` line
      has been removed from `.chezmoiignore` in the meantime.
- [ ] **Catppuccin extension is required but not listed.** `workbench.colorTheme:
      "Catppuccin Macchiato"` and `iconTheme: "catppuccin-macchiato"` need
      `Catppuccin.catppuccin-vsc` + `Catppuccin.catppuccin-vsc-icons` from Open VSX.
      Without them VSCodium silently falls back to the default theme.
- [x] **Theme inconsistency** — resolved. Both VSCodium theme keys are now
      Macchiato, matching alacritty, ghostty, bat, delta, fzf and starship.
- [ ] **Integrated terminal has no Nerd Font.** `terminal.integrated.fontFamily` is
      `"monospace"` (settings.json:7), while the editor asks for `FiraCode Nerd Font`
      (settings.json:4). starship's prompt glyphs therefore render as tofu inside
      VSCodium's terminal while looking correct in alacritty and ghostty. Set it to
      whichever Nerd Font wins the "which font wins" decision below — the two should
      be resolved together, not separately.
- [ ] `settings.json` is JSONC, not strict JSON — it has a `// font ligatures` comment
      and a trailing comma after the last key. VSCodium accepts both; just don't run a
      strict JSON formatter over it.
- [ ] Decide the drift strategy: VSCodium rewrites `settings.json` whenever you change
      a setting in the GUI, which will fight chezmoi. Either accept `chezmoi re-add` as
      the workflow, or make it a `modify_` script.
- [ ] `snippets/` is empty — add it to the repo only if it ever gets content.

---

## zsh — merged, with open items

The standalone zshrc and the repo's `dot_zshrc.tmpl` are now one file.

Brought over from the old config:

- `~/.krew/bin` on `PATH` (guarded on the directory existing), with `typeset -U path`
  so re-sourcing doesn't duplicate entries.
- `kubectl` completion — cached to `$XDG_CACHE_HOME/zsh/kubectl-completion.zsh`
  instead of regenerating per shell. **Delete that file after a kubectl upgrade.**
- `thefuck` alias, guarded on being installed.
- `setopt NO_BG_NICE`, `APPEND_HISTORY`.
- `alias lss='eza'`, and `grep` now carries `--color=auto`.
- ~~`mise_pin` / `mise_pin_all` / `mise_update`~~ — all three are gone again along with
  mise itself. `pacman -Syu` is the update path now.

Deliberately **not** carried over:

- `EDITOR='$(mise which nvim)'` — single-quoted, so it set `EDITOR` to the literal
  string `$(mise which nvim)` rather than a path. Kept `EDITOR="nvim"`, added `VISUAL`.
- `HISTDUP=erase` — not a real zsh variable (it's a widely-copied no-op). The
  `HIST_IGNORE_ALL_DUPS` / `HIST_SAVE_NO_DUPS` options already do this.
- `HISTFILE=~/.zsh_history` — kept the XDG path `$XDG_STATE_HOME/zsh/history`.
- Eager `zinit light` plugin loading — kept async `wait lucid`.
- `~/.zsh_aliases` sourcing — `~/.zshrc.local` already covers machine-local extras;
  no reason to have two hooks.
- `update_fonts` with `sudo` — fonts install to `~/.local/share/fonts`, so the
  user-level `fc-cache -fv` is correct.

Fixed along the way:

- **`zstyle ':completion:*' menu select` → `menu no`.** fzf-tab cannot take over
  completion while zsh is drawing its own selection menu; the old standalone config
  had this right and the repo copy had it wrong.
- **Dropped `export TERM="xterm-256color"`.** It overrode whatever the terminal set,
  costing truecolor/undercurl under ghostty and alacritty. See the tmux item above
  for the follow-on change this requires.
- **fastfetch greeting is now skipped inside tmux**, so a new pane doesn't redraw the
  whole fetch. Remove the `[[ -z "$TMUX" ]]` guard to get the old behaviour back.

### zinit turbo loading — reworked

The plugin block had two real defects, both now fixed:

- `zsh-autosuggestions` under `wait` registers its precmd hook too late and silently
  misses the first prompt. Fixed with `atload'!_zsh_autosuggest_start'`.
- `fast-syntax-highlighting` was loading second, before `zsh-completions` and
  `fzf-tab`. It wraps ZLE widgets, so anything loaded after it goes unhighlighted —
  it is now last.

Also: `zsh-completions` gained `blockf` + `atpull'zinit creinstall -q .'`, and the
compdef replay moved to `atinit'zicdreplay'` on fast-syntax-highlighting. The bare
`zinit cdreplay -q` in the completion section was removed — keeping both would have
replayed every compdef twice.

### Plugins added

- **atuin** — SQLite history, fuzzy search, per-directory filtering, exit codes and
  durations. Initialised with `--disable-up-arrow` so the existing arrow-key
  `history-search-*` bindings survive and atuin takes Ctrl-R only. Drop that flag to
  give atuin the up arrow too.
- **carapace** — completion for ~1000 CLIs. Loaded after compinit, with the `format`
  zstyle carapace needs for fzf-tab to render group headers.
- **zsh-autopair** — auto-closes quotes/brackets. No startup cost.
- **OMZP::sudo** — rebound from Esc-Esc to **Alt-s**, and Esc-Esc explicitly freed in
  `vicmd`, since Esc already leaves insert mode under `bindkey -v`.
- **fzf-git.sh** — Ctrl-G Ctrl-{B,T,H,R,S} for branches/tags/hashes/remotes/stashes.

Skipped as redundant: zsh-z / autojump (zoxide), prompt plugins (starship),
zsh-you-should-use.

Open:

- [x] ~~Verify the mise names for `atuin` and `carapace`.~~ Superseded — both now come
      from the package lists instead (`atuin` in `packages/headless.txt`,
      `carapace-bin` in `packages/headless-aur.txt`). `mise/config.toml` is gone, so
      there is nothing left to verify.
- [ ] atuin on a fresh machine will prompt about sync/registration on first run.
      Decide whether to ship an `atuin/config.toml` with `auto_sync = false` to keep
      unattended installs quiet.
- [ ] carapace and `zsh-completions` now overlap. If carapace works out, dropping
      `zsh-completions` from the zinit block would cut startup work.
- [ ] `KEYTIMEOUT=1` (10ms) is aggressive — it makes `ESC` snappy in vi mode but can
      break multi-key terminal sequences. Consider 10–20 if anything acts up.
- [ ] Vi mode has no cursor-shape switching (beam on insert, block on normal), which
      is the usual companion to `bindkey -v`.
- [x] ~~The bat Catppuccin theme is fetched inside the `if mise not installed` block.~~
      Moved to `dots/run_once_install_bat_theme.sh` when that block was deleted.
- [ ] `dot_zshrc.tmpl` contains **no** chezmoi template directives — it could just be
      `dot_zshrc`. Keeping the `.tmpl` suffix only makes sense if templating is coming.
- [ ] `alias grep='rg'` / `alias find='fd'` shadow the POSIX tools with
      incompatible CLIs. Interactive-only, so scripts are unaffected — but worth
      deciding if you want them at all.

---

## tmux — revised

> ⚠️ **Not validated by running it — tmux is not installed on this host.** Option
> names and copy-mode commands were checked by inspection only. Run
> `tmux -f ~/.tmux.conf new-session -d \; kill-session` once on a machine that has
> tmux to confirm the config parses clean.

Changed:

- **`terminal-overrides ",xterm-256color:RGB"` → `",*:RGB"`.** This was the pending
  consequence of dropping `export TERM` from `.zshrc`: the override only ever matched
  because zsh forced `TERM=xterm-256color`. Wildcarded, it now covers ghostty
  (`xterm-ghostty`) and alacritty too.
- **`set -g set-clipboard on`** — copy via OSC 52, so `y` in copy mode reaches the
  system clipboard through SSH and in Codespaces with no `wl-copy`/`xclip` dependency.
  Both terminals in this repo allow OSC 52 writes by default.
- **`default-shell` prefers zsh** when `/bin/zsh` or `/usr/bin/zsh` exists. Without
  this, tmux inherits bash on any host where `install.sh` had to skip `chsh` for lack
  of privileges — Codespaces being the common case. Falls back to `$SHELL` otherwise.
- **Catppuccin Macchiato applied to pane borders, messages and copy-mode selection.**
  These were still at tmux's defaults (green/yellow) and clashed with the themed
  status bar.
- **Copy mode**: added `C-v` rectangle-toggle and `Escape` to cancel.

Open:

- [ ] **XDG path.** Config deploys to `~/.tmux.conf`; tmux 3.1+ reads
      `~/.config/tmux/tmux.conf`, which would match how the rest of this repo is laid
      out. Moving it means `dot_tmux.conf` → `dot_config/tmux/tmux.conf` and updating
      the `bind r source-file` path. Left alone since it changes repo layout.
- [ ] **No plugin manager (tpm).** Currently dependency-free, which suits the
      headless/unattended targets. Worth keeping unless something specifically needs it.
- [ ] `bind l select-pane -R` shadows tmux's default `last-window` binding.
- [ ] Pane navigation binds aren't `-r`, so each move needs the prefix again. The
      resize binds are `-r`. Intentional?

---

## Terminals — TERM settled

The `TERM` thread that ran through `.zshrc` → `.tmux.conf` → `alacritty.toml` is
closed. The rule now applied consistently: **the terminal owns TERM locally, SSH
substitutes a portable one.**

- `.zshrc` — no longer exports TERM (done earlier).
- `alacritty.toml` — `[env] TERM = "xterm-256color"` **removed**. The `alacritty`
  terminfo entry is present on this host (verified with `infocmp`), and it is what
  gives nvim colored/undercurl underlines. Forcing a generic xterm entry threw that
  away on every local session to fix a problem that only occurs on remote ones.
- `ghostty/config` — TERM left alone (`xterm-ghostty`), same reasoning.
- `.tmux.conf` — already wildcarded to `terminal-overrides ",*:RGB"`, so it matches
  whatever the outer terminal reports.
- **`~/.ssh/config` gained `SetEnv TERM=xterm-256color`.** This is where the remote
  problem actually belongs. `ssh_config(5)` states TERM is *exempt* from the
  server's `AcceptEnv` allowlist, so it needs no cooperation from the remote host.
  Verified with `ssh -G`, which resolves it to `setenv TERM=xterm-256color`.

### alacritty

Validated against the installed alacritty 0.17.0 — it reports unknown keys as
`Unused config key`, and the new file produces none.

- Dropped `[font.glyph_offset]` and `[font.offset]`, both set to `0,0` (no-ops).
- Reordered font faces normal → bold → italic → bold_italic, fixed the stray
  leading blank line and the trailing space after `x=2`.
- Added `[scrolling] history = 50000`, matching `history-limit` in `.tmux.conf` so
  scrollback depth is identical in and out of tmux.
- Added `dynamic_padding` and `mouse.hide_when_typing`.
- Kept `decorations = "full"`. On a tiling Hyprland setup `"none"` is the more
  common choice — left as-is rather than changed silently.

### ghostty

Was a **single line** (`theme = Catppuccin Macchiato`) against alacritty's 41. Now
mirrors alacritty: same font, size, padding, theme.

Open:

- [ ] ⚠️ **Validate the ghostty config.** Ghostty is not installed on this host, so
      none of these keys were checked against a real binary. Run `ghostty +show-config`
      once installed — it prints the effective config and flags unrecognised keys.
- [ ] `scrollback-limit` deliberately omitted from ghostty. Ghostty measures it in
      **bytes**, not lines, so it has no clean equivalent to alacritty's
      `history = 50000`. Set it consciously rather than by analogy.
- [ ] **Font mismatch across the repo.** Both terminals use `MesloLGS NF`, but
      VSCodium asks for `FiraCode Nerd Font`. `fc-list` on this host shows **24
      MesloLGS faces and 0 FiraCode faces**, so VSCodium is currently falling back to
      a default. `run_once_install_fonts.sh` installs both, but has not run here.
      Decide whether one font should win.
- [ ] `selection.save_to_clipboard` not enabled for alacritty — it's a preference
      (auto-copying selections overwrites the clipboard). Ghostty's equivalent is
      `copy-on-select`. Enable in both or neither.

---

## Fonts — headless install skipped

Went with option 2, `.chezmoiignore`, so all desktop/headless divergence stays in
one file and the script body never changes between machines.

The non-obvious part: **scripts are matched in `.chezmoiignore` by their target
name, not their source filename.** chezmoi strips the `run_once_` prefix, so the
entry is `install_fonts.sh` — `run_once_install_fonts.sh` matches nothing and
fails silently. Confirm any change with:

```sh
chezmoi managed | grep install_
```

Verified: 0 matches with `isDesktop=false`, 1 with `isDesktop=true`.

`fc-cache`/`fontconfig` **stays** in install.sh's prerequisite list — it is already
inside the `if [[ "$IS_DESKTOP" == true ]]` branch (install.sh:77-80), which is
exactly the case where the font script still runs.

### Still open — which font wins

- [ ] **Pick one Nerd Font for the whole repo**, then update every consumer below
      in the same pass.

The script installs both, so nothing is outright broken, but the repo asks for three
different things:

| Consumer | File | Currently asks for |
|---|---|---|
| alacritty | `alacritty.toml:23-35` (4 faces) | `MesloLGS NF` |
| ghostty | `ghostty/config:18` | `MesloLGS NF` |
| VSCodium editor | `settings.json:4` | `FiraCode Nerd Font` |
| VSCodium integrated terminal | `settings.json:7` | `monospace` ← **tofu** |

The last row is a genuine bug, not just inconsistency — see the VSCodium section
above.

Deciding factors:

- **MesloLGS NF** is what the terminals already use and what powerlevel10k/starship
  glyph coverage is traditionally tested against. It has **no ligatures**.
- **FiraCode Nerd Font** has ligatures, which `settings.json` explicitly enables
  (`editor.fontLigatures`) — so picking Meslo everywhere means that key becomes a
  no-op and should be dropped.
- On this host: 72 MesloLGS faces installed, **0 FiraCode** — but only because
  `run_once_install_fonts.sh` has never run here, not because of a packaging issue.
  Not a signal either way.

Once picked, if only one font is kept, drop the other's download block from
`run_once_install_fonts.sh` rather than leaving a dead ~25 MB fetch on every
desktop install.

## git — delta and real difftools

`core.pager = cat` did not mean "use a nicer pager", it meant **no paging at all** —
`git log` in any sizeable repo dumped the entire history into the scrollback.
Replaced with `git-delta`, which pages *and* highlights.

- delta reads bat's theme cache, so `syntax-theme = Catppuccin Macchiato` reuses
  the theme `run_once_install_bat_theme.sh` already fetches. One theme, both tools.
- `interactive.diffFilter` routes `git add -p` through delta too.
- `diff.colorMoved = default` is what makes delta's moved-block colouring work.

`diff.tool`/`merge.tool` were `nvim`, which is not a valid tool name — git only
recognises `nvimdiff` (confirmed with `git difftool --tool-help`). With `nvim`,
`git difftool` fell through to prompting for a command on every invocation.

Also set `merge.conflictStyle = zdiff3`, which shows the common ancestor in
conflict markers and hoists shared lines out of both sides.

⚠️ `git-delta` was added to `packages/headless.txt` and is now a **hard dependency**
of `dot_gitconfig` — if it is missing, git cannot page at all. On a non-Arch host
that skips the package phase this breaks git output until delta is installed
manually. See "Non-Arch hosts — no tool path" below.

## ripgrep — config added

`dots/dot_config/ripgrep/config` now exists, so the `.zshrc` guard
(`[[ -f ... ]] && export RIPGREP_CONFIG_PATH=...`) resolves instead of silently
doing nothing. Chose to add a config rather than drop the export because `.zshrc`
aliases `grep` to `rg`, making it the default search on the system.

Settings: `--smart-case`, `--hidden` (a dotfiles repo is mostly hidden files) with
`--glob=!.git/` so `--hidden` doesn't turn every search into an object-database
scan, plus `node_modules/`/`.venv/`/`target/` excludes and
`--max-columns=200 --max-columns-preview` so minified files don't shred the terminal.

Verified against rg's own parser with `rg --debug`: all 8 arguments load, `--hidden`
raises hits from 4 to 6 in this repo, 0 `.git/` paths leak, and smart-case
correctly gives 2 hits for `hello` vs 1 for `Hello`.

Note the config file has **no shell parsing** — one argument per line, quotes and
globs taken literally. `--glob=!.git/` is correct; `--glob "!.git/"` would not work.

## Browsers — resolved, went native

Both browsers are native AUR packages; the flatpak entry is retired.

| | Package | Entry in repo | Overrides |
|---|---|---|---|
| Brave | `brave-origin-bin` | `brave-origin.desktop.tmpl` | `/usr/share/applications/brave-origin.desktop` |
| ungoogled-chromium | `ungoogled-chromium-bin` | `chromium.desktop.tmpl` | `/usr/share/applications/chromium.desktop` |

Both verified with `desktop-file-validate`, and both confirmed to render only in
desktop mode.

Key points:

- **Filenames match the system entries deliberately.** That is the whole mechanism —
  `~/.local/share/applications/<name>.desktop` shadows `/usr/share/applications/<name>.desktop`
  only when the basename is identical. The old `com.brave.Browser.desktop` overrode
  nothing; it was a second, separate launcher.
- **Shared extension flags** live in `dots/.chezmoitemplates/browser-extension-flags`
  and are pulled into both entries with `includeTemplate … | trim`. The `trim` is
  load-bearing: without it the partial's trailing newline splits the `Exec=` line.
- **`.chezmoiremove` added** listing `.local/share/applications/com.brave.Browser.desktop`.
  chezmoi does not delete targets just because they vanish from the source, so without
  this any machine provisioned earlier keeps a dead flatpak launcher. Note this file
  deletes that path on *every* apply.
- `StartupWMClass` is now `brave-origin` (was the flatpak's `brave-browser`). The
  chromium entry has none, matching its upstream file.
- The overrides replace the system entries wholesale rather than merging, so the
  upstream `GenericName[xx]` / `Comment[xx]` translations are dropped. Deliberate —
  the previous entry was English-only too.

Open:

- [ ] ⚠️ **Verify the Tor action actually works.** `brave-origin.desktop` keeps the
      `new-tor-window` action with `--tor`, carried over from the old flatpak entry.
      But `brave-origin`'s own system desktop file has **no** Tor action, and Brave
      Origin is a de-branded build with Brave services stripped — so `--tor` may be
      silently ignored. A Tor menu entry that quietly opens an ordinary window is a
      privacy footgun. Test it, and delete the action if it doesn't hold up.
- [x] ~~Nothing installs AdNauseam.~~ Done — `dots/run_once_install_adnauseam.sh.tmpl`
      fetches the latest release and unpacks it to `~/.local/share/adnauseam` during
      `chezmoi apply`. Verified end to end: installs 3.28.8, manifest lands at the top
      level (not nested), no leftover staging dir. All four failure paths (no `unzip`,
      dead URL, bad archive, no temp dir) warn and exit 0 — a non-zero exit from a
      `run_once_` script aborts the whole apply. A failed run also leaves any existing
      install intact, confirmed by test.
- [x] ~~Fetch the browser extension list.~~ Done — `packages/browser-extensions.txt`
      holds all 17 from the Brave profile, IDs validated and cross-checked against
      `~/.config/BraveSoftware/Brave-Origin/Default/Extensions` with no drift.
      ungoogled-chromium had none of its own (it ships without web store access),
      which is exactly why the list is shared.
- [x] ~~Nothing installs the extension list.~~ Done — `install.sh` converts
      `packages/browser-extensions.txt` into an `ExtensionInstallForcelist` policy and
      writes it to `/etc/chromium/policies/managed/extensions.json` and
      `/etc/brave/policies/managed/extensions.json`. Both paths were confirmed as
      literals inside the shipped binaries rather than assumed (the Brave build
      contains both `/etc/brave/policies` and `/etc/chromium/policies`). Desktop-only,
      root-guarded, never fatal. Verified: 16 entries, valid JSON, both files
      byte-identical, and all four edge cases (no list / no root / no valid IDs /
      normal) behave correctly.
- [x] ~~uBlock Origin and AdNauseam are both present.~~ Resolved — uBO removed from
      the list, AdNauseam kept.
- [ ] ⚠️ **Confirm ungoogled-chromium actually honours the forcelist.** It ships with
      web store integration stripped, so the policy may be written but never acted on.
      The policy is correct either way and Brave is unaffected — but verify on the
      real machine before assuming both browsers converged.
- [ ] Force-installed extensions can't be removed from the browser UI. If that turns
      out to be too rigid day to day, `ExtensionSettings` with `"installation_mode":
      "normal_installed"` installs them but still lets you disable them.
- [ ] Two entries look system-installed rather than chosen: **Plasma Integration**
      (`external-pref-dl`, dropped in by the KDE `plasma-browser-integration` package)
      and **Microsoft Single Sign On**. Worth pruning from the list if you don't want
      them reinstated on a fresh machine.
- [ ] **AdNauseam never auto-updates.** `run_once_` fires once and never again, so the
      extension stays pinned at whatever version was current on first install. Updating
      needs `rm -rf ~/.local/share/adnauseam && chezmoi state delete-bucket
      --bucket=scriptState && chezmoi apply` (documented in the README). If that gets
      annoying, switch to `run_onchange_` keyed on a version string, or add an
      `update_adnauseam` function to `.zshrc`.
- [ ] Neither entry is re-checked against upstream on package upgrade. If
      `brave-origin-bin` renames its binary or icon, the override keeps the stale
      value and the launcher silently breaks.

## mise — dropped for system packages

`dots/dot_config/mise/config.toml` is deleted and every tool it pinned is now a
package in `packages/`. This also settles the old "split the mise toolset" idea —
`cargo:pokeget` no longer compiles from source on every machine, it comes from
the AUR as `pokeget`.

Removed along with it:

- `install.sh` — the `curl https://mise.run | sh` bootstrap and `mise install`.
- `.zshrc` — the `mise activate zsh` eval and the whole `if mise not installed`
  block, plus the `mise_pin` / `mise_pin_all` / `mise_update` functions.

Package name changes worth knowing:

| mise | package | notes |
|---|---|---|
| `node` | `nodejs` + `npm` | npm is a separate package on Arch |
| `pipx` | `python-pipx` | |
| `rust` | `rustup` | needs `rustup default stable` once; conflicts with `rust` |
| `carapace` | `carapace-bin` (AUR) | no official package |
| `claude` | `claude-code` (AUR) | |
| `cargo:pokeget` | `pokeget` (AUR) | |

What this costs, now that it's done:

- [ ] **No version pinning.** `pacman -Syu` moves every tool at once; there is no
      per-tool pin and no rollback short of the pacman cache. The old
      `mise/config.toml` versions are recoverable from git history if a specific
      pin ever needs restoring.
- [ ] **Single system-wide runtimes.** python/node/rust are one version each, so
      per-project switching is gone. If that bites, `rustup` covers Rust and `pipx`
      covers Python CLIs; node would need nvm or fnm.
- [ ] **Non-Arch hosts install no tools at all.** Big enough to have its own
      section — see "Non-Arch hosts — no tool path" below.

---

## Non-Arch hosts — no tool path

**The gap:** `packages/*.txt` hold pacman names, so `install.sh` skips the whole
package step on anything that isn't Arch. mise used to cover those hosts. Now a
Debian Codespace, an Ubuntu VM or an Alpine container gets the dotfiles, the four
cross-distro prerequisites (`curl`, `git`, `zsh`, `tar`) — and nothing else.

**Why it's worse than a bare shell.** `.zshrc` assumes the tools exist. Only
`thefuck`, `kubectl`, `carapace` and `atuin` are behind `command -v` guards; the
rest fire unconditionally, so the first prompt on such a host throws a stack of
`command not found`:

| `dot_zshrc.tmpl` | Needs |
|---|---|
| L76–78 — `eval "$(starship init zsh)"`, `zoxide init`, `fzf --zsh` | starship, zoxide, fzf |
| L180–189 — `FZF_DEFAULT_COMMAND` / preview opts | fd, bat, eza |
| L197–206 — `ls`/`ll`/`lt`, `cat`, `grep`, `find`, `vim`, `lg` | eza, bat, ripgrep, fd, neovim, lazygit |
| L229 — `fastfetch` greeting | fastfetch, pokeget |

`cd` is the sharp one: L77 rebinds it to `zoxide init --cmd cd`, so if zoxide is
missing the eval fails and `cd` is left as the builtin — fine — but the greeting
at L229 runs on *every* shell and errors visibly each time.

- [ ] **`dot_gitconfig` now depends on delta the same way.** The git pass set
      `core.pager = delta` and `interactive.diffFilter = delta --color-only`, and
      added `git-delta` to `packages/headless.txt`. Unlike the `.zshrc` cases above
      this is not a shell alias that can be guarded with `command -v` — git resolves
      the pager itself, so on a host that skipped the package phase **every**
      `git diff` / `git log` / `git show` fails outright rather than degrading.
      Options: accept it as part of "headless means headless Arch" (option 1 below),
      or make the pager conditional via a `.tmpl` + `lookPath` guard:
      ```gotemplate
      {{ if lookPath "delta" }}pager = delta{{ end }}
      ```
      Note that guard is evaluated at **apply** time, so a machine that gains delta
      later needs a re-apply — which is the same caveat as everything else here.

Also note [README.md](README.md) still documents the Codespaces flow as
"bootstrap the full environment on creation", which is no longer true.

Pick one:

1. **Drop the non-Arch target.** Simplest and honest: headless means "headless
   Arch". Delete the Codespaces section from the README, drop the apt/dnf/apk
   branches from the pre phase, and stop claiming cross-distro support. The
   `isDesktop` split stays — it's still useful for Arch servers and containers.
2. **Guard `.zshrc`.** Wrap the evals and aliases in `command -v` checks so the
   shell degrades to plain zsh instead of erroring. Cheap, and worth doing on its
   own merits even if a tool path is added later — a package that fails to install
   currently produces the same mess on Arch.
3. **Add a non-Arch tool path.** Bring back a userspace installer for those hosts
   only — mise again, or a `packages/*.txt` name-mapping table per manager. Undoes
   part of the simplification, so only worth it if Codespaces is genuinely used.

Option 2 is independent of the other two and fixes the loud failure either way.

Related: `install.sh` still has working apt/dnf/apk branches for the four
prerequisites, so the cross-distro scaffolding is half-present — whichever option
wins, make the script and the README agree.
