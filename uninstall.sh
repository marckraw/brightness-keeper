#!/usr/bin/env zsh
set -euo pipefail

INSTALL_ROOT="${BRIGHTNESS_KEEPER_HOME:-$HOME/.local/share/brightness-keeper}"
BIN_DIR="${BRIGHTNESS_KEEPER_BIN_DIR:-$HOME/.local/bin}"
LABEL="com.brightness-keeper"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [[ -z "$INSTALL_ROOT" || "$INSTALL_ROOT" == "/" || "$INSTALL_ROOT" == "$HOME" ]]; then
  echo "brightness-keeper uninstaller: unsafe install directory: $INSTALL_ROOT" >&2
  exit 1
fi

launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
rm -f "$PLIST"

rm -f "$BIN_DIR/brightness-keeper"
rm -f "$BIN_DIR/brightness-keeper-install-agent"
rm -f "$BIN_DIR/brightness-keeper-uninstall-agent"
rm -rf "$INSTALL_ROOT"

echo "Uninstalled brightness-keeper from $INSTALL_ROOT"
