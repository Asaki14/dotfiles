#!/bin/bash
MODULE_DESC_EN="FreshRSS local reader"
MODULE_DESC_ZH="FreshRSS 本地阅读器"
BREW_TAPS=()
BREW_FORMULAE=("colima" "docker" "docker-compose" "uv")
BREW_CASKS=()
DEPENDS=("omp")
post_install() {
  printf '%s\n' 'Start Colima with colima start, then follow the FreshRSS module README to configure credentials and start the reader.'
}
