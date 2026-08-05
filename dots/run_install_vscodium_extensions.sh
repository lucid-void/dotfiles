#!/usr/bin/env bash
# Installs/updates the VSCodium extensions dot_config/VSCodium/User/settings.json
# depends on. Runs on every `chezmoi apply` (plain `run_` prefix, not
# `run_once_`) so extensions get pulled to their latest version each time,
# not just installed once and left to drift.
#
# Deliberately not `set -e`. This script sorts second-to-last in chezmoi's
# target-name ordering, immediately before setup_aria2.sh — so an Open VSX
# outage or a single extension that has gone missing from the gallery used to
# take the aria2 daemon setup down with it. Every failure path warns and the
# rest of the list still gets installed.
set -uo pipefail

warn() { printf 'vscodium: %s\n' "$*" >&2; }

# Installed through codium's configured gallery. The vscodium-bin-marketplace
# package repoints that at the Microsoft marketplace, so only extensions
# published there belong in this list.
EXTENSIONS=(
  anthropic.claude-code
  # Required by settings.json's workbench.colorTheme / iconTheme keys —
  # without these the theme silently falls back to the VSCodium default.
  Catppuccin.catppuccin-vsc
  Catppuccin.catppuccin-vsc-icons
)

# Open VSX-only extensions. jeanp413 never published open-remote-ssh to the
# Microsoft marketplace, so `--install-extension jeanp413.open-remote-ssh`
# reports "not found". Fetch the VSIX from Open VSX directly instead of
# depending on whichever gallery is configured.
OPENVSX_EXTENSIONS=(
  jeanp413.open-remote-ssh
)

if ! command -v codium >/dev/null 2>&1; then
  echo "codium not on PATH — skipping extension install."
  exit 0
fi

failed=0

for ext in "${EXTENSIONS[@]}"; do
  echo "Installing $ext..."
  # NODE_NO_WARNINGS silences codium's own DEP0169 url.parse() deprecation
  # noise (upstream cliProcessMain.js, not ours to fix) on every extension.
  NODE_NO_WARNINGS=1 codium --install-extension "$ext" --force \
    || { warn "$ext failed to install"; failed=$((failed + 1)); }
done

if [[ ${#OPENVSX_EXTENSIONS[@]} -gt 0 ]]; then
  # jq parses the Open VSX API reply. It is in packages/headless.txt, but a
  # bare `chezmoi apply` on a machine that never ran install.sh won't have it —
  # guard rather than dying on `jq: command not found`.
  if ! command -v jq >/dev/null 2>&1; then
    warn "jq not installed — skipping the Open VSX extensions: ${OPENVSX_EXTENSIONS[*]}"
  elif ! command -v curl >/dev/null 2>&1; then
    warn "curl not installed — skipping the Open VSX extensions: ${OPENVSX_EXTENSIONS[*]}"
  else
    vsixdir="$(mktemp -d)" || { warn "could not create temp dir — skipping Open VSX"; exit 0; }
    trap 'rm -rf "$vsixdir"' EXIT

    for ext in "${OPENVSX_EXTENSIONS[@]}"; do
      echo "Installing $ext from Open VSX..."
      if ! url="$(curl -fsSL --retry 3 --connect-timeout 20 --max-time 60 \
            "https://open-vsx.org/api/${ext%%.*}/${ext#*.}/latest" \
            | jq -er '.files.download')"; then
        warn "$ext: could not resolve a download URL from Open VSX"
        failed=$((failed + 1))
        continue
      fi
      # The VSIX is named after the extension rather than left with mktemp's
      # random suffix, so codium's "was successfully installed" line names
      # something recognisable.
      if ! curl -fsSL --retry 3 --connect-timeout 20 --max-time 180 \
            -o "$vsixdir/$ext.vsix" "$url"; then
        warn "$ext: VSIX download failed"
        failed=$((failed + 1))
        continue
      fi
      NODE_NO_WARNINGS=1 codium --install-extension "$vsixdir/$ext.vsix" --force \
        || { warn "$ext failed to install"; failed=$((failed + 1)); }
    done
  fi
fi

[[ $failed -gt 0 ]] && warn "$failed extension(s) could not be installed — they will be retried on the next apply"
exit 0
