#!/bin/bash
# Installation script for mopc
# Adds plugin bin/ directory to PATH

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_DIR="$PROJECT_ROOT/bin"

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

# Check if platform binary exists
PLATFORM_BIN="$PROJECT_ROOT/zig-out/bin/$PLATFORM/mopc$EXT"
DEV_BIN="$PROJECT_ROOT/zig-out/bin/mopc$EXT"

if [ ! -f "$PLATFORM_BIN" ] && [ ! -f "$DEV_BIN" ]; then
    echo "❌ No binary found for $PLATFORM"
    echo "   Run: ./scripts/build-all-platforms.sh"
    exit 1
fi

# Run SessionStart to create bin/mopc symlink
echo "🔗 Creating bin/mopc symlink..."
echo '{"session_id":"install","cwd":"'$(pwd)'"}' | node "$PROJECT_ROOT/hooks/session-start.js" --project-dir "$PROJECT_ROOT" > /dev/null 2>&1

if [ ! -f "$BIN_DIR/mopc$EXT" ]; then
    echo "❌ Failed to create bin/mopc"
    exit 1
fi

echo "✅ Created: bin/mopc$EXT"
echo ""

# Check if bin/ is in PATH
if [[ ":$PATH:" == *":$BIN_DIR:"* ]]; then
    echo "🎉 Installation complete!"
    echo ""
    echo "Try it:"
    echo "  mopc --version"
    echo ""
else
    echo "⚠️  Add plugin bin/ directory to your PATH"
    echo ""
    echo "Add this to your ~/.bashrc or ~/.zshrc:"
    echo "  export PATH=\"$BIN_DIR:\$PATH\""
    echo ""
    echo "Then reload your shell:"
    echo "  source ~/.bashrc  # or ~/.zshrc"
    echo ""
    echo "Or run commands directly:"
    echo "  $BIN_DIR/mopc --version"
    echo ""
fi
