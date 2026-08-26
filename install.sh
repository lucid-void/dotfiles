#!/usr/bin/env bash
#
# Unattended installer — never prompts, safe for Packer, cloud-init and Codespaces.
# Run `install.sh --help` for usage; the text lives in usage() below so it can
# never drift out of sync with the flags actually parsed.
#
# Tools come from the packages/ lists, not from a version manager. Arch and
# Debian/Ubuntu both get the full headless tool set; on any other distro the pre
# phase installs only the prerequisites in REQUIRED_CMDS, so you get the
# dotfiles and nothing else.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$HOME/.local/bin:$PATH"

# ── Mode ───────────────────────────────────────────────────────
IS_DESKTOP=true
if [[ -n "${CODESPACES:-}" || -n "${DOTFILES_HEADLESS:-}" ]]; then
  IS_DESKTOP=false
fi
SKIP_PACKAGES=false
if [[ -n "${DOTFILES_SKIP_PACKAGES:-}" ]]; then
  SKIP_PACKAGES=true
fi
# Kept as a heredoc rather than `sed`-ing the header comment above: that version
# was pinned to line numbers ('2,19p'), so it silently truncated mid-sentence as
# soon as the header grew, and it printed the leading `#` of every line.
usage() {
  cat <<'USAGE'
Unattended installer — never prompts, safe for Packer, cloud-init and Codespaces.

  bash install.sh                # desktop (default)
  bash install.sh --headless     # headless: VM, container, Codespace
  bash install.sh --desktop      # force desktop mode
  bash install.sh --no-packages  # dotfiles only, no package lists

Equivalent env vars: DOTFILES_HEADLESS=1, DOTFILES_SKIP_PACKAGES=1
Codespaces is auto-detected and treated as headless.

Phases:
  pre   — system packages   (needs root/passwordless sudo; skipped otherwise)
  main  — dotfiles          (no privileges required)
  post  — login shell       (needs root/passwordless sudo; skipped otherwise)

Only "main" is required. The pre/post phases no-op with a warning when
privileges are unavailable, so the script still succeeds on locked-down hosts.

Note: --headless/--desktop only take effect on a machine chezmoi has not been
initialised on yet. The answer is persisted by promptBoolOnce in
dots/.chezmoi.toml.tmpl; to change it later, edit isDesktop in
~/.config/chezmoi/chezmoi.toml (this script warns when they disagree).
USAGE
}

for arg in "$@"; do
  case "$arg" in
    --headless)    IS_DESKTOP=false ;;
    --desktop)     IS_DESKTOP=true ;;
    --no-packages) SKIP_PACKAGES=true ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "install.sh: unknown argument: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m warning:\033[0m %s\n' "$*" >&2; }

# ── apt helper ─────────────────────────────────────────────────
# One entry point for every apt-get install in this script. `apt-get update` is
# expensive and was previously run twice on a fresh Debian box (once for the
# prerequisites, once for headless-apt.txt); APT_UPDATED makes the second call a
# no-op. Refuses to run with an empty package list — `apt-get install` with no
# operands exits 100, which the pacman path already guards against.
#
# Never fatal: every failure warns, matching the rest of the pre phase.
APT_UPDATED=false
apt_install() {
  local what="$1"; shift
  if [[ $# -eq 0 ]]; then
    warn "no packages to install for $what — skipping"
    return 0
  fi
  if [[ "$APT_UPDATED" != true ]]; then
    "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get update -qq \
      || warn "apt-get update failed — $what may be stale"
    APT_UPDATED=true
  fi
  "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@" \
    || warn "apt-get install failed for $what — install manually: $*"
}

# ── Privilege detection ────────────────────────────────────────
# SUDO is the command prefix to run something as root, or empty if we cannot.
# `sudo -n` never prompts for a password, so an unattended run can't hang.
#
# On an interactive desktop run without passwordless sudo, we ask once
# (`sudo -v`) and keep the credential alive with a background refresher for the
# rest of the script, instead of checking `sudo -n` (and silently skipping)
# at every privileged step. This only ever fires when IS_DESKTOP is true *and*
# stdin is a TTY, so headless/Codespaces/CI runs keep the original zero-prompt
# behaviour untouched.
#
# SUDO is an array rather than a string so it expands with proper quoting —
# `"${SUDO[@]}"` is empty when we are already root, and shellcheck-clean either
# way, where the old unquoted `$SUDO` relied on deliberate word-splitting.
SUDO=()
HAVE_ROOT=true
SUDO_KEEPALIVE_PID=""
if [[ "$(id -u)" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    SUDO=(sudo -n)
  elif [[ "$IS_DESKTOP" == true && -t 0 ]] && command -v sudo >/dev/null 2>&1 && sudo -v; then
    SUDO=(sudo)
    # `|| true` on the refresh is load-bearing: the subshell inherits `set -e`
    # from above, so without it the first `sudo -n true` that fails (another
    # `sudo -k`, timestamp_timeout=0, a tty_tickets mismatch) kills the
    # refresher silently — and the next privileged step prompts again, which is
    # the exact behaviour this block exists to prevent.
    ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null || true; sleep 60; done ) &
    SUDO_KEEPALIVE_PID=$!
    trap 'if [[ -n "$SUDO_KEEPALIVE_PID" ]]; then kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true; fi' EXIT
  else
    HAVE_ROOT=false
  fi
fi

# ═══════════════════════════════════════════════════════════════
# PRE — system packages
# ═══════════════════════════════════════════════════════════════
# Two steps:
#   1. prerequisites — the handful of commands this script itself needs, on any
#      distro. Only runs when something is actually missing, so it is a no-op on
#      an already provisioned machine.
#   2. package lists — packages/*.txt, Arch only. `--needed` makes re-runs cheap.
#
# Neither step is fatal: main is the phase that matters, so a package failure
# warns and carries on rather than leaving the machine without its dotfiles.

REQUIRED_CMDS=(curl git zsh tar)
if [[ "$IS_DESKTOP" == true ]]; then
  REQUIRED_CMDS+=(fc-cache)   # fontconfig, for run_once_install_fonts.sh
  REQUIRED_CMDS+=(unzip)      # for run_install_adnauseam.sh
fi

missing=()
for cmd in "${REQUIRED_CMDS[@]}"; do
  command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done

if [[ ${#missing[@]} -gt 0 ]]; then
  log "Missing prerequisites: ${missing[*]}"
  if ! $HAVE_ROOT; then
    warn "no root or passwordless sudo — install these manually, then re-run:"
    warn "  ${missing[*]}"
  else
    # Map commands to package names where they differ.
    pkgs=()
    for cmd in "${missing[@]}"; do
      case "$cmd" in
        fc-cache) pkgs+=(fontconfig) ;;
        *)        pkgs+=("$cmd") ;;
      esac
    done

    # Each install is `|| warn` rather than bare: under `set -e` an unguarded
    # failure here (network hiccup, transient mirror error) would abort the
    # entire script, contradicting "nothing in the pre phase is fatal".
    if command -v apt-get >/dev/null 2>&1; then
      apt_install "prerequisites" "${pkgs[@]}"
    elif command -v dnf >/dev/null 2>&1; then
      "${SUDO[@]}" dnf install -y "${pkgs[@]}" || warn "dnf failed — install manually: ${pkgs[*]}"
    elif command -v pacman >/dev/null 2>&1; then
      "${SUDO[@]}" pacman -Sy --noconfirm --needed "${pkgs[@]}" || warn "pacman failed — install manually: ${pkgs[*]}"
    elif command -v apk >/dev/null 2>&1; then
      "${SUDO[@]}" apk add --no-cache "${pkgs[@]}" || warn "apk failed — install manually: ${pkgs[*]}"
    else
      warn "unrecognised package manager — install manually: ${pkgs[*]}"
    fi
  fi
fi

# ── Package lists ──────────────────────────────────────────────
# packages/headless.txt is installed everywhere; desktop mode adds
# packages/desktop.txt and then the AUR list. Arch only — the lists hold
# pacman package names, which don't carry over to apt/dnf/apk.

PKG_DIR="$REPO_DIR/packages"

# One package per line, `#` comments and blank lines stripped.
read_pkg_list() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    warn "package list not found: $file"
    return 0
  fi
  # `|| true`: grep exits 1 on a list that is entirely comments, which is an
  # empty list, not an error.
  sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$file" \
    | grep -v '^$' || true
}

# Reads every list in "$@" into the PKGS array, replacing whatever was in it.
# PKGS is declared here rather than left implicit: the previous version appended
# to whatever the caller happened to leave behind, so each of the three call
# sites had to remember `PKGS=()` first, and reordering them would silently have
# installed the previous phase's list a second time.
PKGS=()
collect_pkgs() {
  local file line
  PKGS=()
  for file in "$@"; do
    while IFS= read -r line; do
      [[ -n "$line" ]] && PKGS+=("$line")
    done < <(read_pkg_list "$file")
  done
}


# ── Non-Arch (apt) package install ──────────────────────────────
# Full parity with headless.txt for Debian/Ubuntu VMs and Codespaces. Package
# names for the straightforward apt-get case live in packages/headless-apt.txt;
# a handful of headless.txt tools have no apt package at all (starship, rustup,
# yq, lazygit, gdu, bottom, fastfetch, carapace, gh) — plus neovim, which has one
# that is too old to be usable — and are fetched below via official installers,
# GitHub release binaries, or a third-party apt repo.
# Everything here is idempotent (command -v guarded) and never fatal — one
# tool failing to install warns and the run continues. All of them land in
# ~/.local/bin except rustup, which owns ~/.cargo/bin — .zshrc adds both.

# Fetch a single-binary GitHub release into ~/.local/bin.
#   $1 owner/repo
#   $2 release asset filename — include a literal %V% where the tag's version
#      number (no leading "v") appears, for assets whose name embeds it
#   $3 command name to install as
#   $4 basename of the binary inside the archive, if different from $3
# Every fallible step below is guarded (`if`, or a trailing `|| ...`) rather
# than bare: under `set -e`, an unguarded failure — even a `cmd1 && cmd2`
# statement where cmd1 legitimately returns false, like the very next line —
# would abort the *entire* install.sh, not just this one optional tool.
#
# Runs in a subshell so a single EXIT trap can clean the temp dir up on every
# path — including SIGINT, which the previous version's five hand-written
# `rm -rf "$tmp"` calls could not catch.
fetch_github_release_binary() (
  local repo="$1" asset="$2" dest="$3" inner_name="${4:-$3}"
  if command -v "$dest" >/dev/null 2>&1; then
    return 0
  fi

  local url tmp tag
  if [[ "$asset" == *%V%* ]]; then
    if ! tag="$(curl -fsSL --retry 3 --connect-timeout 20 --max-time 60 \
          -o /dev/null -w '%{url_effective}' \
          "https://github.com/$repo/releases/latest" | sed 's#.*/##')" || [[ -z "$tag" ]]; then
      warn "could not resolve latest release for $repo — install $dest manually"
      return 1
    fi
    asset="${asset//%V%/${tag#v}}"
    url="https://github.com/$repo/releases/download/$tag/$asset"
  else
    url="https://github.com/$repo/releases/latest/download/$asset"
  fi

  tmp="$(mktemp -d)" || { warn "could not create temp dir for $dest"; return 1; }
  trap 'rm -rf "$tmp"' EXIT

  if ! curl -fsSL --retry 3 --connect-timeout 20 --max-time 180 -o "$tmp/$asset" "$url"; then
    warn "download failed for $dest ($url) — install manually"
    return 1
  fi

  mkdir -p "$HOME/.local/bin"
  case "$asset" in
    *.tar.gz|*.tgz)
      if ! tar -xzf "$tmp/$asset" -C "$tmp"; then
        warn "could not extract $asset — install $dest manually"
        return 1
      fi
      # `-print -quit`, not `| head -1`: head closing the pipe hands find a
      # SIGPIPE (exit 141), which `pipefail` promotes to a failed assignment and
      # `set -e` turns into an abort of the *whole* script — for an optional
      # tool. Same idiom the extension installers already use.
      #
      # Prefer a match under a bin/ directory. Some tarballs ship more than one
      # file named after the binary — fastfetch's has usr/bin/fastfetch *and* a
      # bash-completion script also called `fastfetch` — and a bare -name match
      # takes whichever readdir reaches first. That is filesystem order, not
      # archive order, so it installed the completion script as `fastfetch` on
      # one host and the real binary on the next. The fallback keeps the flat
      # tarballs (lazygit, btm, gdu) working, since those have no bin/ at all.
      local found
      found="$(find "$tmp" -type f -name "$inner_name" -path '*/bin/*' -print -quit)"
      [[ -n "$found" ]] || found="$(find "$tmp" -type f -name "$inner_name" -print -quit)"
      if [[ -z "$found" ]]; then
        warn "could not find $inner_name inside $asset — install $dest manually"
        return 1
      fi
      install -m 755 "$found" "$HOME/.local/bin/$dest" \
        || warn "could not install $dest to ~/.local/bin"
      ;;
    *)
      install -m 755 "$tmp/$asset" "$HOME/.local/bin/$dest" \
        || warn "could not install $dest to ~/.local/bin"
      ;;
  esac
)

# ── Version-guarded upstream installs ──────────────────────────
# Two tools below are in apt but at a version too old to do the job (neovim,
# rclone). They can't use fetch_github_release_binary's `command -v` guard: an
# old copy at /usr/bin satisfies it, so the fetch would be skipped and the host
# left broken. They check the version instead, which also makes them upgrade in
# place rather than no-op once the floor rises.
#
# True when $1 (a bare version, "0.10.4") is at least $2. An empty $1 — the tool
# is absent, or its version could not be parsed — is never new enough.
version_at_least() {
  local have="$1" want="$2"
  [[ -n "$have" ]] || return 1
  # sort -V puts the smaller first; if that is still $want, then $have >= $want.
  #
  # A suffixed build sorts *after* the bare release of the same number, so
  # "1.60.1-DEV" counts as >= "1.60.1". That is the wanted reading here: Debian
  # tags its ordinary release builds -DEV (its rclone 1.60.1 package reports
  # "rclone v1.60.1-DEV"), so the suffix marks a build, not a pre-release, and
  # treating it as older would reinstall over a package that was already fine.
  #
  # `sed -n 1p` rather than `head -1` — head exits early and hands sort a
  # SIGPIPE, which pipefail promotes to a failed assignment and `set -e` turns
  # into an abort of the whole script. Same footgun as the find above.
  [[ "$(printf '%s\n%s\n' "$want" "$have" | sort -V | sed -n 1p)" == "$want" ]]
}

# ── Neovim ─────────────────────────────────────────────────────
# Not from apt. Debian trixie ships 0.10.4 and Ubuntu 24.04 ships 0.9.5, but
# LazyVim requires 0.11.2 and refuses to start below it — so the apt package is
# not a slightly-old editor here, it is one that opens to an error and no
# config. Arch's neovim tracks upstream, which is why headless.txt still names
# the package and only this path replaces it.
#
# fetch_github_release_binary can't be reused: upstream ships a relocatable
# *tree*, not a single binary — bin/nvim needs share/nvim/runtime alongside it.
# So the whole thing goes to ~/.local/share and only a symlink lands in
# ~/.local/bin. nvim derives $VIMRUNTIME from the resolved path of its own
# executable, so it follows that symlink home on its own and no VIMRUNTIME
# export is needed (verified: bin/nvim reached via a symlink in another
# directory still finds its runtime).
NVIM_MIN=0.11.2
NVIM_PREFIX="$HOME/.local/share/nvim-release"

# Version of the nvim on PATH, bare ("0.12.4"), or empty when there is none.
# The first line is "NVIM v0.12.4".
nvim_installed_version() {
  command -v nvim >/dev/null 2>&1 || return 0
  nvim --version 2>/dev/null | sed -n '1s/^NVIM v//p'
}

# Subshell + EXIT trap for temp-dir cleanup on every path, as above.
install_neovim() (
  local have arch asset url tmp top
  have="$(nvim_installed_version)"
  if version_at_least "$have" "$NVIM_MIN"; then
    return 0
  fi

  case "$(uname -m)" in
    x86_64)        arch=x86_64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) warn "no upstream Neovim build for $(uname -m) — install nvim >= $NVIM_MIN manually"; return 1 ;;
  esac

  # The asset name carries no version, so /releases/latest/download/ resolves it
  # without the extra API round-trip fetch_github_release_binary needs for %V%.
  asset="nvim-linux-$arch.tar.gz"
  url="https://github.com/neovim/neovim/releases/latest/download/$asset"

  log "Installing Neovim from upstream (apt has ${have:-none}, need >= $NVIM_MIN)"

  tmp="$(mktemp -d)" || { warn "could not create temp dir for neovim"; return 1; }
  trap 'rm -rf "$tmp"' EXIT

  if ! curl -fsSL --retry 3 --connect-timeout 20 --max-time 300 -o "$tmp/$asset" "$url"; then
    warn "download failed for neovim ($url) — install nvim >= $NVIM_MIN manually"
    return 1
  fi
  if ! tar -xzf "$tmp/$asset" -C "$tmp"; then
    warn "could not extract $asset — install nvim >= $NVIM_MIN manually"
    return 1
  fi

  top="$tmp/nvim-linux-$arch"
  if [[ ! -x "$top/bin/nvim" ]]; then
    warn "$asset did not contain bin/nvim where expected — install nvim manually"
    return 1
  fi

  # Stage in $tmp and move the finished tree in, the way
  # run_once_install_astronvim.sh stages its clone: extracting straight over
  # $NVIM_PREFIX would leave a half-written tree that the symlink already points
  # into if the run is interrupted. The rm only fires once the new tree is
  # extracted and checked, so the window where neither exists is a rename wide.
  mkdir -p "$(dirname "$NVIM_PREFIX")" "$HOME/.local/bin" || {
    warn "could not create ~/.local/share — install nvim manually"; return 1; }
  rm -rf "$NVIM_PREFIX"
  if ! mv "$top" "$NVIM_PREFIX"; then
    warn "could not move the neovim tree into $NVIM_PREFIX — install nvim manually"
    return 1
  fi
  # ~/.local/bin precedes /usr/bin on PATH (see .zshrc), so this shadows any
  # apt-installed nvim that is still present from an earlier provision.
  ln -sf "$NVIM_PREFIX/bin/nvim" "$HOME/.local/bin/nvim" \
    || { warn "could not symlink nvim into ~/.local/bin"; return 1; }

  log "  Neovim $("$NVIM_PREFIX/bin/nvim" --version 2>/dev/null | sed -n '1s/^NVIM v//p') installed to $NVIM_PREFIX"
)

# ── rclone ─────────────────────────────────────────────────────
# Same shape as neovim, different reason. The Filen backend landed in rclone
# 1.73.0 (verified: backend/filen/ and docs/content/filen.md both first exist at
# that tag, neither at 1.72.0), and trixie ships 1.60.1 — so on Debian
# `rclone config` simply does not offer filen as a provider. Arch's rclone is
# 1.75.0, which is why headless.txt names the package and only this path
# replaces it.
#
# Not routed through fetch_github_release_binary for two reasons: that function
# skips on `command -v` where this needs a version floor, and rclone ships a
# .zip, which its tar-only extract case does not handle.
RCLONE_MIN=1.73.0

# Version of the rclone on PATH, bare ("1.75.0"), or empty when there is none.
# The first line is "rclone v1.75.0"; Debian's package reports "rclone
# v1.60.1-DEV", which parses to "1.60.1-DEV" and compares as described in
# version_at_least — either way it is far below the floor.
rclone_installed_version() {
  command -v rclone >/dev/null 2>&1 || return 0
  rclone version 2>/dev/null | sed -n '1s/^rclone v//p'
}

# Subshell + EXIT trap for temp-dir cleanup on every path, as above.
install_rclone() (
  local have arch tag asset url tmp bin
  have="$(rclone_installed_version)"
  if version_at_least "$have" "$RCLONE_MIN"; then
    return 0
  fi

  case "$(uname -m)" in
    x86_64)        arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) warn "no upstream rclone build for $(uname -m) — install rclone >= $RCLONE_MIN manually"; return 1 ;;
  esac

  if ! command -v unzip >/dev/null 2>&1; then
    warn "unzip not installed — cannot unpack rclone; install rclone >= $RCLONE_MIN manually"
    return 1
  fi

  # rclone embeds the version in both the asset name and the directory inside
  # it, so unlike neovim the tag has to be resolved first — same redirect trick
  # fetch_github_release_binary uses for its %V% assets.
  if ! tag="$(curl -fsSL --retry 3 --connect-timeout 20 --max-time 60 \
        -o /dev/null -w '%{url_effective}' \
        "https://github.com/rclone/rclone/releases/latest" | sed 's#.*/##')" || [[ -z "$tag" ]]; then
    warn "could not resolve the latest rclone release — install rclone >= $RCLONE_MIN manually"
    return 1
  fi

  asset="rclone-$tag-linux-$arch.zip"
  url="https://github.com/rclone/rclone/releases/download/$tag/$asset"

  log "Installing rclone from upstream (apt has ${have:-none}, need >= $RCLONE_MIN for the Filen backend)"

  tmp="$(mktemp -d)" || { warn "could not create temp dir for rclone"; return 1; }
  trap 'rm -rf "$tmp"' EXIT

  # ~90 MB unpacked, so a longer --max-time than the single-binary fetches get.
  if ! curl -fsSL --retry 3 --connect-timeout 20 --max-time 300 -o "$tmp/$asset" "$url"; then
    warn "download failed for rclone ($url) — install rclone >= $RCLONE_MIN manually"
    return 1
  fi
  if ! unzip -qo "$tmp/$asset" -d "$tmp"; then
    warn "could not extract $asset — install rclone >= $RCLONE_MIN manually"
    return 1
  fi

  bin="$tmp/rclone-$tag-linux-$arch/rclone"
  if [[ ! -f "$bin" ]]; then
    warn "$asset did not contain rclone where expected — install it manually"
    return 1
  fi

  # A single binary, so unlike neovim this needs no prefix directory — the man
  # page and READMEs in the zip are the only other contents and nothing here
  # reads them. install(1) writes to a temp name and renames, so a concurrent
  # rclone keeps running off the old inode rather than reading a half-written
  # file. ~/.local/bin precedes /usr/bin on PATH (see .zshrc), so this shadows
  # any apt-installed rclone still present from an earlier provision.
  mkdir -p "$HOME/.local/bin" || { warn "could not create ~/.local/bin"; return 1; }
  if ! install -m 755 "$bin" "$HOME/.local/bin/rclone"; then
    warn "could not install rclone to ~/.local/bin"
    return 1
  fi

  log "  rclone ${tag#v} installed to ~/.local/bin/rclone"
)

install_apt_headless() {
  mkdir -p "$HOME/.local/bin"

  if ! $HAVE_ROOT; then
    warn "no root or passwordless sudo — install these yourself, then re-run:"
    warn "  apt-get install $(read_pkg_list "$PKG_DIR/headless-apt.txt" | tr '\n' ' ')"
  else
    collect_pkgs "$PKG_DIR/headless-apt.txt"

    # GitHub CLI and HashiCorp both ship their own apt repos; add each only
    # when its tool is missing, so re-runs don't re-add or re-fetch keys. Each
    # block is one `&&` chain used as an `if` condition — under `set -e` that's
    # the only way a failure partway (bad network, permission edge case) stops
    # just this repo add instead of aborting the whole script.
    if ! command -v gh >/dev/null 2>&1; then
      if "${SUDO[@]}" mkdir -p -m 755 /etc/apt/keyrings \
        && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
             | "${SUDO[@]}" tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null \
        && "${SUDO[@]}" chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
        && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
             | "${SUDO[@]}" tee /etc/apt/sources.list.d/github-cli.list >/dev/null
      then
        PKGS+=(gh)
      else
        warn "could not add the GitHub CLI apt repo — install gh manually"
      fi
    fi
    log "Installing ${#PKGS[@]} packages from headless-apt.txt (+ gh repo as needed)"
    apt_install "headless-apt.txt" "${PKGS[@]}"
  fi

  # bat/fd-find install their binaries as batcat/fdfind on Debian — symlink
  # the names the rest of this repo (aliases, FZF_DEFAULT_COMMAND) expects.
  # `|| true`: neither symlink existing is a normal, non-fatal outcome (e.g.
  # apt install above failed), not a reason to abort the rest of the script.
  if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
    ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat" || true
  fi
  if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
    ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd" || true
  fi

  # The pacman package "yq" is kislyuk's python-yq (a jq wrapper), not
  # mikefarah's go-yq — install the same one via pipx for parity.
  if ! command -v yq >/dev/null 2>&1 && command -v pipx >/dev/null 2>&1; then
    pipx install yq >/dev/null 2>&1 || warn "pipx install yq failed — install manually"
  fi

  # No apt package at all: official installers, unprivileged. Each is a
  # complete `if ... ; then ... || warn; fi` — the trailing `|| warn` matters
  # under `set -e`: without it, a failed install (network down) would be the
  # last command run and would abort the whole script.
  # `-f` matters on a piped install: without it curl hands an HTTP error body
  # (a 502 page, a captive-portal interstitial) straight to `sh` and it gets
  # executed. Every other curl in this repo already uses -fsSL.
  if ! command -v starship >/dev/null 2>&1; then
    curl -fsSL --retry 3 --connect-timeout 20 https://starship.rs/install.sh \
      | sh -s -- -y --bin-dir "$HOME/.local/bin" >/dev/null \
      || warn "starship install failed — install manually"
  fi
  if ! command -v rustup >/dev/null 2>&1; then
    curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | sh -s -- -y >/dev/null 2>&1 \
      || warn "rustup install failed — install manually"
  fi

  # No apt package at all: GitHub release binaries, unprivileged. `|| true` on
  # each call: the function already warns internally on failure, this just
  # stops that failure's exit status from aborting the rest of the script.
  fetch_github_release_binary jesseduffield/lazygit "lazygit_%V%_Linux_x86_64.tar.gz" lazygit || true
  fetch_github_release_binary dundee/gdu "gdu_linux_amd64.tgz" gdu gdu_linux_amd64 || true
  fetch_github_release_binary ClementTsang/bottom "bottom_x86_64-unknown-linux-gnu.tar.gz" btm || true
  fetch_github_release_binary fastfetch-cli/fastfetch "fastfetch-linux-amd64.tar.gz" fastfetch || true
  # carapace is the shell's only completion engine now that .zshrc no longer
  # loads zsh-users/zsh-completions, so the apt path has to supply it too —
  # it's carapace-bin in the AUR, but has no apt package.
  fetch_github_release_binary carapace-sh/carapace-bin "carapace-bin_%V%_linux_amd64.tar.gz" carapace || true
  # No apt package, not on crates.io or PyPI either — GitHub release binary is
  # the only distribution channel. Needed by the fastfetch greeting's logo
  # source (`pokeget sylveon --hide-name` in dot_config/fastfetch/config.jsonc).
  fetch_github_release_binary talwat/pokeget-rs "pokeget-Linux-x86_64.tar.gz" pokeget || true

  # In apt, but too old to be usable — see the version_at_least block above.
  # `|| true` for the same reason as the calls above: they warn internally.
  install_neovim || true
  install_rclone || true
}

if [[ "$SKIP_PACKAGES" == true ]]; then
  log "Skipping package lists (--no-packages)"
elif command -v pacman >/dev/null 2>&1; then
  pkg_files=("$PKG_DIR/headless.txt")
  if [[ "$IS_DESKTOP" == true ]]; then
    pkg_files+=("$PKG_DIR/desktop.txt")
  fi
  collect_pkgs "${pkg_files[@]}"

  if [[ ${#PKGS[@]} -eq 0 ]]; then
    warn "package lists are empty — nothing to install"
  elif ! $HAVE_ROOT; then
    warn "no root or passwordless sudo — install these yourself, then re-run:"
    warn "  pacman -S --needed ${PKGS[*]}"
  else
    log "Installing ${#PKGS[@]} packages from $(basename -a "${pkg_files[@]}" | tr '\n' ' ')"
    # -Syu rather than -Sy: pulling a package built against a newer library into
    # a half-updated system is the classic Arch partial-upgrade breakage.
    "${SUDO[@]}" pacman -Syu --noconfirm --needed "${PKGS[@]}" \
      || warn "pacman failed — check the package names in $PKG_DIR"
  fi
elif command -v apt-get >/dev/null 2>&1; then
  log "Debian/Ubuntu host — installing headless-apt.txt in place of the pacman lists"
  install_apt_headless
else
  log "Not an Arch or Debian/Ubuntu host — skipping package lists (pacman/apt-get only)"
fi

# ── AUR packages ───────────────────────────────────────────────
# Same headless/desktop split as above: headless-aur.txt everywhere, plus
# desktop-aur.txt in desktop mode. Bootstraps paru-bin from the AUR when no
# helper is present. makepkg refuses to run as root, so this needs a normal
# user holding passwordless sudo.

#
# Subshell + EXIT trap so an interrupted bootstrap doesn't leave the clone and a
# half-built package behind in /tmp.
bootstrap_paru() (
  local tmp rc=0
  tmp="$(mktemp -d)" || { warn "could not create temp dir for the paru bootstrap"; return 1; }
  trap 'rm -rf "$tmp"' EXIT
  if git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin"; then
    ( cd "$tmp/paru-bin" && makepkg -si --noconfirm ) || rc=$?
  else
    rc=1
  fi
  return "$rc"
)

if [[ "$SKIP_PACKAGES" != true ]] && command -v pacman >/dev/null 2>&1; then
  aur_files=("$PKG_DIR/headless-aur.txt")
  if [[ "$IS_DESKTOP" == true ]]; then
    aur_files+=("$PKG_DIR/desktop-aur.txt")
  fi
  collect_pkgs "${aur_files[@]}"

  if [[ ${#PKGS[@]} -eq 0 ]]; then
    :
  elif [[ "$(id -u)" -eq 0 ]]; then
    warn "running as root — makepkg won't build as root, skipping AUR packages:"
    warn "  ${PKGS[*]}"
  elif ! $HAVE_ROOT; then
    warn "no passwordless sudo — install these AUR packages yourself:"
    warn "  ${PKGS[*]}"
  else
    AUR_HELPER=""
    for helper in paru yay; do
      if command -v "$helper" >/dev/null 2>&1; then AUR_HELPER="$helper"; break; fi
    done

    if [[ -z "$AUR_HELPER" ]]; then
      log "Bootstrapping paru"
      if bootstrap_paru; then
        AUR_HELPER=paru
      else
        warn "paru bootstrap failed — install these AUR packages yourself:"
        warn "  ${PKGS[*]}"
      fi
    fi

    if [[ -n "$AUR_HELPER" ]]; then
      log "Installing ${#PKGS[@]} AUR packages via $AUR_HELPER from $(basename -a "${aur_files[@]}" | tr '\n' ' ')"
      "$AUR_HELPER" -S --needed --noconfirm "${PKGS[@]}" \
        || warn "$AUR_HELPER failed — check the package names in $PKG_DIR"
    fi
  fi
fi

# ── Rust toolchain ─────────────────────────────────────────────
# rustup is a manager, not a toolchain: Arch's `rustup` package installs only
# the shims, and `cargo` on a fresh box errors with "no default toolchain" until
# one is selected. (The apt path's sh.rustup.rs -y already picks stable, so this
# is a no-op there.) Unprivileged — everything lands in ~/.rustup and
# ~/.cargo/bin, which .zshrc puts on PATH.
#
# Guarded on `rustup default` rather than run unconditionally: a bare
# `rustup default stable` hits the network on every re-run, and this script is
# meant to be cheap to re-run. Non-fatal like the rest of the package phase.
if [[ "$SKIP_PACKAGES" != true ]] && command -v rustup >/dev/null 2>&1; then
  if rustup default >/dev/null 2>&1; then
    log "Rust toolchain already selected ($(rustup default 2>/dev/null | cut -d' ' -f1))"
  else
    log "Installing the stable Rust toolchain (rustup default stable)"
    rustup default stable >/dev/null 2>&1 \
      || warn "rustup default stable failed — run it yourself once you have network"
  fi
fi

# ── Browser extensions — retired enterprise policies ───────────
# install.sh no longer installs browser extensions at all. Both browsers now get
# packages/browser-extensions.txt through dots/run_install_browser_extensions.sh,
# which downloads each CRX with curl and registers it locally under
# <user-data-dir>/External Extensions/ — no root, and one mechanism instead of
# two that failed in different ways.
#
# Two policy files were written here before that, and both have to be actively
# removed rather than merely stopped:
#
#   /etc/chromium/policies/managed/  ExtensionInstallForcelist (ungoogled-chromium)
#   /etc/brave/policies/managed/     ExtensionSettings         (brave-origin)
#
# Leaving either in place breaks the replacement. A policy entry outranks the
# local registration in the pending-install queue, so the working install never
# fires while it is there: "entered for update more than once. old location:
# kExternalPolicyDownload  new location: kExternalPref". The chromium one was
# doubly dead — that build's compiled-in store URL is domain substituted to a
# host that does not resolve, so it never installed anything either.
#
# Only a file this script recognises as one it wrote is removed; an unrelated
# policy that happens to live at the same path is left alone. Desktop-only, and
# never fatal — cleanup that cannot run just means an extra `chezmoi apply` once
# someone runs install.sh with privileges.
if [[ "$IS_DESKTOP" == true ]]; then
  RETIRED_POLICIES=(
    /etc/chromium/policies/managed/extensions.json
    /etc/brave/policies/managed/extensions.json
  )

  # True only for a file this script recognises as one it wrote. Written once
  # and used by both loops below — the detection used to be spelled out twice,
  # so the two could drift and silently start disagreeing about what to delete.
  is_retired_policy() {
    [[ -f "$1" ]] && grep -qE 'ExtensionInstallForcelist|ExtensionSettings' "$1" 2>/dev/null
  }

  stale_policies=()
  for policy in "${RETIRED_POLICIES[@]}"; do
    is_retired_policy "$policy" && stale_policies+=("$policy")
  done

  if [[ ${#stale_policies[@]} -eq 0 ]]; then
    :   # nothing left over
  elif ! $HAVE_ROOT; then
    warn "no root or passwordless sudo — a retired extension policy is still in /etc"
    warn "  it blocks the local-CRX install that replaced it; re-run install.sh"
    warn "  with privileges, or remove it by hand:"
    for policy in "${stale_policies[@]}"; do
      warn "    sudo rm $policy"
    done
  else
    for policy in "${stale_policies[@]}"; do
      if "${SUDO[@]}" rm -f "$policy"; then
        log "Removed retired extension policy $policy"
        # rmdir, not rm -r: the managed/ and policies/ directories are only
        # cleared when this script's file was the last thing in them.
        "${SUDO[@]}" rmdir "$(dirname "$policy")" "$(dirname "$(dirname "$policy")")" 2>/dev/null || true
      else
        warn "could not remove $policy — it will block the local CRX install"
      fi
    done
    log "  extensions are installed by run_install_browser_extensions.sh on apply"
  fi
fi

# ═══════════════════════════════════════════════════════════════
# MAIN — dotfiles (no privileges needed)
# ═══════════════════════════════════════════════════════════════

# ── Submodules ─────────────────────────────────────────────────
# A plain `git clone` (no --recursive) leaves every submodule as an empty
# directory, and a GitHub source tarball omits them entirely. chezmoi then
# applies that emptiness happily: ~/.config/quickshell/end4-pC ends up with
# nothing in it, and the config Hyprland points `qsConfig` at (see
# dots/dot_config/hypr/hyprland/variables.lua) has nothing to load. So this runs
# *before* the apply, not after.
#
# Not gated on --headless: .chezmoiignore does not exclude .config/quickshell,
# so a headless machine is handed the same source tree and would hit the same
# empty directory.
#
# Never fatal — a missing submodule costs one config, where aborting would cost
# the whole dotfiles apply.
if [[ -f "$REPO_DIR/.gitmodules" ]]; then
  if ! command -v git >/dev/null 2>&1; then
    warn "git not installed — cannot fetch submodules; their configs will apply empty"
  elif git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    # `git submodule status` prefixes an uninitialised submodule with `-`, so a
    # repo that was already cloned --recursive touches the network not at all.
    if git -C "$REPO_DIR" submodule status --recursive 2>/dev/null | grep -q '^-'; then
      log "Fetching submodules"
      git -C "$REPO_DIR" submodule update --init --recursive --depth 1 \
        || warn "submodule fetch failed — re-run: git -C $REPO_DIR submodule update --init --recursive"
    fi
  else
    # Not a checkout at all — a downloaded tarball or zip. There is no submodule
    # machinery to init here, so each .gitmodules entry is cloned by hand.
    # `git config -f` reads the file as plain config and needs no repository.
    while read -r key sub_path; do
      [[ -n "$sub_path" ]] || continue
      name="${key#submodule.}"; name="${name%.path}"
      url="$(git config -f "$REPO_DIR/.gitmodules" --get "submodule.$name.url" || true)"
      if [[ -z "$url" ]]; then
        warn "no url for submodule $name in .gitmodules — skipping"
        continue
      fi
      # Anything already populated is left alone: this path cannot tell a stale
      # checkout from a current one, and clobbering it would be worse than
      # leaving it.
      if [[ -n "$(ls -A "$REPO_DIR/$sub_path" 2>/dev/null)" ]]; then
        continue
      fi
      log "Fetching submodule $sub_path (this is not a git checkout)"
      # --depth 1: nothing here needs history, and the recorded commit is
      # unavailable anyway — there is no superproject gitlink to read it from.
      git clone --depth 1 "$url" "$REPO_DIR/$sub_path" \
        || warn "could not clone $url — $sub_path will apply empty"
    done < <(git config -f "$REPO_DIR/.gitmodules" --get-regexp '^submodule\..*\.path$' || true)
  fi
fi

# ── ii-quickshell setup ────────────────────────────────────────
# Runs the fork's own installer before chezmoi apply, same reasoning as the
# submodule fetch above: dots/dot_config/hypr/hyprland/variables.lua points
# qsConfig at this config, so it needs to be in place before anything tries to
# load it. Never fatal — a failure here warns and the rest of the dotfiles
# still apply.
#
# `apply` (the script's default command) refuses to run until the base
# illogical-impulse dotfiles are present, since it only lays down the
# Quickshell config on top of them. On a machine where they're missing —
# i.e. this is the first run — `install` is what pulls in that base first.
# Once ~/.config/illogical-impulse exists, later runs go back to the cheap
# `apply`, so this doesn't reinstall system packages on every re-run.
if [[ -f "$REPO_DIR/ii-quickshell/setup-ii-p3drovfx.sh" ]]; then
  ii_cmd=apply
  [[ -d "${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse" ]] || ii_cmd=install
  log "Running ii-quickshell setup ($ii_cmd)"
  chmod +x "$REPO_DIR/ii-quickshell/setup-ii-p3drovfx.sh"
  "$REPO_DIR/ii-quickshell/setup-ii-p3drovfx.sh" "$ii_cmd" -y \
    || warn "ii-quickshell setup failed — re-run: $REPO_DIR/ii-quickshell/setup-ii-p3drovfx.sh"
fi

log "Installing chezmoi"
if ! command -v chezmoi >/dev/null 2>&1; then
  # The installer is captured and checked rather than piped straight into
  # `sh -c "$(...)"`: on a failed download the command substitution is empty,
  # `sh -c ""` exits 0, `set -e` never fires, and the real failure surfaces
  # several lines later as an opaque "chezmoi: command not found". This is the
  # one step in the script that genuinely must succeed, so it fails loudly.
  chezmoi_installer="$(curl -fsLS --retry 3 --connect-timeout 20 get.chezmoi.io)" || {
    warn "could not download the chezmoi installer from get.chezmoi.io"
    warn "install chezmoi yourself and re-run: https://www.chezmoi.io/install/"
    exit 1
  }
  if [[ -z "$chezmoi_installer" ]]; then
    warn "the chezmoi installer downloaded empty — refusing to run it"
    exit 1
  fi
  sh -c "$chezmoi_installer" -- -b "$HOME/.local/bin"

  if ! command -v chezmoi >/dev/null 2>&1; then
    warn "the chezmoi installer ran but chezmoi is still not on PATH"
    warn "check that $HOME/.local/bin is writable, then re-run"
    exit 1
  fi
fi

# --promptBool is always passed explicitly: chezmoi does *not* fall back to a
# template default when it cannot reach a TTY, it errors with EOF. Passing the
# flag is what makes this run unattended.
#
# It is only honoured on a machine chezmoi has not been initialised on yet:
# dots/.chezmoi.toml.tmpl uses promptBoolOnce, which returns the persisted
# answer thereafter. Warn on a mismatch rather than letting --headless look like
# it worked while every desktop-only script keeps running.
CHEZMOI_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi/chezmoi.toml"
if [[ -f "$CHEZMOI_CONFIG" ]] && grep -q '^[[:space:]]*isDesktop[[:space:]]*=' "$CHEZMOI_CONFIG" 2>/dev/null; then
  persisted="$(sed -n 's/^[[:space:]]*isDesktop[[:space:]]*=[[:space:]]*\([a-z]*\).*/\1/p' "$CHEZMOI_CONFIG" | head -1)"
  if [[ -n "$persisted" && "$persisted" != "$IS_DESKTOP" ]]; then
    warn "chezmoi already has isDesktop=$persisted persisted in $CHEZMOI_CONFIG"
    warn "  this run asked for isDesktop=$IS_DESKTOP, which promptBoolOnce will ignore"
    warn "  edit that file if you meant to switch the machine's mode"
  fi
fi

log "Applying dotfiles (isDesktop=$IS_DESKTOP)"
chezmoi init --apply --no-tty \
  --promptBool "isDesktop=$IS_DESKTOP" \
  --source "$REPO_DIR"

# ═══════════════════════════════════════════════════════════════
# POST — login shell
# ═══════════════════════════════════════════════════════════════

# The passwd entry, not $SHELL: $SHELL is the shell of the *invoking* session,
# so running `bash install.sh` from a zsh terminal on a machine whose login
# shell is still bash used to report "already zsh" and skip chsh forever.
current_login_shell() {
  getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7
}

ZSH_PATH="$(command -v zsh 2>/dev/null || true)"
if [[ -z "$ZSH_PATH" ]]; then
  warn "zsh not installed — skipping login shell change"
elif [[ "$(current_login_shell)" == "$ZSH_PATH" ]]; then
  log "Login shell already zsh"
elif ! $HAVE_ROOT; then
  warn "no root or passwordless sudo — set the login shell yourself:"
  warn "  chsh -s $ZSH_PATH"
else
  log "Setting login shell to zsh"
  grep -qxF "$ZSH_PATH" /etc/shells 2>/dev/null \
    || echo "$ZSH_PATH" | "${SUDO[@]}" tee -a /etc/shells >/dev/null
  "${SUDO[@]}" chsh -s "$ZSH_PATH" "$(id -un)" || warn "chsh failed — set it manually"
fi

# ── SDDM — retired display manager ──────────────────────────────
# Hyprland now starts itself: systemd autologins tty1 and dots/dot_zprofile
# execs Hyprland from there, so SDDM's autologin-into-hyprland setup (and the
# ii-sddm-theme greeter it showed on the way) is just a frame around a step
# that no longer needs one.
#
# Retroactive and idempotent — this only ever arrived via pacman, so a host
# that never had sddm, or was already cleaned up by a previous run, hits the
# `pacman -Qq` guard and no-ops. Desktop + Arch only, matching every other
# sddm/theme reference in this repo.
if [[ "$IS_DESKTOP" == true ]] && command -v pacman >/dev/null 2>&1; then
  if pacman -Qq sddm >/dev/null 2>&1; then
    if ! $HAVE_ROOT; then
      warn "no root or passwordless sudo — remove sddm yourself:"
      warn "  sudo systemctl disable sddm.service"
      warn "  sudo pacman -Rns sddm"
      warn "  sudo rm -rf /usr/share/sddm/themes/ii-sddm-theme /etc/sddm.conf /etc/sddm.conf.d"
    else
      log "Removing sddm (Hyprland now starts itself via tty1 autologin)"
      # disable before remove: pacman won't stop/disable a running service on
      # its own, and a leftover display-manager.service symlink would still
      # point at the now-deleted unit.
      "${SUDO[@]}" systemctl disable sddm.service 2>/dev/null || true
      "${SUDO[@]}" pacman -Rns --noconfirm sddm \
        || warn "pacman could not remove sddm — remove it manually"
      "${SUDO[@]}" rm -rf /usr/share/sddm/themes/ii-sddm-theme /etc/sddm.conf /etc/sddm.conf.d
    fi
  fi

  # tty1 autologin is what dot_zprofile's `exec Hyprland` depends on to ever
  # run — set up unconditionally, not just when sddm was found, so a host
  # that never had sddm still ends up with a way into Hyprland.
  AUTOLOGIN_CONF=/etc/systemd/system/getty@tty1.service.d/autologin.conf
  AUTOLOGIN_USER="$(id -un)"
  if [[ -f "$AUTOLOGIN_CONF" ]] && grep -q -- "--autologin $AUTOLOGIN_USER " "$AUTOLOGIN_CONF" 2>/dev/null; then
    log "tty1 autologin already set up for $AUTOLOGIN_USER"
  elif ! $HAVE_ROOT; then
    warn "no root or passwordless sudo — enable tty1 autologin yourself:"
    warn "  see $AUTOLOGIN_CONF"
  else
    log "Enabling tty1 autologin for $AUTOLOGIN_USER"
    "${SUDO[@]}" mkdir -p "$(dirname "$AUTOLOGIN_CONF")"
    printf '[Service]\nExecStart=\nExecStart=-/sbin/agetty --autologin %s --noclear %%I $TERM\n' "$AUTOLOGIN_USER" \
      | "${SUDO[@]}" tee "$AUTOLOGIN_CONF" >/dev/null
    "${SUDO[@]}" systemctl daemon-reload
    "${SUDO[@]}" systemctl enable getty@tty1.service 2>/dev/null || true
  fi

  # ── Passwordless sudo ──────────────────────────────────────────
  # Companion to tty1 autologin above: without a display manager caching a
  # PAM session, the sudo password becomes the only prompt left anywhere in
  # this single-user desktop's boot path. This makes sudo itself passwordless
  # for the account too, so it's consistent everywhere sudo is invoked, not
  # just inside this script.
  #
  # `visudo -cf` validates the drop-in *before* it's installed — a syntax
  # error landing straight in a live /etc/sudoers.d file breaks sudo for
  # everyone, including the root shell that would otherwise fix it.
  SUDOERS_USER="$(id -un)"
  SUDOERS_DROPIN="/etc/sudoers.d/${SUDOERS_USER}-nopasswd"
  if [[ -f "$SUDOERS_DROPIN" ]]; then
    log "Passwordless sudo already set up for $SUDOERS_USER"
  elif ! $HAVE_ROOT; then
    warn "no root or passwordless sudo — set up passwordless sudo yourself:"
    warn "  echo '$SUDOERS_USER ALL=(ALL) NOPASSWD: ALL' | sudo tee $SUDOERS_DROPIN"
    warn "  sudo chmod 0440 $SUDOERS_DROPIN"
  else
    log "Enabling passwordless sudo for $SUDOERS_USER"
    tmp_sudoers="$(mktemp)"
    echo "$SUDOERS_USER ALL=(ALL) NOPASSWD: ALL" > "$tmp_sudoers"
    if "${SUDO[@]}" visudo -cf "$tmp_sudoers" >/dev/null 2>&1; then
      "${SUDO[@]}" install -m 0440 -o root -g root "$tmp_sudoers" "$SUDOERS_DROPIN" \
        || warn "could not install $SUDOERS_DROPIN — set up passwordless sudo manually"
    else
      warn "generated sudoers drop-in failed visudo validation — skipping (this should not happen)"
    fi
    rm -f "$tmp_sudoers"
  fi
fi

# Pre-warm zinit so the first real terminal is fast. Never fatal.
log "Pre-warming zinit"
zsh -ic '' >/dev/null 2>&1 || true

log "Done."
