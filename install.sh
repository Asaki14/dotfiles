#!/usr/bin/env bash
# install.sh — set this Mac up from the repo:
#   1. link each config directory into ~/.config (skipped when the repo IS ~/.config)
#   2. install the Homebrew packages in Brewfile
#   3. write this machine's local values (headphones, location, fund wallet), never committed
#   4. link ~/.local/share/omacosy to omacosy/src and run the omacosy desktop installer
# --modules limits all of this to the named config directories; steps 3 and 4
# belong to omacosy. Re-running is safe: finished steps are skipped, replaced
# files go to ~/.dotfiles-backup/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CONFIG="$HOME/.config"
MODULES=(beets btop fastfetch fish freshrss gh git karabiner linearmouse mdt mpd nvim omacosy rmpc tern tinycast yazi)
BACKUP="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
DRY=0 BREW=1 DESKTOP=1 NETWORK=1
SELECTED=("${MODULES[@]}")

usage() {
  cat <<USAGE
Usage: ./install.sh [options]
  --modules a,b  only these config directories, their packages and setup:
                 ${MODULES[*]}
  --dry-run      print every action, change nothing
  --no-brew      skip Homebrew packages
  --no-desktop   skip the omacosy desktop (window manager, bar, themes)
  --no-network   do not look up the location from the IP address
  -h, --help     show this help
USAGE
}

select_modules() {
  local name known
  SELECTED=()
  for name in ${1//,/ }; do
    known=0
    for module in "${MODULES[@]}"; do
      if [ "$module" = "$name" ]; then known=1; fi
    done
    if [ "$known" -eq 0 ]; then
      echo "install.sh: unknown module $name" >&2; usage >&2; exit 2
    fi
    SELECTED+=("$name")
  done
  if [ ${#SELECTED[@]} -eq 0 ]; then echo "install.sh: --modules needs a name" >&2; exit 2; fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --modules) [ $# -ge 2 ] || { usage >&2; exit 2; }; select_modules "$2"; shift ;;
    --modules=*) select_modules "${1#*=}" ;;
    --dry-run) DRY=1 ;;
    --no-brew) BREW=0 ;;
    --no-desktop) DESKTOP=0 ;;
    --no-network) NETWORK=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "install.sh: unknown option $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

selected() {
  local module
  for module in "${SELECTED[@]}"; do
    if [ "$module" = "$1" ]; then return 0; fi
  done
  return 1
}

say() { printf '\033[1m==> %s\033[0m\n' "$*"; }
run() {
  printf '  + %s\n' "$*"
  if [ "$DRY" -eq 0 ]; then "$@"; fi
}
write() { # write <path> <content>: create a local file once, never overwrite
  local path=$1 content=$2
  if [ -e "$path" ]; then printf '  = %s (kept)\n' "$path"; return; fi
  printf '  + write %s\n' "$path"
  if [ "$DRY" -eq 0 ]; then printf '%s\n' "$content" > "$path"; fi
}
backup() {
  run mkdir -p "$BACKUP"
  run mv "$1" "$BACKUP/"
}
link() { # link <source> <destination>, moving anything else at the destination aside
  local src=$1 dst=$2
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then return; fi
  if [ -e "$dst" ] || [ -L "$dst" ]; then backup "$dst"; fi
  run mkdir -p "$(dirname "$dst")"
  run ln -s "$src" "$dst"
}

link_configs() {
  say "Config directories"
  if [ -d "$CONFIG" ] && [ "$ROOT" = "$(cd "$CONFIG" && pwd -P)" ]; then
    echo "  repo is ~/.config, nothing to link"
    return
  fi
  for module in "${SELECTED[@]}"; do
    link "$ROOT/$module" "$CONFIG/$module"
  done
}

# Brewfile lines whose trailing comment names a selected config directory
brewfile_for_selection() {
  awk -v want=" ${SELECTED[*]} " '
    /^(brew|cask) / {
      n = split(substr($0, index($0, "#") + 1), tags, " ")
      for (i = 1; i <= n; i++) if (index(want, " " tags[i] " ")) { print; next }
    }' "$ROOT/Brewfile"
}

packages() {
  say "Homebrew packages"
  if ! command -v brew >/dev/null 2>&1; then
    echo 'Install Homebrew first: /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' >&2
    exit 1
  fi
  if [ ${#SELECTED[@]} -eq ${#MODULES[@]} ]; then
    run brew bundle --file "$ROOT/Brewfile"
    return
  fi
  local list; list="$(brewfile_for_selection)"
  if [ -z "$list" ]; then echo "  none needed"; return; fi
  printf '%s\n' "$list" | sed 's/^/    /'
  if [ "$DRY" -eq 0 ]; then printf '%s\n' "$list" | brew bundle --file=-; fi
}

# The first Bluetooth audio device whose name says AirPods, else any paired
# headphones; the bar shows its battery.
detect_headphones() {
  system_profiler SPBluetoothDataType -json 2>/dev/null | python3 -c '
import json, sys
try:
    root = json.load(sys.stdin)["SPBluetoothDataType"]
except Exception:
    sys.exit()
devices = []
for section in root:
    for key in ("device_connected", "device_not_connected"):
        for entry in section.get(key, []):
            for name, info in entry.items():
                devices.append((name, str(info.get("device_minorType", ""))))
for test in (lambda n, t: "airpods" in n.lower(), lambda n, t: t in ("Headphones", "Headset")):
    for name, kind in devices:
        if test(name, kind):
            print(name)
            sys.exit()
'
}

detect_location() {
  curl -fsS --max-time 8 "http://ip-api.com/json/?lang=zh-CN&fields=status,city,lat,lon" 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit()
if d.get("status") == "success":
    print(json.dumps({"name": d["city"], "latitude": d["lat"], "longitude": d["lon"]}, ensure_ascii=False))
'
}

localize() {
  say "This machine's values (gitignored)"
  local bar="$ROOT/omacosy/bar-items.local.conf"
  if [ ! -e "$bar" ]; then
    local headphones; headphones="$(detect_headphones || true)"
    if [ -n "$headphones" ]; then
      write "$bar" "# This machine only (gitignored). Directives here override bar-items.conf.
airpods-name $headphones"
    else
      echo "  no Bluetooth headphones paired; the bar uses airpods-name from bar-items.conf"
    fi
  else
    printf '  = %s (kept)\n' "$bar"
  fi

  local location="$ROOT/omacosy/scripts/location.local.json"
  if [ ! -e "$location" ]; then
    local found=""
    if [ "$NETWORK" -eq 1 ]; then
      echo "  looking up the city from this IP address (ip-api.com) for the weather; --no-network skips it"
      found="$(detect_location || true)"
    fi
    if [ -n "$found" ]; then
      write "$location" "$found"
    else
      echo "  location unknown; weather uses the example city in weather_lib.py until you write $location"
    fi
  else
    printf '  = %s (kept)\n' "$location"
  fi

  local wallet="$ROOT/omacosy/scripts/fission_fund_wallet.json"
  if [ ! -e "$wallet" ]; then
    run cp "$ROOT/omacosy/scripts/fission_fund_wallet.example.json" "$wallet"
    echo "  edit $wallet with your fund codes and shares, or drop fission-estimator from bar-items.conf"
  fi
}

tern_plugin() {
  say "Tern plugin"
  if command -v tern >/dev/null 2>&1; then
    run tern plugin link "$ROOT/tern/plugins/input-source-policy"
  else
    echo "  tern not found; after installing Tern run: tern plugin link $ROOT/tern/plugins/input-source-policy"
  fi
}

desktop() {
  say "omacosy desktop"
  link "$ROOT/omacosy/src" "$HOME/.local/share/omacosy"
  echo "  The omacosy installer changes macOS defaults, installs LaunchAgents, compiles helpers"
  echo "  and sets the wallpaper. File backups do not undo those changes."
  run "$HOME/.local/share/omacosy/install.sh"
}

link_configs
if [ "$BREW" -eq 1 ]; then packages; fi
if selected omacosy; then localize; fi
if selected tern; then tern_plugin; fi
if [ "$DESKTOP" -eq 1 ] && selected omacosy; then desktop; fi

say "Done"
if [ -d "$BACKUP" ]; then echo "  replaced files are in $BACKUP"; fi
cat <<'NEXT'
  Optional, by hand:
    sh ~/.config/mpd/nowplaying/install.sh       # MPD on macOS Now Playing and the media keys
    ~/.config/mpd/playlist-sync                   # link playlists for MPD, fetch missing songs
    see ~/.config/freshrss/README.md              # FreshRSS and its translation worker
    see ~/.config/tinycast/scripts/README.md      # import the system commands into Tinycast
NEXT
