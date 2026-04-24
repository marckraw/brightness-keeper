#!/usr/bin/env zsh
set -euo pipefail

REPO_URL="${BRIGHTNESS_KEEPER_REPO_URL:-https://github.com/marckraw/brightness-keeper}"
REF="${BRIGHTNESS_KEEPER_REF:-master}"
INSTALL_ROOT="${BRIGHTNESS_KEEPER_HOME:-$HOME/.local/share/brightness-keeper}"
BIN_DIR="${BRIGHTNESS_KEEPER_BIN_DIR:-$HOME/.local/bin}"

if [[ -z "$INSTALL_ROOT" || "$INSTALL_ROOT" == "/" || "$INSTALL_ROOT" == "$HOME" ]]; then
  echo "brightness-keeper installer: unsafe install directory: $INSTALL_ROOT" >&2
  exit 1
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "brightness-keeper installer: missing required command: $1" >&2
    exit 1
  fi
}

require_command curl
require_command tar

TMP_DIR="$(mktemp -d)"
ARCHIVE="$TMP_DIR/brightness-keeper.tar.gz"
EXTRACT_DIR="$TMP_DIR/src"
STAGED_ROOT="$TMP_DIR/install"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "Downloading brightness-keeper from $REPO_URL ($REF)..."
curl -fsSL "$REPO_URL/archive/$REF.tar.gz" -o "$ARCHIVE"

mkdir -p "$EXTRACT_DIR" "$STAGED_ROOT" "$BIN_DIR"
tar -xzf "$ARCHIVE" -C "$EXTRACT_DIR" --strip-components 1

mkdir -p "$STAGED_ROOT"
cp -R "$EXTRACT_DIR/tools" "$STAGED_ROOT/tools"
cp "$EXTRACT_DIR/README.md" "$STAGED_ROOT/README.md"
chmod +x "$STAGED_ROOT/tools/brightness-keeper"
chmod +x "$STAGED_ROOT/tools/install-brightness-keeper.sh"
chmod +x "$STAGED_ROOT/tools/uninstall-brightness-keeper.sh"
chmod +x "$STAGED_ROOT/tools/Brightness 100.command"

rm -rf "$INSTALL_ROOT"
mkdir -p "${INSTALL_ROOT:h}"
mv "$STAGED_ROOT" "$INSTALL_ROOT"

ln -sfn "$INSTALL_ROOT/tools/brightness-keeper" "$BIN_DIR/brightness-keeper"
ln -sfn "$INSTALL_ROOT/tools/install-brightness-keeper.sh" "$BIN_DIR/brightness-keeper-install-agent"
ln -sfn "$INSTALL_ROOT/tools/uninstall-brightness-keeper.sh" "$BIN_DIR/brightness-keeper-uninstall-agent"

if ! command -v m1ddc >/dev/null 2>&1; then
  echo ""
  echo "m1ddc was not found. Install it before controlling external DDC/CI displays:"
  echo "  brew install m1ddc"
fi

if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  echo ""
  echo "$BIN_DIR is not in PATH. Add it to your shell profile or run the full path:"
  echo "  $BIN_DIR/brightness-keeper --help"
fi

echo ""
echo "Installed brightness-keeper to $INSTALL_ROOT"
echo "CLI: $BIN_DIR/brightness-keeper"
echo "LaunchAgent installer: $BIN_DIR/brightness-keeper-install-agent"
echo "LaunchAgent uninstaller: $BIN_DIR/brightness-keeper-uninstall-agent"
