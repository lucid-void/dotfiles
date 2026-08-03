# TODO

Open items only — resolved work has been cleared out. Check `git log` for the
history and reasoning behind decisions already made.

## tmux

> ⚠️ **Not validated by running it — tmux is not installed on this host.**
> Option names and copy-mode commands were checked by inspection only. Run
> `tmux -f ~/.tmux.conf new-session -d \; kill-session` once on a machine that
> has tmux to confirm the config parses clean.

- [ ] **XDG path.** Config deploys to `~/.tmux.conf`; tmux 3.1+ reads
      `~/.config/tmux/tmux.conf`, which would match how the rest of this repo
      is laid out. Moving it means `dot_tmux.conf` → `dot_config/tmux/tmux.conf`
      and updating the `bind r source-file` path. Left alone since it changes
      repo layout.
- [ ] **No plugin manager (tpm).** Currently dependency-free, which suits the
      headless/unattended targets. Worth keeping unless something specifically
      needs it.
- [ ] `bind l select-pane -R` shadows tmux's default `last-window` binding.
- [ ] Pane navigation binds aren't `-r`, so each move needs the prefix again.
      The resize binds are `-r`. Intentional?

## zsh

- [ ] atuin on a fresh machine will prompt about sync/registration on first
      run. Decide whether to ship an `atuin/config.toml` with
      `auto_sync = false` to keep unattended installs quiet.
- [ ] carapace and `zsh-completions` now overlap. If carapace works out,
      dropping `zsh-completions` from the zinit block would cut startup work.
- [ ] `KEYTIMEOUT=1` (10ms) is aggressive — it makes `ESC` snappy in vi mode
      but can break multi-key terminal sequences. Consider 10–20 if anything
      acts up.
- [ ] Vi mode has no cursor-shape switching (beam on insert, block on normal),
      which is the usual companion to `bindkey -v`.
- [ ] `dot_zshrc.tmpl` contains **no** chezmoi template directives — it could
      just be `dot_zshrc`. Keeping the `.tmpl` suffix only makes sense if
      templating is coming.
- [ ] `alias grep='rg'` / `alias find='fd'` shadow the POSIX tools with
      incompatible CLIs. Interactive-only, so scripts are unaffected — but
      worth deciding if you want them at all.

## Browsers


- [ ] ⚠️ **Confirmed: ungoogled-chromium does not honour the forcelist.**
      Force-installed extensions from `packages/browser-extensions.txt` don't
      show up on ungoogled-chromium, even though both unpacked extensions
      (AdNauseam, chromium-web-store, both loaded via `--load-extension`) work
      fine there. So it's specifically `ExtensionInstallForcelist` that's a
      no-op — consistent with web store integration being stripped from the
      build. Brave is unaffected either way. Investigate later: whether
      chromium-web-store (now confirmed working) can be used to install these
      manually instead, or whether the forcelist policy should just be dropped
      for ungoogled-chromium and left Brave-only.
- [ ] Force-installed extensions can't be removed from the browser UI. If that
      turns out to be too rigid day to day, `ExtensionSettings` with
      `"installation_mode": "normal_installed"` installs them but still lets
      you disable them.
- [ ] Two entries look system-installed rather than chosen: **Plasma
      Integration** (`external-pref-dl`, dropped in by the KDE
      `plasma-browser-integration` package) and **Microsoft Single Sign On**.
      Worth pruning from the list if you don't want them reinstated on a fresh
      machine.
- [ ] **AdNauseam never auto-updates.** `run_once_` fires once and never
      again, so the extension stays pinned at whatever version was current on
      first install. Updating needs `rm -rf ~/.local/share/adnauseam &&
      chezmoi state delete-bucket --bucket=scriptState && chezmoi apply`
      (documented in the README). If that gets annoying, switch to
      `run_onchange_` keyed on a version string, or add an `update_adnauseam`
      function to `.zshrc`.
- [ ] Neither browser desktop entry is re-checked against upstream on package
      upgrade. If `brave-origin-bin` renames its binary or icon, the override
      keeps the stale value and the launcher silently breaks.

## Git

- [ ] **`dot_gitconfig` still hard-depends on delta.** `core.pager = delta`
      and `interactive.diffFilter = delta --color-only` aren't guarded — git
      resolves the pager itself, so if `git-delta` ever fails to install,
      every `git diff` / `git log` / `git show` fails outright rather than
      degrading. Not yet worth the `.tmpl` + `lookPath` guard below given
      `git-delta` installs cleanly on both apt and pacman today; revisit if
      that changes:
      ```gotemplate
      {{ if lookPath "delta" }}pager = delta{{ end }}
      ```
      That guard evaluates at **apply** time, so a machine that gains delta
      later would need a re-apply.
