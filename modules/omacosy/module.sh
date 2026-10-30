#!/bin/bash
MODULE_DESC_EN="Desktop and theme system"
MODULE_DESC_ZH="桌面与主题系统"
BREW_TAPS=("nikitabobko/tap")
BREW_FORMULAE=("git" "fzf" "eza" "zoxide" "ripgrep" "bat" "lazygit" "btop" "jq" "starship")
BREW_CASKS=("nikitabobko/tap/aerospace" "karabiner-elements" "ghostty" "raycast" "font-jetbrains-mono-nerd-font")
DEPENDS=()
post_install() {
  local target="$HOME/.local/share/omacosy" sha relative source destination
  [ -f "$ROOT/modules/omacosy/UPSTREAM" ] || die 'Missing modules/omacosy/UPSTREAM'
  IFS= read -r sha < "$ROOT/modules/omacosy/UPSTREAM"
  case "$sha" in ''|*[!0-9a-f]*) die 'Invalid upstream commit SHA' ;; esac
  [ "${#sha}" -eq 40 ] || die 'Upstream commit SHA must contain 40 hexadecimal characters'
  # A checkout this installer did not create may hold the user's own fork or edits:
  # move it into the backup directory instead of overwriting it.
  if [ -e "$target" ] && [ ! -f "$target/.git/dotfiles-managed" ]; then
    printf 'Existing omacosy at %s is not managed by this repo; moving it to the backup directory.\n' "$target"
    backup "$target"
  fi
  if [ ! -e "$target" ]; then
    run mkdir -p "$(dirname "$target")"
    run git clone https://github.com/paulsp94/omacosy "$target"
    run touch "$target/.git/dotfiles-managed"
  fi
  run git -C "$target" checkout --force "$sha"
  while IFS= read -r -d '' source; do
    relative=${source#"$ROOT/modules/omacosy/overlay/"}
    [ "$relative" != .deleted ] || continue
    destination="$target/$relative"
    run mkdir -p "$(dirname "$destination")"
    run cp -p "$source" "$destination"
  done < <(find "$ROOT/modules/omacosy/overlay" -type f -print0)
  if [ -f "$ROOT/modules/omacosy/overlay/.deleted" ]; then
    while IFS= read -r relative || [ -n "$relative" ]; do
      [ -n "$relative" ] || continue
      case "$relative" in /*|..|../*|*/../*|*/..) die "Unsafe overlay deletion: $relative" ;; esac
      run rm -rf "$target/$relative"
    done < "$ROOT/modules/omacosy/overlay/.deleted"
  fi
  printf '%s\n' 'omacosy installs launch agents, compiles helpers, changes macOS defaults and may change the wallpaper.'
  if [ "$NO_BREW" -eq 1 ]; then
    # Upstream unconditionally calls brew. A subprocess-only function suppresses
    # those calls without changing upstream files or the caller environment.
    run /bin/bash -c 'brew() { return 0; }; export -f brew; cd "$1"; ./install.sh' bash "$target"
  else
    run /bin/bash -c 'cd "$1"; ./install.sh' bash "$target"
  fi
}
