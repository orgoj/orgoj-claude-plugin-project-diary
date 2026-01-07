# Development Guide

## Prerequisites

- **Zig 0.13.0+** (tested with 0.13.0, should work with 0.15.x)
- **Node.js** (for hooks and install scripts)

## Quick Start

```bash
# Clone the repo
git clone <repo-url>
cd orgoj-claude-plugin-project-diary

# Build for current platform
zig build -Doptimize=ReleaseSafe

# Install symlinks (hooks/mopc and bin/mopc)
./scripts/install-dev.sh

# Test
bin/mopc --version
```

## Development Workflow

### Fast Iteration (Current Platform Only)

```bash
# Build
zig build

# Or build + install symlinks
./scripts/install-dev.sh

# Test directly
zig-out/bin/mopc --version
hooks/mopc --version
bin/mopc --version
```

### Full Build (All Platforms)

For marketplace distribution:

```bash
# Build all platforms
./scripts/build-all-platforms.sh

# Binaries created at:
ls zig-out/bin/*/mopc*
```

## Project Structure

```
.
├── src/
│   ├── main.zig                # Entry point - command dispatcher
│   ├── commands/
│   │   ├── wrapper.zig         # mopc wrapper - session management
│   │   ├── hook.zig            # Hook handler (SessionStart, PreCompact, etc)
│   │   ├── tracker.zig         # Time tracker (stop, prompt)
│   │   └── recovery.zig        # Native JSONL parser
│   └── shared/
│       ├── config.zig          # Config cascade system
│       └── paths.zig           # Path utilities
│
├── hooks/
│   ├── hooks.json              # Hook definitions
│   ├── session-start.js        # Platform detection + symlink creation
│   ├── mopc                    # Symlink (created by SessionStart)
│   └── diary-hook.sh           # (legacy, removed)
│
├── bin/
│   └── mopc                    # Symlink (created by SessionStart)
│
├── zig-out/bin/
│   ├── mopc                    # Dev build (current platform)
│   ├── linux-x64/mopc          # Marketplace
│   ├── linux-arm64/mopc        # Marketplace
│   ├── darwin-x64/mopc         # Marketplace
│   ├── darwin-arm64/mopc       # Marketplace
│   └── windows-x64/mopc.exe    # Marketplace
│
├── scripts/
│   ├── build-all-platforms.sh  # Cross-compile for all platforms
│   ├── install-dev.sh          # Dev build + symlinks
│   └── install.sh              # User installation (add to PATH)
│
├── commands/                   # Claude Code skills
│   ├── diary.md                # /diary command
│   ├── diary-config.md         # /diary-config command
│   └── reflect.md              # /reflect command
│
└── tests/
    └── run-tests.sh            # Integration tests
```

## Build System

### build.zig

Single executable with all commands:
- Output: `zig-out/bin/mopc` (current platform)
- Subcommands: wrapper, hook, tracker, recovery, test-config

### Cross-Compilation

The `build-all-platforms.sh` script builds for:
- `x86_64-linux` → `zig-out/bin/linux-x64/mopc`
- `aarch64-linux` → `zig-out/bin/linux-arm64/mopc`
- `x86_64-macos` → `zig-out/bin/darwin-x64/mopc`
- `aarch64-macos` → `zig-out/bin/darwin-arm64/mopc`
- `x86_64-windows` → `zig-out/bin/windows-x64/mopc.exe`

## How Hooks Work

### SessionStart (hooks/session-start.js)

1. Detects platform (process.platform, process.arch)
2. Finds binary:
   - Prefers `zig-out/bin/mopc` (dev build)
   - Falls back to `zig-out/bin/{platform}/mopc` (marketplace)
3. Creates symlinks:
   - `hooks/mopc` → binary (for hooks)
   - `bin/mopc` → binary (for users)
4. Calls `mopc hook session-start`

### Other Hooks

All other hooks call `hooks/mopc` directly:
- PreCompact: `hooks/mopc hook --project-dir $PWD pre-compact`
- SessionEnd: `hooks/mopc hook --project-dir $PWD session-end`
- Stop: `hooks/mopc tracker --project-dir $PWD stop`
- UserPromptSubmit: `hooks/mopc tracker --project-dir $PWD prompt`

## Testing

### Unit Tests

```bash
zig build test
```

### Integration Tests

```bash
./tests/run-tests.sh
```

Tests cover:
- Config cascade (home → parent dirs → project)
- Recovery generation
- Hook execution
- Tracker (stop, prompt, idle detection)

### Manual Testing

```bash
# Test hook
echo '{"session_id":"test","cwd":"/tmp"}' | hooks/mopc hook --project-dir /tmp session-start

# Test tracker
echo '{"session_id":"test"}' | hooks/mopc tracker --project-dir /tmp stop

# Test config
mopc test-config /tmp

# Test wrapper (dry run)
mopc wrapper -- --help
```

## Config System

Configs are loaded with cascade:
1. `~/.config/mopc/config.json` (home)
2. `../.mopc-config.json` (parent directories, walking up)
3. `.claude/diary/.config.json` (project)

Later configs override earlier ones (field-by-field merge).

```bash
# Test config cascade
mopc test-config /path/to/project
```

## Git Workflow

### Development Branch

All work on feature branches starting with `claude/`:

```bash
git checkout -b claude/feature-name-XXXXX
# ... make changes ...
git commit -m "feat: add feature"
git push -u origin claude/feature-name-XXXXX
```

### Committing

Follow conventional commits:
- `feat:` - New features
- `fix:` - Bug fixes
- `refactor:` - Code refactoring
- `chore:` - Build/tooling changes

### What to Commit

**DO commit:**
- Source code (`src/`)
- Platform binaries (`zig-out/bin/{platform}/mopc*`)
- Scripts (`scripts/`, `hooks/`)
- Tests (`tests/`)
- Documentation

**DO NOT commit:**
- Dev build (`zig-out/bin/mopc`)
- Symlinks (`hooks/mopc`, `bin/mopc`)
- Test artifacts (`/tmp/mopc-test-*`)
- Zig cache (`.zig-cache/`, `zig-cache/`)

## Marketplace Distribution

### Before Release

1. Remove dev build:
   ```bash
   rm zig-out/bin/mopc
   ```

2. Build all platforms:
   ```bash
   ./scripts/build-all-platforms.sh
   ```

3. Verify binaries:
   ```bash
   ls -lh zig-out/bin/*/mopc*
   ```

4. Commit marketplace binaries:
   ```bash
   git add zig-out/bin/*/mopc*
   git commit -m "chore: update marketplace binaries"
   ```

### Plugin Installation (User Side)

When user installs from marketplace:
1. Plugin downloaded to `~/.claude/plugins/project-diary/`
2. User runs `./scripts/install.sh`
3. Adds plugin `bin/` to PATH
4. First Claude session runs SessionStart hook
5. SessionStart creates `bin/mopc` symlink for their platform
6. User can now run `mopc` anywhere

## Troubleshooting

### "mopc binary not found"

```bash
# Build first
zig build

# Or for all platforms
./scripts/build-all-platforms.sh
```

### "Symlink not created"

```bash
# Run SessionStart manually
echo '{"session_id":"test","cwd":"'$(pwd)'"}' | node hooks/session-start.js --project-dir $(pwd)

# Check created symlinks
ls -la hooks/mopc bin/mopc
```

### "Command not found: mopc"

```bash
# Add to PATH
export PATH="/path/to/plugin/bin:$PATH"

# Or install
./scripts/install.sh
```

### Zig Version Mismatch

The project targets Zig 0.13.0+ but should work with 0.15.x. If you encounter build errors:

1. Check Zig version:
   ```bash
   zig version
   ```

2. Update Zig if needed:
   ```bash
   # Download from https://ziglang.org/download/
   ```

3. Report compatibility issues on GitHub

## IDE Setup

### VSCode

Install Zig Language Server extension:
- Extension: `ziglang.vscode-zig`
- Auto-completion, go-to-definition, etc.

### Zed

Zig support built-in, works out of the box.

## Contributing

1. Fork the repo
2. Create feature branch: `git checkout -b claude/feature-name-XXXXX`
3. Make changes
4. Run tests: `./tests/run-tests.sh`
5. Commit: `git commit -m "feat: add feature"`
6. Push: `git push -u origin claude/feature-name-XXXXX`
7. Open PR

## Resources

- [Zig Documentation](https://ziglang.org/documentation/master/)
- [Claude Code Plugin Docs](https://code.claude.com/docs/plugins)
- [Project Issues](https://github.com/orgoj/orgoj-claude-plugin-project-diary/issues)
