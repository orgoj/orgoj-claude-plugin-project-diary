#!/bin/bash
set -euo pipefail

# Only run in Claude Code on the web
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

ZIG_VERSION="0.13.0"
ZIG_INSTALL_DIR="$HOME/.local/zig"
ZIG_BINARY="$ZIG_INSTALL_DIR/zig"

# Check if Zig is already installed
if [ -f "$ZIG_BINARY" ]; then
  INSTALLED_VERSION=$("$ZIG_BINARY" version 2>/dev/null || echo "unknown")
  if [ "$INSTALLED_VERSION" = "$ZIG_VERSION" ]; then
    echo "Zig $ZIG_VERSION already installed"
    echo "export PATH=\"$ZIG_INSTALL_DIR:\$PATH\"" >> "$CLAUDE_ENV_FILE"
    exit 0
  fi
fi

echo "Installing Zig $ZIG_VERSION..."

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
  ZIG_ARCH="x86_64"
elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
  ZIG_ARCH="aarch64"
else
  echo "Unsupported architecture: $ARCH"
  exit 1
fi

# Download and install Zig
ZIG_URL="https://ziglang.org/download/$ZIG_VERSION/zig-linux-$ZIG_ARCH-$ZIG_VERSION.tar.xz"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "Downloading Zig from $ZIG_URL..."
curl -fsSL "$ZIG_URL" -o "$TEMP_DIR/zig.tar.xz"

echo "Extracting Zig..."
tar -xf "$TEMP_DIR/zig.tar.xz" -C "$TEMP_DIR"

echo "Installing to $ZIG_INSTALL_DIR..."
rm -rf "$ZIG_INSTALL_DIR"
mv "$TEMP_DIR/zig-linux-$ZIG_ARCH-$ZIG_VERSION" "$ZIG_INSTALL_DIR"

# Verify installation
if [ -f "$ZIG_BINARY" ]; then
  INSTALLED_VERSION=$("$ZIG_BINARY" version)
  echo "✓ Zig $INSTALLED_VERSION installed successfully"
else
  echo "✗ Zig installation failed"
  exit 1
fi

# Add to PATH for this session
echo "export PATH=\"$ZIG_INSTALL_DIR:\$PATH\"" >> "$CLAUDE_ENV_FILE"

echo "Zig is ready to use!"
