AVAILABLE=()
for module_file in "$ROOT"/modules/*/module.sh; do
  [ -f "$module_file" ] || continue
  module_name=${module_file%/module.sh}
  AVAILABLE+=("${module_name##*/}")
done
usage() {
  cat <<'USAGE'
Usage: ./install.sh [--all | --modules a,b] [--dry-run] [--no-brew]
  No selection: interactive multi-select (fzf or numbered menu).
  --all          Install every module
  --modules a,b  Install named modules and their dependencies
  --list         List modules
  --dry-run      Print actions without writing files or installing anything
  --no-brew      Skip all Homebrew actions (including upstream omacosy)
  --help         Show this help
Existing files are moved to ~/.dotfiles-backup/<timestamp>/ before linking.
USAGE
}
die() { printf 'Error [%s / %s]: %s\n' "$CURRENT_MODULE" "$STEP" "$*" >&2; exit 1; }
failed() {
  local status=$1
  trap - ERR
  printf 'Failed [%s / %s], exit %s\nBackup directory: %s\n' "$CURRENT_MODULE" "$STEP" "$status" "$BACKUP_DIR" >&2
  if [ "${#RESULTS[@]}" -gt 0 ]; then printf '%s\n' "${RESULTS[@]}" >&2; fi
  exit "$status"
}
run() {
  printf '[%s / %s]' "$CURRENT_MODULE" "$STEP"
  printf ' %q' "$@"
  printf '\n'
  if [ "$DRY_RUN" -eq 0 ]; then "$@"; fi
}
load_module() {
  MODULE_DESC_EN= MODULE_DESC_ZH=
  BREW_TAPS=(); BREW_FORMULAE=(); BREW_CASKS=(); DEPENDS=()
  post_install() { :; }
  source "$ROOT/modules/$1/module.sh"
}
list_modules() {
  local item description
  for item in "${AVAILABLE[@]}"; do
    load_module "$item"
    case "${LANG:-en}" in zh*) description=$MODULE_DESC_ZH ;; *) description=$MODULE_DESC_EN ;; esac
    printf '%-14s %s\n' "$item" "$description"
  done
}
select_modules() {
  local choices line token number
  if command -v fzf >/dev/null 2>&1; then
    choices=$(list_modules | fzf --multi --prompt='Modules > ') || exit 0
    while IFS= read -r line; do [ -z "$line" ] || SELECTED+=("${line%% *}"); done <<< "$choices"
  else
    [ -t 0 ] || die 'Use --all or --modules with non-interactive input'
    number=1
    while IFS= read -r line; do printf '%2s) %s\n' "$number" "$line"; number=$((number + 1)); done < <(list_modules)
    printf 'Select numbers separated by spaces (or all): '
    IFS= read -r choices
    if [ "$choices" = all ]; then SELECTED=("${AVAILABLE[@]}"); return; fi
    for token in $choices; do
      case "$token" in ''|*[!0-9]*) die "Invalid selection: $token" ;; esac
      number=$((10#$token))
      [ "$number" -gt 0 ] && [ "$number" -le "${#AVAILABLE[@]}" ] || die "Invalid selection: $token"
      SELECTED+=("${AVAILABLE[$((number - 1))]}")
    done
  fi
}
resolve() {
  local name=$1 item
  case "$name" in ''|*[!a-zA-Z0-9_-]*) die "Invalid module name: $name" ;; esac
  [ -f "$ROOT/modules/$name/module.sh" ] || die "Unknown module: $name"
  for item in ${RESOLVED[@]+"${RESOLVED[@]}"}; do [ "$item" != "$name" ] || return 0; done
  for item in ${VISITING[@]+"${VISITING[@]}"}; do [ "$item" != "$name" ] || die "Dependency cycle: $name"; done
  VISITING+=("$name")
  load_module "$name"
  local dependencies=( ${DEPENDS[@]+"${DEPENDS[@]}"} )
  for item in ${dependencies[@]+"${dependencies[@]}"}; do resolve "$item"; done
  unset 'VISITING[${#VISITING[@]}-1]'
  RESOLVED+=("$name")
}
backup() {
  local destination=$1 relative=${1#"$HOME"/} saved counter=0
  saved="$BACKUP_DIR/$relative"
  while [ -e "$saved" ] || [ -L "$saved" ]; do counter=$((counter + 1)); saved="$BACKUP_DIR/$relative.$counter"; done
  run mkdir -p "$(dirname "$saved")"
  run mv "$destination" "$saved"
}
ensure_parent() {
  local path=$1
  [ "$path" = "$HOME" ] && return 0
  ensure_parent "$(dirname "$path")"
  # Do not follow an existing directory symlink into another dotfiles checkout.
  if [ -L "$path" ] || { [ -e "$path" ] && [ ! -d "$path" ]; }; then backup "$path"; fi
  if [ ! -d "$path" ] || [ -L "$path" ]; then run mkdir -p "$path"; fi
}
link_home() {
  local tree=$1 source destination relative
  [ -d "$tree" ] || return 0
  while IFS= read -r -d '' source; do
    relative=${source#"$tree"/}
    destination="$HOME/$relative"
    if [ -L "$destination" ] && [ "$(readlink "$destination")" = "$source" ]; then continue; fi
    ensure_parent "$(dirname "$destination")"
    if [ -e "$destination" ] || [ -L "$destination" ]; then backup "$destination"; fi
    run ln -s "$source" "$destination"
  done < <(find "$tree" \( -type f -o -type l \) -print0)
}
prepare_omacosy_links() {
  local tree="$ROOT/modules/omacosy/home" source destination
  [ -d "$tree" ] || return 0
  while IFS= read -r -d '' source; do
    destination="$HOME/${source#"$tree"/}"
    # Upstream cp must never write through our symlinks into the public repo.
    if [ -L "$destination" ] && [ "$(readlink "$destination")" = "$source" ]; then
      run rm "$destination"
    elif [ -e "$destination" ] || [ -L "$destination" ]; then
      backup "$destination"
    fi
  done < <(find "$tree" \( -type f -o -type l \) -print0)
}
