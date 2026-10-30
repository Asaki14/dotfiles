#!/bin/bash
MODULE_DESC_EN="File manager and previews"
MODULE_DESC_ZH="文件管理与预览"
BREW_TAPS=()
BREW_FORMULAE=("yazi" "ffmpeg" "sevenzip" "poppler" "fd" "ripgrep" "fzf" "zoxide" "imagemagick" "resvg")
BREW_CASKS=()
DEPENDS=()
post_install() {
  if [ "$DRY_RUN" -eq 0 ] && ! command -v ya >/dev/null 2>&1; then die 'Install yazi to provide ya'; fi
  local packages= plugin
  if [ "$DRY_RUN" -eq 0 ]; then packages=$(ya pkg list); fi
  for plugin in yazi-rs/plugins:smart-enter KKV9/compress; do
    case "$packages" in *"$plugin"*) ;; *) run ya pkg add "$plugin" ;; esac
  done
  run ya pkg install
}
