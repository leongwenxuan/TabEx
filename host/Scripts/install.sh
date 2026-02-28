#!/usr/bin/env bash
# install.sh — Build and install the TabX native host
# Usage: ./Scripts/install.sh [--extension-id EXTENSION_ID]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_DIR="$(dirname "$SCRIPT_DIR")"
BINARY_NAME="tabx-host"
INSTALL_DIR="/usr/local/bin"
MANIFEST_NAME="com.tabx.host.json"
NATIVE_MSG_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"

EXTENSION_ID=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --extension-id)
      EXTENSION_ID="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

echo "==> Building tabx-host (release)…"
cd "$HOST_DIR"
swift build -c release

BUILT_BINARY="$(swift build -c release --show-bin-path 2>/dev/null)/$BINARY_NAME"

echo "==> Installing binary to $INSTALL_DIR/$BINARY_NAME…"
sudo cp "$BUILT_BINARY" "$INSTALL_DIR/$BINARY_NAME"
sudo chmod +x "$INSTALL_DIR/$BINARY_NAME"

echo "==> Installing native messaging manifest…"
mkdir -p "$NATIVE_MSG_DIR"

MANIFEST_SRC="$HOST_DIR/Resources/$MANIFEST_NAME"
MANIFEST_DST="$NATIVE_MSG_DIR/$MANIFEST_NAME"

# Patch the binary path and optionally the extension ID in the manifest.
BINARY_PATH="$INSTALL_DIR/$BINARY_NAME"

if [[ -n "$EXTENSION_ID" ]]; then
  sed \
    -e "s|/usr/local/bin/tabx-host|$BINARY_PATH|g" \
    -e "s|REPLACE_WITH_EXTENSION_ID|$EXTENSION_ID|g" \
    "$MANIFEST_SRC" > "$MANIFEST_DST"
else
  sed \
    -e "s|/usr/local/bin/tabx-host|$BINARY_PATH|g" \
    "$MANIFEST_SRC" > "$MANIFEST_DST"
  echo "  WARNING: Extension ID not provided. Edit $MANIFEST_DST to set allowed_origins."
fi

chmod 644 "$MANIFEST_DST"

echo ""
echo "Installation complete."
echo "  Binary:   $BINARY_PATH"
echo "  Manifest: $MANIFEST_DST"
echo ""
echo "Run 'tabx-host --help' to verify the installation."
