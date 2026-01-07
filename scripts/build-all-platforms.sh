#!/bin/bash
# Cross-compile mopc for all supported platforms
# This ensures marketplace users don't need Zig installed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo "=== Building mopc for all platforms ==="
echo ""

# Detect Zig binary
ZIG="${ZIG:-zig}"
if [ -f "/root/.local/zig/zig" ]; then
    ZIG="/root/.local/zig/zig"
fi

# Build for each platform
build_target() {
    local target=$1
    local platform=$2
    local ext=$3

    echo "Building for $platform ($target)..."

    # Create output directory
    mkdir -p "zig-out/bin/$platform"

    # Build
    $ZIG build -Dtarget="$target" -Doptimize=ReleaseSafe

    # Move binary to platform-specific directory
    mv "zig-out/bin/mopc$ext" "zig-out/bin/$platform/mopc$ext"

    echo "✓ Built zig-out/bin/$platform/mopc$ext"
    echo ""
}

# Linux x86_64
build_target "x86_64-linux" "linux-x64" ""

# Linux ARM64
build_target "aarch64-linux" "linux-arm64" ""

# macOS x86_64 (Intel)
build_target "x86_64-macos" "darwin-x64" ""

# macOS ARM64 (Apple Silicon)
build_target "aarch64-macos" "darwin-arm64" ""

# Windows x86_64
build_target "x86_64-windows" "windows-x64" ".exe"

echo "=== All platforms built successfully ==="
echo ""
echo "Platform binaries:"
find zig-out/bin -type f -name "mopc*" | sort
