#!/bin/bash
MODULE_DESC_EN="Tern terminal configuration"
MODULE_DESC_ZH="Tern 终端配置"
BREW_TAPS=()
BREW_FORMULAE=()
BREW_CASKS=()
DEPENDS=()
post_install() {
  if ! [ -d /Applications/Tern.app ] && ! [ -d "$HOME/Applications/Tern.app" ]; then
    printf '%s\n' 'Tern is in closed beta. Install from https://stencil.so/tern (not the unrelated tern.sh CLI).'
  fi
}
