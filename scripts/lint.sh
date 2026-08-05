#!/usr/bin/env bash
# Lints every shell script in this repo, including the ones inside chezmoi
# templates. Run it locally the same way CI does:
#
#   ./scripts/lint.sh
#
# Needs shellcheck (packages/headless.txt) and chezmoi.
#
# The .tmpl files are not valid bash on disk — they are Go templates that
# render to bash — so they have to go through `chezmoi execute-template` first.
# That is the whole reason this is a script rather than three lines of YAML: CI
# and a local run must render them identically or the lint is theatre.
#
# shfmt is deliberately not run. This repo formats for readability in ways shfmt
# rewrites on sight — aligned `case` arms, short `cmd; cmd ;;` bodies, `<<'EOF'`
# without a space. That style is consistent across every script here, so a
# formatter would mean either one enormous reflow commit or a check that can
# never pass. shellcheck is the tool that finds actual bugs; that is the one
# worth gating on.
set -euo pipefail

REPO_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$REPO_DIR/dots"

red() { printf '\033[1;31m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[1;32m%s\033[0m\n' "$*"; }
info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

for cmd in shellcheck chezmoi; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    red "$cmd is not installed — see packages/headless.txt"
    exit 1
  fi
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/render"

status=0

# ── Plain scripts ──────────────────────────────────────────────
mapfile -t PLAIN < <(cd "$REPO_DIR" && printf '%s\n' install.sh scripts/lint.sh dots/run_*.sh)

info "shellcheck: ${#PLAIN[@]} plain scripts"
( cd "$REPO_DIR" && shellcheck "${PLAIN[@]}" ) || status=1

# ── Templates ──────────────────────────────────────────────────
# Rendered in both modes with a config written by hand rather than
# `--init --promptBool`: .chezmoi.toml.tmpl uses promptBoolOnce, so --promptBool
# is ignored once a machine has a persisted answer and CI would silently lint
# whatever the developer's own machine happens to be set to.
for mode in true false; do
  cat > "$tmp/config-$mode.toml" <<EOF
sourceDir = "$SOURCE_DIR"
[data]
  isDesktop = $mode
EOF
done

# The config is handed over with --config rather than by pointing $HOME at a
# temp directory. chezmoi resolves its config under $XDG_CONFIG_HOME when that
# is set and only falls back to $HOME/.config — GitHub's runners set it, most
# workstations do not, so the $HOME trick worked locally and rendered with no
# isDesktop at all in CI ("map has no entry for key"). --config outranks both.
render() { # $1 = template path, $2 = true|false
  chezmoi execute-template --config "$tmp/config-$2.toml" --source "$SOURCE_DIR" < "$1"
}

mapfile -t TEMPLATES < <(cd "$REPO_DIR" && printf '%s\n' dots/run_*.tmpl)

# Both modes must render and parse. Only the desktop render is shellcheck'd:
# on headless the .isDesktop gate emits an early `exit 0`, so every line after
# it is unreachable and SC2317/SC2329 fire on the whole file. Desktop covers
# all the same code with none of the noise.
info "chezmoi execute-template + bash -n: ${#TEMPLATES[@]} templates x 2 modes"
for mode in true false; do
  for t in "${TEMPLATES[@]}"; do
    name="$(basename "$t" .tmpl)"
    out="$tmp/render/$mode-$name"
    if ! render "$REPO_DIR/$t" "$mode" > "$out" 2> "$tmp/err"; then
      red "render failed (isDesktop=$mode): $t"
      cat "$tmp/err" >&2
      # Drop the empty file the redirection just created, so the count below
      # reflects what actually rendered rather than what was attempted.
      rm -f "$out"
      status=1
      continue
    fi
    if ! bash -n "$out" 2> "$tmp/err"; then
      red "rendered script does not parse (isDesktop=$mode): $t"
      cat "$tmp/err" >&2
      status=1
    fi
  done
done

# Count what actually rendered rather than globbing blind. When every render
# failed, the glob matched nothing and shellcheck was handed a literal `true-*`
# — a confusing second error on top of the real one, and one bad `|| true` away
# from a lint that passes because it checked nothing at all.
mapfile -t RENDERED < <(find "$tmp/render" -maxdepth 1 -name 'true-*' -type f | sort)
if [[ ${#RENDERED[@]} -ne ${#TEMPLATES[@]} ]]; then
  red "only ${#RENDERED[@]} of ${#TEMPLATES[@]} templates rendered — skipping shellcheck on them"
  status=1
fi
if [[ ${#RENDERED[@]} -gt 0 ]]; then
  info "shellcheck: ${#RENDERED[@]} rendered templates (isDesktop=true)"
  shellcheck -s bash "${RENDERED[@]}" || status=1
fi

# ── Repo hygiene ───────────────────────────────────────────────
# Every run_ script chezmoi executes should be executable in the source tree
# too. chezmoi writes them to a temp file with mode 0700 and runs that, so this
# is cosmetic — but a non-executable script here is a sign someone created it
# with a redirect and forgot, and it is one `git update-index` to fix.
info "mode check: run_ scripts"
while IFS= read -r f; do
  if [[ ! -x "$REPO_DIR/$f" ]]; then
    red "not executable: $f  (git update-index --chmod=+x $f)"
    status=1
  fi
done < <(cd "$REPO_DIR" && git ls-files 'dots/run_*')

if [[ $status -eq 0 ]]; then
  green "lint: clean"
else
  red "lint: failures above"
fi
exit "$status"
