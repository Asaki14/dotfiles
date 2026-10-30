#!/bin/bash
set -euo pipefail
set -E
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DRY_RUN=0
NO_BREW=0
CURRENT_MODULE=installer
STEP=arguments
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)-$$"
RESULTS=()
SELECTED=()
RESOLVED=()
VISITING=()
source "$ROOT/lib/install.sh"
trap 'failed "$?"' ERR
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --list) list_modules; exit 0 ;;
    --all) SELECTED=("${AVAILABLE[@]}") ;;
    --modules) shift; [ "$#" -gt 0 ] || die '--modules requires names'; IFS=, read -r -a SELECTED <<< "$1" ;;
    --dry-run) DRY_RUN=1 ;;
    --no-brew) NO_BREW=1 ;;
    *) die "Unknown option: $1" ;;
  esac
  shift
done
if [ "${#SELECTED[@]}" -eq 0 ]; then select_modules; fi
[ "${#SELECTED[@]}" -gt 0 ] || die 'No modules selected'
for name in "${SELECTED[@]}"; do resolve "$name"; done
if [ "$NO_BREW" -eq 0 ] && ! command -v brew >/dev/null 2>&1; then
  printf '%s\n' 'Install Homebrew first:' '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' >&2
  exit 1
fi
for name in "${RESOLVED[@]}"; do
  CURRENT_MODULE=$name
  load_module "$name"
  STEP=packages
  if [ "$NO_BREW" -eq 0 ]; then
    for package in ${BREW_TAPS[@]+"${BREW_TAPS[@]}"}; do run brew tap "$package"; done
    for package in ${BREW_FORMULAE[@]+"${BREW_FORMULAE[@]}"}; do run brew install --formula "$package"; done
    for package in ${BREW_CASKS[@]+"${BREW_CASKS[@]}"}; do run brew install --cask "$package"; done
  fi
  # Upstream copies configs. Run it before our file-level links, including on re-runs.
  if [ "$name" = omacosy ]; then
    STEP=upstream
    prepare_omacosy_links
    post_install
  fi
  STEP=links
  link_home "$ROOT/modules/$name/home"
  if [ "$name" != omacosy ]; then STEP=post_install; post_install; fi
  RESULTS+=("$name: OK")
done
printf '\nBackup directory: %s\n' "$BACKUP_DIR"
printf '%s\n' "${RESULTS[@]}"
