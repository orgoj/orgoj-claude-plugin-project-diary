#!/bin/bash
# Development installation script
# Builds mopc and creates symlink for immediate use

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo "🔨 Building mopc..."

# Detect Zig binary
ZIG="${ZIG:-zig}"
if [ -f "/root/.local/zig/zig" ]; then
    ZIG="/root/.local/zig/zig"
fi

# Build with release-safe optimization (faster than debug, smaller than release-fast)
$ZIG build -Doptimize=ReleaseSafe

# Detect platform for extension
EXT=""
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    EXT=".exe"
fi

SOURCE_BIN="$PROJECT_ROOT/zig-out/bin/mopc$EXT"
TARGET_BIN="$PROJECT_ROOT/hooks/mopc$EXT"

if [ ! -f "$SOURCE_BIN" ]; then
    echo "❌ Build failed - binary not found: $SOURCE_BIN"
    exit 1
fi

echo "✅ Built: $SOURCE_BIN"
echo ""

# Remove old symlink if exists
if [ -e "$TARGET_BIN" ] || [ -L "$TARGET_BIN" ]; then
    rm -f "$TARGET_BIN"
fi

# Create symlink
echo "🔗 Creating symlink..."
ln -sf "$SOURCE_BIN" "$TARGET_BIN"
chmod +x "$TARGET_BIN"

echo "✅ Installed: hooks/mopc -> zig-out/bin/mopc$EXT"
echo ""
echo "🎉 Dev installation complete!"
echo ""
echo "You can now:"
echo "  - Run hooks directly: hooks/mopc hook session-start"
echo "  - Use the wrapper: bin/claude-diary"
echo "  - Run any command: zig-out/bin/mopc --version"
echo ""
echo "Note: SessionStart hook will automatically use this dev build."
