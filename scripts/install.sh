#!/bin/bash
# Installation script for mopc
# Creates symlink in ~/.local/bin/ so mopc is available system-wide

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "📦 Installing mopc..."
echo ""

# Check if binaries exist
if [ ! -d "$PROJECT_ROOT/zig-out/bin" ]; then
    echo "❌ No binaries found. Please build first:"
    echo "   ./scripts/build-all-platforms.sh"
    exit 1
fi

# Detect platform
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$OS" in
    linux*) OS="linux" ;;
    darwin*) OS="darwin" ;;
    mingw*|msys*|cygwin*) OS="windows" ;;
    *) echo "❌ Unsupported OS: $OS"; exit 1 ;;
esac

ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64) ARCH="x64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
esac

PLATFORM="${OS}-${ARCH}"
EXT=""
if [ "$OS" = "windows" ]; then
    EXT=".exe"
fi

# Check if platform binary exists (marketplace)
PLATFORM_BIN="$PROJECT_ROOT/zig-out/bin/$PLATFORM/mopc$EXT"
DEV_BIN="$PROJECT_ROOT/zig-out/bin/mopc$EXT"

if [ ! -f "$PLATFORM_BIN" ] && [ ! -f "$DEV_BIN" ]; then
    echo "❌ No binary found for $PLATFORM"
    echo "   Run: ./scripts/build-all-platforms.sh"
    exit 1
fi

if [ -f "$DEV_BIN" ]; then
    echo "ℹ️  Using dev build: zig-out/bin/mopc$EXT"
    echo "   (For production, run: ./scripts/build-all-platforms.sh)"
    echo ""
fi

# Create ~/.local/bin if it doesn't exist
LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"

# Create symlink
SOURCE="$PROJECT_ROOT/bin/mopc"
TARGET="$LOCAL_BIN/mopc"

# Remove old symlink if exists
if [ -e "$TARGET" ] || [ -L "$TARGET" ]; then
    rm -f "$TARGET"
fi

ln -s "$SOURCE" "$TARGET"
chmod +x "$SOURCE"

echo "✅ Installed: $TARGET -> $SOURCE"
echo ""

# Check if ~/.local/bin is in PATH
if [[ ":$PATH:" != *":$LOCAL_BIN:"* ]]; then
    echo "⚠️  WARNING: $LOCAL_BIN is not in your PATH"
    echo ""
    echo "Add this to your ~/.bashrc or ~/.zshrc:"
    echo '  export PATH="$HOME/.local/bin:$PATH"'
    echo ""
    echo "Then reload your shell:"
    echo "  source ~/.bashrc  # or ~/.zshrc"
    echo ""
else
    echo "🎉 Installation complete!"
    echo ""
    echo "Try it:"
    echo "  mopc --version"
    echo "  mopc --help"
    echo ""
fi
