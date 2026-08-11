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
# yq, lazygit, gdu, bottom, fastfetch, carapace, gh) and are fetched below via
# official installers, GitHub release binaries, or a third-party apt repo.
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
      local found
      found="$(find "$tmp" -type f -name "$inner_name" -print -quit)"
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

# Pre-warm zinit so the first real terminal is fast. Never fatal.
log "Pre-warming zinit"
zsh -ic '' >/dev/null 2>&1 || true

log "Done."
