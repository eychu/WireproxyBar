#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

ARCH="${ARCH:-arm64}"
OUTPUT_DIR="${ROOT_DIR}/build"
APP_BUNDLE="${OUTPUT_DIR}/WireproxyBar.app"

echo "==> Building WireproxyBar ($ARCH)..."

# 1. Prepare build output directory
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 2. Ensure latest wireproxy binary is present
WIREPROXY_BIN="${ROOT_DIR}/wireproxy"
if [ ! -f "$WIREPROXY_BIN" ]; then
    echo "==> Fetching latest wireproxy for darwin_${ARCH}..."
    TMP_DL=$(mktemp -d)
    curl -sSL "https://github.com/windtf/wireproxy/releases/latest/download/wireproxy_darwin_${ARCH}.tar.gz" -o "$TMP_DL/wireproxy.tar.gz"
    tar -xzf "$TMP_DL/wireproxy.tar.gz" -C "$TMP_DL"
    mv "$TMP_DL/wireproxy" "$WIREPROXY_BIN"
    chmod +x "$WIREPROXY_BIN"
    rm -rf "$TMP_DL"
fi

# 3. Compile Swift binary
echo "==> Compiling main.swift..."
CACHE_DIR=$(mktemp -d)
swiftc -O -target "${ARCH}-apple-macos12.0" -module-cache-path "$CACHE_DIR" \
    "$ROOT_DIR/main.swift" \
    -o "$APP_BUNDLE/Contents/MacOS/WireproxyBar"
rm -rf "$CACHE_DIR"

# 4. Copy resources and auxiliary executable
echo "==> Packaging bundle..."
cp "$WIREPROXY_BIN" "$APP_BUNDLE/Contents/MacOS/wireproxy"
chmod +x "$APP_BUNDLE/Contents/MacOS/wireproxy"

cp "$ROOT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/Resources/"*.svg "$APP_BUNDLE/Contents/Resources/"

echo "==> Successfully built: $APP_BUNDLE"

# 5. Optional code signing if SIGN_IDENTITY is set
if [ -n "${SIGN_IDENTITY:-}" ]; then
    echo "==> Signing bundle with identity: $SIGN_IDENTITY"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE/Contents/MacOS/wireproxy"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
    echo "==> Code signing verified."
fi
