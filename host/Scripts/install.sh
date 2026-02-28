#!/usr/bin/env bash
# install.sh — Build and install the TabX native host binary and Chrome manifest.
#
# Usage:
#   ./Scripts/install.sh [--extension-id <ID>] [--prefix <dir>]
#
# Options:
#   --extension-id <ID>   Chrome extension ID to allow in the manifest (required)
#   --prefix <dir>        Installation prefix for the binary (default: /usr/local/bin)
#
# What this script does:
#   1. Builds the tabx-host binary in release mode.
#   2. Copies it to <prefix>/tabx-host.
#   3. Writes the native messaging host manifest to the correct Chrome location.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

EXTENSION_ID=""
INSTALL_PREFIX="/usr/local/bin"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --extension-id)
            EXTENSION_ID="$2"
            shift 2
            ;;
        --prefix)
            INSTALL_PREFIX="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--extension-id <ID>] [--prefix <dir>]" >&2
            exit 1
            ;;
    esac
done

if [[ -z "$EXTENSION_ID" ]]; then
    echo "Error: --extension-id is required." >&2
    echo "Find your extension ID in chrome://extensions" >&2
    exit 1
fi

BINARY_PATH="${INSTALL_PREFIX}/tabx-host"
MANIFEST_DIR="${HOME}/Library/Application Support/Google/Chrome/NativeMessagingHosts"
MANIFEST_PATH="${MANIFEST_DIR}/com.tabx.host.json"

echo "==> Building tabx-host (release)..."
cd "${HOST_DIR}"
swift build -c release

BUILD_BINARY=".build/release/tabx-host"
if [[ ! -f "$BUILD_BINARY" ]]; then
    echo "Error: build did not produce ${BUILD_BINARY}" >&2
    exit 1
fi

echo "==> Installing binary to ${BINARY_PATH}..."
mkdir -p "${INSTALL_PREFIX}"
cp "${BUILD_BINARY}" "${BINARY_PATH}"
chmod +x "${BINARY_PATH}"

echo "==> Writing native messaging manifest to ${MANIFEST_PATH}..."
mkdir -p "${MANIFEST_DIR}"
cat > "${MANIFEST_PATH}" <<EOF
{
  "name": "com.tabx.host",
  "description": "TabX native host — provides git context and tab scoring for the TabX Chrome extension",
  "path": "${BINARY_PATH}",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://${EXTENSION_ID}/"
  ]
}
EOF

echo ""
echo "Installation complete."
echo "  Binary:   ${BINARY_PATH}"
echo "  Manifest: ${MANIFEST_PATH}"
echo ""
echo "Restart Chrome to pick up the new native host."
