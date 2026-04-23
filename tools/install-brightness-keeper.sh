#!/usr/bin/env zsh
set -euo pipefail

TARGET_LEVEL="${1:-100}"
INTERVAL_SECONDS="${2:-10}"
SCRIPT_DIR="${0:A:h}"
LABEL="com.convergence.brightness-keeper"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs"

mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>

  <key>ProgramArguments</key>
  <array>
    <string>$SCRIPT_DIR/brightness-keeper</string>
    <string>--level</string>
    <string>$TARGET_LEVEL</string>
    <string>--interval</string>
    <string>$INTERVAL_SECONDS</string>
    <string>--quiet</string>
  </array>

  <key>RunAtLoad</key>
  <true/>

  <key>KeepAlive</key>
  <true/>

  <key>StandardOutPath</key>
  <string>$LOG_DIR/$LABEL.out.log</string>

  <key>StandardErrorPath</key>
  <string>$LOG_DIR/$LABEL.err.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl enable "gui/$(id -u)/$LABEL"
launchctl kickstart -k "gui/$(id -u)/$LABEL"

echo "Installed $LABEL at $PLIST"
echo "Target brightness: $TARGET_LEVEL; interval: ${INTERVAL_SECONDS}s"
