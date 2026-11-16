#!/usr/bin/env bash
# Install (or refresh) the LaunchAgent that runs the FreshRSS translation worker
# every 30 seconds. Paths come from this machine; re-running is safe.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL=local.freshrss.reader
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
UV="$(command -v uv || true)"
[ -n "$UV" ] || { echo "install-reader: uv not found (brew install uv)" >&2; exit 1; }
OMP_DIR="$(dirname "$(python3 -c 'import json,os,sys; print(os.path.expanduser(json.load(open(sys.argv[1]))["omp_bin"]))' "$DIR/reader-settings.json")")"

mkdir -p "$DIR/reader-data" "$(dirname "$PLIST")"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$UV</string>
    <string>run</string><string>--quiet</string><string>--script</string>
    <string>$DIR/reader.py</string>
  </array>
  <key>WorkingDirectory</key><string>$DIR</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key><string>$HOME</string>
    <key>PATH</key><string>$OMP_DIR:$HOME/.local/bin:/opt/homebrew/bin:/usr/bin:/bin</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>30</integer>
  <key>ProcessType</key><string>Background</string>
  <key>Nice</key><integer>10</integer>
  <key>LowPriorityIO</key><true/>
  <key>StandardOutPath</key><string>$DIR/reader-data/worker.log</string>
  <key>StandardErrorPath</key><string>$DIR/reader-data/worker.log</string>
</dict>
</plist>
PLIST
plutil -lint "$PLIST" >/dev/null
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "install-reader: $LABEL loaded"
