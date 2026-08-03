#!/usr/bin/env bash
#
# Unattended installer — never prompts, safe for Packer, cloud-init and Codespaces.
#
#   bash install.sh              # desktop (default)
#   bash install.sh --headless   # headless: VM, container, Codespace
#   bash install.sh --no-packages  # dotfiles only, no package lists
#
# Equivalent env vars: DOTFILES_HEADLESS=1, DOTFILES_SKIP_PACKAGES=1
# Codespaces is auto-detected and treated as headless.
#
# Layout:
#   pre   — system packages   (needs root/passwordless sudo; skipped otherwise)
#   main  — dotfiles          (no privileges required)
#   post  — login shell       (needs root/passwordless sudo; skipped otherwise)
#
# Tools come from the packages/ lists, not from a version manager. On a non-Arch
# host the pre phase installs only the four prerequisites below, so you get the
# dotfiles and nothing else.
#
# Only "main" is required. The pre/post phases no-op with a warning when
# privileges are unavailable, so the script still succeeds on locked-down hosts.

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
for arg in "$@"; do
  case "$arg" in
    --headless)    IS_DESKTOP=false ;;
    --desktop)     IS_DESKTOP=true ;;
    --no-packages) SKIP_PACKAGES=true ;;
    -h|--help)  sed -n '2,19p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "install.sh: unknown argument: $arg" >&2; exit 2 ;;
  esac
done

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m warning:\033[0m %s\n' "$*" >&2; }

# ── Privilege detection ────────────────────────────────────────
# SUDO is the command prefix to run something as root, or "" if we cannot.
# `sudo -n` never prompts for a password, so an unattended run can't hang.
SUDO=""
HAVE_ROOT=true
if [[ "$(id -u)" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    SUDO="sudo -n"
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
  REQUIRED_CMDS+=(unzip)      # for run_once_install_adnauseam.sh
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

    if command -v apt-get >/dev/null 2>&1; then
      $SUDO env DEBIAN_FRONTEND=noninteractive apt-get update -qq
      $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${pkgs[@]}"
    elif command -v dnf >/dev/null 2>&1; then
      $SUDO dnf install -y "${pkgs[@]}"
    elif command -v pacman >/dev/null 2>&1; then
      $SUDO pacman -Sy --noconfirm --needed "${pkgs[@]}"
    elif command -v apk >/dev/null 2>&1; then
      $SUDO apk add --no-cache "${pkgs[@]}"
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
  sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$file" \
    | grep -v '^$' || true
}

collect_pkgs() {
  local file line
  for file in "$@"; do
    while IFS= read -r line; do
      [[ -n "$line" ]] && PKGS+=("$line")
    done < <(read_pkg_list "$file")
  done
}

if [[ "$SKIP_PACKAGES" == true ]]; then
  log "Skipping package lists (--no-packages)"
elif ! command -v pacman >/dev/null 2>&1; then
  log "Not an Arch host — skipping package lists (pacman-only)"
else
  PKGS=()
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
    $SUDO pacman -Syu --noconfirm --needed "${PKGS[@]}" \
      || warn "pacman failed — check the package names in $PKG_DIR"
  fi
fi

# ── AUR packages ───────────────────────────────────────────────
# Same headless/desktop split as above: headless-aur.txt everywhere, plus
# desktop-aur.txt in desktop mode. Bootstraps paru-bin from the AUR when no
# helper is present. makepkg refuses to run as root, so this needs a normal
# user holding passwordless sudo.

bootstrap_paru() {
  local tmp rc=0
  tmp="$(mktemp -d)"
  if git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin"; then
    ( cd "$tmp/paru-bin" && makepkg -si --noconfirm ) || rc=$?
  else
    rc=1
  fi
  rm -rf "$tmp"
  return "$rc"
}

if [[ "$SKIP_PACKAGES" != true ]] && command -v pacman >/dev/null 2>&1; then
  PKGS=()
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

# ── Browser extensions (ExtensionInstallForcelist) ─────────────
# Chromium has no CLI to install extensions, so the only declarative route is an
# enterprise policy. Both browsers read a JSON file from a compiled-in path:
#
#   ungoogled-chromium  /etc/chromium/policies/managed/
#   brave-origin        /etc/brave/policies/managed/
#
# (Both paths were confirmed as literals inside the shipped binaries — the Brave
# build contains /etc/brave/policies *and* /etc/chromium/policies.)
#
# Root-only, desktop-only, and never fatal: a browser without its extensions is
# not a reason to fail a dotfiles install.
if [[ "$IS_DESKTOP" == true ]]; then
  EXT_LIST="$PKG_DIR/browser-extensions.txt"

  if [[ ! -f "$EXT_LIST" ]]; then
    :   # no list, nothing to enforce
  elif ! $HAVE_ROOT; then
    warn "no root or passwordless sudo — skipping browser extension policy"
    warn "  (run install.sh again with privileges to apply $EXT_LIST)"
  else
    # Strip comments and blanks; keep only well-formed 32-char extension IDs so a
    # typo can't produce a policy file the browser will reject wholesale.
    # NB: strip spaces/tabs/CR but NOT newlines — `tr -d '[:space:]'` would fold
    # the entire file onto one line and match nothing.
    mapfile -t EXT_IDS < <(sed 's/#.*//' "$EXT_LIST" | tr -d ' \t\r' | grep -E '^[a-p]{32}$' || true)

    if [[ ${#EXT_IDS[@]} -eq 0 ]]; then
      warn "no valid extension IDs in $EXT_LIST — skipping policy"
    else
      # ExtensionInstallForcelist entries are "<id>;<update-url>". The update URL
      # is the Chrome Web Store endpoint; without it some builds ignore the entry.
      CRX_URL="https://clients2.google.com/service/update2/crx"
      policy_json="{
  \"ExtensionInstallForcelist\": ["
      for i in "${!EXT_IDS[@]}"; do
        sep=","; [[ $i -eq $(( ${#EXT_IDS[@]} - 1 )) ]] && sep=""
        policy_json+="
    \"${EXT_IDS[$i]};${CRX_URL}\"${sep}"
      done
      policy_json+="
  ]
}"

      log "Applying ExtensionInstallForcelist (${#EXT_IDS[@]} extensions)"
      for dir in /etc/chromium/policies/managed /etc/brave/policies/managed; do
        if $SUDO mkdir -p "$dir" 2>/dev/null \
           && printf '%s\n' "$policy_json" | $SUDO tee "$dir/extensions.json" >/dev/null; then
          $SUDO chmod 644 "$dir/extensions.json" 2>/dev/null || true
          log "  wrote $dir/extensions.json"
        else
          warn "  could not write $dir/extensions.json"
        fi
      done

      warn "force-installed extensions cannot be disabled or removed from the"
      warn "browser UI — edit $EXT_LIST and re-run to change the set."
    fi
  fi
fi

# ═══════════════════════════════════════════════════════════════
# MAIN — dotfiles (no privileges needed)
# ═══════════════════════════════════════════════════════════════

log "Installing chezmoi"
if ! command -v chezmoi >/dev/null 2>&1; then
  sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
fi

# --promptBool is always passed explicitly: chezmoi does *not* fall back to a
# template default when it cannot reach a TTY, it errors with EOF. Passing the
# flag is what makes this run unattended.
log "Applying dotfiles (isDesktop=$IS_DESKTOP)"
chezmoi init --apply --no-tty \
  --promptBool "isDesktop=$IS_DESKTOP" \
  --source "$REPO_DIR"

# ═══════════════════════════════════════════════════════════════
# POST — login shell
# ═══════════════════════════════════════════════════════════════

ZSH_PATH="$(command -v zsh 2>/dev/null || true)"
if [[ -z "$ZSH_PATH" ]]; then
  warn "zsh not installed — skipping login shell change"
elif [[ "${SHELL:-}" == "$ZSH_PATH" ]]; then
  log "Login shell already zsh"
elif ! $HAVE_ROOT; then
  warn "no root or passwordless sudo — set the login shell yourself:"
  warn "  chsh -s $ZSH_PATH"
else
  log "Setting login shell to zsh"
  grep -qxF "$ZSH_PATH" /etc/shells 2>/dev/null \
    || echo "$ZSH_PATH" | $SUDO tee -a /etc/shells >/dev/null
  $SUDO chsh -s "$ZSH_PATH" "$(id -un)" || warn "chsh failed — set it manually"
fi

# Pre-warm zinit so the first real terminal is fast. Never fatal.
log "Pre-warming zinit"
zsh -ic '' >/dev/null 2>&1 || true

log "Done."
