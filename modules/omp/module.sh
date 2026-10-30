#!/bin/bash
MODULE_DESC_EN="oh-my-pi coding agent"
MODULE_DESC_ZH="oh-my-pi 编程助手"
BREW_TAPS=()
BREW_FORMULAE=()
BREW_CASKS=()
DEPENDS=()
post_install() {
  if ! command -v omp >/dev/null 2>&1; then
    printf '%s\n' 'Install omp: https://omp.sh / https://github.com/can1357/oh-my-pi' 'Official command: curl -fsSL https://omp.sh/install | sh'
  fi
}
